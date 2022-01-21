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

variable aws_access_key_id {
  default = env("IPXTESTER_AWS_ACCESS_KEY_ID")
  sensitive = true
}

variable aws_secret_access_key {
  default = env("IPXTESTER_AWS_SECRET_ACCESS_KEY")
  sensitive = true
}

source "amazon-ebs" "build-agent-ipxtester" {
  ami_name = "build-agent-ipxtester-${var.ami_branch}-${var.ami_commit}-{{ isotime `20060102-150405` }}"
  instance_type = "c5n.metal" # Currently the smallest/cheapest bare-metal AMD64 instance, needed for VBox provisioning.
  region        = "us-east-2"

  tags = {
    amicleaner-group = "build-agent-ipxtester"
    amicleaner-branch = "${ var.ami_branch }"
  }

  source_ami_filter {
    filters = {
      name                = "debian-10-amd64-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    most_recent = true
    owners      = ["136693071363"]
  }

  ssh_username = "admin"

  launch_block_device_mappings {
    device_name = "/dev/xvda"
    volume_size = 8
    volume_type = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "build-agent-ipxtester"
  sources = [
    "source.amazon-ebs.build-agent-ipxtester"
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
    source = "buildkite-checkout-hook"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-agent.service"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "rc.local"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "ipxwrapper-ci/ipxtester"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "ipxwrapper-ci/make-interfaces.pl"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-agent.sshconfig"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "ipxwrapper-ci/ssh-keys/ipxtest-insecure.rsa"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      # Install Buildkite agent

      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https dirmngr",
      "sudo apt-key adv --keyserver keys.openpgp.org --recv-keys 32A37959C2FA5C3C99EFBC32A79206696452D198",
      "echo deb https://apt.buildkite.com/buildkite-agent stable main | sudo tee /etc/apt/sources.list.d/buildkite-agent.list > /dev/null",

      "sudo apt-get update",
      "sudo apt-get install -y buildkite-agent",

      "sed -i -e 's/BUILDKITE_AGENT_TOKEN/${var.buildkite_agent_token}/g' /tmp/buildkite-agent.cfg",

      "sudo install -m 0755 -o root -g root /tmp/buildkite-checkout-hook    /etc/buildkite-agent/hooks/checkout",
      "sudo install -m 0755 -o root -g root /tmp/buildkite-environment-hook /etc/buildkite-agent/hooks/environment",
      "sudo install -m 0644 -o root -g root /tmp/buildkite-agent.cfg        /etc/buildkite-agent/buildkite-agent.cfg",

      "sudo install -m 0644 /tmp/buildkite-agent.service /etc/systemd/system/buildkite-agent.service",
      "sudo systemctl daemon-reload",

      # Install VirtualBox

      "wget -qO - https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo apt-key add -",
      "echo deb [arch=amd64] https://download.virtualbox.org/virtualbox/debian buster contrib | sudo tee /etc/apt/sources.list.d/buildkite-agent.list > /dev/null",

      "sudo apt-get update",
      "sudo apt-get install -y linux-headers-cloud-amd64",
      "sudo apt-get install -y virtualbox-6.0",

      # Install ipxtester and depedencies

      "sudo apt-get install -y libconfig-ini-perl libipc-run-perl libnetaddr-ip-perl",
      "sudo install -D -m 0755 -o root -g root /tmp/ipxtester /opt/ipxtester/ipxtester",

      "sudo install -D -m 0644 -o buildkite-agent -g buildkite-agent /tmp/buildkite-agent.sshconfig /var/lib/buildkite-agent/.ssh/config",
      "sudo install -D -m 0600 -o buildkite-agent -g buildkite-agent /tmp/ipxtest-insecure.rsa      /var/lib/buildkite-agent/.ssh/ipxtest-insecure.rsa",

      "echo '#!/bin/sh'                        | sudo tee    /usr/local/bin/ipxtester > /dev/null",
      "echo 'exec /opt/ipxtester/ipxtester $*' | sudo tee -a /usr/local/bin/ipxtester > /dev/null",
      "sudo chmod 0755 /usr/local/bin/ipxtester",

      "perl -c /opt/ipxtester/ipxtester",
      "perl -c /tmp/make-interfaces.pl",

      "   sudo -u buildkite-agent /tmp/make-interfaces.pl 32 192.168.99.0/24 \\",
      "|| sudo -u buildkite-agent /tmp/make-interfaces.pl 32 192.168.99.0/24",

      # Set up AWS CLI

      "sudo apt-get install -y awscli",

      "sudo mkdir -p /root/.aws/",

      "echo [default]                                            | sudo tee    /root/.aws/credentials > /dev/null",
      "echo aws_access_key_id  = ${var.aws_access_key_id}        | sudo tee -a /root/.aws/credentials > /dev/null",
      "echo aws_secret_access_key = ${var.aws_secret_access_key} | sudo tee -a /root/.aws/credentials > /dev/null",
      "sudo chmod 0600 /root/.aws/credentials",

      # For ramdisk
      "sudo apt-get install -y btrfs-progs",
      "sudo mkdir /mnt/ramdisk/",

      # rc.local will take care of remaining provisioning at instace startup
      "sudo install -m 0755 -o root -g root /tmp/rc.local /etc/rc.local",

      "sudo apt-get clean",
    ]

    timeout = "1h"
  }
}
