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

variable apt_proxy_url {
  default = "http://172.16.0.4:8080/"
}

source "amazon-ebs" "build-agent-debian" {
  ami_name = "build-agent-debian-${var.ami_branch}-${var.ami_commit}-{{ isotime `20060102-150405` }}"
  instance_type = "t2.micro"
  region        = "us-east-2"

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
    volume_size = 40
    volume_type = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "build-agent-debian"
  sources = [
    "source.amazon-ebs.build-agent-debian"
  ]

  provisioner "file" {
    source = "buildkite-agent.cfg"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-agent.gitconfig"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-agent.sudoers"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-chroot-run"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "buildkite-environment-hook"
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

      "sudo install -m 0755 /tmp/buildkite-environment-hook /etc/buildkite-agent/hooks/environment",
      "sudo install -m 0644 /tmp/buildkite-agent.cfg /etc/buildkite-agent/buildkite-agent.cfg",
      "sudo install -m 0644 /tmp/buildkite-agent.gitconfig /var/lib/buildkite-agent/.gitconfig",

      "sudo systemctl enable buildkite-agent.service",

      # Install build tools

      "sudo apt-get install -y build-essential dpkg-dev sbuild git-buildpackage",

      "wget -O /tmp/jchroot.c https://raw.githubusercontent.com/vincentbernat/jchroot/master/jchroot.c",
      "gcc -o /tmp/jchroot /tmp/jchroot.c",
      "sudo install -m 0755 /tmp/jchroot /usr/local/bin/",

      "sudo install -m 0755 /tmp/buildkite-chroot-run /usr/local/bin/",
      "sudo install -m 0440 /tmp/buildkite-agent.sudoers /etc/sudoers.d/buildkite-agent",

      "sudo sbuild-adduser buildkite-agent",

      # Prepare plain chroots (used with buildkite-chroot-run)

      "sudo debootstrap --include=build-essential,cmake,gcovr,git,libcapstone-dev,libcapstone3,libglew-dev,libglew2.0,libjansson-dev,libjansson4,liblua5.3-0,liblua5.3-dev,libopenal-dev,libsdl2-2.0-0,libsdl2-dev,libwxgtk3.0-dev,lua5.3,xvfb           --arch=i386 stretch /srv/chroot/stretch-i386/ http://cdn-aws.deb.debian.org/debian",
      "sudo mkdir -p /srv/chroot/stretch-i386/var/lib/buildkite-agent/",

      "sudo debootstrap --include=build-essential,cmake,gcovr,git,libcapstone-dev,libcapstone3,libglew-dev,libglew2.0,libjansson-dev,libjansson4,liblua5.3-0,liblua5.3-dev,libopenal-dev,libsdl2-2.0-0,libsdl2-dev,libwxgtk3.0-dev,lua5.3,xvfb,mingw-w64,nasm --arch=amd64 stretch /srv/chroot/stretch-amd64/ http://cdn-aws.deb.debian.org/debian",
      "sudo mkdir -p /srv/chroot/stretch-amd64/var/lib/buildkite-agent/",

      # Install WinPcap headers for building IPXWrapper

      "wget -O /tmp/WpdPack_4_1_2.zip https://www.winpcap.org/install/bin/WpdPack_4_1_2.zip",
      "mkdir /tmp/WpdPack_4_1_2/",
      "unzip /tmp/WpdPack_4_1_2.zip -d /tmp/WpdPack_4_1_2/",
      "sudo cp -r /tmp/WpdPack_4_1_2/WpdPack/Include/* /srv/chroot/stretch-amd64/usr/i686-w64-mingw32/include/",

      # Prepare sbuild chroots

      "sbuild_chroot() {",
      "  sudo sbuild-createchroot --arch=$2 $1 $3 $4",

      "  if [ -n \"${var.apt_proxy_url}\" ]",
      "  then",
      "    echo \"Acquire::http::Proxy \\\"${var.apt_proxy_url}\\\";\" | sudo tee \"$3/etc/apt/apt.conf.d/proxy\" > /dev/null",
      "  fi",
      "}",

      # Debian 10 (buster)
      "sbuild_chroot buster i386  /srv/chroot/buster-i386-sbuild/  http://cdn-aws.deb.debian.org/debian",
      "sbuild_chroot buster amd64 /srv/chroot/buster-amd64-sbuild/ http://cdn-aws.deb.debian.org/debian",

      # Debian 11 (bullseye)
      "sbuild_chroot bullseye i386  /srv/chroot/bullseye-i386-sbuild/  http://cdn-aws.deb.debian.org/debian",
      "sbuild_chroot bullseye amd64 /srv/chroot/bullseye-amd64-sbuild/ http://cdn-aws.deb.debian.org/debian",

      # Ubuntu 18.04 (bionic)
      "sbuild_chroot bionic i386  /srv/chroot/bionic-i386-sbuild/  http://uk.archive.ubuntu.com/ubuntu",
      "sbuild_chroot bionic amd64 /srv/chroot/bionic-amd64-sbuild/ http://uk.archive.ubuntu.com/ubuntu",

      # Ubuntu 20.04 (focal)
      "sudo ln -s gutsy /usr/share/debootstrap/scripts/focal",
      "sbuild_chroot focal amd64 /srv/chroot/focal-amd64-sbuild/ http://uk.archive.ubuntu.com/ubuntu",

      # Ubuntu 21.04 (hirsute)
      "sudo ln -s gutsy /usr/share/debootstrap/scripts/hirsute",
      "sbuild_chroot hirsute amd64 /srv/chroot/hirsute-amd64-sbuild/ http://uk.archive.ubuntu.com/ubuntu",

      "sudo apt-get clean",
    ]
  }
}
