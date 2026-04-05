#!/bin/bash
#
# First-time container creation for a project (README Step 5.4).
#
# Ensures ~/.claude-creds exists with the right permissions and empty
# credential files (safe to run more than once), derives a container
# name from the current working directory, and runs `docker run` to
# create the container, binding the current directory to /workspace
# and the shared credential files into the container.
#
# First-time use only. To resume an existing container, use
# `docker start -ai <name>` if it is stopped, or `docker exec -it
# <name> /bin/bash` if it is already running (see README Step 5.5).
#
# Usage:
#   cd ~/my-project
#   /path/to/scripts/create-container.sh gpu
#   /path/to/scripts/create-container.sh nogpu

set -euo pipefail

readonly CREDS_DIR="${HOME}/.claude-creds"
readonly CREDS_FILE="${CREDS_DIR}/.credentials.json"
readonly CLAUDE_JSON="${CREDS_DIR}/.claude.json"

err() {
  echo "$@" >&2
}

usage() {
  err "Usage: $0 gpu|nogpu"
}

# Prints a 4-char md5 hash of stdin, using md5sum (Linux) or md5 (macOS).
md5_short() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum | cut -c1-4
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q | cut -c1-4
  else
    err "Error: neither 'md5sum' nor 'md5' found on PATH."
    return 1
  fi
}

# Echoes a container name derived from the current working directory,
# e.g. "my-project-a1b2-claude".
derive_container_name() {
  local dir_base
  local dir_hash
  local workspace="$1"
  dir_base="$(basename "${workspace}" \
    | sed -E 's/[^a-zA-Z0-9_.-]+/-/g; s/^[^a-zA-Z0-9]+|[^a-zA-Z0-9]+$//g')"
  dir_hash="$(printf '%s' "${workspace}" | md5_short)"
  echo "${dir_base:-dir}-${dir_hash}-claude"
}

# Creates ~/.claude-creds and its credential files if missing, and
# enforces 700/600 permissions. Safe to run repeatedly.
ensure_creds() {
  mkdir -p "${CREDS_DIR}"
  chmod 700 "${CREDS_DIR}"

  if [[ ! -e "${CREDS_FILE}" ]]; then
    touch "${CREDS_FILE}"
  fi
  if [[ ! -s "${CLAUDE_JSON}" ]]; then
    echo '{}' > "${CLAUDE_JSON}"
  fi
  chmod 600 "${CREDS_FILE}" "${CLAUDE_JSON}"
}

# Verifies docker is installed and the requested image exists locally.
check_prereqs() {
  local image="$1"
  local variant="$2"

  if ! command -v docker >/dev/null 2>&1; then
    err "Error: 'docker' not found on PATH."
    err "Install Docker first (README Sections 2-3 or Step 5.1)."
    return 1
  fi

  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    err "Error: image '${image}' not found locally."
    err "Build it first (README Step 5.3):"
    if [[ "${variant}" == "gpu" ]]; then
      err "  docker build -t ${image} \\"
      err "    --build-arg NVIDIA_VISIBLE_DEVICES=all \\"
      err "    --build-arg NVIDIA_DRIVER_CAPABILITIES=compute,utility \\"
      err "    -f dockerfiles/Dockerfile.claude dockerfiles/"
    else
      err "  docker build -t ${image} \\"
      err "    -f dockerfiles/Dockerfile.claude dockerfiles/"
    fi
    return 1
  fi
}

main() {
  if [[ $# -ne 1 ]]; then
    usage
    exit 2
  fi

  local variant="$1"
  local image
  local -a gpu_args=()

  case "${variant}" in
    gpu)
      image="claude-code-gpu"
      gpu_args=(--gpus all)
      ;;
    nogpu)
      image="claude-code-nogpu"
      ;;
    *)
      err "Error: variant must be 'gpu' or 'nogpu', got '${variant}'"
      usage
      exit 2
      ;;
  esac

  check_prereqs "${image}" "${variant}"
  ensure_creds

  local workspace
  workspace="$(pwd -P)"

  local cname
  cname="$(derive_container_name "${workspace}")"

  local running
  if running="$(docker container inspect \
      -f '{{.State.Running}}' "${cname}" 2>/dev/null)"; then
    err "Error: a container named '${cname}' already exists."
    err "This script is for first-time setup only."
    if [[ "${running}" == "true" ]]; then
      err "It is currently running. To open a shell in it, run:"
      err "  docker exec -it ${cname} /bin/bash"
    else
      err "To resume it, run:"
      err "  docker start -ai ${cname}"
    fi
    exit 1
  fi

  echo "Creating container '${cname}' from image '${image}'..."
  echo "  workspace: ${workspace} -> /workspace"
  echo "  creds:     ${CREDS_FILE} -> /home/agent/.claude/.credentials.json"
  echo "             ${CLAUDE_JSON} -> /home/agent/.claude.json"
  echo

  # The "${gpu_args[@]+...}" form expands the array only if it is set.
  # Needed for macOS system bash 3.2, which otherwise errors on empty
  # array expansion under `set -u`.
  exec docker run -it ${gpu_args[@]+"${gpu_args[@]}"} \
    --name "${cname}" \
    --mount "type=bind,src=${workspace},dst=/workspace" \
    --mount "type=bind,src=${CREDS_FILE},dst=/home/agent/.claude/.credentials.json" \
    --mount "type=bind,src=${CLAUDE_JSON},dst=/home/agent/.claude.json" \
    "${image}"
}

main "$@"
