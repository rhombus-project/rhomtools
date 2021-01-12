#!/bin/bash

PARTYMAN_PATH=~/rhomtools
PARTICL_PATH=~/rhombuscore
HTML_PATH=$PARTYMAN_PATH/webserver/public_html

"$PARTYMAN_PATH"/rhomtools status > "$HTML_PATH"/rhomtools-status.tmp
"$PARTYMAN_PATH"/rhomtools stakingnode stats >> "$HTML_PATH"/rhomtools-status.tmp
"$PARTICL_PATH"/rhombus-cli getwalletinfo | grep watchonly >> "$HTML_PATH"/rhomtools-status.tmp
