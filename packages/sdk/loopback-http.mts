// Opted-in Node loopback transport only. A dedicated standard Agent avoids
// environment proxies and replaced global Fetch dispatchers. No global setting
// is read or changed, no redirect/retry is followed, and no listener is opened.
import {Agent, request} from 'node:http';
import {Readable} from 'node:stream';
import {isLoopbackEndpointHostname} from './connection-string.mjs';

export function requestLoopbackClient(url, {method, headers, body, signal, redirect}) {
  if (!(url instanceof URL) || url.protocol !== 'http:' ||
      !isLoopbackEndpointHostname(url.hostname) || url.username || url.password ||
      url.search || url.hash || !url.pathname.startsWith('/actql/client/0.1/') ||
      method !== 'POST' || redirect !== 'error' || typeof body !== 'string') {
    return Promise.reject(new TypeError('InvalidLoopbackClientRequest'));
  }
  const port = url.port === '' ? 80 : Number(url.port);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    return Promise.reject(new TypeError('InvalidLoopbackClientRequest'));
  }
  try { signal?.throwIfAborted(); }
  catch (error) { return Promise.reject(error); }
  const hostname = url.hostname.startsWith('[') ? url.hostname.slice(1, -1) : url.hostname;
  const agent = new Agent({keepAlive: false, maxSockets: 1, maxTotalSockets: 1,
    proxyEnv: undefined});
  return new Promise((resolve, reject) => {
    let outgoing;
    const fail = error => { agent.destroy(); reject(error); };
    try {
      outgoing = request({protocol: 'http:', hostname, port, path: url.pathname,
        method: 'POST', headers, signal, agent, maxHeaderSize: 16384}, incoming => {
        incoming.once('close', () => agent.destroy());
        const status = incoming.statusCode;
        if (status >= 300 && status < 400) {
          incoming.destroy();
          fail(new TypeError('LoopbackRedirectRefused'));
          return;
        }
        try {
          const responseHeaders = new Headers();
          for (const [name, value] of Object.entries(incoming.headers)) {
            if (Array.isArray(value)) for (const item of value) responseHeaders.append(name, item);
            else if (value !== undefined) responseHeaders.append(name, value);
          }
          const noBody = status === 204 || status === 205;
          const stream = noBody ? null : Readable.toWeb(incoming, {
            strategy: {highWaterMark: 1, size: chunk => chunk.byteLength},
          });
          // A null-body status cannot feed the SDK's control/read protocol.
          // Do not drain an unbounded malformed 205 body after returning it.
          if (noBody) { incoming.destroy(); agent.destroy(); }
          resolve(new Response(stream, {status, headers: responseHeaders}));
        } catch (error) { incoming.destroy(); fail(error); }
      });
      outgoing.once('error', fail);
      outgoing.once('upgrade', (_response, socket) => {
        socket.destroy(); fail(new TypeError('LoopbackUpgradeRefused'));
      });
      outgoing.end(body);
    } catch (error) { outgoing?.destroy(); fail(error); }
  });
}
