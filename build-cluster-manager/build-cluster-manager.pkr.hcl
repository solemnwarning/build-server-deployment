packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "ami_branch" {
  default = env("AMI_BRANCH")
}

variable "ami_commit" {
  default = env("AMI_COMMIT")
}

variable aws_access_key_id {
  default = env("SCALER_AWS_ACCESS_KEY_ID")
  sensitive = true
}

variable aws_secret_access_key {
  default = env("SCALER_AWS_SECRET_ACCESS_KEY")
  sensitive = true
}

variable aws_region {
  default = "us-east-2"
}

variable buildkite_organization {
  default = "solemnwarning"
}

variable buildkite_api_key {
  default = env("SCALER_BUILDKITE_API_KEY")
  sensitive = true
}

source "amazon-ebs" "build-cluster-manager" {
  ami_name = "build-cluster-manager-${var.ami_branch}-${var.ami_commit}-{{ isotime `20060102-150405` }}"

  instance_type = "t4g.micro"
  region        = "us-east-2"

  tags = {
    amicleaner-group = "build-cluster-manager"
    amicleaner-branch = "${ var.ami_branch }"
  }

  source_ami_filter {
    filters = {
      name                = "debian-10-arm64-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    most_recent = true
    owners      = ["136693071363"]
  }

  ssh_username = "admin"

  launch_block_device_mappings {
    device_name = "/dev/xvda"
    volume_size = 16
    volume_type = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "build-cluster-manager"
  sources = [
    "source.amazon-ebs.build-cluster-manager"
  ]

  provisioner "file" {
    source = "squid.conf"
    destination = "/tmp/squid.conf"
  }

  provisioner "file" {
    source = "buildkite-spot-fleet-scaler/bin/buildkite-spot-fleet-scaler"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      # Updating package list
      "sudo apt-get update",

      # Install and configure Squid
      "sudo apt-get install -y squid",
      "sudo install -m 0644 /tmp/squid.conf /etc/squid/squid.conf",

      # Install and configure buildkite-spot-fleet-scaler

      "sudo apt-get install -y awscli libdata-compare-perl libipc-run-perl libjson-perl liblist-compare-perl libwww-perl",
      "sudo install -m 0755 -o root -g root /tmp/buildkite-spot-fleet-scaler /usr/local/bin/",

      "sudo tee /etc/cron.d/buildkite-spot-fleet-scaler << 'EOF'",

      "AWS_ACCESS_KEY_ID=${var.aws_access_key_id}",
      "AWS_SECRET_ACCESS_KEY=${var.aws_secret_access_key}",
      "AWS_DEFAULT_REGION=${var.aws_region}",
      "BUILDKITE_ORGANIZATION=${var.buildkite_organization}",
      "BUILDKITE_API_KEY=${var.buildkite_api_key}",
      "",
      "# Run buildkite-spot-fleet-scaler every 2 minutes",
      "*/2 * * * * root /usr/local/bin/buildkite-spot-fleet-scaler",

      "EOF",

      "sudo chmod 0600 /etc/cron.d/buildkite-spot-fleet-scaler",
    ]

    timeout = "1h"
  }
}
