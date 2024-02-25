#! /bin/sh -f
## Create an EKS cluster witha NodeGroup using AWS CLI v2
if [ -z "${AWS_REGION" ]; then
   echo "AWS_REGION is unset or empty"
   exit 1
fi
#create VPC
aws cloudformation create-stack --stack-name Way2VPC \
    --region $AWS_REGION \
    --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml

WORKING=1
until [ $WORKING == 0 ];
do 
  aws cloudformation describe-stacks --stack-name Way2VPC \
    --region eu-central-1 \
    --query 'Stacks[*].StackStatus' | grep "CREATE_COMPLETE"
  WORKING = $?
done
# Create policy
cat >eks-cluster-role-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
# Create IAM Role
aws iam create-role --role-name Way2EKSClusterRole --assume-role-policy-document file://"eks-cluster-role-trust-policy.json"
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name Way2EKSClusterRole

export REGION=$AWS_REGION
export CLUSTERNAME=way2
export K8S_VERSION=1.29
export ROLE_ARN=$(aws iam get-role --role-name Way2EKSClusterRole --query 'Role.Arn' --output text)
export SECURITY_GROUP=$(aws cloudformation describe-stacks --stack-name Way2VPC --region eu-central-1 --query 'Stacks[*].Outputs[?OutputKey==`SecurityGroups`].OutputValue | [0] | [0]' --output text)
export SUBNET_IDS=$(aws cloudformation describe-stacks --stack-name Way2VPC --region eu-central-1 --query 'Stacks[*].Outputs[?OutputKey==`SubnetIds`].OutputValue | [0] | [0]' --output text)
aws eks create-cluster --region $REGION \
  --name $CLUSTERNAME \
  --kubernetes-version $K8S_VERSION \
  --role-arn $ROLE_ARN \
  --resources-vpc-config subnetIds=$SUBNET_IDS,securityGroupIds=$SECURITY_GROUP

ACTIVE=1

until [ $ACTIVE = 0 ];
do
  aws eks describe-cluster --region $REGION --name $CLUSTERNAME --query "cluster.status" | grep "ACTIVE"
  ACTIVE = $?
done

aws eks update-kubeconfig --region $REGION --name  $CLUSTERNAME

# Create NodeGroup
## Role
cat >node-role-trust-relationship.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

export NODE_ROLE_NAME=Way2EKSNodeRole
aws iam create-role \
  --role-name $NODE_ROLE_NAME \
  --assume-role-policy-document file://"node-role-trust-relationship.json"
aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
  --role-name $NODE_ROLE_NAME
aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
  --role-name $NODE_ROLE_NAME
aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
  --role-name $NODE_ROLE_NAME

export SUBNET_IDS=$(echo $SUBNET_IDS | tr ',' ' ')

export NODE_ROLE_ARN=$(aws iam get-role --role-name $NODE_ROLE_NAME --query 'Role.Arn' --output text)
# The group itself
aws eks create-nodegroup --cluster-name $CLUSTERNAME \
--nodegroup-name Way2NodeGroup \
--subnets subnet-05093c7f5ffd9227d subnet-0c3871d7e909fbb0d subnet-098075cc435686217 subnet-0b5940fcf21e402ad \
--node-role arn:aws:iam::117473350851:role/Way2EKSNodeRole \
--region $REGION

