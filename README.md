# Audio Server – Audirvana + Diretta RT Linux

High-performance Linux audio server optimized for **low-latency network audio streaming** using **Audirvana Core** and **Diretta**.

System designed as a **dedicated audio transport server** with deterministic scheduling, **RT kernel**, and optimized **network stack**.

---

# 1. System Overview

| Parameter | Value |
|---|---|
Host | `audio-server`
Kernel | `6.12.73+deb13-rt-amd64`
OS | Debian RT
Role | Audio streaming server

### Server responsibilities

- Audirvana Studio **Core server**
- music **file server (SMB / NFS)**
- **Diretta streaming host**
- **network audio transport**

---

# 2. Audio Architecture

```
Audirvana Core
      │
      │ TCP audio stream
      │
Diretta Host
      │
      │ LAN
      │
Diretta Target
      │
USB / I2S
      │
AudioGD R1 R2R DAC
```

### Additional network devices

| Device | Role |
|---|---|
NVIDIA Shield | Kodi playback |
Android / iOS | Audirvana Remote |
Storage | `/mnt/music` |

---

# 3. Full System Diagram

```
                         INTERNET
                             │
                        ROUTER / SWITCH
                             │
            ┌────────────────┴─────────────────┐
            │                                  │
     10.0.0.200                          10.0.0.24
      audio-server                      Diretta Target
      (Debian RT)                         (renderer)
            │                                  │
     Audirvana Studio                    Diretta Engine
        Core Server                            │
            │                                  │
        UPnP stream                        USB / I2S
            │                                  │
         LAN TCP                           AudioGD R1
            │                                  │
            └──────────────►  DAC  ◄───────────┘
                                  │
                               Amplifier
                                  │
                               Speakers
```

---

# 4. Kernel

### Kernel version

```
6.12.73+deb13-rt-amd64
```

### Kernel type

```
PREEMPT_RT
```

### Purpose

- deterministic scheduling
- reduced interrupt latency
- stable network audio timing
- optimized IRQ handling

---

# 5. Kernel Boot Parameters

### GRUB kernel parameters

```
intel_pstate=disable
isolcpus=2,3
nohz_full=2,3
rcu_nocbs=2,3
intel_idle.max_cstate=1
processor.max_cstate=1
nosoftlockup
mitigations=off
nosmt
noibrs
noibpb
spectre_v2=off
l1tf=off
mds=off
tsx=on
no_stf_barrier
nopti
ipv6.disable=1
```

### CPU Isolation

```
isolcpus
nohz_full
rcu_nocbs
```

Separates audio threads from system workload.

```
CPU0-1 → system
CPU2-3 → audio
```

---

# 6. Power Management

Disabled deep sleep states:

```
intel_idle.max_cstate=1
processor.max_cstate=1
```

Goal:

- lower wake latency
- stable CPU timing

---

# 7. Audirvana Core

Audirvana runs as a **systemd service**.

### Service file

```
/etc/systemd/system/audirvanaStudio.service
```

### Configuration

```ini
[Unit]
Description=Run audirvanaStudio
After=network.target avahi-daemon.service

[Service]
User=audirvana
ExecStart=/opt/audirvana/studio/audirvanaStudio --server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Activation

```
sudo systemctl daemon-reload
sudo systemctl enable audirvanaStudio
sudo systemctl start audirvanaStudio
```

### Status

```
systemctl status audirvanaStudio
```

---

# 8. Audirvana Networking

### Audirvana services

| Service | Port |
|---|---|
RemoteServer | dynamic |
UPnP | 49152 |

Example:

```
RemoteServer: 38769
UPnP: 49152
```

Discovery:

```
Avahi / mDNS
```

Remote control:

```
Audirvana Remote App
```

---

# 9. Sysctl Tuning

Network and kernel tuning optimized for **low-latency audio streaming**.

## Network Scheduler

```
net.core.default_qdisc = fq
```

## Network Queue

```
net.core.netdev_max_backlog = 250
net.core.netdev_budget = 150
```

## Busy Polling

```
net.core.busy_poll = 50
net.core.busy_read = 50
```

## TCP Audio Tuning

```
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_tso_win_divisor = 8
```

### Memory Tuning

```
vm.swappiness = 1
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
```

### RT Scheduler

```
kernel.sched_rt_runtime_us = -1
```

### Timer Migration

```
kernel.timer_migration = 0
```

### Watchdog

```
kernel.watchdog = 0
kernel.nmi_watchdog = 0
```

---

# 10. Intel NIC Tuning

### Interface

```
eno1
```

### Offloads disabled

```
TSO
GSO
GRO
LRO
```

### Ring Buffers

```
RX = 256
TX = 256
```

### Interrupt Coalescing

```
rx-usecs = 0
```

---

# 11. Storage

### Music location

```
/mnt/music/Music
```

### Access protocols

- SMB
- NFS

### Library monitoring

```
inotify
```

### Limit

```
fs.inotify.max_user_watches = 524288
```

---

# 12. Diretta

### Renderer type

```
Diretta Renderer
```

### Endpoint

```
http://10.0.0.24:1332
```

### Streaming method

```
UPnP → Diretta
```

---

# 13. Network Layout

| Device | IP |
|---|---|
audio-server | `10.0.0.200`
Diretta renderer | `10.0.0.24`
Kodi (Shield) | `10.0.0.150`

---

# 14. System State

System optimized for:

- RT Linux kernel
- Audirvana Core
- Diretta streaming
- low-latency networking
- stable TCP audio

---

# 15. Stability

Current system behavior:

✔ Audirvana starts automatically  
✔ Diretta renderer auto-detected  
✔ stable network connection  
✔ NIC offloads disabled  
✔ RT kernel active  

System functions as:

**dedicated Linux audio server**

---

# 16. Key Optimizations

### 1. RT Kernel

```
PREEMPT_RT
```

### 2. Network Stack

```
GRO/GSO/TSO disabled
EEE disabled
fq scheduler
```

### 3. CPU Isolation

```
isolcpus
nohz_full
rcu_nocbs
```

---

# 17. Rebuilding the System

Installation order:

```
1 install Debian
2 install RT kernel
3 configure kernel boot parameters
4 configure sysctl tuning
5 configure NIC tuning
6 install Audirvana
7 configure systemd service
8 configure storage (/mnt/music)
9 configure Diretta renderer
```

---

# License

Documentation only.

Configuration intended for **personal high-performance audio systems**.
