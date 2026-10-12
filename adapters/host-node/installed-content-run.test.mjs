// Public Client, normal installed dispatcher, actual common runtime and Local
// Store. Expectations do not use the generated encoder or Result publication.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {execFile} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {inspect} from 'node:util';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {connect as connectRemote} from '../../packages/sdk/index.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';
import {stopGeneratedContentPrefix} from './generated-content-write.mjs';

const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
function authorization() {
  const keys = generateKeyPairSync('ed25519');
  return {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'content-public', entries: [{entry_id: 'local-content', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['read', 'write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  };
}
function program({empty = false, format = 'jsonl', ordered = false} = {}) {
  return {version: 'actql/0.1', id: 'installed-content', stages: [{id: 'main', inputs: {},
    steps: [
      {values: {schema: {id: {type: 'number', nullable: false},
        p: {type: 'number', nullable: true}},
      rows: empty ? [] : [{id: 2, p: null}, {id: 9, p: 90}, {id: 1, p: 7}]}, as: 'seed'},
      {filter: 'id < 3', as: 'selected'},
      {from: 'selected', serialize: {format, fields: ['id', 'p'], name: `selected.${format}`,
        ...(ordered ? {order_by: [{id: 'asc'}]} : {preserve_order: true}), bounds: {max_rows: 3, max_bytes: 128},
        ...(format === 'csv' ? {header: true, null_marker: '\\N', line_ending: 'crlf'} : {})}, as: 'file'},
    ], results: {file: {from: 'file', fields: ['name', 'content', 'media_type', 'size_bytes', 'row_count']}}}],
  results: {file: {from: {stage: 'main', result: 'file'}}}};
}

test('stop-only cleanup records delayed work once without reopening Compute', () => {
  let cancelled = false, polls = 0, total = 3n, charged = 0;
  const control = {
    prefixCancel() { cancelled = true; },
    prefixCleanup() { return polls === 2; },
    prefixWork() { return total; },
    prefixAdvance(_prefix, quantum) {
      assert.equal(cancelled, true);
      assert.equal(quantum, 1);
      polls++;
      total++;
      return {stopped: polls === 2};
    },
  };
  const options = {control, prefix: {}, chargeWork(delta) { charged += delta; return false; }};
  assert.equal(stopGeneratedContentPrefix(options), false);
  assert.equal(stopGeneratedContentPrefix(options), false);
  assert.equal(stopGeneratedContentPrefix(options), true);
  assert.equal(stopGeneratedContentPrefix(options), true);
  assert.equal(charged, 2);
  assert.equal(total, 5n);
  assert.equal(polls, 2);
});

for (const observation of ['throws', 'invalid', 'decreases']) {
  test(`stop-only cleanup continues after ${observation} work observation without fabricated accounting`, () => {
    const original = new Error('OriginalStopAccountingFailure');
    let cancelled = false, polls = 0, reads = 0, charged = 0;
    const control = {
      prefixCancel() { cancelled = true; },
      prefixCleanup() { return polls === 2; },
      prefixWork() {
        reads++;
        if (observation === 'throws') throw original;
        if (observation === 'invalid') return undefined;
        return reads % 2 === 1 ? 10n : 9n;
      },
      prefixAdvance(_prefix, quantum) {
        assert.equal(cancelled, true);
        assert.equal(quantum, 1);
        polls++;
        return {stopped: polls === 2};
      },
    };
    const options = {control, prefix: {}, chargeWork(delta) { charged += delta; }};
    for (let retry = 0; retry < 2; retry++) {
      assert.throws(() => stopGeneratedContentPrefix(options), error =>
        observation === 'throws' ? error === original : error.code === 'InvalidGeneratedContentStopWork');
      assert.equal(polls, retry + 1, 'an accounting error cannot prevent physical stop progress');
    }
    assert.equal(charged, 0, 'unknown work is an error, not a guessed zero or difference');
    assert.equal(stopGeneratedContentPrefix(options), true);
    assert.equal(stopGeneratedContentPrefix(options), true);
    assert.equal(polls, 2);
    assert.equal(reads, 4);
  });
}

for (const entrance of ['Local', 'HTTPS']) {
  for (const [format, empty, expected, sourceFormat = 'json', ordered = false] of [
    ['jsonl', false, '{"id":2,"p":null}\n{"id":1,"p":7}\n'],
    ['jsonl', true, ''],
    ['csv', false, 'id,p\r\n2,\\N\r\n1,7\r\n'],
    ['jsonl', false, '{"id":2,"p":null}\n', 'aql-text'],
    ['jsonl', true, '', 'sql'],
    ['csv', false, 'id,p\r\n2,\\N\r\n', 'aql-text'],
    ['jsonl', false, '{"id":1,"p":7}\n{"id":2,"p":null}\n', 'json', true],
    ['csv', false, 'id,p\r\n1,7\r\n2,\\N\r\n', 'json', true],
    ['jsonl', true, '', 'json', true],
    ['jsonl', false, '{"id":1,"p":7}\n{"id":2,"p":null}\n', 'aql-text', true],
  ]) {
    test(`installed SERIALIZE ${entrance} ${format} empty=${empty} source=${sourceFormat} ordered=${ordered} publishes actual Content`, async t => {
      const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
        prefix: 'content-public-', label: `installed Content ${entrance}`});
      const events = [];
      let starts = 0;
      const installation = {directory: join(scratch.path, 'host'), authorization: {
        ...authorization(),
        observe: (event, detail) => events.push({event, detail}),
        faultInjection: async step => { if (step === 'content_workspace_reserved') starts++; },
      }};
      let client, host, server, previousCertificates, closed = false;
      const close = async () => {
        if (closed) return;
        closed = true;
        await client?.close();
        if (server) {
          server.closeAllConnections();
          await new Promise(resolve => server.close(resolve));
        }
        await host?.close();
        if (previousCertificates !== undefined) setDefaultCACertificates(previousCertificates);
      };
      t.after(close);
      try {
      if (entrance === 'Local') {
        client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
      } else {
        const {key, cert, ca} = await fixtureCertificates(scratch.path);
        previousCertificates = getCACertificates('default');
        setDefaultCACertificates([...previousCertificates, ca.toString('utf8')]);
        host = await openInstalledRemoteHttpHost({...installation,
          authenticate: header => header === 'Bearer content-fixture' ? userInfo().username : undefined});
        server = createServer({key, cert}, host.handler);
        await new Promise((resolve, reject) => {
          server.once('error', reject);
          server.listen(0, '127.0.0.1', resolve);
        });
        client = await connectRemote({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
          token: 'content-fixture', durability: 'durable'});
      }
      } catch (error) {
        assert.fail(inspect(error, {depth: 8, maxStringLength: 2000}));
      }
      const submissionRef = client.newSubmission({nonce: `${format}-${empty}-${sourceFormat}-${ordered}`});
      const source = sourceFormat === 'json' ? JSON.stringify(program({format, empty, ordered}))
        : (ordered && !empty
          ? 'SELECT element AS id, IF(element = 2, CAST(NULL AS FLOAT64), 7) AS p FROM UNNEST([2, 1]) element'
          : `SELECT 2 AS id, CAST(NULL AS FLOAT64) AS p${empty ? ' WHERE FALSE' : ''}`) +
          ` |> SERIALIZE FORMAT ${format.toUpperCase()} ${ordered ? 'ORDER BY id' : 'PRESERVE ORDER'} OPTIONS (` +
          `name = 'selected.${format}', max_rows = 3, max_bytes = 128` +
          (format === 'csv' ? String.raw`, header = TRUE, null_marker = r'\N', encoding = 'UTF-8', line_ending = 'CRLF'` : '') +
          ') |> RESULT file';
      if (sourceFormat !== 'json') {
        const checked = await client.check(source, {kind: 'text', scope: 'bound_input', format: sourceFormat});
        assert.equal(checked.outcome, 'completed', inspect(checked, {depth: 12}));
        assert.equal(checked.report.verdict, 'verified', inspect(checked, {depth: 12}));
      }
      const run = await client.startSource(source, {format: sourceFormat, submissionRef}).catch(error => {
        t.diagnostic(inspect({error, events}, {depth: 14, maxArrayLength: 30}));
        throw error;
      });
      const state = await run.wait({signal: AbortSignal.timeout(15000)});
      assert.equal(state.status, 'succeeded', inspect({state, events}, {depth: 8, maxArrayLength: 20}));
      const rows = await run.result('file').all();
      assert.equal(rows.length, 1);
      assert.deepEqual(Object.keys(rows[0]), ['name', 'content', 'media_type', 'size_bytes', 'row_count']);
      const {content, ...visible} = rows[0];
      assert.deepEqual(visible, {name: `selected.${format}`,
        media_type: format === 'jsonl' ? 'application/x-ndjson' : 'text/csv',
        size_bytes: Buffer.byteLength(expected), row_count: empty ? 0 : sourceFormat === 'json' || ordered ? 2 : 1});
      assert.equal(content.$actql_ref, 'content');
      assert.equal(content.metadata.content_cid, hash(expected));
      assert.equal(content.metadata.size_bytes, Buffer.byteLength(expected));
      assert.equal(content.metadata.truncated, false);
      assert.equal(starts, 1);
      const lookup = await client.lookupSubmission(submissionRef);
      assert.equal(lookup.kind, 'ready');
      assert.deepEqual(lookup.admission.ref, run.ref);
      assert.deepEqual(await (await client.attach(run.ref)).result('file').all(), rows);
      assert.equal(starts, 1, 'attach reads the original saved result without generation');
      await close();
      // Read the exact physical object only after the installed Host closes.
      // The public Ref's digest alone is not evidence of bytes on disk.
      assert.deepEqual(await readFile(join(installation.directory, 'publication', 'objects',
        hash(expected).slice('sha256:'.length))), Buffer.from(expected));
      scratch.passed();
    });
  }
}

test('a new process reads the original public Content without reserializing', async () => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'content-process-', label: 'separate-process Content recovery'});
  const request = {options: {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(scratch.path, 'host'), authorization: authorization()}},
  program: program()};
  const configuration = join(scratch.path, 'request.json');
  // Only synthetic fixture keys enter this owned environment.
  await writeFile(configuration, JSON.stringify(request), {mode: 0o600});
  const driver = fileURLToPath(new URL('./fixtures/content-public-restart.mjs', import.meta.url));
  const execute = async phase => {
    const result = await promisify(execFile)(process.execPath, [driver, configuration, phase],
      {timeout: 30000, killSignal: 'SIGKILL', maxBuffer: 1048576});
    return JSON.parse(result.stdout);
  };
  const created = await execute('create');
  assert.equal(created.starts, 1);
  assert.equal(created.status, 'succeeded');
  await writeFile(configuration, JSON.stringify({...request, ref: created.ref}), {mode: 0o600});
  const restored = await execute('read');
  assert.notEqual(created.pid, restored.pid);
  assert.equal(restored.starts, 0);
  assert.deepEqual(restored.ref, created.ref);
  assert.equal(restored.status, 'succeeded');
  assert.deepEqual(restored.rows, created.rows);
  const expected = Buffer.from('{"id":2,"p":null}\n{"id":1,"p":7}\n');
  assert.equal(restored.rows[0].content.metadata.content_cid, hash(expected));
  assert.deepEqual(await readFile(join(request.options.installation.directory,
    'publication', 'objects', hash(expected).slice('sha256:'.length))), expected);
  scratch.passed();
});

for (const ordered of [false, true]) {
test(`public cancellation after positive input work publishes no Content ordered=${ordered}`, async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'content-cancel-', label: 'public Content cancellation'});
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  const installation = {directory: join(scratch.path, 'host'), authorization: {
    ...authorization(), faultInjection: async (step, detail) => {
      if (step !== 'content_input_identified') return;
      assert.ok(detail.work > 0n, 'original prefix and identity work has actually occurred');
      entered();
      if (!detail.signal.aborted) await new Promise(resolve => {
        detail.signal.addEventListener('abort', resolve, {once: true});
      });
      detail.signal.throwIfAborted();
    },
  }};
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
  let closed = false;
  const close = async () => { if (!closed) { closed = true; await client.close(); } };
  t.after(close);
  const run = await client.startSource(JSON.stringify(program({ordered})), {format: 'json',
    submissionRef: client.newSubmission({nonce: 'content-cancel'})});
  const timeout = AbortSignal.timeout(15000);
  await Promise.race([started, new Promise((_, reject) => {
    timeout.addEventListener('abort', () => reject(timeout.reason), {once: true});
  })]);
  await run.cancel();
  const state = await run.wait({signal: timeout});
  assert.equal(state.status, 'cancelled', inspect(state, {depth: 8}));
  assert.deepEqual(Object.keys(state.result_availability), ['file']);
  assert.equal(state.result_availability.file.state, 'unavailable');
  assert.equal(state.result_availability.file.reason, 'not_published');
  await close();
  await assert.rejects(readFile(join(installation.directory, 'publication', 'objects',
    hash(ordered ? '{"id":1,"p":7}\n{"id":2,"p":null}\n'
      : '{"id":2,"p":null}\n{"id":1,"p":7}\n').slice('sha256:'.length))), {code: 'ENOENT'});
  scratch.passed();
});
}
