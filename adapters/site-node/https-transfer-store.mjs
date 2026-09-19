import {once} from 'node:events';
import {createServer, request as httpsRequest} from 'node:https';

const fail = (code, cause, details = {}) => {
  throw Object.assign(new Error(code, {cause}), {code, ...details});
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;

function reply(response, status, body) {
  const bytes = Buffer.from(JSON.stringify(body), 'utf8');
  response.writeHead(status, {
    'content-type': 'application/json',
    'content-length': String(bytes.byteLength),
    'cache-control': 'no-store',
  });
  response.end(bytes);
}

async function readBoundedBody(request, maxBytes) {
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
  return Buffer.concat(chunks, length);
}

function parseEnvelope(bytes) {
  let value;
  try {
    value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
  } catch (error) {
    fail('InvalidRemoteTransferEnvelope', error);
  }
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join(',') !== 'manifest,request' ||
      !text(value.manifest) || !text(value.request)) {
    fail('InvalidRemoteTransferEnvelope');
  }
  return value;
}

function now(clock) {
  const value = clock();
  if (typeof value === 'bigint' && value >= 0n) return value;
  if (count(value)) return BigInt(value);
  fail('InvalidRemoteTransferClock');
}

function physicalHolding(control, request) {
  const projection = control.requestProjection(request);
  const chunks = control.chunks(request);
  if (chunks.some(chunk => chunk.byteLength > BigInt(Number.MAX_SAFE_INTEGER))) {
    fail('RemoteTransferCapacityUnsupported');
  }
  return Object.freeze({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'remote-transfer',
    holding_cid: control.identity(request),
    manifest_cid: projection[7],
    objects: Object.freeze(chunks.map(chunk => Object.freeze({
      cid: chunk.cid,
      byte_count: Number(chunk.byteLength),
    }))),
  });
}

async function authorizeUse(entry, authorize, control, clock, phase, peer) {
  if (!control.activeAt(entry.request, now(clock))) {
    fail('RemoteTransferExpired');
  }
  if (await authorize(Object.freeze({
    request: entry.request,
    phase,
    peer,
    useId: entry.useId,
  })) !== true) {
    fail('RemoteTransferUnauthorized');
  }
  if (!control.activeAt(entry.request, now(clock))) {
    fail('RemoteTransferExpired');
  }
}

async function releasePrepared(entry) {
  const failures = [];
  for (let index = entry.writers.length - 1; index >= 0; index--) {
    const prepared = entry.prepared[index]?.prepared;
    try {
      if (prepared === undefined) await entry.writers[index].cancel();
      else await prepared.retry();
    }
    catch (error) { failures.push(error); }
  }
  if (failures.length !== 0) {
    throw new AggregateError(failures, 'Transfer Store cleanup failed');
  }
}

export async function startHttpsTransferObjectStore({
  host = '127.0.0.1',
  port = 0,
  key,
  cert,
  ca,
  peerAuthorities,
  control,
  store,
  authorize,
  clock = () => Date.now(),
  maxControlBytes = 131_072,
  maxManifestBytes = 65_536,
  maxChunks = 4096,
  maxReferencedBytes = 9_007_199_254_740_991n,
  maxFrameBytes = 1024 * 1024,
} = {}) {
  if (!text(host) || !count(port) || key === undefined || cert === undefined ||
      ca === undefined || !(peerAuthorities instanceof Map) ||
      control === null || typeof control !== 'object' ||
      typeof control.admitJson !== 'function' ||
      typeof control.identity !== 'function' ||
      typeof control.requestProjection !== 'function' ||
      typeof control.chunks !== 'function' ||
      typeof control.activeAt !== 'function' ||
      store === null || typeof store !== 'object' ||
      typeof store.createPreparedObjectWriter !== 'function' ||
      typeof store.commitPhysicalHolding !== 'function' ||
      typeof store.inspectPhysicalHolding !== 'function' ||
      typeof store.consumePhysicalHolding !== 'function' ||
      typeof authorize !== 'function' || typeof clock !== 'function' ||
      !count(maxControlBytes) || maxControlBytes === 0 ||
      !count(maxManifestBytes) || maxManifestBytes === 0 ||
      !count(maxChunks) || typeof maxReferencedBytes !== 'bigint' ||
      maxReferencedBytes < 0n || !count(maxFrameBytes) ||
      maxFrameBytes === 0) {
    fail('InvalidTransferObjectStoreConfiguration');
  }
  const base = '/v1/transfer-store';
  const uploads = new Map();
  const downloads = new Map();
  let admissionClosed = false;
  let listenerClosed = false;
  let closed = false;

  const peerFor = request => {
    const certificate = request.socket.getPeerCertificate();
    const siteKey = peerAuthorities.get(certificate.fingerprint256);
    if (!request.socket.authorized || !text(siteKey)) {
      fail('RemoteTransferUnauthorized');
    }
    return Object.freeze({siteKey});
  };
  const admit = async (request, peer, phase, useId) => {
    if (admissionClosed || request.headers['content-type'] !==
        'application/json') {
      fail('RemoteTransferUnavailable');
    }
    const claimedRequestCid = request.headers['actql-transfer-cid'];
    const claimedManifestCid = request.headers['actql-manifest-cid'];
    if (!text(claimedRequestCid) || !text(claimedManifestCid)) {
      fail('InvalidRemoteTransferEnvelope');
    }
    const envelope = parseEnvelope(
      await readBoundedBody(request, maxControlBytes),
    );
    const admitted = control.admitJson(
      envelope.request,
      envelope.manifest,
      claimedRequestCid,
      claimedManifestCid,
      {maxChunks, maxManifestBytes, maxReferencedBytes},
    );
    const projection = control.requestProjection(admitted);
    if (projection[1] !== 'store') fail('InvalidRemoteTransferRoute');
    const expectedSite = phase === 'upload' ? projection[2] : projection[4];
    if (peer.siteKey !== expectedSite) fail('RemoteTransferUnauthorized');
    const entry = {request: admitted, useId};
    await authorizeUse(entry, authorize, control, clock, `${phase}:admit`, peer);
    return Object.freeze({admitted, projection, claimedRequestCid});
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
      if (request.method === 'POST' && request.url === `${base}/uploads`) {
        const accepted = await admit(request, peer, 'upload');
        const existing = await store.inspectPhysicalHolding(
          accepted.claimedRequestCid,
        );
        if (existing !== undefined) {
          reply(response, 200, {requestCid: accepted.claimedRequestCid,
            sealed: true});
          return;
        }
        let entry = uploads.get(accepted.claimedRequestCid);
        if (entry === undefined) {
          entry = {
            request: accepted.admitted,
            peer,
            chunks: control.chunks(accepted.admitted),
            writers: [],
            prepared: [],
            nextChunk: 0,
            busy: false,
            useId: undefined,
          };
          for (const chunk of entry.chunks) {
            entry.writers.push(store.createPreparedObjectWriter(
              Number(chunk.byteLength),
            ));
          }
          uploads.set(accepted.claimedRequestCid, entry);
        }
        reply(response, entry.nextChunk === entry.chunks.length ? 200 : 201, {
          requestCid: accepted.claimedRequestCid,
          sealed: false,
          nextChunk: entry.nextChunk,
        });
        return;
      }

      if (request.method === 'POST' && request.url === `${base}/downloads`) {
        const useId = request.headers['actql-transfer-use-id'];
        if (!text(useId) || useId.length > 256) {
          fail('InvalidRemoteTransferUse');
        }
        const accepted = await admit(request, peer, 'download', useId);
        const holding = await store.inspectPhysicalHolding(
          accepted.claimedRequestCid,
        );
        if (holding === undefined) fail('RemoteTransferUnavailable');
        const key = `${accepted.claimedRequestCid}\n${useId}`;
        let entry = downloads.get(key);
        if (entry === undefined) {
          entry = {
            request: accepted.admitted,
            peer,
            useId,
            holding,
            complete: false,
            busy: false,
          };
          await authorizeUse(
            entry,
            authorize,
            control,
            clock,
            'download:claim',
            peer,
          );
          downloads.set(key, entry);
        }
        reply(response, 200, {
          requestCid: accepted.claimedRequestCid,
          useId,
          complete: entry.complete,
        });
        return;
      }

      const parts = request.url?.split('/').filter(Boolean) ?? [];
      if (parts.length < 5 || parts[0] !== 'v1' ||
          parts[1] !== 'transfer-store') {
        fail('RemoteTransferUnavailable');
      }
      const operation = parts[2];
      const requestCid = decodeURIComponent(parts[3]);
      if (operation === 'uploads') {
        const entry = uploads.get(requestCid);
        if (entry === undefined || entry.peer.siteKey !== peer.siteKey) {
          fail('RemoteTransferUnavailable');
        }
        if (request.method === 'PUT' && parts.length === 6 &&
            parts[4] === 'chunks') {
          const index = Number(parts[5]);
          if (!count(index) || index >= entry.chunks.length ||
              index !== entry.nextChunk || entry.busy ||
              request.headers['content-type'] !==
                'application/octet-stream') {
            fail('InvalidRemoteTransferChunk');
          }
          await authorizeUse(
            entry, authorize, control, clock, 'upload:write', peer,
          );
          const expected = entry.chunks[index];
          const announced = request.headers['content-length'];
          if (!text(announced) || !/^(0|[1-9][0-9]*)$/.test(announced) ||
              BigInt(announced) !== expected.byteLength) {
            fail('RemoteTransferChunkLengthMismatch');
          }
          entry.busy = true;
          let received = 0n;
          try {
            for await (const frame of request) {
              received += BigInt(frame.byteLength);
              if (received > expected.byteLength) {
                fail('RemoteTransferChunkLengthMismatch');
              }
              for (let offset = 0; offset < frame.byteLength;
                offset += maxFrameBytes) {
                await entry.writers[index].append(
                  frame.subarray(offset, offset + maxFrameBytes),
                );
              }
            }
            if (received !== expected.byteLength) {
              fail('RemoteTransferChunkLengthMismatch');
            }
            entry.prepared[index] = await entry.writers[index].seal(
              expected.cid,
            );
            entry.nextChunk++;
          } catch (error) {
            try { await releasePrepared(entry); }
            catch (cleanupError) {
              throw new AggregateError(
                [error, cleanupError],
                'Transfer Store write and cleanup failed',
                {cause: error},
              );
            }
            uploads.delete(requestCid);
            throw error;
          } finally {
            entry.busy = false;
          }
          reply(response, 200, {requestCid, nextChunk: entry.nextChunk});
          return;
        }
        if (request.method === 'POST' && parts.length === 5 &&
            parts[4] === 'commit') {
          await readBoundedBody(request, 0);
          await authorizeUse(
            entry, authorize, control, clock, 'upload:commit', peer,
          );
          if (entry.busy || entry.nextChunk !== entry.chunks.length) {
            fail('RemoteTransferIncomplete');
          }
          await store.commitPhysicalHolding(
            physicalHolding(control, entry.request),
            entry.prepared.map(value => value.prepared),
          );
          uploads.delete(requestCid);
          reply(response, 200, {requestCid, sealed: true});
          return;
        }
      }

      if (operation === 'downloads' && parts.length >= 6) {
        const useId = decodeURIComponent(parts[4]);
        const entry = downloads.get(`${requestCid}\n${useId}`);
        if (entry === undefined || entry.peer.siteKey !== peer.siteKey) {
          fail('RemoteTransferUnavailable');
        }
        if (request.method === 'GET' && parts.length === 7 &&
            parts[5] === 'chunks') {
          const index = Number(parts[6]);
          if (!count(index) || index >= entry.holding.objects.length ||
              entry.complete || entry.busy) {
            fail('InvalidRemoteTransferChunk');
          }
          await authorizeUse(
            entry, authorize, control, clock, 'download:read', peer,
          );
          const object = entry.holding.objects[index];
          entry.busy = true;
          response.writeHead(200, {
            'content-type': 'application/octet-stream',
            'content-length': String(object.byte_count),
            'cache-control': 'no-store',
          });
          try {
            await store.consumePhysicalHolding(requestCid, index,
              async frame => {
                const owned = Buffer.from(frame);
                if (!response.write(owned)) await once(response, 'drain');
              });
            response.end();
          } finally {
            entry.busy = false;
          }
          return;
        }
        if (request.method === 'POST' && parts.length === 6 &&
            parts[5] === 'complete') {
          await readBoundedBody(request, 0);
          await authorizeUse(
            entry, authorize, control, clock, 'download:complete', peer,
          );
          if (entry.busy) fail('RemoteTransferBusy');
          entry.complete = true;
          reply(response, 200, {requestCid, useId, complete: true});
          return;
        }
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
    fail('TransferObjectStoreAddressUnavailable');
  }
  return Object.freeze({
    origin: `https://${host}:${address.port}`,
    port: address.port,
    async close() {
      admissionClosed = true;
      if (closed) return false;
      if (!listenerClosed) {
        await new Promise((resolve, reject) => server.close(error => {
          if (error) reject(error);
          else resolve();
        }));
        listenerClosed = true;
      }
      const cleanupFailures = [];
      for (const [requestCid, entry] of uploads) {
        try {
          await releasePrepared(entry);
          uploads.delete(requestCid);
        } catch (error) {
          cleanupFailures.push(error);
        }
      }
      if (cleanupFailures.length !== 0) {
        throw new AggregateError(
          cleanupFailures,
          'Transfer Store close cleanup failed',
        );
      }
      if (uploads.size !== 0 || [...downloads.values()].some(
        entry => !entry.complete || entry.busy,
      )) {
        fail('RemoteTransferCleanupPending');
      }
      closed = true;
      return true;
    },
  });
}

async function responseJson(response, maxBytes) {
  const bytes = await readBoundedBody(response, maxBytes);
  let value;
  try { value = JSON.parse(bytes.toString('utf8')); }
  catch (error) { fail('InvalidRemoteTransferResponse', error); }
  if (response.statusCode !== 200 && response.statusCode !== 201) {
    fail('RemoteTransferRejected', undefined, {
      remoteError: value?.error,
      statusCode: response.statusCode,
    });
  }
  return value;
}

async function send({
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
    const outgoing = httpsRequest(new URL(path, origin), {
      method, ca, cert, key, servername, minVersion: 'TLSv1.3', signal, headers,
    }, response => responseJson(response, maxResponseBytes).then(
      value => writing.then(() => resolve(value), reject),
      error => writing.then(() => reject(error), () => reject(error)),
    ));
    outgoing.once('error', error => writing.then(
      () => reject(error),
      () => reject(error),
    ));
    writing = Promise.resolve().then(() => write(outgoing));
    writing.catch(error => outgoing.destroy(error));
  });
}

function envelope(control, request) {
  return Buffer.from(JSON.stringify({
    manifest: control.manifestJson(request),
    request: control.requestJson(request),
  }), 'utf8');
}

function commonHeaders(control, request, bytes) {
  return {
    'content-type': 'application/json',
    'content-length': String(bytes.byteLength),
    'actql-transfer-cid': control.identity(request),
    'actql-manifest-cid': control.requestProjection(request)[7],
  };
}

export async function uploadHttpsTransferObject({
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
      typeof control.requestProjection !== 'function' ||
      typeof control.identity !== 'function' ||
      typeof control.chunks !== 'function' || request === undefined ||
      !Array.isArray(sourceBodies) || !count(maxResponseBytes) ||
      maxResponseBytes === 0) {
    fail('InvalidTransferObjectUploadConfiguration');
  }
  const projection = control.requestProjection(request);
  if (projection[1] !== 'store') fail('InvalidRemoteTransferRoute');
  const chunks = control.chunks(request);
  if (chunks.length !== sourceBodies.length) {
    fail('RemoteTransferSourceMismatch');
  }
  for (let index = 0; index < chunks.length; index++) {
    const source = sourceBodies[index];
    if (source === null || typeof source !== 'object' ||
        typeof source.consume !== 'function' ||
        source.cid !== chunks[index].cid ||
        BigInt(source.bytes) !== chunks[index].byteLength) {
      fail('RemoteTransferSourceMismatch');
    }
  }
  const body = envelope(control, request);
  const common = {origin, ca, cert, key, servername, signal,
    maxResponseBytes};
  const admitted = await send({
    ...common,
    path: '/v1/transfer-store/uploads',
    method: 'POST',
    headers: commonHeaders(control, request, body),
    write(outgoing) { outgoing.end(body); },
  });
  if (admitted.sealed === true) return admitted;
  const requestCid = control.identity(request);
  for (let index = admitted.nextChunk ?? 0; index < chunks.length; index++) {
    const source = sourceBodies[index];
    await send({
      ...common,
      path: `/v1/transfer-store/uploads/${encodeURIComponent(requestCid)}` +
        `/chunks/${index}`,
      method: 'PUT',
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': chunks[index].byteLength.toString(),
      },
      async write(outgoing) {
        await source.consume(async frame => {
          const owned = Buffer.from(frame);
          if (!outgoing.write(owned)) await once(outgoing, 'drain');
        }, signal);
        outgoing.end();
      },
    });
  }
  return await send({
    ...common,
    path: `/v1/transfer-store/uploads/${encodeURIComponent(requestCid)}` +
      '/commit',
    method: 'POST',
    headers: {'content-length': '0'},
    write(outgoing) { outgoing.end(); },
  });
}

async function downloadChunk({common, path, writer, expected, signal}) {
  await new Promise((resolve, reject) => {
    let received = 0n;
    let consuming = Promise.resolve();
    const outgoing = httpsRequest(new URL(path, common.origin), {
      method: 'GET',
      ca: common.ca,
      cert: common.cert,
      key: common.key,
      servername: common.servername,
      minVersion: 'TLSv1.3',
      signal,
    }, response => {
      if (response.statusCode !== 200 ||
          response.headers['content-type'] !== 'application/octet-stream' ||
          BigInt(response.headers['content-length'] ?? '-1') !==
            expected.byteLength) {
        response.resume();
        reject(Object.assign(new Error('RemoteTransferRejected'), {
          code: 'RemoteTransferRejected',
        }));
        return;
      }
      response.on('data', frame => {
        response.pause();
        received += BigInt(frame.byteLength);
        consuming = consuming.then(() => writer.append(frame));
        consuming.then(() => response.resume(), error => response.destroy(error));
      });
      response.once('end', () => consuming.then(() => {
        if (received !== expected.byteLength) {
          fail('RemoteTransferChunkLengthMismatch');
        }
        resolve();
      }, reject));
      response.once('error', reject);
    });
    outgoing.once('error', reject);
    outgoing.end();
  });
}

export async function receiveHttpsTransferObject({
  origin,
  ca,
  cert,
  key,
  servername = 'localhost',
  control,
  request,
  useId,
  journal,
  destinationStore,
  signal,
  maxResponseBytes = 16_384,
} = {}) {
  if (!text(origin) || ca === undefined || cert === undefined ||
      key === undefined || !text(servername) || !text(useId) ||
      control === null || typeof control !== 'object' ||
      journal === null || typeof journal !== 'object' ||
      typeof journal.accept !== 'function' ||
      typeof journal.advance !== 'function' ||
      typeof journal.commitDestinationReceipt !== 'function' ||
      destinationStore === null || typeof destinationStore !== 'object' ||
      typeof destinationStore.createPreparedObjectWriter !== 'function' ||
      typeof destinationStore.commitPhysicalHolding !== 'function' ||
      typeof destinationStore.inspectPhysicalHolding !== 'function' ||
      !count(maxResponseBytes) || maxResponseBytes === 0) {
    fail('InvalidTransferObjectDownloadConfiguration');
  }
  const projection = control.requestProjection(request);
  if (projection[1] !== 'store') fail('InvalidRemoteTransferRoute');
  const requestCid = control.identity(request);
  let accepted = journal.accept(request, control);
  let record = accepted.record;
  const initial = control.recordProjection(record);
  if (initial[0] === 0) {
    record = journal.advance(control.prepareStart(record), control);
  }
  const destinationHolding = physicalHolding(control, request);
  let installed = await destinationStore.inspectPhysicalHolding(requestCid);
  const common = {origin, ca, cert, key, servername, signal,
    maxResponseBytes};
  const admission = envelope(control, request);
  await send({
    ...common,
    path: '/v1/transfer-store/downloads',
    method: 'POST',
    headers: {
      ...commonHeaders(control, request, admission),
      'actql-transfer-use-id': useId,
    },
    write(outgoing) { outgoing.end(admission); },
  });
  if (control.recordProjection(record)[5] === 0) {
    record = journal.advance(
      control.prepareSourceSettled(record, true, true),
      control,
    );
  }
  if (installed === undefined) {
    const prepared = [];
    try {
      const chunks = control.chunks(request);
      for (let index = 0; index < chunks.length; index++) {
        const writer = destinationStore.createPreparedObjectWriter(
          Number(chunks[index].byteLength),
        );
        await downloadChunk({
          common,
          path: `/v1/transfer-store/downloads/${encodeURIComponent(
            requestCid,
          )}/${encodeURIComponent(useId)}/chunks/${index}`,
          writer,
          expected: chunks[index],
          signal,
        });
        prepared.push(await writer.seal(chunks[index].cid));
      }
      await destinationStore.commitPhysicalHolding(
        destinationHolding,
        prepared.map(value => value.prepared),
      );
      installed = await destinationStore.inspectPhysicalHolding(requestCid);
    } catch (error) {
      const failures = [];
      for (let index = prepared.length - 1; index >= 0; index--) {
        try { await prepared[index].cleanup.retry(); }
        catch (cleanupError) { failures.push(cleanupError); }
      }
      if (failures.length !== 0) {
        throw new AggregateError(
          [error, ...failures],
          'Transfer destination write and cleanup failed',
          {cause: error},
        );
      }
      throw error;
    }
  }
  if (JSON.stringify(installed) !== JSON.stringify(destinationHolding)) {
    fail('RemoteTransferDestinationMismatch');
  }
  await send({
    ...common,
    path: `/v1/transfer-store/downloads/${encodeURIComponent(
      requestCid,
    )}/${encodeURIComponent(useId)}/complete`,
    method: 'POST',
    headers: {'content-length': '0'},
    write(outgoing) { outgoing.end(); },
  });
  const receipt = control.prepareDestinationReceipt(request, requestCid);
  journal.commitDestinationReceipt(receipt, request, control);
  if (control.recordProjection(record)[1] !== 2) {
    record = journal.advance(
      control.prepareDestinationCommit(record),
      control,
    );
  }
  return Object.freeze({request, record, receipt, holding: installed});
}
