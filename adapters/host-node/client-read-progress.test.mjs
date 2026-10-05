import assert from 'node:assert/strict';
import test, {after} from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {inspect} from 'node:util';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect, ClientError} from '../../packages/sdk/index.mjs';
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

async function installed(t, entrance, fixture, invalidRow) {
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
  let client;
  if (entrance === 'local') {
    const host = createNodeInProcessClientHost(services);
    const port = invalidRow === undefined ? host : {
      async perform(operation, ...args) {
        const response = await host.perform(operation, ...args);
        if (operation !== 'read') return response;
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
    client = await connect({mode,
      endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'scoped-token'});
  }
  t.after(() => client.close());
  return {result: (await client.attach(ref)).result('answer'), operations, settled};
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
    try {
      await assert.rejects(async () => {
        for await (const row of reader) {
          seen.push(row);
          assert.equal(reader.rowsYielded(), seen.length);
          if (seen.length === 120) release();
        }
      }, error => error instanceof ClientError && error.attemptId === reader.attemptId &&
        error.rowsYielded === 120);
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
    if (reader) {
      assert.equal(reader.state(), 'prefix');
      assert.equal(reader.rowsYielded(), 121);
    }
    assert.equal(JSON.parse(fixture.state.record.wire).state, 'streaming');
    assert.equal(fixture.state.admissions, 1);
    assert.equal(fixture.state.grantUses, 1);
    assert.equal(fixture.state.readers, 1);
    assert.deepEqual(f.operations, ['connect', 'attach', 'read']);
  });
}
