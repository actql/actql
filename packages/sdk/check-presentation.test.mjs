import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import {packSdkFixture} from './packed-package.fixture.mjs';

function assertBrowserClosure(bundle, checkInput) {
  const inputs = Object.keys(bundle.metafile.inputs);
  assert(inputs.some(path => path.endsWith('/sdk/check-presentation.mjs')));
  assert(inputs.some(path => path.endsWith('/sdk/operation-presentation.mjs')));
  assert(inputs.some(path => path.endsWith('/sdk/loopback-http-unavailable.mjs')));
  assert(!inputs.some(path => path.endsWith('/sdk/loopback-http.mjs')));
  for (const input of inputs) {
    checkInput(input);
    assert(!/\.(?:test|fixture)\.mjs$/u.test(input), `Test-only input: ${input}`);
  }
}

test('packed SDK public exports and browser bundle include their presentation modules', t => {
  const cache = mkdtempSync(join(tmpdir(), 'actql-sdk-presentation-'));
  t.after(() => rmSync(cache, {recursive: true}));
  const environment = {...process.env};
  delete environment.NODE_TEST_CONTEXT;
  const run = (command, args, cwd = cache) => execFileSync(command, args, {
    cwd, env: environment, encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'],
  });
  // Real tarballs and an external install expose missing transitive modules
  // that source imports and a dry-run inventory cannot exercise.
  const packages = ['client-wire', 'sdk'].map(name => {
    const result = [packSdkFixture({name, destination: cache, run,
      directory: fileURLToPath(new URL(`../${name}/`, import.meta.url))})];
    // The actual tarball supplies the package report, independently of stdout.
    const entries = Array.isArray(result) ? result : Object.values(result);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].name, `@actql/${name}`);
    return entries[0];
  });
  t.diagnostic(JSON.stringify(packages.map(({name, shasum, integrity}) => ({name, shasum, integrity}))));
  writeFileSync(join(cache, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--offline', '--ignore-scripts', '--no-save',
    '--no-audit', '--no-fund', '--cache', cache,
    ...packages.map(entry => join(cache, entry.filename))]);
  run(process.execPath, ['--input-type=module', '-e', `
    import assert from 'node:assert/strict';
    const sdk = await import('@actql/sdk');
    assert.deepEqual(Object.keys(sdk).sort(), ${JSON.stringify(JSON.parse(readFileSync(new URL('./fixtures/public-exports.json', import.meta.url), 'utf8')))});
    await assert.rejects(import('@actql/sdk/internal/client.mjs'), {code: 'ERR_PACKAGE_PATH_NOT_EXPORTED'});
    const host = await import('@actql/sdk/host-port');
    assert.equal(typeof sdk.connect, 'function');
    assert.equal(host.connectInProcess, sdk.connectInProcess);
    assert.equal(typeof host.canonicalJson, 'function');
    assert.equal(sdk.getCheckReasonCatalogInfo().revision, '2026-10-25.1');
    assert.equal(sdk.getCheckReasonCatalogEntry('parameter_value_required').family, 'requirement');
    for (const name of ['formatSubmission', 'formatCancellation',
      'formatReadFailure', 'formatEffectUncertainty']) {
      assert.equal(typeof sdk[name], 'function');
      assert.equal(sdk[name]({}), undefined);
    }
  `]);
  // Consume unchanged behavioral cases through the normally installed SDK.
  // Only public import specifiers change; fixture assertions and replies do not.
  const consumers = ['check-locations', 'run-control-revisions', 'client-close',
    'read-progress', 'submission-identity', 'cancel-identity', 'connection-string-client',
    'connection-start-order'];
  writeFileSync(join(cache, 'submission-fixture.mjs'),
    readFileSync(new URL('./submission-fixture.mjs', import.meta.url)));
  for (const name of consumers) {
    const source = readFileSync(new URL(`./${name}.test.mjs`, import.meta.url), 'utf8');
    writeFileSync(join(cache, `${name}.test.mjs`), source
      .replaceAll("from './index.mjs'", "from '@actql/sdk'")
      .replaceAll("from './host-port.mjs'", "from '@actql/sdk/host-port'"));
  }
  const report = run(process.execPath, ['--test-reporter=tap', '--test',
    ...consumers.map(name => `${name}.test.mjs`)]);
  const count = Number(/^# tests (\d+)$/mu.exec(report)?.[1]);
  assert(count > 0, report);
  assert.match(report, /^# fail 0$/mu);
  assert.match(report, /^# skipped 0$/mu);
  t.diagnostic(`Normally packed/installed SDK behavioral cases: ${count}`);
  for (const name of ['check-presentation.mjs', 'operation-presentation.mjs',
    'operation-formats.mjs', 'json-value-wire.generated.mjs', 'connection-string.mjs',
    'loopback-http.mjs', 'loopback-http-unavailable.mjs',
    'check-reason-catalog.generated.js', 'check-reason-catalog.generated.d.ts']) {
    assert.equal(packages[1].files.filter(file => file.path === name).length, 1);
  }
  assert.equal(packages[1].files.some(file => file.path.endsWith('.test.mjs')), false);
  const bundle = buildSync({absWorkingDir: cache,
    entryPoints: ['node_modules/@actql/sdk/index.mjs'], bundle: true,
    platform: 'browser', format: 'esm', target: 'es2022', write: false, metafile: true});
  assertBrowserClosure(bundle, path => {
    const prefix = 'node_modules/@actql/';
    assert(path.startsWith(prefix), `Unexpected browser dependency: ${path}`);
    const [name, ...parts] = path.slice(prefix.length).split('/');
    assert(['sdk', 'client-wire'].includes(name));
    assert(packages.find(entry => entry.name === `@actql/${name}`).files
      .some(file => file.path === parts.join('/')), `Missing packed input: ${path}`);
  });
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
  assertBrowserClosure(bundle, path => {
    const resolved = relative(root, join(root, path));
    assert(/^(?:packages\/(?:sdk|client-wire)\/)/u.test(resolved),
      `Unexpected browser dependency: ${path}`);
  });
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
