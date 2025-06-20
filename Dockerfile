# Stage 1: Base image with common dependencies
FROM nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04 AS base

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
    python3.12 \
    python3.12-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel
RUN pip install gdown

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --version 0.3.39 --cuda-version 12.6 --nvidia 
#RUN /usr/bin/yes | comfy --workspace /comfyui install --version 0.2.0 --cuda-version 11.8 --nvidia
# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client && rm -rf ~/.cache/pip

# Add scripts
ADD src/start.sh src/rp_handler.py test_input.json ./
#ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh
#RUN chmod +x /start.sh /restore_snapshot.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Optionally copy the snapshot file
#ADD *snapshot*.json /

# Restore the snapshot to install custom nodes
#RUN /restore_snapshot.sh && rm -rf ~/.cache/pip

#WORKDIR /comfyui/custom_nodes

# Modify the config.ini file
#RUN echo "bypass_ssl = true" >> /comfyui/custom_nodes/ComfyUI-Manager/config.ini

#ComfyUI-Impact-Pack
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git ./comfyui/custom_nodes/ComfyUI-Impact-Pack
RUN pip install -r /comfyui/custom_nodes/ComfyUI-Impact-Pack/requirements.txt --no-cache-dir && rm -rf ~/.cache/pip

#ComfyUI-Layer-Style
RUN git clone https://github.com/chflame163/ComfyUI_LayerStyle ./comfyui/custom_nodes/ComfyUI_LayerStyle
RUN pip install -r /comfyui/custom_nodes/ComfyUI_LayerStyle/requirements.txt --no-cache-dir && rm -rf ~/.cache/pip

RUN git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git ./comfyui/custom_nodes/ComfyUI_IPAdapter_plus
#RUN pip install -r /comfyui/custom_nodes/ComfyUI_IPAdapter_plus/requirements.txt --no-cache-dir && rm -rf ~/.cache/pip

# install custom nodes using comfy-cli
RUN comfy-node-install comfyui_controlnet_aux ComfyUI_Comfyroll_CustomNodes SeargeSDXL ComfyMath rgthree-comfy

#RUN pip install --no-cache-dir torch==2.0.1 torchvision==0.15.2 --index-url https://download.pytorch.org/whl/cu118
#RUN pip install --upgrade torch torchvision torchaudio xformers \
    #--extra-index-url https://download.pytorch.org/whl/cu118 \
    #&& rm -rf ~/.cache/pip

#Install custom nodes manually

RUN gdown 1z8Kc4xrYNpwsILqqMES6uJIrz5707vRX -O ./comfyui/input/EmptyImage2.png
RUN gdown 14f_0NPb5KO-Mtnnsz0ucAKHEa2JIfg5R -O ./comfyui/input/EmptySmallImage.png
#
##SeargeSDXL
#RUN git clone https://github.com/SeargeDP/SeargeSDXL.git ./SeargeSDXL
#RUN pip install -r ./SeargeSDXL/requirements.txt --no-cache-dir
#
##ComfyUI-ControlNet-Aux
#RUN git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git ./comfyui_controlnet_aux
#RUN pip install -r ./comfyui_controlnet_aux/requirements.txt --no-cache-dir 
#
##ComfyUI-Comfyroll-CustomNodes
#RUN git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git ./ComfyUI_Comfyroll_CustomNodes
#RUN pip install -r ./ComfyUI_Comfyroll_CustomNodes/requirements.txt --no-cache-dir
#
##ComfyUI-IPAdapter-Plus
#RUN git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git ./ComfyUI_IPAdapter_plus
#RUN pip install -r ./ComfyUI_IPAdapter_plus/requirements.txt --no-cache-dir 
#
##ComfyUI-Math
#RUN git clone https://github.com/evanspearman/ComfyMath.git ./ComfyMath
#RUN pip install -r ./ComfyMath/requirements.txt --no-cache-dir
#
##rgthree-comfy
#RUN git clone https://github.com/rgthree/rgthree-comfy.git ./rgthree-comfy
#RUN pip install -r ./rgthree-comfy/requirements.txt --no-cache-dir
#
##ComfyUI-Manager
#RUN git clone https://github.com/comfyanonymous/ComfyUI-Manager.git ./ComfyUI-Manager
#RUN pip install -r ./ComfyUI-Manager/requirements.txt --no-cache-dir    
#
##ComfyUI-LayerStyle
#RUN git clone https://github.com/Kahsolt/ComfyUI-LayerStyle.git ./ComfyUI-LayerStyle
#RUN pip install -r ./ComfyUI-LayerStyle/requirements.txt --no-cache-dir 

#WORKDIR /

RUN apt-get update && apt-get install -y dos2unix
RUN dos2unix /start.sh

# Start container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base AS downloader

ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories
RUN mkdir -p models/checkpoints models/vae
RUN mkdir -p models/loras models/ipadapter models/controlnet models/clip_vision models/upscale_models

#RUN sed -i '28a folder_names_and_paths["ipadapter"] = ([os.path.join(models_dir, "IPAdapter")], supported_pt_extensions)' folder_paths.py 




#RUN mkdir -p custom_nodes   


#RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git /custom_nodes/ComfyUI-Impact-Pack
#RUN git clone https://github.com/Fannovel16/comfyui_controlnet_aux /custom_nodes/comfyui_controlnet_aux
#RUN git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes /custom_nodes/ComfyUI_Comfyroll_CustomNodes
#RUN git clone https://github.com/SeargeDP/SeargeSDXL /custom_nodes/SeargeSDXL
#RUN git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus /custom_nodes/ComfyUI_IPAdapter_plus
#RUN git clone https://github.com/evanspearman/ComfyMath /custom_nodes/ComfyMath
#RUN git clone https://github.com/theUpsider/ComfyUI-Logic /custom_nodes/ComfyUI-Logic
#RUN git clone https://github.com/rgthree/rgthree-comfy /custom_nodes/rgthree-comfy

# Download checkpoints/vae/LoRA to include in image based on model type

#RUN if [ "$MODEL_TYPE" = "sdxl" ]; then \
#      wget -O models/checkpoints/realvisxlV50_v50Bakedvae.safetensors https://huggingface.co/frankjoshua/realvisxlV50_v50Bakedvae/resolve/main/realvisxlV50_v50Bakedvae.safetensors && \
#      wget -O models/checkpoints/Juggernaut_X_RunDiffusion.safetensors https://huggingface.co/RunDiffusion/Juggernaut-X-v10/resolve/main/Juggernaut-X-RunDiffusion-NSFW.safetensors && \
#      wget -O models/checkpoints/sdXL_v10RefinerVAEFix.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors && \
#      wget -O models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors && \
#      wget -O models/clip_vision/CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors && \
#      wget -O models/controlnet/control-lora-canny-rank256.safetensors https://huggingface.co/stabilityai/control-lora/resolve/main/control-LoRAs-rank256/control-lora-canny-rank256.safetensors && \
#      wget -O models/controlnet/control-lora-depth-rank256.safetensors https://huggingface.co/stabilityai/control-lora/resolve/main/control-LoRAs-rank256/control-lora-depth-rank256.safetensors && \
#      wget -O models/ipadapter/ip-adapter_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter_sd15.safetensors && \
#      wget -O models/ipadapter/ip-adapter_sd15_light_v11.bin https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter_sd15_light_v11.bin && \
#      wget -O models/ipadapter/ip-adapter-plus_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-plus_sd15.safetensors && \
#      wget -O models/ipadapter/ip-adapter-plus-face_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-plus-face_sd15.safetensors && \
#      wget -O models/ipadapter/ip-adapter-full-face_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-full-face_sd15.safetensors && \
#      wget -O models/ipadapter/ip-adapter_sd15_vit-G.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter_sd15_vit-G.safetensors && \
#      wget -O models/ipadapter/ip-adapter_sdxl_vit-h.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors && \
#      wget -O models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors && \
#      wget -O models/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors && \
#      wget -O models/ipadapter/ip-adapter_sdxl.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl.safetensors && \
#      wget -O models/ipadapter/ip-adapter_sdxl.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl.safetensors && \
#      wget -O models/loras/InteriorDesignUniversal_XL_v1.0.safetensors https://huggingface.co/insprt/Interior-Design-Universal/resolve/main/Interior-Design-UniversalXL_v1.0.safetensors && \
#      wget -O models/loras/JZCGXL026_AerialView.safetensors https://civitai.com/api/download/models/406691?type=Model&format=SafeTensor && \
#      wget -O models/loras/SketchuraXL_LoRA.safetensors https://civitai.com/api/download/models/586867?type=Model&format=SafeTensor && \
#      wget -O models/loras/xl_more_art-full_v1.safetensors https://civitai.com/api/download/models/152309?type=Model&format=SafeTensor && \
#      wget -O models/loras/Jiangda_xiaoguotu_0.2.safetensors https://civitai.com/api/download/models/130291?type=Model&format=SafeTensor && \
#      wget -O models/loras/lwmirXL-V1.0fp16.safetensors https://civitai.com/api/download/models/128403?type=Model&format=SafeTensor && \
#      wget -O models/upscale_models/RealESRGAN_x4plus.pth https://huggingface.co/lllyasviel/Annotators/resolve/main/RealESRGAN_x4plus.pth \
#    fi
#RUN if [ "$MODEL_TYPE" = "sd3" ]; then \
#      wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/checkpoints/sd3_medium_incl_clips_t5xxlfp8.safetensors https://huggingface.co/stabilityai/stable-diffusion-3-medium/resolve/main/sd3_medium_incl_clips_t5xxlfp8.safetensors; \
#    fi
#RUN if [ "$MODEL_TYPE" = "flux1-schnell" ]; then \
#      wget -O models/unet/flux1-schnell.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors && \
#      wget -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
#      wget -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
#      wget -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors; \
#    fi
#RUN if [ "$MODEL_TYPE" = "flux1-dev" ]; then \
#        wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/unet/flux1-dev.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors && \
#        wget -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
#        wget -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
#        wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors; \
#    fi


#RUN if [ "$MODEL_TYPE" = "sdxl" ]; then \
        #wget -O models/checkpoints/realvisxlV50_v50Bakedvae.safetensors https://huggingface.co/frankjoshua/realvisxlV50_v50Bakedvae/resolve/main/realvisxlV50_v50Bakedvae.safetensors && \
        #wget -O models/checkpoints/Juggernaut_X_RunDiffusion.safetensors https://huggingface.co/RunDiffusion/Juggernaut-X-v10/resolve/main/Juggernaut-X-RunDiffusion-NSFW.safetensors && \
        #wget -O models/checkpoints/sdXL_v10RefinerVAEFix.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors && \
        #wget -O models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors && \
        #wget -O models/clip_vision/CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors && \
        #wget -O models/controlnet/control-lora-canny-rank256.safetensors https://huggingface.co/stabilityai/control-lora/resolve/main/control-LoRAs-rank256/control-lora-canny-rank256.safetensors && \
        #wget -O models/controlnet/control-lora-depth-rank256.safetensors https://huggingface.co/stabilityai/control-lora/resolve/main/control-LoRAs-rank256/control-lora-depth-rank256.safetensors && \
        #wget -O models/ipadapter/ip-adapter_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter_sd15.safetensors && \
        #wget -O models/ipadapter/ip-adapter_sd15_light_v11.bin https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter_sd15_light_v11.bin && \
        #wget -O models/ipadapter/ip-adapter-plus_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-plus_sd15.safetensors && \
        #wget -O models/ipadapter/ip-adapter-plus-face_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-plus-face_sd15.safetensors && \
        #wget -O models/ipadapter/ip-adapter-full-face_sd15.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-full-face_sd15.safetensors && \
        #wget -O models/ipadapter/ip-adapter_sd15_vit-G.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter_sd15_vit-G.safetensors && \
        #wget -O models/ipadapter/ip-adapter_sdxl_vit-h.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors && \
        #wget -O models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors && \
        #wget -O models/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors && \
        #wget -O models/ipadapter/ip-adapter_sdxl.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl.safetensors && \
        #wget -O models/loras/ip-adapter_sdxl.safetensors https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl.safetensors && \
        #wget -O models/loras/InteriorDesignUniversal_XL_v1.0.safetensors https://huggingface.co/insprt/Interior-Design-Universal/resolve/main/Interior-Design-UniversalXL_v1.0.safetensors && \
        #wget -O models/loras/JZCGXL026_AerialView.safetensors https://civitai.com/api/download/models/406691?type=Model&format=SafeTensor && \
        #wget -O models/loras/SketchuraXL_LoRA.safetensors https://civitai.com/api/download/models/586867?type=Model&format=SafeTensor && \
        #wget -O models/loras/xl_more_art-full_v1.safetensors https://civitai.com/api/download/models/152309?type=Model&format=SafeTensor && \
        #wget -O models/loras/Jiangda_xiaoguotu_0.2.safetensors https://civitai.com/api/download/models/130291?type=Model&format=SafeTensor && \
        #wget -O models/loras/lwmirXL-V1.0fp16.safetensors https://civitai.com/api/download/models/128403?type=Model&format=SafeTensor && \
        #wget -O models/upscale_models/RealESRGAN_x4plus.pth https://huggingface.co/lllyasviel/Annotators/resolve/main/RealESRGAN_x4plus.pth
        #wget -O models/loras/ModelMaker-XL.safetensors https://drive.google.com/uc?export=download&id=1zr39Hobx062pqEUYcgCov8V18MR_oLHn
        #WORKDIR /comfyui/models/loras
        #RUN gdown 1zr39Hobx062pqEUYcgCov8V18MR_oLHn
        #RUN gdown 1njfgedJ9EmXUCE3-aDMejXD-RpDMIZJL
        #RUN gdown 1qZtEAlzBtbApZN2TLu9M2bmOORknXTfo
        #WORKDIR /comfyui
        #RUN wget -O models/sams/sam_vit_b_01ec64.pth https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth &&\
        #

# Stage 3: Final image
FROM base AS final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Start container
CMD ["/start.sh"]
