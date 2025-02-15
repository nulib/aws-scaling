locals {
  solr_collections   = ["arch", "avr"]

  step_function_payload = jsonencode({
    solr = {
      baseUrl       = module.solrcloud.outputs.solr.endpoint
      collections   = local.solr_collections
    }

    rds = {
      stack     = module.data_services.outputs.postgres.instance_name
    }
  })

  # Set the following line to 0 for Standard Time or -1 for Daylight Saving Time
  dst_offset = -1
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
      aws_sfn_state_machine.spin_up_meadow.arn,
      aws_sfn_state_machine.spin_down_meadow.arn,
      aws_sfn_state_machine.spin_up_arch_avr.arn,
      aws_sfn_state_machine.spin_down_arch_avr.arn
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
  name                  = "spin-up-morning"
  description           = "Spin up in the morning"
  schedule_expression   = "cron(00 ${12 + local.dst_offset} ? * MON-FRI *)"
  is_enabled            = true
}

resource "aws_cloudwatch_event_target" "spin_up_in_the_morning" {
  rule        = aws_cloudwatch_event_rule.spin_up_in_the_morning.name
  target_id   = "SpinUpMeadow"
  arn         = aws_sfn_state_machine.spin_up_meadow.arn
  role_arn    = aws_iam_role.event_rule_step_function.arn
}

resource "aws_cloudwatch_event_rule" "spin_down_in_the_evening" {
  name                  = "spin-down-evening"
  description           = "Spin down in the evening"

  schedule_expression   = "cron(00 ${02 + local.dst_offset} ? * TUE-SAT *)"
  is_enabled            = true
}

resource "aws_cloudwatch_event_target" "spin_down_meadow_in_the_evening" {
  rule        = aws_cloudwatch_event_rule.spin_down_in_the_evening.name
  target_id   = "SpinDownMeadow"
  arn         = aws_sfn_state_machine.spin_down_meadow.arn
  role_arn    = aws_iam_role.event_rule_step_function.arn
}

resource "aws_cloudwatch_event_target" "spin_down_arch_avr_in_the_evening" {
  rule        = aws_cloudwatch_event_rule.spin_down_in_the_evening.name
  target_id   = "SpinDownArchAndAVR"
  arn         = aws_sfn_state_machine.spin_down_arch_avr.arn
  input       = local.step_function_payload
  role_arn    = aws_iam_role.event_rule_step_function.arn
}
