"""
SAST Scanner — Compliance Evidence Vault (Milestone 2 / Integration)
Ankita Das | CS6620

Environment variables (baked into task definition via Terraform):
  DB_HOST, DB_NAME, DB_USER, DB_SSLMODE, REPORT_BUCKET

Environment variables (injected at runtime by Ishit's Step Functions):
  JOB_ID   — UUID of the job row in RDS
  S3_KEY   — e.g. uploads/{job_id}/source.zip  (matches state_machine.json)

Environment variables (injected at runtime, stored in SSM):
  DB_PASSWORD — never baked in, always runtime override

Schema alignment (Shubham's schema.sql):
  findings columns: id, job_id, severity, vuln_type, detail
  jobs.error_msg   (NOT error_message)
  jobs.s3_key      updated to report path on completion
"""

import os
import re
import json
import uuid
import hashlib
import zipfile
import tempfile
import logging
import boto3
import psycopg2
from datetime import datetime, timezone
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# 11 vulnerability patterns
# ---------------------------------------------------------------------------
VULN_PATTERNS = {
    "SQL_INJECTION": {
        "severity": "HIGH",
        "patterns": [
            r'execute\s*\(\s*["\'].*?\%',
            r'cursor\.execute\s*\(\s*f["\']',
            r'SELECT.*\+.*request\.',
            r'query\s*=\s*["\'].*\+',
        ],
        "description": "Potential SQL injection via unsanitised input in query construction",
    },
    "HARDCODED_SECRET": {
        "severity": "HIGH",
        "patterns": [
            r'(?i)(password|passwd|pwd)\s*=\s*["\'][^"\']{4,}["\']',
            r'(?i)(api_key|apikey|secret_key|auth_token)\s*=\s*["\'][^"\']{8,}["\']',
            r'(?i)aws_secret_access_key\s*=\s*["\'][^"\']+["\']',
            r'(?i)private_key\s*=\s*["\']-----BEGIN',
        ],
        "description": "Hardcoded credential or secret detected in source code",
    },
    "COMMAND_INJECTION": {
        "severity": "HIGH",
        "patterns": [
            r'os\.system\s*\(',
            r'subprocess\.(call|run|Popen)\s*\(.*shell\s*=\s*True',
            r'eval\s*\(\s*request\.',
            r'exec\s*\(\s*request\.',
        ],
        "description": "Potential OS command injection via unsanitised input",
    },
    "XSS": {
        "severity": "MEDIUM",
        "patterns": [
            r'innerHTML\s*=\s*(?!`[^$])',
            r'document\.write\s*\(',
            r'dangerouslySetInnerHTML',
            r'render_template_string\s*\(.*request\.',
        ],
        "description": "Potential Cross-Site Scripting (XSS) vulnerability",
    },
    "INSECURE_DESERIALIZATION": {
        "severity": "HIGH",
        "patterns": [
            r'pickle\.loads\s*\(',
            r'yaml\.load\s*\([^,)]*\)',
            r'marshal\.loads\s*\(',
            r'jsonpickle\.decode\s*\(',
        ],
        "description": "Insecure deserialization — arbitrary object instantiation possible",
    },
    "PATH_TRAVERSAL": {
        "severity": "MEDIUM",
        "patterns": [
            r'open\s*\(\s*request\.',
            r'open\s*\(.*\+.*request\.',
            r'os\.path\.join\s*\(.*request\.',
            r'send_file\s*\(.*request\.',
        ],
        "description": "Potential path traversal — user input used in file path construction",
    },
    "WEAK_CRYPTO": {
        "severity": "MEDIUM",
        "patterns": [
            r'hashlib\.md5\s*\(',
            r'hashlib\.sha1\s*\(',
            r'DES\s*\(',
            r'Cipher\.new\s*\(.*MODE_ECB',
        ],
        "description": "Weak or deprecated cryptographic algorithm detected",
    },
    "INSECURE_RANDOM": {
        "severity": "LOW",
        "patterns": [
            r'random\.random\s*\(',
            r'random\.randint\s*\(',
            r'Math\.random\s*\(',
        ],
        "description": "Non-cryptographic RNG used for security-sensitive value",
    },
    "OPEN_REDIRECT": {
        "severity": "MEDIUM",
        "patterns": [
            r'redirect\s*\(\s*request\.',
            r'HttpResponseRedirect\s*\(\s*request\.',
            r'res\.redirect\s*\(\s*req\.',
        ],
        "description": "Potential open redirect — redirect target derived from user input",
    },
    "SSRF": {
        "severity": "HIGH",
        "patterns": [
            r'requests\.get\s*\(\s*request\.',
            r'urllib\.request\.urlopen\s*\(\s*request\.',
            r'fetch\s*\(\s*req\.',
            r'axios\.(get|post)\s*\(\s*req\.',
        ],
        "description": "Potential SSRF — URL derived from user input",
    },
    "DEBUG_ENABLED": {
        "severity": "LOW",
        "patterns": [
            r'DEBUG\s*=\s*True',
            r'app\.run\s*\(.*debug\s*=\s*True',
            r'app\.config\[.DEBUG.\]\s*=\s*True',
        ],
        "description": "Debug mode enabled in production code",
    },
}

SCANNABLE_EXTENSIONS = {
    ".py", ".js", ".ts", ".jsx", ".tsx", ".java", ".go",
    ".rb", ".php", ".cs", ".cpp", ".c", ".h", ".sh",
    ".yaml", ".yml", ".env",
}


def scan_file(filepath: Path, relative_path: str) -> list[dict]:
    findings = []
    try:
        lines = filepath.read_text(errors="replace").splitlines()
    except Exception as e:
        log.warning(f"Could not read {relative_path}: {e}")
        return findings
    for vuln_type, meta in VULN_PATTERNS.items():
        for pattern in meta["patterns"]:
            for line_num, line in enumerate(lines, start=1):
                if re.search(pattern, line):
                    findings.append({
                        "id":        str(uuid.uuid4()),
                        "vuln_type": vuln_type,
                        "severity":  meta["severity"],
                        # Fold file/line into detail — schema has no separate columns
                        "detail":    f"{meta['description']} [{relative_path}:{line_num}]",
                    })
    return findings


def scan_zip(zip_path: str) -> list[dict]:
    all_findings = []
    with tempfile.TemporaryDirectory() as tmpdir:
        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(tmpdir)
        root = Path(tmpdir)
        for fpath in root.rglob("*"):
            if fpath.is_file() and fpath.suffix.lower() in SCANNABLE_EXTENSIONS:
                rel = str(fpath.relative_to(root))
                found = scan_file(fpath, rel)
                all_findings.extend(found)
                if found:
                    log.info(f"  {rel}: {len(found)} finding(s)")
    return all_findings


# ---------------------------------------------------------------------------
# AWS helpers
# ---------------------------------------------------------------------------

def download_from_s3(bucket: str, s3_key: str, dest: str) -> None:
    """Download source zip directly from S3 using S3_KEY (not a presigned URL)."""
    log.info(f"Downloading s3://{bucket}/{s3_key} ...")
    boto3.client("s3").download_file(bucket, s3_key, dest)
    log.info(f"Downloaded {Path(dest).stat().st_size:,} bytes")


def upload_report(report: dict, bucket: str, key: str) -> str:
    payload = json.dumps(report, indent=2, default=str).encode()
    digest  = hashlib.sha256(payload).hexdigest()
    boto3.client("s3").put_object(
        Bucket=bucket, Key=key, Body=payload,
        ContentType="application/json",
        Metadata={"sha256": digest},
    )
    log.info(f"Report → s3://{bucket}/{key}  sha256={digest[:16]}…")
    return digest


def get_db():
    return psycopg2.connect(
        host            = os.environ["DB_HOST"],
        port            = int(os.environ.get("DB_PORT", 5432)),
        dbname          = os.environ["DB_NAME"],
        user            = os.environ["DB_USER"],
        password        = os.environ["DB_PASSWORD"],
        connect_timeout = 10,
        sslmode         = os.environ.get("DB_SSLMODE", "require"),
    )


def write_to_rds(job_id: str, findings: list[dict], report_key: str) -> None:
    """
    Uses exact column names from Shubham's schema.sql:
      findings: id, job_id, severity, vuln_type, detail
      jobs:     s3_key  (updated to report path so GET /jobs/{id} can surface it)
    Does NOT set status=COMPLETED — Step Functions MarkJobCompleted does that.
    """
    conn = get_db()
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE jobs SET s3_key=%s WHERE id=%s",
                    (report_key, job_id),
                )
                for f in findings:
                    cur.execute(
                        """INSERT INTO findings (id, job_id, severity, vuln_type, detail)
                           VALUES (%s, %s, %s, %s, %s)""",
                        (f["id"], job_id, f["severity"], f["vuln_type"], f["detail"]),
                    )
    finally:
        conn.close()
    log.info(f"Wrote {len(findings)} findings to RDS")


def mark_failed(job_id: str, error: str) -> None:
    """Safety-net direct DB write. error_msg matches schema.sql column name."""
    try:
        conn = get_db()
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE jobs SET status='FAILED', error_msg=%s WHERE id=%s",
                    (error[:500], job_id),
                )
        conn.close()
    except Exception as e:
        log.error(f"Could not mark FAILED: {e}")


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

def main():
    job_id        = os.environ["JOB_ID"]
    s3_key        = os.environ["S3_KEY"]       # passed by Ishit's state_machine.json
    report_bucket = os.environ["REPORT_BUCKET"]
    report_key    = f"reports/sast/{job_id}/report.json"

    log.info(f"=== SAST | job={job_id} | s3_key={s3_key} ===")
    try:
        with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
            zip_path = tmp.name

        download_from_s3(report_bucket, s3_key, zip_path)

        findings = scan_zip(zip_path)
        log.info(f"Scan done — {len(findings)} findings")

        sev = {"HIGH": 0, "MEDIUM": 0, "LOW": 0}
        for f in findings:
            sev[f["severity"]] += 1

        report = {
            "job_id": job_id, "scan_type": "SAST",
            "scanned_at": datetime.now(timezone.utc).isoformat(),
            "total_findings": len(findings),
            "severity_summary": sev,
            "findings": findings,
        }

        upload_report(report, report_bucket, report_key)
        write_to_rds(job_id, findings, report_key)

        # Exit 0 — Step Functions detects success and calls MarkJobCompleted Lambda
        log.info("=== SAST done — exit 0 ===")

    except Exception as e:
        log.error(f"Fatal: {e}", exc_info=True)
        mark_failed(job_id, str(e))
        raise  # non-zero exit → Step Functions Catch → MarkJobFailed Lambda


if __name__ == "__main__":
    main()