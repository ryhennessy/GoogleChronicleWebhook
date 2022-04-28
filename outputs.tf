# Output value definitions

output "lambda_bucket_name" {
  description = "Name of the S3 bucket used to store function code."

  value = aws_s3_bucket.lambda_bucket.id
}

output "base_url" {
  description = "Lambda Function URL for Lacework Webhook Integration."

  value = aws_api_gateway_deployment.lacework_gateway.invoke_url
}
