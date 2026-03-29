FROM swift:6.2-jammy AS builder
WORKDIR /build
COPY Package.swift ./
RUN bash -lc 'set -euo pipefail; \
    date; \
    ( \
      GIT_TRACE=1 \
      GIT_TRACE_PACKET=1 \
      GIT_TRACE_PERFORMANCE=1 \
      GIT_CURL_VERBOSE=1 \
      GIT_PROGRESS_DELAY=0 \
      swift package resolve --verbose \
    ) & \
    pid=$!; \
    while kill -0 "$pid" 2>/dev/null; do \
      echo "[spm-resolve] still running at $(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
      sleep 15; \
    done; \
    wait "$pid"; \
    date'
COPY . .
RUN swift build -c release

FROM ubuntu:22.04
RUN apt-get update && apt-get install -y libssl3 ca-certificates libstdc++6 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/.build/release/Run /app/Run
COPY --from=builder /usr/lib/swift /usr/lib/swift
COPY --from=builder /build/SCMDBSnapshot /app/SCMDBSnapshot
ENV LD_LIBRARY_PATH=/usr/lib/swift/linux
EXPOSE 8080
CMD ["/app/Run", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
