import assert from 'node:assert/strict';
import test from 'node:test';
import {exchangeLimits, observeResponseHeaders, ownHttpRequest,
  ownRequestHeaders, ownResponseHeaderNames, requestTarget} from
  './http-exchange.mjs';

test('request target encodes ordered query pairs onto an exact path', () => {
  assert.equal(requestTarget('/repos/o/r/issues'), '/repos/o/r/issues');
  assert.equal(requestTarget('/repos/o/r/issues', [['state', 'open'],
    ['per_page', '100'], ['labels', "a b,c'(d)*!"]]),
  '/repos/o/r/issues?state=open&per_page=100&labels=a%20b%2Cc%27%28d%29%2A%21');
  assert.equal(requestTarget('/query?q=SELECT%20Id', []), '/query?q=SELECT%20Id',
    'a provider-built locator keeps its own encoded query');
  for (const [path, query] of [['', []], ['/a?b=c', [['d', 'e']]], ['/a', [['', 'x']]],
    ['/a', [['k', 1]]], ['/a', [['k']]],
    ['/a', Array.from({length: exchangeLimits.maxQueryPairs + 1},
      (_, index) => [`k${index}`, 'v'])],
    ['/a', [['k', 'v'.repeat(exchangeLimits.maxQueryBytes)]]]]) {
    assert.throws(() => requestTarget(path, query),
      /InvalidHttpRequestTarget|InvalidHttpRequestQuery/);
  }
});

test('request headers are lowercase, non-secret, bounded and unique', () => {
  const owned = ownRequestHeaders([['accept', 'application/vnd.github+json'],
    ['x-github-api-version', '2026-03-10'], ['user-agent', 'actql-test/0.1']]);
  assert.deepEqual(owned, [['accept', 'application/vnd.github+json'],
    ['x-github-api-version', '2026-03-10'], ['user-agent', 'actql-test/0.1']]);
  assert.ok(Object.isFrozen(owned) && Object.isFrozen(owned[0]));
  assert.deepEqual(ownRequestHeaders(), []);
  for (const reserved of ['authorization', 'cookie', 'host', 'content-type',
    'content-length', 'transfer-encoding', 'x-forwarded-for']) {
    assert.throws(() => ownRequestHeaders([[reserved, 'x']]),
      {code: 'ReservedHttpRequestHeader'});
  }
  for (const headers of [[['Accept', 'x']], [['x y', 'x']], [['a', '']],
    [['a', 'vé']], [['a', 'v\r\nb: c']], [['a', 'v ']], [['a', ' v']],
    [['a', 'x'], ['a', 'y']], [['a']], [['a', 'x'.repeat(1025)]],
    Array.from({length: exchangeLimits.maxRequestHeaders + 1},
      (_, index) => [`h${index}`, 'v']), 'accept: x']) {
    assert.throws(() => ownRequestHeaders(headers),
      {code: 'InvalidHttpRequestHeaders'});
  }
});

test('an owned request fixes method, target, headers and body together', () => {
  const request = ownHttpRequest({method: 'POST', path: '/x',
    query: [['a', '1']], headers: [['user-agent', 'u']], body: '{}'});
  assert.deepEqual(request, {method: 'POST', target: '/x?a=1',
    headers: [['user-agent', 'u']], body: '{}'});
  assert.deepEqual(ownHttpRequest({method: 'GET', path: '/x'}),
    {method: 'GET', target: '/x', headers: []});
  assert.throws(() => ownHttpRequest({method: 'DELETE', path: '/x'}),
    {code: 'InvalidHttpRequestMethod'});
  assert.throws(() => ownHttpRequest({method: 'GET', path: '/x', body: '{}'}),
    {code: 'InvalidHttpRequestBody'});
  assert.throws(() => ownHttpRequest({method: 'POST', path: '/x',
    body: Buffer.from('{}')}), {code: 'InvalidHttpRequestBody'});
});

test('response header observation admits only declared names under caps', () => {
  const received = {link: '<https://api.example/next>; rel="next"',
    'x-ratelimit-remaining': '0', 'x-secret': 'never', 'set-cookie': ['a=b']};
  assert.deepEqual(observeResponseHeaders(received,
    ['link', 'x-ratelimit-remaining', 'retry-after']),
  [['link', '<https://api.example/next>; rel="next"'],
    ['x-ratelimit-remaining', '0']]);
  assert.deepEqual(observeResponseHeaders(received, []), []);
  assert.deepEqual(observeResponseHeaders(undefined, ['link']), []);
  assert.deepEqual(ownResponseHeaderNames(['link']), ['link']);
  assert.throws(() => observeResponseHeaders(received, ['set-cookie']),
    {code: 'InvalidHttpResponseHeaderNames'});
  assert.throws(() => observeResponseHeaders(received, ['Link']),
    {code: 'InvalidHttpResponseHeaderNames'});
  assert.throws(() => observeResponseHeaders(received, ['link', 'link']),
    {code: 'InvalidHttpResponseHeaderNames'});
  assert.throws(() => observeResponseHeaders({link: ['a', 'b']}, ['link']),
    {code: 'HttpHeaderObservationInvalid'});
  // Overflow refuses the observation; it never shortens it to "no next page".
  assert.throws(() => observeResponseHeaders(
    {link: 'x'.repeat(exchangeLimits.maxHeaderValueBytes + 1)}, ['link']),
  {code: 'HttpHeaderObservationExceeded'});
  const wide = Object.fromEntries(Array.from({length: 9}, (_, index) =>
    [`h${index}`, 'x'.repeat(1000)]));
  assert.throws(() => observeResponseHeaders(wide, Object.keys(wide)),
    {code: 'HttpHeaderObservationExceeded'});
});
