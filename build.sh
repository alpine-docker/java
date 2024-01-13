#!/usr/bin/env bash

# Prerequisite
# Make sure you set secret enviroment variables in CI
# DOCKER_USERNAME
# DOCKER_PASSWORD

set -e

# usage
Usage() {
  echo "$0 <image_name>"
}

if [ $# -eq 0 ]; then
  Usage
  exit 1
fi

build_docker_image() {
  local tag="$1"
  local runtime="$2"
  local image_name="$3"
  local platform="$4"
  local dockerfile_name="$5"

  short_tag="${tag%%.*}"

  if [ "$runtime" == "jdk" ]; then
      runtime_option="--tag ${image_name}:${short_tag}"
  else
      runtime_option=""
  fi

  echo "Building Docker image with tag: $tag, image name: $image_name, platform: $platform"
  # Create a new buildx builder instance
  builder_name=$(uuidgen)
  docker buildx create --use --name "mybuilder-${builder_name}"

  if [[ "$CIRCLE_BRANCH" == "master" || "$CIRCLE_BRANCH" == "main" ]]; then
    docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
    docker buildx build --progress=plain --push \
     --platform "${platform}" \
     --no-cache \
     --tag "${image_name}:${tag}" \
     --tag "${image_name}:${tag}-${runtime}" \
     ${runtime_option} \
     --tag "${image_name}:${short_tag}-${runtime}" \
     -f "${dockerfile_name}" \
     .
  fi
  
  # Clean up the builder instance
  docker buildx rm "mybuilder-${builder_name}"
}

# main

image="alpine/$1"
#platform="${2:-linux/arm/v7,linux/arm64/v8,linux/arm/v6,linux/amd64,linux/ppc64le,linux/s390x}"
platform="${2:-linux/amd64}"

# Git clone the repository
git clone https://github.com/adoptium/containers
pushd containers || exit 1

# Get all folder names as "alpine"
alpine_folders=($(find . -type d -name 'alpine'))

# Get the Dockerfile name
for folder in "${alpine_folders[@]}"; do
  dockerfile=$(find "$folder" -type f \( -name 'Dockerfile' -o -name 'Dockerfile.releases.full' \))
  if [ -n "$dockerfile" ]; then
    DOCKERFILE="$dockerfile"
    echo $DOCKERFILE
    dockerfile_dir=$(dirname "$DOCKERFILE")
    dockerfile_name=$(basename "$DOCKERFILE")

    pushd $dockerfile_dir

    # Extract the Java version from the Dockerfile
    java_version=$(grep -E '^ENV JAVA_VERSION' "${dockerfile_name}" | awk '{print $3}' | cut -d'-' -f2 | cut -d'+' -f1)
    
    # Set the version as a variable and run the build
    tag="$java_version"

    # Extract the runtime information from the path
    runtime=$(echo "$dockerfile_dir" | awk -F'/' '{print $(NF-1)}')

    # Run the build
    echo "Building image for tag: ${tag}"
    build_docker_image "${tag}" "${runtime}" "${image}" "${platform}" "${dockerfile_name}"

    popd
  fi
done

popd
