// Real source-checkout SDK/Host/Common/SQLite and normal native Local Files.
// No forged Content, operation extent, Resource grant or replacement owner.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {access, mkdir, readFile, stat, writeFile} from 'node:fs/promises';
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

test('ordinary Project STORE retains its approved bytes and exact Result through separate-process Saved',
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
      const run = await step('start original STORE', () => client.startSource(source, {format: 'sql'}));
      assert.equal((await step('await Preview', () => run.wait({signal: AbortSignal.timeout(15_000)}))).status,
        'waiting_checkpoint');
      await assert.rejects(access(join(data, 'copy.jsonl')), {code: 'ENOENT'});
      const checkpoint = (await client.checkpoints()).items.find(value => value.kind === 'effect_set');
      assert(checkpoint);
      const resolved = await step('approve exact checkpoint', () => client.resolveCheckpoints([
        {checkpoint, decision: 'approved'}], {signer: {keyId: 'reviewer', reviewerId: 'reviewer',
        authorityScopeCid: run.ref.authorityScopeCid, sign: bytes => sign(null, bytes, keys.privateKey)}}));
      assert.equal(resolved.results[0].status, 'committed');
      phase = 'resume original Run';
      const signal = AbortSignal.timeout(15_000); let state;
      do {
        state = await run.status({signal});
        if (!['waiting_checkpoint', 'resuming', 'running'].includes(state.status)) break;
        await delay(20, undefined, {signal});
      } while (true);
      assert.equal(state.status, 'succeeded', inspect(state));
      const rows = await step('read exact authored Result', () => run.result('answer').all());
      assert.equal(rows.length, 1); assert.equal(rows[0].name, 'one.jsonl');
      const expected = Buffer.from('{"id":1}\n');
      assert.deepEqual(await readFile(join(data, 'copy.jsonl')), expected);
      assert.equal(rows[0].content.metadata.content_cid,
        'sha256:' + createHash('sha256').update(expected).digest('hex'));
      const before = await stat(join(data, 'copy.jsonl'), {bigint: true});
      await writeFile(join(directory, 'saved.json'), JSON.stringify({options, ref: run.ref, rows}), {mode: 0o600});
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
            assert.equal((await run.status()).status, 'succeeded');
            assert.deepEqual(await run.result('answer').all(), saved.rows);
          } finally {await client.close();}
        `], {cwd: directory, timeout: 20_000}));
      const after = await stat(join(data, 'copy.jsonl'), {bigint: true});
      assert.deepEqual([after.dev, after.ino, after.size, after.mtimeNs],
        [before.dev, before.ino, before.size, before.mtimeNs], 'Saved must not rewrite the file');
      assert.deepEqual(await readFile(join(data, 'copy.jsonl')), expected);
    } catch (cause) {
      primary = cause;
      t.diagnostic(JSON.stringify({phase, code: cause.code, failure: inspect(cause, {depth: 5})}));
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
