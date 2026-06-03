terraform {
    required_version = ">= 1.6.0"

    required_providers {
    linode = {
        source  = "linode/linode"
        version = "~> 2.0"
    }
    local = {
        source  = "hashicorp/local"
        version = "~> 2.4"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

