# Compliance Evidence Vault

> A tamper-proof, automated security scanning platform with SHA-256 hashed evidence storage, long-term Glacier archival, and WORM audit trails — built for CS6620 Fundamentals of Cloud Computing (Spring 2026) at Northeastern University.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [AWS Services](#aws-services)
- [Project Structure](#project-structure)
- [Data Flow](#data-flow)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [GitHub Secrets](#github-secrets)
- [Environment Variables](#environment-variables)
- [Database Schema](#database-schema)
- [S3 Bucket Structure](#s3-bucket-structure)
- [Retention Policy](#retention-policy)
- [API Reference](#api-reference)
- [Local Testing](#local-testing)
- [Contributors](#contributors)

---

## Overview

The Compliance Evidence Vault is a cloud-native security platform that runs SAST (Static Application Security Testing) and API Penetration Testing scans on demand, and stores the results as tamper-evident compliance evidence. It is designed for regulated organizations that need demonstrable, auditable records of security testing for SOC2, HIPAA, and PCI-DSS certification.

**What it does:**

- Accepts scan requests through a browser dashboard
- Queues jobs asynchronously via SQS and dispatches them through AWS Step Functions
- Runs SAST and Pentest scanners in isolated ECS Fargate containers in a private VPC subnet
- SHA-256 hashes every report immediately on scan completion
- Stores full JSON scan reports in S3 with lifecycle-based Glacier archival
- Records scan metadata and findings in RDS PostgreSQL for fast dashboard queries
- Logs every AWS API call via CloudTrail in a WORM-locked S3 bucket
- Enforces least-privilege access with LabRole IAM on every service boundary
- Monitors the pipeline with 4 CloudWatch alarms routed to SNS email alerts

**Scanners:**

| Scanner | Type | What it detects |
|---------|------|-----------------|
| SAST | Static (zip upload) | 11 vulnerability patterns: SQL injection, hardcoded secrets, command injection, XSS, insecure deserialization, path traversal, weak crypto (MD5/SHA1), insecure random, open redirect, SSRF, debug mode enabled |
| Pentest | Dynamic (live URL) | 6 probe categories: missing security headers, TLS configuration, sensitive path exposure (/.env, /.git), dangerous HTTP methods (TRACE/PUT/DELETE), cookie flag absence, injection surfaces |

---

## Architecture

```
User (Browser)
     │  HTTPS
     ▼
API Gateway ── API key auth + throttling
     │
     ▼
Lambda — cev-api-handler                    ──► RDS PostgreSQL (INSERT job PENDING)
     │   returns job_id + presigned URL in <1s       compliancevault db
     │
     ├──► S3 presigned PUT URL ◄── Browser uploads zip directly
     │        cev-reports-{account_id}/uploads/{job_id}/source.zip
     │
     └──► SQS ── cev-scan-queue (15-min visibility, DLQ after 3 failures)
                  │
                  ▼
           Lambda — cev-orchestrator (SQS event source mapping)
                  │
                  ▼
           Step Functions — cev-scan-orchestrator
                  │
                  ├── RouteByType (Choice)
                  │       │
                  │       ├── SAST ──► WaitForUpload (30s) ──► RunSASTScanner
                  │       └── PENTEST ──────────────────────► RunPentestScanner
                  │
                  │   [Both scanners: ECS Fargate, private subnet, 3× retry with backoff]
                  │       │
                  │       ├── ResultPath: $.ecs_result (preserves $.job_id)
                  │       │
                  │       ├── Success ──► MarkJobCompleted (Lambda: cev-status-updater)
                  │       └── Failure ──► MarkJobFailed   (Lambda: cev-status-updater)
                  │
                  ▼
           ECS Fargate — private subnet, no public IP
                  │
           ┌──────┴──────┐
           ▼             ▼
    SAST Scanner    Pentest Scanner
    (Python 3.11)   (Python 3.11)
           │             │
           └──────┬──────┘
                  │
        ┌─────────┴──────────┐
        ▼                    ▼
 S3 — cev-reports        RDS PostgreSQL
 reports/{type}/{id}/    findings table
 report.json             (severity, vuln_type, detail)
        │
  SHA-256 hash
  in report body
        │
  Lifecycle: Standard ──(90 days)──► Glacier ──(7 years)──► Expire

CloudTrail ── WORM COMPLIANCE mode, 7-year retention ──► S3 cloudtrail logs
CloudWatch ── 4 alarms: SQS depth, Lambda errors, Fargate CPU >85%, DLQ depth >0
SNS ── routes all alarms to team email
```

**Changes from Milestone 1 proposal (based on professor feedback):**

| Feedback item | What we added |
|---|---|
| Use IaC for repeatable infrastructure | Full Terraform for all 39 resources across 3 modules |
| Add async processing with queues | SQS buffer between Lambda and Step Functions |
| Add retry mechanism for scan failures | Step Functions 3× exponential backoff (30s → 60s → 120s) |
| Add DLQ for failure capture | SQS Dead-Letter Queue + CloudWatch alarm on DLQ depth |
| RDS in private subnet | VPC private subnet, RDS SG allows only Lambda and Fargate SGs |
| Add CloudWatch monitoring | 4 alarms: SQS, Lambda, Fargate CPU, DLQ |
| Secure VPC design | Public subnet: API Gateway. Private subnet: Lambda, Fargate, RDS |
| CloudTrail for audit | COMPLIANCE mode Object Lock, 7-year retention |

---

## AWS Services

| Service | Role | Why we chose it |
|---------|------|-----------------|
| **API Gateway** | HTTPS REST entry point | Decouples browser from Lambda; provides API key auth, throttling, request validation; no EC2 to manage |
| **Lambda (cev-api-handler)** | Job creation + presigned URL | Returns job_id in <1s; stateless; no idle cost |
| **Lambda (cev-orchestrator)** | SQS → Step Functions bridge | Reads SQS batch, starts one Step Functions execution per job, returns batchItemFailures for partial retry |
| **Lambda (cev-status-updater)** | Job status updates | Called by Step Functions on completion or failure; clears error_msg on COMPLETED |
| **SQS (cev-scan-queue)** | Async job buffer | 15-min visibility timeout; decouples API response from scanner execution; DLQ after 3 failures |
| **Step Functions** | Scan orchestration | Routes SAST vs Pentest; WaitForUpload state for browser upload timing; 3× retry with exponential backoff; explicit FAILED branch |
| **ECS Fargate (SAST)** | Static code scanner | One-shot container; zero idle cost; no public IP; private subnet; 512 CPU / 1024 MB |
| **ECS Fargate (Pentest)** | Dynamic HTTP scanner | One-shot container; zero idle cost; no public IP; private subnet; 256 CPU / 512 MB |
| **ECR** | Container image registry | Stores SAST and Pentest images with scan_on_push; deployed via GitHub Actions |
| **RDS PostgreSQL** | Scan metadata + findings | ACID guarantees; jobs and findings tables; private subnet; accessible only from Lambda and Fargate SGs |
| **S3 (cev-reports-{account})** | Report storage + uploads | Receives SHA-256 hashed JSON reports; lifecycle to Glacier at 90 days; CORS configured for browser uploads |
| **CloudWatch** | Pipeline monitoring | 4 alarms; log groups for all Lambda and ECS components; 30-day retention |
| **CloudTrail** | Immutable audit log | Every AWS API call logged; COMPLIANCE mode Object Lock; 7-year retention; log file validation enabled |
| **SNS** | Alert notifications | Routes CloudWatch alarms to team email address |
| **VPC** | Network isolation | Public subnet: API Gateway. Private subnets A+B: Lambda, Fargate, RDS. NAT Gateway for outbound. S3 VPC Gateway endpoint |
| **SSM Parameter Store** | Secret management | DB_PASSWORD stored as SecureString at /cev/db_password; passed to Step Functions container overrides |

---

## Project Structure

```
compliance-evidence-vault/
├── compute/
│   ├── sast-scanner/
│   │   ├── Dockerfile
│   │   ├── requirements.txt          # boto3, psycopg2-binary, requests
│   │   └── scanner.py                # 11-pattern SAST engine + RDS writer + S3 report upload
│   ├── pentest-scanner/
│   │   ├── Dockerfile
│   │   ├── requirements.txt          # boto3, psycopg2-binary, requests
│   │   └── scanner.py                # 6-category HTTP prober + RDS writer + S3 report upload
│   ├── terraform/
│   │   └── main.tf                   # ECR repos, ECS cluster, task definitions, CW log groups, S3 lifecycle
│   └── local-test/
│       ├── local_test_runner.py      # Mock-based test runner (no Docker/AWS needed)
│       ├── sample_vulnerable_app.py  # SAST test target (10+ findings)
│       └── docker-compose.yml        # Local postgres + localstack + vulnerable Flask app
│
├── api/
│   ├── lambda/
│   │   ├── handler.py                # cev-api-handler: job creation, presigned URL, SQS enqueue
│   │   ├── status_updater.py         # cev-status-updater: job status updates, schema migration
│   │   └── requirements.txt
│   ├── terraform/
│   │   ├── main.tf                   # API Gateway, Lambda functions, RDS, S3 bucket
│   │   ├── variables.tf              # All values from GitHub Secrets via tfvars
│   │   ├── lambda.tf                 # Lambda functions + VPC config
│   │   ├── rds.tf                    # RDS instance + subnet group
│   │   ├── s3.tf                     # Reports bucket + CORS + lifecycle
│   │   ├── api_gateway.tf            # REST API + routes + usage plan
│   │   └── outputs.tf                # rds_endpoint, api_url, s3_bucket_name, etc.
│   ├── schema.sql                    # Shared source of truth — jobs + findings tables
│   └── frontend/
│       └── dashboard.html            # Single-page dashboard (polling, severity table, job detail)
│
├── infra/
│   ├── terraform/
│   │   ├── main.tf                   # VPC, subnets, SQS, Step Functions, CloudWatch, CloudTrail
│   │   ├── variables.tf
│   │   └── outputs.tf                # vpc_id, subnet IDs, SG IDs, SQS URL/ARN, state_machine_arn
│   └── step_functions/
│       └── state_machine.json        # Step Functions definition with WaitForUpload + ResultPath
│
├── .github/
│   └── workflows/
│       └── deploy.yml                # Unified CI/CD: build Lambda zip → API terraform → schema → compute terraform → Docker push
│
└── README.md
```

---

## Data Flow

End-to-end flow for a SAST scan:

1. **User opens dashboard** at `http://localhost:8080/dashboard.html` (served locally via `python -m http.server 8080`)
2. **Selects SAST**, picks a `.zip` file, clicks Submit Job
3. **Dashboard POSTs to API Gateway** → Lambda `cev-api-handler` creates a job row in RDS (`status=PENDING`), returns `job_id` + presigned S3 PUT URL in <1 second
4. **Browser uploads zip** directly to `s3://cev-reports-{account}/uploads/{job_id}/source.zip` via the presigned URL (no API Gateway involved)
5. **Lambda enqueues message** to SQS with `{ job_id, scan_type, s3_key }`
6. **Lambda `cev-orchestrator`** receives SQS trigger, starts a Step Functions execution
7. **Step Functions routes**: SAST → `WaitForUpload` (30 seconds) → `RunSASTScanner`
8. **Fargate task launches** in private subnet; environment overrides inject `JOB_ID`, `S3_KEY`, `DB_PASSWORD`
9. **SAST scanner runs**: downloads zip from S3, runs 11 regex patterns, SHA-256 hashes report, writes findings to RDS `findings` table, uploads `report.json` to `s3://cev-reports-{account}/reports/sast/{job_id}/report.json`
10. **Step Functions calls `MarkJobCompleted`** → Lambda `cev-status-updater` sets `status=COMPLETED`, clears `error_msg`
11. **Dashboard auto-refreshes** every 10 seconds, shows COMPLETED badge; user clicks job to see severity breakdown

For PENTEST: skip the file upload step; submit `target_url` in the POST body; Step Functions routes directly to `RunPentestScanner` with no wait.

---

## Prerequisites

- Python 3.11+
- Docker and Docker Compose
- Node.js 18+ (for local dashboard serving)
- Terraform 1.7+
- AWS CLI configured with AWS Academy Learner Lab credentials
- GitHub repository with Actions enabled

---

## Deployment

Deployment is fully automated via GitHub Actions. The single workflow `deploy.yml` runs all steps in order.

### One-time setup

**1. Deploy Ishit's base infrastructure (Phase 1) — run once**

Go to GitHub → Actions → "Phase 1 — Deploy VPC and base infrastructure" → Run workflow.

This creates the VPC, subnets, SQS queue, Step Functions state machine, and security groups. Copy the output values into GitHub Secrets (see [GitHub Secrets](#github-secrets)).

**2. Run the full deployment workflow**

Go to GitHub → Actions → "Full deployment — all infrastructure in one account" → Run workflow.

This runs 6 steps automatically:

```
Step 1: Build lambda_function.zip from handler.py + status_updater.py + dependencies
Step 2: api/terraform  → RDS, S3, API Gateway, Lambda (imports existing resources first)
Step 3a: Apply schema.sql via cev-status-updater Lambda
Step 3b: Store DB_PASSWORD in SSM at /cev/db_password
Step 4: compute/terraform → ECR repos, ECS cluster, Fargate task definitions
Step 5: Build and push Docker images to ECR
Step 6: Print deployment summary (API URL, RDS endpoint, task definition ARNs)
```

**3. Update Step Functions with real task definition ARNs**

After Step 6, copy the SAST and Pentest task definition ARNs from the summary and run:

```bash
aws stepfunctions update-state-machine \
  --state-machine-arn "arn:aws:states:us-east-1:{account}:stateMachine:cev-scan-orchestrator" \
  --definition file://infra/step_functions/state_machine.json
```

**4. Enable the SQS event source mapping**

```bash
MAPPING_UUID=$(aws lambda list-event-source-mappings \
  --function-name cev-orchestrator \
  --query "EventSourceMappings[0].UUID" --output text)

aws lambda update-event-source-mapping \
  --uuid $MAPPING_UUID --enabled
```

**5. Configure S3 CORS for browser uploads**

```bash
aws s3api put-bucket-cors \
  --bucket cev-reports-{account_id} \
  --cors-configuration '{
    "CORSRules": [{
      "AllowedOrigins": ["*"],
      "AllowedMethods": ["GET","PUT","POST","DELETE","HEAD"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }]
  }'
```

### Credential refresh (AWS Academy)

AWS Academy session tokens expire every few hours. Before each deployment run, update these three GitHub Secrets with fresh values from AWS Academy → AWS Details → Show:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

---

## GitHub Secrets

All infrastructure values are stored as GitHub Secrets. No values are hardcoded in Terraform or workflow files.

| Secret | Description | Value source |
|--------|-------------|--------------|
| `AWS_ACCESS_KEY_ID` | AWS Academy session credential | AWS Academy → AWS Details |
| `AWS_SECRET_ACCESS_KEY` | AWS Academy session credential | AWS Academy → AWS Details |
| `AWS_SESSION_TOKEN` | AWS Academy session token | AWS Academy → AWS Details |
| `AWS_ACCOUNT_ID` | AWS account ID | `126573932591` |
| `DB_PASSWORD` | RDS master password |  |
| `VPC_ID` | VPC from Phase 1 | Phase 1 workflow output |
| `PRIVATE_SUBNET_A` | Private subnet A ID | Phase 1 workflow output |
| `PRIVATE_SUBNET_B` | Private subnet B ID | Phase 1 workflow output |
| `PUBLIC_SUBNET` | Public subnet ID | Phase 1 workflow output |
| `LAMBDA_SG_ID` | Lambda security group ID | Phase 1 workflow output |
| `RDS_SG_ID` | RDS security group ID | Phase 1 workflow output |
| `FARGATE_SG_ID` | Fargate security group ID | Phase 1 workflow output |
| `SQS_QUEUE_URL` | SQS queue URL | Phase 1 workflow output |
| `SQS_QUEUE_ARN` | SQS queue ARN | Phase 1 workflow output |
| `STATE_MACHINE_ARN` | Step Functions ARN | Phase 1 workflow output |

---

## Environment Variables

Environment variables are never hardcoded. They are injected at runtime by Terraform (into Lambda) and by Step Functions container overrides (into Fargate tasks).

### Lambda functions

| Variable | Lambda | Description |
|----------|--------|-------------|
| `DB_HOST` | both | RDS endpoint (set by Terraform from `aws_db_instance.cev_postgres.address`) |
| `DB_NAME` | both | `compliancevault` |
| `DB_USER` | both | `cevadmin` |
| `DB_PASSWORD` | both | From GitHub Secret `DB_PASSWORD` via Terraform tfvars |
| `S3_BUCKET` | cev-api-handler | Reports bucket name |
| `SQS_URL` | cev-api-handler | SQS queue URL |

### ECS Fargate tasks (injected by Step Functions at runtime)

| Variable | Scanner | Description |
|----------|---------|-------------|
| `REPORT_BUCKET` | both | S3 bucket for reports (baked into task definition) |
| `DB_HOST` | both | RDS endpoint (baked into task definition) |
| `DB_NAME` | both | `compliancevault` (baked into task definition) |
| `DB_USER` | both | `cevadmin` (baked into task definition) |
| `DB_SSLMODE` | both | `require` |
| `JOB_ID` | both | Injected per execution by Step Functions container override |
| `S3_KEY` | SAST | Injected per execution by Step Functions container override |
| `TARGET_URL` | Pentest | Injected per execution by Step Functions container override |
| `DB_PASSWORD` | both | Injected per execution by Step Functions container override (from SSM) |

---

## Database Schema

```sql
-- api/schema.sql
-- Shared source of truth between Shubham's Lambda and Ankita's scanners

CREATE TABLE IF NOT EXISTS jobs (
  id         UUID PRIMARY KEY,
  scan_type  TEXT NOT NULL CHECK (scan_type IN ('SAST', 'PENTEST')),
  status     TEXT NOT NULL DEFAULT 'PENDING'
               CHECK (status IN ('PENDING', 'RUNNING', 'COMPLETED', 'FAILED')),
  s3_key     TEXT,
  error_msg  TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS findings (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id     UUID NOT NULL REFERENCES jobs(id),
  severity   TEXT NOT NULL CHECK (severity IN ('HIGH', 'MEDIUM', 'LOW')),
  vuln_type  TEXT NOT NULL,
  detail     TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_findings_job_id ON findings (job_id);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs (created_at DESC);
```

Schema is applied on first deployment via the `cev-status-updater` Lambda's `run_schema` action. Re-running is safe — all statements use `IF NOT EXISTS`.

---

## S3 Bucket Structure

```
cev-reports-{account_id}/
├── uploads/
│   └── {job_id}/
│       └── source.zip          ← uploaded by browser via presigned URL; expires after 7 days
└── reports/
    ├── sast/
    │   └── {job_id}/
    │       └── report.json     ← SHA-256 hashed; written by SAST scanner
    └── pentest/
        └── {job_id}/
            └── report.json     ← SHA-256 hashed; written by Pentest scanner
```

**Bucket settings:** public access fully blocked, CORS configured for browser PUT uploads, versioning disabled (SHA-256 hash in report body provides integrity).

**Lifecycle rules:**

| Prefix | Transition | Action |
|--------|-----------|--------|
| `reports/` | 90 days | Transition to GLACIER |
| `reports/` | 2555 days (7 years) | Expire |
| `uploads/` | 7 days | Expire |

---

## Retention Policy

| Phase | Storage class | Duration | Who can access |
|-------|--------------|----------|----------------|
| Active | S3 Standard | 0–90 days | Lambda (write), Fargate (write), dashboard (read via API) |
| Archive | S3 Glacier | 90 days – 7 years | LabRole (restore request required) |
| Deletion | — | After 7 years | Automated by S3 lifecycle expiration |

This policy satisfies **SOC 2 Type II**, **HIPAA**, and **PCI-DSS** minimum retention requirements. CloudTrail WORM logs provide the immutable API access record that auditors require alongside the scan reports.

---

## API Reference

All endpoints require the `x-api-key` header. The API key is managed by API Gateway and can be retrieved via:

```bash
aws apigateway get-api-keys --include-values \
  --query "items[?contains(name,'cev')].value" --output text
```

---

### POST /jobs — Create a scan job

**SAST request:**
```json
{
  "scan_type": "SAST"
}
```

**SAST response** `201`:
```json
{
  "job_id": "9bc723f2-3795-4578-99a9-55e598176a73",
  "upload_url": "https://cev-reports-{account}.s3.amazonaws.com/uploads/{job_id}/source.zip?X-Amz-...",
  "s3_key": "uploads/9bc723f2-3795-4578-99a9-55e598176a73/source.zip",
  "status": "PENDING"
}
```

Upload your zip to `upload_url` via HTTP PUT immediately after receiving the response (URL expires in 1 hour).

**PENTEST request:**
```json
{
  "scan_type": "PENTEST",
  "target_url": "https://example.com"
}
```

**PENTEST response** `201`:
```json
{
  "job_id": "45644d23-9b09-4c73-a47f-ea626e31e7e9",
  "status": "PENDING",
  "s3_key": "uploads/45644d23-9b09-4c73-a47f-ea626e31e7e9/source.zip"
}
```

PENTEST jobs are queued immediately — no file upload required.

---

### GET /jobs/{id} — Get job status and findings

**Response** `200`:
```json
{
  "job_id": "9bc723f2-3795-4578-99a9-55e598176a73",
  "scan_type": "SAST",
  "status": "COMPLETED",
  "s3_key": "reports/sast/9bc723f2-3795-4578-99a9-55e598176a73/report.json",
  "error_msg": null,
  "created_at": "2026-06-15 22:08:56.968181+00:00",
  "updated_at": "2026-06-15 22:12:11.938896+00:00",
  "findings": [
    {
      "finding_id": "2fc504f4-7168-4d91-8bde-c24355766864",
      "severity": "HIGH",
      "vuln_type": "HARDCODED_SECRET",
      "detail": "Hardcoded credential or secret detected in source code [vuln.py:2]",
      "created_at": "2026-06-15 22:12:11.938896+00:00"
    },
    {
      "finding_id": "e0a3d98a-5a99-4693-b6a5-49d440e5ae4c",
      "severity": "HIGH",
      "vuln_type": "COMMAND_INJECTION",
      "detail": "Potential OS command injection via unsanitised input [vuln.py:3]",
      "created_at": "2026-06-15 22:12:11.938896+00:00"
    }
  ]
}
```

---

### GET /jobs — List all jobs

**Response** `200`:
```json
{
  "jobs": [
    {
      "job_id": "9bc723f2-3795-4578-99a9-55e598176a73",
      "scan_type": "SAST",
      "status": "COMPLETED",
      "created_at": "2026-06-15 22:08:56.968181+00:00",
      "updated_at": "2026-06-15 22:12:11.938896+00:00"
    }
  ]
}
```

---

## Local Testing

Test both scanners locally without Docker or AWS:

```bash
cd compute/local-test

# SAST — scans sample_vulnerable_app.py
python local_test_runner.py sast
# Expected: 10 findings (6 HIGH, 1 MEDIUM, 3 LOW)

# Pentest — offline mode with mock HTTP responses
python local_test_runner.py pentest --offline
# Expected: 29 findings across 6 probe categories

# Both
python local_test_runner.py all --offline
```

The test runner mocks boto3 and psycopg2 so no AWS credentials or database are needed.

To run against a real local target:

```bash
docker-compose up          # starts postgres + localstack + vulnerable Flask app
python local_test_runner.py pentest --url http://localhost:8080
```

To serve the dashboard locally:

```bash
cd api/frontend
python -m http.server 8080
# Open http://localhost:8080/dashboard.html
# Enter your API Gateway URL and API key in the config bar
```

---

## Contributors

| Name | Role | Components owned |
|------|------|-----------------|
| **Ishit Arhatia** | Infrastructure & Orchestration | VPC, SQS + DLQ, Step Functions, Lambda orchestrator, CloudWatch alarms, SNS, CloudTrail, `infra/terraform/` |
| **Ankita Das** | Compute & Scanners | SAST scanner, Pentest scanner, ECS Fargate, ECR, S3 lifecycle, `compute/` |
| **Shubham Kumar** | API & Frontend | API Gateway, Lambda handler + status updater, RDS PostgreSQL, browser dashboard, `api/` |

---

## Deployed Resources

All resources run in `us-east-1` under account `126573932591`.

| Resource | Name / ID |
|----------|-----------|
| API Gateway | `https://7pns6j1i9e.execute-api.us-east-1.amazonaws.com/prod` |
| S3 bucket | `cev-reports-126573932591` |
| RDS | `cev-postgres.cmppftqgluub.us-east-1.rds.amazonaws.com` |
| ECS cluster | `compliance-vault-compute-cluster` |
| SAST task def | `compliance-vault-compute-sast:3` |
| Pentest task def | `compliance-vault-compute-pentest:3` |
| ECR (SAST) | `126573932591.dkr.ecr.us-east-1.amazonaws.com/compliance-vault-compute-sast-scanner` |
| ECR (Pentest) | `126573932591.dkr.ecr.us-east-1.amazonaws.com/compliance-vault-compute-pentest-scanner` |
| Step Functions | `cev-scan-orchestrator` |
| SSM secret | `/cev/db_password` |

---

*CS6620 Fundamentals of Cloud Computing — Spring 2026 — Northeastern University, Khoury College of Computer Sciences*