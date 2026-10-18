import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, symlink, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));

// The canonical ordinary Local image/runtime prerequisites must be prepared
// from this source. No replacement Common, Host, scope, issuer or SQLite port
// is supplied. These cases initialize control only: they dispatch no Run,
// metadata request, Source, Model, Content, signing or Provider operation.
async function actualHost(body) {
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'finite-initial-host-', label: 'original selected initial Host'});
  await mkdir(join(scratch.path, 'node_modules/@actql'), {recursive: true});
  for (const name of ['node', 'local-node', 'sdk', 'client-wire']) {
    await symlink(join(root, 'packages', name), join(scratch.path, 'node_modules/@actql', name));
  }
  const entry = join(scratch.path, 'entry.mjs');
  await writeFile(entry, 'import assert from "node:assert/strict";\n' +
    'import {open} from "@actql/node";\n' + body);
  const result = spawnSync(process.execPath, ['--no-lazy', '--require',
    '@actql/node/selected-infer-startup', entry], {
    cwd: scratch.path, env: {PATH: process.env.PATH}, encoding: 'utf8',
    timeout: 120000, maxBuffer: 1024 * 1024});
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'initial-control-closed');
  scratch.passed();
}

test('the selected original undefined input reaches one actual Host and closes its own control children', async () => {
  await actualHost([
    'const client = await open();',
    'assert.equal(client.info.stateDir, process.cwd()+"/.actql");',
    'assert.equal(typeof client.close,"function");',
    'await client.close();',
    // Retiring this Host never replenishes the process/module/native domain.
    'await assert.rejects(open(),{code:"NodeInitialControlInputUnavailable"});',
    'console.log("initial-control-closed");',
  ].join('\n'));
});

test('unsupported caller objects refuse before traps without consuming the supported original generation', async () => {
  await actualHost([
    'let reads=0;',
    'const raw=new Proxy({}, {get(){reads++;throw new Error("RawGet");},ownKeys(){reads++;throw new Error("RawKeys");}});',
    'await assert.rejects(open(raw),{code:"NodeInitialControlInputUnavailable"});',
    'assert.equal(reads,0);',
    'const client=await open(); await client.close();',
    'console.log("initial-control-closed");',
  ].join('\n'));
});
