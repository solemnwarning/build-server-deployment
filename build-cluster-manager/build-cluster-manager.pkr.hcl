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

source "amazon-ebs" "build-cluster-manager" {
  ami_name = "build-cluster-manager-${var.ami_branch}-${var.ami_commit}-{{ isotime `20060102-150405` }}"

  instance_type = "t4g.micro"
  region        = "us-east-2"

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

  provisioner "shell" {
    inline = [
      # Updating package list
      "sudo apt-get update",

      # Install and configure Squid
      "sudo apt-get install -y squid",
      "sudo install -m 0644 /tmp/squid.conf /etc/squid/squid.conf",
    ]
  }
}
