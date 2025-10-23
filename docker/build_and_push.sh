#!/bin/bash
# Build Docker image from the docker directory

# Set version
VERSION="v0.0.9"

# Build with version tag (build context is parent directory)
docker build -f Dockerfile -t mathesong/petfit:${VERSION} .. --platform linux/amd64

# Tag as latest
docker tag mathesong/petfit:${VERSION} mathesong/petfit:latest

# Push both tags
docker push mathesong/petfit:${VERSION}
docker push mathesong/petfit:latest
