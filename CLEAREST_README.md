# Metabase Docker Build & AWS ECR Deployment Guide

## Prerequisites

- Docker installed and running (Docker Desktop or OrbStack)
- AWS CLI configured with appropriate credentials
- Access to AWS ECR in us-east-1 region

## Quick Start

### 1. Create ECR Repository (if not exists)

```bash
# Check if repository exists, create if it doesn't
aws ecr describe-repositories --region us-east-1 --repository-names metabase || \
aws ecr create-repository --region us-east-1 --repository-name metabase
```

### 2. Build Docker Image

The Metabase repository includes a multi-stage Dockerfile that builds the entire application from source.

```bash
# Navigate to the repository root
cd metabase

# Build the Docker image for production (AMD64 architecture, takes ~15-30 minutes)
DOCKER_BUILDKIT=1 docker build \
  --platform linux/amd64 \
  --build-arg MB_EDITION=ee \
  --build-arg VERSION=v1.55.10.6 \
  -t metabase:latest .
```

**Build Arguments:**

- `MB_EDITION`: Edition to build (`oss` for open source, `ee` for enterprise)
- `VERSION`: Version tag (e.g., `v0.50.0`) - **Required when building from source**. Use a semantic version format
- `--platform linux/amd64`: **Required for production** - ensures compatibility with x86_64 servers

### 3. Authenticate with AWS ECR

```bash
# Get ECR login token and authenticate Docker
aws ecr get-login-password --region us-east-1 | \
docker login --username AWS --password-stdin 584641603422.dkr.ecr.us-east-1.amazonaws.com
```

### 4. Tag and Push to ECR

```bash
# Tag the image for ECR
docker tag metabase:latest 584641603422.dkr.ecr.us-east-1.amazonaws.com/metabase:latest

# Push to ECR
docker push 584641603422.dkr.ecr.us-east-1.amazonaws.com/metabase:latest
```

## Complete Build Commands

Here are the complete commands for building and pushing to ECR:

```bash
# Navigate to the repository root
cd metabase

# Build for production (AMD64 architecture)
DOCKER_BUILDKIT=1 docker build \
  --platform linux/amd64 \
  --build-arg MB_EDITION=ee \
  --build-arg VERSION=v0.50.0 \
  -t metabase:1.55.10.6 \
  .

# Tag for ECR
docker tag metabase:1.55.10.6 584641603422.dkr.ecr.us-east-1.amazonaws.com/metabase:1.55.10.6
docker tag metabase:1.55.10.6 584641603422.dkr.ecr.us-east-1.amazonaws.com/metabase:latest

# Authenticate with ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 584641603422.dkr.ecr.us-east-1.amazonaws.com

# Push both tags
docker push 584641603422.dkr.ecr.us-east-1.amazonaws.com/metabase:1.55.10.6
docker push 584641603422.dkr.ecr.us-east-1.amazonaws.com/metabase:latest
```

## Alternative: Using Pre-built JAR

If you have a pre-built `metabase.jar` file, you can use the simpler Dockerfile:

```bash
# Copy your metabase.jar to the bin/docker directory
cp target/uberjar/metabase.jar bin/docker/

# Build using the pre-built JAR Dockerfile
cd bin/docker
docker build -f Dockerfile -t metabase:latest .
```

## Automated Build & Deploy Script

An enhanced build script `build-and-push-to-ecr.sh` has been created in the repository root with the following features:

- Checks for existing local images to avoid unnecessary rebuilds
- Supports custom image tags and versions via command-line arguments
- Provides colored output for better readability
- Shows image size after successful push
- Includes progress indicators during build

### Usage

```bash
# Make the script executable (first time only)
chmod +x build-and-push-to-ecr.sh

# Build with defaults (latest tag, v0.50.0, OSS edition)
./build-and-push-to-ecr.sh

# Build with custom tag and version
./build-and-push-to-ecr.sh v1.0 v0.51.0

# Build enterprise edition
./build-and-push-to-ecr.sh latest v0.50.0 ee
```

### Script Features

The script automatically:
1. Checks if ECR repository exists (creates if needed)
2. Detects existing local images to avoid rebuilds
3. Authenticates with AWS ECR
4. Tags and pushes the image
5. Displays the final image URI and size

## Build Details

### What Gets Built

The Docker build creates a complete Metabase application including:

- **Core Application**: Full Metabase server
- **Database Drivers**: All supported database connectors (PostgreSQL, MySQL, Oracle, Snowflake, BigQuery, etc.)
- **Frontend Assets**: Production-optimized React application
- **Backend Services**: Clojure-based API and services

### Build Stages

1. **Frontend Build**: Compiles TypeScript/React application
2. **Backend Build**: Compiles Clojure code and creates uberjar
3. **Driver Build**: Builds all database driver modules
4. **Final Image**: Alpine Linux with Java runtime and Metabase

### Image Details

- **Base Image**: Alpine Linux with Eclipse Temurin JRE 21
- **Final Size**: ~850MB
- **Exposed Port**: 3000
- **Entrypoint**: `/app/run_metabase.sh`

## Troubleshooting

### Common Issues

1. **Architecture Mismatch**: If you get "exec format error" when running on production servers, ensure you build with `--platform linux/amd64` flag.

2. **Version Error**: If you get "Insufficient input [:version]" error, ensure you're providing the VERSION build arg with a valid semantic version (e.g., `--build-arg VERSION=v0.50.0`).

3. **Docker Not Running**: Ensure Docker Desktop or OrbStack is running:
   ```bash
   # For Docker Desktop
   open -a Docker

   # For OrbStack
   orb start
   ```

4. **ECR Authentication Failed**: Token expires after 12 hours. Re-authenticate:
   ```bash
   aws ecr get-login-password --region us-east-1 | \
   docker login --username AWS --password-stdin 584641603422.dkr.ecr.us-east-1.amazonaws.com
   ```

5. **Build Takes Too Long**: The build process downloads many dependencies. Ensure stable internet connection and sufficient disk space (~10GB needed during build).

6. **Database Migration Issues**: If you get "Downgrade detected" errors, ensure your database schema version matches the Metabase version. You may need to restore from a compatible backup or use the correct Metabase version.

## Deployment

After pushing to ECR, you can deploy the image using:

- **ECS/Fargate**: Create a task definition with the ECR image URI
- **EKS**: Use in Kubernetes deployments
- **EC2**: Pull and run directly on EC2 instances
- **Lambda**: Use for containerized Lambda functions (with modifications)

### Example ECS Task Definition

```json
{
  "family": "metabase",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "2048",
  "memory": "4096",
  "containerDefinitions": [
    {
      "name": "metabase",
      "image": "584641603422.dkr.ecr.us-east-1.amazonaws.com/metabase:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "MB_DB_TYPE",
          "value": "postgres"
        },
        {
          "name": "MB_DB_HOST",
          "value": "your-db-host"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/metabase",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

## Environment Variables

Key environment variables for running Metabase:

- `MB_DB_TYPE`: Database type (h2, postgres, mysql)
- `MB_DB_HOST`: Database hostname
- `MB_DB_PORT`: Database port
- `MB_DB_NAME`: Database name
- `MB_DB_USER`: Database username
- `MB_DB_PASS`: Database password
- `MB_JETTY_PORT`: Port to run on (default: 3000)
- `MB_SITE_URL`: Public URL of your Metabase instance

## Additional Resources

- [Official Metabase Documentation](https://www.metabase.com/docs/latest/)
- [Metabase on Docker Hub](https://hub.docker.com/r/metabase/metabase)
- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)

## Support

For issues specific to this build process, check:
1. Docker build logs: `docker build . 2>&1 | tee build.log`
2. AWS ECR push logs: Check CloudTrail for ECR API calls
3. Container logs when running: `docker logs <container-id>`
