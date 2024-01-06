# Prepare terraform provider downloaded packages
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }
    time = {
      source = "hashicorp/time"
      version = "~> 0.10.0"
    }
  }
}