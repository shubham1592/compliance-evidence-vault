output "lambda_role_arn" {
  value = data.aws_iam_role.lab_role.arn
}

output "fargate_task_role_arn" {
  value = data.aws_iam_role.lab_role.arn
}

output "step_functions_role_arn" {
  value = data.aws_iam_role.lab_role.arn
}