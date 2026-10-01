// Test transport only. Forward the actual Site request to the real gateway;
// lose its HTTPS ACK only after the gateway's durable receiver returned 200.
// Holding a poll reply controls arrival order, not execution authorization.
import {createServer, request} from 'node:https';

export async function observationAckLossProxy({origin, key, cert, ca,
  loseAck, allowDispatch, onAckLost}) {
  const server = createServer({key, cert, minVersion: 'TLSv1.3'}, async (incoming, outgoing) => {
    try {
      const chunks = [];
      for await (const chunk of incoming) chunks.push(chunk);
      const body = Buffer.concat(chunks);
      const observation = incoming.url.endsWith('/observations');
      const drop = observation && loseAck(body.toString('utf8'));
      const upstream = await new Promise((resolve, reject) => {
        const forwarded = request(new URL(incoming.url, origin), {
          method: incoming.method, ca, headers: incoming.headers,
        }, async response => {
          try {
            const parts = [];
            for await (const part of response) parts.push(part);
            resolve({status: response.statusCode, body: Buffer.concat(parts)});
          } catch (error) { reject(error); }
        });
        forwarded.on('error', reject);
        forwarded.end(body);
      });
      if (drop && upstream.status === 200) {
        onAckLost(body.toString('utf8'));
        outgoing.destroy();
        return;
      }
      if (!observation && upstream.status === 200) {
        const envelope = JSON.parse(upstream.body.toString('utf8'));
        if (envelope.version.startsWith('actql-remote-poll-dispatch') &&
            !allowDispatch(envelope)) {
          outgoing.writeHead(204);
          outgoing.end();
          return;
        }
      }
      outgoing.writeHead(upstream.status, {'content-type': 'application/json'});
      outgoing.end(upstream.body);
    } catch (error) { outgoing.destroy(error); }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return {origin: `https://127.0.0.1:${server.address().port}`,
    close: async () => {
      server.closeAllConnections();
      await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    }};
}
