variable "application_name" {
  type    = string
  default = "Coder"
}

variable "application_version" {
  type    = string
  default = "1.28.2${env("RELEASE_EXTRA")}"
}

variable "apt_packages" {
  type    = string
  default = "apt-transport-https ca-certificates curl jq linux-image-extra-virtual software-properties-common "
}

variable "aws_access_key" {
  type    = string
  default = "${env("AWS_ACCESS_KEY")}"
  sensitive = true
}

variable "aws_region" {
  type    = string
  default = "${env("AWS_REGION")}"
}

variable "aws_secret_key" {
  type    = string
  default = "${env("AWS_SECRET_KEY")}"
  sensitive = true
}

variable "do_api_token" {
  type      = string
  default   = "${env("DIGITALOCEAN_API_TOKEN")}"
  sensitive = true
}

variable "docker_compose_version" {
  type    = string
  default = "1.29.2"
}

variable "ami_groups" {
  type    = string
  default = "${env("AWS_AMI_GROUPS")}"
}

variable "image_name" {
  type    = string
  default = "coder-20-04-${env("RELEASE_EXTRA")}"
}

# The amazon-ami data block is generated from your amazon builder source_ami_filter; a data
# from this block can be referenced in source and locals blocks.
# Read the documentation for data blocks here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/data
# Read the documentation for the Amazon AMI Data Source here:
# https://www.packer.io/docs/datasources/amazon/ami
data "amazon-ami" "aws1" {
  access_key = "${var.aws_access_key}"
  filters = {
    name                = "ubuntu/images/*ubuntu-focal-20.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "${var.aws_region}"
  secret_key  = "${var.aws_secret_key}"
}

# source blocks are generated from your builders; a source can be referenced in
# build blocks. A build block runs provisioner and post-processors on a
# source. Read the documentation for source blocks here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/source
source "amazon-ebs" "aws1" {
  access_key    = "${var.aws_access_key}"
  ami_name      = "${var.image_name}"
  # ami_groups    = ["${var.ami_groups}"]
  ami_description = "${var.application_name} ${var.application_version}: Provision remote dev environments with support for VS Code, JetBrains, SSH, Jupyter, and more. "
  instance_type = "t2.micro"
  region        = "${var.aws_region}"
  secret_key    = "${var.aws_secret_key}"
  source_ami    = "${data.amazon-ami.aws1.id}"
  ssh_username  = "ubuntu"
  tags          = {
    Name = "${var.application_name}"
  }
}

source "digitalocean" "digitalocean1" {
  api_token     = "${var.do_api_token}"
  image         = "ubuntu-20-04-x64"
  region        = "nyc3"
  size          = "s-1vcpu-1gb"
  snapshot_name = "${var.image_name}"
  ssh_username  = "root"
}

# a build block invokes sources and runs provisioning steps on them. The
# documentation for build blocks can be found here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/build
build {
  sources = ["source.amazon-ebs.aws1", "source.digitalocean.digitalocean1"]

  provisioner "shell" {
    inline = ["cloud-init status --wait"]
  }

  provisioner "shell" {
    inline           = ["mkdir -p /tmp/packer"]
  }
  
  provisioner "file" {
    destination = "/tmp/packer/var/"
    source      = "files/var/"
    only        = ["digitalocean"]
  }

  provisioner "file" {
    destination = "/tmp/packer/etc/"
    source      = "files/etc/"
  }


  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "LC_ALL=C", "LANG=en_US.UTF-8", "LC_CTYPE=en_US.UTF-8"]
    inline           = ["apt -qqy update", "apt -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' full-upgrade", "apt -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install ${var.apt_packages}", "apt-get -qqy clean"]
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} {{ .Path }}"
  }


  provisioner "shell" {
    inline           = ["rsync -a  /tmp/packer/ / && rm -rf /tmp/packer/"]
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} {{ .Path }}"
  }

  provisioner "shell" {
    environment_vars = ["application_name=${var.application_name}", "application_version=${var.application_version}", "docker_compose_version=${var.docker_compose_version}", "DEBIAN_FRONTEND=noninteractive", "LC_ALL=C", "LANG=en_US.UTF-8", "LC_CTYPE=en_US.UTF-8"]
    scripts          = ["files/scripts/010-docker.sh", "files/scripts/011-docker-compose.sh", "files/scripts/012-grub-opts.sh", "files/scripts/013-docker-dns.sh", "files/scripts/014-ufw-docker.sh", "files/scripts/015-coder.sh"]
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} {{ .Path }}"
  }

  provisioner "shell" {
    environment_vars = ["application_name=${var.application_name}", "application_version=${var.application_version}", "docker_compose_version=${var.docker_compose_version}", "DEBIAN_FRONTEND=noninteractive", "LC_ALL=C", "LANG=en_US.UTF-8", "LC_CTYPE=en_US.UTF-8"]
    scripts          = ["files/scripts/020-application-tag.sh"]
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} {{ .Path }}"
    only             = ["digitalocean"]
  }

  provisioner "shell" {
    environment_vars = ["application_name=${var.application_name}", "application_version=${var.application_version}", "docker_compose_version=${var.docker_compose_version}", "DEBIAN_FRONTEND=noninteractive", "LC_ALL=C", "LANG=en_US.UTF-8", "LC_CTYPE=en_US.UTF-8"]
    scripts          = ["files/scripts/900-cleanup.sh"]
    execute_command  = "echo 'packer' | sudo -S env {{ .Vars }} {{ .Path }}"
  }

}
