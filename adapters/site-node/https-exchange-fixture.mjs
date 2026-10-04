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
import {join} from 'node:path';

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
  'cookie']);

function matches({method, pathname}, exchange) {
  return (method === undefined || method === exchange.method) &&
    (pathname === undefined || (pathname instanceof RegExp
      ? pathname.test(exchange.pathname) : pathname === exchange.pathname));
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
// (an object body is sent as JSON). `faults` are consumed `times` (default
// once) before the routes: `{kind: 'lose-reply'}` destroys the connection
// after reading the request, `{kind: 'reply', reply}` answers with a fixed
// reply such as a 429 or 403 rate limit. `seen()` returns every request the
// server observed, with credential headers reduced to `authorized`.
export async function openHttpsExchangeFixture(t, {routes = [],
  faults = []} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-https-exchange-'));
  const {ca, cert, key, caPath} = await fixtureCertificates(root);
  const seen = [];
  const pending = faults.map(fault => ({...fault, times: fault.times ?? 1}));
  const server = createServer({cert, key}, (request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.once('end', () => {
      const url = new URL(request.url, 'https://fixture.invalid');
      const headers = {};
      for (const [name, value] of Object.entries(request.headers)) {
        if (!credentialHeaders.has(name)) headers[name] = value;
      }
      const exchange = Object.freeze({
        method: request.method, path: request.url, pathname: url.pathname,
        query: Object.freeze(Object.fromEntries(url.searchParams)),
        headers: Object.freeze(headers),
        authorized: typeof request.headers.authorization === 'string',
        body: Buffer.concat(chunks).toString('utf8'),
      });
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
        throw new TypeError('InvalidHttpsExchangeFault');
      }
      const route = routes.find(entry => matches(entry, exchange));
      send(response, route === undefined ? {status: 404, body: ''}
        : route.handle(exchange));
    });
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const origin = `https://127.0.0.1:${server.address().port}`;
  const close = async () => {
    await new Promise(resolve => server.close(resolve));
    await rm(root, {recursive: true, force: true});
  };
  t?.after(close);
  return Object.freeze({origin, ca, caPath, close,
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
