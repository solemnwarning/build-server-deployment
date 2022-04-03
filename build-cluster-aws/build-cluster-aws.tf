terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"

  backend "s3" {
    bucket         = "build-cluster-state"
    region         = "us-east-2"
    key            = "build-cluster-state"
    dynamodb_table = "build-cluster-lock"
  }
}

provider "aws" {
  profile = "default"
  region  = "us-east-2"
}

resource "aws_vpc" "build_cluster_vpc" {
  cidr_block = "172.16.0.0/22"

  tags = {
    Name = "build-cluster-vpc"
  }
}

resource "aws_internet_gateway" "build_cluster_gateway" {
  vpc_id = aws_vpc.build_cluster_vpc.id

  tags = {
    Name = "build-cluster-gateway"
  }
}

resource "aws_default_route_table" "build_cluster_routes" {
  default_route_table_id = aws_vpc.build_cluster_vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.build_cluster_gateway.id
  }

  tags = {
    Name = "build-cluster-routes"
  }
}

# Subnet for instances that need access to the HTTP proxy/cache.
# Proxy is on 172.16.0.4:8080

resource "aws_subnet" "build_cluster_proxy" {
  vpc_id            = aws_vpc.build_cluster_vpc.id
  cidr_block        = "172.16.0.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "build-cluster-proxy"
  }
}

# build-cluster-manager is a constantly-running instance that runs a HTTP
# proxy/cache for repeated downloads (e.g. deb/rpm build dependencies) and
# handles on-demand scaling of the build agent spot fleets.

data "aws_ami" "build_cluster_manager" {
  most_recent = true

  filter {
    name   = "name"
    values = ["build-cluster-manager-master-*"]
  }

  owners = ["self"]
}

resource "aws_instance" "build_cluster_manager" {
  ami           = data.aws_ami.build_cluster_manager.id
  instance_type = "t4g.micro"

  tags = {
    Name = "build-cluster-manager"
  }

  subnet_id = aws_subnet.build_cluster_proxy.id
  private_ip = "172.16.0.4"

  associate_public_ip_address = true
  key_name = "solemnwarning@infinity"
}

# build-agent-copr spot request fleet, scaled by build-cluster-manager.

data "aws_ami" "build_agent_copr" {
  most_recent = true

  filter {
    name   = "name"
    values = ["build-agent-copr-master-*"]
  }

  owners = ["self"]
}

resource "aws_spot_fleet_request" "copr" {
  iam_fleet_role  = "arn:aws:iam::652694334613:role/aws-service-role/spotfleet.amazonaws.com/AWSServiceRoleForEC2SpotFleet"
  target_capacity = 0

  # terminate_instances = true
  terminate_instances_with_expiration = true

  tags = {
    buildkite-agent-meta-data = "queue=copr-cli"
    buildkite-agent-spawn     = "4"

    buildkite-scaler-min-instances = "0"
    buildkite-scaler-max-instances = "1"
    buildkite-scaler-enable        = "1"
  }

  launch_specification {
    ami           = data.aws_ami.build_agent_copr.id
    instance_type = "c5a.large"

    subnet_id = aws_subnet.build_cluster_proxy.id

    associate_public_ip_address = true
    key_name = "solemnwarning@infinity"
  }
}

# build-agent-debian spot request fleet, scaled by build-cluster-manager.

data "aws_ami" "build_agent_debian" {
  most_recent = true

  filter {
    name   = "name"
    values = ["build-agent-debian-master-*"]
  }

  owners = ["self"]
}

resource "aws_spot_fleet_request" "debian" {
  iam_fleet_role  = "arn:aws:iam::652694334613:role/aws-service-role/spotfleet.amazonaws.com/AWSServiceRoleForEC2SpotFleet"
  target_capacity = 0

  # terminate_instances = true
  terminate_instances_with_expiration = true

  tags = {
    buildkite-agent-meta-data = "queue=linux-generic,queue=linux-debian"
    buildkite-agent-spawn     = "1"

    buildkite-scaler-min-instances = "0"
    buildkite-scaler-max-instances = "4"
    buildkite-scaler-enable        = "1"
  }

  launch_specification {
    ami           = data.aws_ami.build_agent_debian.id
    instance_type = "c5a.xlarge"

    subnet_id = aws_subnet.build_cluster_proxy.id

    associate_public_ip_address = true
    key_name = "solemnwarning@infinity"
  }
}

# build-agent-freebsd spot request fleet, scaled by build-cluster-manager.

data "aws_ami" "build_agent_freebsd" {
  most_recent = true

  filter {
    name   = "name"
    values = ["build-agent-freebsd-master-*"]
  }

  owners = ["self"]
}

resource "aws_spot_fleet_request" "freebsd" {
  iam_fleet_role  = "arn:aws:iam::652694334613:role/aws-service-role/spotfleet.amazonaws.com/AWSServiceRoleForEC2SpotFleet"
  target_capacity = 0

  # terminate_instances = true
  terminate_instances_with_expiration = true

  tags = {
    buildkite-agent-meta-data = "queue=freebsd-amd64"
    buildkite-agent-spawn     = "1"

    buildkite-scaler-min-instances = "0"
    buildkite-scaler-max-instances = "2"
    buildkite-scaler-enable        = "1"
  }

  launch_specification {
    ami           = data.aws_ami.build_agent_freebsd.id
    instance_type = "c5a.xlarge"

    subnet_id = aws_subnet.build_cluster_proxy.id

    associate_public_ip_address = true
    key_name = "solemnwarning@infinity"
  }
}

# build-agent-ipxtester spot request fleet, scaled by build-cluster-manager.

data "aws_ami" "build_agent_ipxtester" {
  most_recent = true

  filter {
    name   = "name"
    values = ["build-agent-ipxtester-master-*"]
  }

  owners = ["self"]
}

resource "aws_spot_fleet_request" "ipxtester" {
  iam_fleet_role  = "arn:aws:iam::652694334613:role/aws-service-role/spotfleet.amazonaws.com/AWSServiceRoleForEC2SpotFleet"
  target_capacity = 0

  # terminate_instances = true
  terminate_instances_with_expiration = true

  tags = {
    buildkite-agent-meta-data = "queue=ipxwrapper-test"
    buildkite-agent-spawn     = "6"

    buildkite-scaler-min-instances = "0"
    buildkite-scaler-max-instances = "1"
    buildkite-scaler-enable        = "1"
  }

  launch_specification {
    ami           = data.aws_ami.build_agent_ipxtester.id
    instance_type = "m5.metal"

    subnet_id = aws_subnet.build_cluster_proxy.id

    associate_public_ip_address = true
    key_name = "solemnwarning@infinity"
  }
}


# build-agent-windows spot request fleet, scaled by build-cluster-manager.

data "aws_ami" "build_agent_windows" {
  most_recent = true

  filter {
    name   = "name"
    values = ["build-agent-windows-master-*"]
  }

  owners = ["self"]
}

resource "aws_spot_fleet_request" "windows" {
  iam_fleet_role  = "arn:aws:iam::652694334613:role/aws-service-role/spotfleet.amazonaws.com/AWSServiceRoleForEC2SpotFleet"
  target_capacity = 0

  # terminate_instances = true
  terminate_instances_with_expiration = true

  tags = {
    buildkite-agent-meta-data = "queue=mingw-i686,queue=mingw-x86_64"
    buildkite-agent-spawn     = "1"

    buildkite-scaler-min-instances = "0"
    buildkite-scaler-max-instances = "2"
    buildkite-scaler-enable        = "1"
  }

  launch_specification {
    ami           = data.aws_ami.build_agent_windows.id
    instance_type = "c5a.xlarge"

    subnet_id = aws_subnet.build_cluster_proxy.id

    associate_public_ip_address = true
  }
}
