FROM atrium-linux-runner:ubuntu24.04-20260908

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq sqlite3 liburi-perl python3-jsonschema python3-yaml \
    && rm -rf /var/lib/apt/lists/*
USER runner
