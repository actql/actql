import assert from 'node:assert/strict';
import test, {after} from 'node:test';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {inspect} from 'node:util';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect, ClientError, explainReadFailure, formatReadFailure, explainDeliveryAttempt} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {openResultDeliveryControl} from '../../packages/run-host-core/index.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import * as resultAccess from '../host-common/result-access.mjs';
import {createResultDeliveryFixture} from '../../scripts/fixtures/result-delivery-acceptance.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('9')};
const tlsRoot = await mkdtemp(join(tmpdir(), 'actql-read-progress-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
  '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(tlsRoot, name))));
const originalCAs = getCACertificates('default');
setDefaultCACertificates([...originalCAs, cert.toString('utf8')]);
after(async () => {
  setDefaultCACertificates(originalCAs);
  await rm(tlsRoot, {recursive: true, force: true});
});

async function installed(t, entrance, fixture, invalidRow, lookupReply) {
  const operations = [];
  let finished;
  const settled = entrance === 'local' ? Promise.resolve()
    : new Promise(resolve => { finished = resolve; });
  const mode = entrance === 'local' ? 'local' : 'remote';
  const services = {
    authenticate: () => 'principal',
    authorizeConnection: ({operation}) => { operations.push(operation); return true; },
    negotiate: () => ({version: 'actql-client-host/0.1', mode, owner: mode,
      durability: 'volatile', scopeRef: 'principal', capabilities: [],
      limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
        maxRows: 256, maxBatchRows: 16, maxBatchRetainedValueBytes: 8192}}),
    attach: () => ({ref, durability: 'volatile', revision: 1}),
    resultService: fixture.service, maxRowBytes: 1024,
  };
  let client, endpoint = 'actql:embedded';
  if (entrance === 'local') {
    const host = createNodeInProcessClientHost(services);
    const port = invalidRow === undefined && lookupReply === undefined ? host : {
      async perform(operation, ...args) {
        const response = await host.perform(operation, ...args);
        if (operation === 'delivery-attempt' && lookupReply) {
          return lookupReply(response);
        }
        if (operation !== 'read' || invalidRow === undefined) return response;
        return {kind: 'rows', frames: {
          async *[Symbol.asyncIterator]() {
            for await (const frame of response.frames) {
              yield frame.value.value === 2 ? {...frame, value: invalidRow.value} : frame;
            }
          },
        }};
      },
    };
    client = await connectInProcess({mode, owner: mode}, port);
  } else {
    const handler = createClientHttpHandler(services);
    const server = createServer({key, cert}, async (request, response) => {
      if (invalidRow !== undefined && request.url.endsWith('/read')) {
        // Corrupt one serialized row downstream of the real delivery owner.
        const write = response.write.bind(response);
        response.write = (bytes, ...args) => write(
          Buffer.from(bytes).toString('utf8') === '{"value":2}\n'
            ? Buffer.from(invalidRow.wire) : bytes, ...args);
      }
      try { await handler(request, response); }
      finally { if (request.url.endsWith('/read')) finished(); }
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(async () => {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    });
    endpoint = `https://127.0.0.1:${server.address().port}/`;
    client = await connect({mode, endpoint, token: 'scoped-token'});
  }
  t.after(() => client.close());
  return {result: (await client.attach(ref)).result('answer'), operations, settled, endpoint};
}

function assertReadExplanation(f, failure, attemptId, rowsYielded, observation = 'read_incomplete', cleanupUnknown = false) {
  const operations = [...f.operations];
  const quantity = `${rowsYielded} ${rowsYielded === 1 ? 'row' : 'rows'}`;
  const expected = {observation, ...(cleanupUnknown ? {cleanup: 'unknown'} : {}), attemptId, rowsYielded,
    summary: observation === 'cleanup_unknown'
      ? `Reader cleanup could not be confirmed after returning ${quantity}.`
      : `This read stopped after returning ${quantity}.`,
    hint: 'Keep this read reference. Look it up before deciding whether to open a new read from the beginning.',
    next: {operation: 'deliveryAttempt', ref, resultName: 'answer', attemptId,
      lookupContext: {endpoint: f.endpoint, scopeRef: 'principal'}},
  };
  const explanation = explainReadFailure(failure);
  for (const format of ['text', 'html', 'json']) {
    const output = formatReadFailure(failure, {format});
    assert.ok(output);
    assert.doesNotMatch(output, /private-result-fragment|private-delivery-secret|scoped-token/u);
    if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, expected,
      '[check-mutation:operation-read-public-format]');
  }
  assert.deepEqual(explanation, expected, '[check-mutation:read-explanation]');
  assert.deepEqual(explainReadFailure(failure, {locale: 'ja'}), {...expected,
    summary: observation === 'cleanup_unknown'
      ? `${rowsYielded}行を返した後のreader cleanupを確認できません。`
      : `この読み取りは${rowsYielded}行を返した後で停止しました。`,
    hint: 'この読み取り参照を保持してください。先頭から新しく読み取るか判断する前に、元の参照で状態を確認してください。'},
  '[check-mutation:operation-read-public-locale]');
  assert.equal(explainReadFailure(failure, {get locale() {throw new Error('private-locale');}}), explanation);
  assert.equal(Object.isFrozen(explanation), true);
  assert.equal(Object.isFrozen(explanation.next), true);
  assert.equal(Object.isFrozen(explanation.next.ref), true);
  assert.equal(Object.isFrozen(explanation.next.lookupContext), true);
  assert.equal(explainReadFailure({...failure}), undefined, '[check-mutation:read-explanation-custody]');
  assert.equal(explainReadFailure(new ClientError(failure.code, {...failure})), undefined);
  failure.code = 'Succeeded';
  failure.message = 'Read completed successfully';
  failure.rowsYielded = 0;
  failure.attemptId = 'edited-read-attempt';
  assert.deepEqual(explainReadFailure(failure), expected, '[check-mutation:read-explanation]');
  assert.deepEqual(f.operations, operations);
  assert.doesNotMatch(JSON.stringify(explanation), /private-result-fragment|private-delivery-secret|scoped-token/u);
}

// Literal malformed row shapes and expected counts are independent of decoding.
const invalidRows = [
  {value: null, wire: 'null\n'},
  {value: false, wire: 'false\n'},
  {value: true, wire: 'true\n'},
  {value: 0, wire: '0\n'},
  {value: 42, wire: '42\n'},
  {value: '', wire: '""\n'},
  {value: 'private-result-fragment', wire: '"private-result-fragment"\n'},
  {value: [], wire: '[]\n'},
  {value: [{value: 2}], wire: '[{"value":2}]\n'},
];

for (const entrance of ['local', 'https']) {
  for (const operation of ['rows', 'all']) {
    test(`${entrance}: ${operation} refuses non-object delivery rows before yielding`,
      {timeout: 15000}, async t => {
        for (const invalidRow of invalidRows) {
          const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
            rows: ['{"value":1}', '{"value":2}', '{"value":3}'], maxBytes: 4096,
          });
          const f = await installed(t, entrance, fixture, invalidRow);
          const reader = operation === 'rows' ? f.result.rows() : undefined;
          const returned = [];
          let failure;
          try {
            if (reader) for await (const row of reader) returned.push(row);
            else returned.push(...await f.result.all());
          } catch (error) { failure = error; }
          assert.equal(failure?.code, 'InvalidResultFrame', '[check-mutation:read-row-shape]');
          assert.equal(failure.rowsYielded, reader ? 1 : 0, '[check-mutation:read-row-count]');
          assert.equal(failure.attemptId,
            reader?.attemptId ?? JSON.parse(fixture.state.selected.wire).attempt_id);
          assert.deepEqual(returned, reader ? [{value: 1}] : []);
          if (reader) {
            assert.equal(reader.state(), 'prefix', '[check-mutation:read-row-state]');
            assert.equal(reader.rowsYielded(), 1);
          }
          assert.doesNotMatch(inspect(failure, {showHidden: true, depth: 8}), /private-result-fragment/u);
          assert.equal(fixture.state.admissions, 1);
          assert.equal(fixture.state.grantUses, 1);
          assert.deepEqual(f.operations, ['connect', 'attach', 'read']);
        }
      });
  }
}

for (const operation of ['rows', 'all']) {
  test(`https: ${operation} classifies malformed JSON as an invalid delivery frame`,
    {timeout: 10000}, async t => {
      const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
        rows: ['{"value":1}', '{"value":2}', '{"value":3}'], maxBytes: 4096,
      });
      const f = await installed(t, 'https', fixture, {wire: 'private-result-fragment\n'});
      const reader = operation === 'rows' ? f.result.rows() : undefined;
      const returned = [];
      let failure;
      try {
        if (reader) for await (const row of reader) returned.push(row);
        else returned.push(...await f.result.all());
      } catch (error) { failure = error; }
      assert.equal(failure?.code, 'InvalidResultFrame', '[check-mutation:read-row-syntax]');
      assert.equal(failure.rowsYielded, reader ? 1 : 0, '[check-mutation:read-row-count]');
      assert.equal(failure.attemptId,
        reader?.attemptId ?? JSON.parse(fixture.state.selected.wire).attempt_id);
      assert.deepEqual(returned, reader ? [{value: 1}] : []);
      assert.doesNotMatch(inspect(failure, {showHidden: true, depth: 8}), /private-result-fragment/u);
      assert.equal(fixture.state.admissions, 1);
      assert.equal(fixture.state.grantUses, 1);
      assert.deepEqual(f.operations, ['connect', 'attach', 'read']);
    });
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: 120 yielded rows survive a real delivery-owner failure`, {timeout: 10000}, async t => {
    let release;
    const yielded = new Promise(resolve => { release = resolve; });
    const rows = Array.from({length: 121}, (_, index) => `{"value":${index + 1}}`);
    const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
      rows, maxBytes: 16384,
      async readRows(accept) {
        for (const row of rows.slice(0, 120)) await accept(row);
        await yielded;
        throw new Error('published row stream interrupted');
      },
    });
    const f = await installed(t, entrance, fixture);
    const reader = f.result.rows();
    const seen = [];
    let failure;
    try {
      await assert.rejects(async () => {
        for await (const row of reader) {
          seen.push(row);
          assert.equal(reader.rowsYielded(), seen.length);
          if (seen.length === 120) release();
        }
      }, error => {
        failure = error;
        return error instanceof ClientError && error.attemptId === reader.attemptId &&
          error.rowsYielded === 120;
      });
    } finally { release(); }
    assert.deepEqual(seen, Array.from({length: 120}, (_, index) => ({value: index + 1})));
    assert.equal(reader.rowsYielded(), 120);
    assert.equal(reader.state(), 'prefix');
    await f.settled;
    assert.equal(JSON.parse(fixture.state.selected.wire).attempt_id, reader.attemptId);
    assert.equal(JSON.parse(fixture.state.record.wire).state, 'failed');
    assert.equal(JSON.parse(fixture.state.record.wire).result_delivery_receipt_cid, undefined);
    assert.equal(fixture.state.admissions, 1);
    assert.equal(fixture.state.grantUses, 1);
    assert.equal(fixture.state.readers, 1);
    assert.deepEqual(f.operations, ['connect', 'attach', 'read']);
    assert.equal(failure.cleanupError !== undefined, entrance === 'https');
    assertReadExplanation(f, failure, reader.attemptId, 120, 'read_incomplete', entrance === 'https');
  });

  test(`${entrance}: normal completion counts 121 rows through the same owner`, {timeout: 10000}, async t => {
    let release;
    const clientCompleted = new Promise(resolve => { release = resolve; });
    const rows = Array.from({length: 121}, (_, index) => `{"value":${index + 1}}`);
    const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(),
      {rows, maxBytes: 16384, async beforeAppend(record) {
        if (entrance === 'https' && JSON.parse(record.wire).state === 'succeeded') {
          await clientCompleted;
        }
      }});
    const f = await installed(t, entrance, fixture);
    const reader = f.result.rows();
    try {
      assert.equal((await Array.fromAsync(reader)).length, 121);
      assert.equal(reader.rowsYielded(), 121);
      assert.equal(reader.state(), 'complete');
      if (entrance === 'https') {
        assert.equal(JSON.parse(fixture.state.record.wire).state, 'streaming');
      }
    } finally { release(); }
    await f.settled;
    assert.equal(JSON.parse(fixture.state.record.wire).state, 'succeeded');
    assert.equal(fixture.state.grantUses, 1);
    assert.deepEqual(f.operations, ['connect', 'attach', 'read']);
  });
}

for (const operation of ['rows', 'all']) {
  test(`local: ${operation} preserves a terminal record failure after all 121 rows`, async t => {
    const unavailable = Object.assign(new Error('private-delivery-secret'), {
      stack: 'private-delivery-secret', cause: new Error('private-delivery-secret'),
      sourceLocator: 'connector://private-delivery-secret',
    });
    const rows = Array.from({length: 121}, (_, index) => `{"value":${index + 1}}`);
    const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
      rows, maxBytes: 16384, async beforeAppend(record) {
        if (JSON.parse(record.wire).state === 'succeeded') throw unavailable;
      },
    });
    const f = await installed(t, 'local', fixture);
    const reader = operation === 'rows' ? f.result.rows() : undefined;
    const returned = [];
    let failure;
    try {
      if (reader) {
        for await (const row of reader) returned.push(row);
      } else {
        returned.push(...await f.result.all());
      }
    } catch (error) { failure = error; }
    assert.equal(failure?.code, 'ClientHostFailure', '[check-mutation:local-outcome]');
    assert.ok(failure instanceof ClientError);
    assert.equal(failure.rowsYielded, reader ? 121 : 0);
    assert.equal(failure.attemptId,
      reader?.attemptId ?? JSON.parse(fixture.state.selected.wire).attempt_id);
    assert.doesNotMatch(inspect(failure, {showHidden: true, depth: 8}), /private-delivery-secret/u);
    const publicCause = reader ? failure.cause : failure.cause.cause;
    assert.equal(publicCause.cause, undefined);
    assert.equal(publicCause.stack, undefined);
    assert.equal(publicCause.cleanupHandle, undefined);
    assert.equal(returned.length, reader ? 121 : 0);
    const failedAttemptId = failure.attemptId;
    if (reader) {
      assert.equal(reader.state(), 'prefix');
      assert.equal(reader.rowsYielded(), 121);
    }
    assert.equal(JSON.parse(fixture.state.record.wire).state, 'streaming');
    assert.equal(fixture.state.admissions, 1);
    assert.equal(fixture.state.grantUses, 1);
    assert.equal(fixture.state.readers, 1);
    assert.deepEqual(f.operations, ['connect', 'attach', 'read']);
    assertReadExplanation(f, failure, failedAttemptId, reader ? 121 : 0);
  });
}


for (const entrance of ['local', 'https']) {
  test(`${entrance}: batches count only rows returned before Delivery failure`, {timeout: 10000}, async t => {
    let release;
    const consumed = new Promise(resolve => { release = resolve; });
    const rows = Array.from({length: 121}, (_, index) => `{"value":${index + 1}}`);
    const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
      rows, maxBytes: 16384,
      async readRows(accept) {
        for (const row of rows.slice(0, 120)) await accept(row);
        await consumed;
        throw new Error('private-delivery-secret');
      },
    });
    const f = await installed(t, entrance, fixture);
    const reader = f.result.batches({maxBatchRows: 16});
    const returned = [];
    let failure;
    try {
      for await (const batch of reader) {
        returned.push(...batch);
        if (returned.length === 112) release();
      }
    } catch (error) { failure = error; }
    finally { release(); }
    await f.settled;
    assert.ok(failure);
    assert.equal(failure.rowsYielded, 112);
    assert.equal(reader.rowsYielded(), 112);
    assert.equal(reader.state(), 'prefix');
    assert.deepEqual(returned, Array.from({length: 112}, (_, index) => ({value: index + 1})));
    assert.equal(JSON.parse(fixture.state.record.wire).state, 'failed');
    assert.equal(fixture.state.grantUses, 1);
    assert.equal(fixture.state.admissions, 1);
    assert.equal(failure.cleanupError !== undefined, entrance === 'https');
    assertReadExplanation(f, failure, reader.attemptId, 112, 'read_incomplete', entrance === 'https');
  });
}

test('https: early reader cleanup uncertainty retains its original lookup target', {timeout: 10000}, async t => {
  const perform = globalThis.fetch;
  t.mock.method(globalThis, 'fetch', async (...args) => {
    const response = await perform(...args);
    if (String(args[0]).endsWith('/read')) {
      const getReader = response.body.getReader.bind(response.body);
      response.body.getReader = (...options) => {
        const reader = getReader(...options);
        const cancel = reader.cancel.bind(reader);
        reader.cancel = async (...values) => {
          await cancel(...values);
          throw new Error('private-delivery-secret');
        };
        return reader;
      };
    }
    return response;
  });
  const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
    rows: ['{"value":1}', '{"value":2}', '{"value":3}'], maxBytes: 4096,
  });
  const f = await installed(t, 'https', fixture);
  const reader = f.result.rows();
  const iterator = reader[Symbol.asyncIterator]();
  assert.deepEqual(await iterator.next(), {value: {value: 1}, done: false});
  let failure;
  await assert.rejects(iterator.return(), error => {
    failure = error;
    return error.code === 'ResultReadCleanupUnknown';
  });
  assert.equal(reader.state(), 'prefix');
  assert.equal(reader.rowsYielded(), 1);
  assertReadExplanation(f, failure, reader.attemptId, 1, 'cleanup_unknown');
});

// The fixture retains the actual delivery owner's contracts. Only its DTO
// container is reused; neither receipt issuance nor transition rules change.
for (const entrance of ['local', 'https']) {
  test(`${entrance}: delivery lookup snapshots survive reused owner record containers`, async t => {
    let release;
    const held = new Promise(resolve => {release = resolve;});
    let reused;
    const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
      async readRows(accept) {await accept('{"value":7}'); await held;},
      lookup(current) {
        if (!reused) reused = current;
        else {
          for (const key of Object.keys(reused.record)) delete reused.record[key];
          Object.assign(reused.record, current.record);
          reused.hostReleaseReceipt = current.hostReleaseReceipt;
        }
        return reused;
      },
    });
    const f = await installed(t, entrance, fixture);
    const reader = f.result.rows();
    const iterator = reader[Symbol.asyncIterator]();
    try {
      assert.deepEqual(await iterator.next(), {done: false, value: {value: 7}});
      const pending = await f.result.deliveryAttempt(reader.attemptId);
      assert.equal(pending.record.state, 'streaming');
      assert.equal(pending.hostReleaseReceipt, null);
      assert.equal(explainDeliveryAttempt(pending).observation, 'delivery_streaming');
      assert.equal(explainDeliveryAttempt(pending).hostConfirmedByteCount, 0);
      release();
      assert.equal((await iterator.next()).done, true);
      await f.settled;
      const completed = await f.result.deliveryAttempt(reader.attemptId);
      assert.equal(completed.record.state, 'succeeded');
      assert.equal(completed.record.confirmed_byte_count, 12);
      assert.equal(explainDeliveryAttempt(completed).observation, 'host_delivery_succeeded');
      assert.equal(completed.hostReleaseReceipt.delivered_sha256,
        createHash('sha256').update('{"value":7}\n').digest('hex'));
      assert.equal(pending.record.state, 'streaming', '[check-mutation:delivery-lookup-snapshot]');
      assert.equal(explainDeliveryAttempt(pending).observation, 'delivery_streaming');
      assert.equal(pending.hostReleaseReceipt, null);
      assert.equal(Object.isFrozen(pending.record), true, '[check-mutation:delivery-lookup-freeze]');
      assert.equal(Object.isFrozen(completed.attempt), true, '[check-mutation:delivery-lookup-freeze]');
      assert.equal(Object.isFrozen(completed.hostReleaseReceipt), true, '[check-mutation:delivery-lookup-freeze]');
      assert.equal(Object.isFrozen(reused.record), false, '[check-mutation:delivery-lookup-detached]');
      assert.throws(() => {pending.record.state = 'succeeded';}, TypeError);
      assert.equal(pending.record.state, 'streaming');
      assert.equal(fixture.state.admissions, 1);
      assert.equal(fixture.state.grantUses, 1);
      assert.equal(fixture.state.readers, 1);
      assert.deepEqual(f.operations, ['connect', 'attach', 'read', 'delivery-attempt', 'delivery-attempt']);
    } finally {release(); await iterator.return();}
  });
}

for (const fault of ['clone changes a previously valid field', 'reply cannot be cloned']) {
  test(`local: delivery lookup rejects ${fault}`, async t => {
    const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
      lookup: current => current,
    });
    const f = await installed(t, 'local', fixture, undefined, value => {
      if (fault === 'reply cannot be cloned') return new Proxy(value, {});
      let reads = 0;
      const observedAt = value.record.observed_at;
      Object.defineProperty(value.record, 'observed_at', {enumerable: true,
        get() {return ++reads === 1 ? observedAt : 42;}});
      return value;
    });
    const reader = f.result.rows();
    assert.deepEqual(await Array.fromAsync(reader), [{value: 7}]);
    let failure;
    try {await f.result.deliveryAttempt(reader.attemptId);} catch (error) {failure = error;}
    assert.equal(failure?.code, 'InvalidHostAttemptLookup', '[check-mutation:delivery-lookup-admission]');
    assert.deepEqual(f.operations, ['connect', 'attach', 'read', 'delivery-attempt']);
    assert.equal(fixture.state.grantUses, 1);
  });
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: failed Delivery explanation retains sink bytes without failing the Run`, async t => {
    const fixture = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
      async readRows(accept) {
        await accept('{"value":7}');
        throw new Error('private-delivery-failure');
      },
      lookup: current => current,
    });
    const f = await installed(t, entrance, fixture);
    const reader = f.result.rows();
    const returned = [];
    await assert.rejects(async () => {for await (const row of reader) returned.push(row);});
    await f.settled;
    assert.deepEqual(returned, [{value: 7}]);
    assert.equal(reader.rowsYielded(), 1);
    const lookup = await f.result.deliveryAttempt(reader.attemptId);
    assert.equal(lookup.record.state, 'failed');
    assert.equal(lookup.hostReleaseReceipt, null);
    const explanation = explainDeliveryAttempt(lookup);
    assert.equal(explanation.observation, 'delivery_failed', '[check-mutation:delivery-observation-classification]');
    assert.equal(explanation.hostConfirmedByteCount, 12);
    assert.equal(explanation.recordSequence, 1);
    assert.equal(explanation.summary, 'The Host reports that this Delivery failed; this does not fail the Run.');
    assert.equal(Object.hasOwn(explanation, 'hostReleaseReceiptCid'), false);
    assert.equal(Object.hasOwn(explanation, 'runStatus'), false);
    assert.equal(Object.hasOwn(explanation, 'rowsYielded'), false);
    assert.doesNotMatch(JSON.stringify(explanation), /private-delivery-failure/);
    assert.deepEqual(f.operations, ['connect', 'attach', 'read', 'delivery-attempt']);
    assert.equal(fixture.state.grantUses, 1);
    assert.equal(fixture.state.readers, 1);
  });
}
