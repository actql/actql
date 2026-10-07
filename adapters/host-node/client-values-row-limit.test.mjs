import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';

const expected = JSON.parse(await readFile(new URL('./fixtures/read-121.expected.json', import.meta.url), 'utf8'));
const fixture = fileURLToPath(new URL('./client-values-row-limit.fixture.mjs', import.meta.url));

async function invoke(directory, facts, phase) {
  try {
    const log = execFileSync(process.execPath, [fixture, JSON.stringify(facts)], {timeout: 20000, stdio: 'pipe', encoding: 'utf8'});
    await writeFile(join(directory, `${phase}.log`), log);
  } catch (error) {
    const log = `${error.stdout ?? ''}\n${error.stderr ?? ''}`;
    await writeFile(join(directory, `${phase}.log`), log);
    throw new Error(`${error.code ?? 'InstalledReadFailed'}: ${log}`, {cause: error});
  }
}

test('invalid explicit row configurations are refused before installing a Host', async () => {
  for (const valuesMaxRows of [null, 0, -1, 1.5, 10001, NaN, Infinity, '121']) {
    await assert.rejects(connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {valuesMaxRows}}), {message: 'InvalidLocalValuesRowLimit'});
    await assert.rejects(openInstalledRemoteHttpHost({directory: '/unused',
      authenticate: () => 'principal', valuesMaxRows}), {message: 'InvalidLocalValuesRowLimit'});
  }
});

for (const entrance of ['local', 'https']) {
  test(`${entrance}: installed explicit row capacity publishes 121 rows and restores the original Run under current defaults`,
    {timeout: 40000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-installed-read-121-', label: `${entrance} installed row capacity`});
      const directory = scratch.path;
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
      const output = join(directory, 'initial.json');
      await invoke(directory, {directory, entrance, output}, 'initial');
      const initial = JSON.parse(await readFile(output, 'utf8'));
      assert.equal(initial.status.status, 'succeeded');
      assert.equal(initial.computes, 1);
      assert.deepEqual(initial.rows, expected);
      assert.equal(initial.readState, 'complete');
      assert.equal(initial.attempt.record.state, 'succeeded');
      assert.notEqual(initial.attempt.hostReleaseReceipt, null);
      assert.deepEqual(initial.description.columns, [{name: 'id', contract: {type: 'number', nullable: false}}]);
      const restoredOutput = join(directory, 'restored.json');
      await invoke(directory, {directory, entrance,
        output: restoredOutput, ref: initial.ref}, 'restored');
      const restored = JSON.parse(await readFile(restoredOutput, 'utf8'));
      assert.deepEqual(restored.ref, initial.ref);
      assert.deepEqual(restored.request.ref, initial.ref);
      assert.equal(restored.status.status, 'succeeded');
      assert.equal(restored.computes, 0);
      assert.deepEqual(restored.rows, expected);
      assert.equal(restored.readState, 'complete');
      assert.notEqual(restored.attempt.attempt.attempt_id, initial.attempt.attempt.attempt_id);
      assert.equal(restored.attempt.record.state, 'succeeded');
      assert.notEqual(restored.attempt.hostReleaseReceipt, null);
      console.log('INSTALLED_READ_121_EVIDENCE', JSON.stringify({directory, entrance,
        ref: initial.ref, rows: expected.length, initialComputes: initial.computes,
        restoredComputes: restored.computes}));
      scratch.passed();
    });
}
