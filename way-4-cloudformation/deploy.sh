#! /bin/bash -x
if [ -z $1 ] || [ -z $2 ];
then
  echo Usage: deploy.sh [stack-name] [region]
  exit 1 
fi

aws cloudformation create-stack --stack-name $1 \
                                --region $2 \
                                --template-body file://eks.yaml \
                                --capabilities CAPABILITY_NAMED_IAM
aws cloudformation create-stack --stack-name $1-ng \
                                --parameters ParameterKey=ClusterStack,ParameterValue=$1 \
                                --region $2 \
                                --template-body file://ng.yaml \
                                --capabilities CAPABILITY_NAMED_IAM
