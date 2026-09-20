import {once} from 'node:events';
import {createServer, request as httpsRequest} from 'node:https';

const fail = (code, cause, details = {}) => {
  throw Object.assign(new Error(code, {cause}), {code, ...details});
};
const text = value => typeof value === 'string' && value.length > 0;
const integer = value => Number.isSafeInteger(value) && value >= 0;

function reply(response, status, body) {
  const bytes = Buffer.from(JSON.stringify(body), 'utf8');
  response.writeHead(status, {
    'content-type': 'application/json',
    'content-length': String(bytes.byteLength),
    'cache-control': 'no-store',
  });
  response.end(bytes);
}

function replyCanonical(response, status, body) {
  const bytes = Buffer.from(body, 'utf8');
  response.writeHead(status, {
    'content-type': 'application/json',
    'content-length': String(bytes.byteLength),
    'cache-control': 'no-store',
  });
  response.end(bytes);
}

async function readControlBody(request, maxBytes) {
  const announced = request.headers['content-length'];
  if (announced !== undefined &&
      (!/^(0|[1-9][0-9]*)$/.test(announced) ||
      Number(announced) > maxBytes)) {
    fail('RemoteTransferControlBodyTooLarge');
  }
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.byteLength;
    if (length > maxBytes) fail('RemoteTransferControlBodyTooLarge');
    chunks.push(chunk);
  }
  return new TextDecoder('utf-8', {fatal: true}).decode(
    Buffer.concat(chunks, length),
  );
}

function currentTime(clock) {
  const value = clock();
  if (typeof value === 'bigint' && value >= 0n) return value;
  if (integer(value)) return BigInt(value);
  fail('InvalidRemoteTransferClock');
}

async function cleanupPhysical(entry) {
  if (entry.cleanupInFlight !== undefined) return await entry.cleanupInFlight;
  const attempt = (async () => {
    const errors = [];
    for (let index = entry.writers.length - 1; index >= 0; index--) {
      const body = entry.bodies[index];
      const writer = entry.writers[index];
      try { body?.close(); }
      catch (error) { errors.push(error); }
      if (body === undefined) {
        try { writer.cancel(); }
        catch (error) { errors.push(error); }
      }
      try { await writer.cleanupHandle.retry(); }
      catch (error) { errors.push(error); }
    }
    const pending = entry.writers.some(
      writer => writer.cleanupHandle.status().pending,
    );
    if (errors.length) {
      throw new AggregateError(errors, 'Remote Transfer cleanup failed');
    }
    return !pending;
  })();
  entry.cleanupInFlight = attempt;
  try { return await attempt; }
  finally {
    if (entry.cleanupInFlight === attempt) entry.cleanupInFlight = undefined;
  }
}

async function authorizeUse(
  entry,
  authorize,
  control,
  clock,
  phase,
  peer,
  requireActive = true,
) {
  if (requireActive && !control.activeAt(entry.request, currentTime(clock))) {
    fail('RemoteTransferExpired');
  }
  if (await authorize(Object.freeze({
    request: entry.request,
    phase,
    peer,
  })) !== true) {
    fail('RemoteTransferUnauthorized');
  }
  if (requireActive && !control.activeAt(entry.request, currentTime(clock))) {
    fail('RemoteTransferExpired');
  }
}

export async function startHttpsDirectTransferReceiver({
  host = '127.0.0.1',
  port = 0,
  key,
  cert,
  ca,
  sourceAuthorities,
  destinationSiteKey,
  destinationSiteGeneration,
  control,
  journal,
  store,
  authorize,
  clock = () => Date.now(),
  maxControlBytes = 131_072,
  maxManifestBytes = 65_536,
  maxChunks = 4096,
  maxReferencedBytes = 9_007_199_254_740_991n,
  maxFrameBytes = 1024 * 1024,
} = {}) {
  if (!text(host) || !integer(port) || key === undefined ||
      cert === undefined || ca === undefined ||
      !(sourceAuthorities instanceof Map) ||
      !text(destinationSiteKey) || !integer(destinationSiteGeneration) ||
      control === null || typeof control !== 'object' ||
      typeof control.admitJson !== 'function' ||
      typeof control.admitAdmissionEnvelopeJson !== 'function' ||
      typeof control.identity !== 'function' ||
      typeof control.requestProjection !== 'function' ||
      typeof control.chunks !== 'function' ||
      typeof control.activeAt !== 'function' ||
      typeof control.prepareStart !== 'function' ||
      typeof control.prepareSourceSettled !== 'function' ||
      typeof control.prepareDestinationCommit !== 'function' ||
      typeof control.prepareFailure !== 'function' ||
      typeof control.prepareCleanup !== 'function' ||
      typeof control.recordProjection !== 'function' ||
      typeof control.recordIsDestinationCommitted !== 'function' ||
      typeof control.directCleanupConfirmed !== 'function' ||
      typeof control.replyJson !== 'function' ||
      journal === null || typeof journal !== 'object' ||
      typeof journal.accept !== 'function' ||
      typeof journal.advance !== 'function' ||
      store === null || typeof store !== 'object' ||
      typeof store.reserve !== 'function' || typeof authorize !== 'function' ||
      typeof clock !== 'function' || !integer(maxControlBytes) ||
      maxControlBytes === 0 || !integer(maxManifestBytes) ||
      maxManifestBytes === 0 || !integer(maxChunks) ||
      typeof maxReferencedBytes !== 'bigint' || maxReferencedBytes < 0n ||
      !integer(maxFrameBytes) || maxFrameBytes === 0) {
    fail('InvalidDirectTransferReceiverConfiguration');
  }
  const base = `/v1/sites/${encodeURIComponent(destinationSiteKey)}/` +
    `generations/${destinationSiteGeneration}/transfers`;
  const entries = new Map();
  let admissionClosed = false;
  let listenerClosed = false;
  let fullyClosed = false;
  let closeInFlight;

  const stateReply = entry => control.replyJson(entry.record);
  const peerFor = request => {
    const certificate = request.socket.getPeerCertificate();
    const sourceSite = sourceAuthorities.get(certificate.fingerprint256);
    if (!request.socket.authorized || !text(sourceSite)) {
      fail('RemoteTransferUnauthorized');
    }
    return Object.freeze({sourceSite});
  };
  const entryFor = (requestCid, peer) => {
    const entry = entries.get(requestCid);
    if (entry === undefined || entry.sourceSite !== peer.sourceSite) {
      fail('RemoteTransferUnavailable');
    }
    return entry;
  };
  const persistFailure = async (
    entry,
    {cancelled = false, sourceStopped = false} = {},
  ) => {
    const state = control.recordProjection(entry.record);
    if (state[1] !== 2 && state[4] !== 1) {
      entry.record = journal.advance(
        control.prepareFailure(entry.record, cancelled, sourceStopped),
        control,
      );
    }
    let reclaimed = false;
    try { reclaimed = await cleanupPhysical(entry); }
    catch (error) {
      entry.cleanupError = error;
      return false;
    }
    if (reclaimed) {
      const next = control.recordProjection(entry.record);
      if (next[4] !== 1) {
        entry.record = journal.advance(
          control.prepareCleanup(
            entry.record,
            sourceStopped,
            true,
            true,
          ),
          control,
        );
      }
      entries.delete(control.identity(entry.request));
    }
    return reclaimed;
  };

  const server = createServer({
    key,
    cert,
    ca,
    requestCert: true,
    rejectUnauthorized: true,
    minVersion: 'TLSv1.3',
  }, async (request, response) => {
    try {
      const peer = peerFor(request);
      if (request.method === 'POST' && request.url === base) {
        if (admissionClosed || request.headers['content-type'] !==
            'application/json') {
          fail('RemoteTransferUnavailable');
        }
        const claimedRequestCid = request.headers['actql-transfer-cid'];
        const claimedManifestCid = request.headers['actql-manifest-cid'];
        if (!text(claimedRequestCid) || !text(claimedManifestCid)) {
          fail('InvalidRemoteTransferEnvelope');
        }
        const admitted = control.admitAdmissionEnvelopeJson(
          await readControlBody(request, maxControlBytes),
          claimedRequestCid,
          claimedManifestCid,
          {maxChunks, maxManifestBytes, maxReferencedBytes},
        );
        const projection = control.requestProjection(admitted);
        if (projection[1] !== 'direct' || projection[2] !== peer.sourceSite ||
            projection[4] !== destinationSiteKey ||
            Number(projection[5]) !== destinationSiteGeneration) {
          fail('RemoteTransferUnauthorized');
        }
        const transient = {request: admitted};
        await authorizeUse(transient, authorize, control, clock, 'admit', peer);
        const existing = entries.get(claimedRequestCid);
        if (existing !== undefined) {
          replyCanonical(response, 200, stateReply(existing));
          return;
        }
        const accepted = journal.accept(admitted, control);
        if (!accepted.created) {
          if (control.directCleanupConfirmed(accepted.record)) {
            replyCanonical(response, 200, control.replyJson(accepted.record));
            return;
          }
          fail('RemoteTransferReconciliationRequired');
        }
        const entry = {
          request: accepted.request,
          record: accepted.record,
          sourceSite: peer.sourceSite,
          chunks: control.chunks(accepted.request),
          writers: [],
          bodies: [],
          nextChunk: 0,
          operationInFlight: false,
          cleanupInFlight: undefined,
          cleanupError: undefined,
        };
        entries.set(claimedRequestCid, entry);
        try {
          for (const chunk of entry.chunks) {
            const writer = store.reserve(Number(chunk.byteLength));
            entry.writers.push(writer);
            await writer.start();
          }
          entry.record = journal.advance(
            control.prepareStart(entry.record),
            control,
          );
        } catch (error) {
          try { await persistFailure(entry, {sourceStopped: true}); }
          catch (cleanupError) { entry.cleanupError = cleanupError; }
          throw error;
        }
        replyCanonical(response, 201, stateReply(entry));
        return;
      }

      const prefix = `${base}/`;
      if (!request.url?.startsWith(prefix)) {
        fail('RemoteTransferUnavailable');
      }
      const suffix = request.url.slice(prefix.length);
      const parts = suffix.split('/');
      const requestCid = decodeURIComponent(parts[0] ?? '');
      const entry = entryFor(requestCid, peer);
      if (request.method === 'PUT' && parts.length === 3 &&
          parts[1] === 'chunks') {
        const index = Number(parts[2]);
        if (!integer(index) || index >= entry.chunks.length ||
            request.headers['content-type'] !== 'application/octet-stream') {
          fail('InvalidRemoteTransferChunk');
        }
        await authorizeUse(entry, authorize, control, clock, 'write', peer);
        if (entry.bodies[index] !== undefined) {
          replyCanonical(response, 200, stateReply(entry));
          return;
        }
        if (entry.operationInFlight) fail('RemoteTransferBusy');
        if (index !== entry.nextChunk) fail('RemoteTransferChunkOrder');
        const expected = entry.chunks[index];
        const announced = request.headers['content-length'];
        if (!text(announced) || !/^(0|[1-9][0-9]*)$/.test(announced) ||
            BigInt(announced) !== expected.byteLength) {
          fail('RemoteTransferChunkLengthMismatch');
        }
        const writer = entry.writers[index];
        let received = 0n;
        entry.operationInFlight = true;
        try {
          for await (const frame of request) {
            received += BigInt(frame.byteLength);
            if (received > expected.byteLength) {
              fail('RemoteTransferChunkLengthMismatch');
            }
            for (let offset = 0; offset < frame.byteLength;
              offset += maxFrameBytes) {
              await writer.appendBytes(
                frame.subarray(offset, offset + maxFrameBytes),
              );
            }
          }
          if (received !== expected.byteLength) {
            fail('RemoteTransferChunkLengthMismatch');
          }
          const body = await writer.sealPhysical();
          if (body.cid !== expected.cid || BigInt(body.bytes) !==
              expected.byteLength) {
            body.close();
            fail('RemoteTransferChunkIntegrityMismatch');
          }
          entry.bodies[index] = body;
          entry.nextChunk++;
        } catch (error) {
          try { await persistFailure(entry); }
          catch (cleanupError) { entry.cleanupError = cleanupError; }
          throw error;
        } finally {
          entry.operationInFlight = false;
        }
        replyCanonical(response, 200, stateReply(entry));
        return;
      }
      if (request.method === 'POST' && parts.length === 2 &&
          parts[1] === 'commit') {
        await readControlBody(request, 0);
        await authorizeUse(entry, authorize, control, clock, 'commit', peer);
        if (entry.operationInFlight) fail('RemoteTransferBusy');
        if (entry.nextChunk !== entry.chunks.length ||
            entry.bodies.length !== entry.chunks.length) {
          fail('RemoteTransferIncomplete');
        }
        const state = control.recordProjection(entry.record);
        if (state[1] !== 2) {
          entry.record = journal.advance(
            control.prepareSourceSettled(entry.record, true, false),
            control,
          );
          entry.record = journal.advance(
            control.prepareDestinationCommit(entry.record),
            control,
          );
        }
        replyCanonical(response, 200, stateReply(entry));
        return;
      }
      if (request.method === 'POST' && parts.length === 2 &&
          parts[1] === 'cancel') {
        await readControlBody(request, 0);
        await authorizeUse(
          entry,
          authorize,
          control,
          clock,
          'cancel',
          peer,
          false,
        );
        await persistFailure(entry, {cancelled: true, sourceStopped: true});
        replyCanonical(response, 200, stateReply(entry));
        return;
      }
      fail('RemoteTransferUnavailable');
    } catch (error) {
      if (!response.headersSent) {
        const hidden = error?.code === 'RemoteTransferUnauthorized' ||
          error?.code === 'RemoteTransferUnavailable';
        reply(response, hidden ? 404 : 409, {
          error: hidden ? 'not_found' : 'transfer_rejected',
        });
      } else {
        response.destroy(error);
      }
    }
  });
  server.on('clientError', (_error, socket) => socket.destroy());
  server.once('close', () => { listenerClosed = true; });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.off('error', reject);
      resolve();
    });
  });
  const address = server.address();
  if (address === null || typeof address === 'string') {
    server.close();
    fail('DirectTransferReceiverAddressUnavailable');
  }

  return Object.freeze({
    origin: `https://${host}:${address.port}`,
    port: address.port,
    claim(requestCid) {
      const entry = entries.get(requestCid);
      if (entry === undefined || control.recordProjection(entry.record)[1] !== 2) {
        fail('RemoteTransferUnavailable');
      }
      return Object.freeze({
        request: entry.request,
        bodies: Object.freeze([...entry.bodies]),
      });
    },
    async release(requestCid) {
      const entry = entries.get(requestCid);
      if (entry === undefined || control.recordProjection(entry.record)[1] !== 2) {
        fail('RemoteTransferUnavailable');
      }
      if (!await cleanupPhysical(entry)) return false;
      entry.record = journal.advance(
        control.prepareCleanup(entry.record, true, true, true),
        control,
      );
      entries.delete(requestCid);
      return true;
    },
    async retryCleanup(requestCid, {sourceStopped = false} = {}) {
      const entry = entries.get(requestCid);
      if (entry === undefined) return false;
      return await persistFailure(entry, {sourceStopped});
    },
    async close() {
      admissionClosed = true;
      if (fullyClosed) return false;
      if (closeInFlight !== undefined) return await closeInFlight;
      const attempt = (async () => {
        if (!listenerClosed) {
          await new Promise((resolve, reject) => server.close(error => {
            if (error) reject(error);
            else resolve();
          }));
          listenerClosed = true;
        }
        if (entries.size !== 0) fail('RemoteTransferCleanupPending');
        fullyClosed = true;
        return true;
      })();
      closeInFlight = attempt;
      try { return await attempt; }
      finally {
        if (closeInFlight === attempt) closeInFlight = undefined;
      }
    },
  });
}

async function responseBody(response, maxBytes) {
  const chunks = [];
  let length = 0;
  for await (const chunk of response) {
    length += chunk.byteLength;
    if (length > maxBytes) fail('RemoteTransferResponseTooLarge');
    chunks.push(chunk);
  }
  const body = Buffer.concat(chunks, length).toString('utf8');
  if (response.statusCode !== 200 && response.statusCode !== 201) {
    let value;
    try { value = JSON.parse(body); } catch {}
    fail('RemoteTransferRejected', undefined, {
      remoteError: value?.error,
      statusCode: response.statusCode,
    });
  }
  return body;
}

async function sendRequest({
  origin,
  path,
  method,
  ca,
  cert,
  key,
  servername,
  headers,
  signal,
  write,
  maxResponseBytes,
}) {
  return await new Promise((resolve, reject) => {
    let writing = Promise.resolve();
    const request = httpsRequest(new URL(path, origin), {
      method,
      ca,
      cert,
      key,
      servername,
      minVersion: 'TLSv1.3',
      signal,
      headers,
    }, response => {
      responseBody(response, maxResponseBytes).then(
        value => writing.then(() => resolve(value), reject),
        error => writing.then(() => reject(error), () => reject(error)),
      );
    });
    request.once('error', error => {
      writing.then(
        () => reject(error),
        () => reject(error),
      );
    });
    writing = Promise.resolve().then(() => write(request));
    writing.catch(error => {
      request.destroy(error);
    });
  });
}

export async function sendHttpsDirectTransfer({
  origin,
  ca,
  cert,
  key,
  servername = 'localhost',
  control,
  request,
  sourceBodies,
  signal,
  maxResponseBytes = 16_384,
} = {}) {
  if (!text(origin) || ca === undefined || cert === undefined ||
      key === undefined || !text(servername) ||
      control === null || typeof control !== 'object' ||
      typeof control.requestJson !== 'function' ||
      typeof control.manifestJson !== 'function' ||
      typeof control.admissionEnvelopeJson !== 'function' ||
      typeof control.admitReplyJson !== 'function' ||
      typeof control.identity !== 'function' ||
      typeof control.requestProjection !== 'function' ||
      typeof control.chunks !== 'function' ||
      typeof control.recordIsDestinationCommitted !== 'function' ||
      typeof control.directCleanupConfirmed !== 'function' ||
      request === undefined ||
      !Array.isArray(sourceBodies) || !integer(maxResponseBytes) ||
      maxResponseBytes === 0) {
    fail('InvalidDirectTransferSenderConfiguration');
  }
  const projection = control.requestProjection(request);
  if (projection[1] !== 'direct') fail('InvalidDirectTransferRoute');
  const chunks = control.chunks(request);
  if (chunks.length !== sourceBodies.length) {
    fail('RemoteTransferSourceMismatch');
  }
  for (let index = 0; index < chunks.length; index++) {
    const body = sourceBodies[index];
    if (body === null || typeof body !== 'object' ||
        typeof body.consume !== 'function' || body.cid !== chunks[index].cid ||
        BigInt(body.bytes) !== chunks[index].byteLength) {
      fail('RemoteTransferSourceMismatch');
    }
  }
  const requestCid = control.identity(request);
  const base = `/v1/sites/${encodeURIComponent(projection[4])}/` +
    `generations/${projection[5]}/transfers`;
  const envelope = Buffer.from(control.admissionEnvelopeJson(request), 'utf8');
  const common = {
    origin,
    ca,
    cert,
    key,
    servername,
    signal,
    maxResponseBytes,
  };
  const admittedBody = await sendRequest({
    ...common,
    path: base,
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'content-length': String(envelope.byteLength),
      'actql-transfer-cid': requestCid,
      'actql-manifest-cid': projection[7],
    },
    write(outgoing) { outgoing.end(envelope); },
  });
  const admitted = control.admitReplyJson(admittedBody, request);
  if (control.recordIsDestinationCommitted(admitted)) {
    return Object.freeze({
      requestCid,
      state: Object.freeze([...control.recordProjection(admitted)]),
    });
  }
  if (control.directCleanupConfirmed(admitted)) {
    fail('RemoteTransferTerminalFailure');
  }
  let sourceStopped = true;
  try {
    for (let index = 0; index < chunks.length; index++) {
      sourceStopped = false;
      const chunkReply = await sendRequest({
        ...common,
        path: `${base}/${encodeURIComponent(requestCid)}/chunks/${index}`,
        method: 'PUT',
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': chunks[index].byteLength.toString(),
        },
        async write(outgoing) {
          try {
            await sourceBodies[index].consume(async frame => {
              const owned = Buffer.from(frame);
              if (!outgoing.write(owned)) await once(outgoing, 'drain');
            }, signal);
            outgoing.end();
          } finally {
            sourceStopped = true;
          }
        },
      });
      control.admitReplyJson(chunkReply, request);
    }
    const committedBody = await sendRequest({
      ...common,
      path: `${base}/${encodeURIComponent(requestCid)}/commit`,
      method: 'POST',
      headers: {'content-length': '0'},
      write(outgoing) { outgoing.end(); },
    });
    const committed = control.admitReplyJson(committedBody, request);
    return Object.freeze({
      requestCid,
      state: Object.freeze([...control.recordProjection(committed)]),
    });
  } catch (error) {
    if (sourceStopped) {
      try {
        await sendRequest({
          ...common,
          signal: undefined,
          path: `${base}/${encodeURIComponent(requestCid)}/cancel`,
          method: 'POST',
          headers: {'content-length': '0'},
          write(outgoing) { outgoing.end(); },
        });
      } catch {}
    }
    throw error;
  }
}
