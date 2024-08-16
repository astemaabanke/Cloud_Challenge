/*
author: Alex Tema Abanke
email: atemaaba@terpmail.umd.edu
purpose: This terraform file will define various serverless AWS services that will be used to build the application infrastructure
Services to be used include: API GATEWAY, LAMBDA and DYNAMODB
This Terraform 
*/

// define cloud provide 
provider "aws" {
  region = "us-east-1"
}

// create a zip file of the javascript source code  

data "archive_file" "lambda_counter_code" {
  type = "zip"  
  source_dir = "${path.module}/lambda-code"
  output_path = "${path.module}/lambda-code.zip"

}
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "lambda-bucket-cloud-challenge"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}
// Take the zip file created and put in an s3 bucket 

resource "aws_s3_object" "lambda_counter_code" {
  bucket = aws_s3_bucket.lambda_bucket.id  // create the bucket
  key = "counterapp.zip" // name of the zip file 
  source = data.archive_file.lambda_counter_code.output_path  // the source where the zip is coming from 

  etag = filemd5(data.archive_file.lambda_counter_code.output_path)
}

// create the lambda function 

resource "aws_lambda_function" "visitorCounterFunction" {
  function_name = "visitorCounterFunction"

  s3_bucket = aws_s3_bucket.lambda_bucket.id // specify bucket to take files 
  s3_key = aws_s3_object.lambda_counter_code.key

  runtime = "nodejs16.x"
  handler = "counterapp.handler"

  source_code_hash = data.archive_file.lambda_counter_code.output_base64sha256
  role = aws_iam_role.lambda_serverless_role.arn

}

# // cloudwatch 
# resource "aws_cloudwatch_log_group" "hello_world" {
#   name = "/aws/lambda/${aws_lambda_function.visitorCounterFunction.function_name}"

#   retention_in_days = 30
# }

// create an IAM ROLE to be used by lamdba
resource "aws_iam_role" "lambda_serverless_role" {
  
  name = "lambda_serverless_role"
  assume_role_policy = file("lambda-policy.json")

}
// attach the policy to the IAM role 
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role = aws_iam_role.lambda_serverless_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


// create a DynamoDB where the lambda code will update 
resource "aws_dynamodb_table" "visitor_count2" {
  name = "VisitorCount2"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "id"

    attribute {
    name ="id"
    type = "S" // S stands for string type 
  }

  tags = {
    Name = "VisitorCount2"
    Environment = "production"
  }
}


// Create a custom policy to allow DynamoDB access for the new tables 

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda_dynamodb_policy"
  description = "Policy to allow Lambda to updae DynamoDB items"

  policy = jsonencode({
    Version = "2012-10-17", 
    Statement = [
      {
        Effect = "Allow",
        Action = "dynamodb:UpdateItem",
        Resource = aws_dynamodb_table.visitor_count2.arn // Use the arn of the new table 
      }
    ]
  })
}

// attach the custome DynamoDB policy to the IAM role 

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role = aws_iam_role.lambda_serverless_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


output "function_name" {
  description = "Name of the lambda function"
  value = aws_lambda_function.visitorCounterFunction
}

// Create an API GATEWAY ENDPONT 
resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

// Create the stage of the API
resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "serverless_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}
// Maps the API  request to lambda
resource "aws_apigatewayv2_integration" "visitor_counter" {
  api_id             = aws_apigatewayv2_api.lambda.id
  integration_uri    = aws_lambda_function.visitorCounterFunction.arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  
}

resource "aws_apigatewayv2_route" "visitor_counter_route" {
  api_id    = aws_apigatewayv2_api.lambda.id
  route_key = "GET /visitor_counter"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_counter.id}"
}

// defines a log group to store access logs
resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

// Gives permission to the API gateway
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitorCounterFunction.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}





