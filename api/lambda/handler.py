import json
import os
import uuid
import boto3
import psycopg2
from datetime import datetime, timezone

DB_HOST     = os.environ["DB_HOST"]
DB_NAME     = os.environ["DB_NAME"]
DB_USER     = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]
S3_BUCKET   = os.environ["S3_BUCKET"]
SQS_URL     = os.environ["SQS_URL"]

s3  = boto3.client("s3",  region_name="us-east-1")
sqs = boto3.client("sqs", region_name="us-east-1")


def get_db_conn():
    return psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        port=5432,
        connect_timeout=5
    )


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps(body, default=str)
    }


def create_job(body):
    scan_type = body.get("scan_type", "").upper()
    if scan_type not in ("SAST", "PENTEST"):
        return response(400, {"error": "scan_type must be SAST or PENTEST"})

    job_id = str(uuid.uuid4())
    s3_key = f"uploads/{job_id}/source.zip"

    conn = get_db_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO jobs (id, scan_type, status, s3_key) VALUES (%s, %s, 'PENDING', %s)",
                (job_id, scan_type, s3_key)
            )
        conn.commit()
    finally:
        conn.close()

    presigned_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": S3_BUCKET, "Key": s3_key},
        ExpiresIn=300
    )

    sqs.send_message(
        QueueUrl=SQS_URL,
        MessageBody=json.dumps({
            "job_id":    job_id,
            "scan_type": scan_type,
            "s3_key":    s3_key
        })
    )

    return response(201, {
        "job_id":     job_id,
        "upload_url": presigned_url,
        "s3_key":     s3_key,
        "status":     "PENDING"
    })


def get_job(job_id):
    conn = get_db_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, scan_type, status, s3_key, error_msg, created_at, updated_at FROM jobs WHERE id = %s",
                (job_id,)
            )
            row = cur.fetchone()
            if not row:
                return response(404, {"error": "Job not found"})

            job = {
                "job_id":     str(row[0]),
                "scan_type":  row[1],
                "status":     row[2],
                "s3_key":     row[3],
                "error_msg":  row[4],
                "created_at": str(row[5]),
                "updated_at": str(row[6]),
                "findings":   []
            }

            cur.execute(
                "SELECT id, severity, vuln_type, detail, created_at FROM findings WHERE job_id = %s ORDER BY severity",
                (job_id,)
            )
            for f in cur.fetchall():
                job["findings"].append({
                    "finding_id": str(f[0]),
                    "severity":   f[1],
                    "vuln_type":  f[2],
                    "detail":     f[3],
                    "created_at": str(f[4])
                })

        return response(200, job)
    finally:
        conn.close()


def list_jobs():
    conn = get_db_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, scan_type, status, created_at, updated_at FROM jobs ORDER BY created_at DESC LIMIT 50"
            )
            jobs = []
            for row in cur.fetchall():
                jobs.append({
                    "job_id":     str(row[0]),
                    "scan_type":  row[1],
                    "status":     row[2],
                    "created_at": str(row[3]),
                    "updated_at": str(row[4])
                })
        return response(200, {"jobs": jobs})
    finally:
        conn.close()


def lambda_handler(event, context):
    method = event.get("httpMethod", "")
    path   = event.get("path", "")
    params = event.get("pathParameters") or {}

    try:
        if method == "POST" and path == "/jobs":
            body = json.loads(event.get("body") or "{}")
            return create_job(body)
        elif method == "GET" and params.get("id"):
            return get_job(params["id"])
        elif method == "GET" and path == "/jobs":
            return list_jobs()
        else:
            return response(404, {"error": "Route not found"})
    except Exception as e:
        print(f"ERROR: {e}")
        return response(500, {"error": "Internal server error", "detail": str(e)})