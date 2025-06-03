#!/usr/bin/env bash

# Create symlink if it doesn't exist
#if [ ! -L "/comfyui/input" ]; then
#    ln -s /runpod-volume/input /comfyui/input
#fi

mkdir -p /runpod-volume/models /runpod-volume/input /runpod-volume/custom_nodes
mkdir -p /workspace/models /workspace/input /workspace/custom_nodes
#ln -sf /workspace/models/* /runpod-volume/models 2>/dev/null || true
#ln -sf /workspace/input/* /runpod-volume/input 2>/dev/null || true
#ln -sf /workspace/custom_nodes/* /runpod-volume/custom_nodes 2>/dev/null || true

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
#comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# ComfyManager is installed during custom node installation and causes issues on container startup, so we remove it here.
COMFY_MANAGER_PATH="/comfyui/custom_nodes/ComfyUI-Manager"
if [ -d "$COMFY_MANAGER_PATH" ]; then
    rm -rf "$COMFY_MANAGER_PATH"
    echo "Removed ComfyUI-Manager from $COMFY_MANAGER_PATH"
else
    echo "ComfyUI-Manager not found at $COMFY_MANAGER_PATH"
fi

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /rp_handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /rp_handler.py
fi