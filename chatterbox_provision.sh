#!/bin/bash
# Chatterbox on the genrush volume: venv on the pod's LOCAL disk (network volume is slow for thousands of small files),
# tarred to /workspace/chatterbox/venv.tgz so every future boot extracts it in seconds (boot.sh does that). HF model cache on the volume.
set -x
mkdir -p /workspace/.hf/hub /workspace/.pipcache /workspace/chatterbox /workspace/genrush/voices
export HF_HOME=/workspace/.hf PIP_CACHE_DIR=/workspace/.pipcache
if [ -f /workspace/chatterbox/venv.tgz ] && [ ! -x /root/cbvenv/bin/python ]; then echo "=== EXTRACT cached venv ==="; tar xzf /workspace/chatterbox/venv.tgz -C /root; fi
[ -x /root/cbvenv/bin/python ] || python3 -m venv /root/cbvenv
/root/cbvenv/bin/pip install -q -U pip wheel
if ! /root/cbvenv/bin/python -c 'import chatterbox' 2>/dev/null; then
  echo "=== INSTALL chatterbox-tts==0.1.3 (pinned, MAR-1202 manifest) ==="
  # python 3.12 image: a dependency (pkuseg) builds from source and imports numpy in setup.py; give it numpy + cython outside build isolation
  /root/cbvenv/bin/pip install -q numpy cython setuptools
  /root/cbvenv/bin/pip install -q --no-build-isolation pkuseg || echo "pkuseg no-isolation install failed, continuing"
  /root/cbvenv/bin/pip install -q chatterbox-tts==0.1.3 || { echo FAILED_PIP; exit 1; }
  echo "=== TAR venv -> volume ==="; tar czf /workspace/chatterbox/venv.tgz.tmp -C /root cbvenv && mv /workspace/chatterbox/venv.tgz.tmp /workspace/chatterbox/venv.tgz
fi
/root/cbvenv/bin/python -c 'import torch,chatterbox;print("CHECK cuda",torch.cuda.is_available(),"torch",torch.__version__)' || { echo FAILED_CHECK; exit 1; }
echo "=== warm the model cache + clone test ==="
/root/cbvenv/bin/python /workspace/genrush/chatterbox_gen.py /workspace/genrush/voices/wnba_ref.wav /workspace/genrush/voices/test_lines.json /workspace/genrush/voices/test_out && echo CLONE_TEST_OK
echo PROVISION_DONE
