packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "buildkite_agent_token" {
  default   = env("BUILDKITE_AGENT_TOKEN")
  sensitive = true
}

variable "ami_branch" {
  default = env("AMI_BRANCH")
}

variable "ami_commit" {
  default = env("AMI_COMMIT")
}

source "amazon-ebs" "freebsd-agent" {
  ami_name = "build-agent-freebsd-${var.ami_branch}-${var.ami_commit}-{{ isotime `20060102-150405` }}"

  instance_type = "t2.micro"
  region        = "us-east-2"

  source_ami_filter {
    filters = {
      name                = "FreeBSD 13.*-RELEASE-amd64-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    most_recent = true
    owners      = ["679593333241"]
  }

  ssh_username = "ec2-user"
}

build {
  name = "freebsd-agent"
  sources = [
    "source.amazon-ebs.freebsd-agent"
  ]

  provisioner "file" {
    source      = "xvfb-run"
    destination = "/tmp/"
  }

  provisioner "file" {
    source      = "install-buildkite.sh"
    destination = "/tmp/"
  }

  provisioner "file" {
    source      = "buildkite-agent.cfg"
    destination = "/tmp/"
  }

  provisioner "file" {
    source      = "buildkite-environment-hook"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "su - root -c 'env ASSUME_ALWAYS_YES=yes pkg install \\",
      "  bash           \\",
      "  capstone4      \\",
      "  git            \\",
      "  gmake          \\",
      "  jansson        \\",
      "  jq             \\",
      "  lua53          \\",
      "  pidof          \\",
      "  pkgconf        \\",
      "  wget           \\",
      "  wx30-gtk3      \\",
      "  xauth          \\",
      "  xorg-vfbserver \\",
      "'",

      "su - root -c 'install -o root -g wheel -m 0755 /tmp/xvfb-run /usr/local/bin/xvfb-run'",
    ]
  }

  provisioner "shell" {
    inline = [
      "chmod 0755 /tmp/install-buildkite.sh",
      "su - root -c /tmp/install-buildkite.sh",

      "sed -i '' -e 's/BUILDKITE_AGENT_TOKEN/${var.buildkite_agent_token}/g' /tmp/buildkite-agent.cfg",

      "su - root -c 'install -m 0640 -o root -g buildkite-agent /tmp/buildkite-agent.cfg        /usr/local/etc/buildkite-agent/buildkite-agent.cfg'",
      "su - root -c 'install -m 0755 -o root -g wheel           /tmp/buildkite-environment-hook /usr/local/etc/buildkite-agent/hooks/environment'",
    ]
  }

  # Cleanup temporary files.

  provisioner "shell" {
    inline = [
      "rm /tmp/buildkite-agent.cfg",
      "rm /tmp/buildkite-environment-hook",
      "rm /tmp/install-buildkite.sh",
      "rm /tmp/xvfb-run",
    ]
  }
}
