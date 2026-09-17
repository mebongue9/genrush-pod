#!/usr/bin/env bash
# One-time volume setup, run on the pod through the agent (no SSH). Idempotent. 2026-09-17: EU-RO-1 volume genrush-models-ro.
set -u
W=/workspace; G=$W/genrush; M=$W/models; F=$W/fonts
echo "== [1] bootstrap (ComfyUI + venv on the volume)"; bash $G/pod_bootstrap.sh 2>&1 | tail -4
echo "== [2] audio deps"; $W/venv/bin/pip install -q soundfile faster-whisper 2>&1 | tail -1
echo "== [3] models (only what the presets use)"; cd $M
dl(){ mkdir -p "$1"; [ -s "$1/$2" ] && { echo "skip $2"; return; }; echo "$(date +%T) GET $2"; aria2c -q -x8 -s8 -c --file-allocation=none -d "$1" -o "$2" "$3" || echo "FAILED $2"; }
dl diffusion_models z_image_turbo_bf16.safetensors "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
dl text_encoders qwen_3_4b.safetensors "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
dl vae ae.safetensors "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
dl diffusion_models flux2_dev_fp8mixed.safetensors "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors"
dl text_encoders mistral_3_small_flux2_fp8.safetensors "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/text_encoders/mistral_3_small_flux2_fp8.safetensors"
dl vae flux2-vae.safetensors "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
dl loras Flux_2-Turbo-LoRA_comfyui.safetensors "https://huggingface.co/fal/FLUX.2-dev-Turbo/resolve/main/comfy/Flux_2-Turbo-LoRA_comfyui.safetensors"
echo "== [4] fonts"; mkdir -p $F; cd $F
for u in ofl/anton/Anton-Regular.ttf ofl/poppins/Poppins-Bold.ttf ofl/poppins/Poppins-SemiBold.ttf ofl/patrickhand/PatrickHand-Regular.ttf; do
  b=$(basename $u); [ -s $b ] || curl -sfL "https://github.com/google/fonts/raw/main/$u" -o $b || echo "FAILED font $b"; done
ls -la $F
echo "== [5] check"; ls $M/diffusion_models $M/text_encoders $M/vae $M/loras; du -sh $M; $W/venv/bin/python -c "import faster_whisper, soundfile; print('audio deps ok')"
echo "SETUP_VOLUME_DONE"
