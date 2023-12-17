#! /bin/bash

## Install essential packages
sudo apt-get update && sudo apt upgrade -y 
sudo apt-get install make build-essential gcc git jq chrony -y

# sudo snap install go --classic 
# echo "PATH=~/go/bin:$PATH" >> ~/.profile
# source ~/.profile
wget https://golang.org/dl/go1.18.10.linux-amd64.tar.gz
cat <<EOF >> ~/.profile
export MONIKER_NAME="CHANGE_ME"
EXPORT LIVE_RPC_NODE="http://35.241.221.154:26657"
export CHAIN_ID="odin-mainnet-freya"
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF
source ~/.profile
go version

## Clone odin repo and build from source
git clone https://github.com/ODIN-PROTOCOL/odin-core.git
cd odin-core
git fetch --tags
git checkout v0.6.2
make all
mkdir -p ~/.odin/cosmovisor/genesis/bin
cp ~/go/bin/odind ~/.odin/cosmovisor/genesis/bin/
cd ..
odind version

## Download cosmovisor
wget https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.1.0/cosmovisor-v1.1.0-linux-amd64.tar.gz ; tar xvfz  cosmovisor-v1.1.0-linux-amd64.tar.gz -C ~/go/bin/

## Set external_address in config.toml
sed -i "s/external_address = \"\"/external_address = \"$(echo $(curl ifconfig.me):26656)\"/" .odin/config/config.toml

## Setup statesync
SNAP_RPC="http://34.79.179.216:26657,http://34.140.252.7:26657,http://35.241.221.154:26657,http://35.241.238.207:26657"
RPC_ADDR="http://34.79.179.216:26657"
INTERVAL=2000

LATEST_HEIGHT=$(curl -s $RPC_ADDR/block | jq -r .result.block.header.height);
BLOCK_HEIGHT=$(($LATEST_HEIGHT-$INTERVAL))
TRUST_HASH=$(curl -s "$RPC_ADDR/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)
SEED="4529fc24a87ff5ab105970f425ced7a6c79f0b8f@odin-seed-01.mercury-nodes.net:29536,c8ee9f66163f0c1220c586eab1a2a57f6381357f@odin.seed.rhinostake.com:16658"

## Displaying Height and hash
echo "TRUST HEIGHT: $BLOCK_HEIGHT"
echo "TRUST HASH: $TRUST_HASH"

## editing config.toml with correct values
sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ; \
s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$SNAP_RPC\"| ; \
s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT| ; \
s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"| ; \
s|^(seeds[[:space:]]+=[[:space:]]+).*$|\1\"$SEED\"|" $HOME/.odin/config/config.toml
export ODIN_STATESYNC_ENABLE=true
export ODIN_STATESYNC_RPC_SERVERS="$SNAP_RPC"
export ODIN_STATESYNC_TRUST_HEIGHT=$BLOCK_HEIGHT
export ODIN_STATESYNC_TRUST_HASH=$TRUST_HASH

sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "0.0001loki"/' .odin/config/app.toml
sed -i 's/pruning = "default"/pruning = "custom"/' .odin/config/app.toml 
sed -i 's/pruning-keep-recent = "0"/pruning-keep-recent = "362880"/' .odin/config/app.toml
sed -i 's/pruning-interval = "0"/pruning-interval = "100"/' .odin/config/app.toml

curl https://raw.githubusercontent.com/ODIN-PROTOCOL/networks/master/mainnets/odin-mainnet-freya/genesis.json > ~/.odin/config/genesis.json

echo "[Unit]
Description=Odin Cosmovisor Daemon
After=network-online.target
[Service]
User=fenrir
ExecStart=/home/fenrir/go/bin/cosmovisor run start
Restart=on-failure
RestartSec=3
LimitNOFILE=infinity
Environment="DAEMON_HOME=/home/fenrir/.odin"
Environment="DAEMON_NAME=odind"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
[Install]
WantedBy=multi-user.target" > odind.service
sudo cp odind.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable odind
odind tendermint unsafe-reset-all
sudo systemctl start odind
echo "Odin Daemon has been built, configured, and started.  Please check the log file with 'journalctl -fu odind' to verify node operational."

# set Storage=persistent in /etc/systemd/journald.conf if logs are not shown. Restart to see if live: sudo systemctl restart systemd-journald
