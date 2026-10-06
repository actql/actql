import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';

test('packed SDK public exports and browser bundle include their presentation modules', t => {
  const cache = mkdtempSync(join(tmpdir(), 'actql-sdk-presentation-'));
  t.after(() => rmSync(cache, {recursive: true}));
  const run = (command, args, cwd = cache) => execFileSync(command, args, {
    cwd, encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'],
  });
  // Real tarballs and an external install expose missing transitive modules
  // that source imports and a dry-run inventory cannot exercise.
  const packages = ['client-wire', 'sdk'].map(name => {
    const result = JSON.parse(run('npm', ['pack', '--json', '--cache', cache,
      '--pack-destination', cache], fileURLToPath(new URL(`../${name}/`, import.meta.url))));
    // npm can key workspace reports by package name instead of returning a list.
    const entries = Array.isArray(result) ? result : Object.values(result);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].name, `@actql/${name}`);
    return entries[0];
  });
  writeFileSync(join(cache, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--offline', '--ignore-scripts', '--no-save',
    '--no-audit', '--no-fund', '--cache', cache,
    ...packages.map(entry => join(cache, entry.filename))]);
  run(process.execPath, ['--input-type=module', '-e', `
    import assert from 'node:assert/strict';
    const sdk = await import('@actql/sdk');
    const host = await import('@actql/sdk/host-port');
    assert.equal(typeof sdk.connect, 'function');
    assert.equal(host.connectInProcess, sdk.connectInProcess);
    assert.equal(typeof host.canonicalJson, 'function');
    assert.equal(sdk.getCheckReasonCatalogInfo().revision, '2026-10-07.1');
    assert.equal(sdk.getCheckReasonCatalogEntry('parameter_value_required').family, 'requirement');
    for (const name of ['formatSubmission', 'formatCancellation',
      'formatReadFailure', 'formatEffectUncertainty']) {
      assert.equal(typeof sdk[name], 'function');
      assert.equal(sdk[name]({}), undefined);
    }
  `]);
  for (const name of ['check-presentation.mjs', 'operation-presentation.mjs',
    'operation-formats.mjs', 'json-value-wire.generated.mjs',
    'check-reason-catalog.generated.js', 'check-reason-catalog.generated.d.ts']) {
    assert.equal(packages[1].files.filter(file => file.path === name).length, 1);
  }
  assert.equal(packages[1].files.some(file => file.path.endsWith('.test.mjs')), false);
  const bundle = buildSync({absWorkingDir: cache,
    entryPoints: ['node_modules/@actql/sdk/index.mjs'], bundle: true,
    platform: 'browser', format: 'esm', target: 'es2022', write: false, metafile: true});
  assert.deepEqual(Object.keys(bundle.metafile.inputs).sort(), [
    'node_modules/@actql/client-wire/client-host.generated.js',
    'node_modules/@actql/client-wire/index.mjs',
    'node_modules/@actql/client-wire/publication.generated.js',
    'node_modules/@actql/sdk/check-presentation.mjs',
    'node_modules/@actql/sdk/check-reason-catalog.generated.js',
    'node_modules/@actql/sdk/checkpoints.mjs',
    'node_modules/@actql/sdk/index.mjs',
    'node_modules/@actql/sdk/json-value-wire.generated.mjs',
    'node_modules/@actql/sdk/operation-formats.mjs',
    'node_modules/@actql/sdk/operation-presentation.mjs',
  ]);
  assert(Object.values(bundle.metafile.outputs).every(output => output.imports.length === 0));
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
    'packages/sdk/check-reason-catalog.generated.js',
    'packages/sdk/checkpoints.mjs',
    'packages/sdk/index.mjs',
    'packages/sdk/json-value-wire.generated.mjs',
    'packages/sdk/operation-formats.mjs',
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
