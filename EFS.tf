#---------------------------------selecting our region for instance---------------------------------------------------------------
provider "aws" {
region = "ap-south-1"
profile = "lekhika"
}

#-----------------------------------creating key-------------------------------------------------------------------------------------
resource "aws_key_pair" "taskkey1" {
key_name = "taskkey1"
public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDvLGoUhVxILq6u3C5Ffl2aJMnOAizwGlwlSkxN2mbcE17F8xKZ0NgEOhsuMPHT81t0hYcr7JNrDoyycEcHVo2s+l2u1mDSi0qMFlrY4LCEhr2m0bbEljGIjAJK4Zd1O3chM+WLXmWT6R0030vGGiEXnhvFIv/BShAQDEbUhSgMMbprdrCoaswWguCYQ2rfwBMHrEQazluIb9BFP8z5ed4FEPpudSxYpho2PDLhY6bxLIG4P1zY+v8Ix9W9KmxEWVjEVYiIMcA5DlnylHNcE5t8N3i7pQGrb1clUdq9q/5r12NXxweMmgae5/WAEo8wcObMrS7n2ERlACYyERLX1MOr"
}
#------------------------------------------launching vpc------------------------------------------------------------------------
resource "aws_vpc" "my_vpc" {
  cidr_block       = "192.168.0.0/16"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"
  instance_tenancy = "default"


  tags = {
    Name = "lekhikavpc"
}
  }
  
resource "aws_subnet" "vpc_subnet" {
  vpc_id     = "${aws_vpc.my_vpc.id}"
  cidr_block = "192.168.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone = "ap-south-1a"
  tags = {
    Name = "lekhikasub1"
  
}
}
resource "aws_internet_gateway" "inter_gateway" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my_ig"
  }
}

resource "aws_route_table" "rt_tb" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    
gateway_id = aws_internet_gateway.inter_gateway.id
    cidr_block = "0.0.0.0/0"
  }

    tags = {
    Name = "myroute-table"
  }
}

resource "aws_route_table_association" "rt_associate" {
  subnet_id      = aws_subnet.vpc_subnet.id
  route_table_id = aws_route_table.rt_tb.id
}
#----------------------------------creating security group----------------------------------------------------------------------------
resource "aws_security_group" "security" {
name = "security"
description = "allow NFS"
vpc_id = aws_vpc.my_vpc.id

	ingress {
	description = "SSH"
	from_port = 22
	to_port = 22
	protocol = "tcp"
	cidr_blocks = [ "0.0.0.0/0" ]
	}
	ingress {
	description = "EFS"
	from_port = 2049
	to_port = 2049
	protocol = "tcp"
	cidr_blocks = [ "0.0.0.0/0" ]
	}
	ingress {
	description = "HTTP"
	from_port = 80
	to_port = 80
	protocol = "tcp"
	cidr_blocks = [ "0.0.0.0/0" ]
	}
	egress {
	from_port = 0
	to_port = 0
	protocol = "-1"
	cidr_blocks = ["0.0.0.0/0"]
	}
	tags = {
	Name = "security"
	}
}



#------------------------------------------launching eFS volume------------------------------------------------------------------------

resource "aws_efs_file_system" "new_efs" {
creation_token = "efs"

tags = {
Name = "efs_vloume"
}
}


resource "aws_efs_mount_target" "mount_EFS" {
file_system_id = aws_efs_file_system.new_efs.id
subnet_id = aws_subnet.vpc_subnet.id
security_groups = [ aws_security_group.security.id ]
}


#--------------------------------creating s3-------------------------------------------------------------------------
resource "aws_s3_bucket" "b" {
	  bucket = "lekhhikabalti"
	  acl    = "private"
	  tags = {
		Name = "My bucket"
	  }
}


locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Some comment"
}
resource "aws_instance" "lekinst" {
	ami = "ami-0447a12f28fddb066"
	instance_type = "t2.micro"
	availability_zone = "ap-south-1a"
	key_name = "taskkey1"
	subnet_id = aws_subnet.vpc_subnet.id
    vpc_security_group_ids = [ aws_security_group.security.id ]

	user_data = <<-EOF

	   #!/bin/bash
        sleep 5m
        sudo su - root
        # Install AWS EFS Utilities
        yum install -y amazon-efs-utils
        # Mount EFS
        mkdir /efs
        efs_id="${aws_efs_file_system.new_efs.id}"
        mount -t efs "${aws_efs_file_system.new_efs.id}":/ /var/www/html
        # Edit fstab so EFS automatically loads on reboot
        echo $efs_id:/ /efs efs defaults,_netdev 0 0 >> /etc/fstab
        sudo yum install httpd -y
        sudo systemctl start httpd
        sudo systemctl enable httpd
        sudo yum install git -y
	   git clone https://github.com/lekhika13/awscloud.git
	EOF
	tags = {
	Name = "lekinst"
	}
}

#----------------------------------creating code pipeline------------------------------------------------------------------
resource "aws_iam_role" "codepipeline_role" {
  name = "test-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = "${aws_iam_role.codepipeline_role.id}"

 policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.b.arn}",
        "${aws_s3_bucket.b.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_codepipeline" "codepipeline" {
  name     = "tf-test-pipeline"
  role_arn = "${aws_iam_role.codepipeline_role.arn}"


   artifact_store {
    location = "${aws_s3_bucket.b.bucket}"
    type     = "S3"
	}
	 
	 stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["SourceArtifact"]


      configuration = {
        Owner  = "lekhika13"
        Repo   = "awscloud"
        Branch = "master"
		OAuthToken = "70a27f8906e0ca643cc401d95b35211e88d288df"
        
      }
    }
  }

 

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      input_artifacts = ["SourceArtifact"]
      version         = "1"

      configuration = {
        BucketName = "${aws_s3_bucket.b.bucket}"
        Extract = "true"
      }
    }
  }
}

#----------------------------------------------creating web distribution---------------------------------------------------------------
resource "aws_cloudfront_distribution" "s3_distribution" {
		  origin {
			domain_name = "${aws_s3_bucket.b.bucket_regional_domain_name}"
			origin_id   = "${local.s3_origin_id}"

			s3_origin_config {
			  origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
				}
			}


		  enabled             = true
		  is_ipv6_enabled     = true
		  comment             = "Some comment"
		


		  default_cache_behavior {
				allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
				cached_methods   = ["GET", "HEAD"]
				target_origin_id = "${local.s3_origin_id}"

				forwarded_values {
				  query_string = false

				  cookies {
					forward = "none"
				  }
				}

				viewer_protocol_policy = "allow-all"
				
		  }
			restrictions {
			geo_restriction {
			  restriction_type = "whitelist"
			  locations        = ["US", "CA", "GB", "IN"]
			}
			}

		  tags = {
			Environment = "production"
			}

		  viewer_certificate {
			cloudfront_default_certificate = true
		  }
}
 

