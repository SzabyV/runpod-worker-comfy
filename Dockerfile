# Stage 1: Base image with common dependencies
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    libgl1 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install comfy-cli
RUN pip install comfy-cli
#RUN pip install gdown

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia --version 0.2.7

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install runpod
RUN pip install runpod requests

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add scripts
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

# Optionally copy the snapshot file
ADD *snapshot*.json /

# Restore the snapshot to install custom nodes
RUN /restore_snapshot.sh

# Start container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base as downloader

ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories
RUN mkdir -p models/checkpoints models/vae

# Download checkpoints/vae/LoRA to include in image based on model type
RUN if [ "$MODEL_TYPE" = "sdxl" ]; then \
      wget -O models/checkpoints/sd_xl_base_1.0.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors && \
      wget -O models/vae/sdxl_vae.safetensors https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors && \
      wget -O models/vae/sdxl-vae-fp16-fix.safetensors https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors; \
    elif [ "$MODEL_TYPE" = "sd3" ]; then \
      wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/checkpoints/sd3_medium_incl_clips_t5xxlfp8.safetensors https://huggingface.co/stabilityai/stable-diffusion-3-medium/resolve/main/sd3_medium_incl_clips_t5xxlfp8.safetensors; \
    elif [ "$MODEL_TYPE" = "flux1-schnell" ]; then \
      wget -O models/unet/flux1-schnell.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors && \
      wget -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
      wget -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
      wget -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors; \
    elif [ "$MODEL_TYPE" = "flux1-dev" ]; then \
      wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/unet/flux1-dev.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors && \
      wget -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
      wget -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
      wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors; \
    elif [ "$MODEL_TYPE" = "aip" ]; then \
        wget -O models/checkpoints/realvisxlV50_v50Bakedvae.safetensors https://huggingface.co/frankjoshua/realvisxlV50_v50Bakedvae/resolve/main/realvisxlV50_v50Bakedvae.safetensors && \
        wget -O models/checkpoints/Juggernaut_X_RunDiffusion.safetensors https://huggingface.co/RunDiffusion/Juggernaut-X-v10/resolve/main/Juggernaut-X-RunDiffusion-NSFW.safetensors && \
        wget -O models/checkpoints/sdXL_v10RefinerVAEFix.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors && \
        wget -O models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors && \
        wget -O models/clip_vision/CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors && \
        wget -O models/controlnet/control-lora-canny-rank256.safetensors https://huggingface.co/stabilityai/control-lora/resolve/main/control-LoRAs-rank256/control-lora-canny-rank256.safetensors && \
        wget -O models/controlnet/control-lora-depth-rank256.safetensors https://huggingface.co/stabilityai/control-lora/resolve/main/control-LoRAs-rank256/control-lora-depth-rank256.safetensors && \
        wget -O models/ipadapter/ip-adapter_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter_sd15.safetensors && \
        wget -O models/ipadapter/ip-adapter_sd15_light_v11.bin https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter_sd15_light_v11.bin && \
        wget -O models/ipadapter/ip-adapter-plus_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-plus_sd15.safetensors && \
        wget -O models/ipadapter/ip-adapter-plus-face_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-plus-face_sd15.safetensors && \
        wget -O models/ipadapter/ip-adapter-full-face_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-full-face_sd15.safetensors && \
        wget -O models/ipadapter/ip-adapter_sd15_vit-G.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter_sd15_vit-G.safetensors && \
        wget -O models/ipadapter/ip-adapter_sdxl_vit-h.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors && \
        wget -O models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors && \
        wget -O models/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors && \
        wget -O models/ipadapter/ip-adapter_sdxl.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl.safetensors && \
        wget -O models/loras/ip-adapter_sdxl.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl.safetensors && \
        wget -O models/loras/InteriorDesignUniversal_XL_v1.0.safetensors https://huggingface.co/insprt/Interior-Design-Universal/resolve/main/Interior-Design-UniversalXL_v1.0.safetensors && \
        wget -O models/loras/JZCGXL026_AerialView.safetensors https://civitai.com/api/download/models/406691?type=Model&format=SafeTensor && \
        wget -O models/loras/SketchuraXL_LoRA.safetensors https://civitai.com/api/download/models/586867?type=Model&format=SafeTensor && \
        wget -O models/loras/xl_more_art-full_v1.safetensors https://civitai.com/api/download/models/152309?type=Model&format=SafeTensor && \
        wget -O models/loras/Jiangda_xiaoguotu_0.2.safetensors https://civitai.com/api/download/models/130291?type=Model&format=SafeTensor && \
        wget -O models/loras/lwmirXL-V1.0fp16.safetensors https://civitai.com/api/download/models/128403?type=Model&format=SafeTensor
        #wget -O models/loras/ModelMaker-XL.safetensors https://drive.google.com/uc?export=download&id=1zr39Hobx062pqEUYcgCov8V18MR_oLHn
        WORKDIR /comfyui/models/loras
        RUN gdown 1zr39Hobx062pqEUYcgCov8V18MR_oLHn
        RUN gdown 1njfgedJ9EmXUCE3-aDMejXD-RpDMIZJL
        RUN gdown 1qZtEAlzBtbApZN2TLu9M2bmOORknXTfo
        WORKDIR /comfyui
        RUN wget -O models/sams/sam_vit_b_01ec64.pth https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth &&\
        wget -O models/upscale_models/RealESRGAN_x4plus.pth https://huggingface.co/lllyasviel/Annotators/resolve/main/RealESRGAN_x4plus.pth
    fi

# Stage 3: Final image
FROM base as final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Start container
CMD ["/start.sh"]
