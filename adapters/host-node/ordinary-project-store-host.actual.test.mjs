// Real source-checkout SDK/Host/Common/SQLite and normal native Local Files.
// No forged Content, operation extent, Resource grant or replacement owner.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {access, mkdir, readFile, readdir, stat, writeFile} from 'node:fs/promises';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {inspect, promisify} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const execute = promisify(execFile);
const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
const source = "SELECT 1 AS id |> SERIALIZE FORMAT JSONL ORDER BY id OPTIONS (name = 'one.jsonl') " +
  "|> RESULT answer |> EFFECT STORE local.files SET (path = 'copy.jsonl', content = content)";

// Equivalent public authored JSON uses the same installed Command and actual
// Content family. Keep the SQL cases above/below: this isolates lowering cost,
// not a replacement runtime, request or authority.
const jsonSource = JSON.stringify({version: 'actql/0.1', id: 'ordinary-store-json', stages: [{
  id: 'source', inputs: {}, steps: [
    {values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}, as: 'selected'},
    {serialize: {format: 'jsonl', fields: ['id'], name: 'one.jsonl', preserve_order: true}, as: 'attachment'},
  ], results: {answer: {from: 'attachment', fields: ['content', 'name', 'media_type', 'size_bytes', 'row_count']}},
  effects: {save: {command: {contract: 'command:local.local.files.store.v1',
    target: {published_store: {target_ref: 'connector://local/files', mapping_ref: 'mapping:local.local.files.store.v1'}},
    from: {result: 'answer'}, input: {path: {literal: 'copy.jsonl'}, content: {field: 'content'}}}}},
}], results: {answer: {from: {stage: 'source', result: 'answer'}}}});

for (const variant of [
  {name: 'approved JSON one-row', decision: 'approved', source: jsonSource, format: 'json', bytes: '{"id":1}\n'},
  {name: 'approved JSON empty input', decision: 'approved',
    source: jsonSource.replace('"rows":[{"id":1}]', '"rows":[]'), format: 'json', bytes: ''},
  {name: 'approved JSON multirow single file', decision: 'approved',
    source: jsonSource.replace('"rows":[{"id":1}]', '"rows":[{"id":1},{"id":2},{"id":3}]'),
    format: 'json', bytes: '{"id":1}\n{"id":2}\n{"id":3}\n'},
  {name: 'signed JSON rejection', decision: 'rejected', source: jsonSource, format: 'json'},
  {name: 'approved one-row', decision: 'approved', source, bytes: '{"id":1}\n'},
  {name: 'approved multirow single file', decision: 'approved',
    source: source.replace('SELECT 1 AS id', 'SELECT id FROM (SELECT 3 AS id UNION ALL SELECT 1 AS id UNION ALL SELECT 2 AS id)'),
    bytes: '{"id":1}\n{"id":2}\n{"id":3}\n'},
  {name: 'approved empty input', decision: 'approved', source: source.replace('SELECT 1 AS id', 'SELECT 1 AS id WHERE FALSE'), bytes: ''},
  {name: 'signed rejection', decision: 'rejected', source},
]) test(`ordinary Project STORE ${variant.name} closes and preserves exact separate-process Saved without resend`,
  {timeout: 90_000}, async t => {
    const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
      prefix: 'ordinary-project-store-', label: 'ordinary Project STORE'});
    const directory = scratch.path, data = join(directory, 'data');
    await mkdir(data);
    await writeFile(join(directory, 'actql.config.json'), JSON.stringify({version: 'actql-config/0.1',
      connectors: 'connectors.json'}));
    await writeFile(join(directory, 'connectors.json'), JSON.stringify({version: 'actql-connectors/0.1',
      connections: {local: {connector: 'local', root: './data', tables: {}}}}));
    const keys = generateKeyPairSync('ed25519');
    // Explicit test-operator configuration. No product Account is changed.
    const authorization = {accountConfiguration: JSON.stringify({
      version: 'actql-execution-account-config/0.1', account_id: 'ordinary-project-store', entries: [
        {entry_id: 'effect-review', outcome: 'delegate', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {any_of: ['effect']}, exclusions: []},
        {entry_id: 'read-write', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {any_of: ['read', 'write']}, exclusions: []},
      ]}), hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}]};
    const options = {mode: 'local', owner: 'local', installation: {
      directory: join(directory, 'host'), authorization,
      // Source-free generation needs the original explicit unknown-provenance
      // policy. This is not an Effect permission or a capacity allowance.
      resultDataPolicy: {kind: 'data_policy', wire: policyWire,
        cid: 'sha256:' + createHash('sha256').update(policyWire).digest('hex')},
    }};
    let client, phase = 'connect', primary;
    const previous = process.cwd(); process.chdir(directory);
    const step = async (name, operation) => {
      phase = name; const value = await operation(); t.diagnostic(`${name}: passed`); return value;
    };
    t.diagnostic(JSON.stringify({directory}));
    try {
      client = await step('connect ordinary Project Host', () => connectEmbeddedLocal(options));
      const run = await step('start original STORE', () => client.startSource(variant.source, {format: variant.format ?? 'sql'}));
      const previewState = await step('await Preview', () => run.wait({signal: AbortSignal.timeout(15_000)}));
      assert.equal(previewState.status, 'waiting_checkpoint', inspect(previewState, {depth: 4}));
      await assert.rejects(access(join(data, 'copy.jsonl')), {code: 'ENOENT'});
      const checkpoint = (await client.checkpoints()).items.find(value => value.kind === 'effect_set');
      assert(checkpoint);
      const resolved = await step(`${variant.decision} exact checkpoint`, () => client.resolveCheckpoints([
        {checkpoint, decision: variant.decision}], {signer: {keyId: 'reviewer', reviewerId: 'reviewer',
        authorityScopeCid: run.ref.authorityScopeCid, sign: bytes => sign(null, bytes, keys.privateKey)}}));
      assert.equal(resolved.results[0].status, 'committed');
      phase = 'resume original Run';
      const signal = AbortSignal.timeout(15_000); let state;
      do {
        state = await run.status({signal});
        if (!['waiting_checkpoint', 'resuming', 'running'].includes(state.status)) break;
        await delay(20, undefined, {signal});
      } while (true);
      const expectedStatus = variant.decision === 'approved' ? 'succeeded' : 'cancelled';
      assert.equal(state.status, expectedStatus, inspect(state));
      let rows, before;
      const expected = Buffer.from(variant.bytes ?? '');
      if (expectedStatus === 'succeeded') {
        rows = await step('read exact authored Result', () => run.result('answer').all());
        assert.equal(rows.length, 1); assert.equal(rows[0].name, 'one.jsonl');
        assert.deepEqual(await readFile(join(data, 'copy.jsonl')), expected);
        assert.equal(rows[0].content.metadata.content_cid,
          'sha256:' + createHash('sha256').update(expected).digest('hex'));
        before = await stat(join(data, 'copy.jsonl'), {bigint: true});
      } else await assert.rejects(access(join(data, 'copy.jsonl')), {code: 'ENOENT'});
      await writeFile(join(directory, 'saved.json'), JSON.stringify({options, ref: run.ref, rows, expectedStatus}), {mode: 0o600});
      await step('close original Host', () => client.close()); client = undefined;
      const hostUrl = new URL('./embedded-local.mjs', import.meta.url).href;
      await step('separate-process Saved reads same Result', () => execute(process.execPath,
        ['--input-type=module', '-e', `
          import assert from 'node:assert/strict';
          import {readFile} from 'node:fs/promises';
          const {connectEmbeddedLocal} = await import(${JSON.stringify(hostUrl)});
          const saved = JSON.parse(await readFile('saved.json'));
          const client = await connectEmbeddedLocal(saved.options);
          try {
            const run = await client.attach(saved.ref);
            assert.equal((await run.status()).status, saved.expectedStatus);
            if (saved.expectedStatus === 'succeeded') assert.deepEqual(await run.result('answer').all(), saved.rows);
          } finally {await client.close();}
        `], {cwd: directory, timeout: 20_000}));
      if (expectedStatus === 'succeeded') {
        const after = await stat(join(data, 'copy.jsonl'), {bigint: true});
        assert.deepEqual([after.dev, after.ino, after.size, after.mtimeNs],
          [before.dev, before.ino, before.size, before.mtimeNs], 'Saved must not rewrite the file');
        assert.deepEqual(await readFile(join(data, 'copy.jsonl')), expected);
      }
      assert.deepEqual(await readdir(data), expectedStatus === 'succeeded' ? ['copy.jsonl'] : [],
        'closed writers leave no temporary files and rejected/Saved Runs never write');
    } catch (cause) {
      primary = cause;
      t.diagnostic(JSON.stringify({phase, code: cause.code, failure: inspect(cause, {depth: 5})}));
      if (cause.code === 'SubmissionUnknown' && cause.submissionRef !== undefined) {
        // Observe only this exact intent; a failed acknowledgement never
        // authorizes a second startSource or replacement business Run.
        const observed = await client.lookupSubmission(cause.submissionRef);
        t.diagnostic(`original submission lookup: ${inspect(observed, {depth: 2})}`);
        await assert.rejects(access(join(data, 'copy.jsonl')), {code: 'ENOENT'});
      }
    } finally {
      try {await client?.close();}
      catch (cause) {primary = primary === undefined ? cause : new AggregateError([primary, cause],
        'Original STORE and Host cleanup failed');}
      process.chdir(previous);
    }
    if (primary !== undefined) throw primary;
    await assert.rejects(access(join(directory, 'host/publication/owner/owner.json')), {code: 'ENOENT'});
    scratch.passed();
  });
