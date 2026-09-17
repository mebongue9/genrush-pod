#!/bin/bash
# MiniMax H3 image-to-video (+ native audio) models for the I2V/FL2V template. ~44 GB. Idempotent, aria2 resumes.
set -u
command -v aria2c >/dev/null || { echo "installing aria2 (container disk is fresh on every pod)"; apt-get update -y >/dev/null 2>&1; apt-get install -y aria2 >/dev/null 2>&1; }
cd /workspace/models
dl(){ mkdir -p "$1"; [ -s "$1/$2" ] && { echo "skip $2"; return; }; echo "$(date +%T) GET $2"; aria2c -q -x8 -s8 -c --file-allocation=none -d "$1" -o "$2" "$3" || echo "FAILED $2"; }
B=https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main
dl diffusion_models minimax_h3_fl2va_pruned_int8_convrot.safetensors "$B/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"
dl text_encoders qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors "$B/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
dl vae minimax_h3_video_vae_fp16.safetensors "$B/vae/minimax_h3_video_vae_fp16.safetensors"
dl vae minimax_h3_audio_vae_fp32.safetensors "$B/vae/minimax_h3_audio_vae_fp32.safetensors"
dl loras minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors "$B/loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors"
echo "H3_DOWNLOAD_DONE $(date +%T)"; du -sh /workspace/models
