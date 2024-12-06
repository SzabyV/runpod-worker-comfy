#!/usr/bin/env bash

set -e

SNAPSHOT_FILE=$(ls /*snapshot*.json 2>/dev/null | head -n 1)

if [ -z "$SNAPSHOT_FILE" ]; then
    echo "runpod-worker-comfy: No snapshot file found. Exiting..."
    exit 0
fi

echo "runpod-worker-comfy: restoring snapshot: $SNAPSHOT_FILE"

# Create a temporary file to store requirements
TEMP_REQUIREMENTS=$(mktemp)
trap 'rm -f $TEMP_REQUIREMENTS' EXIT

# Get currently installed packages with versions
CURRENT_PACKAGES=$(pip freeze)

# Extract packages from snapshot and compare with currently installed
jq -r '.pips | to_entries[] | select(.value != "") | "\(.key)\(.value)"' "$SNAPSHOT_FILE" | while read -r package_spec; do
    # Skip if package is already installed with correct version
    if ! echo "$CURRENT_PACKAGES" | grep -q "^${package_spec}$"; then
        # Skip certain system packages that cause conflicts
        case "$package_spec" in
            "python-apt"*|"gyp"*|"dbus-python"*|"PyGObject"*)
                echo "runpod-worker-comfy: Skipping system package: $package_spec"
                continue
                ;;
        esac
        echo "$package_spec" >> "$TEMP_REQUIREMENTS"
    else
        echo "runpod-worker-comfy: Already installed: $package_spec"
    fi
done

# Install missing packages if any exist
if [ -s "$TEMP_REQUIREMENTS" ]; then
    echo "runpod-worker-comfy: Installing missing packages..."
    # Install packages in batches to reduce memory usage
    split -l 50 "$TEMP_REQUIREMENTS" /tmp/req_chunk_
    for chunk in /tmp/req_chunk_*; do
        pip install -r "$chunk" --no-cache-dir || {
            echo "runpod-worker-comfy: Failed to install packages from $chunk"
            cat "$chunk"
            exit 1
        }
        rm "$chunk"
    done
else
    echo "runpod-worker-comfy: No new packages to install"
fi

echo "runpod-worker-comfy: restored snapshot file: $SNAPSHOT_FILE"