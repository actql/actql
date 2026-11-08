import assert from 'node:assert/strict';
import test from 'node:test';
import {checkHttpRequestMethodBody, exchangeLimits, observeResponseHeaders, ownHttpRequest, ownHttpByteRequest,
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
    'content-length', 'transfer-encoding', 'x-forwarded-for',
    'x-cybozu-api-token', 'x-cybozu-authorization']) {
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
  assert.throws(() => ownHttpRequest({method: 'TRACE', path: '/x'}),
    {code: 'InvalidHttpRequestMethod'});
  assert.throws(() => ownHttpRequest({method: 'GET', path: '/x', body: '{}'}),
    {code: 'InvalidHttpRequestBody'});
  assert.throws(() => ownHttpRequest({method: 'POST', path: '/x',
    body: Buffer.from('{}')}), {code: 'InvalidHttpRequestBody'});
});

test('shared method/body rules preserve legacy shapes and bound new methods', () => {
  for (const method of ['GET', 'DELETE']) {
    assert.deepEqual(ownHttpRequest({method, path: '/items/1'}),
      {method, target: '/items/1', headers: []});
    assert.doesNotThrow(() => checkHttpRequestMethodBody(method, undefined,
      {requireBody: true}));
    for (const body of ['', '{}', null, Buffer.from('{}')]) {
      assert.throws(() => ownHttpRequest({method, path: '/items/1', body}),
        {code: 'InvalidHttpRequestBody'});
    }
  }
  for (const method of ['POST', 'PATCH', 'PUT']) {
    for (const body of ['', '{}', '{"name":"café"}']) {
      assert.deepEqual(ownHttpRequest({method, path: '/items/1', body}),
        {method, target: '/items/1', headers: [], body});
      assert.doesNotThrow(() => checkHttpRequestMethodBody(method, body,
        {requireBody: true}));
    }
    for (const body of [null, 0, {}, Buffer.from('{}')]) {
      assert.throws(() => ownHttpRequest({method, path: '/items/1', body}),
        {code: 'InvalidHttpRequestBody'});
    }
    assert.throws(() => checkHttpRequestMethodBody(method, undefined,
      {requireBody: true}), {code: 'InvalidHttpRequestBody'});
  }
  for (const method of ['POST', 'PATCH']) {
    assert.deepEqual(ownHttpRequest({method, path: '/items/1'}),
      {method, target: '/items/1', headers: []},
      'the typed legacy envelope still allows an absent body');
  }
  assert.throws(() => ownHttpRequest({method: 'PUT', path: '/items/1'}),
    {code: 'InvalidHttpRequestBody'});
  for (const method of ['HEAD', 'OPTIONS', 'TRACE', 'put', 'delete', '', null]) {
    assert.throws(() => checkHttpRequestMethodBody(method, undefined),
      {code: 'InvalidHttpRequestMethod'});
  }
});

test('explicit byte request preserves non-UTF8, zero bytes and exactly the selected view', () => {
  const backing = new Uint8Array(64).fill(0x55);
  const view = backing.subarray(7, 13);
  view.set([0, 255, 192, 128, 13, 10]);
  const request = ownHttpByteRequest({method: 'POST', path: '/upload',
    query: [['name', 'é%2F.bin']], headers: [['accept', 'application/json']],
    bodyBytes: view, bodyMediaType: 'multipart/related; boundary="original"', maxBodyBytes: 6});
  assert.deepEqual([...request.bodyBytes], [0, 255, 192, 128, 13, 10]);
  assert.equal(request.bodyBytes.buffer.byteLength, 6);
  assert.notEqual(request.bodyBytes.buffer, backing.buffer);
  assert.equal(request.target, '/upload?name=e%CC%81%252F.bin');
  assert.equal(request.bodyMediaType, 'multipart/related; boundary="original"');
  assert.equal(request.body, undefined);
  assert.ok(Object.isFrozen(request));
  backing.fill(0x33);
  assert.deepEqual([...request.bodyBytes], [0, 255, 192, 128, 13, 10]);
  for (const method of ['POST', 'PATCH', 'PUT']) {
    assert.equal(ownHttpByteRequest({method, path: '/empty', bodyBytes: new Uint8Array(),
      bodyMediaType: 'application/octet-stream', maxBodyBytes: 0}).bodyBytes.byteLength, 0);
  }
});

test('binary shape is opt-in and rejects unsafe media, shared backing and missing bounds', () => {
  const original = {method: 'POST', path: '/upload', bodyBytes: new Uint8Array([1, 2]),
    bodyMediaType: 'application/octet-stream', maxBodyBytes: 2};
  for (const change of [{body: ''}, {bodyBytes: '12'}, {bodyBytes: new Uint16Array(2)},
    {bodyBytes: new Uint8Array(new SharedArrayBuffer(2))}, {bodyMediaType: undefined},
    {bodyMediaType: 'application/octet-stream\r\nx-secret: injected'},
    {bodyMediaType: 'application/é'}, {bodyMediaType: 'a'.repeat(1025)},
    {maxBodyBytes: undefined}, {maxBodyBytes: -1}, {maxBodyBytes: 1},
    {maxBodyBytes: 1.5}, {maxBodyBytes: Infinity}, {maxBodyBytes: 2 ** 53}]) {
    assert.throws(() => ownHttpByteRequest({...original, ...change}),
      {code: 'InvalidHttpRequestBody'});
  }
  for (const method of ['GET', 'DELETE']) {
    assert.throws(() => ownHttpByteRequest({...original, method}), {code: 'InvalidHttpRequestBody'});
  }
  assert.throws(() => ownHttpByteRequest({...original, method: 'TRACE'}),
    {code: 'InvalidHttpRequestMethod'});
  assert.throws(() => ownHttpByteRequest({...original, headers: [['content-type', 'text/plain']]}),
    {code: 'ReservedHttpRequestHeader'});
  assert.throws(() => ownHttpRequest({method: 'POST', path: '/upload', body: original.bodyBytes}),
    {code: 'InvalidHttpRequestBody'}, 'legacy String admission has not changed');
});

test('byte length/backing properties cannot disguise an over-limit or shared source view', () => {
  const shape = {method: 'POST', path: '/upload',
    bodyMediaType: 'application/octet-stream', maxBodyBytes: 1};
  const over = new Uint8Array([1, 2]);
  Object.defineProperty(over, 'byteLength', {value: 1});
  assert.throws(() => ownHttpByteRequest({...shape, bodyBytes: over}),
    {code: 'InvalidHttpRequestBody'});
  const shared = new Uint8Array(new SharedArrayBuffer(1));
  Object.defineProperty(shared, 'buffer', {value: new ArrayBuffer(1)});
  assert.throws(() => ownHttpByteRequest({...shape, bodyBytes: shared}),
    {code: 'InvalidHttpRequestBody'});
  const detached = new Uint8Array(1);
  structuredClone(detached.buffer, {transfer: [detached.buffer]});
  assert.throws(() => ownHttpByteRequest({...shape, bodyBytes: detached}),
    {code: 'InvalidHttpRequestBody'});
  const stable = new Uint8Array(new ArrayBuffer(4, {maxByteLength: 8}));
  stable.set([0, 255, 13, 10]);
  assert.deepEqual([...ownHttpByteRequest({...shape, bodyBytes: stable,
    maxBodyBytes: 4}).bodyBytes], [0, 255, 13, 10]);
});

test('resizable shrink after metadata admission cannot expose uninitialized body bytes', () => {
  const backing = new ArrayBuffer(4, {maxByteLength: 8});
  const source = new Uint8Array(backing);
  source.set([1, 2, 3, 4]);
  const query = ['name', 'original'];
  Object.defineProperty(query, 1, {get() { backing.resize(2); return 'original'; }});
  assert.throws(() => ownHttpByteRequest({method: 'POST', path: '/upload', query: [query],
    bodyBytes: source, bodyMediaType: 'application/octet-stream', maxBodyBytes: 4}),
  {code: 'InvalidHttpRequestBody'});
});

test('resizable growth after metadata admission refuses rather than changing the snapshot extent', () => {
  const backing = new ArrayBuffer(4, {maxByteLength: 8});
  const source = new Uint8Array(backing);
  const query = ['name', 'original'];
  Object.defineProperty(query, 1, {get() { backing.resize(8); return 'original'; }});
  assert.throws(() => ownHttpByteRequest({method: 'POST', path: '/upload', query: [query],
    bodyBytes: source, bodyMediaType: 'application/octet-stream', maxBodyBytes: 4}),
  {code: 'InvalidHttpRequestBody'});
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
  // A reserved name is refused as a declaration, before any exchange.
  for (const reserved of ['set-cookie', 'authorization', 'cookie', 'host']) {
    assert.throws(() => ownResponseHeaderNames([reserved]),
      {code: 'InvalidHttpResponseHeaderNames'});
  }
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


test('funded query construction keeps the exact encoded demand and all default refusals', () => {
  const query = [['properties', 'x'.repeat(6000)], ['after', "é/😀!'()*"]];
  const expected = '/objects?properties=' + 'x'.repeat(6000) +
    '&after=%C3%A9%2F%F0%9F%98%80%21%27%28%29%2A';
  const bound = expected.length - '/objects?'.length;
  assert.throws(() => requestTarget('/objects', query), {code:'InvalidHttpRequestQuery'});
  assert.equal(requestTarget('/objects', query, {maxQueryBytes:bound}), expected);
  assert.throws(() => requestTarget('/objects', query, {maxQueryBytes:bound-1}), {code:'InvalidHttpRequestQuery'});
  for (const maxQueryBytes of [0,-1,Infinity,2147483648,1.5]) {
    assert.throws(() => requestTarget('/objects', [], {maxQueryBytes}), {code:'InvalidHttpRequestQuery'});
  }
  assert.throws(() => requestTarget('/objects', Array.from({length:33},()=>['a','b']),
    {maxQueryBytes:10000}), {code:'InvalidHttpRequestQuery'});
  assert.throws(() => ownHttpRequest({method:'GET',path:'/objects',query,
    maxQueryBytes:bound}), {code:'InvalidHttpRequestQuery'}, 'provider DATA cannot select the owner bound');
  assert.throws(() => ownHttpRequest({method:'GET',path:'/objects',query,
    headers:[['authorization','x']]}, {maxQueryBytes:bound}), {code:'ReservedHttpRequestHeader'});
  assert.throws(() => requestTarget('/query?original=x', [['a','b']],
    {maxQueryBytes:bound}), {code:'InvalidHttpRequestTarget'});
  assert.throws(() => requestTarget('/path-too-large', [], {maxQueryBytes:2}),
    {code:'InvalidHttpRequestTarget'});
});

test('actual HubSpot managed caller preserves all selected properties through funded HTTP construction', async () => {
  const {prepareHubSpotManagedSequence} = await import('../connectors/hubspot/site/hubspot-managed-sequence.mjs');
  // Explicit provider decoder/current/response ports; this executes actual
  // protocol request construction, not a physical send or numerical admission.
  const names = Array.from({length:245},(_,index)=>'field_'+String(index).padStart(3,'0')+'_long_property');
  const observed = [], originalCatalog = {};
  const moon = {
    hubspotRecheckAccountIdentityJson(){},hubspotProjectProperties(){return {$tag:1,_0:originalCatalog};},
    hubspotRecheckPropertyCatalog(){return {$tag:1};},hubspotPropertyCatalogObjectType(){return 'companies';},
    hubspotProjectObjectPage(){return {$tag:1,_0:{}};},hubspotObjectPageRowsWire(){return {$tag:1,_0:'[]'};},
    hubspotObjectPageMetadataJson(){return '{"rowCount":0}';},
  };
  const sequence = prepareHubSpotManagedSequence({moon,originalPortalId:'7',originalCatalog,
    objectType:'companies',properties:names,limits:{maxColumns:245,maxNameUnits:10000,maxResponseBytes:100,
      maxRequests:4,maxPages:1,maxRows:2,perPage:2},authorizeMetadata:async()=>({}),responseCapacity(){}});
  await sequence.read({signal:new AbortController().signal,
    async readChild(child){const prepared=child.prepare();
      const request=ownHttpRequest(prepared.request,{maxQueryBytes:10000});observed.push(request.target);
      if(prepared.request.query.length){
        assert.throws(()=>ownHttpRequest(prepared.request),{code:'InvalidHttpRequestQuery'});
        const params=new URL('https://example.invalid'+request.target).searchParams;
        assert.deepEqual(params.get('properties').split(','),names);
        assert.equal(params.get('limit'),'2');assert.equal(params.get('archived'),'false');
        return prepared.project({accepted:true,statusCode:200,body:Buffer.from('{}')});
      }
      return undefined;
    },async consumeObservation(){},async consumePage(rows){assert.deepEqual(rows,[]);},
  });
  assert.equal(observed.length,4);assert(observed[2].length>4096);assert.equal(sequence.retire(),true);
});
