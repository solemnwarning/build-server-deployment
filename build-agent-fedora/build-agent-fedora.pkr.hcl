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

variable dnf_proxy_url {
  # Escape for sed
  default = "http:\\/\\/172.16.0.4:8080\\/"
}

source "amazon-ebs" "build-agent-fedora" {
  ami_name = "build-agent-fedora-${var.ami_branch}-${var.ami_commit}-{{ isotime `20060102-150405` }}"
  instance_type = "t2.micro"
  region        = "us-east-2"

  tags = {
    amicleaner-group = "build-agent-fedora"
    amicleaner-branch = "${ var.ami_branch }"
  }

  source_ami_filter {
    filters = {
      name                = "Fedora-Cloud-Base-34-*.x86_64-*"
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

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 14
    volume_type = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "build-agent-fedora"
  sources = [
    "source.amazon-ebs.build-agent-fedora"
  ]

  provisioner "file" {
    source = "buildkite-agent.cfg"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-agent.sudoers"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-build-rpm"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-environment-hook"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "dnf.conf.fedora"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "dnf.conf.epel7"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "dnf.conf.epel8"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      # Install Buildkite agent

      "echo ################################",
      "echo #                              #",
      "echo #  INSTALLING BUILDKITE AGENT  #",
      "echo #                              #",
      "echo ################################",

      "sudo tee /etc/yum.repos.d/buildkite-agent.repo <<'EOF'",
      "[buildkite-agent]",
      "name = Buildkite Pty Ltd",
      "baseurl = https://yum.buildkite.com/buildkite-agent/stable/x86_64/",
      "enabled = 1",
      "gpgcheck = 0",
      "priority = 1",
      "EOF",

      "sudo yum -y install buildkite-agent",

      "sed -i -e 's/BUILDKITE_AGENT_TOKEN/${var.buildkite_agent_token}/g' /tmp/buildkite-agent.cfg",

      "sudo install -m 0755 /tmp/buildkite-environment-hook /etc/buildkite-agent/hooks/environment",
      "sudo install -m 0644 /tmp/buildkite-agent.cfg /etc/buildkite-agent/buildkite-agent.cfg",

      "sudo systemctl enable buildkite-agent.service",

      # Install build tools

      "echo ############################",
      "echo #                          #",
      "echo #  INSTALLING BUILD TOOLS  #",
      "echo #                          #",
      "echo ############################",

      "sudo yum -y install wget gcc",

      "wget -O /tmp/jchroot.c https://raw.githubusercontent.com/vincentbernat/jchroot/master/jchroot.c",
      "gcc -o /tmp/jchroot /tmp/jchroot.c",
      "sudo install -m 0755 /tmp/jchroot /usr/local/bin/",

      "sudo yum -y install perl perl-Readonly",

      "sudo install -m 0755 /tmp/buildkite-build-rpm /usr/local/bin/",
      "sudo install -m 0440 /tmp/buildkite-agent.sudoers /etc/sudoers.d/buildkite-agent",

      "sudo yum -y install distribution-gpg-keys",
      "sudo yum -y install capstone-devel jansson-devel lua-devel make wxGTK3-devel",

      # Prepare bootstrap chroot
      #
      # Fedora 33+ use SQLite for their RPM database rather than BDB.
      # When using dnf to install a chroot, the host rpm is used and whatever database format it
      # uses winds up in the chroot.
      #
      # Having chroots that can't read their own RPM database isn't helpful, so instead, *sigh*, we
      # bootstrap an EPEL 8 chroot (which, as mentioned, can't read its own RPM database), then use
      # THAT to create the final chroots for older distributions.

      "echo ################################",
      "echo #                              #",
      "echo #  PREPARING BOOTSTRAP CHROOT  #",
      "echo #                              #",
      "echo ################################",

      "BOOTSTRAP=/srv/chroot/bootstrap/",

      "sudo mkdir -p $BOOTSTRAP/{etc/dnf,dev,proc,usr/share,srv/chroot}/",
      "sudo install -m 0644 -o root -g root /tmp/dnf.conf.epel8 $BOOTSTRAP/etc/dnf/dnf.conf",
      "sudo cp -a /usr/share/distribution-gpg-keys $BOOTSTRAP/usr/share/",

      "sudo dnf --installroot=\"$BOOTSTRAP\" -c \"$BOOTSTRAP/etc/dnf/dnf.conf\" --nodocs --releasever=8 --forcearch=x86_64 install distribution-gpg-keys dnf",

      "sudo cp /etc/resolv.conf $BOOTSTRAP/etc/resolv.conf",

      "sudo mount -o bind /dev/         $BOOTSTRAP/dev/",
      "sudo mount -o bind /dev/pts/     $BOOTSTRAP/dev/pts/",
      "sudo mount -t proc none          $BOOTSTRAP/proc/",
      "sudo mount -o bind /srv/chroot/  $BOOTSTRAP/srv/chroot/",

      # Prepare Fedora 33 chroot

      "echo ################################",
      "echo #                              #",
      "echo #  PREPARING FEDORA 33 CHROOT  #",
      "echo #                              #",
      "echo ################################",

      "ROOT=/srv/chroot/fedora-33-x86_64/",
      "RELEASEVER=33",

      "sudo mkdir -p $ROOT/{etc/dnf,dev,proc,usr/share}/",
      "sudo install -m 0644 -o root -g root /tmp/dnf.conf.fedora $ROOT/etc/dnf/dnf.conf",
      "sudo cp -a /usr/share/distribution-gpg-keys $ROOT/usr/share/",

      "sudo dnf --installroot=\"$ROOT\" -c \"$ROOT/etc/dnf/dnf.conf\" --nodocs --releasever=$RELEASEVER --forcearch=x86_64 groupinstall core",
      "sudo dnf --installroot=\"$ROOT\" -c \"$ROOT/etc/dnf/dnf.conf\" --nodocs --releasever=$RELEASEVER --forcearch=x86_64 install distribution-gpg-keys rpmdevtools",

      "sudo sed -i -e 's/^\\[main\\]$/[main]\\nproxy=${var.dnf_proxy_url}/' \"$ROOT/etc/dnf/dnf.conf\"",

      # Prepare Fedora 34 chroot

      "echo ################################",
      "echo #                              #",
      "echo #  PREPARING FEDORA 34 CHROOT  #",
      "echo #                              #",
      "echo ################################",

      "ROOT=/srv/chroot/fedora-34-x86_64/",
      "RELEASEVER=34",

      "sudo mkdir -p $ROOT/{etc/dnf,dev,proc,usr/share}/",
      "sudo install -m 0644 -o root -g root /tmp/dnf.conf.fedora $ROOT/etc/dnf/dnf.conf",
      "sudo cp -a /usr/share/distribution-gpg-keys $ROOT/usr/share/",

      "sudo dnf --installroot=\"$ROOT\" -c \"$ROOT/etc/dnf/dnf.conf\" --nodocs --releasever=$RELEASEVER --forcearch=x86_64 groupinstall core",
      "sudo dnf --installroot=\"$ROOT\" -c \"$ROOT/etc/dnf/dnf.conf\" --nodocs --releasever=$RELEASEVER --forcearch=x86_64 install distribution-gpg-keys rpmdevtools",

      "sudo sed -i -e 's/^\\[main\\]$/[main]\\nproxy=${var.dnf_proxy_url}/' \"$ROOT/etc/dnf/dnf.conf\"",

      # Prepare EPEL 7 chroot

      "echo #############################",
      "echo #                           #",
      "echo #  PREPARING EPEL 7 CHROOT  #",
      "echo #                           #",
      "echo #############################",

      "ROOT=/srv/chroot/epel-7-x86_64/",

      "sudo mkdir -p $ROOT/{etc/dnf,dev,proc,usr/share}/",
      "sudo install -m 0644 -o root -g root /tmp/dnf.conf.epel7 $ROOT/etc/dnf/dnf.conf",
      "sudo cp -a /usr/share/distribution-gpg-keys $ROOT/usr/share/",

      "sudo chroot $BOOTSTRAP dnf --installroot=\"$ROOT\" -c \"$ROOT/etc/dnf/dnf.conf\" --nodocs --releasever=7 --forcearch=x86_64 groupinstall core",
      "sudo chroot $BOOTSTRAP dnf --installroot=\"$ROOT\" -c \"$ROOT/etc/dnf/dnf.conf\" --nodocs --releasever=7 --forcearch=x86_64 install distribution-gpg-keys rpmdevtools epel-release",
      "sudo chroot $BOOTSTRAP dnf --installroot=\"$ROOT\" -c \"$ROOT/etc/dnf/dnf.conf\" --nodocs --releasever=7 --forcearch=x86_64 install dnf dnf-plugins-core",

      "sudo sed -i -e 's/^\\[main\\]$/[main]\\nproxy=${var.dnf_proxy_url}/' \"$ROOT/etc/dnf/dnf.conf\"",

      # Prepare EPEL 8 chroot

      "echo #############################",
      "echo #                           #",
      "echo #  PREPARING EPEL 8 CHROOT  #",
      "echo #                           #",
      "echo #############################",

      "ROOT=/srv/chroot/epel-8-x86_64/",

      "sudo mkdir -p $ROOT/{etc/dnf,dev,proc,usr/share}/",
      "sudo install -m 0644 -o root -g root /tmp/dnf.conf.epel8 $ROOT/etc/dnf/dnf.conf",
      "sudo cp -a /usr/share/distribution-gpg-keys $ROOT/usr/share/",

      "sudo chroot $BOOTSTRAP dnf --installroot=\"$ROOT\" -c \"$ROOT/etc/dnf/dnf.conf\" --nodocs --releasever=8 --forcearch=x86_64 groupinstall core",
      "sudo chroot $BOOTSTRAP dnf --installroot=\"$ROOT\" -c \"$ROOT/etc/dnf/dnf.conf\" --nodocs --releasever=8 --forcearch=x86_64 install distribution-gpg-keys rpmdevtools epel-release",

      "sudo sed -i -e 's/^\\[main\\]$/[main]\\nproxy=${var.dnf_proxy_url}/' \"$ROOT/etc/dnf/dnf.conf\"",

      # Clean up bootstrap chroot

      "echo #################",
      "echo #               #",
      "echo #  CLEANING UP  #",
      "echo #               #",
      "echo #################",

      "sudo umount $BOOTSTRAP/srv/chroot/",
      "sudo umount $BOOTSTRAP/proc/",
      "sudo umount $BOOTSTRAP/dev/pts/",
      "sudo umount $BOOTSTRAP/dev/",

      "sudo rm -rf $BOOTSTRAP",

      "sudo dnf clean all",
    ]
  }
}
