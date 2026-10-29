// A provider-neutral HTTPS fixture for tests that drive the real credential
// resource boundary: a TLS server under its own test CA, a route table, a
// request log that never records credential values, and the faults a
// provider must classify (a reply that never arrives, a rate-limit reply).
// It replaces no owner. Authorization, grants, the credential journal and
// the Effect Ledger stay the product's; the fixture only answers HTTPS.
import {execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir} from 'node:os';
import {isAbsolute, join} from 'node:path';

function openssl(root, ...arguments_) {
  execFileSync('openssl', arguments_, {cwd: root, stdio: 'ignore'});
}

// A one-day test CA and a `localhost`/`127.0.0.1` resource certificate.
export async function fixtureCertificates(root) {
  openssl(root, 'genrsa', '-out', 'ca.key', '2048');
  openssl(root, 'req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
    '-subj', '/CN=ActQL Exchange Fixture CA', '-days', '1');
  openssl(root, 'genrsa', '-out', 'resource.key', '2048');
  openssl(root, 'req', '-new', '-key', 'resource.key', '-out', 'resource.csr',
    '-subj', '/CN=localhost');
  await writeFile(join(root, 'resource.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n');
  openssl(root, 'x509', '-req', '-in', 'resource.csr', '-CA', 'ca.crt',
    '-CAkey', 'ca.key', '-CAcreateserial', '-out', 'resource.crt',
    '-days', '1', '-extfile', 'resource.ext');
  const [ca, cert, key] = await Promise.all(['ca.crt', 'resource.crt',
    'resource.key'].map(name => readFile(join(root, name))));
  return Object.freeze({ca, cert, key, caPath: join(root, 'ca.crt')});
}

const credentialHeaders = new Set(['authorization', 'proxy-authorization',
  'cookie', 'x-cybozu-api-token', 'x-cybozu-authorization']);

function matches({method, pathname, bodyIncludes}, exchange) {
  return (method === undefined || method === exchange.method) &&
    (pathname === undefined || (pathname instanceof RegExp
      ? pathname.test(exchange.pathname) : pathname === exchange.pathname)) &&
    (bodyIncludes === undefined || exchange.body.includes(bodyIncludes));
}

function send(response, {status = 200, headers = {}, body = ''} = {}) {
  const bytes = Buffer.from(typeof body === 'string' ? body
    : JSON.stringify(body), 'utf8');
  response.writeHead(status, {'content-type': 'application/json', ...headers,
    'content-length': bytes.byteLength});
  response.end(bytes);
}

// Open the fixture for one test. `routes` are `{method?, pathname?, handle}`
// tried in order; `handle(exchange)` returns `{status?, headers?, body?}`
// or a Promise of that reply (an object body is sent as JSON). `faults` are consumed `times` (default
// once) before the routes: `{kind: 'lose-reply'}` destroys the connection
// after reading the request, `{kind: 'apply-then-lose-reply'}` lets the
// route apply the request and then destroys the connection instead of
// answering, `{kind: 'reply', reply}` answers with a fixed reply such as a
// 429 or 403 rate limit. A fault or route may also require `bodyIncludes`. `seen()` returns every request the
// server observed, with credential headers reduced to `authorized`.
// Scenario suites can select an absolute `scratchParent` and retain the
// original TLS material with `preserveScratch`, without changing process.env.
// `expectedAuthorization` requires one exact Authorization value before route
// admission; the distinct `expectedKintoneApiToken` selects one exact API-token
// header instead. These closed modes cannot be selected together. Token mode
// refuses every additional credential-bearing header before route admission.
// `maxRequestBytes` bounds actual received body bytes. Provider
// reply DATA may select `dropAfterApply: true` after its handler has returned.
// A resolved close acknowledges this listener's actual close callback.
export async function openHttpsExchangeFixture(t, {routes = [], faults = [],
  scratchParent = tmpdir(),
  preserveScratch = process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1',
  expectedAuthorization, expectedKintoneApiToken, maxRequestBytes} = {}) {
  if (typeof scratchParent !== 'string' || !isAbsolute(scratchParent)) {
    throw new TypeError('InvalidHttpsExchangeScratchParent');
  }
  if (typeof preserveScratch !== 'boolean') {
    throw new TypeError('InvalidHttpsExchangeScratchPreservation');
  }
  if (expectedAuthorization !== undefined && (typeof expectedAuthorization !== 'string' ||
      !expectedAuthorization || /[\r\n\0]/u.test(expectedAuthorization))) {
    throw new TypeError('InvalidHttpsExchangeAuthorization');
  }
  if (expectedKintoneApiToken !== undefined &&
      (expectedAuthorization !== undefined || typeof expectedKintoneApiToken !== 'string' ||
        !expectedKintoneApiToken || /[\r\n\0]/u.test(expectedKintoneApiToken))) {
    throw new TypeError('InvalidHttpsExchangeAuthorization');
  }
  if (maxRequestBytes !== undefined &&
      (!Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0)) {
    throw new TypeError('InvalidHttpsExchangeRequestLimit');
  }
  const root = await mkdtemp(join(scratchParent, 'actql-https-exchange-'));
  const {ca, cert, key, caPath} = await fixtureCertificates(root);
  const seen = [];
  const pending = faults.map(fault => ({...fault, times: fault.times ?? 1}));
  const server = createServer({cert, key}, (request, response) => {
    const url = new URL(request.url, 'https://fixture.invalid');
    const headers = {};
    for (const [name, value] of Object.entries(request.headers)) {
      if (!credentialHeaders.has(name)) headers[name] = value;
    }
    const authorizationCount = request.rawHeaders.filter((_, index) =>
      index % 2 === 0 && request.rawHeaders[index].toLowerCase() === 'authorization').length;
    const bearerAuthorized = expectedAuthorization === undefined
      ? ['authorization', 'x-cybozu-api-token', 'x-cybozu-authorization'].some(name =>
        typeof request.headers[name] === 'string')
      : authorizationCount === 1 && request.headers.authorization === expectedAuthorization;
    const authorized = expectedKintoneApiToken === undefined ? bearerAuthorized
      : request.rawHeaders.filter((name, index) => index % 2 === 0 &&
        credentialHeaders.has(name.toLowerCase())).length === 1 &&
        request.headers['x-cybozu-api-token'] === expectedKintoneApiToken;
    const exchangeWithBody = body => Object.freeze({
      method: request.method, path: request.url, pathname: url.pathname,
      query: Object.freeze(Object.fromEntries(url.searchParams)),
      headers: Object.freeze(headers), authorized, body,
    });
    if ((expectedAuthorization !== undefined || expectedKintoneApiToken !== undefined) && !authorized) {
      seen.push(Object.freeze({...exchangeWithBody(''), rejected: 'authorization'}));
      send(response, {status: 401});
      request.resume();
      return;
    }
    const chunks = [];
    let received = 0, rejected = false;
    request.on('data', chunk => {
      if (rejected) return;
      received += chunk.byteLength;
      if (maxRequestBytes !== undefined && received > maxRequestBytes) {
        rejected = true;
        chunks.length = 0;
        seen.push(Object.freeze({...exchangeWithBody(''), rejected: 'request_bytes'}));
        send(response, {status: 413});
        return;
      }
      chunks.push(chunk);
    });
    request.once('end', () => {
      if (rejected) return;
      const exchange = exchangeWithBody(Buffer.concat(chunks).toString('utf8'));
      seen.push(exchange);
      const fault = pending.find(entry => entry.times > 0 &&
        matches(entry, exchange));
      if (fault !== undefined) {
        fault.times--;
        if (fault.kind === 'lose-reply') {
          request.socket.destroy();
          return;
        }
        if (fault.kind === 'reply') {
          send(response, fault.reply);
          return;
        }
        if (fault.kind === 'apply-then-lose-reply') {
          const applied = routes.find(entry => matches(entry, exchange));
          Promise.resolve().then(() => applied?.handle(exchange)).then(
            () => request.socket.destroy(), () => request.socket.destroy());
          return;
        }
        throw new TypeError('InvalidHttpsExchangeFault');
      }
      const route = routes.find(entry => matches(entry, exchange));
      Promise.resolve().then(() => route === undefined
        ? {status: 404, body: ''} : route.handle(exchange)).then(
        reply => {
          if (reply?.dropAfterApply === true) request.socket.destroy();
          else if (!response.destroyed) send(response, reply);
        },
        () => request.socket.destroy());
    });
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const origin = `https://127.0.0.1:${server.address().port}`;
  let serverClosed = false;
  let closing;
  const close = () => {
    if (closing !== undefined) return closing;
    const attempt = (async () => {
      if (!serverClosed) {
        await new Promise((resolve, reject) => server.close(error => {
          if (error !== undefined) reject(error);
          else resolve();
        }));
        serverClosed = true;
      }
      if (!preserveScratch) await rm(root, {recursive: true, force: true});
    })();
    closing = attempt;
    // A cleanup retry keeps this original server and scratch directory. It
    // cannot reopen the listener or repeat any provider request.
    attempt.catch(() => { if (closing === attempt) closing = undefined; });
    return attempt;
  };
  t?.after(close);
  return Object.freeze({root, origin, ca, caPath, close,
    seen: () => Object.freeze([...seen]),
    remainingFaults: () => pending.reduce((sum, fault) => sum + fault.times, 0),
  });
}

// An RFC 8288 `Link` header value from `{rel: target}` relations.
export function linkHeader(relations) {
  return Object.entries(relations)
    .map(([rel, target]) => `<${target}>; rel="${rel}"`).join(', ');
}

// A paged listing route in the common REST shape: `size`/`page` query
// parameters (defaults `per_page`/`page`), a bounded page size, and `Link`
// relations `next`, `prev`, `first`, `last`; the last page carries no `next`.
export function pagedListing({items, origin, pathname, defaultSize = 30,
  maxSize = 100, sizeParameter = 'per_page', pageParameter = 'page',
  query = {}}) {
  const matchesFixed = exchange => Object.entries(query).every(([name,
    value]) => exchange.query[name] === value);
  return Object.freeze({method: 'GET', pathname, handle(exchange) {
    if (!matchesFixed(exchange)) return {status: 404, body: ''};
    const size = Math.min(maxSize,
      Number(exchange.query[sizeParameter] ?? defaultSize));
    const page = Number(exchange.query[pageParameter] ?? 1);
    if (!Number.isInteger(size) || size < 1 || !Number.isInteger(page) ||
        page < 1) {
      return {status: 422, body: {message: 'Validation Failed'}};
    }
    const last = Math.max(1, Math.ceil(items.length / size));
    const target = number => {
      const parameters = new URLSearchParams({...query,
        [sizeParameter]: String(size), [pageParameter]: String(number)});
      return `${origin}${pathname}?${parameters}`;
    };
    const relations = {};
    if (page < last) {
      relations.next = target(page + 1);
      relations.last = target(last);
    }
    if (page > 1) {
      relations.prev = target(page - 1);
      relations.first = target(1);
    }
    return {status: 200,
      headers: Object.keys(relations).length === 0 ? {}
        : {link: linkHeader(relations)},
      body: items.slice((page - 1) * size, page * size)};
  }});
}
