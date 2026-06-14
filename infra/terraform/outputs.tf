output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_a_id" {
  value = module.vpc.private_subnet_a_id
}

output "private_subnet_b_id" {
  value = module.vpc.private_subnet_b_id
}

output "public_subnet_id" {
  value = module.vpc.public_subnet_id
}

output "lambda_sg_id" {
  value = module.vpc.lambda_sg_id
}

output "fargate_sg_id" {
  value = module.vpc.fargate_sg_id
}

output "rds_sg_id" {
  value = module.vpc.rds_sg_id
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "sqs_queue_arn" {
  value = module.sqs.queue_arn
}

output "dlq_arn" {
  value = module.sqs.dlq_arn
}

output "lambda_role_arn" {
  value = module.iam.lambda_role_arn
}

output "fargate_task_role_arn" {
  value = module.iam.fargate_task_role_arn
}