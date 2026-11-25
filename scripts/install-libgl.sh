#!/usr/bin/env bash
# Provides libGL.so.1 for opencv-python (non-headless) without the Mesa drivers.
#
# Debian's libgl1 depends on Mesa, which pulls in LLVM, ICU, and Z3 (~200 MB).
# OAK4 apps have no display, so only the GLVND dispatch libraries are needed for
# `import cv2` to succeed. Their files are extracted without registering the
# packages with dpkg, so an app that needs real OpenGL can still run
# `apt-get install libgl1`, which installs Mesa and replaces these files.
#
# Expects `apt-get update` to have been run.
set -Eeuo pipefail

apt-get install -y --no-install-recommends libglvnd0 libx11-6 libxext6 libxrender1

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
chown _apt "$TMP_DIR"
cd "$TMP_DIR"

apt-get download libgl1 libglx0
for deb in ./*.deb; do
    dpkg-deb --fsys-tarfile "$deb" | tar -x -C / --wildcards './usr/lib/*'
done
ldconfig

ldconfig -p | grep -q 'libGL\.so\.1 '
