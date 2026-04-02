# Docker + Claude Code Setup

Dockerfiles and a step-by-step guide for running [Claude Code](https://code.claude.com/) in Docker containers — with or without NVIDIA GPU support, on Ubuntu or macOS. Also includes an optional [helper script](#section-7--helper-script-claude-dockersh) that wraps the common Docker commands.

> These instructions have been tested but are provided as-is — review each command before running it and ensure you have backups of any important data.

## Quick Start

| Your setup | Start here |
|---|---|
| Ubuntu + NVIDIA GPU | [Section 1](#section-1--purge-any-existing-docker-installation) (follow all sections) |
| Ubuntu, no GPU | [Sections 1–3](#section-1--purge-any-existing-docker-installation) for Docker install, then skip to [Section 6](#section-6--setup-without-gpu-ubuntu-or-macos) |
| macOS | [Section 6](#section-6--setup-without-gpu-ubuntu-or-macos) directly |

## Table of Contents

1. [Purge Any Existing Docker Installation](#section-1--purge-any-existing-docker-installation)
2. [Install Docker Engine](#section-2--install-docker-engine)
3. [Docker Post-Installation Setup](#section-3--docker-post-installation-setup)
4. [Install and Configure the NVIDIA Container Toolkit](#section-4--install-and-configure-the-nvidia-container-toolkit)
5. [Running Claude Code in a Docker Container with GPU Access](#section-5--running-claude-code-in-a-docker-container-with-gpu-access)
6. [Setup Without GPU (Ubuntu or macOS)](#section-6--setup-without-gpu-ubuntu-or-macos)
7. [Helper Script (`claude-docker.sh`)](#section-7--helper-script-claude-dockersh)

<details>
<summary><strong>Prerequisites</strong> (Sections 1–5 only)</summary>

- Ubuntu 24.04 LTS (Noble Numbat), 64-bit (amd64/arm64)
- An NVIDIA GPU with Kepler architecture or newer (compute capability ≥ 3.0)
- NVIDIA GPU drivers already installed and working on the host (verify with `nvidia-smi`)
- Root or sudo access

</details>

---

## Section 1 — Purge Any Existing Docker Installation

Before installing Docker cleanly, remove all conflicting or leftover packages and data.

**Source:** [docs.docker.com/engine/install/ubuntu — "Uninstall old versions"](https://docs.docker.com/engine/install/ubuntu/#uninstall-old-versions) and ["Uninstall Docker Engine"](https://docs.docker.com/engine/install/ubuntu/#uninstall-docker-engine)

### Step 1.1 — Remove all Docker packages

Remove unofficial packages that may conflict, then purge any prior official Docker CE installation:

```bash
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null | cut -f1) 2>/dev/null

sudo apt purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
```

Both commands are safe to run even if the packages aren't installed:
- The first removes unofficial packages that may conflict.
- The second uses `purge` to also delete configuration files from any prior official installation.

### Step 1.2 — Delete residual data and config files

Docker stores images, containers, volumes, and network data under `/var/lib/docker` and `/var/lib/containerd`. These are **not** removed by `apt purge`:

```bash
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -f /etc/apt/sources.list.d/docker.sources
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/keyrings/docker.asc
sudo rm -f /etc/apt/keyrings/docker.gpg
```

> [!WARNING]
> This permanently destroys **all** Docker images, containers, volumes, and networks on this host. Only do this if you want a truly clean slate.

---

## Section 2 — Install Docker Engine

**Source:** [docs.docker.com/engine/install/ubuntu — "Install using the apt repository"](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)

### Step 2.1 — Install prerequisites

```bash
sudo apt update
sudo apt install -y ca-certificates curl
```

These ensure you can fetch packages over HTTPS and download GPG keys.

### Step 2.2 — Add Docker's official GPG key

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

This downloads Docker's GPG signing key and stores it in `/etc/apt/keyrings/` — the modern location for third-party signing keys on Debian-based systems. The `chmod a+r` ensures all users can read it.

### Step 2.3 — Add the Docker apt repository

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

### Step 2.4 — Install Docker Engine packages

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

This installs five packages:

| Package | Purpose |
|---|---|
| `docker-ce` | Docker daemon |
| `docker-ce-cli` | CLI client |
| `containerd.io` | Container runtime |
| `docker-buildx-plugin` | BuildKit build plugin |
| `docker-compose-plugin` | Docker Compose v2 |

### Step 2.5 — Verify the installation

On Ubuntu 24.04, Docker starts automatically after installation. Confirm it's running and then pull a test image:

```bash
sudo systemctl status docker
sudo docker run hello-world
```

If you see `Active: active (running)` from the first command and the "Hello from Docker!" message from the second, the engine is working correctly.

---

## Section 3 — Docker Post-Installation Setup

**Source:** [docs.docker.com/engine/install/linux-postinstall](https://docs.docker.com/engine/install/linux-postinstall/)

### Step 3.1 — Add your user to the `docker` group

By default, the Docker daemon socket is owned by `root` and the `docker` group. To run `docker` commands without `sudo`, add your user to that group:

```bash
sudo groupadd docker 2>/dev/null   # Create the group (may already exist)
sudo usermod -aG docker $USER
```

You must **log out and log back in** for the group change to take effect. Alternatively, in your current shell, run `newgrp docker`.

> [!CAUTION]
> The `docker` group grants root-equivalent privileges on the host. Only add trusted users.

> [!NOTE]
> **If running in a VM:** A full reboot may be needed instead of just logging out.

### Step 3.2 — Enable Docker to start on boot

On Ubuntu 24.04 the Docker service is enabled at boot by default. To make sure (or to explicitly set it):

```bash
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
```

This configures systemd to start both the Docker daemon and containerd automatically on every boot.

### Step 3.3 — Verify Docker runs without sudo

```bash
docker run hello-world
```

If this succeeds without `sudo`, post-installation is complete. If you get a permission denied error, confirm you logged out and back in (or rebooted) after Step 3.1.

---

## Section 4 — Install and Configure the NVIDIA Container Toolkit

**Source:** [docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

### Step 4.1 — Install prerequisites

```bash
sudo apt-get update && sudo apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg2
```

### Step 4.2 — Add the NVIDIA Container Toolkit repository

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

- The first command downloads NVIDIA's GPG key and converts it to the binary format apt expects.
- The second downloads the repository list and injects the `signed-by` directive so apt trusts packages from this repo.

### Step 4.3 — Install the NVIDIA Container Toolkit

```bash
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
```

> [!TIP]
> **Version pinning:** The official docs show pinning to a specific version (e.g., `nvidia-container-toolkit=1.18.2-1`). For most users, installing the latest available version without pinning (as above) is simpler. Pin explicitly if you need reproducible deployments.

### Step 4.4 — Configure NVIDIA as the default Docker runtime

Run the `nvidia-ctk` utility to register the NVIDIA runtime with Docker and set it as the default runtime in one step:

```bash
sudo nvidia-ctk runtime configure --runtime=docker --set-as-default
```

This automatically edits `/etc/docker/daemon.json` to both register the `nvidia` runtime and set `"default-runtime": "nvidia"`. With the default runtime set, **all containers automatically use the NVIDIA runtime** — you won't need to pass `--gpus` or `--runtime=nvidia` on every `docker run` command.

**Source:** [NVIDIA Container Toolkit Install Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) and [NVIDIA Container Toolkit User Guide (`--set-as-default` flag)](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/docker-specialized.html)

Verify the result by inspecting the generated file:

```bash
cat /etc/docker/daemon.json
```

It should look like this:

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

Restart Docker to pick up the new daemon configuration:

```bash
sudo systemctl restart docker
```

### Step 4.5 — Verify GPU access from Docker

**Source:** [docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/sample-workload.html](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/sample-workload.html)

```bash
docker run --rm nvidia/cuda:13.2.0-base-ubuntu24.04 nvidia-smi
```

This pulls NVIDIA's official CUDA base image and runs `nvidia-smi` inside the container. You should see output listing your GPU(s), driver version, and CUDA version — matching (or compatible with) the host driver.

Because the NVIDIA runtime was set as the default above, no `--gpus` flag is needed — official CUDA images set the `NVIDIA_VISIBLE_DEVICES` environment variable internally, and the default runtime picks that up automatically. If the command fails, try adding `--gpus all` explicitly to rule out a default-runtime configuration issue.

> [!TIP]
> **Choosing an image tag:** Replace `13.2.0-base-ubuntu24.04` with a tag matching your driver's supported CUDA version. Check your host CUDA version with `nvidia-smi` on the host and browse available tags at [hub.docker.com/r/nvidia/cuda](https://hub.docker.com/r/nvidia/cuda).

---

## Section 5 — Running Claude Code in a Docker Container with GPU Access

> [!IMPORTANT]
> **Not from official docs.** As of April 2026, `docker sandbox run` uses microVMs that do not support GPU passthrough. The official [Docker Sandboxes Claude Code page](https://docs.docker.com/ai/sandboxes/agents/claude-code/) does not document GPU access. The approach below bypasses Docker Sandboxes entirely and runs Claude Code in a standard Docker container with `--gpus all`.
>
> This workaround is adapted from community approaches (notably [Xueshen Liu's guide](https://xenshinu.github.io/claude_tmux/) and [Martin Thorsen Ranang's truecolor fix](https://ranang.medium.com/fixing-claude-codes-flat-or-washed-out-remote-colors-82f8143351ed)) and the official [Docker custom templates documentation](https://docs.docker.com/ai/sandboxes/templates/).

### Step 5.1 — Create the Dockerfile (one-time setup)

The Dockerfile is provided in this repo at [`dockerfiles/Dockerfile.claude-gpu`](dockerfiles/Dockerfile.claude-gpu). It:
- Builds on the official Claude Code sandbox template
- Adds NVIDIA environment variables for GPU access
- Sets truecolor terminal support
- Optionally installs the CUDA toolkit for compiling GPU code

> [!NOTE]
> **About the `agent` user:** The official sandbox template runs as a non-root user called `agent` with sudo access. Switch to `USER root` for system-level installations, then back to `USER agent` at the end. See the [Docker custom templates documentation](https://docs.docker.com/ai/sandboxes/templates/) for details.

If you cloned this repo, skip to Step 5.2. Otherwise, copy the Dockerfile to a permanent location:

```bash
mkdir -p ~/.docker-templates
cp dockerfiles/Dockerfile.claude-gpu ~/.docker-templates/
```

### Step 5.2 — Build the image (one-time setup)

From the repo directory:

```bash
docker build -t claude-code-gpu -f dockerfiles/Dockerfile.claude-gpu dockerfiles/
```

Or if you copied the file to `~/.docker-templates/`:

```bash
docker build -t claude-code-gpu -f ~/.docker-templates/Dockerfile.claude-gpu ~/.docker-templates
```

This creates a reusable image called `claude-code-gpu`. You only need to rebuild it if you change the Dockerfile.

### Step 5.3 — Create a container for a new project

Each project gets its own named container. Before your first container, create a shared credentials directory on the host (one-time setup):

```bash
mkdir -p ~/.claude-creds/.claude
echo '{}' > ~/.claude-creds/.claude.json
```

Then create a container from the project directory:

```bash
cd ~/my-project
docker run -it --gpus all \
    --name "$(basename $(pwd))-claude" \
    -v $(pwd):/workspace \
    -v ~/.claude-creds/.claude:/home/agent/.claude \
    -v ~/.claude-creds/.claude.json:/home/agent/.claude.json \
    claude-code-gpu
```

- The container is automatically named after the working directory (e.g., `my-project-claude`). To use a custom name, replace `"$(basename $(pwd))-claude"` with your own (e.g., `--name webapp-claude`).
- The two `-v ~/.claude-creds/...` mounts share your Claude credentials (login session, plugins, settings, MCP servers) between the host and all containers. You authenticate once and every container picks it up automatically.

Inside the container, launch Claude Code and authenticate:

```bash
claude
```

Claude Code starts in `/workspace` (your mounted project directory) and prompts you to log in interactively on first launch. Sign in with your Pro, Max, Team, or Enterprise account.

> [!TIP]
> To switch accounts later, run `/login` from within Claude Code. To verify GPU access, run `nvidia-smi` inside the container.

### Step 5.4 — Resume an existing container (daily workflow)

After the first run, always use `start` to resume the container — this preserves installed packages and any configuration:

```bash
docker start -ai my-project-claude
```

This is your day-to-day command. Substitute your container name, or use `docker ps -a --filter "ancestor=claude-code-gpu"` to find it. You can run it from any directory — the project directory from Step 5.3 is permanently bound to `/workspace`.

When you're done working, exit the shell with `exit` or `Ctrl+D`, or run:

```bash
docker stop my-project-claude
```

To open an additional terminal session in the same running container, use `docker exec` from another terminal:

```bash
docker exec -it my-project-claude /bin/bash
```

You can open as many `docker exec` sessions as you want.

> [!NOTE]
> `docker start -ai` only works on a **stopped** container — use `docker exec` for extra sessions in a running container. Credentials are stored on the host in `~/.claude-creds/`, so they survive even if you `docker rm` a container. Installed packages inside the container are still lost on removal.

### Step 5.5 — List and manage project containers

```bash
docker ps -a --filter "ancestor=claude-code-gpu"    # List all Claude Code GPU containers
docker stop my-project-claude                        # Stop a project container
docker rm my-project-claude                          # Remove (credentials are safe on host)
```

---

## Section 6 — Setup Without GPU (Ubuntu or macOS)

If you don't have an NVIDIA GPU, skip Section 4 and follow the steps below to run Claude Code in a Docker container.

### Step 6.1 — Install Docker

**Ubuntu:** Follow Sections 1–3 of this guide to install Docker Engine.

**macOS:** Install Docker Desktop via [Homebrew](https://brew.sh/):

```bash
brew install --cask docker-desktop
```

Then open **Docker Desktop** from your Applications folder or via Spotlight (`Cmd + Space` → type "Docker"). Follow the on-screen prompts to grant the required permissions and wait for the whale icon to appear in your menu bar.

**Source:** [docs.docker.com/desktop/setup/install/mac-install](https://docs.docker.com/desktop/setup/install/mac-install/)

Verify Docker is running on either platform:

```bash
docker --version
```

### Step 6.2 — Create the Dockerfile (one-time setup)

The Dockerfile is provided in this repo at [`dockerfiles/Dockerfile.claude-nogpu`](dockerfiles/Dockerfile.claude-nogpu). It builds on the official Claude Code sandbox template and adds truecolor terminal support.

If you cloned this repo, skip to Step 6.3. Otherwise, copy the Dockerfile to a permanent location:

```bash
mkdir -p ~/.docker-templates
cp dockerfiles/Dockerfile.claude-nogpu ~/.docker-templates/
```

### Step 6.3 — Build the image (one-time setup)

From the repo directory:

```bash
docker build -t claude-code-nogpu -f dockerfiles/Dockerfile.claude-nogpu dockerfiles/
```

Or if you copied the file to `~/.docker-templates/`:

```bash
docker build -t claude-code-nogpu -f ~/.docker-templates/Dockerfile.claude-nogpu ~/.docker-templates
```

This creates a reusable image called `claude-code-nogpu`. You only need to rebuild it if you change the Dockerfile.

### Step 6.4 — Create a container for a new project

Before your first container, create a shared credentials directory on the host (one-time setup — skip this if you already did it in Section 5):

```bash
mkdir -p ~/.claude-creds/.claude
echo '{}' > ~/.claude-creds/.claude.json
```

Then create a container from the project directory:

```bash
cd ~/my-project
docker run -it \
    --name "$(basename $(pwd))-claude" \
    -v $(pwd):/workspace \
    -v ~/.claude-creds/.claude:/home/agent/.claude \
    -v ~/.claude-creds/.claude.json:/home/agent/.claude.json \
    claude-code-nogpu
```

The two `-v ~/.claude-creds/...` mounts share your Claude credentials between the host and all containers. You authenticate once and every container picks it up automatically.

Inside the container, launch Claude Code and authenticate:

```bash
claude
```

Claude Code starts in `/workspace` and prompts you to log in interactively on first launch. Sign in with your Pro, Max, Team, or Enterprise account.

> [!TIP]
> To switch accounts later, run `/login` from within Claude Code.

### Step 6.5 — Resume an existing container (daily workflow)

```bash
docker start -ai my-project-claude
```

You can run this from any directory — the project directory from Step 6.4 is permanently bound to `/workspace`.

When you're done working, exit the shell with `exit` or `Ctrl+D`, or run:

```bash
docker stop my-project-claude
```

To open an additional terminal session in the same running container, use `docker exec` from another terminal:

```bash
docker exec -it my-project-claude /bin/bash
```

You can open as many `docker exec` sessions as you want.

> [!NOTE]
> `docker start -ai` only works on a **stopped** container — use `docker exec` for extra sessions in a running container. Credentials are stored on the host in `~/.claude-creds/`, so they survive even if you `docker rm` a container. Installed packages inside the container are still lost on removal.

### Step 6.6 — List and manage project containers

```bash
docker ps -a --filter "ancestor=claude-code-nogpu"    # List all Claude Code containers
docker stop my-project-claude                          # Stop a project container
docker rm my-project-claude                            # Remove (credentials are safe on host)
```

---

## Section 7 — Helper Script (`claude-docker.sh`)

The [`scripts/claude-docker.sh`](scripts/claude-docker.sh) script wraps all the Docker commands from Sections 5 and 6 into short one-liners. It auto-names containers from the current directory and handles credential mounts automatically.

> This script is entirely optional — every command it runs is documented in the sections above.

### Step 7.1 — Install the script

Clone this repo (if you haven't already) and optionally symlink the script so it's available from anywhere:

```bash
git clone https://github.com/yanzheb/docker-claude-code-setup.git
cd docker-claude-code-setup
chmod +x scripts/claude-docker.sh

# Optional: make it available globally
sudo ln -s "$(pwd)/scripts/claude-docker.sh" /usr/local/bin/claude-docker

# To remove the symlink later:
sudo rm /usr/local/bin/claude-docker
```

### Step 7.2 — Build an image

```bash
claude-docker build-gpu       # Builds from dockerfiles/Dockerfile.claude-gpu
claude-docker build-nogpu     # Builds from dockerfiles/Dockerfile.claude-nogpu
```

### Step 7.3 — Create a container for a new project

From the project directory:

```bash
cd ~/my-project
claude-docker new              # Without GPU
claude-docker new --gpu        # With GPU
```

This creates a container named `my-project-claude`, mounts the current directory to `/workspace`, and sets up shared credentials in `~/.claude-creds/`. Run `claude` inside the container to start Claude Code.

### Step 7.4 — Daily workflow

```bash
cd ~/my-project
claude-docker start            # Resume the container (docker start -ai)
claude-docker exec             # Open an additional shell in a running container
claude-docker stop             # Stop the container
```

`start`, `stop`, and `exec` all detect the container name from the current directory.

### Step 7.5 — List and remove containers

```bash
claude-docker list             # Show all Claude Code containers (GPU and non-GPU)
claude-docker rm               # Remove the container for the current directory (prompts for confirmation)
```

Credentials are stored on the host in `~/.claude-creds/`, so they survive removal.

### Step 7.6 — All commands

| Command | What it does |
|---|---|
| `build-gpu` | Build the GPU image |
| `build-nogpu` | Build the no-GPU image |
| `new [--gpu]` | Create a new container for the current directory |
| `start` | Resume the container |
| `stop` | Stop the container |
| `exec` | Open an additional shell |
| `list` | List all Claude Code containers |
| `rm` | Remove the container (with confirmation) |

---

## Author

Created by [Yanzhe Bekkemoen](https://github.com/yanzheb), with assistance from [Claude](https://claude.ai) by Anthropic.

## License

This project is licensed under the [MIT License](LICENSE).
