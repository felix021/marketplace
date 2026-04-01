---
name: python-env-setup
description: Set up Python virtual environments with fast package installation, optimized for machines in China. Use when user wants to create a venv, install requirements/packages, or set up any Python project environment. Configures Chinese PyPI mirrors and uses uv for 10-100x faster installs. Works for all Python projects — web, ML/CUDA, data science, CLI tools, etc.
argument-hint: [requirements-file] or [package-names...]
user-invocable: true
---

# Python Environment Setup (Fast, China-optimized)

Set up Python virtual environments with fast package installation using `uv` and Chinese PyPI mirrors. Works for **all** Python projects — web frameworks, ML/CUDA, data science, CLI tools, etc.

## Workflow

1. Ensure prerequisites (uv, pip mirror) are configured
2. Create or activate a virtual environment
3. Install packages from requirements file or arguments

## Step 1: Ensure Prerequisites

### Check and configure PyPI mirror

```bash
# Check if mirror is configured
pip config get global.index-url 2>/dev/null || pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
```

### Check and install uv

```bash
which uv >/dev/null 2>&1 || pip install uv
```

### Configure uv to use the same mirror

uv respects `UV_INDEX_URL` or `--index-url`. Set the env var for the session:

```bash
export UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
```

## Step 2: Create or Activate Virtual Environment

Check if a venv already exists in the project directory. Common locations: `venv/`, `.venv/`, `env/`.

```bash
# Check for existing venv
if [ -d "venv" ]; then
    echo "Found existing venv at ./venv"
elif [ -d ".venv" ]; then
    echo "Found existing venv at ./.venv"
else
    # Create new venv using uv (much faster than python -m venv)
    uv venv venv
fi
```

Activate for subsequent commands:

```bash
source venv/bin/activate  # or .venv/bin/activate
```

## Step 3: Install Packages

### From requirements file

Parse `$0` for a requirements file (default: `requirements.txt`).

```bash
# Use uv pip install - 10-100x faster than pip, with aggressive caching
uv pip install -r requirements.txt
```

If a `pyproject.toml` or `setup.py` exists instead:

```bash
uv pip install -e .
```

### From arguments

If `$ARGUMENTS` contains package names instead of a file:

```bash
uv pip install $ARGUMENTS
```

### For PyTorch with CUDA

If the project needs PyTorch with CUDA, use the PyTorch index alongside the mirror:

```bash
uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --extra-index-url https://pypi.tuna.tsinghua.edu.cn/simple
```

Common CUDA wheel indexes:
- `https://download.pytorch.org/whl/cu118` — CUDA 11.8
- `https://download.pytorch.org/whl/cu121` — CUDA 12.1
- `https://download.pytorch.org/whl/cu124` — CUDA 12.4

Check the system CUDA version first:

```bash
nvcc --version 2>/dev/null || nvidia-smi | head -3
```

### For conda/mamba environments

If the project uses conda (`environment.yml`), prefer mamba for faster solves:

```bash
# Install mamba if not present
which mamba >/dev/null 2>&1 || conda install -y -c conda-forge mamba

# Configure conda to use Chinese mirrors (TUNA)
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/pytorch/
conda config --set show_channel_urls yes

mamba env create -f environment.yml
```

## Handling Common Scenarios

### Building packages that need compilation

Some packages (e.g. `psycopg2`, `mysqlclient`, `Pillow`) need system headers:

```bash
# Debian/Ubuntu — install common build deps
sudo apt-get install -y build-essential python3-dev libffi-dev libssl-dev
```

### Packages with Git dependencies

If `requirements.txt` contains `git+https://github.com/...` URLs, these will be slow from China. Options:
1. Use a proxy if available: `export HTTPS_PROXY=$HTTP_PROXY` (set `HTTP_PROXY` env var to your proxy URL)
2. Replace with a mirror if available (e.g. gitee, ghproxy)

### Node/npm for projects with mixed stacks

Some Python projects (e.g. Jupyter extensions) also need npm. Use a Chinese npm mirror:

```bash
npm config set registry https://registry.npmmirror.com
```

## Tips

- **uv caches aggressively** at `~/.cache/uv/` — shared across all projects, so the second project installing the same package is near-instant
- **pip cache** is at `~/.cache/pip/` — also shared, but slower than uv's cache
- If uv fails on a package, fall back to `pip install` (some packages with custom build systems may not work with uv yet)
- For editable installs: `uv pip install -e .`
- To see cache size: `uv cache list` or `du -sh ~/.cache/uv/`
- To clean cache when disk is tight: `uv cache clean`

## Mirror Alternatives

If Tsinghua mirror is slow or down, alternatives:

| Mirror | URL |
|--------|-----|
| Tsinghua | `https://pypi.tuna.tsinghua.edu.cn/simple` |
| Aliyun | `https://mirrors.aliyun.com/pypi/simple/` |
| Douban | `https://pypi.douban.com/simple/` |
| USTC | `https://pypi.mirrors.ustc.edu.cn/simple/` |
| Huawei | `https://repo.huaweicloud.com/repository/pypi/simple/` |
