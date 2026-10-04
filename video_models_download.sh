#!/bin/bash
# Open video models for the footage test (Martin, 2026-10-04): Wan 2.2 14B image-to-video (Apache 2.0) and LTX 2.5
# distilled (gated: the Hugging Face token is read from <workspace>/genrush/.hf_token, never stored in this repo).
# What to do is read from <workspace>/genrush/video_models.plan, a list of words:  wan  ltx  rm-wan  rm-ltx
# It only ever touches the files named below. The volume is shared with the space pipeline (250 GB): the missing
# files of a set are downloaded only if they fit with 20 GB to spare. Idempotent, aria2 resumes.
# WORKSPACE and USED_GB_OVERRIDE exist so the logic can be tested off the pod.
set -u
WS=${WORKSPACE:-/workspace}
command -v aria2c >/dev/null || { echo "installing aria2 (container disk is fresh on every pod)"; apt-get update -y >/dev/null 2>&1; apt-get install -y aria2 >/dev/null 2>&1; }
TOK=$(cat "$WS/genrush/.hf_token" 2>/dev/null || true)
PLAN=$(cat "$WS/genrush/video_models.plan" 2>/dev/null || true)
QUOTA=${VOLUME_GB:-250}
cd "$WS/models" || exit 5
W=https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files
L=https://huggingface.co/Lightricks/LTX-2.5/resolve/main
UP=$WS/ComfyUI/models/latent_upscale_models
# set | folder | file | url | gated | size in GB (rounded up)
FILES="wan|diffusion_models|wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|$W/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors||14
wan|diffusion_models|wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|$W/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors||14
wan|vae|wan_2.1_vae.safetensors|$W/vae/wan_2.1_vae.safetensors||1
wan|text_encoders|umt5_xxl_fp8_e4m3fn_scaled.safetensors|https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors||7
ltx|diffusion_models|ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors|$L/diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors|gated|21
ltx|text_encoders|gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors|$L/text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors|gated|15
ltx|vae|ltx-2.5-video-vae-bf16.safetensors|$L/vae/ltx-2.5-video-vae-bf16.safetensors|gated|2
ltx|vae|ltx-2.5-audio-vae-bf16.safetensors|$L/vae/ltx-2.5-audio-vae-bf16.safetensors|gated|1
ltx|text_encoders|gemma4_e2b_it_int8_convrot.safetensors|https://huggingface.co/Comfy-Org/gemma-4/resolve/main/text_encoders/gemma4_e2b_it_int8_convrot.safetensors||5
ltx|$UP|ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors|$L/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors|gated|1"
present(){ [ -s "$1/$2" ] && [ ! -e "$1/$2.aria2" ]; }
used_gb(){ if [ -n "${USED_GB_OVERRIDE:-}" ]; then echo "$USED_GB_OVERRIDE"; else du -s --block-size=1G "$WS" 2>/dev/null | cut -f1; fi; }
RC=0
echo "plan: $PLAN"
# ComfyUI on this volume only reads latent upscalers from its own models folder (extra_model_paths.yaml has no entry for
# them): a copy that an earlier run put under <workspace>/models is moved to where ComfyUI looks.
U=ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors
if [ -s "latent_upscale_models/$U" ]; then mkdir -p "$UP" && mv "latent_upscale_models/$U" "$UP/" && echo "moved $U to ComfyUI's folder"; rmdir latent_upscale_models 2>/dev/null; fi
for step in $PLAN; do
  case "$step" in
    rm-wan|rm-ltx)
      set_=${step#rm-}
      while IFS='|' read -r s folder name url gated gb; do
        [ "$s" = "$set_" ] && [ -e "$folder/$name" ] && { rm -f "$folder/$name" "$folder/$name.aria2"; echo "removed $name"; }
      done <<< "$FILES" ;;
    wan|ltx)
      USED=$(used_gb); NEED=0; MISSING=0
      while IFS='|' read -r s folder name url gated gb; do
        [ "$s" = "$step" ] || continue
        present "$folder" "$name" || { NEED=$((NEED + gb)); MISSING=$((MISSING + 1)); }
      done <<< "$FILES"
      echo "volume: ${USED} GB used of ${QUOTA} GB; set '$step': $MISSING file(s) missing, about ${NEED} GB to download"
      if [ "$MISSING" -gt 0 ] && [ $((USED + NEED + 20)) -gt "$QUOTA" ]; then echo "NOT ENOUGH ROOM for $step: nothing downloaded"; RC=3; continue; fi
      while IFS='|' read -r s folder name url gated gb; do
        [ "$s" = "$step" ] || continue
        mkdir -p "$folder"
        if present "$folder" "$name"; then echo "skip $name"; continue; fi
        echo "$(date +%T) GET $name"
        if [ "$gated" = gated ]; then aria2c -q -x8 -s8 -c --file-allocation=none --header="Authorization: Bearer $TOK" -d "$folder" -o "$name" "$url"; else aria2c -q -x8 -s8 -c --file-allocation=none -d "$folder" -o "$name" "$url"; fi
        if present "$folder" "$name"; then echo "$(date +%T) OK $name $(du -h "$folder/$name" | cut -f1)"; else echo "FAILED $name"; RC=6; fi
      done <<< "$FILES" ;;
    *) echo "unknown step: $step"; RC=4 ;;
  esac
done
echo "AFTER volume: $(used_gb) GB used of ${QUOTA} GB"
echo "VIDEO_MODELS_DOWNLOAD_DONE $(date +%T) rc=$RC"
exit $RC
