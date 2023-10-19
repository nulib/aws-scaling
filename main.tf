terraform {
  backend "s3" {
    key    = "aws-scaling.tfstate"
  }
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

locals {
  environment   = module.core.outputs.stack.environment
  namespace     = module.core.outputs.stack.namespace

  tags = merge(
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

module "data_services" {
  source = "git::https://github.com/nulib/infrastructure.git//modules/remote_state"
  component = "data_services"
}

module "solrcloud" {
  source = "git::https://github.com/nulib/infrastructure.git//modules/remote_state"
  component = "solrcloud"
}

data "aws_region" "current" { }

data "aws_iam_policy_document" "scaling_step_function" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [
      module.solrcloud.outputs.utils.function_arn,
      "${module.solrcloud.outputs.utils.function_arn}:*"
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
}

resource "aws_iam_role" "scaling_step_function" {
  name                  = "${local.namespace}-scaling-step-function"
  assume_role_policy    = data.aws_iam_policy_document.scaling_step_function_assume_role.json
}

resource "aws_iam_role_policy_attachment" "scaling_step_function" {
  role          = aws_iam_role.scaling_step_function.id
  policy_arn    = aws_iam_policy.scaling_step_function.arn
}

resource "aws_sfn_state_machine" "update_service_counts" {
  name        = "${local.namespace}-update-service-counts"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = file("${path.module}/state_machines/update_service_counts.json")
}

resource "aws_sfn_state_machine" "ensure_db_instance_available" {
  name        = "${local.namespace}-ensure-db-instance-available"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = file("${path.module}/state_machines/ensure_db_instance_available.json")
}

data "template_file" "spin_down_arch_avr" {
  template   = file("${path.module}/state_machines/spin_down_arch_avr.json")

  vars = {
    update_service_counts_state_machine_arn   = aws_sfn_state_machine.update_service_counts.arn
    solr_utils_lambda_arn                     = module.solrcloud.outputs.utils.qualified_function_arn
  }
}

resource "aws_sfn_state_machine" "spin_down_arch_avr" {
  name        = "${local.namespace}-spin-down-arch-and-avr"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = data.template_file.spin_down_arch_avr.rendered
}

data "template_file" "spin_up_arch_avr" {
  template   = file("${path.module}/state_machines/spin_up_arch_avr.json")

  vars = {
    ensure_db_instance_available_state_machine_arn    = aws_sfn_state_machine.ensure_db_instance_available.arn
    update_service_counts_state_machine_arn           = aws_sfn_state_machine.update_service_counts.arn
    solr_utils_lambda_arn                             = module.solrcloud.outputs.utils.qualified_function_arn
  }
}

resource "aws_sfn_state_machine" "spin_up_arch_avr" {
  name        = "${local.namespace}-spin-up-arch-and-avr"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = data.template_file.spin_up_arch_avr.rendered
}

data "template_file" "spin_down_meadow" {
  template   = file("${path.module}/state_machines/spin_down_meadow.json")

  vars = {
    update_service_counts_state_machine_arn   = aws_sfn_state_machine.update_service_counts.arn
  }
}

resource "aws_sfn_state_machine" "spin_down_meadow" {
  name        = "${local.namespace}-spin-down-meadow"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = data.template_file.spin_down_meadow.rendered
}

data "template_file" "spin_up_meadow" {
  template   = file("${path.module}/state_machines/spin_up_meadow.json")

  vars = {
    ensure_db_instance_available_state_machine_arn    = aws_sfn_state_machine.ensure_db_instance_available.arn
    update_service_counts_state_machine_arn           = aws_sfn_state_machine.update_service_counts.arn
  }
}

resource "aws_sfn_state_machine" "spin_up_meadow" {
  name        = "${local.namespace}-spin-up-meadow"
  role_arn    = aws_iam_role.scaling_step_function.arn
  definition  = data.template_file.spin_up_meadow.rendered
}

