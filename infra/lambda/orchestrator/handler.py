"""
cev-orchestrator Lambda
infra/lambda/orchestrator.py
Ishit's ownership — included here so the team has a complete picture.

Triggered by SQS (cev-scan-queue).
Reads DB_PASSWORD from SSM Parameter Store — never from env vars.
Starts the Step Functions execution with db_password in the payload
so ECS containers receive it as a runtime override.
"""

import json
import os
import boto3

ssm    = boto3.client("ssm",            region_name="us-east-1")
sfn    = boto3.client("stepfunctions",  region_name="us-east-1")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
SSM_DB_PASSWORD   = os.environ.get("SSM_DB_PASSWORD_PATH", "/cev/db_password")


def get_db_password() -> str:
    """Fetch DB_PASSWORD from SSM Parameter Store (SecureString)."""
    resp = ssm.get_parameter(Name=SSM_DB_PASSWORD, WithDecryption=True)
    return resp["Parameter"]["Value"]


def lambda_handler(event, context):
    db_password = get_db_password()

    for record in event.get("Records", []):
        body = json.loads(record["body"])

        job_id    = body["job_id"]
        scan_type = body["scan_type"]
        s3_key    = body.get("s3_key", "")
        target_url = body.get("target_url", "")

        payload = {
            "job_id":      job_id,
            "scan_type":   scan_type,
            "db_password": db_password,   # passed as container override by state machine
        }

        if scan_type == "SAST":
            payload["s3_key"] = s3_key
        elif scan_type == "PENTEST":
            payload["target_url"] = target_url

        sfn.start_execution(
            stateMachineArn = STATE_MACHINE_ARN,
            name            = f"{scan_type.lower()}-{job_id}",
            input           = json.dumps(payload),
        )

        print(f"Started execution for job {job_id} ({scan_type})")

    return {"statusCode": 200}