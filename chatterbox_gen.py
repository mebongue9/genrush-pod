#!/usr/bin/env python3
"""Chatterbox batch TTS with a cloned voice. Loads the model ONCE, synthesizes every line, writes <out>/<i>.wav at 24 kHz mono.
  /root/cbvenv/bin/python chatterbox_gen.py <ref.wav> <lines.json> <outdir>     lines.json = ["sentence", ...]
Called by pod_episode.py --tts chatterbox. Settings: exaggeration 0.5, cfg_weight 0.5 (Chatterbox defaults; the WNBA clone was judged on these)."""
import json, os, sys, time
os.environ.setdefault("HF_HOME", "/workspace/.hf"); os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "0"   # the RunPod image sets it to 1 but the venv has no hf_transfer
import torch, torchaudio
from chatterbox.tts import ChatterboxTTS
ref, lines, out = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3]
os.makedirs(out, exist_ok=True)
t0 = time.time(); model = ChatterboxTTS.from_pretrained(device="cuda"); print(f"model loaded {time.time()-t0:.1f}s sr={model.sr}", flush=True)
for i, s in enumerate(lines):
    w = model.generate(s, audio_prompt_path=ref, exaggeration=0.5, cfg_weight=0.5, temperature=0.7)
    if model.sr != 24000:
        w = torchaudio.functional.resample(w, model.sr, 24000)
    torchaudio.save(f"{out}/{i:03d}.wav", w.cpu(), 24000)
    print(f"{i:03d} {w.shape[-1]/24000:.1f}s {s[:50]}", flush=True)
print(f"DONE {len(lines)} lines in {time.time()-t0:.0f}s", flush=True)
