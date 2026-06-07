import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sfn_client = boto3.client('stepfunctions')

STATE_MACHINE_ARN = os.environ['STATE_MACHINE_ARN']


def handler(event, context):
    """
    Triggered by SQS. Reads each scan job message and
    starts one Step Functions execution per job.
    """
    batch_item_failures = []

    for record in event['Records']:
        message_id = record['messageId']

        try:
            body       = json.loads(record['body'])
            job_id     = body['job_id']
            scan_type  = body['scan_type']
            s3_key     = body.get('s3_key')
            target_url = body.get('target_url')

            logger.info(f"Starting execution for job_id={job_id} scan_type={scan_type}")

            execution_input = {
                "job_id":     job_id,
                "scan_type":  scan_type,
                "s3_key":     s3_key,
                "target_url": target_url
            }

            response = sfn_client.start_execution(
                stateMachineArn=STATE_MACHINE_ARN,
                name=f"scan-{job_id}",
                input=json.dumps(execution_input)
            )

            logger.info(f"Started execution: {response['executionArn']}")

        except Exception as e:
            logger.error(f"Failed to process message {message_id}: {str(e)}")
            batch_item_failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": batch_item_failures}