terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      version = "~> 5.95"
      source  = "hashicorp/aws"
    }
    wiz = {
      version = " ~> 1.24"
      source  = "tf.app.wiz.io/wizsec/wiz"
    }
    helm = {
      version = " ~> 2.17"
      source  = "hashicorp/helm"
    }
    kubernetes = {
      version = " ~> 2.36"
      source  = "hashicorp/kubernetes"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.3"
    }
  }
}
