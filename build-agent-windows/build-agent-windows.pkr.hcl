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

variable "administrator_password" {
  default   = env("WINDOWS_ADMIN_PASSWORD")
  sensitive = true
}

variable "buildkite_agent_token" {
  default   = env("BUILDKITE_AGENT_TOKEN")
  sensitive = true
}

source "amazon-ebs" "build-agent-windows" {
  ami_name = "build-agent-windows-${var.ami_branch}-${var.ami_commit}-{{ isotime `20060102-150405` }}"

  instance_type = "t2.medium"
  region        = "us-east-2"

  tags = {
    amicleaner-group = "build-agent-windows"
    amicleaner-branch = "${ var.ami_branch }"
  }

  source_ami_filter {
    filters = {
      name                = "Windows_Server-2019-English-Full-Base-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    most_recent = true
    owners      = ["801119661308"]
  }

  user_data = <<EOF
<powershell>
# Set administrator password
net user Administrator ${var.administrator_password}
wmic useraccount where "name='Administrator'" set PasswordExpires=FALSE

# First, make sure WinRM can't be connected to
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new enable=yes action=block

# Delete any existing WinRM listeners
winrm delete winrm/config/listener?Address=*+Transport=HTTP  2>$Null
winrm delete winrm/config/listener?Address=*+Transport=HTTPS 2>$Null

# Disable group policies which block basic authentication and unencrypted login

Set-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WinRM\Client -Name AllowBasic -Value 1
Set-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WinRM\Client -Name AllowUnencryptedTraffic -Value 1
Set-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WinRM\Service -Name AllowBasic -Value 1
Set-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WinRM\Service -Name AllowUnencryptedTraffic -Value 1

# Create a new WinRM listener and configure
winrm create winrm/config/listener?Address=*+Transport=HTTP
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="0"}'
winrm set winrm/config '@{MaxTimeoutms="7200000"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service '@{MaxConcurrentOperationsPerUser="12000"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

# Configure UAC to allow privilege elevation in remote shells
$Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$Setting = 'LocalAccountTokenFilterPolicy'
Set-ItemProperty -Path $Key -Name $Setting -Value 1 -Force

# Configure and restart the WinRM Service; Enable the required firewall exception
Stop-Service -Name WinRM
Set-Service -Name WinRM -StartupType Automatic
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new action=allow localip=any remoteip=any
Start-Service -Name WinRM
</powershell>
EOF

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = "${var.administrator_password}"
}

build {
  name = "build-agent-windows"
  sources = [
    "source.amazon-ebs.build-agent-windows"
  ]

  provisioner "file" {
    source      = "HTML Help Workshop.zip"
    destination = "C:\\HTML Help Workshop.zip"
  }

  # Install MSYS/MinGW and any required packages.
  # Based on Docker installation instructions from https://www.msys2.org/docs/ci/

  provisioner "powershell" {
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "$ProgressPreference = 'SilentlyContinue';",

      "Invoke-WebRequest -UseBasicParsing -uri 'https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe' -OutFile msys2.exe",
      ".\\msys2.exe -y -oC:\\",
      "Remove-Item msys2.exe",

      "function msys() { C:\\msys64\\usr\\bin\\bash.exe @('-lc') + @Args; }",
      "msys ' '",
      "msys 'pacman --noconfirm -Syuu'",
      "msys 'pacman --noconfirm -Syuu'",
      "msys 'pacman --noconfirm -S base-devel git p7zip mingw-w64-{i686,x86_64}-{toolchain,wxWidgets,jansson,capstone,jbigkit,lua,lua-luarocks,libunistring}'",
      "msys 'pacman --noconfirm -Scc'",

      "msys 'perl -MCPAN -e \"install Template\"'",

      "function mingw32() { $env:MSYSTEM = 'MINGW32'; C:\\msys64\\usr\\bin\\bash.exe @('-lc') + @Args; Remove-Item Env:\\MSYSTEM }",
      "mingw32 'luarocks install busted'",

      "function mingw64() { $env:MSYSTEM = 'MINGW64'; C:\\msys64\\usr\\bin\\bash.exe @('-lc') + @Args; Remove-Item Env:\\MSYSTEM }",
      "mingw64 'luarocks install busted'",

      "Expand-Archive -Path 'C:\\HTML Help Workshop.zip' -DestinationPath 'C:\\Program Files (x86)'",
      "Remove-Item 'C:\\HTML Help Workshop.zip'",
    ]
  }

  # Install Buildkite Agent

  provisioner "powershell" {
    environment_vars = [
      "buildkiteAgentToken=${var.buildkite_agent_token}",
      "buildkiteAgentTags=queue=mingw-i686,queue=mingw-x86_64",
    ]

    inline = [
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/buildkite/agent/main/install.ps1'))",

      "New-Item -ItemType directory -Path C:\\buildkite-agent\\hooks",

      "Invoke-WebRequest -Uri 'https://nssm.cc/release/nssm-2.24.zip' -OutFile 'nssm-2.24.zip'",
      "Expand-Archive -Path nssm-2.24.zip -DestinationPath nssm-2.24",
      "Remove-Item nssm-2.24.zip",

      "Copy-Item nssm-2.24\\nssm-2.24\\win64\\nssm.exe C:\\buildkite-agent\\bin\\nssm.exe",
      "Remove-Item nssm-2.24 -Force -Recurse -ErrorAction SilentlyContinue",

      "C:\\buildkite-agent\\bin\\nssm.exe install 'Buildkite Agent' 'C:\\buildkite-agent\\buildkite-agent-run.bat'",
    ]
  }

  provisioner "file" {
    source      = "buildkite-environment-hook.bat"
    destination = "C:\\buildkite-agent\\hooks\\environment.bat"
  }

  provisioner "file" {
    source      = "buildkite-agent-run.bat"
    destination = "C:\\buildkite-agent\\buildkite-agent-run.bat"
  }

  # Secure WinRM when system shuts down

  provisioner "powershell" {
    inline = [
      "Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/DarwinJS/Undo-WinRMConfig/master/Undo-WinRMConfig.ps1')",
    ]
  }
}
