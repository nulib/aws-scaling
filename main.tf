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

  function_name          = "${local.namespace}-scaling-utils"
  description            = "Utility functions for spinning resources up and down"
  handler                = "index.handler"
  runtime                = "nodejs14.x"
  source_path            = "${path.module}/lambda"
  vpc_subnet_ids         = module.core.outputs.vpc.private_subnets.ids
  vpc_security_group_ids = [
    module.solrcloud.outputs.solr.client_security_group,
    module.core.outputs.vpc.http_security_group_id
  ]
  attach_network_policy  = true
}

