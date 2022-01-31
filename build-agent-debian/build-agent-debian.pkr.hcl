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

variable "buildkite_user_ssh_key" {
  default   = env("BUILDKITE_USER_SSH_KEY")
  sensitive = true
}

variable apt_proxy_url {
  default = "http://172.16.0.4:8080/"
}

source "amazon-ebs" "build-agent-debian" {
  ami_name = "build-agent-debian-${var.ami_branch}-${var.ami_commit}-{{ isotime `20060102-150405` }}"
  instance_type = "t2.micro"
  region        = "us-east-2"

  tags = {
    amicleaner-group = "build-agent-debian"
    amicleaner-branch = "${ var.ami_branch }"
  }

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/*/ubuntu-focal-20.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    most_recent = true
    owners      = ["099720109477"]
  }

  ssh_username = "ubuntu"

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 24
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
    source = "buildkite-agent.known_hosts"
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

  provisioner "file" {
    source = "buildkite-agent.service"
    destination = "/tmp/"
  }

  provisioner "file" {
    source = "WpdPack_4_1_2.zip"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "#!/bin/bash -e",

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

      "sudo mkdir -p /var/lib/buildkite-agent/.ssh/",

      "sudo tee /var/lib/buildkite-agent/.ssh/id_rsa > /dev/null << 'EOF'",
      "${var.buildkite_user_ssh_key}",
      "EOF",
      "sudo chown -R buildkite-agent:buildkite-agent /var/lib/buildkite-agent/.ssh/",
      "sudo chmod 0600 /var/lib/buildkite-agent/.ssh/id_rsa",

      "sudo install -m 0600 -o buildkite-agent -g buildkite-agent /tmp/buildkite-agent.known_hosts /var/lib/buildkite-agent/.ssh/known_hosts",

      "sudo install -m 0644 /tmp/buildkite-agent.service /etc/systemd/system/buildkite-agent.service",
      "sudo systemctl daemon-reload",

      "sudo systemctl enable buildkite-agent.service",

      # Install build tools

      "sudo apt-get install -y build-essential dpkg-dev sbuild git-buildpackage debhelper dh-lua",

      "wget -O /tmp/jchroot.c https://raw.githubusercontent.com/vincentbernat/jchroot/master/jchroot.c",
      "gcc -o /tmp/jchroot /tmp/jchroot.c",
      "sudo install -m 0755 /tmp/jchroot /usr/local/bin/",

      "sudo install -m 0755 /tmp/buildkite-chroot-run /usr/local/bin/",
      "sudo install -m 0440 /tmp/buildkite-agent.sudoers /etc/sudoers.d/buildkite-agent",

      "sudo sbuild-adduser buildkite-agent",

      # Prepare plain chroots (used with buildkite-chroot-run)

      "sudo debootstrap --include=file,build-essential,cmake,gcovr,git,libcapstone-dev,libcapstone3,libglew-dev,libglew2.0,libgtk2.0-dev,libjansson-dev,libjansson4,liblua5.3-0,liblua5.3-dev,libopenal-dev,libsdl2-2.0-0,libsdl2-dev,libtemplate-perl,libunistring-dev,libunistring0,libwxgtk3.0-dev,lua5.3,lua-busted,xvfb,xauth,zip --arch=i386 stretch /srv/chroot/stretch-i386/ http://cdn-aws.deb.debian.org/debian",
      "sudo mkdir -p /srv/chroot/stretch-i386/var/lib/buildkite-agent/",

      "sudo wget -O /srv/chroot/stretch-i386/opt/linuxdeploy-i386.AppImage https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-i386.AppImage",
      "sudo mount -t proc proc /srv/chroot/stretch-i386/proc/",
      "sudo chroot /srv/chroot/stretch-i386/ /bin/bash -c ' \\",
      "  cd /opt/ \\",
      "  && chmod 0755 linuxdeploy-i386.AppImage \\",
      "  && ./linuxdeploy-i386.AppImage --appimage-extract \\",
      "  && mv squashfs-root linuxdeploy \\",
      "  && ln -s /opt/linuxdeploy/AppRun /usr/local/bin/linuxdeploy'",

      "sudo debootstrap --include=file,build-essential,cmake,gcovr,git,libcapstone-dev,libcapstone3,libglew-dev,libglew2.0,libgtk2.0-dev,libjansson-dev,libjansson4,liblua5.3-0,liblua5.3-dev,libopenal-dev,libsdl2-2.0-0,libsdl2-dev,libtemplate-perl,libunistring-dev,libunistring0,libwxgtk3.0-dev,lua5.3,lua-busted,xvfb,xauth,mingw-w64,nasm,zip --arch=amd64 stretch /srv/chroot/stretch-amd64/ http://cdn-aws.deb.debian.org/debian",
      "sudo mkdir -p /srv/chroot/stretch-amd64/var/lib/buildkite-agent/",

      "sudo wget -O /srv/chroot/stretch-amd64/opt/linuxdeploy-x86_64.AppImage https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage",
      "sudo mount -t proc proc /srv/chroot/stretch-amd64/proc/",
      "sudo chroot /srv/chroot/stretch-amd64/ /bin/bash -c ' \\",
      "  cd /opt/ \\",
      "  && chmod 0755 linuxdeploy-x86_64.AppImage \\",
      "  && ./linuxdeploy-x86_64.AppImage --appimage-extract \\",
      "  && mv squashfs-root linuxdeploy \\",
      "  && ln -s /opt/linuxdeploy/AppRun /usr/local/bin/linuxdeploy'",

      # Install WinPcap headers for building IPXWrapper

      # "wget -O /tmp/WpdPack_4_1_2.zip https://www.winpcap.org/install/bin/WpdPack_4_1_2.zip",
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

      # Debian 12(?) (bookworm)
      "sbuild_chroot bookworm i386  /srv/chroot/bookworm-i386-sbuild/  http://cdn-aws.deb.debian.org/debian",
      "sbuild_chroot bookworm amd64 /srv/chroot/bookworm-amd64-sbuild/ http://cdn-aws.deb.debian.org/debian",

      # Ubuntu 18.04 (bionic)
      "sbuild_chroot bionic i386  /srv/chroot/bionic-i386-sbuild/  http://uk.archive.ubuntu.com/ubuntu",
      "sudo sed -i -e 's/ main$/ main universe/g' /srv/chroot/bionic-i386-sbuild/etc/apt/sources.list",

      "sbuild_chroot bionic amd64 /srv/chroot/bionic-amd64-sbuild/ http://uk.archive.ubuntu.com/ubuntu",
      "sudo sed -i -e 's/ main$/ main universe/g' /srv/chroot/bionic-amd64-sbuild/etc/apt/sources.list",

      # Ubuntu 20.04 (focal)
      "sbuild_chroot focal amd64 /srv/chroot/focal-amd64-sbuild/ http://uk.archive.ubuntu.com/ubuntu",
      "sudo sed -i -e 's/ main$/ main universe/g' /srv/chroot/focal-amd64-sbuild/etc/apt/sources.list",

      # Ubuntu 21.10 (impish)
      "sbuild_chroot impish amd64 /srv/chroot/impish-amd64-sbuild/ http://uk.archive.ubuntu.com/ubuntu",
      "sudo sed -i -e 's/ main$/ main universe/g' /srv/chroot/impish-amd64-sbuild/etc/apt/sources.list",

      # Use tmpfs for schroot overlays (build stuff in tmpfs)
      "echo 'none  /var/lib/schroot/union/overlay  tmpfs  size=75%  0  0' | sudo tee -a /etc/fstab > /dev/null",

      # Set up "${DIST}-${ARCH}-buildkite" configurations for each of the
      # sbuild chroots which will mount /var/lib/buildkite-agent/builds/ inside
      # the chroot so they can be used for non-sbuild stuff too.

      "for f in /etc/schroot/chroot.d/*-sbuild-*",
      "do",
      "    sed -E \\",
      "        -e 's/^\\[(.*)-sbuild\\]$/[\\1-buildkite]/' \\",
      "        -e 's/^profile=sbuild$/profile=buildkite/' \\",
      "        < \"$f\" | sudo tee \"$(echo \"$f\" | sed -e 's/sbuild-/buildkite-/')\" > /dev/null",
      "done",

      "sudo cp -an /etc/schroot/sbuild /etc/schroot/buildkite",
      "echo '/var/lib/buildkite-agent/builds/  /var/lib/buildkite-agent/builds/  none  rw,bind  0  0' \\",
      "    | sudo tee -a /etc/schroot/buildkite/fstab > /dev/null",

      "sudo apt-get clean",

      "df -h",
    ]

    timeout = "1h"
  }
}
