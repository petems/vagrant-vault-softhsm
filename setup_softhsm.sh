#!/usr/bin/env bash

sudo apt-get update
sudo apt-get install -y libltdl7 libsofthsm2 softhsm2 opensc unzip unzip libcap2-bin
sudo mkdir -p /var/lib/softhsm/tokens/
sudo tee /etc/softhsm/softhsm2.conf <<EOF
# SoftHSM v2 configuration file
directories.tokendir = /var/lib/softhsm/tokens/
objectstore.backend = file
# ERROR, WARNING, INFO, DEBUG
log.level = DEBUG
EOF

sudo softhsm2-util --init-token --slot 0 --label "hsm_demo" --pin 1234 --so-pin asdf
