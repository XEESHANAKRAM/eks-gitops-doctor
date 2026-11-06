terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket = "fixture-tfstate"
    key    = "fixture/terraform.tfstate"
    region = "us-east-1"
  }
}
