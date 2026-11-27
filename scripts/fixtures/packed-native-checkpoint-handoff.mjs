// Ordinary installed Node client, Native CLI, and one original HTTPS Host.
// The fixture signer builds an answer only; the CLI must submit it first.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {promisify} from 'node:util';
import {connect, signCheckpointAnswer} from '@actql/node';
import {publishEffect} from '@actql/local-node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {runInstalledEffectInventoryAcceptance} from './installed-effect-inventory-acceptance.mjs';

const launcher = process.argv[2];
assert(launcher);
const library = process.argv[3] ?? 'libcurl.so.4';
const handoff = await mkdtemp(join(tmpdir(), 'actql-checkpoint-handoff-'));
const run = promisify(execFile);
try {
  await writeFile(join(handoff, 'connection.json'), JSON.stringify({
    mode: 'remote', owner: 'remote', durability: 'durable', consentRefs: [], runners: [],
  }), {flag: 'wx', mode: 0o600});
  let wire;
  async function command({endpoint, caPath, token}, args) {
    const tokenFile = token === 'synthetic-reviewer-token' ? 'reviewer.txt' : 'owner.txt';
    await writeFile(join(handoff, tokenFile), token + '\n', {mode: 0o600});
    return (await run(launcher, ['--mode', 'remote', '--endpoint', endpoint,
      '--connection-root', handoff, '--connection-file', 'connection.json',
      '--token-root', handoff, '--token-file', tokenFile, '--http-library', library,
      // The shared test listener authenticates the two distinct Account roles
      // with fixture bearer tokens. The CLI requires certificate file options
      // even when this listener does not require a client certificate.
      '--ca', caPath, '--cert', join(dirname(caPath), 'resource.crt'),
      '--key', join(dirname(caPath), 'resource.key'), ...args],
    {cwd: handoff, timeout: 30_000, maxBuffer: 64 * 1024})).stdout;
  }
  const result = await runInstalledEffectInventoryAcceptance({connect, publishEffect,
    openInstalledRemoteHttpHost, profile: 'cli-handoff', cliHandoff: {
      sign: (checkpoint, signer) => signCheckpointAnswer(checkpoint, 'approved', signer),
      async resolve({answer, ...options}) {
        if (wire === undefined) {
          wire = JSON.stringify(answer);
          await writeFile(join(handoff, 'answer.json'), wire, {flag: 'wx', mode: 0o600});
        } else assert.equal(JSON.stringify(answer), wire, 'Replay the original signed bytes');
        return JSON.parse(await command(options, ['resolve', '--signed-answer-file', 'answer.json']));
      },
      async observe({runRef, operation, ...options}) {
        const ref = 'run.json';
        await writeFile(join(handoff, ref), JSON.stringify(runRef), {mode: 0o600});
        if (operation === 'status') return JSON.parse(await command(options, ['status', '--ref-file', ref]));
        const stdout = await command(options, ['read', '--ref-file', ref,
          '--result-name', 'answer', '--attempt-id', 'original-sdk-run-cold-read']);
        return stdout.trimEnd().split('\n').map(JSON.parse);
      },
    }});
  await writeFile('native-checkpoint-handoff.json', JSON.stringify(result, null, 2) + '\n',
    {flag: 'wx', mode: 0o600});
} finally {
  await rm(handoff, {recursive: true, force: true});
}
