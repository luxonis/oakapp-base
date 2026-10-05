# Maintainer release steps

Only Luxonis maintainers with registry permissions should publish official
`oakapp-base` images.

## Preferred: Release images workflow

Run the **Release images** workflow in GitHub Actions and provide the base
image version. Optionally provide an explicit `oak_webrtc` version; otherwise
the workflow resolves the current stable release once and embeds it in every
image. The workflow builds all image variants and publishes them to both Docker
Hub and Quay. The ONNX Runtime and llama.cpp images are built after the standard
Python 3.12 image and use that just-published image as their base.

Before release, validate inference with both ONNX Runtime and llama.cpp on OAK4,
including their NPU backends. A successful image build alone does not verify
acceleration.

## Manual release

Replace `1.2.9` below with the release version. Set
`OAK_WEBRTC_VERSION` explicitly when the release must use a specific WebRTC
binary; omit it to resolve the current stable release at build time.

## Docker Hub

```bash
docker buildx build -f ./Dockerfile.py312 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9 -t luxonis/oakapp-base:latest --push .
docker buildx build -f ./Dockerfile.py311 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-py311 --push .
docker buildx build -f ./Dockerfile.py310 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-py310 --push .
docker buildx build -f ./Dockerfile.c++ --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-cpp --push .
docker buildx build -f ./Dockerfile.onnxruntime --platform=linux/arm64 --build-arg BASE_IMAGE=luxonis/oakapp-base:1.2.9 -t luxonis/oakapp-base:1.2.9-onnxruntime --push .
docker buildx build -f ./Dockerfile.llamacpp --platform=linux/arm64 --build-arg BASE_IMAGE=luxonis/oakapp-base:1.2.9 -t luxonis/oakapp-base:1.2.9-llamacpp --push .
```

## Quay

```bash
docker login quay.io

docker buildx build -f ./Dockerfile.py312 --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9 -t quay.io/luxonis/oakapp-base:latest --push .
docker buildx build -f ./Dockerfile.py311 --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9-py311 --push .
docker buildx build -f ./Dockerfile.py310 --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9-py310 --push .
docker buildx build -f ./Dockerfile.c++ --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9-cpp --push .
docker buildx build -f ./Dockerfile.onnxruntime --platform=linux/arm64 --build-arg BASE_IMAGE=quay.io/luxonis/oakapp-base:1.2.9 -t quay.io/luxonis/oakapp-base:1.2.9-onnxruntime --push .
docker buildx build -f ./Dockerfile.llamacpp --platform=linux/arm64 --build-arg BASE_IMAGE=quay.io/luxonis/oakapp-base:1.2.9 -t quay.io/luxonis/oakapp-base:1.2.9-llamacpp --push .
```

Create and push an annotated git tag for the release:

```bash
git tag -a X.Y.Z <commit_hash> -m "<tagging_message>"
git push origin X.Y.Z
```
