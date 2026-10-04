#!/bin/bash
# Open video models for the footage test (Martin, 2026-10-04): Wan 2.2 14B image-to-video (Apache 2.0) and LTX 2.5
# distilled (gated: the Hugging Face token is read from /workspace/genrush/.hf_token, never stored in this repo).
# What to do is read from /workspace/genrush/video_models.plan, a list of words:  wan  ltx  rm-wan  rm-ltx
# It only ever touches the files named below. The volume is shared with the space pipeline (250 GB): a set is
# downloaded only if it fits with 20 GB to spare. Idempotent, aria2 resumes.
set -u
command -v aria2c >/dev/null || { echo "installing aria2 (container disk is fresh on every pod)"; apt-get update -y >/dev/null 2>&1; apt-get install -y aria2 >/dev/null 2>&1; }
TOK=$(cat /workspace/genrush/.hf_token 2>/dev/null || true)
PLAN=$(cat /workspace/genrush/video_models.plan 2>/dev/null || true)
QUOTA=${VOLUME_GB:-250}
cd /workspace/models
W=https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files
L=https://huggingface.co/Lightricks/LTX-2.5/resolve/main
# set | folder | file | url | gated
FILES="wan|diffusion_models|wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|$W/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|
wan|diffusion_models|wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|$W/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|
wan|vae|wan_2.1_vae.safetensors|$W/vae/wan_2.1_vae.safetensors|
wan|text_encoders|umt5_xxl_fp8_e4m3fn_scaled.safetensors|https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|
ltx|diffusion_models|ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors|$L/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors|gated
ltx|text_encoders|gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors|$L/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors|gated
ltx|vae|ltx-2.5-video-vae-bf16.safetensors|$L/vae/ltx-2.5-video-vae-bf16.safetensors|gated
ltx|vae|ltx-2.5-audio-vae-bf16.safetensors|$L/vae/ltx-2.5-audio-vae-bf16.safetensors|gated
ltx|latent_upscale_models|ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors|$L/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors|gated"
need_gb(){ case "$1" in wan) echo 36;; ltx) echo 41;; *) echo 0;; esac; }
used_gb(){ du -s --block-size=1G /workspace 2>/dev/null | cut -f1; }
RC=0
echo "plan: $PLAN"
for step in $PLAN; do
  case "$step" in
    rm-wan|rm-ltx)
      set_=${step#rm-}
      echo "$FILES" | while IFS='|' read -r s folder name url gated; do [ "$s" = "$set_" ] && [ -e "$folder/$name" ] && { rm -f "$folder/$name" "$folder/$name.aria2"; echo "removed $name"; }; done ;;
    wan|ltx)
      USED=$(used_gb); NEED=$(need_gb "$step")
      HAVE=$(echo "$FILES" | while IFS='|' read -r s folder name url gated; do [ "$s" = "$step" ] && [ -s "$folder/$name" ] && [ ! -e "$folder/$name.aria2" ] && echo x; done | wc -l)
      WANT=$(echo "$FILES" | grep -c "^$step|")
      echo "volume: ${USED} GB used of ${QUOTA} GB; set '$step' needs about ${NEED} GB ($HAVE of $WANT files already there)"
      if [ "$HAVE" -lt "$WANT" ] && [ $((USED + NEED + 20)) -gt "$QUOTA" ]; then echo "NOT ENOUGH ROOM for $step: nothing downloaded"; RC=3; continue; fi
      echo "$FILES" | while IFS='|' read -r s folder name url gated; do
        [ "$s" = "$step" ] || continue
        mkdir -p "$folder"
        if [ -s "$folder/$name" ] && [ ! -e "$folder/$name.aria2" ]; then echo "skip $name"; continue; fi
        echo "$(date +%T) GET $name"
        if [ "$gated" = gated ]; then aria2c -q -x8 -s8 -c --file-allocation=none --header="Authorization: Bearer $TOK" -d "$folder" -o "$name" "$url"; else aria2c -q -x8 -s8 -c --file-allocation=none -d "$folder" -o "$name" "$url"; fi \
          && echo "$(date +%T) OK $name $(du -h "$folder/$name" | cut -f1)" || echo "FAILED $name"
      done ;;
    *) echo "unknown step: $step"; RC=4 ;;
  esac
done
echo "AFTER volume: $(used_gb) GB used of ${QUOTA} GB"
echo "VIDEO_MODELS_DOWNLOAD_DONE $(date +%T) rc=$RC"
exit $RC
