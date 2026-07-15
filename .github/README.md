<p align="center">
  <a href="#quick-start"><img src="https://img.shields.io/badge/docker-334MB-2496ED?logo=docker&logoColor=white" alt="Docker"></a>
  <a href="#usage"><img src="https://img.shields.io/badge/sse-%20%E2%9C%93-brightgreen" alt="SSE"></a>
  <a href="#usage"><img src="https://img.shields.io/badge/stdio-%20%E2%9C%93-brightgreen" alt="STDIO"></a>
  <a href="https://pypi.org/project/mcpdoc/"><img src="https://img.shields.io/badge/mcpdoc-0.0.10-blue" alt="mcpdoc 0.0.10"></a>
</p>

---

## What is mcpdoc?

**mcpdoc** turns documentation websites into MCP tools. It fetches [`llms.txt`](https://llmstxt.org/) files from configured sources and makes their content available through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/).

Use it to give AI assistants real-time access to framework docs, API references, and technical guides — without dumping terabytes into context windows.

```
LLM/AI Agent  ←→  MCP Protocol  ←→  mcpdoc  ←→  llms.txt URLs
                                            ↕
                                       Documentation
                                       (on demand)
```

---

## Architecture

```mermaid
graph TB
    subgraph Host["Docker Host"]
        MC["mcpdoc container<br/><code>-p 32355:8000</code>"]
        CFG["config.yaml<br/>6 doc sources"]
        EP["docker-entrypoint.sh<br/>auto-detect transport"]
    end

    subgraph MCP["Model Context Protocol"]
        LLM["AI Agent<br/><i>Claude, Copilot, etc.</i>"]
    end

    subgraph Web["Source Documentation"]
        LG["LangGraph<br/>llms.txt"]
        LC["LangChain<br/>llms.txt"]
        PV["Pydantic<br/>llms.txt"]
        FM["Fast MCP<br/>llms.txt"]
        PA["Plano AI<br/>llms.txt"]
        UV["Astral uv<br/>llms.txt"]
    end

    LLM -- "SSE / STDIO" --> MC
    MC --> CFG
    MC --> Web
```

### Transport modes

```mermaid
flowchart LR
    A["docker run -d -p 32355:8000 mcpdoc"]
    B["echo '{}' | docker run -i mcpdoc"]
    C["docker run -i mcpdoc --transport=sse --port=9000"]

    A --> D["entrypoint detects: no pipe"]
    D --> E["--transport=sse"]
    E --> F["SSE Server on :8000"]

    B --> G["entrypoint detects: stdin is pipe"]
    G --> H["--transport=stdio"]
    H --> I["JSON-RPC over stdio"]

    C --> J["entrypoint detects: --transport= explicit"]
    J --> K["passthrough as-is"]
    K --> L["SSE Server on :9000"]
```

### Build stages

```mermaid
flowchart LR
    subgraph Builder["Builder Stage"]
        B1["ubuntu:24.04"] --> B2["apt: ca-certificates"]
        B2 --> B3["COPY uv from ghcr.io"]
        B3 --> B4["uv tool install mcpdoc"]
        B4 --> B5["/opt/mcpdoc/bin/mcpdoc"]
    end

    subgraph Runtime["Runtime Stage"]
        R1["ubuntu:24.04"] --> R2["apt: ca-certificates + curl"]
        R2 --> R3["groupadd + useradd mcpdoc"]
        R3 --> R4["COPY --from=builder<br/>--chown=mcpdoc"]
        R4 --> R5["COPY docker-entrypoint.sh<br/>config.yaml"]
        R5 --> R6["USER mcpdoc:1001"]
        R6 --> R7["ENTRYPOINT"]
    end

    B5 -.->|"--chown=mcpdoc"| R4
```

---

## Quick start

```bash
# 1. Build the image
docker build --progress=plain -t mcpdoc .

# 2. Run as SSE server (default)
docker run --rm -d -p 32355:8000 mcpdoc

# 3. Connect from AI client
curl -N http://localhost:32355/sse
# → event: endpoint
# → data: /messages/?session_id=<id>
```

---

## Usage

### SSE mode (server)

Serve documentation as an MCP SSE endpoint — the primary use case.

```bash
# Default: port 8000, 6 doc sources
docker run --rm -d -p 32355:8000 mcpdoc

# Custom port, explicit transport
docker run --rm -d -p 8080:8000 mcpdoc --transport=sse --port=8000
```

<details>
<summary>Full MCP handshake example</summary>

```bash
# 1. Open SSE connection → get session_id
curl -N http://localhost:32355/sse
# event: endpoint
# data: /messages/?session_id=abc123...

# 2. Initialize
curl -X POST "http://localhost:32355/messages/?session_id=abc123..." \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"my-client","version":"1.0"}}}'

# 3. List tools
curl -X POST "http://localhost:32355/messages/?session_id=abc123..." \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

# 4. List doc sources
curl -X POST "http://localhost:32355/messages/?session_id=abc123..." \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_doc_sources","arguments":{}}}'

# 5. Fetch docs
curl -X POST "http://localhost:32355/messages/?session_id=abc123..." \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"fetch_docs","arguments":{"url":"https://langchain-ai.github.io/langgraph/llms.txt"}}}'
```

Responses arrive as SSE `event: message` on the same connection.
</details>

### STDIO mode (pipe)

Connect directly to the container's stdio — for local CLI or embedded MCP clients.

```bash
# Auto-detected: stdin is a pipe → --transport=stdio
echo '{}' | docker run --rm -i mcpdoc

# Explicit override
echo '{}' | docker run --rm -i mcpdoc --transport=stdio

# With different config
echo '{}' | docker run --rm -i mcpdoc --yaml /app/config.yaml --transport=stdio
```

### Custom config

Mount or override the configuration file:

```bash
# Mount your own config
docker run --rm -d -p 32355:8000 \
  -v $(pwd)/my-config.yaml:/app/config.yaml \
  mcpdoc

# Override with inline arguments
docker run --rm -i mcpdoc \
  --urls "FastMCP:https://gofastmcp.com/llms-full.txt" \
  --transport=stdio
```

---

## Configuration

### `config.yaml`

Define documentation sources as a list of `llms.txt` URLs:

```yaml
- name: LangGraph Python
  llms_txt: https://langchain-ai.github.io/langgraph/llms.txt
- name: LangChain Python
  llms_txt: https://python.langchain.com/llms.txt
- name: Pydantic Validation
  llms_txt: https://pydantic.dev/docs/validation/latest/llms.txt
- name: Fast MCP
  llms_txt: https://gofastmcp.com/llms-full.txt
- name: Plano AI
  llms_txt: https://docs.planoai.dev/includes/llms.txt
- name: Astral uv uvx
  llms_txt: https://docs.astral.sh/uv/llms.txt
```

### Adding a documentation source

1. Find the project's `llms.txt` URL (convention: `https://<domain>/llms.txt`)
2. Add it to `config.yaml`:
   ```yaml
   - name: My Framework
     llms_txt: https://my-framework.dev/llms.txt
   ```
3. Rebuild or mount the config:
   ```bash
   docker build --progress=plain -t mcpdoc .
   # or
   docker run -v $(pwd)/config.yaml:/app/config.yaml ...
   ```

### Using `--urls` (no config file needed)

```bash
docker run --rm -i mcpdoc \
  --urls "LangGraph:https://langchain-ai.github.io/langgraph/llms.txt" \
  --urls "FastMCP:https://gofastmcp.com/llms-full.txt" \
  --transport=stdio
```

---

## Available tools

Once connected, the MCP server exposes two tools:

| Tool | Description | Trigger |
|------|-------------|---------|
| `list_doc_sources` | List all configured documentation sources | First call |
| `fetch_docs` | Fetch documentation by URL | After getting sources |

```mermaid
sequenceDiagram
    participant Agent as AI Agent
    participant MCP as mcpdoc
    participant Web as llms.txt URLs

    Agent->>MCP: list_doc_sources
    MCP-->>Agent: 6 doc sources (URLs)

    Agent->>MCP: fetch_docs(url=...langgraph/llms.txt)
    MCP->>Web: HTTP GET llms.txt
    Web-->>MCP: markdown content
    MCP-->>Agent: parsed documentation

    Agent->>MCP: fetch_docs(url=from llms.txt)
    MCP->>Web: HTTP GET specific page
    Web-->>MCP: content
    MCP-->>Agent: parsed documentation
```

---

## Image reference

| Layer | Content | Size |
|-------|---------|------|
| ubuntu:24.04 | Base OS | ~78 MB |
| apt packages | ca-certificates, curl | ~10 MB |
| `/opt/mcpdoc` | mcpdoc + Python 3.14 + 42 packages | ~157 MB |
| config, entrypoint | Configuration | ~1 kB |
| **Total** | | **~334 MB** |

### Security

- Runs as **non-root** user `mcpdoc` (uid 1001)
- `USER mcpdoc` in Dockerfile — no `root` processes
- HEALTHCHECK with `curl` via port check only

---

## Development

```bash
# Prerequisites
# - Docker 24+
# - uv (optional, for local testing)

# Build
docker build --progress=plain -t mcpdoc .

# Test all modes
docker run --rm -d -p 32355:8000 mcpdoc                        # SSE
echo '{}' | docker run --rm -i mcpdoc                           # STDIO
echo '{}' | docker run --rm -i mcpdoc --transport=stdio         # explicit STDIO

# Check health
docker inspect --format='{{json .State.Health}}' $(docker ps -lq)

# Run with custom config (mount)
docker run --rm -d -p 32355:8000 \
  -v $(pwd)/config.yaml:/app/config.yaml \
  mcpdoc
```

### Project structure

```
mcpdoc/
├── .dockerignore            # Tight build context
├── Dockerfile               # Multi-stage build
├── config.yaml              # 6 documentation sources
├── docker-entrypoint.sh     # Transport auto-detection
└── .github/
    └── README.md            # This file
```

---

## CLI reference

```
mcpdoc [OPTIONS]

Options:
  --yaml, -y PATH      YAML config file with doc sources
  --json, -j PATH      JSON config file with doc sources
  --urls, -u LIST      llms.txt URLs (format: name:url)
  --follow-redirects   Follow HTTP redirects
  --timeout FLOAT      HTTP timeout in seconds (default: 10)
  --transport MODE     Transport: stdio | sse (default: stdio)
  --host TEXT          Bind host for SSE mode (default: 127.0.0.1)
  --port INT           Bind port for SSE mode (default: 8000)
  --log-level LEVEL    DEBUG | INFO | WARNING | ERROR
  --allowed-domains    Additional allowed domains ('*' = any)
  --help, -h           Show help
  --version, -V        Show version
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `port is already allocated` | Container from previous run | `docker rm -f <container>` |
| `curl: (7) Connection refused` | Server not ready | Wait for HEALTHCHECK |
| `No source option provided` | `--yaml` or `--urls` missing | Entrypoint adds it automatically |
| `Permission denied` | Wrong user ownership | Rebuild with `docker build --no-cache` |

---

<p align="center">
  <sub>Built with <a href="https://docs.astral.sh/uv/">uv</a> · <a href="https://pypi.org/project/mcpdoc/">mcpdoc on PyPI</a></sub>
</p>
