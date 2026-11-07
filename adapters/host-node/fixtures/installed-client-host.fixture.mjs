import {createServer} from 'node:https';
import {types} from 'node:util';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {realpath} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';

// Retained package fixtures may select Common through a build alias. Its FFI
// imports retain instance-local operational originals, so the Host must come
// from that SAME physical package. Equal checkout modules are not substitutes.
const commonPath = await realpath(new URL('../../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url));
const hostUrl = new URL('../../../../../adapters/host-node/embedded-local.mjs',
  pathToFileURL(commonPath));
const {connectEmbeddedLocal, openInstalledRemoteHttpHost} = await import(hostUrl.href);
// Explanation custody belongs to this same physical SDK namespace.
export const installedClientSdk = createRequire(hostUrl)('@actql/sdk');
const {connect} = installedClientSdk;

// Both entrances retain the production Host's own preparation and children.
// Callers supply their authored installation and TLS DATA, never an admission,
// replacement service, preparation callback or operational parent.
export async function openInstalledClientHostFixture(t, {entrance, installation,
  authenticate, certificates, serve}) {
  let client, host, server, closing;
  const trust = getCACertificates('default');
  const close = () => closing ??= (async () => {
    try {
      await client?.close();
      if (server) {
        server.closeAllConnections();
        await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      }
      return await host?.close();
    } finally {setDefaultCACertificates(trust);}
  })();
  t.after(close);
  try {
    if (entrance === 'in-process') {
      client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
        durability: 'durable', installation}, 'connect');
    } else if (entrance === 'HTTP') {
      host = await openInstalledRemoteHttpHost({...installation, authenticate});
      setDefaultCACertificates([...trust, certificates.ca.toString('utf8')]);
      server = createServer({key: certificates.key, cert: certificates.cert},
        (request, response) => serve === undefined ? host.handler(request, response)
          : serve(request, response, host.handler));
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', resolve);
      });
      client = await connect({mode: 'remote', token: 'fixture-token', durability: 'durable',
        endpoint: `https://127.0.0.1:${server.address().port}/`});
    } else {
      throw new TypeError('InvalidInstalledClientFixtureEntrance');
    }
    return {client, close};
  } catch (cause) {
    // Error DATA only: no getters, custom inspectors or cleanup callbacks.
    const describe = (error, depth = 0) => {
      if (depth === 4 || error === null || typeof error !== 'object' || types.isProxy(error)) return undefined;
      const result = {};
      for (const name of ['name', 'message', 'code', 'cause', 'primaryFailure']) {
        const field = Object.getOwnPropertyDescriptor(error, name);
        if (field === undefined || !Object.hasOwn(field, 'value')) continue;
        if (typeof field.value === 'string') result[name] = field.value.slice(0, 1024);
        else if (name === 'cause' || name === 'primaryFailure') result[name] = describe(field.value, depth + 1);
      }
      return result;
    };
    t.diagnostic('Installed Host fixture original initialization failure: ' + JSON.stringify(describe(cause)));
    throw cause;
  }
}
