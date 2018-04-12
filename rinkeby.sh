#!/bin/sh

echo plort > supersecret.txt
if [ ! -f myaddress ]
then
  geth --rinkeby account new --password supersecret.txt
  touch myaddress
fi

service apache2 restart

geth --rinkeby --unlock 0 --password=supersecret.txt --ws --wsaddr 0.0.0.0 -wsapi eth --wsorigins="*" &
ipfs daemon &

sleep 10

cd webasm-solidity/node
node setup.js rinkeby.json > config.json
node app.js

