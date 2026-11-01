# Wine exercises the Windows ABI under an isolated display, not a real Windows OS.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    wine wine64 xvfb xauth \
    && rm -rf /var/lib/apt/lists/*
ENV WINEARCH=win64 WINEDEBUG=-all WINEPREFIX=/tmp/linkpad-wine \
    LINKPAD_WINDOWS_INTEGRATION=1 DISPLAY=:99
COPY pointer.test.exe /tests/pointer.test.exe
CMD ["sh", "-c", "Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp -ac & for attempt in $(seq 1 100); do test -S /tmp/.X11-unix/X99 && break; sleep 0.1; done; test -S /tmp/.X11-unix/X99 || exit 1; wineboot -u && wine /tests/pointer.test.exe -test.v"]
