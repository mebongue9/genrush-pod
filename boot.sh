#!/usr/bin/env bash
# genrush pod boot (dockerStartCmd). Runs on every fresh pod. NO apt, NO pip: everything lives on the volume.
# Fetched by the pod's start command from GitHub, so a pod needs nothing but the volume to come up.
set -u
W=/workspace; G=$W/genrush; C=$W/ComfyUI; V=$W/venv; B=$W/bin
RAW=https://raw.githubusercontent.com/mebongue9/genrush-pod/main
mkdir -p $G/logs $B
fetch() { curl -sfL "$1" -o "$2" || python3 -c "import urllib.request,sys;urllib.request.urlretrieve(sys.argv[1],sys.argv[2])" "$1" "$2"; }
fetch $RAW/pod_agent.py $G/pod_agent.py
# static ffmpeg with nvenc, once, on the volume (BtbN gpl build)
if [ ! -x $B/ffmpeg ]; then
  echo "[boot] fetching static ffmpeg"
  fetch https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz /tmp/ff.tar.xz \
    && tar -xJf /tmp/ff.tar.xz -C /tmp && cp /tmp/ffmpeg-master-latest-linux64-gpl/bin/ff* $B/ && chmod +x $B/ff*
fi
# Chatterbox venv (several GB) unpacks from the volume IN THE BACKGROUND. It used to run in the foreground and
# blocked the agent + ComfyUI for minutes: boot went from ~90 s to 247 s and one pod crossed the 300 s readiness
# limit and was destroyed (2026-09-17). pod_episode.py waits for /root/cbvenv/.ready before the voice stage.
if [ -f $W/chatterbox/venv.tgz ] && [ ! -f /root/cbvenv/.ready ]; then
  ( tar xzf $W/chatterbox/venv.tgz -C /root && touch /root/cbvenv/.ready && echo "[boot] chatterbox venv ready" >> $G/logs/agent.out ) &
fi
export HF_HOME=$W/.hf PATH=$B:$V/bin:$PATH
python3 $G/pod_agent.py 8000 >> $G/logs/agent.out 2>&1 &
echo "[boot] agent on 8000"
if [ ! -x $V/bin/python ] || [ ! -f $C/main.py ]; then
  echo "[boot] SETUP MODE: no venv/ComfyUI on this volume yet; agent only. Run pod_bootstrap.sh + pod_download_models.sh through the agent."
  exec sleep infinity
fi
cd $C && exec $V/bin/python main.py --listen 0.0.0.0 --port 8188 --output-directory $W/output --preview-method auto 2>&1 | tee -a $G/comfy.log
