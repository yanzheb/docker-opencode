# Run Claude Code in Docker with GPU Support

[![License: MIT](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)
![Last commit](https://img.shields.io/github/last-commit/yanzheb/docker-claude-code-setup)
[![Base image](https://img.shields.io/badge/base-docker%2Fsandbox--templates%3Aclaude--code-2496ED?logo=docker)](https://hub.docker.com/r/docker/sandbox-templates)

A Dockerfile and a guide for running [Claude Code](https://code.claude.com/) in Docker containers, with or without NVIDIA GPU support, on Ubuntu or macOS.

> These instructions have been tested but are provided as-is. Review each command before running it and back up any important data.

## Why This Repo?

Coding agents are useful, but I won't give them full access to my machine. I wanted to use Claude Code without giving up privacy or control, so I looked for a way to run it inside Docker.

I first tried [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/agents/claude-code/), but they use microVMs that don't support GPU passthrough, and I need the GPU. They're also still experimental.

I also looked at a few community projects:

- [cco](https://github.com/nikvdp/cco) works well, but it prefers native OS sandboxing and only falls back to Docker. I wanted to own the Dockerfile so I could set up GPU passthrough and tweak the image myself.
- [jai](https://github.com/stanford-scs/jai) takes a lightweight approach using Linux kernel APIs, but it's Linux-only. I also need macOS support.
- [claudebox](https://github.com/RchGrav/claudebox) bundles language profiles, firewall rules, and tmux into one setup, which is more than I needed.

So I built this. It's a thin wrapper around Docker's official [`docker/sandbox-templates:claude-code`](https://hub.docker.com/r/docker/sandbox-templates) image. It's small, easy to read, and easy to change. Docker keeps the base image updated, so I don't have to.

Switching to a different coding agent is easy. Docker ships [the same kind of image for other agents](https://hub.docker.com/r/docker/sandbox-templates/tags) like OpenCode, Codex, and Gemini CLI. To try one, copy a Dockerfile in `dockerfiles/`, change the `FROM` line, and rebuild. The rest stays the same.

## Quick Start

| Your setup | Start here |
|---|---|
| Ubuntu + NVIDIA GPU | [Sections 2-4](#section-2---install-docker-engine), then [Section 5](#section-5---running-claude-code-in-a-docker-container) (Section 1 optional) |
| Ubuntu, no GPU | [Sections 2-3](#section-2---install-docker-engine), then [Section 5](#section-5---running-claude-code-in-a-docker-container) (Section 1 optional) |
| macOS | [Section 5](#section-5---running-claude-code-in-a-docker-container) directly |

## Table of Contents

1. [Purge Any Existing Docker Installation (Optional)](#section-1-optional---purge-any-existing-docker-installation)
2. [Install Docker Engine](#section-2---install-docker-engine)
3. [Docker Post-Installation Setup](#section-3---docker-post-installation-setup)
4. [Install and Configure the NVIDIA Container Toolkit](#section-4---install-and-configure-the-nvidia-container-toolkit)
5. [Running Claude Code in a Docker Container](#section-5---running-claude-code-in-a-docker-container)

Prerequisites (Sections 1-4, and Section 5 GPU variant):

- Ubuntu 24.04 LTS (Noble Numbat), 64-bit (amd64/arm64)
- An NVIDIA GPU with Kepler architecture or newer (compute capability ≥ 3.0)
- NVIDIA GPU drivers installed and working on the host (verify with `nvidia-smi`)
- Root or sudo access

## Section 1 (Optional) - Purge Any Existing Docker Installation

<details>
<summary><strong>Click to expand.</strong> Skip this section if you don't already have Docker installed or don't need a clean slate. It removes all conflicting or leftover packages and data before installing Docker cleanly.</summary>

Source: [docs.docker.com/engine/install/ubuntu - "Uninstall old versions"](https://docs.docker.com/engine/install/ubuntu/#uninstall-old-versions) and ["Uninstall Docker Engine"](https://docs.docker.com/engine/install/ubuntu/#uninstall-docker-engine)

### Step 1.1 - Remove all Docker packages

Remove unofficial packages that may conflict, then purge any prior official Docker CE installation:

```bash
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null | cut -f1) 2>/dev/null

sudo apt purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
```

Both commands are safe to run even if the packages aren't installed:
- The first removes unofficial packages that may conflict.
- The second uses `purge` to also delete configuration files from any prior official installation.

### Step 1.2 - Delete residual data and config files

Docker stores images, containers, volumes, and network data under `/var/lib/docker` and `/var/lib/containerd`. These are not removed by `apt purge`:

```bash
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -f /etc/apt/sources.list.d/docker.sources
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/keyrings/docker.asc
sudo rm -f /etc/apt/keyrings/docker.gpg
```

Warning: this permanently destroys all Docker images, containers, volumes, and networks on this host. Only do this if you want a clean slate.

</details>

## Section 2 - Install Docker Engine

Source: [docs.docker.com/engine/install/ubuntu - "Install using the apt repository"](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)

### Step 2.1 - Install prerequisites

```bash
sudo apt update
sudo apt install -y ca-certificates curl
```

These allow fetching packages over HTTPS and downloading GPG keys.

### Step 2.2 - Add Docker's official GPG key

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

This downloads Docker's GPG signing key to `/etc/apt/keyrings/`, the standard location for third-party signing keys on Debian-based systems. The `chmod a+r` makes it readable by all users.

### Step 2.3 - Add the Docker apt repository

```bash
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
```

This creates a DEB822-format sources file pointing to Docker's official repository for your Ubuntu release (Noble for 24.04). The `Signed-By` field ties the repo to the GPG key you just downloaded.

### Step 2.4 - Install Docker Engine packages

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Step 2.5 - Verify the installation

On Ubuntu 24.04, Docker starts automatically after installation. Confirm it's running and pull a test image:

```bash
sudo systemctl status docker
sudo docker run hello-world
```

If the first command shows `Active: active (running)` and the second prints "Hello from Docker!", the engine is working.

## Section 3 - Docker Post-Installation Setup

Source: [docs.docker.com/engine/install/linux-postinstall](https://docs.docker.com/engine/install/linux-postinstall/)

### Step 3.1 - Add your user to the `docker` group

By default, the Docker daemon socket is owned by `root` and the `docker` group. To run `docker` commands without `sudo`, add your user to that group:

```bash
sudo groupadd docker 2>/dev/null   # Create the group (may already exist)
sudo usermod -aG docker $USER
```

You must log out and log back in for the group change to take effect. Alternatively, run `newgrp docker` in your current shell.

The `docker` group grants root-equivalent privileges on the host. Only add trusted users.

On a VM, a full reboot may replace the logout step.

### Step 3.2 - Enable Docker to start on boot

On Ubuntu 24.04 the Docker service is enabled at boot by default. To make sure (or set it explicitly):

```bash
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
```

This configures systemd to start both the Docker daemon and containerd automatically on every boot.

### Step 3.3 - Verify Docker runs without sudo

```bash
docker run hello-world
```

If this succeeds without `sudo`, post-installation is complete. If you get a permission denied error, confirm you logged out and back in (or rebooted) after Step 3.1.

## Section 4 - Install and Configure the NVIDIA Container Toolkit

Source: [docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

### Step 4.1 - Install prerequisites

```bash
sudo apt-get update && sudo apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg2
```

### Step 4.2 - Add the NVIDIA Container Toolkit repository

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

- The first command downloads NVIDIA's GPG key and converts it to the binary format apt expects.
- The second downloads the repository list and adds the `signed-by` directive so apt trusts packages from this repo.

### Step 4.3 - Install the NVIDIA Container Toolkit

```bash
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
```

The official docs show pinning to a specific version (e.g., `nvidia-container-toolkit=1.18.2-1`). For most users, installing the latest version without pinning (as above) is simpler. Pin explicitly if you need reproducible deployments.

### Step 4.4 - Configure NVIDIA as the default Docker runtime

Run `nvidia-ctk` to register the NVIDIA runtime with Docker and set it as the default:

```bash
sudo nvidia-ctk runtime configure --runtime=docker --set-as-default
```

This edits `/etc/docker/daemon.json` to register the `nvidia` runtime and set `"default-runtime": "nvidia"`. All containers then use the NVIDIA runtime automatically. You can drop `--gpus` and `--runtime=nvidia` from every `docker run` command.

Source: [NVIDIA Container Toolkit Install Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) and [NVIDIA Container Toolkit User Guide (`--set-as-default` flag)](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/docker-specialized.html)

Verify the result:

```bash
cat /etc/docker/daemon.json
```

<details>
<summary><strong>Expected output</strong></summary>

```json
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    }
}
```

</details>

Restart Docker to apply the new configuration:

```bash
sudo systemctl restart docker
```

### Step 4.5 - Verify GPU access from Docker

Source: [docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/sample-workload.html](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/sample-workload.html)

```bash
docker run --rm nvidia/cuda:13.2.0-base-ubuntu24.04 nvidia-smi
```

You should see output listing your GPU(s), driver version, and CUDA version, matching (or compatible with) the host driver.

<details>
<summary><strong>Notes on the command and image tag</strong></summary>

This pulls NVIDIA's official CUDA base image and runs `nvidia-smi` inside the container.

Because the NVIDIA runtime was set as the default above, no `--gpus` flag is needed. Official CUDA images set the `NVIDIA_VISIBLE_DEVICES` environment variable internally, and the default runtime picks that up automatically. If the command fails, try adding `--gpus all` explicitly to rule out a default-runtime configuration issue.

Replace `13.2.0-base-ubuntu24.04` with a tag matching your driver's supported CUDA version. Check your host CUDA version with `nvidia-smi` and browse available tags at [hub.docker.com/r/nvidia/cuda](https://hub.docker.com/r/nvidia/cuda).

</details>

## Section 5 - Running Claude Code in a Docker Container

This section covers both GPU and non-GPU setups. Use the GPU variant if you completed Section 4. Use the no-GPU variant for Ubuntu without a GPU or macOS.

The setup below is adapted from community guides (notably [Xueshen Liu's guide](https://xenshinu.github.io/claude_tmux/) and [Martin Thorsen Ranang's truecolor fix](https://ranang.medium.com/fixing-claude-codes-flat-or-washed-out-remote-colors-82f8143351ed)) and the official [Docker custom templates documentation](https://docs.docker.com/ai/sandboxes/agents/custom-environments/).

### Step 5.1 - Install Docker (macOS only)

If you're on Ubuntu, you already installed Docker in Sections 1-3. Skip to Step 5.2.

macOS: install Docker Desktop via [Homebrew](https://brew.sh/):

```bash
brew install --cask docker-desktop
```

Then open Docker Desktop from your Applications folder or via Spotlight (`Cmd + Space`, type "Docker"). Follow the on-screen prompts to grant permissions. Wait for the whale icon to appear in your menu bar.

Source: [docs.docker.com/desktop/setup/install/mac-install](https://docs.docker.com/desktop/setup/install/mac-install/)

Verify Docker is running:

```bash
docker --version
```

### Step 5.2 - Review the Dockerfiles

A single Dockerfile builds on the official Claude Code sandbox template and adds truecolor terminal support. Two build arguments (`NVIDIA_VISIBLE_DEVICES` and `NVIDIA_DRIVER_CAPABILITIES`) switch GPU access on or off at build time. They are empty by default (no GPU). Pass them as `--build-arg` to produce a GPU-enabled image.

- [`dockerfiles/Dockerfile.claude`](dockerfiles/Dockerfile.claude)

The official sandbox template runs as a non-root user called `agent` with sudo access. For system-level installations, switch to `USER root` in the Dockerfile, then back to `USER agent` at the end. See the [Docker custom templates documentation](https://docs.docker.com/ai/sandboxes/agents/custom-environments/) for details.

### Step 5.3 - Build the image (one-time setup)

From the repo root:

```bash
# GPU:
docker build -t claude-code-gpu \
    --build-arg NVIDIA_VISIBLE_DEVICES=all \
    --build-arg NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    -f dockerfiles/Dockerfile.claude dockerfiles/

# No GPU:
docker build -t claude-code-nogpu -f dockerfiles/Dockerfile.claude dockerfiles/
```

You only need to rebuild if you change the Dockerfile or want to pull updated base images. Add `--pull` to fetch the latest base image and pick up security patches instead of reusing a cached layer.

### Step 5.4 - Create a container for a new project

Each project gets its own named container. Run the first-time-setup script from the project directory:

```bash
cd ~/my-project
/path/to/this/repo/scripts/create-container.sh gpu     # or: nogpu
```

The script creates the shared credential files under `~/.claude-creds/` if missing (safe to re-run). It then derives a container name from the current directory (e.g., `my-project-a1b2-claude`) and runs `docker run` with the right `--mount` flags. If a container for this directory already exists, the script stops and prints the resume command. See [Step 5.5](#step-55---resume-an-existing-container-daily-workflow).

Inside the container, launch Claude Code and authenticate:

```bash
claude
```

Claude Code starts in `/workspace` (your mounted project directory) and prompts you to log in on first launch. Sign in with your Pro, Max, Team, or Enterprise account. To switch accounts later, run `/login` from within Claude Code. To verify GPU access, run `nvidia-smi` inside the container.

<details>
<summary><strong>Manual alternative</strong> (what the script does, in case you'd rather run it by hand or want to check the script first)</summary>

Create the shared credential files on the host (one-time):

```bash
mkdir -p ~/.claude-creds
chmod 700 ~/.claude-creds
touch ~/.claude-creds/.credentials.json
echo '{}' > ~/.claude-creds/.claude.json
chmod 600 ~/.claude-creds/.credentials.json ~/.claude-creds/.claude.json
```

`chmod 700`/`600` restrict the directory and files to your user so nobody else on the system can read your login tokens.

Then create the container from the project directory. For a custom container name, skip the `cname` block and pass your own value to `--name` (e.g., `--name webapp-claude`):

```bash
cd ~/my-project

# Optional: derive the container name from the current directory.
# Skip this block if you'd rather pass your own name to --name below.
dir_base="$(basename "$(pwd)" | tr -cs 'a-zA-Z0-9_.\n-' '-' | sed 's/^[^a-zA-Z0-9]*//')"
dir_hash="$(printf '%s' "$(pwd)" | md5sum | cut -c1-4)"  # macOS: use md5 instead of md5sum
cname="${dir_base:-dir}-${dir_hash}-claude"

# GPU:
docker run -it --gpus all \
    --name "${cname}" \
    --mount type=bind,src="$(pwd)",dst=/workspace \
    --mount type=bind,src="$HOME/.claude-creds/.credentials.json",dst=/home/agent/.claude/.credentials.json \
    --mount type=bind,src="$HOME/.claude-creds/.claude.json",dst=/home/agent/.claude.json \
    claude-code-gpu

# No GPU:
docker run -it \
    --name "${cname}" \
    --mount type=bind,src="$(pwd)",dst=/workspace \
    --mount type=bind,src="$HOME/.claude-creds/.credentials.json",dst=/home/agent/.claude/.credentials.json \
    --mount type=bind,src="$HOME/.claude-creds/.claude.json",dst=/home/agent/.claude.json \
    claude-code-nogpu
```

The hash in the derived name disambiguates directories that share a basename but live in different locations. The credential `--mount` flags share only your Claude login between containers. Settings, plugins, and MCP server configurations remain container-local.

</details>

### Step 5.5 - Resume an existing container (daily workflow)

After the first run, always use `start` to resume the container. This preserves installed packages and configuration:

```bash
docker start -ai my-project-a1b2-claude
```

This is your day-to-day command. Substitute your container name, or use the filter commands below to find it. You can run it from any directory, since the project directory from Step 5.4 is permanently bound to `/workspace`.

When you're done, exit the shell with `exit` or `Ctrl+D`, or run:

```bash
docker stop my-project-a1b2-claude
```

To open an additional terminal in the same running container, use `docker exec` from another terminal:

```bash
docker exec -it my-project-a1b2-claude /bin/bash
```

You can open as many `docker exec` sessions as you want.

`docker start -ai` only works on a stopped container. If it's already running, use `docker exec` instead. Login credentials are stored on the host in `~/.claude-creds/`, so they survive even if you `docker rm` a container. Settings, plugins, MCP configurations, and installed packages inside the container are lost on removal.

## Useful Commands

| Task | Command |
|---|---|
| Build image (GPU) | `docker build -t claude-code-gpu --build-arg NVIDIA_VISIBLE_DEVICES=all --build-arg NVIDIA_DRIVER_CAPABILITIES=compute,utility -f dockerfiles/Dockerfile.claude dockerfiles/` |
| Build image (no GPU) | `docker build -t claude-code-nogpu -f dockerfiles/Dockerfile.claude dockerfiles/` |
| Create a container for a new project | See [Step 5.4](#step-54---create-a-container-for-a-new-project) |
| Resume a stopped container | `docker start -ai <name>` |
| Open extra shell in running container | `docker exec -it <name> /bin/bash` |
| Stop a container | `docker stop <name>` |
| Remove a container | `docker rm <name>` |
| List GPU containers | `docker ps -a --filter "ancestor=claude-code-gpu"` |
| List non-GPU containers | `docker ps -a --filter "ancestor=claude-code-nogpu"` |
| Launch Claude Code (inside container) | `claude` |
| Verify GPU access (inside container) | `nvidia-smi` |

## Author

Created by [Yanzhe Bekkemoen](https://github.com/yanzheb), with assistance from [Claude](https://claude.ai) by Anthropic.

## Contributing

Contributions are welcome. Feel free to open an issue or pull request.

## License

This project is licensed under the [MIT License](LICENSE).
