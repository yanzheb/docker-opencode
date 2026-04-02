#!/bin/bash
#
# Wrapper for running Claude Code in Docker containers.
# https://github.com/yanzheb/docker-claude-code-setup

# Safety options:
#   -e  Exit immediately if any command fails.
#   -u  Treat unset variables as errors.
#   -o pipefail  If any command in a pipeline fails, the whole
#                pipeline fails.
set -euo pipefail

# --- Resolve symlinks to find the actual script location ---
# If this script is called through a symlink
# (e.g. /usr/local/bin/claude-docker ->
# /home/you/repo/scripts/claude_docker.sh), we follow the chain
# of links to find where the real script lives. This lets us
# locate the repo directory reliably no matter how the script
# is invoked.
#
# BASH_SOURCE[0] is the path used to invoke this script.
# -L tests whether a path is a symbolic link.
# readlink returns the target a symlink points to.
script_path="${BASH_SOURCE[0]}"
while [[ -L "${script_path}" ]]; do
  dir="$(cd "$(dirname "${script_path}")" && pwd)"
  script_path="$(readlink "${script_path}")"
  # If the link target is a relative path, make it absolute.
  [[ "${script_path}" != /* ]] && script_path="${dir}/${script_path}"
done
SCRIPT_DIR="$(cd "$(dirname "${script_path}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# readonly makes these variables immutable (cannot be reassigned
# later). Declaring and assigning on separate lines avoids masking
# the exit code of the command substitution (shellcheck SC2155).
readonly SCRIPT_DIR
readonly REPO_DIR

# --- Constants ---
readonly GPU_IMAGE="claude-code-gpu"
readonly NOGPU_IMAGE="claude-code-nogpu"
readonly CREDS_DIR="${HOME}/.claude-creds"

#######################################
# Print a timestamped message to stderr (standard error).
# Writing errors to stderr keeps them separate from normal
# output, so piping or redirecting stdout is not polluted
# by error messages.
# Arguments:
#   $@ - Message strings to print.
#######################################
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Derive a container name from the current directory.
# For example, if you are in /home/you/my-project, this
# returns "my-project-claude". The tr command replaces any
# characters that are not alphanumeric, underscores, dots,
# or hyphens with a hyphen, so the name is always safe for
# Docker.
# Outputs:
#   The container name string to stdout.
#######################################
container_name() {
  local base
  base="$(basename "$(pwd)" | tr -cs 'a-zA-Z0-9_.\n-' '-')"
  echo "${base}-claude"
}

#######################################
# Create the shared credentials directory if it does not
# exist. This directory is mounted into every container so
# that your Claude credentials persist across container
# rebuilds.
# Globals:
#   CREDS_DIR
#######################################
ensure_creds() {
  # -p: create parent dirs as needed, no error if it exists.
  mkdir -p "${CREDS_DIR}/.claude"
  if [[ ! -f "${CREDS_DIR}/.claude.json" ]]; then
    echo '{}' > "${CREDS_DIR}/.claude.json"
  fi
}

#######################################
# Print usage information to stdout.
# Arguments:
#   None.
#######################################
usage() {
  cat <<EOF
Usage: claude_docker.sh <command>

Commands:
  build-gpu       Build the GPU-enabled image
  build-nogpu     Build the image without GPU support
  new [--gpu]     Create a new container
  start           Resume the container
  stop            Stop the container
  exec            Open a shell in the running container
  list            List all Claude Code containers
  rm              Remove the container

Options:
  --gpu           Use the GPU image ('new' command)

The container is automatically named <directory>-claude
based on your current working directory.
EOF
}

#######################################
# Build a Docker image.
# Arguments:
#   $1 - Variant: "gpu" or "nogpu".
# Globals:
#   REPO_DIR
#######################################
cmd_build() {
  local variant="$1"
  local image="claude-code-${variant}"
  echo "Building ${image}..."
  # -t tags the image with a name.
  # -f specifies which Dockerfile to use.
  # The last argument is the build context directory (where
  # Docker looks for files referenced in the Dockerfile).
  docker build -t "${image}" \
    -f "${REPO_DIR}/dockerfiles/Dockerfile.claude-${variant}" \
    "${REPO_DIR}/dockerfiles"
  echo "Done. Image: ${image}"
}

#######################################
# Create a new container for the current directory.
# Mounts your working directory into the container at
# /workspace, and mounts shared credentials so they persist
# across containers.
# Arguments:
#   $1 - Optional: --gpu to use the GPU image.
# Globals:
#   GPU_IMAGE, NOGPU_IMAGE, CREDS_DIR
#######################################
cmd_new() {
  # "local" restricts the variable to this function's scope.
  # Declaration is separate from assignment so that a failing
  # command substitution is not hidden by local's always-zero
  # exit code.
  local name
  name="$(container_name)"
  ensure_creds

  local image="${NOGPU_IMAGE}"
  # Arrays let us build up a list of arguments safely, even
  # when some items contain spaces.
  local run_args=()

  # ${1:-} means "use $1 if set, otherwise use empty string".
  # This prevents an "unbound variable" error from set -u
  # when no argument is passed.
  if [[ "${1:-}" == "--gpu" ]]; then
    image="${GPU_IMAGE}"
    # += appends to the array.
    run_args+=(--gpus all)
  fi

  # "docker image inspect" succeeds (exit 0) if the image
  # exists. The "!" negates it: enter the if-block when the
  # image is missing. &>/dev/null discards both stdout and
  # stderr so the user only sees our custom error message.
  if ! docker image inspect "${image}" &>/dev/null; then
    err "Image '${image}' not found." \
      "Run 'build-gpu' or 'build-nogpu' first."
    exit 1
  fi

  if docker container inspect "${name}" &>/dev/null; then
    err "Container '${name}' already exists." \
      "Use 'start' to resume or 'rm' to remove it."
    exit 1
  fi

  echo "Creating container '${name}' from ${image}..."
  # docker run flags:
  #   -it      Allocate an interactive terminal.
  #   --name   Give the container a human-readable name.
  #   -v X:Y   Mount host path X at container path Y.
  docker run -it ${run_args[@]+"${run_args[@]}"} \
    --name "${name}" \
    -v "$(pwd)":/workspace \
    -v "${CREDS_DIR}/.claude":/home/agent/.claude \
    -v "${CREDS_DIR}/.claude.json":/home/agent/.claude.json \
    "${image}"
}

#######################################
# Exit with an error if the container does not exist.
# Arguments:
#   $1 - Container name.
#######################################
require_container() {
  local name="$1"
  if ! docker container inspect "${name}" &>/dev/null; then
    err "No container '${name}' found." \
      "Use 'new' to create one."
    exit 1
  fi
}

#######################################
# Reattach to a stopped container.
# Flags: -a = attach stdout/stderr, -i = interactive.
#######################################
cmd_start() {
  local name
  name="$(container_name)"
  require_container "${name}"
  docker start -ai "${name}"
}

#######################################
# Stop the container for the current directory.
#######################################
cmd_stop() {
  local name
  name="$(container_name)"
  require_container "${name}"
  docker stop "${name}"
}

#######################################
# Open an extra shell session inside a running container.
#######################################
cmd_exec() {
  local name
  name="$(container_name)"
  require_container "${name}"
  docker exec -it "${name}" /bin/bash
}

#######################################
# List all Claude Code containers (running or stopped).
# Globals:
#   GPU_IMAGE, NOGPU_IMAGE
#######################################
cmd_list() {
  local gpu_list nogpu_list
  # --filter selects containers built from a specific image.
  # --format controls output columns using Go templates.
  local fmt="  {{.Names}}\t{{.Status}}"
  gpu_list="$(docker ps -a \
    --filter "ancestor=${GPU_IMAGE}" \
    --format "${fmt}")"
  nogpu_list="$(docker ps -a \
    --filter "ancestor=${NOGPU_IMAGE}" \
    --format "${fmt}")"

  echo "GPU containers:"
  # ${var:-(none)}: use $var if non-empty, otherwise "(none)".
  echo "${gpu_list:-(none)}"
  echo ""
  echo "Non-GPU containers:"
  echo "${nogpu_list:-(none)}"
}

#######################################
# Remove the container for the current directory.
# Asks for confirmation before removing. Credentials in
# CREDS_DIR are not affected.
# Globals:
#   CREDS_DIR
#######################################
cmd_rm() {
  local name
  name="$(container_name)"
  require_container "${name}"

  local confirm
  # read -r prevents backslash interpretation.
  # -p shows a prompt string.
  read -rp \
    "Remove '${name}'? Creds safe in ${CREDS_DIR}. [y/N] " \
    confirm
  # =~ is a regex match. ^[Yy]$ matches "Y" or "y".
  if [[ "${confirm}" =~ ^[Yy]$ ]]; then
    docker rm "${name}"
    echo "Removed."
  else
    echo "Cancelled."
  fi
}

#######################################
# Entry point. Routes the first argument to the matching
# command function. Wrapping this in a function (instead of
# putting it at the top level) is a bash convention that
# keeps the script organized when there are many functions.
# Arguments:
#   $@ - All command-line arguments passed to the script.
#######################################
main() {
  # case...esac is bash's version of a switch statement.
  # Each pattern ends with ) and each branch ends with ;;
  case "${1:-}" in
    build-gpu)   cmd_build gpu ;;
    build-nogpu) cmd_build nogpu ;;
    new)         cmd_new "${2:-}" ;;
    start)       cmd_start ;;
    stop)        cmd_stop ;;
    exec)        cmd_exec ;;
    list)        cmd_list ;;
    rm)          cmd_rm ;;
    -h|--help|"") usage ;;
    *)
      err "Unknown command: $1"
      usage >&2
      exit 1
      ;;
  esac
}

# "$@" passes all arguments to main, preserving quoting.
# This must be the last executable line in the script.
main "$@"
