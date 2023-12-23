#!/bin/bash

set -e
set -o pipefail

export MIX_ENV=test

echo "######### Fetch Deps"
mix deps.get --all
mix format
MIX_ENV=test mix compile --force

echo "######### Run Tests"
mix coveralls.html
rm -f *.coverdata

echo "######### Build RPI4 FW"

MIX_TARGET=rpi4 MIX_ENV=prod mix deps.get
MIX_TARGET=rpi4 MIX_ENV=prod mix compile --force
MIX_TARGET=rpi4 MIX_ENV=prod mix firmware

echo "######### Build RPI3 FW"

MIX_TARGET=rpi3 MIX_ENV=prod mix deps.get
MIX_TARGET=rpi3 MIX_ENV=prod mix compile --force
MIX_TARGET=rpi3 MIX_ENV=prod mix firmware

echo "######### Build RPI0 FW"
MIX_TARGET=rpi MIX_ENV=prod mix deps.get
MIX_TARGET=rpi MIX_ENV=prod mix compile --force
MIX_TARGET=rpi MIX_ENV=prod mix firmware

echo "######## Build IMG"
fwup -S -s /opt/farmlab_os/priv/prod.pub -i /opt/farmlab_os/_build/rpi4/rpi4_prod/nerves/images/farmbot.fw -o /opt/farmlab_os/_build/rpi4/rpi4_prod/nerves/images/farmlab-rpi4-$(cat VERSION).fw
fwup -a -t complete -i /opt/farmlab_os/_build/rpi4/rpi4_prod/nerves/images/farmlab-rpi4-$(cat VERSION).fw -d /opt/farmlab_os/farmlab-rpi4-$(cat VERSION).img
sha256sum /opt/farmlab_os/farmlab-rpi4-$(cat VERSION).img > /opt/farmlab_os/farmlab-rpi4-$(cat VERSION).sha256
