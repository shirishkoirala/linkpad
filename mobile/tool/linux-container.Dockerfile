# Build/test with: python3 mobile/tool/test_linux_container.py
# Pinned SDK images; this container never mounts a host display or server state.
FROM golang:1.26.5-bookworm@sha256:0d327c83532d3cdeeeebab56ce85962bf09cb89545355b10207c7771b0c3713f AS go
FROM ghcr.io/cirruslabs/flutter@sha256:0a9de3b70b5b7b921a346eb2793e363dc22280849a4fd690d9dde99ce1c2b1b8
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
    libsecret-1-dev libjsoncpp-dev libayatana-appindicator3-dev \
    xvfb xauth dbus-x11 xdotool x11-utils libgl1-mesa-dri python3 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=go /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}" \
    LIBGL_ALWAYS_SOFTWARE=1 NO_AT_BRIDGE=1
WORKDIR /work
COPY go.mod go.sum ./
RUN go mod download
COPY . .
WORKDIR /work/mobile
RUN flutter --version && flutter pub get && flutter build linux --release
WORKDIR /work
CMD ["/bin/bash", "mobile/tool/linux-container-test.sh"]
