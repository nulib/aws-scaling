locals {
  solr_collections   = ["arch", "avr"]
  meadow_db_name      = "meadow-db"

  step_function_payload = jsonencode({
    solr = {
      baseUrl       = module.solrcloud.outputs.solr.endpoint
      collections   = local.solr_collections
    }

    rds = {
      meadow    = local.meadow_db_name
      stack     = module.data_services.outputs.postgres.instance_name
    }
  })  
}

data "aws_iam_policy_document" "scaling_rule_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "event_rule_step_function" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [
      aws_sfn_state_machine.spin_up_environment.arn,
      aws_sfn_state_machine.spin_down_environment.arn
    ]
  }
}

resource "aws_iam_role" "event_rule_step_function" {
  name                  = "${local.namespace}-environment-scaling-event"
  assume_role_policy    = data.aws_iam_policy_document.scaling_rule_assume_role.json

  inline_policy {
    name    = "${local.namespace}-environment-scaling-event-policy"
    policy  = data.aws_iam_policy_document.event_rule_step_function.json
  }
}

resource "aws_cloudwatch_event_rule" "spin_up_in_the_morning" {
  name                  = "spin-up-environment"
  description           = "Spin up environment in the morning"
  schedule_expression   = "cron(00 11 ? * MON-FRI *)"
  is_enabled            = true
  tags                  = local.tags
}

resource "aws_cloudwatch_event_target" "spin_up_in_the_morning" {
  rule        = aws_cloudwatch_event_rule.spin_up_in_the_morning.name
  target_id   = "SpinUpEnvironment"
  arn         = aws_sfn_state_machine.spin_up_environment.arn
  input       = local.step_function_payload
  role_arn    = aws_iam_role.event_rule_step_function.arn
}

resource "aws_cloudwatch_event_rule" "spin_down_in_the_evening" {
  name                  = "spin-down-environment"
  description           = "Spin down environment in the evening"
  schedule_expression   = "cron(00 01 ? * TUE-SAT *)"
  is_enabled            = true
  tags                  = local.tags
}

resource "aws_cloudwatch_event_target" "spin_down_in_the_evening" {
  rule        = aws_cloudwatch_event_rule.spin_down_in_the_evening.name
  target_id   = "SpinDownEnvironment"
  arn         = aws_sfn_state_machine.spin_down_environment.arn
  input       = local.step_function_payload
  role_arn    = aws_iam_role.event_rule_step_function.arn
}
