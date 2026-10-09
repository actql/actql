import {submissionEpoch, originalSubmission, readySubmissionAttempt} from './submission-fixture.mjs';
import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {setImmediate} from 'node:timers/promises';
import {connect, connectInProcess, explainReadFailure} from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'typed-results', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')};
const time = '2026-10-07T00:00:00.000Z';
const profile = {submissionEpoch, version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'scope', capabilities: [], limits: {
    maxReadWireBytes: 65536, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
    maxRows: 256, maxBatchRows: 3, maxBatchRetainedValueBytes: 4096}};
const state = {version: 'actql-run-state/0.1', run_id: 'typed-run',
  status: 'succeeded', updated_at: time, next_action: {kind: 'read_result', results: ['answer']},
  result_available: true, result_availability: {answer: {state: 'available',
    observed_at: time, reason: 'confirmed_present'}}};
const schema = validate => ({'~standard': {version: 1, vendor: 'test', validate}});
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => {resolve = yes; reject = no;});
  return {promise, resolve, reject};
};

async function fixture(t, mode, overrides = {}) {
  const calls = [], stats = {pulled: 0, returned: 0, closed: 0};
  const rows = overrides.rows ?? [{n: 1}, {n: 2}];
  const operate = async (operation, body, signal) => {
    calls.push({operation, body});
    if (operation === 'connect') return {...profile, mode, owner: mode};
    if (operation === 'submit-intent') return readySubmissionAttempt(body, {ref, durability: 'durable', revision: 1});
    if (operation === 'attach') {
      return {ref, durability: 'durable', revision: 1};
    }
    if (operation === 'wait') {await overrides.wait?.(); return state;}
    assert.equal(operation, 'read');
    if (mode === 'local') return {kind: 'rows', frames: {
      async *[Symbol.asyncIterator]() {
        try {
          for (const value of rows) {
            signal.throwIfAborted(); stats.pulled++;
            yield {value, byteLength: new TextEncoder().encode(JSON.stringify(value)).length};
          }
        } finally {stats.returned++;}
      },
    }, async close() {stats.closed++; await overrides.cleanup?.();}};
    if (overrides.response) return overrides.response(stats);
    return new Response(rows.map(row => JSON.stringify(row) + '\n').join('') + '\x1e');
  };
  let client;
  if (mode === 'local') client = await connectInProcess({mode, owner: mode}, {perform: operate});
  else {
    mock.method(globalThis, 'fetch', async (url, init) => {
      const value = await operate(url.pathname.split('/').at(-1), JSON.parse(init.body), init.signal);
      return value instanceof Response ? value : Response.json(value);
    });
    t.after(() => mock.restoreAll());
    client = await connect({mode, endpoint: 'https://host.example/', token: 'token'});
  }
  t.after(() => client.close());
  return {client, result: (await client.attach(ref)).result('answer'), calls, stats};
}

for (const mode of ['local', 'remote']) {
  test(`${mode}: raw calls and sync/async schema views preserve row order and one read`, async t => {
    const f = await fixture(t, mode);
    assert.deepEqual(await f.result.all(), [{n: 1}, {n: 2}]);
    assert.deepEqual(await f.result.all(schema(row => ({value: row.n * 2}))), [2, 4]);
    const reader = f.result.rows(schema(async row => ({value: `row-${row.n}`})));
    assert.equal(reader.state(), 'not_started');
    assert.deepEqual(await Array.fromAsync(reader), ['row-1', 'row-2']);
    assert.equal(reader.state(), 'complete'); assert.equal(reader.rowsYielded(), 2);
    assert.equal(f.calls.filter(x => x.operation === 'read').length, 3);
    assert.equal(f.calls.some(x => ['cancel', 'submit-intent'].includes(x.operation)), false);
  });

  test(`${mode}: an empty Result validates no rows`, async t => {
    const f = await fixture(t, mode, {rows: []});
    assert.deepEqual(await f.result.all(schema(() => assert.fail('No row to validate'))), []);
    const reader = f.result.rows(schema(() => assert.fail('No row to validate')));
    assert.deepEqual(await Array.fromAsync(reader), []);
    assert.equal(reader.state(), 'complete'); assert.equal(reader.rowsYielded(), 0);
  });

  test(`${mode}: typed failures retain original identity and actual caller progress`, async t => {
    const f = await fixture(t, mode);
    const issues = [{message: 'private invalid n', path: ['n']}];
    const validator = schema(row => row.n === 1 ? {value: row.n} : {issues});
    const reader = f.result.rows(validator), iterator = reader[Symbol.asyncIterator]();
    assert.deepEqual(await iterator.next(), {done: false, value: 1});
    let failure;
    await assert.rejects(iterator.next(), error => {
      failure = error;
      assert.equal(error.code, 'ResultValidationFailed');
      assert.equal(error.validationKind, 'issues'); assert.equal(error.issues, issues);
      assert.equal(error.rowIndex, 1); assert.equal(error.rowsYielded, 1);
      assert.equal(error.attemptId, reader.attemptId);
      assert.deepEqual(error.resultRef, f.result.ref);
      assert.doesNotMatch(JSON.stringify(error), /private invalid n/); return true;
    });
    assert.equal(reader.rowsYielded(), 1); assert.equal(reader.state(), 'prefix');
    assert.deepEqual(explainReadFailure(failure).next.ref, ref);
    assert.equal(explainReadFailure(failure).next.resultName, 'answer');
    await assert.rejects(f.result.all(validator), error =>
      error.code === 'ResultValidationFailed' && error.rowIndex === 1 &&
      error.rowsYielded === 0 && error.issues === issues &&
      error.resultRef.resultName === 'answer');
  });

  test(`${mode}: raw quotas run before mutating transforms and collection counts`, async t => {
    const f = await fixture(t, mode);
    let validated = 0;
    const shrink = schema(row => {validated++; delete row.n; return {value: null};});
    for (const [limits, code, expectedCalls] of [
      [{maxWireBytes: 1}, 'ResultWireLimit', 0],
      [{maxRowWireBytes: 1}, 'ResultRowWireLimit', 0],
      [{maxRowRetainedValueBytes: 1}, 'ResultRowRetainedLimit', 0],
      [{maxRows: 1}, 'ResultRetainedLimit', 1],
      [{maxRetainedValueBytes: 270}, 'ResultRetainedLimit', 1],
    ]) {
      validated = 0;
      await assert.rejects(f.result.all(shrink, limits), {code, rowsYielded: 0});
      assert.equal(validated, expectedCalls);
    }
    // The provider-owned raw input was never passed to application code.
    assert.deepEqual(await f.result.all(), [{n: 1}, {n: 2}]);
  });

  test(`${mode}: transforms support non-JSON and thenable outputs without assimilation`, async t => {
    const f = await fixture(t, mode);
    let assimilated = 0;
    const thenable = {then() {assimilated++; throw new Error('must not run');}};
    const cycle = {}; cycle.self = cycle;
    const pending = new Promise(() => {});
    const fn = () => 'callable';
    const date = new Date('2026-10-07T00:00:00.000Z');
    for (const output of [undefined, null, 12n, date, new Map([['x', 1]]),
      cycle, fn, thenable, pending]) {
      const view = schema(() => ({value: output}));
      const values = await f.result.all(view, {maxRetainedValueBytes: 600});
      assert.equal(values.length, 2); assert.equal(values[0], output); assert.equal(values[1], output);
      const reader = f.result.rows(view), iterator = reader[Symbol.asyncIterator]();
      const next = await iterator.next();
      assert.equal(next.done, false); assert.equal(next.value, output);
      assert.equal(reader.rowsYielded(), 1); await iterator.return();
    }
    assert.equal(assimilated, 0);
  });

  test(`${mode}: never-settling validation cannot block client.close`, {timeout: 2000}, async t => {
    const entered = deferred(), late = deferred();
    const f = await fixture(t, mode);
    const reader = f.result.rows(schema(() => {entered.resolve(); return late.promise;}));
    const next = reader[Symbol.asyncIterator]().next();
    const rejected = assert.rejects(next, {code: 'ClientClosed', rowsYielded: 0,
      attemptId: reader.attemptId});
    await entered.promise; await f.client.close(); await rejected;
    assert.equal(reader.state(), 'prefix'); assert.equal(reader.rowsYielded(), 0);
    late.reject(new Error('late application failure is observed'));
    await setImmediate();
    if (mode === 'local') {assert.equal(f.stats.returned, 1); assert.equal(f.stats.closed, 1);}
  });

  test(`${mode}: caller abort interrupts validation and never publishes late output`, {timeout: 2000}, async t => {
    const entered = deferred(), late = deferred(), controller = new AbortController();
    const f = await fixture(t, mode);
    const reader = f.result.rows(schema(() => {entered.resolve(); return late.promise;}),
      {signal: controller.signal});
    const next = reader[Symbol.asyncIterator]().next();
    const rejected = assert.rejects(next, error => error.rowsYielded === 0 &&
      error.code !== 'ResultValidationFailed');
    await entered.promise; controller.abort(); await rejected;
    late.resolve({value: 'too late'}); await setImmediate();
    assert.equal(reader.rowsYielded(), 0);
  });
}

test('validation is serial and reader backpressure does not pull the next Local row', async t => {
  const f = await fixture(t, 'local'), entered = deferred(), finish = deferred();
  let validations = 0;
  const reader = f.result.rows(schema(async row => {
    validations++; if (row.n === 1) {entered.resolve(); await finish.promise;}
    return {value: row.n};
  }));
  const iterator = reader[Symbol.asyncIterator](), first = iterator.next();
  await entered.promise;
  assert.equal(f.stats.pulled, 1); assert.equal(validations, 1); assert.equal(reader.rowsYielded(), 0);
  finish.resolve(); assert.deepEqual(await first, {done: false, value: 1});
  await setImmediate(); assert.equal(f.stats.pulled, 1); assert.equal(validations, 1);
  assert.deepEqual(await iterator.next(), {done: false, value: 2});
  await iterator.return(); assert.equal(f.stats.returned, 1); assert.equal(f.stats.closed, 1);
});

test('validation errors distinguish issues, throws, rejections and malformed results', async t => {
  const f = await fixture(t, 'local', {rows: [{n: 1}]});
  const thrown = new Error('private callback exception');
  for (const [validate, kind] of [
    [() => ({issues: []}), 'issues'],
    [() => {throw thrown;}, 'exception'],
    [async () => {throw thrown;}, 'exception'],
    [() => undefined, 'invalid_result'], [() => null, 'invalid_result'],
    [() => ({}), 'invalid_result'], [() => ({issues: false}), 'invalid_result'],
    [() => ({issues: [{path: ['n']}]}), 'invalid_result'],
    [() => ({issues: [{message: 'bad path', path: [{}]}]}), 'invalid_result'],
  ]) {
    await assert.rejects(f.result.all(schema(validate)), error => {
      assert.equal(error.code, 'ResultValidationFailed'); assert.equal(error.validationKind, kind);
      assert.equal(error.rowIndex, 0); assert.equal(error.rowsYielded, 0);
      if (kind === 'exception') assert.equal(error.cause.cause.cause, thrown);
      assert.doesNotMatch(JSON.stringify(error), /private callback exception/); return true;
    });
  }
  assert.deepEqual(await f.result.all(schema(() => ({value: undefined}))), [undefined]);
});

test('an abort triggered by a validation result getter is checked before publication', async t => {
  const f = await fixture(t, 'local'), controller = new AbortController();
  const reader = f.result.rows(schema(() => ({get value() {controller.abort(); return 1;}})),
    {signal: controller.signal});
  await assert.rejects(reader[Symbol.asyncIterator]().next());
  assert.equal(reader.rowsYielded(), 0);
});

test('invalid schemas fail before read; callable schemas and their receivers are supported', async t => {
  const f = await fixture(t, 'local');
  for (const standard of [null, {}, {version: 2, vendor: 'test', validate() {}},
    {version: 1, vendor: 'test', validate: true}]) {
    await assert.rejects(f.result.all({'~standard': standard}), {code: 'InvalidResultSchema'});
    assert.throws(() => f.result.rows({'~standard': standard}), {code: 'InvalidResultSchema'});
  }
  assert.equal(f.calls.some(x => x.operation === 'read'), false);
  function callable() {}
  callable['~standard'] = {version: 1, vendor: 'callable', offset: 10,
    validate(row) {return {value: row.n + this.offset};}};
  assert.deepEqual(await f.result.all(callable), [11, 12]);
});

test('Result and query shortcut capture validators, inherited limits and live signals at invocation', async t => {
  const waiting = deferred(), release = deferred();
  const f = await fixture(t, 'local', {wait: async () => {waiting.resolve(); await release.promise;}});
  const validator = schema(row => ({value: row.n}));
  const options = Object.create({maxRows: 1});
  const query = f.client.sql('SELECT n FROM source');
  const collection = query.all(validator, options);
  validator['~standard'].validate = () => assert.fail('mutated method');
  validator['~standard'] = schema(() => assert.fail('mutated adapter'))['~standard'];
  options.maxRows = 200;
  await waiting.promise; release.resolve();
  await assert.rejects(collection, {code: 'ResultRetainedLimit', rowsYielded: 0});
  assert.equal(f.calls.filter(x => x.operation === 'submit-intent').length, 1);
  assert.equal(f.calls.filter(x => x.operation === 'read').length, 1);

  const captured = schema(row => ({value: row.n})), controller = new AbortController();
  const selected = {signal: controller.signal, maxRowRetainedValueBytes: 1};
  const reader = f.result.rows(captured, selected);
  captured['~standard'].validate = () => assert.fail('late validator');
  selected.maxRowRetainedValueBytes = 1024; selected.signal = new AbortController().signal;
  await assert.rejects(Array.fromAsync(reader), {code: 'ResultRowRetainedLimit'});
  const live = f.result.rows(schema(row => ({value: row.n})), {signal: controller.signal});
  controller.abort(); await assert.rejects(Array.fromAsync(live));
  assert.equal(live.rowsYielded(), 0);
});

for (const mode of ['local', 'remote']) {
  for (const operation of ['rows', 'all']) {
    test(`${mode}: ${operation} preserves validation failure and secondary cleanup uncertainty`, async t => {
      let ready = false;
      const cleanup = new Error('private cleanup uncertainty');
      const f = await fixture(t, mode, {cleanup() {if (!ready) throw cleanup;},
        response: () => new Response(new ReadableStream({
          start(controller) {controller.enqueue(new TextEncoder().encode('{"n":1}\n'));},
          cancel() {throw cleanup;},
        }))});
      const view = schema(() => ({issues: [{message: 'n rejected', path: ['n']}]}));
      let failure;
      await assert.rejects(operation === 'all' ? f.result.all(view) : Array.fromAsync(f.result.rows(view)), error => {
        failure = error;
        assert.equal(error.code, 'ResultValidationFailed'); assert.equal(error.validationKind, 'issues');
        assert.equal(error.cleanupError, cleanup); assert.equal(error.rowIndex, 0);
        assert.equal(error.rowsYielded, 0); return true;
      });
      assert.equal(explainReadFailure(failure).cleanup, 'unknown');
      assert.equal(explainReadFailure(failure).observation, 'read_incomplete');
      ready = true; await f.client.close();
    });
  }
}

for (const operation of ['rows', 'all']) {
  test(`Local ${operation} retains a rejecting frame return without a close callback`, async t => {
    const cleanup = new Error('frame return failed');
    let returned = 0;
    const client = await connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation) {
        if (operation === 'connect') return profile;
        if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
        assert.equal(operation, 'read');
        return {kind: 'rows', frames: {
          [Symbol.asyncIterator]() {return {
            async next() {return {done: false, value: {value: {n: 1}, byteLength: 7}};},
            async return() {returned++; throw cleanup;},
          };},
        }};
      },
    });
    t.after(() => client.close());
    const result = (await client.attach(ref)).result('answer');
    const view = schema(() => ({issues: [{message: 'invalid n'}]}));
    await assert.rejects(operation === 'all' ? result.all(view) : Array.fromAsync(result.rows(view)), error =>
      error.code === 'ResultValidationFailed' && error.rowsYielded === 0 &&
      error.rowIndex === 0 && error.cleanupError === cleanup &&
      explainReadFailure(error).cleanup === 'unknown');
    assert.equal(returned, 1);
  });
}

test('Local validation preserves both frame-return and close cleanup errors', async t => {
  const frameError = new Error('frame return failed'), closeError = new Error('close failed');
  let ready = false;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation) {
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
      assert.equal(operation, 'read');
      return {kind: 'rows', frames: {
        async *[Symbol.asyncIterator]() {
          try {yield {value: {n: 1}, byteLength: 7};}
          finally {throw frameError;}
        },
      }, async close() {if (!ready) throw closeError;}};
    },
  });
  t.after(() => client.close());
  const result = (await client.attach(ref)).result('answer');
  await assert.rejects(result.all(schema(() => ({issues: [{message: 'invalid n'}]}))), error => {
    assert.equal(error.code, 'ResultValidationFailed'); assert.equal(error.rowIndex, 0);
    assert.equal(error.rowsYielded, 0); assert.ok(error.cleanupError instanceof AggregateError);
    assert.deepEqual(error.cleanupError.errors, [frameError, closeError]);
    assert.equal(explainReadFailure(error).cleanup, 'unknown'); return true;
  });
  ready = true; await client.close();
});

test('raw aggregate quota failure now stays inside the owner and retains cleanup uncertainty', async t => {
  const cleanup = new Error('uncertain cleanup');
  const f = await fixture(t, 'remote', {response: () => new Response(new ReadableStream({
    start(controller) {controller.enqueue(new TextEncoder().encode('{"n":1}\n{"n":2}\n'));},
    cancel() {throw cleanup;},
  }))});
  await assert.rejects(f.result.all({maxRows: 1}), error => error.code === 'ResultRetainedLimit' &&
    error.rowsYielded === 0 && error.cleanupError === cleanup && explainReadFailure(error).cleanup === 'unknown');
});

test('typed Result and query public declarations infer the schema output', () => {
  const result = spawnSync(process.execPath, [
    fileURLToPath(new URL('../../node_modules/typescript/bin/tsc', import.meta.url)),
    '--strict', '--target', 'ES2022', '--module', 'NodeNext', '--moduleResolution', 'NodeNext', '--noEmit',
    fileURLToPath(new URL('./typed-results.typecheck.mts', import.meta.url)),
  ], {encoding: 'utf8', timeout: 30000});
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test('Local frame iteration retains native next-method capture and callable IteratorResult support', async t => {
  let captured = 0, returned = 0;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation) {
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
      assert.equal(operation, 'read');
      return {kind: 'rows', frames: {
        [Symbol.asyncIterator]() {
          let index = 0;
          return {
            get next() {
              captured++;
              return async function () {
                assert.equal(typeof this.return, 'function');
                return Object.assign(() => {}, {done: false,
                  value: {value: {n: ++index}, byteLength: 7}});
              };
            },
            async return() {returned++; return Object.assign(() => {}, {done: true});},
          };
        },
      }};
    },
  });
  t.after(() => client.close());
  const reader = (await client.attach(ref)).result('answer').rows();
  const iterator = reader[Symbol.asyncIterator]();
  assert.deepEqual(await iterator.next(), {done: false, value: {n: 1}});
  assert.deepEqual(await iterator.next(), {done: false, value: {n: 2}});
  assert.equal(captured, 1);
  await iterator.return();
  assert.equal(returned, 1); assert.equal(reader.rowsYielded(), 2);
});
