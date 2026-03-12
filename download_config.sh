#!/bin/bash
set -e

echo "=== Downloading Terraform Files from S3 ==="
echo ""

# Find the S3 bucket
echo "Looking for S3 bucket..."
BUCKET_NAME=$(aws s3 ls | grep selenium-prod | awk '{print $3}')

if [ -z "$BUCKET_NAME" ]; then
  echo "ERROR: Could not find S3 bucket!"
  echo "Make sure Stage 1 was deployed successfully."
  exit 1
fi

echo "Found bucket: $BUCKET_NAME"
echo ""

# Download terraform files
echo "Downloading terraform-files.tar.gz..."
aws s3 cp s3://$BUCKET_NAME/stage2/terraform-files.tar.gz .

if [ ! -f terraform-files.tar.gz ]; then
  echo "ERROR: Download failed!"
  echo ""
  echo "Make sure you uploaded the files from your laptop:"
  echo "  tar -czf terraform-files.tar.gz *.tf scripts/ data/ terraform.tfvars"
  echo "  aws s3 cp terraform-files.tar.gz s3://$BUCKET_NAME/stage2/"
  exit 1
fi

# Extract
echo "Extracting files..."
tar -xzf terraform-files.tar.gz

# Verify
echo ""
echo "Files extracted successfully:"
ls -lh *.tf

echo ""
echo "=== Next Steps ==="
echo "1. Set Wiz credentials:"
echo "   export WIZ_CLIENT_ID=\"your-client-id\""
echo "   export WIZ_CLIENT_SECRET=\"your-client-secret\""
echo ""
echo "2. Update terraform.tfvars:"
echo "   deployment_stage = \"stage2\""
echo "   create_bastion_host = false"
echo ""
echo "3. Deploy Stage 2:"
echo "   terraform init"
echo "   terraform apply"
echo ""
echo "4. After EKS is created, configure kubectl:"
echo "   ./setup_stage2.sh"

