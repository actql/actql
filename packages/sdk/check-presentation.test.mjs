import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';

test('SDK package inventory includes its current check translation module', t => {
  const cache = mkdtempSync(join(tmpdir(), 'actql-sdk-presentation-'));
  t.after(() => rmSync(cache, {recursive: true}));
  const result = JSON.parse(execFileSync('npm', ['pack', '--dry-run', '--json', '--cache', cache], {
    cwd: fileURLToPath(new URL('./', import.meta.url)), encoding: 'utf8', timeout: 30000,
    stdio: ['ignore', 'pipe', 'pipe'],
  }));
  // npm can key workspace reports by package name instead of returning a list.
  const packages = Array.isArray(result) ? result : Object.values(result);
  assert.equal(packages.length, 1);
  assert.equal(packages[0].name, '@actql/sdk');
  assert.equal(packages[0].files.filter(file => file.path === 'check-presentation.mjs').length, 1);
  assert.equal(packages[0].files.filter(file => file.path === 'operation-presentation.mjs').length, 1);
  assert.equal(packages[0].files.filter(file => file.path === 'json-value-wire.generated.mjs').length, 1);
  assert.equal(packages[0].files.some(file => file.path.endsWith('.test.mjs')), false);
});

test('browser SDK consumer localizes a pinned Problem without I/O or input custody', async t => {
  mock.method(globalThis, 'fetch', () => { throw new Error('UnexpectedPresentationNetwork'); });
  t.after(() => mock.restoreAll());
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const bundle = buildSync({absWorkingDir: root, entryPoints: ['packages/sdk/index.mjs'],
    // Shared node_modules may link another worktree; check this source's wire.
    alias: {'@actql/client-wire': join(root, 'packages/client-wire/index.mjs')},
    bundle: true, platform: 'browser', format: 'esm', target: 'es2022',
    write: false, metafile: true});
  assert.deepEqual(Object.keys(bundle.metafile.inputs).sort(), [
    'packages/client-wire/client-host.generated.js',
    'packages/client-wire/index.mjs',
    'packages/client-wire/publication.generated.js',
    'packages/sdk/check-presentation.mjs',
    'packages/sdk/checkpoints.mjs',
    'packages/sdk/index.mjs',
    'packages/sdk/json-value-wire.generated.mjs',
    'packages/sdk/operation-presentation.mjs',
  ]);
  assert(Object.values(bundle.metafile.outputs).every(output => output.imports.length === 0));
  const sdk = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].contents).toString('base64')}`);
  const outcome = JSON.parse(readFileSync(new URL('../client-wire/fixtures/check-reporting-failure.json', import.meta.url), 'utf8'));
  const original = JSON.stringify(outcome);
  const explanation = sdk.explainCheckOutcome(outcome, {locale: 'ja'});
  assert.equal(explanation.outcome, 'failed');
  assert.equal(explanation.summary, '報告用の予算内では、束縛された検査報告全体を作成できませんでした。');
  assert.equal(explanation.correlationRef, 'corr:independent-reporting-failure');
  assert.equal(Object.hasOwn(explanation, 'next'), false);
  assert.equal(sdk.getCheckInput(outcome, 'source'), undefined);
  assert.equal(JSON.stringify(outcome), original);
});
