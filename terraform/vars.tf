variable "region" {
  description = "AWS Region"
  default = "eu-west-2"
}

variable "appName" {
  description = "App name"
  default = "fellscout"
}

variable "containerPort" {
  default = 80
}

variable "hostPort" {
  default = 80
}

variable "image" {
  default = "public.ecr.aws/c1i0s5p6/fellscout:latest"
}

# TODO: vcpu, memory,
