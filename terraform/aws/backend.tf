terraform {
  backend "s3" {
    bucket         = "t-mining-pilots-infra-terraform"
    key            = "terraform/state/dev/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "t-mining-pilots-infra-terraform-lock-table"
    encrypt        = true
  }
}
