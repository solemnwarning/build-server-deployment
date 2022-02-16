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

variable "buildkite_agent_token" {
  default   = env("BUILDKITE_AGENT_TOKEN")
  sensitive = true
}

variable "buildkite_user_aws_access_key_id" {
  default   = env("BUILDKITE_USER_AWS_ACCESS_KEY_ID")
  sensitive = true
}

variable "buildkite_user_aws_secret_access_key" {
  default   = env("BUILDKITE_USER_AWS_SECRET_ACCESS_KEY")
  sensitive = true
}

source "amazon-ebs" "build-agent-copr" {
  ami_name = "build-agent-copr-${var.ami_branch}-${var.ami_commit}-{{ isotime `20060102-150405` }}"
  instance_type = "a1.medium"
  region        = "us-east-2"

  tags = {
    amicleaner-group = "build-agent-copr"
    amicleaner-branch = "${ var.ami_branch }"
  }

  source_ami_filter {
    filters = {
      name                = "Fedora-Cloud-Base-35-*.aarch64-hvm-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    most_recent = true
    owners      = ["125523088429"]
  }

  ssh_username = "fedora"

  # Use user_data to enable SHA-1 signatures during SSH handshake
  # Workaround for https://github.com/hashicorp/packer/issues/8609
  user_data = <<EOF
#!/bin/bash
sudo update-crypto-policies --set LEGACY
EOF
}

build {
  name    = "build-agent-copr"
  sources = [
    "source.amazon-ebs.build-agent-copr"
  ]

  provisioner "file" {
    source = "buildkite-agent.cfg"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-environment-hook"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-agent.service.extra"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      # Install Buildkite agent

      "sudo tee /etc/yum.repos.d/buildkite-agent.repo <<'EOF'",
      "[buildkite-agent]",
      "name = Buildkite Pty Ltd",
      "baseurl = https://yum.buildkite.com/buildkite-agent/stable/aarch64/",
      "enabled = 1",
      "gpgcheck = 0",
      "priority = 1",
      "EOF",

      "sudo yum -y install buildkite-agent",

      "sed -i -e 's/BUILDKITE_AGENT_TOKEN/${var.buildkite_agent_token}/g' /tmp/buildkite-agent.cfg",

      "sudo install -m 0755 /tmp/buildkite-environment-hook /etc/buildkite-agent/hooks/environment",
      "sudo install -m 0644 /tmp/buildkite-agent.cfg /etc/buildkite-agent/buildkite-agent.cfg",

      # Need to disable SELinux since the default policy on Fedora stops systemd from reading
      # files in /etc/systemd/system/... fuck SELinux.
      "sudo grubby --update-kernel ALL --args selinux=0",

      "cat /usr/share/buildkite-agent/systemd/buildkite-agent.service /tmp/buildkite-agent.service.extra > /tmp/buildkite-agent.service",
      "sudo install -m 0644 /tmp/buildkite-agent.service /etc/systemd/system/buildkite-agent.service",
      "sudo systemctl daemon-reload",

      "sudo systemctl enable buildkite-agent.service",

      # Set up buildkite-agent user AWS configuration

      "sudo -u buildkite-agent mkdir /var/lib/buildkite-agent/.aws/",

      "sudo -u buildkite-agent tee /var/lib/buildkite-agent/.aws/config << 'EOF' > /dev/null",
      "[default]",
      "region = us-east-2",
      "EOF",

      "sudo -u buildkite-agent tee /var/lib/buildkite-agent/.aws/credentials << 'EOF' > /dev/null",
      "[default]",
      "aws_access_key_id = ${var.buildkite_user_aws_access_key_id}",
      "aws_secret_access_key = ${var.buildkite_user_aws_secret_access_key}",
      "EOF",

      "sudo -u buildkite-agent chmod 0600 /var/lib/buildkite-agent/.aws/*",

      "sudo yum -y install rpm-build awscli copr-cli",

      "sudo dnf clean all",
    ]

    timeout = "1h"
  }
}
