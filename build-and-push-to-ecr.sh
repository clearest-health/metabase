#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="584641603422"
ECR_REPOSITORY="metabase"
IMAGE_TAG="${1:-latest}"
MB_VERSION="${2:-v0.50.0}"
MB_EDITION="${3:-oss}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting Metabase Docker build and ECR deployment...${NC}"
echo -e "   Image Tag: ${IMAGE_TAG}"
echo -e "   Version: ${MB_VERSION}"
echo -e "   Edition: ${MB_EDITION}"
echo ""

# Step 1: Ensure ECR repository exists
echo -e "${YELLOW}📦 Checking ECR repository...${NC}"
if aws ecr describe-repositories --region $AWS_REGION --repository-names $ECR_REPOSITORY 2>/dev/null; then
    echo -e "${GREEN}✓ Repository exists${NC}"
else
    echo -e "${YELLOW}Creating repository...${NC}"
    aws ecr create-repository --region $AWS_REGION --repository-name $ECR_REPOSITORY
    echo -e "${GREEN}✓ Repository created${NC}"
fi

# Step 2: Check if image already exists locally
echo -e "${YELLOW}🔍 Checking for existing local image...${NC}"
if docker images | grep -q "^${ECR_REPOSITORY}.*${IMAGE_TAG}"; then
    echo -e "${GREEN}✓ Found existing image locally${NC}"
    read -p "Do you want to rebuild the image? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Skipping build, using existing image${NC}"
    else
        echo -e "${YELLOW}🔨 Building Docker image (this may take 15-30 minutes)...${NC}"
        DOCKER_BUILDKIT=1 docker build \
          --build-arg MB_EDITION=$MB_EDITION \
          --build-arg VERSION=$MB_VERSION \
          -t $ECR_REPOSITORY:$IMAGE_TAG \
          --progress=plain \
          .
        echo -e "${GREEN}✓ Build completed${NC}"
    fi
else
    echo -e "${YELLOW}🔨 Building Docker image (this may take 15-30 minutes)...${NC}"
    DOCKER_BUILDKIT=1 docker build \
      --build-arg MB_EDITION=$MB_EDITION \
      --build-arg VERSION=$MB_VERSION \
      -t $ECR_REPOSITORY:$IMAGE_TAG \
      --progress=plain \
      .
    echo -e "${GREEN}✓ Build completed${NC}"
fi

# Step 3: Authenticate with ECR
echo -e "${YELLOW}🔐 Authenticating with AWS ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | \
docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
echo -e "${GREEN}✓ Authentication successful${NC}"

# Step 4: Tag and push
echo -e "${YELLOW}🏷️  Tagging image...${NC}"
docker tag $ECR_REPOSITORY:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG
echo -e "${GREEN}✓ Image tagged${NC}"

echo -e "${YELLOW}📤 Pushing to ECR...${NC}"
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG
echo -e "${GREEN}✓ Push completed${NC}"

# Step 5: Display image info
echo ""
echo -e "${GREEN}✅ Successfully deployed to ECR!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "📍 Image URI: ${GREEN}$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG${NC}"

# Get image size
IMAGE_SIZE=$(aws ecr describe-images --region $AWS_REGION --repository-name $ECR_REPOSITORY \
  --image-ids imageTag=$IMAGE_TAG --query 'imageDetails[0].imageSizeInBytes' --output text 2>/dev/null || echo "0")

if [ "$IMAGE_SIZE" != "0" ]; then
    IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))
    echo -e "📦 Image Size: ${IMAGE_SIZE_MB} MB"
fi

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Usage examples:"
echo "  ./build-and-push-to-ecr.sh                    # Build latest with v0.50.0"
echo "  ./build-and-push-to-ecr.sh v1.0 v0.51.0       # Build v1.0 tag with v0.51.0"
echo "  ./build-and-push-to-ecr.sh latest v0.50.0 ee  # Build enterprise edition"
