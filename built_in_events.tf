# This event rule and its target may already exist in any account that has previously 
# created a Step Function that calls another Step Function. If so, `terraform apply`
# will fail, and you'll need to adopt these by running
#
#  terraform import aws_cloudwatch_event_rule.step_function_execution_events StepFunctionsGetEventsForStepFunctionsExecutionRule
#  terraform import aws_cloudwatch_event_target.step_function_execution_events default/StepFunctionsGetEventsForStepFunctionsExecutionRule/StepFunctionsGetEventsForStepFunctionsExecutionRule-Id
#

resource "aws_cloudwatch_event_rule" "step_function_execution_events" {
  name          = "StepFunctionsGetEventsForStepFunctionsExecutionRule"
  description   = "This rule is used to notify Step Functions regarding integrated workflow executions"

  event_pattern = jsonencode({
    source = ["aws.states"]
    "detail-type" = ["Step Functions Execution Status Change"],
    detail = {
      status = [
        "FAILED",
        "SUCCEEDED",
        "TIMED_OUT",
        "ABORTED"
      ]
    }
  })

  lifecycle {
    ignore_changes  = all
    prevent_destroy = true
  }
}

resource "aws_cloudwatch_event_target" "step_function_execution_events" {
  rule = aws_cloudwatch_event_rule.step_function_execution_events.name
  target_id = "StepFunctionsGetEventsForStepFunctionsExecutionRule-Id"
  arn  = "arn:aws:states:${data.aws_region.current.name}:::"
}

