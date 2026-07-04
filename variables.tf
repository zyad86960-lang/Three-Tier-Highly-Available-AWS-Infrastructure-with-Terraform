variable "vpc_cider" {
    default = "10.0.0.0/16"
  
}
variable "public_subnet" {
    default = {
        "us-east-1a" = 10
        "us-east-1b" = 20
    }
}
variable "private_subnet" {
    default = {
        "us-east-1a" = 100
        "us-east-1b" = 200
    }
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_name" {
  type    = string
  default = "project_vpc"
}
variable "instance_type" {
    type = string
    default = "t2.micro"
  
}
variable "allowed_ports" {
    type = list(number)
    default = ["22", "80", "443"]
  
}