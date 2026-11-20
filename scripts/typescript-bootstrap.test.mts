// Execute the canonical private-root preparation recipe with the installed
// compiler. These are fresh source fixtures, not product/runtime acceptance.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import {copyFile, mkdir, mkdtemp, readFile, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import type {TestContext} from 'node:test';
import {prepareCopiedTypeScript} from './copied-typescript-preparation.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
async function fixture(t: TestContext, {linkTools = true}: {linkTools?: boolean} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-ts-bootstrap-'));
  t.after(() => rm(root, {recursive: true}));
  const manifest: unknown = JSON.parse(await readFile(join(repository, 'package.json'), 'utf8'));
  assert(manifest && typeof manifest === 'object' && 'scripts' in manifest);
  const scripts = manifest.scripts;
  assert(scripts && typeof scripts === 'object' && 'prepare' in scripts && 'build:typescript' in scripts);
  assert.equal(typeof scripts.prepare, 'string');
  assert.equal(typeof scripts['build:typescript'], 'string');
  await writeFile(join(root, 'package.json'), JSON.stringify({
    name: 'actql-ts-bootstrap-fixture', version: '0.0.0', private: true, type: 'module',
    scripts: {prepare: scripts.prepare, 'build:typescript': scripts['build:typescript'],
      postprepare: 'node scripts/entry.mjs'},
  }));
  for (const path of ['tsconfig.base.json', 'tsconfig.tooling.json'])
    await copyFile(join(repository, path), join(root, path));
  if (linkTools) await symlink(join(repository, 'node_modules'), join(root, 'node_modules'), 'dir');
  await mkdir(join(root, 'scripts'));
  await writeFile(join(root, 'scripts/entry.mts'), `import {writeFileSync} from 'node:fs';
export const payload: string = 'original';
writeFileSync(new URL('../executed.json', import.meta.url), JSON.stringify({payload, node: process.versions.node}));
`);
  const prepare = () => spawnSync('npm', ['--cache', join(root, 'npm-cache'), 'run', 'prepare'], {
    cwd: root, encoding: 'utf8', timeout: 30_000, maxBuffer: 4 * 1024 * 1024,
    env: {...process.env, npm_config_update_notifier: 'false'},
  });
  return {root, prepare};
}

test('canonical npm preparation emits runnable same-path JavaScript and declarations', async t => {
  const f = await fixture(t);
  // The private root compiler must resolve the actual selected SDK, transport
  // and schema declarations without a second package-local tool installation.
  await writeFile(join(f.root, 'scripts/provider-input.mts'), `
import type {LanguageModelV4} from '@ai-sdk/provider';
import type {PhysicalAcquisitionLimits} from '@actql/provider-ai-sdk';
import type {Client} from 'undici';
import type {EmbeddedLocalOptions} from '@actql/node';
export type OriginalProviderInputs = {
  model: LanguageModelV4; acquisition: PhysicalAcquisitionLimits; client: Client;
  local: EmbeddedLocalOptions;
};
`);
  const result = f.prepare();
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert(existsSync(join(f.root, 'scripts/entry.mjs')));
  assert(existsSync(join(f.root, 'scripts/entry.d.mts')));
  assert(existsSync(join(f.root, 'scripts/provider-input.d.mts')));
  assert.deepEqual(JSON.parse(await readFile(join(f.root, 'executed.json'), 'utf8')),
    {payload: 'original', node: process.versions.node});
});

test('strict preparation failure cannot execute a stale ignored output in the next lifecycle', async t => {
  const f = await fixture(t), first = f.prepare();
  assert.equal(first.status, 0, first.stdout + first.stderr);
  const output = await readFile(join(f.root, 'scripts/entry.mjs'));
  await rm(join(f.root, 'executed.json'));
  await writeFile(join(f.root, 'scripts/entry.mts'),
    'export const payload: string = 7;\nexport const unchecked = value => value;\n');
  const failed = f.prepare();
  assert.equal(failed.error, undefined);
  assert.equal(failed.signal, null);
  assert.notEqual(failed.status, 0);
  assert.match(failed.stdout + failed.stderr, /TS2322/u);
  assert.match(failed.stdout + failed.stderr, /TS7006/u);
  assert.deepEqual(await readFile(join(f.root, 'scripts/entry.mjs')), output,
    'The previous output remains present; a failed prerequisite must not execute it');
  assert.equal(existsSync(join(f.root, 'executed.json')), false);
});


// Exercise the actual copied-source prerequisite with the same canonical build
// recipe and installed compiler; no Core/Common/package producer is invoked.
const copiedCommand: Parameters<typeof prepareCopiedTypeScript>[0]['run'] =
  (command, args, cwd, env, timeout) => {
    const result = spawnSync(command, args, {cwd, env, timeout,
      encoding: 'utf8', maxBuffer: 4 * 1024 * 1024});
    if (result.error) throw result.error;
    if (result.signal !== null || result.status !== 0)
      throw new Error(result.stdout + result.stderr);
  };

test('copied Source emits at its own paths before a later consumer enters', async t => {
  const f = await fixture(t, {linkTools: false});
  assert.equal(existsSync(join(f.root, 'scripts/entry.mjs')), false);
  await prepareCopiedTypeScript({source: repository, root: f.root,
    environment: process.env, run: copiedCommand});
  assert(existsSync(join(f.root, 'scripts/entry.mjs')));
  assert(existsSync(join(f.root, 'scripts/entry.d.mts')));
  assert.equal(existsSync(join(f.root, 'executed.json')), false,
    'Compiler preparation does not execute the emitted consumer');
  const result = spawnSync(process.execPath, ['scripts/entry.mjs'], {
    cwd: f.root, encoding: 'utf8', timeout: 10_000});
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.deepEqual(JSON.parse(await readFile(join(f.root, 'executed.json'), 'utf8')),
    {payload: 'original', node: process.versions.node});
});

test('copied Source compiler failure prevents prepack with stale emit and preserves the original failure', async t => {
  const f = await fixture(t, {linkTools: false});
  const stale = 'throw new Error("stale consumer must not execute");\n';
  await writeFile(join(f.root, 'scripts/entry.mjs'), stale);
  await writeFile(join(f.root, 'scripts/entry.mts'), 'export const payload: string = 7;\n');
  let original: unknown, enteredPrepack = false;
  await assert.rejects((async () => {
    await prepareCopiedTypeScript({source: repository, root: f.root,
      environment: process.env, run(...args) {
        try {return copiedCommand(...args);}
        catch (failure) {original = failure; throw failure;}
      }});
    enteredPrepack = true;
  })(), failure => {
    assert.ok(failure instanceof Error);
    assert.equal(failure, original);
    assert.match(failure.message, /TS2322/u);
    return true;
  });
  assert.equal(enteredPrepack, false);
  assert.equal(await readFile(join(f.root, 'scripts/entry.mjs'), 'utf8'), stale);
  assert.equal(existsSync(join(f.root, 'executed.json')), false);
});
