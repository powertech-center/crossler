#!/bin/bash

IMAGE="ghcr.io/powertech-center/alpine/cross-go:latest"

if [ $# -eq 0 ]; then
    # No arguments - interactive mode
    docker run -it --rm -v "$(pwd):/workspace" -w /workspace "$IMAGE"
else
    # With arguments - run command and exit
    docker run --rm -v "$(pwd):/workspace" -w /workspace "$IMAGE" "$@"
fi
