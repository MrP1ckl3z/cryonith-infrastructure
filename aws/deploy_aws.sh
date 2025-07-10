#!/bin/bash

# Cryonith LLC AWS Deployment Script
# Deploy organized infrastructure to AWS

set -e

echo "🚀 Starting Cryonith AWS Deployment..."

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
STACK_NAME=${STACK_NAME:-cryonith-production}
EC2_INSTANCE_TYPE=${EC2_INSTANCE_TYPE:-t3.medium}
KEY_NAME=${KEY_NAME:-cryonith-key}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install AWS CLI first."
    exit 1
fi

# Check AWS credentials
print_status "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

print_success "AWS credentials verified"

# Step 1: Create/Update DynamoDB tables
print_status "Setting up DynamoDB tables..."
if [ -f "dynamodb/setup_tables.sh" ]; then
    chmod +x dynamodb/setup_tables.sh
    ./dynamodb/setup_tables.sh
else
    print_warning "DynamoDB setup script not found, creating basic tables..."
    
    # Create basic trading tables
    aws dynamodb create-table \
        --table-name cryonith-trades \
        --attribute-definitions \
            AttributeName=id,AttributeType=S \
        --key-schema \
            AttributeName=id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region $AWS_REGION || print_warning "Table might already exist"
    
    aws dynamodb create-table \
        --table-name cryonith-portfolios \
        --attribute-definitions \
            AttributeName=user_id,AttributeType=S \
        --key-schema \
            AttributeName=user_id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region $AWS_REGION || print_warning "Table might already exist"
fi

print_success "DynamoDB tables configured"

# Step 2: Deploy EC2 instances
print_status "Deploying EC2 infrastructure..."

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*" \
    --query 'Images[0].ImageId' \
    --output text \
    --region $AWS_REGION)

print_status "Using AMI: $AMI_ID"

# Create security group
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name cryonith-sg \
    --description "Cryonith Trading Platform Security Group" \
    --query 'GroupId' \
    --output text \
    --region $AWS_REGION 2>/dev/null || \
    aws ec2 describe-security-groups \
    --group-names cryonith-sg \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $AWS_REGION)

print_status "Security Group: $SECURITY_GROUP_ID"

# Configure security group rules
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION 2>/dev/null || true

aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION 2>/dev/null || true

aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION 2>/dev/null || true

aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 5000 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION 2>/dev/null || true

aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 8000 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION 2>/dev/null || true

# Create EC2 instance
print_status "Launching EC2 instance..."

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type $EC2_INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP_ID \
    --user-data file://ec2/user_data.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cryonith-production}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region $AWS_REGION)

print_success "EC2 Instance launched: $INSTANCE_ID"

# Wait for instance to be running
print_status "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $AWS_REGION

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region $AWS_REGION)

print_success "Instance running at: $PUBLIC_IP"

# Step 3: Deploy Lambda functions (if any)
if [ -d "lambda" ] && [ "$(ls -A lambda)" ]; then
    print_status "Deploying Lambda functions..."
    cd lambda
    for func_dir in */; do
        if [ -d "$func_dir" ]; then
            func_name=$(basename "$func_dir")
            print_status "Deploying Lambda function: $func_name"
            cd "$func_dir"
            
            # Create deployment package
            zip -r "../${func_name}.zip" .
            cd ..
            
            # Deploy to Lambda
            aws lambda create-function \
                --function-name "cryonith-${func_name}" \
                --runtime python3.9 \
                --role arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/lambda-execution-role \
                --handler index.handler \
                --zip-file "fileb://${func_name}.zip" \
                --region $AWS_REGION || \
            aws lambda update-function-code \
                --function-name "cryonith-${func_name}" \
                --zip-file "fileb://${func_name}.zip" \
                --region $AWS_REGION
            
            rm "${func_name}.zip"
        fi
    done
    cd ..
    print_success "Lambda functions deployed"
fi

# Step 4: Output deployment information
print_success "🎉 AWS Deployment Complete!"
echo ""
echo "📊 Deployment Summary:"
echo "  • Region: $AWS_REGION"
echo "  • EC2 Instance: $INSTANCE_ID"
echo "  • Public IP: $PUBLIC_IP"
echo "  • Security Group: $SECURITY_GROUP_ID"
echo ""
echo "🔗 Access URLs:"
echo "  • SSH: ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP"
echo "  • API: http://$PUBLIC_IP:5000"
echo "  • Trading API: http://$PUBLIC_IP:8000"
echo ""
echo "📝 Next Steps:"
echo "  1. SSH into the instance and verify services"
echo "  2. Configure domain and SSL certificates"
echo "  3. Set up monitoring and alerts"
echo ""

# Save deployment info
cat > ../deployment_info.json << EOF
{
  "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aws_region": "$AWS_REGION",
  "ec2_instance_id": "$INSTANCE_ID",
  "public_ip": "$PUBLIC_IP",
  "security_group_id": "$SECURITY_GROUP_ID",
  "api_endpoints": {
    "main_api": "http://$PUBLIC_IP:5000",
    "trading_api": "http://$PUBLIC_IP:8000"
  }
}
EOF

print_success "Deployment info saved to deployment_info.json"
print_success "🚀 Cryonith AWS Infrastructure is ready!" 