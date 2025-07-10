#!/bin/bash

# AWS DynamoDB Setup for Cryonith LLC Trading Infrastructure
# Phase 1: Hybrid Data Backend

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 Setting up AWS DynamoDB for Cryonith LLC Trading Data${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${YELLOW}⚠️  AWS CLI not found. Install it first:${NC}"
    echo "curl 'https://awscli.amazonaws.com/AWSCLIV2.pkg' -o 'AWSCLIV2.pkg'"
    echo "sudo installer -pkg AWSCLIV2.pkg -target /"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${YELLOW}⚠️  AWS credentials not configured. Run: aws configure${NC}"
    exit 1
fi

REGION=${AWS_REGION:-us-east-1}
echo -e "${BLUE}📍 Using AWS Region: $REGION${NC}"

# 1. Trade Logs Table
echo -e "${GREEN}📊 Creating Ursus Trade Logs Table...${NC}"
aws dynamodb create-table \
    --table-name CryonithTradeLogs \
    --attribute-definitions \
        AttributeName=TradeId,AttributeType=S \
        AttributeName=Timestamp,AttributeType=S \
    --key-schema \
        AttributeName=TradeId,KeyType=HASH \
        AttributeName=Timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION \
    --tags Key=Project,Value=CryonithLLC Key=Environment,Value=Production \
    2>/dev/null || echo "Table CryonithTradeLogs already exists"

# 2. Strategy Metrics Table  
echo -e "${GREEN}🧠 Creating Strategy Metrics Table...${NC}"
aws dynamodb create-table \
    --table-name CryonithStrategyMetrics \
    --attribute-definitions \
        AttributeName=StrategyId,AttributeType=S \
        AttributeName=Timestamp,AttributeType=S \
    --key-schema \
        AttributeName=StrategyId,KeyType=HASH \
        AttributeName=Timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION \
    --tags Key=Project,Value=CryonithLLC Key=Environment,Value=Production \
    2>/dev/null || echo "Table CryonithStrategyMetrics already exists"

# 3. Market Signals Table
echo -e "${GREEN}📡 Creating Market Signals Table...${NC}"
aws dynamodb create-table \
    --table-name CryonithMarketSignals \
    --attribute-definitions \
        AttributeName=SignalId,AttributeType=S \
        AttributeName=Timestamp,AttributeType=S \
    --key-schema \
        AttributeName=SignalId,KeyType=HASH \
        AttributeName=Timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION \
    --tags Key=Project,Value=CryonithLLC Key=Environment,Value=Production \
    2>/dev/null || echo "Table CryonithMarketSignals already exists"

# 4. Performance Analytics Table
echo -e "${GREEN}📈 Creating Performance Analytics Table...${NC}"
aws dynamodb create-table \
    --table-name CryonithPerformance \
    --attribute-definitions \
        AttributeName=MetricType,AttributeType=S \
        AttributeName=Date,AttributeType=S \
    --key-schema \
        AttributeName=MetricType,KeyType=HASH \
        AttributeName=Date,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION \
    --tags Key=Project,Value=CryonithLLC Key=Environment,Value=Production \
    2>/dev/null || echo "Table CryonithPerformance already exists"

# Wait for tables to be active
echo -e "${BLUE}⏳ Waiting for tables to become active...${NC}"
for table in CryonithTradeLogs CryonithStrategyMetrics CryonithMarketSignals CryonithPerformance; do
    echo "Waiting for $table..."
    aws dynamodb wait table-exists --table-name $table --region $REGION
done

# Create IAM role for Pi access
echo -e "${GREEN}🔐 Creating IAM role for Pi access...${NC}"
cat > cryonith-pi-trust-policy.json << EOF
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

aws iam create-role \
    --role-name CryonithPiDataAccess \
    --assume-role-policy-document file://cryonith-pi-trust-policy.json \
    2>/dev/null || echo "Role CryonithPiDataAccess already exists"

# Create policy for DynamoDB access
cat > cryonith-pi-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:UpdateItem",
                "dynamodb:BatchWriteItem"
            ],
            "Resource": [
                "arn:aws:dynamodb:$REGION:*:table/Cryonith*"
            ]
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name CryonithPiDynamoDBAccess \
    --policy-document file://cryonith-pi-policy.json \
    2>/dev/null || echo "Policy already exists"

# Attach policy to role
aws iam attach-role-policy \
    --role-name CryonithPiDataAccess \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/CryonithPiDynamoDBAccess \
    2>/dev/null || echo "Policy already attached"

# Create access keys for Pi
echo -e "${GREEN}🔑 Creating access keys for Pi...${NC}"
aws iam create-user --user-name cryonith-pi-user 2>/dev/null || echo "User already exists"
aws iam attach-user-policy \
    --user-name cryonith-pi-user \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/CryonithPiDynamoDBAccess \
    2>/dev/null || echo "Policy already attached to user"

# Generate credentials
echo -e "${BLUE}📝 Generating Pi credentials...${NC}"
CREDENTIALS=$(aws iam create-access-key --user-name cryonith-pi-user --output json 2>/dev/null || echo '{"AccessKey":{"AccessKeyId":"EXISTS","SecretAccessKey":"EXISTS"}}')

# Output setup info
echo -e "${GREEN}✅ DynamoDB Setup Complete!${NC}"
echo ""
echo "🏗️  Tables Created:"
echo "   • CryonithTradeLogs - Trade execution logs"
echo "   • CryonithStrategyMetrics - Strategy performance data"  
echo "   • CryonithMarketSignals - Market analysis signals"
echo "   • CryonithPerformance - Daily/weekly analytics"
echo ""
echo "🔐 IAM Setup:"
echo "   • Role: CryonithPiDataAccess"
echo "   • User: cryonith-pi-user"
echo "   • Policy: CryonithPiDynamoDBAccess"
echo ""
echo "📊 Next Steps:"
echo "   1. Configure Pi with AWS credentials"
echo "   2. Deploy ursus_data_logger.py"
echo "   3. Set up Grafana dashboard"
echo ""

# Clean up temp files
rm -f cryonith-pi-trust-policy.json cryonith-pi-policy.json

echo -e "${YELLOW}💡 Save these credentials for Pi configuration:${NC}"
if [[ "$CREDENTIALS" != *"EXISTS"* ]]; then
    echo "$CREDENTIALS" | jq -r '"AWS_ACCESS_KEY_ID=" + .AccessKey.AccessKeyId'
    echo "$CREDENTIALS" | jq -r '"AWS_SECRET_ACCESS_KEY=" + .AccessKey.SecretAccessKey'
    echo "AWS_REGION=$REGION"
fi 