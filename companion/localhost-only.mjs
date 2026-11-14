// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Makes NihonSub listen on this Mac only. NihonSub has no password, so it shouldn't be open
// to the whole Wi-Fi. Only the bridge (which needs a token) is reachable from other devices.
//
// Used as:  node --import ./localhost-only.mjs server.js

import net from 'node:net';

const listen = net.Server.prototype.listen;
net.Server.prototype.listen = function (port, ...rest) {
  const isPort = typeof port === 'number' || (typeof port === 'string' && /^\d+$/.test(port));
  if (isPort && (rest.length === 0 || typeof rest[0] === 'function')) rest.unshift('127.0.0.1');
  return listen.call(this, port, ...rest);
};
