// Test-only transport assembly. Execution and durable cleanup stay with the
// installed Host; this holder never creates a Source, grant or execution owner.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

export async function connectRealRouteTransport(held, {connect, openInstalledRemoteHttpHost,
  createServer, options, transport, https, principalId, resolveSourceSecret}) {
  assert(['local', 'https'].includes(transport));
  assert(!held.client && !held.server && !held.host, 'Close the original connection before reopening');
  assert(held.initializationFailure?.cleanupPending !== true, 'Original initialization retains cleanup');
  held.transport = transport;
  held.clientOpened = false; held.clientClosed = false;
  held.serverCreated = false; held.serverClosed = false; held.hostClose = undefined;
  const installation = {...options.installation, resolveSourceSecret};
  if (transport === 'local') {
    try { held.client = await connect({...options, installation}); }
    catch (error) { held.initializationFailure = error; throw error; }
  } else {
    assert(https && typeof https.token === 'string' && https.token.length >= 32);
    assert.equal(typeof principalId, 'string');
    try {
      held.host = await openInstalledRemoteHttpHost({...installation,
        authenticate: header => header === `Bearer ${https.token}` ? principalId : undefined});
    } catch (error) { held.initializationFailure = error; throw error; }
    held.server = createServer({key: await readFile(https.keyPath), cert: await readFile(https.certPath)},
      held.host.handler);
    held.serverCreated = true;
    await new Promise((resolve, reject) => {
      const failed = error => reject(error);
      held.server.once('error', failed);
      held.server.listen(0, '127.0.0.1', () => {
        held.server.removeListener('error', failed);
        resolve();
      });
    });
    const address = held.server.address();
    assert(address && address.address === '127.0.0.1' && Number.isInteger(address.port) && address.port > 0);
    held.client = await connect({mode: 'remote', durability: options.durability,
      endpoint: `https://127.0.0.1:${address.port}/`, token: https.token});
  }
  held.clientOpened = true;
  return held.client;
}

export async function closeRealRouteTransport(held) {
  let failure = held.initializationFailure?.cleanupPending === true
    ? held.initializationFailure : undefined;
  if (held.client) {
    try { await held.client.close(); held.client = undefined; held.clientClosed = true; }
    catch (error) { failure ??= error; }
  }
  if (held.server) {
    try {
      held.server.closeAllConnections();
      await new Promise((resolve, reject) => held.server.close(error => error ? reject(error) : resolve()));
      held.server = undefined;
      held.serverClosed = true;
    } catch (error) { failure ??= error; }
  }
  if (held.host) {
    try {
      held.hostClose = await held.host.close();
      assert(held.hostClose && held.hostClose.storeCleanupPending === false &&
        held.hostClose.authorizationCleanupPending === false &&
        held.hostClose.diagnosticDeliveryPending === false &&
        Array.isArray(held.hostClose.pendingRetention) && held.hostClose.pendingRetention.length === 0,
      'Installed HTTPS Host retains cleanup responsibility');
      held.host = undefined;
    } catch (error) { failure ??= error; }
  }
  if (failure) throw failure;
  return {transport: held.transport,
    clientCloseResolved: held.clientOpened === true ? held.clientClosed === true : null,
    ...(held.transport === 'https' ? {serverClosed: held.serverCreated ? held.serverClosed : null,
      hostClose: held.hostClose} : {})};
}
