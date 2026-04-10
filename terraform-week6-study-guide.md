# Terraform + AWS: Week 6 Study Guide

## Overview

This week you'll build a serverless API using Lambda and API Gateway — the other dominant compute pattern on AWS alongside containers. You'll learn to package and deploy Lambda functions with Terraform, wire up API Gateway routes, manage permissions, and handle common patterns like environment variables, layers, and DynamoDB integration.

---

## Day 1–2: Lambda Function Basics

Deploy your first Lambda function using Terraform.

### Project Setup

Create a `src/` directory for your Lambda code, separate from your Terraform files:

```
week6-serverless/
├── src/
│   └── handler.py
├── main.tf
├── variables.tf
├── outputs.tf
├── lambda.tf
├── iam.tf
└── ...
```

### Lambda Code

```python
# src/handler.py
import json
import os

def lambda_handler(event, context):
    environment = os.environ.get("ENVIRONMENT", "unknown")
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": f"Hello from {environment}!",
            "path": event.get("rawPath", "/"),
            "method": event.get("requestContext", {}).get("http", {}).get("method", "GET")
        })
    }
```

### Resources to Build

1. **Package the code** — Use `archive_file` data source to zip the Lambda code:

```hcl
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/lambda.zip"
}
```

2. **`aws_iam_role`** — Create the Lambda execution role:

```hcl
resource "aws_iam_role" "lambda" {
  name = "${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
```

3. **`aws_lambda_function`** — Deploy the function:

```hcl
resource "aws_lambda_function" "api" {
  function_name    = "${var.environment}-api"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda.arn
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }
}
```

4. **`aws_cloudwatch_log_group`** — Create explicitly so you control retention:

```hcl
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = 14
}
```

### Exercises

- Apply and test your function from the Lambda console using the "Test" button.
- Modify the Python code, re-apply, and notice how `source_code_hash` triggers an update automatically.
- Check CloudWatch Logs for your function's output.
- Try increasing `memory_size` to 256 and observe that it also increases CPU allocation (Lambda ties CPU to memory).

---

## Day 3: API Gateway (HTTP API)

Create an API Gateway to expose your Lambda function as an HTTP endpoint.

### Resources to Build

1. **`aws_apigatewayv2_api`** — Create an HTTP API (v2 is simpler and cheaper than REST API v1):

```hcl
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.environment}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 3600
  }
}
```

2. **`aws_apigatewayv2_stage`** — Create the default stage with auto-deploy:

```hcl
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      method         = "$context.httpMethod"
      path           = "$context.path"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }
}
```

3. **`aws_apigatewayv2_integration`** — Connect API Gateway to Lambda:

```hcl
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}
```

4. **`aws_apigatewayv2_route`** — Define API routes:

```hcl
resource "aws_apigatewayv2_route" "get" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "catch_all" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}
```

5. **`aws_lambda_permission`** — Allow API Gateway to invoke your Lambda:

```hcl
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
```

### Exercises

- Output the API Gateway endpoint and hit it with `curl` — you should get your JSON response.
- Try different paths and methods — the catch-all route handles everything.
- Check the API Gateway access logs in CloudWatch.
- Try removing the `aws_lambda_permission` and observe the 500 error — this is a very common mistake.

---

## Day 4: DynamoDB Integration

Add a DynamoDB table and connect it to your Lambda function.

### Resources to Build

1. **`aws_dynamodb_table`** — Create a simple table:

```hcl
resource "aws_dynamodb_table" "items" {
  name         = "${var.environment}-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = var.environment
  }
}
```

2. **IAM policy for Lambda** — Allow the function to read/write the table:

```hcl
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "dynamodb-access"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      Resource = [
        aws_dynamodb_table.items.arn,
        "${aws_dynamodb_table.items.arn}/index/*"
      ]
    }]
  })
}
```

3. **Pass the table name** to Lambda via environment variable:

```hcl
environment {
  variables = {
    ENVIRONMENT = var.environment
    TABLE_NAME  = aws_dynamodb_table.items.name
  }
}
```

4. **Update your Lambda code** to use DynamoDB:

```python
import json
import os
import boto3
import uuid

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])

def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if method == "POST":
        body = json.loads(event.get("body", "{}"))
        item = {"id": str(uuid.uuid4()), **body}
        table.put_item(Item=item)
        return {"statusCode": 201, "body": json.dumps(item)}

    elif method == "GET":
        result = table.scan()
        return {"statusCode": 200, "body": json.dumps(result["Items"])}

    return {"statusCode": 405, "body": json.dumps({"error": "Method not allowed"})}
```

### Exercises

- Use `curl -X POST -d '{"name":"test"}' <API_URL>` to create items.
- Use `curl <API_URL>` to list all items.
- Check the DynamoDB table in the console to see the stored items.
- Try removing the IAM policy and observe the Lambda error in CloudWatch — always check permissions first when Lambda fails.

---

## Day 5: Lambda Layers & Advanced Patterns

Learn to manage shared dependencies and advanced Lambda configurations.

### Lambda Layers

For functions with external dependencies, use layers instead of bundling everything:

```hcl
resource "aws_lambda_layer_version" "dependencies" {
  filename            = "${path.module}/build/layer.zip"
  layer_name          = "${var.environment}-python-deps"
  compatible_runtimes = ["python3.12"]
  source_code_hash    = filebase64sha256("${path.module}/build/layer.zip")
}

resource "aws_lambda_function" "api" {
  # ... existing config ...
  layers = [aws_lambda_layer_version.dependencies.arn]
}
```

Build the layer:

```bash
mkdir -p layer/python
pip install requests boto3 -t layer/python/
cd layer && zip -r ../build/layer.zip python/
```

### Multiple Lambda Functions

Use `for_each` to manage multiple functions with shared configuration:

```hcl
locals {
  functions = {
    "get-items"    = { handler = "get_items.handler",    method = "GET",    path = "/items" }
    "create-item"  = { handler = "create_item.handler",  method = "POST",   path = "/items" }
    "delete-item"  = { handler = "delete_item.handler",  method = "DELETE", path = "/items/{id}" }
  }
}

resource "aws_lambda_function" "functions" {
  for_each = local.functions

  function_name    = "${var.environment}-${each.key}"
  handler          = each.value.handler
  # ... shared config ...
}
```

### Exercises

- Create a Lambda layer with a third-party library, deploy it, and verify the function can import the library.
- Refactor your single function into multiple functions (one per API route) using `for_each`.
- Add a `reserved_concurrent_executions` limit to a function and test what happens when you exceed it.

---

## Day 6–7: Clean Up & Reflect

### Tasks

1. **Create a serverless module** — Encapsulate the Lambda + API Gateway + DynamoDB pattern into a reusable module.
2. **Add API Gateway throttling** — Configure rate limiting on your stage to prevent abuse.
3. **Test full destroy and re-apply** — Lambda permissions and API Gateway dependencies can be tricky.
4. **Write a README** documenting your serverless architecture.

### Bonus Challenges

- Add SQS as an event source: create an `aws_sqs_queue`, an `aws_lambda_event_source_mapping`, and a second Lambda that processes queue messages.
- Add a custom domain to API Gateway using `aws_apigatewayv2_domain_name` with an ACM certificate.
- Use `aws_lambda_function_url` as a simpler alternative to API Gateway for single-function APIs.
- Implement structured logging in your Lambda and create a CloudWatch Insights query to search logs.

---

## Key Concepts This Week

| Concept | Why It Matters |
|---|---|
| `source_code_hash` | Triggers redeployment when code changes |
| `archive_file` data source | Packages code at plan time, not a separate build step |
| HTTP API vs REST API | HTTP API (v2) is simpler, cheaper, and faster — use it by default |
| `aws_lambda_permission` | Without this, API Gateway gets 500 errors — most common Lambda mistake |
| Lambda environment variables | Pass configuration without hardcoding in code |
| DynamoDB `PAY_PER_REQUEST` | Perfect for unpredictable workloads — no capacity planning needed |
| Lambda layers | Share dependencies across functions without duplicating code |
| IAM least privilege | Scope Lambda permissions to specific tables and actions |
