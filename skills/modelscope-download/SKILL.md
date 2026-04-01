---
name: modelscope-download
description: Download AI models from ModelScope (modelscope.cn). Use when user wants to download models, check model file sizes from ModelScope, or download safetensors/weights files. Supports listing repo files, checking sizes, and multi-threaded downloading with aria2c/axel.
argument-hint: [model-repo] [file] or [model-repo] [file] [output-dir]
user-invocable: true
---

# ModelScope Model Downloader

Download AI models from ModelScope (modelscope.cn) using the API and multi-threaded downloaders.

## Workflow

1. Parse arguments: `$0` = model repo (e.g. `black-forest-labs/FLUX.1-schnell`), `$1` = file path (optional), `$2` = output directory (optional, defaults to current directory)
2. Query the ModelScope API to list available files and sizes
3. If a specific file is requested, show its size and download it; otherwise list all downloadable files
4. Download using aria2c (preferred, 16 threads) or axel (fallback)

## Step 1: Query Model Info

Use the ModelScope API to list files. **Always show file sizes to the user before downloading.**

```bash
# List all files in a repo
curl -s "https://modelscope.cn/api/v1/models/{REPO}/repo/files?Revision=master" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data.get('Success'):
    for f in data['Data']['Files']:
        size = f['Size']
        if size >= 1073741824:
            size_str = f'{size/1073741824:.2f} GB'
        elif size >= 1048576:
            size_str = f'{size/1048576:.1f} MB'
        elif size >= 1024:
            size_str = f'{size/1024:.1f} KB'
        else:
            size_str = f'{size} B'
        lfs = ' [LFS]' if f.get('IsLFS') else ''
        print(f\"{f['Name']:50s} {size_str:>10s}{lfs}\")
else:
    print(f\"Error: {data.get('Message', 'Unknown error')}\")
"
```

For files in subdirectories, append `&Path=SUBDIR` to query nested paths.

## Step 2: Show Size and Confirm

Always show the user the file name and size before downloading. Use `AskUserQuestion` to confirm, especially for files larger than 1 GB.

## Step 3: Download

### Build download URL

The direct download URL format:
```
https://modelscope.cn/models/{REPO}/resolve/master/{FILE_PATH}
```

For LFS files, use the ModelScope LFS API to get the actual download URL:
```bash
# Get LFS download URL (handles large file redirects)
curl -sIL "https://modelscope.cn/models/{REPO}/resolve/master/{FILE_PATH}" 2>&1 | grep -i "^location:" | tail -1
```

### aria2c (preferred)

```bash
aria2c -x 16 -s 16 -k 1M --max-tries=5 --retry-wait=3 \
  -o "{OUTPUT_FILENAME}" \
  "https://modelscope.cn/models/{REPO}/resolve/master/{FILE_PATH}"
```

Parameters:
- `-x 16` : 16 connections per server
- `-s 16` : split into 16 parts
- `-k 1M` : minimum split size 1MB
- `--max-tries=5` : retry up to 5 times
- `--retry-wait=3` : wait 3s between retries
- `-o` : output filename

### axel (fallback if aria2c fails)

```bash
axel -n 16 -a -o "{OUTPUT_FILENAME}" \
  "https://modelscope.cn/models/{REPO}/resolve/master/{FILE_PATH}"
```

Parameters:
- `-n 16` : 16 connections
- `-a` : show progress alternately
- `-o` : output filename

## Common Model Repos

| Model | Repo |
|-------|------|
| FLUX.1-schnell | `black-forest-labs/FLUX.1-schnell` |
| FLUX.1-dev | `black-forest-labs/FLUX.1-dev` |
| FLUX text encoders (clip_l, t5xxl) | `comfyanonymous/flux_text_encoders` |
| SDXL | `stabilityai/stable-diffusion-xl-base-1.0` |

## Notes

- No proxy needed for ModelScope (domestic CDN, fast in China)
- ModelScope uses LFS for large files, the resolve URL handles redirection automatically
- If download fails, try reducing thread count or using axel as fallback
- For interrupted downloads, aria2c supports resume with `-c` flag
