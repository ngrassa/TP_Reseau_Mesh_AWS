#!/bin/bash
#============================================================================
# provision.sh — Provisioning d'un nœud mesh OLSR
# Usage : provision.sh <IP_PRIVÉE>
# Auteur : Pr Noureddine GRASSA — ISET Sousse
# Note  : Compilation depuis les sources (olsrd absent des dépôts 22.04)
#============================================================================

set -e

NODE_IP="$1"

if [ -z "$NODE_IP" ]; then
  echo "Usage: $0 <IP_PRIVÉE>"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "══════════════════════════════════════════"
echo "  Provisioning nœud mesh : $NODE_IP"
echo "══════════════════════════════════════════"

# ── 1. Installation des dépendances ───────────────────────────────────────
echo "[1/5] Installation des dépendances..."
apt-get update -qq
apt-get install -y -qq build-essential git flex bison libgps-dev \
  net-tools tcpdump iperf3 traceroute > /dev/null 2>&1
echo "  ✓ Dépendances installées"

# ── 2. Compilation OLSRd depuis les sources ───────────────────────────────
echo "[2/5] Compilation OLSRd depuis les sources..."
cd /tmp

if [ ! -d "olsrd" ]; then
  git clone https://github.com/OLSR/olsrd.git --depth 1 2>/dev/null
fi

cd olsrd
make -j$(nproc) > /dev/null 2>&1
make install > /dev/null 2>&1

# Compiler les plugins (txtinfo pour monitoring)
cd lib/txtinfo
make -j$(nproc) > /dev/null 2>&1
make install > /dev/null 2>&1
cd /tmp

echo "  ✓ OLSRd compilé et installé"

# ── 3. Détection de l'interface réseau ────────────────────────────────────
echo "[3/5] Configuration réseau..."

MESH_IFACE=$(ip -4 addr show | grep "10.0.1" | awk '{print $NF}')

if [ -z "$MESH_IFACE" ]; then
  MESH_IFACE="ens5"
fi

echo "  Interface mesh détectée : $MESH_IFACE"

# ── 4. Configuration OLSRd ────────────────────────────────────────────────
echo "[4/5] Configuration OLSRd..."

mkdir -p /etc/olsrd

cat > /etc/olsrd/olsrd.conf <<OLSR_CONF
# ─── Configuration OLSRd pour TP Mesh ───
# Nœud : $NODE_IP

DebugLevel  1
IpVersion   4

HelloInterval       2.0
HelloValidityTime   6.0
TcInterval          5.0
TcValidityTime      15.0
MidInterval         5.0
MidValidityTime     15.0
HnaInterval         5.0
HnaValidityTime     15.0

UseHysteresis       yes
HystScaling         0.50
HystThrHigh         0.80
HystThrLow          0.30

LinkQualityLevel            2
LinkQualityFishEye          1
LinkQualityAlgorithm        "etx_ff"

Interface "$MESH_IFACE"
{
    HelloInterval       2.0
    HelloValidityTime   6.0
    TcInterval          5.0
    TcValidityTime      15.0
}

# Plugin txtinfo pour monitoring (port 2006)
LoadPlugin "olsrd_txtinfo.so.1.1"
{
    PlParam "port"   "2006"
    PlParam "accept" "0.0.0.0"
}
OLSR_CONF

echo "  ✓ OLSRd configuré sur $MESH_IFACE"

# ── 5. Activer le forwarding IP et démarrer OLSRd ────────────────────────
echo "[5/5] Activation du routage et démarrage OLSRd..."

sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

for f in /proc/sys/net/ipv4/conf/*/rp_filter; do
  echo 0 > "$f"
done

cat > /etc/systemd/system/olsrd.service <<SERVICE
[Unit]
Description=OLSR Mesh Routing Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/olsrd -f /etc/olsrd/olsrd.conf -nofork
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable olsrd
systemctl start olsrd

echo ""
echo "══════════════════════════════════════════"
echo "  ✓ Nœud $NODE_IP provisionné !"
echo "  OLSRd actif sur $MESH_IFACE"
echo "  Monitoring : curl http://$NODE_IP:2006/all"
echo "══════════════════════════════════════════"
