# Maintainer release steps

Only Luxonis maintainers with registry permissions should publish official
`oakapp-base` images.

## Preferred: Release images workflow

Run the **Release images** workflow in GitHub Actions and provide the base
image version. Optionally provide an explicit `oak_webrtc` version; otherwise
the workflow resolves the current stable release once and embeds it in every
image. The workflow builds the four standard images and publishes them to both
Docker Hub and Quay.

`Dockerfile.onnxruntime` is not included in this workflow.

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
```

## Quay

```bash
docker login quay.io

docker buildx build -f ./Dockerfile.py312 --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9 -t quay.io/luxonis/oakapp-base:latest --push .
docker buildx build -f ./Dockerfile.py311 --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9-py311 --push .
docker buildx build -f ./Dockerfile.py310 --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9-py310 --push .
docker buildx build -f ./Dockerfile.c++ --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9-cpp --push .
```

Create and push an annotated git tag for the release:

```bash
git tag -a X.Y.Z <commit_hash> -m "<tagging_message>"
git push origin X.Y.Z
```
