// npm file selection only. This metadata check deliberately does not execute
// prepack and cannot qualify a normal package, runtime or outside-checkout use.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import ts from 'typescript';

test('SDK npm file selection keeps executable emit and declarations without maintained TS sources', async t => {
  const cache = await mkdtemp(join(tmpdir(), 'actql-ts-pack-selection-'));
  t.after(() => rm(cache, {recursive: true}));
  const result = spawnSync('npm', ['pack', '--dry-run', '--json', '--ignore-scripts', '--cache', cache], {
    cwd: fileURLToPath(new URL('../packages/sdk/', import.meta.url)),
    encoding: 'utf8', timeout: 30_000, maxBuffer: 4 * 1024 * 1024,
    env: {...process.env, npm_config_update_notifier: 'false'},
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  const report: unknown = JSON.parse(result.stdout);
  assert(Array.isArray(report) && report.length === 1);
  const item: unknown = report[0];
  assert(item && typeof item === 'object' && 'files' in item && Array.isArray(item.files));
  const files = new Set(item.files.map((file: unknown) => {
    assert(file && typeof file === 'object' && 'path' in file && typeof file.path === 'string');
    return file.path;
  }));
  for (const required of ['index.mjs', 'index.d.mts', 'host-port.mjs', 'host-port.d.mts',
    'loopback-http.mjs', 'loopback-http-unavailable.mjs', 'internal/data.mjs', 'internal/data.d.mts', 'internal/README.md']) {
    assert(files.has(required), `Missing installed SDK member: ${required}`);
  }
  for (const path of files) {
    assert(!/\.[cm]?tsx?$/u.test(path) || /\.d\.[cm]?ts$/u.test(path),
      `Maintained TypeScript source entered the installed package: ${path}`);
    assert(!/\.test\.[cm]?[jt]s$/u.test(path), `Test entered the installed SDK: ${path}`);
  }
});

test('required client typecheck includes every tracked SDK and Wire type fixture', async () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const manifest: unknown = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
  assert(manifest && typeof manifest === 'object' && 'scripts' in manifest);
  const scripts = manifest.scripts;
  assert(scripts && typeof scripts === 'object' && 'check:client-types' in scripts);
  assert.equal(scripts['check:client-types'], 'tsc --project tsconfig.client-types.json');
  const config = ts.getParsedCommandLineOfConfigFile(join(root, 'tsconfig.client-types.json'), {}, {
    ...ts.sys,
    onUnRecoverableConfigFileDiagnostic(diagnostic) {
      assert.fail(ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'));
    },
  });
  assert(config);
  assert.deepEqual(config.errors, []);
  assert.equal(config.options.strict, true);
  assert.equal(config.options.noEmit, true);
  const tracked = spawnSync('git', ['ls-files', '-z', '--', 'packages/sdk', 'packages/client-wire'], {
    cwd: root, encoding: 'utf8', timeout: 5_000,
  });
  assert.equal(tracked.status, 0, tracked.stderr);
  const fixtures = tracked.stdout.split('\0').filter(path => /\.typecheck\.[cm]?tsx?$/u.test(path));
  assert(fixtures.includes('packages/sdk/run-wait-since.typecheck.mts'));
  assert(fixtures.includes('packages/sdk/public-aql-format.typecheck.mts'));
  const roots = new Set(config.fileNames);
  assert.deepEqual(fixtures.filter(path => !roots.has(resolve(root, path))), []);
});
