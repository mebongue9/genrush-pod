#!/usr/bin/env bash
# genrush pod boot (dockerStartCmd). Runs on every fresh pod. NO apt, NO pip: everything lives on the volume.
# Fetched by the pod's start command from GitHub, so a pod needs nothing but the volume to come up.
set -u
W=/workspace; G=$W/genrush; C=$W/ComfyUI; V=$W/venv; B=$W/bin
T0=$(date +%s)
# BOOT TELEMETRY: every boot appends one JSON line to the volume, so a slow or failed pod can be investigated
# afterwards from data instead of guesses (which host, which phase, how fast the storage and CPU were).
mkdir -p $G/logs
BOOTLOG=$G/logs/boots.jsonl
POD=${RUNPOD_POD_ID:-unknown}
ev() { echo "{\"pod\":\"$POD\",\"t\":$(( $(date +%s) - T0 )),\"event\":\"$1\"${2:+,$2}}" >> $BOOTLOG; }
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
CPU=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //;s/"//g')
ev boot_start "\"gpu\":\"$GPU\",\"cpu\":\"$CPU\",\"cores\":$(nproc),\"ram_gb\":$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1048576 )),\"when\":\"$(date -u +%FT%TZ)\""
RAW=https://raw.githubusercontent.com/mebongue9/genrush-pod/main
mkdir -p $G/logs $B
fetch() { curl -sfL "$1" -o "$2" || python3 -c "import urllib.request,sys;urllib.request.urlretrieve(sys.argv[1],sys.argv[2])" "$1" "$2"; }
fetch $RAW/pod_agent.py $G/pod_agent.py
ev agent_fetched
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
  ( U0=$(date +%s)
    SZ=$(( $(stat -c %s $W/chatterbox/venv.tgz) / 1048576 ))
    # storage read speed on THIS host: first 1 GB of the tarball, bypassing nothing, just timed
    R0=$(date +%s%N); dd if=$W/chatterbox/venv.tgz of=/dev/null bs=4M count=256 2>/dev/null; R1=$(date +%s%N)
    MBS=$(( 1024 * 1000000000 / ( R1 - R0 + 1 ) ))
    tar xzf $W/chatterbox/venv.tgz -C /root && touch /root/cbvenv/.ready
    ev venv_unpacked "\"seconds\":$(( $(date +%s) - U0 )),\"tarball_mb\":$SZ,\"volume_read_mb_s\":$MBS" ) &
fi
export HF_HOME=$W/.hf PATH=$B:$V/bin:$PATH
python3 $G/pod_agent.py 8000 >> $G/logs/agent.out 2>&1 &
echo "[boot] agent on 8000"
ev agent_started
if [ ! -x $V/bin/python ] || [ ! -f $C/main.py ]; then
  echo "[boot] SETUP MODE: no venv/ComfyUI on this volume yet; agent only. Run pod_bootstrap.sh + pod_download_models.sh through the agent."
  exec sleep infinity
fi
ev comfy_starting
# log the moment ComfyUI actually answers, so "ComfyUI startup" is measured, not inferred
( for i in $(seq 1 600); do curl -sf -m 2 http://127.0.0.1:8188/system_stats >/dev/null && { ev comfy_answering; break; }; sleep 1; done ) &
cd $C && exec $V/bin/python main.py --listen 0.0.0.0 --port 8188 --output-directory $W/output --preview-method auto 2>&1 | tee -a $G/comfy.log
