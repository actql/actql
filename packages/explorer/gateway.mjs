import {readWaitingCheckpoints,readCheckpointReview} from './checkpoint-read.mjs';
import {randomBytes, timingSafeEqual} from 'node:crypto';
import {Hono} from 'hono';
import {serve} from '@hono/node-server';
import {validRunRef} from '@actql/client-wire';
import {createReadEpoch, describeExistingResult, readExistingRun, readExistingRunPlan,
  readStaticPlan} from '@actql/explorer-ui/read-model';
import {copyExplorerLaunchInput} from './launch-input.mjs';
import {requestExistingCancellation, lookupExistingCancellation} from './cancellation.mjs';
import {readRunObservation} from '@actql/explorer-ui/run-observation';

// These are presentation/transport ceilings, not new execution reservations.
export const gatewayLimits = Object.freeze({bodyBytes: 65536, replyBytes: 262144,
  bodyDepth: 64, bodyNodes: 10000, inFlight: 4, assets: 32,
  assetBytes: 4 * 1024 * 1024, sessionMs: 300000, bootstrapMs: 60000,
  requestMs: 15000});
const cookieName = 'actql_explorer_session';
const token = () => randomBytes(32).toString('base64url');
const sameToken = (a, b) => typeof a === 'string' && typeof b === 'string' &&
  /^[a-zA-Z0-9_-]{43}$/u.test(a) && /^[a-zA-Z0-9_-]{43}$/u.test(b) &&
  timingSafeEqual(Buffer.from(a), Buffer.from(b));
const exact = (value, required, optional = []) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  required.every(key => Object.hasOwn(value, key)) &&
  Object.keys(value).every(key => [...required, ...optional].includes(key));
const fail = (code, status = 400) => {throw Object.assign(new Error(code), {code, status});};
function jsonShape(value) {
  const pending = [[value, 0]]; let count = 0;
  while (pending.length) {
    const [node, depth] = pending.pop();
    if (++count > gatewayLimits.bodyNodes || depth > gatewayLimits.bodyDepth) {
      fail('ExplorerBodyLimit', 413);
    }
    if (node !== null && typeof node === 'object') {
      for (const child of Object.values(node)) pending.push([child, depth + 1]);
    }
  }
}
async function readJson(request) {
  if (request.headers.get('content-type') !== 'application/json') fail('ExplorerContentType');
  const length = request.headers.get('content-length');
  if (length !== null && (!/^\d+$/u.test(length) || Number(length) > gatewayLimits.bodyBytes)) {
    fail('ExplorerBodyLimit', 413);
  }
  const reader = request.body?.getReader();
  if (!reader) fail('ExplorerInvalidRequest');
  const chunks = []; let size = 0;
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    reader.cancel().catch(() => {});
  }, gatewayLimits.requestMs);
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (timedOut) fail('ExplorerReadTimeout', 504);
      if (done) break;
      size += value.byteLength;
      if (size > gatewayLimits.bodyBytes) fail('ExplorerBodyLimit', 413);
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {clearTimeout(timer); reader.releaseLock();}
  let parsed;
  try {parsed = JSON.parse(new TextDecoder('utf-8', {fatal: true})
    .decode(Buffer.concat(chunks, size)));}
  catch {fail('ExplorerInvalidRequest');}
  jsonShape(parsed);
  return parsed;
}
function copiedAssets(assets) {
  if (!(assets instanceof Map) || assets.size > gatewayLimits.assets) fail('ExplorerInvalidAssets');
  const result = new Map(); let size = 0;
  for (const [path, asset] of assets) {
    if (!/^\/(?:index\.html|assets\/[a-zA-Z0-9_-]+\.(?:js|css|svg))$/u.test(path) ||
        !exact(asset, ['body', 'contentType']) || !(asset.body instanceof Uint8Array) ||
        !['text/html; charset=utf-8', 'text/javascript; charset=utf-8',
          'text/css; charset=utf-8', 'image/svg+xml'].includes(asset.contentType)) {
      fail('ExplorerInvalidAssets');
    }
    size += asset.body.byteLength;
    if (size > gatewayLimits.assetBytes) fail('ExplorerAssetLimit');
    result.set(path, {body: Buffer.from(asset.body), contentType: asset.contentType});
  }
  return result;
}
function safeReadError(error) {
  if (['ExplorerBodyLimit', 'ExplorerContentType', 'ExplorerInvalidRequest',
    'ExplorerSessionExpired', 'ExplorerBootstrapRefused', 'ExplorerSessionRefused',
    'ExplorerBusy', 'ExplorerCapabilityUnavailable', 'ExplorerReplyLimit',
    'ExplorerReadTimeout', 'ExplorerStaleScope', 'ExplorerMapLimit',
    'ExplorerUnresolvedPort', 'ExplorerInvalidPlan', 'ExplorerInvalidRunPlan', 'ExplorerInvalidCancellation','ExplorerInvalidCheckpointReview'].includes(error?.code)) {
    return {code: error.code, status: error.status ?? 409};
  }
  // Never serialize Host messages, bodies, URLs, stack traces or credentials.
  if (error?.code === 'AuthorizationDenied' || error?.code === 'ClientUnauthorized' ||
      error?.status === 401 || error?.status === 403) {
    return {code: 'ExplorerReadRefused', status: 403};
  }
  return {code: 'ExplorerReadUnavailable', status: 502};
}

/** Attach a borrowed, already-connected public SDK Client. No Host is opened. */
export function createExplorerGateway({client, origin, assets = new Map(),
  now = Date.now, sessionMs = gatewayLimits.sessionMs,
  bootstrapMs = gatewayLimits.bootstrapMs, launchInput = null, allowCancellation = false}) {
  const address = new URL(origin);
  if (address.protocol !== 'http:' || address.hostname !== '127.0.0.1' ||
      !address.port || origin !== address.origin || address.username || address.password ||
      typeof allowCancellation !== 'boolean' || typeof client?.attach !== 'function' || typeof now !== 'function' ||
      !Number.isSafeInteger(sessionMs) || sessionMs <= 0 || sessionMs > gatewayLimits.sessionMs ||
      !Number.isSafeInteger(bootstrapMs) || bootstrapMs <= 0 || bootstrapMs > gatewayLimits.bootstrapMs) {
    fail('ExplorerInvalidGateway');
  }
  const staticAssets = copiedAssets(assets), epoch = createReadEpoch();
  const initialInput = copyExplorerLaunchInput(launchInput, gatewayLimits.bodyBytes);
  let closed = false, scopeEpoch = 0, session, bootstrap, inFlight = 0, closing;
  const outstanding = new Set();
  const invalidate = () => {epoch.invalidate(); scopeEpoch++; session = undefined; bootstrap = undefined;};
  const assertSession = selected => {
    if (closed || session !== selected || !session || now() >= session.expiresAt) {
      if (session === selected) invalidate();
      fail('ExplorerSessionExpired', 401);
    }
  };
  const app = new Hono();
  app.use('*', async (c, next) => {
    c.header('Cache-Control', 'no-store');
    c.header('X-Content-Type-Options', 'nosniff');
    c.header('Referrer-Policy', 'no-referrer');
    c.header('Content-Security-Policy', "default-src 'none'; script-src 'self'; worker-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
    if (closed) return c.json({error: 'ExplorerClosed'}, 503);
    // Host is checked independently from the URL parsed by the Node adapter.
    if (c.req.header('host') !== address.host || c.req.url.length > 1024 ||
        c.req.header('forwarded') !== undefined || c.req.header('x-forwarded-host') !== undefined ||
        new URL(c.req.url).origin !== origin) return c.json({error: 'ExplorerHostRefused'}, 403);
    const requestOrigin = c.req.header('origin');
    const site = c.req.header('sec-fetch-site');
    if ((requestOrigin !== undefined && requestOrigin !== origin) ||
        (site !== undefined && !['same-origin', 'none'].includes(site))) {
      return c.json({error: 'ExplorerOriginRefused'}, 403);
    }
    if (c.req.method === 'POST' && requestOrigin !== origin) {
      return c.json({error: 'ExplorerOriginRefused'}, 403);
    }
    if (new URL(c.req.url).search !== '') return c.json({error: 'ExplorerInvalidRequest'}, 400);
    await next();
  });
  app.onError((error, c) => {
    const safe = safeReadError(error);
    return c.json({error: safe.code}, safe.status);
  });
  app.post('/api/session', async c => {
    const body = await readJson(c.req.raw);
    if (!exact(body, ['bootstrap']) || !bootstrap || now() >= bootstrap.expiresAt ||
        !sameToken(body.bootstrap, bootstrap.value)) fail('ExplorerBootstrapRefused', 403);
    invalidate();
    session = {value: token(), csrf: token(), expiresAt: now() + sessionMs};
    c.header('Set-Cookie', `${cookieName}=${session.value}; Path=/api; HttpOnly; SameSite=Strict; Max-Age=${Math.ceil(sessionMs / 1000)}`);
    return c.json({csrf: session.csrf, scopeEpoch, expiresAt: session.expiresAt,
      capabilities: {plan: typeof client.plan === 'function', run: true,
        resultMetadata: true, resultPayload: false, control: false, sample: false, cancellation: allowCancellation, checkpointList:typeof client.checkpoints==='function', checkpointReview:typeof client.reviewCheckpoint==='function'}});
  });
  app.post('/api/:group/:kind', async c => {
    const selected = session;
    assertSession(selected);
    // Duplicate cookies are refused; no ambiguous first/last interpretation.
    const matches = (c.req.header('cookie') ?? '').split(';')
      .map(part => part.trim()).filter(part => part.startsWith(`${cookieName}=`));
    if (matches.length !== 1 || !sameToken(matches[0].slice(cookieName.length + 1), selected.value) ||
        !sameToken(c.req.header('x-actql-csrf'), selected.csrf)) fail('ExplorerSessionRefused', 403);
    if (inFlight >= gatewayLimits.inFlight) fail('ExplorerBusy', 429);
    inFlight++;
    const originalTicket = epoch.capture(), originalEpoch = scopeEpoch;
    let timedOut = false, timer;
    const ticket = {assertCurrent() {
      originalTicket.assertCurrent();
      assertSession(selected);
      if (timedOut) fail('ExplorerReadTimeout', 504);
    }};
    // Register before any SDK callback can run, including a reentrant close.
    const read = Promise.resolve().then(async () => {try {
      const body = await readJson(c.req.raw);
      assertSession(selected); ticket.assertCurrent();
      let data;
      const group=c.req.param('group'),kind=c.req.param('kind');
      if (group==='control') {
        if (!allowCancellation) fail('ExplorerCapabilityUnavailable',404);
        if (kind==='cancel') {
          if (!exact(body,['cancelRef','attemptRef'])) fail('ExplorerInvalidRequest');
          data=await requestExistingCancellation(client,body,ticket);
        } else if (kind==='lookup-cancellation') {
          if (!exact(body,['cancelRef'])) fail('ExplorerInvalidRequest');
          data=await lookupExistingCancellation(client,body.cancelRef,ticket);
        } else fail('ExplorerCapabilityUnavailable',404);
      } else if (group!=='read') fail('ExplorerCapabilityUnavailable',404);
      else switch (kind) {
        case 'launch':
          if (!exact(body, [])) fail('ExplorerInvalidRequest');
          // Return only the existing Owner's admitted projection, not the
          // file's authoring text or a path into the launcher's filesystem.
          if (initialInput === null) data = null;
          else if (initialInput.kind === 'program') {
            const input = initialInput.format === 'program'
              ? JSON.parse(initialInput.text) : initialInput.text;
            const options = initialInput.format === 'program'
              ? {} : {format: initialInput.format};
            data = {kind: 'program', plan: await readStaticPlan(client, input, options, ticket)};
          } else {
            data = {kind: 'run', originalPlan: await readExistingRunPlan(client, initialInput.ref, ticket)};
          }
          break;
        case 'plan':
          if (!exact(body, ['input'], ['options']) ||
              !(typeof body.input === 'string' || body.input !== null &&
                typeof body.input === 'object' && !Array.isArray(body.input)) ||
              (body.options !== undefined && !exact(body.options, [],
                ['format', 'parameters', 'parameterDeclarations', 'maxWireBytes', 'maxNodes', 'maxDepth']))) {
            fail('ExplorerInvalidRequest');
          }
          data = await readStaticPlan(client, body.input, body.options ?? {}, ticket);
          break;
        case 'run':
          if (!exact(body, ['ref']) || !validRunRef(body.ref)) fail('ExplorerInvalidRequest');
          data = await readExistingRun(client, body.ref, ticket);
          break;
        case 'observation':
          if (!exact(body, ['ref']) || !validRunRef(body.ref)) fail('ExplorerInvalidRequest');
          data = await readRunObservation(client, body.ref, ticket);
          break;
        case 'run-plan':
          if (!exact(body, ['ref']) || !validRunRef(body.ref)) fail('ExplorerInvalidRequest');
          data = await readExistingRunPlan(client, body.ref, ticket);
          break;
        case 'checkpoints':
          if(!exact(body,[]))fail('ExplorerInvalidRequest');
          data=await readWaitingCheckpoints(client,ticket);break;
        case 'checkpoint-review':
          if(!exact(body,['checkpoint']))fail('ExplorerInvalidRequest');
          data=await readCheckpointReview(client,body.checkpoint,ticket);break;
        case 'result':
          if (!exact(body, ['ref', 'name']) || !validRunRef(body.ref) ||
              typeof body.name !== 'string' || body.name.length === 0 || body.name.length > 1024) {
            fail('ExplorerInvalidRequest');
          }
          data = await describeExistingResult(client, body.ref, body.name, ticket);
          break;
        default: fail('ExplorerCapabilityUnavailable', 404);
      }
      assertSession(selected); ticket.assertCurrent();
      const reply = JSON.stringify({scopeEpoch: originalEpoch, data});
      if (Buffer.byteLength(reply) > gatewayLimits.replyBytes) fail('ExplorerReplyLimit', 413);
      c.header('Content-Type', 'application/json');
      return c.body(reply);
    } catch (error) {
      assertSession(selected); ticket.assertCurrent();
      throw error;
    }});
    outstanding.add(read);
    const settled = () => {
      // Keep the slot until this same original read leaves the collection.
      outstanding.delete(read);
      inFlight--;
    };
    void read.then(settled, settled);
    // Timing out a presentation read neither cancels a Run nor releases the
    // outstanding SDK slot early. It remains held until that read settles.
    try {
      return await Promise.race([read, new Promise((_, reject) => {
        timer = setTimeout(() => {
          timedOut = true;
          reject(Object.assign(new Error('ExplorerReadTimeout'),
            {code: 'ExplorerReadTimeout', status: 504}));
        }, gatewayLimits.requestMs);
      })]);
    } finally {clearTimeout(timer);}
  });
  app.get('*', c => {
    const path = c.req.path === '/' ? '/index.html' : c.req.path;
    const asset = staticAssets.get(path);
    if (!asset) return c.json({error: 'ExplorerNotFound'}, 404);
    c.header('Content-Type', asset.contentType);
    return c.body(asset.body);
  });
  return Object.freeze({fetch: app.fetch,
    issueBootstrap() {
      if (closed) fail('ExplorerClosed');
      // Only an explicit local launcher/operator action creates a new session.
      invalidate();
      bootstrap = {value: token(), expiresAt: now() + bootstrapMs};
      return Object.freeze({origin, bootstrap: bootstrap.value, expiresAt: bootstrap.expiresAt});
    },
    invalidateScope() {invalidate();},
    close() {
      if (!closing) {
        closed = true;
        invalidate();
        // Presentation timeout, session invalidation and socket close do not
        // settle an original SDK invocation. The Client still owns its own
        // physical cleanup and must be closed separately after this settles.
        closing = Promise.allSettled([...outstanding]).then(() => {});
      }
      return closing;
    },
  });
}

/** The launcher owns only its loopback HTTP server, never the borrowed Client. */
export async function startExplorerGateway({port = 0, ...options}) {
  if (!Number.isSafeInteger(port) || port < 0 || port > 65535 || 'origin' in options) {
    fail('ExplorerInvalidGateway');
  }
  let gateway;
  // The adapter's global Request/Response optimization would change the SDK's
  // native Fetch response admission for a later HTTPS connection in this process.
  const server = serve({hostname: '127.0.0.1', port, overrideGlobalObjects: false,
    fetch: request => gateway ? gateway.fetch(request) :
      new Response(null, {status: 503})});
  server.requestTimeout = gatewayLimits.requestMs;
  server.headersTimeout = gatewayLimits.requestMs;
  await new Promise((resolve, reject) => {
    if (server.listening) resolve();
    else {server.once('listening', resolve); server.once('error', reject);}
  });
  const address = server.address();
  const origin = `http://127.0.0.1:${address.port}`;
  try {gateway = createExplorerGateway({...options, origin});}
  catch (error) {await new Promise(resolve => server.close(resolve)); throw error;}
  let closing;
  return Object.freeze({origin, issueBootstrap: gateway.issueBootstrap,
    invalidateScope: gateway.invalidateScope,
    close() {
      if (closing) return closing;
      const originalCalls = gateway.close();
      const socket = new Promise((resolve, reject) => {
        server.close(error => error ? reject(error) : resolve());
        server.closeAllConnections();
      });
      const attempt = Promise.allSettled([socket, originalCalls]).then(results => {
        const failed = results.filter(result => result.status === 'rejected');
        if (failed.length) throw new AggregateError(failed.map(result => result.reason),
          'ExplorerGatewayCleanupPending');
      });
      closing = attempt;
      // Only a settled failed attempt may retry this same server. A missing
      // callback or outstanding SDK read keeps its original attempt retained.
      void attempt.then(undefined, () => {
        if (closing === attempt) closing = undefined;
      });
      return attempt;
    },
  });
}
