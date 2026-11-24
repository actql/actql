// Execute the canonical private-root preparation recipe with the installed
// compiler. These are fresh source fixtures, not product/runtime acceptance.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import {chmod, copyFile, mkdir, mkdtemp, readFile, realpath, rm, stat, symlink, writeFile} from 'node:fs/promises';
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
  await copyFile(join(repository, 'scripts/typescript-executable-modes.mts'),
    join(root, 'scripts/typescript-executable-modes.mts'));
  await writeFile(join(root, 'scripts/entry.mts'), `#!/usr/bin/env node
import {writeFileSync} from 'node:fs';
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
  await chmod(join(f.root, 'scripts/entry.mts'), 0o755);
  const result = f.prepare();
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert(existsSync(join(f.root, 'scripts/entry.mjs')));
  assert(existsSync(join(f.root, 'scripts/entry.d.mts')));
  assert(existsSync(join(f.root, 'scripts/provider-input.d.mts')));
  assert.equal((await stat(join(f.root, 'scripts/entry.mjs'))).mode & 0o111,
    (await stat(join(f.root, 'scripts/entry.mts'))).mode & 0o111);
  if (process.platform !== 'win32') {
    await rm(join(f.root, 'executed.json'));
    const direct = spawnSync(join(f.root, 'scripts/entry.mjs'), [], {
      cwd: f.root, encoding: 'utf8', timeout: 10_000});
    assert.equal(direct.error, undefined);
    assert.equal(direct.signal, null);
    assert.equal(direct.status, 0, direct.stdout + direct.stderr);
  }
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
  const localNode = 'packages/local-node';
  await mkdir(join(f.root, localNode), {recursive: true});
  for (const path of ['package.json', 'observation.d.ts']) {
    await copyFile(join(repository, localNode, path), join(f.root, localNode, path));
  }
  await writeFile(join(f.root, 'scripts/observation.mts'), `
import type {HostObservationConnection as Published} from '@actql/local-node/observation';
import type {HostObservationConnection as Local} from '../packages/local-node/observation.js';
export const connection = (value: Published): Local => value;
`);
  assert.equal(existsSync(join(f.root, 'scripts/entry.mjs')), false);
  await prepareCopiedTypeScript({source: repository, root: f.root,
    environment: process.env, run: copiedCommand});
  assert.equal(await realpath(join(f.root, 'node_modules/@actql/local-node')),
    await realpath(join(f.root, localNode)));
  assert.equal(existsSync(join(f.root, 'node_modules/@actql/otel-node')), false);
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

test('artifact source switch discards old emit and prepares the selected Git source', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-ts-artifact-source-'));
  t.after(() => rm(root, {recursive: true}));
  const environment: NodeJS.ProcessEnv = {...process.env, npm_config_offline: 'true', npm_config_audit: 'false',
    npm_config_update_notifier: 'false'};
  const run = (file: string, args: readonly string[], env = environment) => spawnSync(file, args, {
    cwd: root, env, encoding: 'utf8', timeout: 30_000, maxBuffer: 4 * 1024 * 1024,
  });
  const checked = (file: string, args: readonly string[], env = environment) => {
    const result = run(file, args, env);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    return result.stdout.trim();
  };
  const git = (...args: string[]) => checked('git', args);
  const commit = (message: string) => {
    git('add', '-A');
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
      'commit', '--quiet', '-m', message);
    return git('rev-parse', 'HEAD');
  };
  const helper = join(repository, 'scripts/ci-checkout-artifact-source.sh');
  const tools = await mkdtemp(join(tmpdir(), 'actql-ts-artifact-tools-'));
  t.after(() => rm(tools, {recursive: true}));
  await writeFile(join(tools, 'npm'), `#!/bin/sh
if [ "\${GITHUB_TOKEN+x}" = x ]; then
  echo "Artifact verification token reached the selected npm process" >&2
  exit 97
fi
exec "$ACTQL_FIXTURE_NPM" "$@"
`, {mode: 0o755});
  const checkoutEnvironment = {...environment, PATH: `${tools}:${environment.PATH ?? ''}`,
    ACTQL_FIXTURE_NPM: checked('which', ['npm']), GITHUB_TOKEN: 'synthetic-verification-token'};
  git('init', '--quiet');
  await mkdir(join(root, 'scripts'));
  await writeFile(join(root, '.gitignore'), '/scripts/stale.mjs\n/scripts/stale.d.mts\n/keep.mjs\n');
  await writeFile(join(root, 'scripts/entry.mjs'), "console.log('original JS');\n");
  const legacy = commit('Legacy JavaScript source');
  await rm(join(root, 'scripts/entry.mjs'));
  await writeFile(join(root, '.gitignore'),
    '/scripts/entry.mjs\n/scripts/entry.d.mts\n/scripts/stale.mjs\n/scripts/stale.d.mts\n/keep.mjs\n');
  const compiler = join(repository, 'node_modules/typescript/bin/tsc');
  const project = {compilerOptions: {module: 'NodeNext', strict: true, noEmitOnError: true, declaration: true},
    include: ['scripts/*.mts']};
  await writeFile(join(root, 'tsconfig.tooling.json'), JSON.stringify(project));
  await writeFile(join(root, 'package.json'), JSON.stringify({name: 'bootstrap-fixture', version: '1.0.0',
    scripts: {'build:typescript': `${JSON.stringify(process.execPath)} ${JSON.stringify(compiler)} --project tsconfig.tooling.json`}}));
  await writeFile(join(root, 'package-lock.json'), JSON.stringify({name: 'bootstrap-fixture', version: '1.0.0',
    lockfileVersion: 3, requires: true, packages: {'': {name: 'bootstrap-fixture', version: '1.0.0'}}}));
  await writeFile(join(root, 'scripts/entry.mts'), "const value: string = 'selected TS'; console.log(value);\n");
  const selected = commit('TypeScript source selected by the artifact');
  await writeFile(join(root, 'scripts/entry.mts'), "const value: string = 7; console.log(value);\n");
  const invalid = commit('TypeScript source with a compiler failure');
  await writeFile(join(root, 'scripts/entry.mts'), "const value: string = 'controller'; console.log(value);\n");
  await writeFile(join(root, 'scripts/stale.mts'), "export const controllerOnly = true;\n");
  const controller = commit('Controller with an extra emitted module');
  checked('npm', ['run', 'build:typescript']);
  await writeFile(join(root, 'keep.mjs'), '// unrelated ignored file\n');
  assert(existsSync(join(root, 'scripts/stale.mjs')));
  assert(existsSync(join(root, 'scripts/stale.d.mts')));

  checked('bash', [helper, controller], checkoutEnvironment);
  assert.equal(checked(process.execPath, ['scripts/entry.mjs']), 'controller');
  checked('bash', [helper, selected], checkoutEnvironment);
  assert.equal(git('rev-parse', 'HEAD'), selected);
  assert.equal(checked(process.execPath, ['scripts/entry.mjs']), 'selected TS');
  assert.equal(existsSync(join(root, 'scripts/stale.mjs')), false);
  assert.equal(existsSync(join(root, 'scripts/stale.d.mts')), false);
  assert(existsSync(join(root, 'scripts/entry.d.mts')));

  const refused = run('bash', [helper, invalid], checkoutEnvironment);
  assert.notEqual(refused.status, 0);
  assert.match(refused.stdout + refused.stderr, /TS2322/u);
  assert.equal(git('rev-parse', 'HEAD'), invalid);
  assert.equal(existsSync(join(root, 'scripts/entry.mjs')), false);

  checked('bash', [helper, legacy], checkoutEnvironment);
  assert.equal(git('rev-parse', 'HEAD'), legacy);
  assert.equal(checked(process.execPath, ['scripts/entry.mjs']), 'original JS');
  assert.equal(await readFile(join(root, 'keep.mjs'), 'utf8'), '// unrelated ignored file\n');
  assert.equal(git('status', '--porcelain'), '');
});
