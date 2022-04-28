terraform {
  required_providers {
    lacework = {
      source = "lacework/lacework"
      version = "~> 0.14.0"
    }
  }
}


provider "aws" {
  region = var.aws_region
}

provider "lacework" {
}


resource "random_pet" "lambda_bucket_name" {
  prefix = "lacework-gc-reporter"
  length = 2
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket_name.id

  force_destroy = true
}

resource "aws_s3_bucket_acl" "lambda_bucket_acl" {
  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

data "archive_file" "lambda_gc_reporter" {
  type = "zip"

  source_dir  = "${path.module}/gc-reporter"
  output_path = "${path.module}/gc-reporter.zip"
}

resource "aws_s3_object" "lambda_gc_reporter" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "gc-reporter.zip"
  source = data.archive_file.lambda_gc_reporter.output_path

  etag = filemd5(data.archive_file.lambda_gc_reporter.output_path)
}

resource "aws_lambda_function" "lacework_gc_reporter" {
  function_name = "LaceworkGCReporter"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_gc_reporter.key
  source_code_hash = data.archive_file.lambda_gc_reporter.output_base64sha256
  role = aws_iam_role.lambda_exec.arn

  runtime = "python3.9"
  handler = "lambda_function.lacework_reporter"
  timeout = 60
  environment {
    variables = {
      CUSTOMER_KEY = var.customer_key
      GC_URL = var.google_chronicle_url
       }
    }
}

resource "aws_cloudwatch_log_group" "lacework-cw-logsd" {
  name = "/aws/lambda/${aws_lambda_function.lacework_gc_reporter.function_name}"

  retention_in_days = 1
}

resource "aws_iam_role" "lambda_exec" {
  name = "lacework_serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_api_gateway_rest_api" "lacework_gateway" {
  name        = "LaceworkGRGateway"
  policy      = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [{
      "Effect": "Allow",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "execute-api:/*/*/*"
    },
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "execute-api:/*/*/*",
      "Condition": {
        "NotIpAddress": {
          "aws:SourceIp": ["35.165.121.10", "35.165.83.150", "52.43.197.121", "34.208.85.38", "35.166.181.157", "52.88.113.199", "44.231.201.69", "54.203.18.234", "54.213.7.200" ]
        }
      }
    }
  ]
}
EOT 
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.lacework_gateway.id
  parent_id   = aws_api_gateway_rest_api.lacework_gateway.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.lacework_gateway.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.lacework_gateway.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lacework_gc_reporter.invoke_arn
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.lacework_gateway.id
  resource_id   = aws_api_gateway_rest_api.lacework_gateway.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.lacework_gateway.id
  resource_id = aws_api_gateway_method.proxy_root.resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lacework_gc_reporter.invoke_arn
}

resource "aws_api_gateway_deployment" "lacework_gateway" {
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.lacework_gateway.id
  stage_name  = "lacework"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lacework_gc_reporter.function_name
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_rest_api.lacework_gateway.execution_arn}/*/*"
}

resource "time_sleep" "wait_time" {
  create_duration = "10s"
  depends_on = [aws_api_gateway_deployment.lacework_gateway]
}

resource "lacework_alert_channel_webhook" "google-cronicle" {
  name      = "Google Chronicle Webhook"
  webhook_url = aws_api_gateway_deployment.lacework_gateway.invoke_url
}
