# Stage 1: Builder — установка mcpdoc
FROM ubuntu:24.04 AS builder

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_TOOL_DIR=/opt/mcpdoc/share/uv/tools \
    UV_TOOL_BIN_DIR=/opt/mcpdoc/bin \
    UV_PYTHON_INSTALL_DIR=/opt/mcpdoc/share/uv/python

RUN --mount=type=cache,target=/root/.cache \
    uv tool install --from=mcpdoc mcpdoc

# Stage 2: Runtime — минимальный образ для запуска
FROM ubuntu:24.04

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Создаём непривилегированного пользователя
RUN groupadd --gid 568 mcpdoc && useradd --gid mcpdoc --uid 568 --create-home mcpdoc

# Копирование установленного mcpdoc из builder с владельцем mcpdoc
COPY --from=builder --chown=mcpdoc:mcpdoc /opt/mcpdoc /opt/mcpdoc

# Метки для docker inspect
LABEL org.opencontainers.image.title="mcpdoc" \
      org.opencontainers.image.description="MCP LLMS-TXT Documentation Server" \
      org.opencontainers.image.source="https://pypi.org/project/mcpdoc/" \
      org.opencontainers.image.version="0.0.10"

USER mcpdoc
WORKDIR /app

ENV PATH=/opt/mcpdoc/bin:$PATH

# Используем не-privileged порт (для USER mcpdoc)
EXPOSE 8000

COPY --link config.yaml ./

ENTRYPOINT ["mcpdoc", "--yaml", "config.yaml", "--follow-redirects", "--host=0.0.0.0", "--port=8000"]
CMD ["--timeout=15"]
