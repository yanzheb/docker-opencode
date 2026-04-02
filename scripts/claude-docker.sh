#!/usr/bin/env bash
set -euo pipefail

# claude-docker.sh — Wrapper for running Claude Code in Docker containers.
# https://github.com/yanzheb/docker-claude-code-setup

# Resolve symlinks to find the actual script location.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GPU_IMAGE="claude-code-gpu"
NOGPU_IMAGE="claude-code-nogpu"
CREDS_DIR="$HOME/.claude-creds"

# Container name is derived from the current directory.
container_name() {
    echo "$(basename "$(pwd)")-claude"
}

# Ensure the shared credentials directory exists.
ensure_creds() {
    mkdir -p "$CREDS_DIR/.claude"
    if [ ! -f "$CREDS_DIR/.claude.json" ]; then
        echo '{}' > "$CREDS_DIR/.claude.json"
    fi
}

usage() {
    cat <<EOF
Usage: claude-docker.sh <command>

Commands:
  build-gpu       Build the GPU-enabled Claude Code image
  build-nogpu     Build the Claude Code image without GPU support
  new [--gpu]     Create a new container for the current directory
  start           Resume the container for the current directory
  stop            Stop the container for the current directory
  exec            Open an additional shell in the running container
  list            List all Claude Code containers
  rm              Remove the container for the current directory

Options:
  --gpu           Use the GPU image (for 'new' command)

The container is automatically named <directory>-claude based on
your current working directory.
EOF
}

cmd_build_gpu() {
    echo "Building $GPU_IMAGE..."
    docker build -t "$GPU_IMAGE" \
        -f "$REPO_DIR/dockerfiles/Dockerfile.claude-gpu" \
        "$REPO_DIR/dockerfiles"
    echo "Done. Image: $GPU_IMAGE"
}

cmd_build_nogpu() {
    echo "Building $NOGPU_IMAGE..."
    docker build -t "$NOGPU_IMAGE" \
        -f "$REPO_DIR/dockerfiles/Dockerfile.claude-nogpu" \
        "$REPO_DIR/dockerfiles"
    echo "Done. Image: $NOGPU_IMAGE"
}

cmd_new() {
    local name
    name="$(container_name)"
    ensure_creds

    local image="$NOGPU_IMAGE"
    local gpu_flags=""

    if [ "${1:-}" = "--gpu" ]; then
        image="$GPU_IMAGE"
        gpu_flags="--gpus all"
    fi

    echo "Creating container '$name' from $image..."
    # shellcheck disable=SC2086
    docker run -it $gpu_flags \
        --name "$name" \
        -v "$(pwd)":/workspace \
        -v "$CREDS_DIR/.claude":/home/agent/.claude \
        -v "$CREDS_DIR/.claude.json":/home/agent/.claude.json \
        "$image"
}

cmd_start() {
    local name
    name="$(container_name)"
    docker start -ai "$name"
}

cmd_stop() {
    local name
    name="$(container_name)"
    docker stop "$name"
}

cmd_exec() {
    local name
    name="$(container_name)"
    docker exec -it "$name" /bin/bash
}

cmd_list() {
    echo "GPU containers:"
    docker ps -a --filter "ancestor=$GPU_IMAGE" --format "  {{.Names}}\t{{.Status}}"
    echo ""
    echo "Non-GPU containers:"
    docker ps -a --filter "ancestor=$NOGPU_IMAGE" --format "  {{.Names}}\t{{.Status}}"
}

cmd_rm() {
    local name
    name="$(container_name)"
    read -rp "Remove container '$name'? Credentials are safe in $CREDS_DIR. [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker rm "$name"
        echo "Removed."
    else
        echo "Cancelled."
    fi
}

case "${1:-}" in
    build-gpu)   cmd_build_gpu ;;
    build-nogpu) cmd_build_nogpu ;;
    new)         cmd_new "${2:-}" ;;
    start)       cmd_start ;;
    stop)        cmd_stop ;;
    exec)        cmd_exec ;;
    list)        cmd_list ;;
    rm)          cmd_rm ;;
    -h|--help|"") usage ;;
    *)
        echo "Unknown command: $1" >&2
        usage >&2
        exit 1
        ;;
esac
