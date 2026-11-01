# The Try Weik.io container: the whole platform in one image, so an integration developer only types weikio commands.
# The platform's programs come out of the published images of one release, each pinned by tag and digest. The weikio
# command line client is the release's published Linux file, checked against its SHA-256 sum. This folder is the build
# context, so the image needs nothing else from this repository.

# --- the release --------------------------------------------------------------------------------------------------
ARG WEIKIO_VERSION=2026.2.1
ARG WEIKIO_CLI_SHA256=24f950e6cbab170e73c68530a4ac5770d2760346f89f77bfa3a326930ca4b999
ARG BACKEND_IMAGE=docker.io/weikio/weikio-backend:2026.2.1@sha256:3f8effa15befcf6e892910dfde434876a7b2fcad62712a115b607d16863b268a
ARG AGENT_IMAGE=docker.io/weikio/weikio-agent:2026.2.1@sha256:eafe64a7f41442b648757ab0408ccef05a4357cd0c263106a16e5741c201bae7
ARG APIM_IMAGE=docker.io/weikio/weikio-apim:2026.2.1@sha256:84530db566b66acbad8229d5cfd5dc6ebb50fa858b380380e7143e9fcf58d4a5
ARG NATS_IMAGE=docker.io/library/nats:2.14.7-alpine3.22@sha256:4063edae0717ba5f7501bfde75f97fd9b57f5b93597b92c70b6a6fbbf6a74e06
ARG VICTORIA_LOGS_IMAGE=docker.io/victoriametrics/victoria-logs:v1.52.0@sha256:47b820890d64c4575a2a0a46415dcd8a4fd59a0f1fcd6a377693d7aea639442e
ARG VICTORIA_METRICS_IMAGE=docker.io/victoriametrics/victoria-metrics:v1.153.0@sha256:5eff7af5341e401471002f58d106d399e614a62f3d240f2dbc21901e49eed5dd
ARG VICTORIA_TRACES_IMAGE=docker.io/victoriametrics/victoria-traces:v0.12.0@sha256:80919fcc85cc6dd87f598d20ccf42d0ab1120de8f25d4dcf08c5ea2515a496ba
# --- end of the release -------------------------------------------------------------------------------------------

# The Go toolchain the notices read the Go programs' modules with.
ARG GO_IMAGE=golang:1.27.1-alpine3.24@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414
# The Camel line 'camel' runs when no line is named: the platform's default. 'weikio dev run' names the line, and the
# camel command runs it from the launcher jar of that line, which the backend image carries for its builder.
ARG CAMEL_VERSION=4.22.1

FROM ${AGENT_IMAGE} AS agent
FROM ${APIM_IMAGE} AS apim
FROM ${NATS_IMAGE} AS nats
FROM ${VICTORIA_LOGS_IMAGE} AS victoria-logs
FROM ${VICTORIA_METRICS_IMAGE} AS victoria-metrics
FROM ${VICTORIA_TRACES_IMAGE} AS victoria-traces

# The backend's image with the developer's tools, which the notices list with the image's other packages.
FROM ${BACKEND_IMAGE} AS platform
USER root

# The developer's tools. forward-admin-ui.js reaches the admin UI's port with socat when no editor forwards it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates procps less unzip jq bash-completion socat iproute2 \
    && rm -rf /var/lib/apt/lists/*

# The base image's user becomes the developer's, with a home of its own. The image's spare user at uid 1000 is removed,
# because a devcontainer gives the developer's user the uid of the person on a Linux host, which is most often 1000.
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && usermod -l weikio -d /home/weikio -m -s /bin/bash app \
    && groupmod -n weikio app \
    && mkdir -p /home/weikio/.weikio-dev \
    && chown weikio:weikio /home/weikio/.weikio-dev

# The notices of everything the image holds, written as the product images write theirs: the backend's own, the packages
# of the agent, the gateway and the client, the agent's collector as the agent's notices list it, and each upstream
# program with the Go modules it is built from, which are fetched at their versions from the Go module proxy.
FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS notices
ARG WEIKIO_VERSION
ARG NATS_IMAGE
ARG VICTORIA_LOGS_IMAGE
ARG VICTORIA_METRICS_IMAGE
ARG VICTORIA_TRACES_IMAGE
COPY --from=platform /THIRD-PARTY-NOTICES.txt /notices/in/backend.txt
COPY --from=platform /licenses/components.tsv /notices/in/backend.tsv
COPY --from=agent /THIRD-PARTY-NOTICES.txt /notices/in/agent.txt
COPY --from=agent /licenses/components.tsv /notices/in/agent.tsv
COPY --from=agent /licenses/otelcol-contrib.modules /notices/in/otelcol-contrib.modules
COPY --from=apim /THIRD-PARTY-NOTICES.txt /notices/in/apim.txt
COPY --from=apim /licenses/components.tsv /notices/in/apim.tsv
COPY licenses/cli.txt licenses/cli.tsv /notices/in/
COPY --from=platform /var/lib/dpkg/ /notices/in/dpkg/
COPY --from=platform /usr/share/dotnet/shared/*/*/*.deps.json /notices/in/runtime/
COPY --from=nats /usr/local/bin/nats-server /notices/in/bin/nats-server
COPY --from=victoria-logs /victoria-logs-prod /notices/in/bin/victoria-logs
COPY --from=victoria-metrics /victoria-metrics-prod /notices/in/bin/victoria-metrics
COPY --from=victoria-traces /victoria-traces-prod /notices/in/bin/victoria-traces
COPY licenses/ /notices/tool/
RUN set -eu; \
    chmod 0755 /notices/tool/notices.sh /notices/tool/third-party-notices.sh; \
    { echo "nats-server Apache-2.0 $NATS_IMAGE /usr/local/bin/nats-server"; \
      echo "victoria-logs Apache-2.0 $VICTORIA_LOGS_IMAGE /victoria-logs-prod"; \
      echo "victoria-metrics Apache-2.0 $VICTORIA_METRICS_IMAGE /victoria-metrics-prod"; \
      echo "victoria-traces Apache-2.0 $VICTORIA_TRACES_IMAGE /victoria-traces-prod"; } > /notices/in/programs.txt; \
    WEIKIO_VERSION="$WEIKIO_VERSION" GOMODCACHE=/notices/go-modules \
        sh /notices/tool/notices.sh /notices/in /notices/out

FROM platform
ARG WEIKIO_VERSION
ARG WEIKIO_CLI_SHA256
ARG BACKEND_IMAGE
ARG CAMEL_VERSION

# The platform's other programs, from their published images. The agent runs the integrations on its own image's Java
# runtime, which holds the class-data archive a deployment's start is sped up from, and keeps and sends its site's
# telemetry with its own image's collector, at the path the agent starts it from.
COPY --from=agent /app/ /opt/weikio/agent/
COPY --from=agent /opt/java/ /opt/weikio/agent-java/
COPY --from=agent /otelcol-contrib /otelcol-contrib
COPY --from=apim /app/ /opt/weikio/apim/
COPY --from=nats /usr/local/bin/nats-server /usr/local/bin/nats-server
COPY --from=victoria-logs /victoria-logs-prod /usr/local/bin/victoria-logs
COPY --from=victoria-metrics /victoria-metrics-prod /usr/local/bin/victoria-metrics
COPY --from=victoria-traces /victoria-traces-prod /usr/local/bin/victoria-traces

# The release's weikio client, put in place only when it matches its SHA-256 sum.
RUN set -eu; \
    curl -fsSL --proto '=https' -o /usr/local/bin/weikio \
        "https://weik.io/downloads/cli/$WEIKIO_VERSION/weikio-$WEIKIO_VERSION-linux-x64"; \
    echo "$WEIKIO_CLI_SHA256  /usr/local/bin/weikio" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/weikio

# The licence files, in the places the product images keep them.
COPY licenses/LICENSE licenses/NOTICE /
COPY licenses/README.md /licenses/README.md
COPY --from=agent /licenses/jdk/ /licenses/jdk/
COPY --from=agent /licenses/otelcol-contrib.modules /licenses/otelcol-contrib.modules
COPY --from=notices /notices/out/THIRD-PARTY-NOTICES.txt /THIRD-PARTY-NOTICES.txt
COPY --from=notices /notices/out/components.tsv /licenses/components.tsv
COPY --from=notices /notices/out/*.modules /licenses/

# The start script, the helper, Camel's command line, the shell hook and the smoke test.
COPY scripts/ /usr/local/bin/
COPY shell/weikio-dev.sh /usr/local/share/weikio-dev/shell-hook.sh
COPY test/smoke.sh /usr/local/share/weikio-dev/smoke.sh
RUN set -eu; \
    chmod 0755 /usr/local/bin/weikio-dev-platform /usr/local/bin/weikio-dev /usr/local/bin/camel /usr/local/share/weikio-dev/smoke.sh; \
    printf '\n# Try Weik.io: start-up notice, welcome and completion in interactive shells.\n[ -r /usr/local/share/weikio-dev/shell-hook.sh ] && . /usr/local/share/weikio-dev/shell-hook.sh\n' >> /etc/bash.bashrc; \
    XDG_CONFIG_HOME=/tmp/cli-config weikio completion bash > /etc/bash_completion.d/weikio; \
    rm -rf /tmp/cli-config; \
    printf 'WEIKIO_VERSION=%s\nBACKEND_IMAGE=%s\nCAMEL_VERSION=%s\n' "$WEIKIO_VERSION" "$BACKEND_IMAGE" "$CAMEL_VERSION" > /usr/local/share/weikio-dev/release

# The data of the installation, kept in a volume across restarts and rebuilds. The client keeps its key in a file of
# its own, because the container has no secret store.
ENV WEIKIO_DEV_DATA=/home/weikio/.weikio-dev \
    WEIKIO_KEYRING=off

# Healthy once the API answers. On the first start that is after the installation is set up.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20m --retries=3 \
    CMD ["curl", "-fsS", "-o", "/dev/null", "http://127.0.0.1:8580/healthz"]

# The start script runs as root only to give the data volume to the developer's user, then runs every process as that user.
USER root
WORKDIR /home/weikio
ENTRYPOINT ["/usr/local/bin/weikio-dev-platform"]
CMD []
