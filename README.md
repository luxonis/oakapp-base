# Base Docker Image for OAK4 oakapps

This Docker image is a multi-stage build designed to provide a minimal and efficient environment for running a Python applications using [DepthAI v3](https://github.com/luxonis/depthai-core) alongside Nginx and libraries neccesary to provide local and remote access to frontend via oak_webrtc binary. 

Key Features
- Base Image: debian:bookworm-slim for both build and final stages.
- Python Version: built from source with optimizations for usage on OAK4. Images for version 3.12 and 3.11
- Included Services:
    - nginx for serving static content and reverse proxying. Self-signed SSL certificates generated during the build process. 
	- oak_webrtc binary for DepthAI WebRTC functionalities.
	- runit for service supervision.

# Build and deploy

`docker buildx build -f ./Dockerfile.py312 --platform=linux/arm64 -t luxonis/oakapp-base:1.2.8 -t luxonis/oakapp-base:latest --push .`

`docker buildx build -f ./Dockerfile.py311 --platform=linux/arm64 -t luxonis/oakapp-base:1.2.8-py311 --push .`

`docker buildx build -f ./Dockerfile.py310 --platform=linux/arm64 -t luxonis/oakapp-base:1.2.8-py310 --push .`

`docker buildx build -f ./Dockerfile.c++ --platform=linux/arm64 -t luxonis/oakapp-base:1.2.8-cpp --push .`

and
login

	docker login quay.io

and push

`docker buildx build -f ./Dockerfile.py312 --platform=linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.8 -t quay.io/luxonis/oakapp-base:latest --push .`

`docker buildx build -f ./Dockerfile.py311 --platform=linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.8-py311 --push .`

`docker buildx build -f ./Dockerfile.py310 --platform=linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.8-py310 --push .`

`docker buildx build -f ./Dockerfile.c++ --platform=linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.8-cpp --push .`

