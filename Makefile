# all: run

# This makefile contains some convenience commands for deploying and publishing our
# cloudformation scripts.

# For example, to build and run the entire infrastructure, just run:
# $ make

# or to deploy just a section, , run:
# $ make :vpc stack-name=ttg-web

stack-name ?= ttg-ecs
base-name ?= 626810777133
bucket-name = $(base-name)-$(stack-name)-s3
s3-stack = $(stack-name)-s3

default:
	$(call blue, "Basic test. ctrl-C if this stalls as that means its not finding our resources.")
	$(call blue, "Checking if our S3 bucket s3://$(bucket-name) is present")
	@aws s3api wait bucket-exists --bucket $(bucket-name)
	$(call blue, "Found it.")

show-profile:
	aws iam get-user

install-aws:
	# make sure python is installed on your machine
	# see http://docs.aws.amazon.com/cli/latest/userguide/installing.html
	pip install awscli --upgrade --user

configure-profile: install-aws
	# configure your profile (we'll call it cf-course):
	aws configure --profile default

# S3 Bucket creation!

create-bucket:
	# Create our bucket using our stack formation script
	# The initial dash tells make to ignore the creation error if it already exists.
	$(call blue, "Create our S3 bucket s3://$(bucket-name).  It will fails if it already exists.")
	-aws cloudformation create-stack \
		--stack-name $(s3-stack) \
		--template-body file://infrastructure\s3.yaml \
		--parameters \	
			ParameterKey=EnvironmentName,ParameterValue=dev \
			ParameterKey=BucketName,ParameterValue=$(bucket-name) \
		--profile default \
		--region us-east-1

load-bucket: create-bucket
	$(call blue, "Upload our cloud-formation scripts to s3://$(bucket-name)/infrastructure")
	aws s3api wait bucket-exists --bucket $(bucket-name)
	aws s3 sync ./infrastructure s3://$(bucket-name)/infrastructure --acl private

# VPC creation!

create-vpc:
	$(call blue, "Create our VPC infrastructure.")
	aws cloudformation create-stack \
		--stack-name $(stack-name)-vpc \
		--template-body file://infrastructure\vpc.yaml \
		--parameters \
			ParameterKey=EnvironmentName,ParameterValue=$(stack-name) \
			ParameterKey=VpcCIDR,ParameterValue=10.180.0.0/16 \
			ParameterKey=PublicSubnet1CIDR,ParameterValue=10.180.8.0/21 \
			ParameterKey=PublicSubnet2CIDR,ParameterValue=10.180.16.0/21 \
			ParameterKey=PrivateSubnet1CIDR,ParameterValue=10.180.24.0/21 \
			ParameterKey=PrivateSubnet2CIDR,ParameterValue=10.180.32.0/21 \
		--profile default \
		--region us-east-1

remove-vpc: remove-sg
	aws cloudformation delete-stack --stack-name $(stack-name)-vpc

# Security Group creation!

create-sg:
	$(call blue, "Create our Security Groups")
	aws cloudformation create-stack \
		--stack-name $(stack-name)-sg \
		--template-body file://infrastructure\security-groups.yaml \
		--parameters \
			ParameterKey=EnvironmentName,ParameterValue=$(stack-name) \
		--profile default \
		--region us-east-1

remove-sg:
	aws cloudformation delete-stack --stack-name $(stack-name)-elb

# ELB Creation

create-alb:
	$(call blue, "Create our Application Load Balancer")
	aws cloudformation create-stack \
		--stack-name $(stack-name)-alb \
		--template-body file://infrastructure\load-balancers.yaml \
		--parameters \
			ParameterKey=EnvironmentName,ParameterValue=$(stack-name) \
		--profile default \
		--region us-east-1

remove-alb:
	aws cloudformation delete-stack --stack-name $(stack-name)-alb

# ECS Creation

deploy-ecs:
	$(call blue, "Deploying our ECS stack...")
	-aws cloudformation create-stack \
		--stack-name $(stack-name)-ecs \
		--template-body file://infrastructure\ecs-cluster.yaml \
		--parameters \
			ParameterKey=EnvironmentName,ParameterValue=$(stack-name) \
		--profile default \
		--region us-east-1 \
		--capabilities CAPABILITY_NAMED_IAM

remove-ecs:
	aws cloudformation delete-stack --stack-name $(stack-name)-ecs

image: binary
	$(call blue, "Building docker image...")
	docker build -t ${name}:${version} .
	$(MAKE) clean

run:
	$(call blue, "Testing run...")
	@echo "$(name)"
	@echo "$(stack-name)"

	# docker run -i -t --rm -p 8001:8001 ${name}:${version} 

publish:  
	$(call blue, "Publishing Docker image to registry...")
	docker tag ${name}:latest ${registry}/${name}:${version}
	docker push ${registry}/${name}:${version} 

clean: remove-bucket

remove-bucket:
	aws s3 rm s3://$(bucket-name)-s3/infrastructure
	aws cloudformation delete-stack --stack-name $(s3-stack)

define blue
	@tput setaf 6
	@echo $1
	@tput setaf 7
endef
