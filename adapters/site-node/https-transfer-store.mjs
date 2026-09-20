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

function replyCanonical(response, status, body) {
  const bytes = Buffer.from(body, 'utf8');
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
  useJournal,
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
      typeof control.admitAdmissionEnvelopeJson !== 'function' ||
      typeof control.storeUploadReplyJson !== 'function' ||
      typeof control.storeUseReplyJson !== 'function' ||
      typeof control.identity !== 'function' ||
      typeof control.requestProjection !== 'function' ||
      typeof control.chunks !== 'function' ||
      typeof control.activeAt !== 'function' ||
      typeof control.admitDestinationReceiptJson !== 'function' ||
      typeof control.destinationReceiptJson !== 'function' ||
      typeof control.destinationReceiptIdentity !== 'function' ||
      store === null || typeof store !== 'object' ||
      typeof store.createPreparedObjectWriter !== 'function' ||
      typeof store.commitPhysicalHolding !== 'function' ||
      typeof store.inspectPhysicalHolding !== 'function' ||
      typeof store.consumePhysicalHolding !== 'function' ||
      useJournal === null || typeof useJournal !== 'object' ||
      typeof useJournal.accept !== 'function' ||
      typeof useJournal.advance !== 'function' ||
      typeof useJournal.recover !== 'function' ||
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
  const storeUseControl = control.storeUse;
  if (storeUseControl === null || typeof storeUseControl !== 'object') {
    fail('MissingRemoteTransferStoreControl');
  }

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
    const admitted = control.admitAdmissionEnvelopeJson(
      new TextDecoder('utf-8', {fatal: true}).decode(
        await readBoundedBody(request, maxControlBytes),
      ),
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

  for (const recovered of useJournal.recover(control)) {
    const projection = storeUseControl.projection(recovered.storeUse);
    const holding = await store.inspectPhysicalHolding(projection[1]);
    if (holding === undefined) continue;
    const state = storeUseControl.recordProjection(recovered.record);
    downloads.set(`${projection[1]}\n${projection[2]}`, {
      request: recovered.request,
      peer: Object.freeze({siteKey: projection[3]}),
      useId: projection[2],
      holding,
      storeUse: recovered.storeUse,
      useRecord: recovered.record,
      complete: state[1] === '2',
      receipt: undefined,
      busy: false,
    });
  }

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
          replyCanonical(response, 200, control.storeUploadReplyJson(
            accepted.admitted,
            'admission',
            control.chunks(accepted.admitted).length,
            true,
          ));
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
        replyCanonical(
          response,
          entry.nextChunk === entry.chunks.length ? 200 : 201,
          control.storeUploadReplyJson(
            accepted.admitted,
            'admission',
            entry.nextChunk,
            false,
          ),
        );
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
          const acceptedUse = useJournal.accept(
            accepted.admitted,
            useId,
            control,
          );
          let useRecord = acceptedUse.record;
          if (storeUseControl.recordProjection(useRecord)[1] === '0') {
            useRecord = useJournal.advance(
              storeUseControl.prepareStart(useRecord),
              control,
            );
          }
          entry = {
            request: accepted.admitted,
            peer,
            useId,
            holding,
            storeUse: acceptedUse.storeUse,
            useRecord,
            complete:
              storeUseControl.recordProjection(useRecord)[1] === '2',
            receipt: undefined,
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
        replyCanonical(response, 200, control.storeUseReplyJson(
          accepted.admitted,
          useId,
          'admission',
          entry.complete,
        ));
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
          replyCanonical(response, 200, control.storeUploadReplyJson(
            entry.request,
            'chunk',
            entry.nextChunk,
            false,
          ));
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
          replyCanonical(response, 200, control.storeUploadReplyJson(
            entry.request,
            'commit',
            entry.nextChunk,
            true,
          ));
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
          const state = storeUseControl.recordProjection(entry.useRecord);
          const confirmedChunks = Number(state[3]);
          const confirmedBytes = BigInt(state[4]);
          const expectedPrefix = entry.holding.objects.slice(0, index)
            .reduce((total, item) => total + BigInt(item.byte_count), 0n);
          if (confirmedChunks !== index || confirmedBytes !== expectedPrefix) {
            fail('RemoteTransferChunkOrder');
          }
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
            const finished = once(response, 'finish');
            response.end();
            await finished;
            entry.useRecord = useJournal.advance(
              storeUseControl.prepareProgress(
                entry.useRecord,
                index + 1,
                confirmedBytes + BigInt(object.byte_count),
              ),
              control,
            );
          } catch (error) {
            const failedState = storeUseControl.recordProjection(
              entry.useRecord,
            );
            if (failedState[1] !== '2' && failedState[1] !== '3') {
              entry.useRecord = useJournal.advance(
                storeUseControl.prepareFailure(entry.useRecord, true),
                control,
              );
              entry.useRecord = useJournal.advance(
                storeUseControl.prepareCleanup(entry.useRecord),
                control,
              );
            }
            throw error;
          } finally {
            entry.busy = false;
          }
          return;
        }
        if (request.method === 'POST' && parts.length === 6 &&
            parts[5] === 'complete') {
          const claimedReceiptCid = request.headers[
            'actql-destination-receipt-cid'
          ];
          if (!text(claimedReceiptCid) ||
              request.headers['content-type'] !== 'application/json') {
            fail('InvalidRemoteTransferDestinationReceipt');
          }
          const receiptJson = new TextDecoder('utf-8', {fatal: true}).decode(
            await readBoundedBody(request, 4096),
          );
          const receipt = control.admitDestinationReceiptJson(
            receiptJson,
            entry.request,
            claimedReceiptCid,
          );
          await authorizeUse(
            entry, authorize, control, clock, 'download:complete', peer,
          );
          if (entry.busy) fail('RemoteTransferBusy');
          const state = storeUseControl.recordProjection(entry.useRecord);
          if (state[1] === '2' && state[6] !== claimedReceiptCid) {
            fail('RemoteTransferDestinationReceiptCollision');
          }
          if (state[1] !== '2') {
            entry.useRecord = useJournal.advance(
              storeUseControl.prepareComplete(entry.useRecord, receipt),
              control,
            );
            entry.useRecord = useJournal.advance(
              storeUseControl.prepareCleanup(entry.useRecord),
              control,
            );
            entry.receipt = receipt;
            entry.complete = true;
          }
          replyCanonical(response, 200, control.storeUseReplyJson(
            entry.request,
            useId,
            'completion',
            true,
          ));
          return;
        }
        if (request.method === 'POST' && parts.length === 6 &&
            parts[5] === 'cancel') {
          await readBoundedBody(request, 0);
          await authorizeUse(
            entry, authorize, control, clock, 'download:cancel', peer,
          );
          if (entry.busy) fail('RemoteTransferBusy');
          const state = storeUseControl.recordProjection(entry.useRecord);
          if (state[1] !== '2' && state[1] !== '3') {
            entry.useRecord = useJournal.advance(
              storeUseControl.prepareFailure(entry.useRecord, true),
              control,
            );
            entry.useRecord = useJournal.advance(
              storeUseControl.prepareCleanup(entry.useRecord),
              control,
            );
          }
          reply(response, 200, {requestCid, useId, cancelled: true});
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
        entry => entry.busy,
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
  const wire = bytes.toString('utf8');
  let value;
  try { value = JSON.parse(wire); }
  catch (error) { fail('InvalidRemoteTransferResponse', error); }
  if (response.statusCode !== 200 && response.statusCode !== 201) {
    fail('RemoteTransferRejected', undefined, {
      remoteError: value?.error,
      statusCode: response.statusCode,
    });
  }
  if (value !== null && typeof value === 'object') responseWires.set(value, wire);
  return value;
}

const responseWires = new WeakMap();

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
  return Buffer.from(control.admissionEnvelopeJson(request), 'utf8');
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
      typeof control.admissionEnvelopeJson !== 'function' ||
      typeof control.admitStoreUploadReplyJson !== 'function' ||
      typeof control.storeUploadReplyProjection !== 'function' ||
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
  const admittedReply = control.admitStoreUploadReplyJson(
    responseWires.get(admitted),
    request,
    'admission',
  );
  const admittedState = control.storeUploadReplyProjection(admittedReply);
  if (admittedState[2] === '1') return admitted;
  const requestCid = control.identity(request);
  for (let index = Number(admittedState[1]); index < chunks.length; index++) {
    const source = sourceBodies[index];
    const uploaded = await send({
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
    control.admitStoreUploadReplyJson(
      responseWires.get(uploaded),
      request,
      'chunk',
    );
  }
  const committed = await send({
    ...common,
    path: `/v1/transfer-store/uploads/${encodeURIComponent(requestCid)}` +
      '/commit',
    method: 'POST',
    headers: {'content-length': '0'},
    write(outgoing) { outgoing.end(); },
  });
  control.admitStoreUploadReplyJson(
    responseWires.get(committed),
    request,
    'commit',
  );
  return committed;
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
      typeof control.prepareDestinationReceipt !== 'function' ||
      typeof control.destinationReceiptJson !== 'function' ||
      typeof control.destinationReceiptIdentity !== 'function' ||
      typeof control.admitStoreUseReplyJson !== 'function' ||
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
  const admittedUse = await send({
    ...common,
    path: '/v1/transfer-store/downloads',
    method: 'POST',
    headers: {
      ...commonHeaders(control, request, admission),
      'actql-transfer-use-id': useId,
    },
    write(outgoing) { outgoing.end(admission); },
  });
  control.admitStoreUseReplyJson(
    responseWires.get(admittedUse),
    request,
    useId,
    'admission',
  );
  if (control.recordProjection(record)[5] === 0) {
    record = journal.advance(
      control.prepareSourceSettled(record, true, true),
      control,
    );
  }
  if (installed === undefined) {
    const writers = [];
    const prepared = [];
    try {
      const chunks = control.chunks(request);
      for (let index = 0; index < chunks.length; index++) {
        const writer = destinationStore.createPreparedObjectWriter(
          Number(chunks[index].byteLength),
        );
        writers.push(writer);
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
      for (let index = writers.length - 1; index >= 0; index--) {
        try {
          if (prepared[index] === undefined) await writers[index].cancel();
          else await prepared[index].prepared.retry();
        }
        catch (cleanupError) { failures.push(cleanupError); }
      }
      try {
        await send({
          ...common,
          signal: undefined,
          path: `/v1/transfer-store/downloads/${encodeURIComponent(
            requestCid,
          )}/${encodeURIComponent(useId)}/cancel`,
          method: 'POST',
          headers: {'content-length': '0'},
          write(outgoing) { outgoing.end(); },
        });
      } catch {}
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
  const receipt = control.prepareDestinationReceipt(request, requestCid);
  journal.commitDestinationReceipt(receipt, request, control);
  const receiptJson = Buffer.from(
    control.destinationReceiptJson(receipt),
    'utf8',
  );
  const completedUse = await send({
    ...common,
    path: `/v1/transfer-store/downloads/${encodeURIComponent(
      requestCid,
    )}/${encodeURIComponent(useId)}/complete`,
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'content-length': String(receiptJson.byteLength),
      'actql-destination-receipt-cid':
        control.destinationReceiptIdentity(receipt),
    },
    write(outgoing) { outgoing.end(receiptJson); },
  });
  control.admitStoreUseReplyJson(
    responseWires.get(completedUse),
    request,
    useId,
    'completion',
  );
  if (control.recordProjection(record)[1] !== 2) {
    record = journal.advance(
      control.prepareDestinationCommit(record),
      control,
    );
  }
  return Object.freeze({request, record, receipt, holding: installed});
}
