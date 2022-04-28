# Input variable definitions

variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = ""
}


variable "customer_key" {
  description = "Google Chronicle Customer Key."

  type    = string
  default = ""
}

variable "google_chronicle_url" {
  description = "Google Chronicle URL."

  type    = string
  default = ""
}
