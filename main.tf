terraform {
  backend "s3" {
    key    = "aws-scaling.tfstate"
  }
}

provider "aws" { }

locals {
  environment   = module.core.outputs.stack.environment
  namespace     = module.core.outputs.stack.namespace
  tags          = merge(
    module.core.outputs.stack.tags, 
    {
      Component   = "aws-scaling",
      Git         = "github.com/nulib/aws-scaling"
      Project     = "Infrastructure"
    }
  )
}

module "core" {
  source = "git::https://github.com/nulib/infrastructure.git//modules/remote_state"
  component = "core"
}

module "solrcloud" {
  source = "git::https://github.com/nulib/infrastructure.git//modules/remote_state"
  component = "solrcloud"
}

data "aws_region" "current" { }

module "lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "2.35.1"

  function_name          = "${local.namespace}-solr-utils"
  description            = "Utility functions for managing a solr cluster"
  handler                = "index.handler"
  runtime                = "nodejs14.x"
  source_path            = "${path.module}/lambda"
  timeout                = 30
  vpc_subnet_ids         = module.core.outputs.vpc.private_subnets.ids
  vpc_security_group_ids = [
    module.solrcloud.outputs.solr.client_security_group,
    module.core.outputs.vpc.http_security_group_id
  ]
  attach_network_policy  = true

  tags                   = local.tags
}

data "aws_iam_policy_document" "scaling_step_function" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [
      module.lambda.lambda_function_arn,
      "${module.lambda.lambda_function_arn}:*"
    ]
  }

  statement {
    effect    = "Allow"
    actions   = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "rds:DescribeDBInstances",
      "rds:StopDBInstance",
      "rds:StartDBInstance",
      "states:DescribeExecution",
      "states:StartExecution",
      "states:StartSyncExecution",
      "states:StopExecution",
      "states:SendTaskHeartbeat",
      "states:SendTaskSuccess",
      "states:SendTaskFailure"
    ]
    resources = ["*"]
  }

  statement {
    actions   = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule"      
    ]
    resources = [
      aws_cloudwatch_event_rule.step_function_execution_events.arn
    ]
  }
}

data "aws_iam_policy_document" "scaling_step_function_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "scaling_step_function" {
  name    = "${local.namespace}-scaling-step-function"
  policy  = data.aws_iam_policy_document.scaling_step_function.json
  tags    = local.tags
}

resource "aws_iam_role" "scaling_step_function" {
  name                  = "${local.namespace}-scaling-step-function"
  assume_role_policy    = data.aws_iam_policy_document.scaling_step_function_assume_role.json
  tags                  = local.tags
}

resource "aws_iam_role_policy_attachment" "scaling_step_function" {
  role          = aws_iam_role.scaling_step_function.id
  policy_arn    = aws_iam_policy.scaling_step_function.arn
}

resource "aws_sfn_state_machine" "update_service_counts" {
  name        = "${local.namespace}-update-service-counts"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = file("${path.module}/state_machines/update_service_counts.json")
  tags        = local.tags
}

resource "aws_sfn_state_machine" "ensure_db_instance_available" {
  name        = "${local.namespace}-ensure-db-instance-available"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = file("${path.module}/state_machines/ensure_db_instance_available.json")

  tags        = local.tags
}

data "template_file" "spin_down_state_machine" {
  template   = file("${path.module}/state_machines/spin_down_environment.json")

  vars = {
    update_service_counts_state_machine_arn   = aws_sfn_state_machine.update_service_counts.arn
    solr_utils_lambda_arn                     = module.lambda.lambda_function_qualified_arn
  }
}

resource "aws_sfn_state_machine" "spin_down_environment" {
  name        = "${local.namespace}-spin-down-environment"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = data.template_file.spin_down_state_machine.rendered
  tags        = local.tags
}

data "template_file" "spin_up_state_machine" {
  template   = file("${path.module}/state_machines/spin_up_environment.json")

  vars = {
    ensure_db_instance_available_state_machine_arn    = aws_sfn_state_machine.ensure_db_instance_available.arn
    update_service_counts_state_machine_arn           = aws_sfn_state_machine.update_service_counts.arn
    solr_utils_lambda_arn                             = module.lambda.lambda_function_qualified_arn
  }
}

resource "aws_sfn_state_machine" "spin_up_environment" {
  name        = "${local.namespace}-spin-up-environment"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = data.template_file.spin_up_state_machine.rendered
  tags        = local.tags
}
