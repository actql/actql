// Protocol-authored authenticated HTTPS peer; it proves delivery/receipt
// plumbing, not a Cloud Run commit or physical Native Checkpoint persistence.
import {createServer} from 'node:https';
import {createHash} from 'node:crypto';
import {once} from 'node:events';
const hash = wire => 'sha256:' + createHash('sha256').update(wire).digest('hex');
const canonical = value => value && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
  : JSON.stringify(value);
export async function startNativeEffectCheckpointServer({host, key, cert, ca}) {
  const counts = {accepted: 0, bare: 0, foreign: 0, lost: 0};
  let original;
  const server = createServer({key, cert, ca, requestCert: true, rejectUnauthorized: true}, async (request, response) => {
    try {
      if (!request.socket.authorized) { response.writeHead(403).end(); return; }
      const chunks = []; let bytes = 0;
      for await (const chunk of request) {
        bytes += chunk.length;
        if (bytes > 262144) { response.writeHead(413).end(); return; }
        chunks.push(chunk);
      }
      if (request.url === '/counts') {
        response.writeHead(200, {'content-type': 'application/json'}).end(canonical(counts)); return;
      }
      const route = request.url?.slice(1);
      if (!Object.hasOwn(counts, route)) { response.writeHead(404).end(); return; }
      counts[route]++;
      const wire = Buffer.concat(chunks).toString('utf8');
      original ??= wire;
      if (wire !== original) { response.writeHead(409).end(); return; }
      if (route === 'lost') { response.destroy(); return; }
      if (route === 'bare') { response.writeHead(200, {'content-type': 'application/json'}).end('{}'); return; }
      const report = JSON.parse(wire);
      const checkpoint = JSON.parse(report.checkpoint_wire);
      const reply = {checkpoint_cid: checkpoint.checkpoint_cid,
        dispatch_request_cid: report.dispatch_request_cid, outcome: 'accepted', reason: '',
        report_cid: route === 'foreign' ? hash('other-report') : hash(wire),
        version: 'actql-remote-effect-checkpoint-reply/0.1'};
      response.writeHead(200, {'content-type': 'application/json'}).end(canonical(reply));
    } catch {
      response.writeHead(500).end();
    }
  });
  server.listen(0, host); await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Checkpoint fixture listener unavailable');
  return {origin: `https://${host}:${address.port}`, counts: () => ({...counts}),
    close: async () => {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}};
}
