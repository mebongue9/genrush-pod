#!/bin/bash
# Open video models for the footage test (Martin, 2026-10-04): Wan 2.2 14B image-to-video + its 4-step LoRAs (Apache 2.0)
# and LTX 2.5 distilled (gated: the Hugging Face token is read from /workspace/genrush/.hf_token, never stored in this repo).
# About 70 GB. Idempotent, aria2 resumes. Prints free space before and after.
set -u
command -v aria2c >/dev/null || { echo "installing aria2 (container disk is fresh on every pod)"; apt-get update -y >/dev/null 2>&1; apt-get install -y aria2 >/dev/null 2>&1; }
TOK=$(cat /workspace/genrush/.hf_token 2>/dev/null || true)
cd /workspace/models
echo "BEFORE $(df -h /workspace | tail -1)"
# The volume is shared with the space pipeline (250 GB). Refuse to start unless these models fit with 20 GB to spare.
USED=$(du -s --block-size=1G /workspace 2>/dev/null | cut -f1); NEED=75; QUOTA=${VOLUME_GB:-250}
echo "volume: ${USED} GB used of ${QUOTA} GB, this download needs about ${NEED} GB"
if [ $((USED + NEED + 20)) -gt "$QUOTA" ]; then echo "NOT ENOUGH ROOM: stopping before downloading anything"; exit 3; fi
dl(){ mkdir -p "$1"; [ -s "$1/$2" ] && [ ! -e "$1/$2.aria2" ] && { echo "skip $2"; return; }; echo "$(date +%T) GET $2"
      if [ "${4:-}" = gated ]; then aria2c -q -x8 -s8 -c --file-allocation=none --header="Authorization: Bearer $TOK" -d "$1" -o "$2" "$3"; else aria2c -q -x8 -s8 -c --file-allocation=none -d "$1" -o "$2" "$3"; fi \
      && echo "$(date +%T) OK $2 $(du -h "$1/$2" | cut -f1)" || echo "FAILED $2"; }
W=https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files
dl diffusion_models wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors "$W/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
dl diffusion_models wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors "$W/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"
dl loras wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors "$W/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"
dl loras wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors "$W/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"
dl vae wan_2.1_vae.safetensors "$W/vae/wan_2.1_vae.safetensors"
dl text_encoders umt5_xxl_fp8_e4m3fn_scaled.safetensors "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
L=https://huggingface.co/Lightricks/LTX-2.5/resolve/main
dl diffusion_models ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors "$L/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" gated
dl text_encoders gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors "$L/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" gated
dl vae ltx-2.5-video-vae-bf16.safetensors "$L/vae/ltx-2.5-video-vae-bf16.safetensors" gated
dl vae ltx-2.5-audio-vae-bf16.safetensors "$L/vae/ltx-2.5-audio-vae-bf16.safetensors" gated
dl latent_upscale_models ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors "$L/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" gated
echo "AFTER $(df -h /workspace | tail -1)"
echo "VIDEO_MODELS_DOWNLOAD_DONE $(date +%T)"
