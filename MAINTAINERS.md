# Maintainer release steps

Only Luxonis maintainers with registry permissions should publish official
`oakapp-base` images.

## Docker Hub

```bash
docker buildx build -f ./Dockerfile.py312 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9 -t luxonis/oakapp-base:latest --push .
docker buildx build -f ./Dockerfile.py311 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-py311 --push .
docker buildx build -f ./Dockerfile.py310 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-py310 --push .
docker buildx build -f ./Dockerfile.c++ --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-cpp --push .
docker buildx build -f ./Dockerfile.onnxruntime --platform=linux/arm64 -t luxonis/oakapp-base:1.2.9-onnxruntime --push .
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
