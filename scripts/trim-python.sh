#!/usr/bin/env bash
# Removes files from a source-built Python installation that applications do
# not use at runtime: the test suite, IDLE/Tk, the static libpython, optimized
# (-O/-OO) bytecode, and debug symbols.
#
# Usage: trim-python.sh <prefix> <major.minor>
set -Eeuo pipefail

PREFIX="$1"
VERSION="$2"
LIB="$PREFIX/lib/python$VERSION"

test -x "$PREFIX/bin/python$VERSION"

# Test suites, IDLE, and Tk modules (_tkinter is not built)
rm -rf "$LIB/test" "$LIB/idlelib" "$LIB/tkinter" "$LIB/turtledemo" "$LIB/turtle.py"
find "$LIB" -path "$LIB/site-packages" -prune -o \
    -type d \( -name test -o -name tests -o -name idle_test \) -prune -exec rm -rf {} +

# C test extension modules
find "$LIB/lib-dynload" \( -name '_test*' -o -name '_ctypes_test*' \
    -o -name '_xxtestfuzz*' -o -name 'xxlimited*' -o -name 'xxsubtype*' \) -delete

# Windows installer stubs shipped with distutils (Python < 3.12)
find "$LIB" -name '*.exe' -delete

# Static libpython, only needed to embed Python into C programs
find "$PREFIX/lib" -name "libpython$VERSION*.a" -delete

# Keep the default bytecode, drop the -O and -OO variants
find "$PREFIX" -name '*.opt-[12].pyc' -delete

# Strip debug symbols from the interpreter and extension modules
strip --strip-unneeded "$PREFIX/bin/python$VERSION"
find "$LIB/lib-dynload" -name '*.so' -exec strip --strip-unneeded {} +

# Make sure the trimmed interpreter and pip still work
"$PREFIX/bin/python$VERSION" -c 'import ssl, sqlite3, ctypes, lzma, bz2, zlib, json, venv, ensurepip'
"$PREFIX/bin/python$VERSION" -m pip --version
