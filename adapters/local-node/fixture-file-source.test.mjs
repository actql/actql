import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {createFixtureFileSupplier} from './fixture-file-source.mjs';

// Callback-order tests only. Core document admission and real Store-backed
// Content issuance have their own actual-runtime tests; these ports claim
// neither a real ResourceRef nor a physical cleanup acknowledgement.
const rowDigest = row => 'sha256:' + createHash('sha256').update(JSON.stringify(row)).digest('hex');
const fixtureVersion = row => 'sha256:' + createHash('sha256').update(JSON.stringify({
  declared_version: row.revision, row_version_cid: rowDigest(row),
})).digest('hex');

function fixture({rows, maxContentBytes = 1024, failAdmit = false, scope} = {}) {
  rows ??= [
    {id: 'one', title: 'Repeated name', revision: 'r1', mime: 'text/plain', body: 'e\u0301\n"line"\n'},
    {id: 'two', title: 'Repeated name', revision: 'r2', mime: 'text/plain', body: ''},
  ];
  const declaration = {}, originalRead = {};
  const encode = () => Buffer.from(JSON.stringify({
    documents: {key: ['id'], rows}, unrelated: {literal: 9007199254740991},
  }));
  let raw = encode();
  const state = {events: [], issued: new Map(), pending: undefined, page: undefined,
    captures: [], current: true, bytesCalls: 0, reads: 0, admissions: 0};
  const documents = new Map(), cells = new Map();
  const resourceFor = identity => Object.freeze({$actql_ref: 'resource', identity,
    ...(scope === undefined ? {} : {scope})});
  const physical = {declaration, resource: 'documents', itemsPath: ['documents', 'rows'],
    keyPath: ['documents', 'key'], primaryIdentity: 'id', writableFields: []};
  const fields = {identity: 'id', name: 'title', version: 'revision', mediaType: 'mime', contentUtf8: 'body'};
  const limits = {maxBytes: 4096, maxNodes: 128, maxDepth: 8, maxRows: 4,
    maxWork: 16384, maxPageBytes: 4096, maxContentBytes};
  const moon = {
    clientProgramRelationObserveTarget(d, selected, identity) {
      if (!documents.has(d) || selected !== declaration) return {$tag: 0, _0: 'ForeignSource'};
      const value = documents.get(d).find(row => row.id === identity);
      if (value === undefined) return {$tag: 0, _0: 'InvalidPage'};
      const row = Object.freeze({}); cells.set(row, value);
      return {$tag: 1, _0: row};
    },
    clientProgramRelationTargetRowCount(d) {return documents.get(d)?.length;},
    clientProgramRelationTargetRowIdentity(d, index) {return documents.get(d)?.[index]?.id;},
    clientProgramRelationTargetText(row, field) {return cells.get(row)?.[field];},
    clientProgramRelationTargetVersion(row) {return cells.has(row) ? rowDigest(cells.get(row)) : undefined;},
    clientProgramRelationTargetTextBytes(row, field) {
      state.bytesCalls++; state.events.push('utf8');
      const text = cells.get(row)?.[field];
      return text === undefined ? undefined : Buffer.from(text, 'utf8');
    },
  };
  const setup = {moon, physical, fields, limits,
    async readOriginalBytes(options) {
      assert.strictEqual(options.rowRun.originalRead ?? options.rowRun.originalKeyedRead, originalRead);
      state.reads++; state.events.push('read');
      return raw;
    },
    projectOriginalDocument(bytes, options) {
      assert.strictEqual(bytes, raw);
      assert.strictEqual(options.rowRun.originalRead ?? options.rowRun.originalKeyedRead, originalRead);
      assert.strictEqual(state.pending?.bytes, raw, 'the original charge precedes parent projection');
      state.admissions++; state.events.push('project');
      if (failAdmit) throw Object.assign(new Error('MoonBitHostFailure', {cause: 'InvalidPage'}),
        {code: 'MoonBitHostFailure'});
      const document = Object.freeze({});
      documents.set(document, structuredClone(rows));
      return document;
    },
    issueResource(identity) {
      assert(rows.some(row => row.id === identity));
      const resource = resourceFor(identity);
      state.issued.set(JSON.stringify(resource), identity);
      state.events.push('issue:' + identity);
      return resource;
    },
    resolveResource(resource) {state.events.push('resolve'); return state.issued.get(JSON.stringify(resource));},
    assertCurrent() {if (!state.current) throw new Error('OriginalSourceNotCurrent');},
  };
  const supplier = createFixtureFileSupplier(setup);
  const verifyRead = async () => {state.events.push('verify');};
  const chargePage = bytes => {
    assert.strictEqual(bytes, raw, 'only the actual document is received transport DATA');
    assert.equal(state.pending, undefined);
    state.events.push('charge');
    state.pending = {bytes};
    return state.pending;
  };
  const listingOptions = {rowRun: {originalRead}, verifyRead, chargePage,
    listing: {
      async beginRequest(token) {assert.equal(token, undefined); state.events.push('begin-list');},
      async consumePage(body, {charge}) {
        assert.strictEqual(charge, state.pending); state.pending = undefined;
        state.page = JSON.parse(body); state.events.push('list-page');
      },
    }};
  const contentOptions = (identity = 'one', version = state.page?.items.find(item => item.resource.identity === identity)?.version ?? 'unlisted') => ({
    rowRun: {originalKeyedRead: originalRead}, verifyRead, chargePage,
    requestWire: JSON.stringify({resource: resourceFor(identity), version}),
    async beginRequest(bytes) {
      assert.deepEqual(JSON.parse(bytes), JSON.parse(this.requestWire)); state.events.push('begin-content');
    },
    consumeObservation(charge) {
      assert.strictEqual(charge, state.pending); state.pending = undefined; state.events.push('consume-raw');
    },
    async captureContent(observed) {
      assert.equal(state.pending, undefined); state.captures.push(observed); state.events.push('capture');
      return Object.freeze({$fixtureContent: String(state.captures.length)});
    },
    async consumePage(value) {state.contentRows = value; state.events.push('content-page');},
  });
  // Installed callbacks are receiver-independent. Avoid making the fixture's
  // request check depend on `this`, which the real RowRun callbacks do not use.
  const content = (...args) => {
    const options = contentOptions(...args), wire = options.requestWire;
    options.beginRequest = async bytes => {
      assert.deepEqual(JSON.parse(bytes), JSON.parse(wire)); state.events.push('begin-content');
    };
    return options;
  };
  return {supplier, setup, state, get raw() {return raw;}, get rows() {return rows;}, listingOptions, content,
    replaceRows(next) {rows = structuredClone(next); raw = encode();}};
}

test('fixture files use original charged document and Source-issued IDs, not nonunique names or invented paths', async () => {
  const f = fixture();
  await f.supplier.readListing(f.listingOptions);
  assert.equal(f.state.reads, 1); assert.equal(f.state.admissions, 1); assert.equal(f.state.bytesCalls, 0);
  assert.equal(f.state.pending, undefined);
  assert.deepEqual(f.state.page, {items: f.rows.map(row => ({
    resource: {$actql_ref: 'resource', identity: row.id}, version: fixtureVersion(row),
    name: row.title, path: null, media_type: row.mime, size_bytes: null, modified_at: null,
  })), request_token: null, next_token: null});
  assert(f.state.events.indexOf('begin-list') < f.state.events.indexOf('read'));
  assert(f.state.events.indexOf('charge') < f.state.events.indexOf('project'));
});

test('fixture content consumes raw ticket before exact UTF8 Store capture and preserves the request correlation', async () => {
  const f = fixture(); await f.supplier.readListing(f.listingOptions);
  f.state.events.length = 0;
  await f.supplier.readContent(f.content());
  const bytes = Buffer.from(f.rows[0].body);
  assert.deepEqual(f.state.captures, [{bytes, mediaType: 'text/plain',
    contentCid: 'sha256:' + createHash('sha256').update(bytes).digest('hex')}]);
  assert.deepEqual(f.state.contentRows, [{resource: {$actql_ref: 'resource', identity: 'one'},
    version: fixtureVersion(f.rows[0]), content: {$fixtureContent: '1'}}]);
  for (const [first, second] of [['resolve', 'begin-content'], ['begin-content', 'read'],
    ['charge', 'project'], ['project', 'consume-raw'], ['consume-raw', 'utf8'], ['utf8', 'capture'], ['capture', 'content-page']]) {
    assert(f.state.events.indexOf(first) < f.state.events.indexOf(second), first + ' before ' + second);
  }
});

test('fixture empty UTF8 content is real zero-byte data, and declared metadata columns remain exact', async () => {
  const f = fixture({maxContentBytes: 0}); await f.supplier.readListing(f.listingOptions);
  const options = f.content('two'); options.columns = ['resource', 'version', 'content', 'name', 'media_type', 'path'];
  await f.supplier.readContent(options);
  assert.equal(f.state.captures[0].bytes.byteLength, 0);
  assert.equal(f.state.captures[0].contentCid, 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  assert.deepEqual(f.state.contentRows[0], {resource: {$actql_ref: 'resource', identity: 'two'},
    version: fixtureVersion(f.rows[1]), content: {$fixtureContent: '1'}, name: 'Repeated name', media_type: 'text/plain', path: null});
});

test('fixture foreign resource refuses before physical request and stale version refuses before UTF8/capture', async () => {
  const f = fixture();
  await assert.rejects(f.supplier.readContent(f.content()), {code: 'FixtureFileResourceUnavailable'});
  assert.equal(f.state.reads, 0); assert.equal(f.state.events.includes('begin-content'), false);
  await f.supplier.readListing(f.listingOptions);
  await assert.rejects(f.supplier.readContent(f.content('one', 'stale')), {code: 'FixtureFileVersionMismatch'});
  assert.equal(f.state.pending, undefined); assert.equal(f.state.bytesCalls, 0); assert.equal(f.state.captures.length, 0);
});

test('fixture replacement with unchanged declared version rejects the old exposed version before capture', async () => {
  const f = fixture(); await f.supplier.readListing(f.listingOptions);
  const prior = f.content(), oldVersion = JSON.parse(prior.requestWire).version;
  const changed = f.rows.map(row => row.id === 'one' ? {...row, body: 'Replacement bytes\n'} : row);
  f.replaceRows(changed);
  assert.equal(f.rows[0].revision, 'r1', 'the declared sample version stays untouched');
  await assert.rejects(f.supplier.readContent(prior), {code: 'FixtureFileVersionMismatch'});
  assert.equal(f.state.bytesCalls, 0); assert.equal(f.state.captures.length, 0);
  assert.equal(f.state.pending, undefined);
  await f.supplier.readListing(f.listingOptions);
  assert.notEqual(f.state.page.items[0].version, oldVersion);
  assert.equal(f.state.page.items[0].version, fixtureVersion(changed[0]));
  await f.supplier.readContent(f.content());
  assert.deepEqual(f.state.captures[0].bytes, Buffer.from('Replacement bytes\n'));
});

test('fixture equal rows in a different Source inventory do not authorize a foreign ResourceRef', async () => {
  const first = fixture({scope: 'source-a'}), second = fixture({scope: 'source-b'});
  await first.supplier.readListing(first.listingOptions);
  await second.supplier.readListing(second.listingOptions);
  assert.equal(first.state.page.items[0].version, second.state.page.items[0].version,
    'equal physical data is not Source authority');
  const foreign = {...second.content(), requestWire: first.content().requestWire};
  second.state.events.length = 0;
  await assert.rejects(second.supplier.readContent(foreign), {code: 'FixtureFileResourceUnavailable'});
  assert.equal(second.state.reads, 1); assert.equal(second.state.captures.length, 0);
  assert.equal(second.state.events.includes('begin-content'), false);
});

test('fixture provider version refuses an unavailable original row digest before reference issuance', async () => {
  const f = fixture();
  f.setup.moon.clientProgramRelationTargetVersion = () => undefined;
  const supplier = createFixtureFileSupplier(f.setup);
  await assert.rejects(supplier.readListing(f.listingOptions), {code: 'FixtureFileVersionUnavailable'});
  assert.equal(f.state.issued.size, 0); assert.equal(f.state.page, undefined);
});

test('fixture content bound rejects before UTF8 allocation, even when the original document fits', async () => {
  const f = fixture({maxContentBytes: 1}); await f.supplier.readListing(f.listingOptions);
  await assert.rejects(f.supplier.readContent(f.content()), {code: 'FixtureFileContentBytesUnavailable'});
  assert.equal(f.state.bytesCalls, 0); assert.equal(f.state.captures.length, 0);
});

test('fixture admission refusal retains the original pending ticket and issues no references', async () => {
  const f = fixture({failAdmit: true});
  await assert.rejects(f.supplier.readListing(f.listingOptions), {code: 'MoonBitHostFailure'});
  assert.strictEqual(f.state.pending.bytes, f.raw);
  assert.equal(f.state.issued.size, 0); assert.equal(f.state.page, undefined);
});

test('fixture oversized original is charged but rejected before the parent projection', async () => {
  const f = fixture();
  const supplier = createFixtureFileSupplier({...f.setup,
    limits: {...f.setup.limits, maxBytes: 1, maxContentBytes: 0}});
  await assert.rejects(supplier.readListing(f.listingOptions), {code: 'FixtureFileOriginalBytesLimit'});
  assert.strictEqual(f.state.pending.bytes, f.raw);
  assert.equal(f.state.admissions, 0); assert.equal(f.state.issued.size, 0);
});

test('fixture post-read current refusal charges received bytes but never admits or captures', async () => {
  const f = fixture();
  const original = f.setup.readOriginalBytes;
  const supplier = createFixtureFileSupplier({...f.setup, async readOriginalBytes(options) {
    const bytes = await original(options); f.state.current = false; return bytes;
  }});
  await assert.rejects(supplier.readListing(f.listingOptions), /OriginalSourceNotCurrent/u);
  assert.strictEqual(f.state.pending.bytes, f.raw);
  assert.equal(f.state.admissions, 0); assert.equal(f.state.issued.size, 0);
});

test('fixture pre-abort and malformed keyed request never enter physical I/O', async () => {
  const f = fixture(); const controller = new AbortController(); controller.abort(new Error('Stopped'));
  await assert.rejects(f.supplier.readListing({...f.listingOptions, signal: controller.signal}), /Stopped/u);
  for (const requestWire of ['null', '{}', '{', JSON.stringify({resource: {}, version: 'r1', extra: true})]) {
    await assert.rejects(f.supplier.readContent({...f.content(), requestWire}), {code: 'InvalidFixtureFileContentRequest'});
  }
  assert.equal(f.state.reads, 0);
});

test('fixture supplier snapshots roles, limits and original Core/projection methods before awaits', async () => {
  const f = fixture();
  f.setup.fields.name = 'foreign'; f.setup.limits.maxRows = 0;
  f.setup.moon.clientProgramRelationObserveTarget = () => assert.fail('No replaced Core method');
  f.setup.projectOriginalDocument = () => assert.fail('No replaced parent projection');
  await f.supplier.readListing(f.listingOptions);
  assert.equal(f.state.page.items.length, 2); assert.equal(f.state.page.items[0].name, 'Repeated name');
});

test('fixture supplier requires declared physical identity/key path and valid bounded configuration', () => {
  const f = fixture();
  for (const physical of [{...f.setup.physical, keyPath: undefined}, {...f.setup.physical, primaryIdentity: 'name'}]) {
    assert.throws(() => createFixtureFileSupplier({...f.setup, physical}), {code: 'InvalidFixtureFileSupplier'});
  }
  assert.throws(() => createFixtureFileSupplier({...f.setup, limits: {...f.setup.limits, maxContentBytes: 4097}}),
    {code: 'InvalidFixtureFileLimits'});
  assert.throws(() => createFixtureFileSupplier({...f.setup, projectOriginalDocument: undefined}),
    {code: 'InvalidFixtureFileSupplier'});
});

test('fixture foreign parent projection cannot issue a Resource or capture Content', async () => {
  const f = fixture();
  const supplier = createFixtureFileSupplier({...f.setup, projectOriginalDocument() {return Object.freeze({});}});
  await assert.rejects(supplier.readListing(f.listingOptions), {code: 'FixtureFileRowsUnavailable'});
  assert.equal(f.state.issued.size, 0); assert.strictEqual(f.state.pending.bytes, f.raw);
  const keyed = fixture(); await keyed.supplier.readListing(keyed.listingOptions);
  const foreign = createFixtureFileSupplier({...keyed.setup, projectOriginalDocument() {return Object.freeze({});}});
  await assert.rejects(foreign.readContent(keyed.content()), {code: 'MoonBitHostFailure'});
  assert.equal(keyed.state.bytesCalls, 0); assert.equal(keyed.state.captures.length, 0);
});

test('fixture physical failure keeps the same parent cleanup carrier without retry or close acknowledgement', async () => {
  const f = fixture(); let retries = 0;
  const failure = Object.assign(new Error('OriginalFileClosePending'), {
    cleanupPending: true, cleanupHandle: Object.freeze({retry() {retries++;}, status() {return {pending: true};}}),
  });
  const supplier = createFixtureFileSupplier({...f.setup, async readOriginalBytes() {throw failure;}});
  await assert.rejects(supplier.readListing(f.listingOptions), error => error === failure);
  assert.equal(retries, 0); assert.equal(supplier.close, undefined);
  assert.equal(f.state.admissions, 0); assert.equal(f.state.issued.size, 0);
});


test('fixture raw retention awaits the same charged bytes before listing or content decode', async () => {
  for (const kind of ['listing', 'content']) {
    const f = fixture();
    if (kind === 'content') await f.supplier.readListing(f.listingOptions);
    f.state.events.length = 0;
    const before = f.state.admissions, reads = f.state.reads;
    const gate = Promise.withResolvers();
    const options = kind === 'listing' ? f.listingOptions : f.content();
    options.retainRawResponse = async bytes => {
      assert.strictEqual(bytes, f.raw);
      assert.strictEqual(f.state.pending.bytes, bytes);
      f.state.events.push('retain');
      await gate.promise;
      f.state.events.push('retained');
    };
    const pending = kind === 'listing' ? f.supplier.readListing(options) : f.supplier.readContent(options);
    try {
      await new Promise(setImmediate);
      assert.equal(f.state.events.at(-1), 'retain');
      assert.equal(f.state.admissions, before);
      assert.equal(f.state.reads, reads + 1);
      assert.equal(f.state.captures.length, 0);
    } finally {gate.resolve();}
    await pending;
    assert.deepEqual(f.state.events.slice(f.state.events.indexOf('read'),
      f.state.events.indexOf('project') + 1),
    ['read', 'charge', 'verify', 'retain', 'retained', 'verify', 'project']);
    assert.equal(f.state.admissions, before + 1);
    assert.equal(f.state.reads, reads + 1);
  }
});

test('fixture raw retention snapshots the own callback before the first await', async () => {
  for (const kind of ['listing', 'content']) {
    const f = fixture();
    if (kind === 'content') await f.supplier.readListing(f.listingOptions);
    const options = kind === 'listing' ? f.listingOptions : f.content();
    let retained = 0;
    options.retainRawResponse = bytes => {assert.strictEqual(bytes, f.raw); retained++;};
    const verify = options.verifyRead;
    options.verifyRead = async () => {
      options.retainRawResponse = () => assert.fail('replacement callback must not be selected');
      await verify();
    };
    await (kind === 'listing' ? f.supplier.readListing(options) : f.supplier.readContent(options));
    assert.equal(retained, 1);
  }
});

test('fixture raw retention rechecks cancellation and original current after the pending await', async () => {
  for (const kind of ['listing', 'content']) for (const stop of ['signal', 'current', 'verify']) {
    const f = fixture();
    if (kind === 'content') await f.supplier.readListing(f.listingOptions);
    const before = f.state.admissions, reads = f.state.reads;
    const options = kind === 'listing' ? f.listingOptions : f.content();
    const gate = Promise.withResolvers(), controller = new AbortController();
    const stopped = new Error('OriginalReadStopped');
    let retained = false, settled = false, finished = false;
    options.signal = controller.signal;
    const verify = options.verifyRead;
    options.verifyRead = async () => {if (finished && stop === 'verify') throw stopped; await verify();};
    options.retainRawResponse = async bytes => {
      assert.strictEqual(bytes, f.raw); retained = true;
      await gate.promise; finished = true;
    };
    const result = (kind === 'listing' ? f.supplier.readListing(options) : f.supplier.readContent(options))
      .then(() => ({ok: true}), reason => ({ok: false, reason})).finally(() => {settled = true;});
    try {
      await new Promise(setImmediate);
      assert.equal(retained, true);
      if (stop === 'signal') controller.abort(stopped);
      if (stop === 'current') f.state.current = false;
      await new Promise(setImmediate);
      assert.equal(settled, false, 'the original retention must finish before cancellation settles');
      assert.equal(f.state.admissions, before);
    } finally {gate.resolve();}
    const outcome = await result;
    assert.equal(outcome.ok, false);
    if (stop === 'current') assert.equal(outcome.reason.message, 'OriginalSourceNotCurrent');
    else assert.strictEqual(outcome.reason, stopped);
    assert.equal(f.state.admissions, before);
    assert.equal(f.state.reads, reads + 1);
    assert.strictEqual(f.state.pending.bytes, f.raw);
    assert.equal(f.state.captures.length, 0);
  }
});

test('fixture raw retention preserves synchronous and rejected reasons including undefined without decode or retry', async () => {
  for (const kind of ['listing', 'content']) for (const asyncFailure of [false, true]) {
    for (const reason of [new Error('OriginalRetentionFailure'), undefined]) {
      const f = fixture();
      if (kind === 'content') await f.supplier.readListing(f.listingOptions);
      const before = f.state.admissions, reads = f.state.reads, issued = f.state.issued.size;
      const options = kind === 'listing' ? f.listingOptions : f.content();
      let calls = 0;
      options.retainRawResponse = bytes => {
        assert.strictEqual(bytes, f.raw); calls++;
        if (asyncFailure) return Promise.reject(reason);
        throw reason;
      };
      const outcome = await (kind === 'listing' ? f.supplier.readListing(options) : f.supplier.readContent(options))
        .then(() => ({ok: true}), error => ({ok: false, error}));
      assert.equal(outcome.ok, false);
      assert.strictEqual(outcome.error, reason);
      assert.equal(calls, 1); assert.equal(f.state.reads, reads + 1);
      assert.equal(f.state.admissions, before); assert.equal(f.state.issued.size, issued);
      assert.strictEqual(f.state.pending.bytes, f.raw);
      assert.equal(f.state.bytesCalls, 0); assert.equal(f.state.captures.length, 0);
    }
  }
});

test('fixture raw retention never runs before synchronous charge, current or byte-limit refusal', async () => {
  for (const refusal of ['charge', 'current', 'limit']) {
    const f = fixture(); let retained = 0;
    const originalRead = f.setup.readOriginalBytes;
    const stopped = new Error('OriginalChargeFailure');
    const supplier = createFixtureFileSupplier({...f.setup,
      limits: refusal === 'limit' ? {...f.setup.limits, maxBytes: 1, maxContentBytes: 0} : f.setup.limits,
      async readOriginalBytes(options) {
        const bytes = await originalRead(options);
        if (refusal === 'current') f.state.current = false;
        return bytes;
      }});
    const options = {...f.listingOptions, retainRawResponse() {retained++;}};
    if (refusal === 'charge') options.chargePage = () => {throw stopped;};
    await assert.rejects(supplier.readListing(options), error => refusal === 'charge' ? error === stopped
      : refusal === 'current' ? error.message === 'OriginalSourceNotCurrent'
      : error.code === 'FixtureFileOriginalBytesLimit');
    assert.equal(retained, 0); assert.equal(f.state.reads, 1); assert.equal(f.state.admissions, 0);
    assert.equal(f.state.issued.size, 0);
  }
});

test('fixture raw retention accepts only an optional own DATA method and leaves absent legacy events exact', async () => {
  for (const kind of ['listing', 'content']) {
    const run = async configure => {
      const f = fixture();
      if (kind === 'content') await f.supplier.readListing(f.listingOptions);
      f.state.events.length = 0;
      const options = kind === 'listing' ? f.listingOptions : f.content();
      configure(options);
      await (kind === 'listing' ? f.supplier.readListing(options) : f.supplier.readContent(options));
      return f.state.events;
    };
    const baseline = await run(() => {});
    assert.equal(baseline.filter(event => event === 'verify').length, kind === 'listing' ? 7 : 6);
    assert.deepEqual(await run(options => {options.retainRawResponse = undefined;}), baseline);
    assert.deepEqual(await run(options => Object.setPrototypeOf(options, {
      get retainRawResponse() {assert.fail('inherited callback must not be read');},
    })), baseline);
    for (const descriptor of [{get() {assert.fail('own accessor must not run');}}, {value: null}, {value: 1}]) {
      const f = fixture();
      const options = kind === 'listing' ? f.listingOptions : f.content();
      Object.defineProperty(options, 'retainRawResponse', descriptor);
      await assert.rejects(kind === 'listing' ? f.supplier.readListing(options) : f.supplier.readContent(options),
        {code: 'FixtureFileCallbacksUnavailable'});
      assert.equal(f.state.reads, 0); assert.equal(f.state.events.length, 0);
    }
  }
});
