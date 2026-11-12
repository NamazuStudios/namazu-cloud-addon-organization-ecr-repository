terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

provider "aws" {
  default_tags {
    tags = local.provider_default_tags
  }
}
