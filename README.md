# Run OpenCode in Docker with GPU Support

[![License: MIT](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)
![Last commit](https://img.shields.io/github/last-commit/yanzheb/docker-opencode-setup)
[![Base image](https://img.shields.io/badge/base-docker%2Fsandbox--templates%3Aopencode-2496ED?logo=docker)](https://hub.docker.com/r/docker/sandbox-templates)

Dockerfiles and a guide for running [OpenCode](https://opencode.ai) in Docker containers, with or without NVIDIA GPU support, on Ubuntu or macOS.

> These instructions have been tested but are provided as-is. Review each command before running it and back up any important data.

## Why This Repo?

Coding agents are useful, but I won't give them full access to my machine. I wanted to use OpenCode without giving up privacy or control, so I looked for a way to run it inside Docker.

I first tried [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/), but they use microVMs that don't support GPU passthrough, and I need the GPU. They're also still experimental.

So I built this. It's a thin wrapper around Docker's official [`docker/sandbox-templates:opencode`](https://hub.docker.com/r/docker/sandbox-templates) image. It's small, easy to read, and easy to extend. I can bake in whatever tools a project needs so OpenCode can run them itself to verify its work. For a project that builds LaTeX documents, that means a full LaTeX toolchain, letting the agent compile, read the errors, and fix them on its own. Docker keeps the base image updated, so I don't have to.

Switching to a different coding agent is easy. Docker ships [the same kind of image for other agents](https://hub.docker.com/r/docker/sandbox-templates/tags) like Claude Code, Codex, and Gemini CLI. To try one, copy a Dockerfile in `dockerfiles/`, change the `FROM` line, and rebuild. The rest stays the same.

## Quick Start

| Your setup | Start here |
|---|---|
| Ubuntu + NVIDIA GPU | [Sections 2-4](#section-2---install-docker-engine), then [Section 5](#section-5---running-opencode-in-a-docker-container) (Section 1 optional) |
| Ubuntu, no GPU | [Sections 2-3](#section-2---install-docker-engine), then [Section 5](#section-5---running-opencode-in-a-docker-container) (Section 1 optional) |
| macOS | [Section 5](#section-5---running-opencode-in-a-docker-container) directly |

## Table of Contents

1. [Purge Any Existing Docker Installation (Optional)](#section-1-optional---purge-any-existing-docker-installation)
2. [Install Docker Engine](#section-2---install-docker-engine)
3. [Docker Post-Installation Setup](#section-3---docker-post-installation-setup)
4. [Install and Configure the NVIDIA Container Toolkit](#section-4---install-and-configure-the-nvidia-container-toolkit)
5. [Running OpenCode in a Docker Container](#section-5---running-opencode-in-a-docker-container)

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
sudo apt-get update
sudo apt-get install -y ca-certificates curl
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
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Step 2.5 - Verify the installation

On Ubuntu 24.04, Docker starts automatically after installation. Confirm it's running and pull a test image:

```bash
sudo systemctl status docker
```

If the output shows `Active: active (running)`, the engine is working. Step 3.3 runs a full end-to-end verification.

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
sudo apt-get update && sudo apt-get install -y --no-install-recommends gnupg2
```

`ca-certificates` and `curl` were already installed in Step 2.1.

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

The official docs show pinning to a specific version (e.g., `nvidia-container-toolkit=1.18.2-1`). Pin explicitly if you need reproducible deployments, otherwise the unpinned install above is simpler.

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

This pulls NVIDIA's official CUDA base image and runs `nvidia-smi` inside the container. If the command fails, try adding `--gpus all` explicitly to rule out a default-runtime configuration issue.

Replace `13.2.0-base-ubuntu24.04` with a tag matching your driver's supported CUDA version. Check your host CUDA version with `nvidia-smi` and browse available tags at [hub.docker.com/r/nvidia/cuda](https://hub.docker.com/r/nvidia/cuda).

</details>

## Section 5 - Running OpenCode in a Docker Container

GPU variants are in collapsible sections you can skip. The setup follows the [Docker custom templates documentation](https://docs.docker.com/ai/sandboxes/agents/custom-environments/) and [OpenCode documentation](https://opencode.ai/docs).

### Step 5.1 - Install Docker (macOS only)

If you're on Ubuntu, you already installed Docker in Sections 1-3. Skip to Step 5.2.

macOS: install Docker Desktop via [Homebrew](https://brew.sh/):

```bash
brew install --cask docker-desktop
```

Open Docker Desktop from your Applications folder or Spotlight (`Cmd + Space`, type "Docker") and follow the prompts. Wait for the whale icon in your menu bar.

Source: [docs.docker.com/desktop/setup/install/mac-install](https://docs.docker.com/desktop/setup/install/mac-install/)

Verify Docker is running:

```bash
docker --version
```

### Step 5.2 - Review the Dockerfiles (optional)

<details>
<summary><strong>Click to expand.</strong> The Dockerfiles are short and commented; worth a look before building, but not required.</summary>

- [`dockerfiles/Dockerfile.opencode`](dockerfiles/Dockerfile.opencode) (base image)
- [`dockerfiles/Dockerfile.opencode-latex`](dockerfiles/Dockerfile.opencode-latex) (derived image adding `texlive-full` and `latexmk`)
- [`dockerfiles/Dockerfile.opencode-ollama`](dockerfiles/Dockerfile.opencode-ollama) (derived image adding Ollama)

The official sandbox template runs as a non-root user called `agent` with sudo access. For system-level installations, switch to `USER root` in the Dockerfile, then back to `USER agent` at the end. See the [Docker custom templates documentation](https://docs.docker.com/ai/sandboxes/agents/custom-environments/) for details.

</details>

### Step 5.3 - Build the image (one-time setup)

From the repo root:

```bash
docker build -t opencode-nogpu -f dockerfiles/Dockerfile.opencode dockerfiles/
```

Rebuild only if you change the Dockerfile or want updated base images. Add `--pull` to fetch the latest base image and pick up security patches.

<details>
<summary><strong>GPU variant and project-specific extras</strong></summary>

**GPU build**

```bash
docker build -t opencode-gpu \
    --build-arg NVIDIA_VISIBLE_DEVICES=all \
    --build-arg NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    -f dockerfiles/Dockerfile.opencode dockerfiles/
```

In Step 5.4, use `opencode-gpu` instead of `opencode-nogpu`.

**Project-specific extras**

Add a derived Dockerfile that layers tools on top of the base image. The repository includes two examples:

- [`dockerfiles/Dockerfile.opencode-latex`](dockerfiles/Dockerfile.opencode-latex), which installs `texlive-full` and `latexmk`:

  ```bash
  docker build -t opencode-latex \
      -f dockerfiles/Dockerfile.opencode-latex dockerfiles/
  ```

- [`dockerfiles/Dockerfile.opencode-ollama`](dockerfiles/Dockerfile.opencode-ollama), which installs Ollama and starts it in the background:

  ```bash
  docker build -t opencode-ollama \
      -f dockerfiles/Dockerfile.opencode-ollama dockerfiles/
  ```

To layer on the GPU base instead, pass `--build-arg BASE_IMAGE=opencode-gpu`. `texlive-full` is several gigabytes, so the first build of the LaTeX image will take a while.

In Step 5.4, replace `opencode-nogpu` with your derived image name (e.g. `opencode-latex` or `opencode-ollama`). Additional derived images (`Dockerfile.opencode-rust`, etc.) follow the same pattern.

</details>

### Step 5.4 - Create a container for a new project

Each project gets its own container, named after its directory (e.g. `my-project-opencode`).

First, make sure OpenCode's config files exist on the host (one-time, safe to re-run):

```bash
mkdir -p ~/.config/opencode
touch ~/.config/opencode/opencode.json
touch ~/.config/opencode/tui.json
```

Then create the container from your project directory:

```bash
# Navigate to your project directory first, e.g.:
# cd ~/my-project

workspace="$(pwd -P)"
cname="my-project-opencode"   # Edit to your preferred container name

docker run -it \
    --name "${cname}" \
    --mount type=bind,src="${workspace}",dst=/workspace \
    --mount type=bind,src="$HOME/.config/opencode/opencode.json",dst=/home/agent/.config/opencode/opencode.json \
    --mount type=bind,src="$HOME/.config/opencode/tui.json",dst=/home/agent/.config/opencode/tui.json \
    opencode-nogpu
```

<details>
<summary><strong>Notes</strong></summary>

> **Note:** If two projects share a directory name, set `cname` manually to avoid a conflict (e.g. `cname="my-project-2-opencode"`).

> **Note:** If you use PyTorch's `DataLoader` with `num_workers > 0`, add `--shm-size=8g` to the `docker run` command. Docker's default 64 MB shared-memory limit causes "No space left on device" errors at runtime.

</details>

<details>
<summary><strong>GPU variant. Click to expand.</strong></summary>

```bash
# Navigate to your project directory first, e.g.:
# cd ~/my-project

workspace="$(pwd -P)"
cname="my-project-opencode"   # Edit to your preferred container name

docker run -it --gpus all \
    --name "${cname}" \
    --mount type=bind,src="${workspace}",dst=/workspace \
    --mount type=bind,src="$HOME/.config/opencode/opencode.json",dst=/home/agent/.config/opencode/opencode.json \
    --mount type=bind,src="$HOME/.config/opencode/tui.json",dst=/home/agent/.config/opencode/tui.json \
    opencode-gpu
```

To verify GPU access, run `nvidia-smi` inside the container.

</details>

The `--mount` flags share your project directory and OpenCode config with the container.

Inside the container, launch OpenCode:

```bash
opencode
```

OpenCode starts in `/workspace`, reading API keys and provider credentials from the mounted `opencode.json` and terminal UI settings from `~/.config/opencode/tui.json`. See the [OpenCode documentation](https://opencode.ai/docs) for full config details.

### Step 5.5 - Resume an existing container (daily workflow)

After the first run, always use `start` to resume — this preserves installed packages and configuration:

```bash
docker start -ai my-project-opencode
```

Substitute your container name. You can run this from any directory.

When you're done, exit with `exit` or `Ctrl+D`. The container stops automatically.

**Stopping and removing:**

```bash
docker stop my-project-opencode   # stop a running container
docker rm my-project-opencode     # remove it entirely
```

Your OpenCode config files (`~/.config/opencode/opencode.json` and `~/.config/opencode/tui.json`) live on the host and survive container removal. Packages installed inside the container are lost.

**Other useful commands:**

```bash
docker ps      # list running containers
docker ps -a   # include stopped containers

docker exec -it my-project-opencode /bin/bash   # open a second terminal in a running container
```

> **Note:** `docker start -ai` only works on a stopped container. If it's already running, use `docker exec` instead.

## Author

Created by [Yanzhe Bekkemoen](https://github.com/yanzheb), with assistance from [Claude](https://claude.ai) by Anthropic.

## Contributing

Contributions are welcome. Feel free to open an issue or pull request.

## License

This project is licensed under the [MIT License](LICENSE).
