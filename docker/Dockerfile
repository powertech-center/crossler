# Crossler Dev Image
# Development environment for Crossler on Linux
# Inherits Go toolchain from alpine-go
# Adds Linux packaging backends: msitools (wixl), nfpm, osslsigncode

FROM ghcr.io/powertech-center/alpine-go:latest

# msitools provides wixl for building .msi packages
RUN apk add --no-cache msitools

# nfpm for building .deb, .rpm, .apk packages
RUN NFPM_VERSION=$(wget -qO- https://api.github.com/repos/goreleaser/nfpm/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/') && \
    wget -qO /tmp/nfpm.tar.gz "https://github.com/goreleaser/nfpm/releases/latest/download/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz" && \
    tar -xz -C /usr/local/bin -f /tmp/nfpm.tar.gz nfpm && \
    rm /tmp/nfpm.tar.gz

# osslsigncode for Authenticode signing of Windows binaries and .msi
# No prebuilt Linux binary available — build from source
# cmake, make, g++ are already available from alpine-go base image
RUN apk add --no-cache openssl-dev libgsf-dev && \
    OSSVER=$(wget -qO- https://api.github.com/repos/mtrojnar/osslsigncode/releases/latest | grep '"tag_name"' | sed 's/.*"\([^"]*\)".*/\1/') && \
    wget -qO /tmp/osslsigncode.tar.gz "https://github.com/mtrojnar/osslsigncode/archive/refs/tags/${OSSVER}.tar.gz" && \
    mkdir /tmp/osslsigncode-src && \
    tar -xz -C /tmp/osslsigncode-src --strip-components=1 -f /tmp/osslsigncode.tar.gz && \
    cmake -S /tmp/osslsigncode-src -B /tmp/osslsigncode-build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build /tmp/osslsigncode-build --parallel && \
    cp /tmp/osslsigncode-build/osslsigncode /usr/local/bin/ && \
    rm -rf /tmp/osslsigncode.tar.gz /tmp/osslsigncode-src /tmp/osslsigncode-build
WORKDIR /workspace
