#!/bin/bash
# Chatterbox on the genrush volume. venv on the pod's LOCAL disk, built ON TOP of the image's torch (--system-site-packages):
# chatterbox-tts 0.1.3 pins torch 2.6/cu124, which has no kernels for the RTX PRO 6000 Blackwell (sm_120) the pod sometimes lands on.
# The image's torch 2.8/cu128 runs ComfyUI on every GPU we get, so Chatterbox uses that one. Tarred to the volume for instant boots.
set -x
mkdir -p /workspace/.hf/hub /workspace/.pipcache /workspace/chatterbox /workspace/genrush/voices
export HF_HOME=/workspace/.hf PIP_CACHE_DIR=/workspace/.pipcache HF_HUB_ENABLE_HF_TRANSFER=0
if [ "${1:-}" = "--rebuild" ]; then rm -rf /root/cbvenv /workspace/chatterbox/venv.tgz; fi
if [ -f /workspace/chatterbox/venv.tgz ] && [ ! -x /root/cbvenv/bin/python ]; then echo "=== EXTRACT cached venv ==="; tar xzf /workspace/chatterbox/venv.tgz -C /root; fi
[ -x /root/cbvenv/bin/python ] || python3 -m venv --system-site-packages /root/cbvenv
P=/root/cbvenv/bin/python; $P -m pip install -q -U pip wheel
if ! $P -c 'import chatterbox' 2>/dev/null; then
  echo "=== INSTALL chatterbox-tts==0.1.3 WITHOUT its torch pin ==="
  $P -m pip install -q numpy cython setuptools
  $P -m pip install -q --no-build-isolation pkuseg || echo "pkuseg no-isolation failed, continuing"
  $P -m pip install -q --no-deps chatterbox-tts==0.1.3 || { echo FAILED_PIP; exit 1; }
  DEPS=$($P - <<'PY'
from importlib.metadata import requires
import re
out=[]
for r in requires("chatterbox-tts") or []:
    name=re.split(r"[ ;<>=!\[]", r)[0].lower()
    if name in ("torch","torchaudio") or "extra ==" in r: continue
    out.append(r.split(";")[0].strip())
print(" ".join(f'"{d}"' for d in out))
PY
)
  echo "deps: $DEPS"; eval $P -m pip install -q $DEPS || { echo FAILED_DEPS; exit 1; }
  $P -c 'import torchaudio' 2>/dev/null || $P -m pip install -q torchaudio --index-url https://download.pytorch.org/whl/cu128
  echo "=== TAR venv -> volume ==="; tar czf /workspace/chatterbox/venv.tgz.tmp -C /root cbvenv && mv /workspace/chatterbox/venv.tgz.tmp /workspace/chatterbox/venv.tgz
fi
$P -c 'import torch,torchaudio,chatterbox;print("CHECK cuda",torch.cuda.is_available(),"torch",torch.__version__,"torchaudio",torchaudio.__version__,"gpu",torch.cuda.get_device_name(0))' || { echo FAILED_CHECK; exit 1; }
echo "=== clone test ==="
$P /workspace/genrush/chatterbox_gen.py /workspace/genrush/voices/wnba_ref.wav /workspace/genrush/voices/test_lines.json /workspace/genrush/voices/test_out || { echo FAILED_CLONE; exit 1; }
echo PROVISION_DONE
