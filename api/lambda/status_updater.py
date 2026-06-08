import json
import os
import psycopg2

DB_HOST     = os.environ["DB_HOST"]
DB_NAME     = os.environ["DB_NAME"]
DB_USER     = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]


def get_db_conn():
    return psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        port=5432,
        connect_timeout=5
    )


def lambda_handler(event, context):
    job_id    = event.get("job_id")
    status    = event.get("status")
    error_msg = event.get("error_msg")

    if not job_id or status not in ("RUNNING", "COMPLETED", "FAILED"):
        return {"statusCode": 400, "body": "Invalid input"}

    conn = get_db_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE jobs
                SET status = %s, error_msg = %s
                WHERE id = %s
                """,
                (status, error_msg, job_id)
            )
        conn.commit()
    finally:
        conn.close()

    return {"statusCode": 200, "body": f"Job {job_id} updated to {status}"}