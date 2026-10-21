import assert from 'node:assert/strict';
import test from 'node:test';
import {createExplorerGateway} from './gateway.mjs';

const origin = 'http://127.0.0.1:43210';
const navigation = {'Sec-Fetch-Site': 'cross-site', 'Sec-Fetch-Mode': 'navigate',
  'Sec-Fetch-Dest': 'document', 'Sec-Fetch-User': '?1'};

function fixture(t) {
  const html = '<!doctype html><title>Explorer</title>';
  const gateway = createExplorerGateway({origin,
    client: {attach() {assert.fail('static navigation must not call the Client');}},
    assets: new Map([
      ['/index.html', {body: Buffer.from(html), contentType: 'text/html; charset=utf-8'}],
      ['/assets/app.js', {body: Buffer.from('export {};'), contentType: 'text/javascript; charset=utf-8'}],
    ]),
  });
  t.after(() => gateway.close());
  return {html, send(path = '/', headers = {}, method = 'GET') {
    return gateway.fetch(new Request(origin + path, {method,
      headers: {Host: '127.0.0.1:43210', ...headers},
      ...(method === 'POST' ? {body: '{}'} : {}),
    }));
  }};
}

test('public HTML accepts activated top-level browser navigation from another site', async t => {
  const h = fixture(t);
  for (const site of ['cross-site', 'same-site']) for (const path of ['/', '/index.html']) {
    const response = await h.send(path, {...navigation, 'Sec-Fetch-Site': site});
    assert.equal(response.status, 200, `${site} ${path}`);
    assert.equal(await response.text(), h.html);
  }
});

test('document navigation cannot bypass API Origin, Host, framing or asset checks', async t => {
  const h = fixture(t);
  for (const [path, headers, method] of [
    ['/', {...navigation, 'Sec-Fetch-User': '?0'}, 'GET'],
    ['/', {...navigation, 'Sec-Fetch-Dest': 'iframe'}, 'GET'],
    ['/', {...navigation, 'Sec-Fetch-Mode': 'cors'}, 'GET'],
    ['/', {...navigation, Origin: 'https://foreign.example'}, 'GET'],
    ['/', {...navigation, Origin: 'null'}, 'GET'],
    ['/assets/app.js', navigation, 'GET'],
    ['/api/session', navigation, 'GET'],
    ['/api/session', navigation, 'POST'],
    ['/api/session', {...navigation, Origin: origin}, 'POST'],
  ]) {
    const response = await h.send(path, headers, method);
    assert.equal(response.status, 403, `${method} ${path}`);
    assert.deepEqual(await response.json(), {error: 'ExplorerOriginRefused'});
  }
  const badHost = await h.send('/', {...navigation, Host: 'foreign.example'});
  assert.equal(badHost.status, 403);
  assert.deepEqual(await badHost.json(), {error: 'ExplorerHostRefused'});
  const forwarded = await h.send('/', {...navigation, Forwarded: 'host=foreign.example'});
  assert.equal(forwarded.status, 403);
  assert.deepEqual(await forwarded.json(), {error: 'ExplorerHostRefused'});
  assert.equal((await h.send('/?bootstrap=untrusted', navigation)).status, 400);
});

test('ordinary static reads keep no-store CSP and same-origin behavior', async t => {
  const h = fixture(t);
  for (const headers of [{}, {'Sec-Fetch-Site': 'none'}, {'Sec-Fetch-Site': 'same-origin'}]) {
    const response = await h.send('/', headers);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
    assert.match(response.headers.get('content-security-policy'), /frame-ancestors 'none'/u);
    assert.match(response.headers.get('content-security-policy'), /script-src 'self'/u);
  }
});
