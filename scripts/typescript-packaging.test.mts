// npm file selection only. This metadata check deliberately does not execute
// prepack and cannot qualify a normal package, runtime or outside-checkout use.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import ts from 'typescript';
import {prepareExplorerXYFlowTypes} from './prepare-explorer-xyflow-types.mjs';

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
  assert.equal(config.options.noUncheckedIndexedAccess, true);
  assert.equal(config.options.exactOptionalPropertyTypes, true);
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

test('required Explorer typechecks use separate Node and browser compiler graphs', async () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const projects = [
    {file: 'packages/explorer/tsconfig.json', browser: false, entries: [
      'packages/explorer/gateway.typecheck.mts', 'packages/explorer/launcher.typecheck.mts',
    ]},
    {file: 'packages/explorer-ui/tsconfig.json', browser: true, entries: [
      'packages/explorer-ui/plan-explorer.tsx', 'packages/explorer-ui/run-inspector.tsx',
      'packages/explorer-ui/flow-layout-worker.mts', 'packages/explorer-ui/flow-model.mts',
      'packages/explorer-ui/read-model.typecheck.mts', 'packages/explorer-ui/run-observation.typecheck.mts',
      'packages/explorer-ui/checkpoint-review.typecheck.mts', 'packages/explorer-ui/xyflow-node.typecheck.mts',
    ]},
    {file: 'packages/explorer/app/tsconfig.json', browser: true, entries: [
      'packages/explorer/app/main.tsx', 'packages/explorer/app/story-card-groups.mts',
    ]},
  ];
  const manifest = JSON.parse(await readFile(join(root, 'package.json'), 'utf8')) as {scripts: Record<string, unknown>};
  assert.equal(manifest.scripts['check:explorer-types'],
    ['node scripts/prepare-explorer-xyflow-types.mjs', ...projects.map(({file}) => `tsc --project ${file}`)].join(' && '));
  for (const {file, browser, entries} of projects) {
    const config = ts.getParsedCommandLineOfConfigFile(join(root, file), {}, {
      ...ts.sys,
      onUnRecoverableConfigFileDiagnostic(diagnostic) {
        assert.fail(ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'));
      },
    });
    assert(config, file);
    assert.deepEqual(config.errors, []);
    const {options, fileNames} = config;
    assert.equal(options.skipLibCheck, false, file);
    assert.equal(options.noUncheckedIndexedAccess, true, file);
    assert.equal(options.exactOptionalPropertyTypes, true, file);
    for (const option of ['strict', 'noEmit', 'isolatedModules', 'erasableSyntaxOnly', 'noImplicitOverride',
      'noImplicitReturns', 'noFallthroughCasesInSwitch'] as const) {
      assert.equal(options[option], true, `${file} must enable ${option}`);
    }
    const graph = new Set(ts.createProgram(fileNames, options).getSourceFiles().map(source => resolve(source.fileName)));
    for (const entry of entries) assert(graph.has(resolve(root, entry)), `${file} omitted ${entry}`);
    assert.equal(graph.has(resolve(root, 'packages/sdk/loopback-http-unavailable.mts')), browser, file);
    assert.equal(graph.has(resolve(root, 'packages/sdk/loopback-http.mts')), !browser, file);
    assert.equal([...graph].some(path => /(?:^|[/\\])@types[/\\]node[/\\]/u.test(path)), !browser, file);
  }
});

test('Explorer XYFlow preparation changes only the pinned declaration members', async t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const temporary = await mkdtemp(join(tmpdir(), 'actql-xyflow-exact-types-'));
  t.after(() => rm(temporary, {recursive: true}));
  const installation = 'node_modules/@xyflow/system';
  const lockPath = join(temporary, 'package-lock.json');
  const lock = await readFile(join(root, 'package-lock.json'), 'utf8');
  const manifestPath = join(installation, 'package.json');
  const manifest = await readFile(join(root, manifestPath), 'utf8');
  const esm = join(installation, 'dist/esm/types/nodes.d.ts');
  const umd = join(installation, 'dist/umd/types/nodes.d.ts');
  const raw = "= Omit<NodeType, 'measured'> & {";
  const fixed = "= Omit<NodeType, 'measured'> & Omit<NodeBase, 'measured'> & {";
  const original = (await readFile(join(root, esm), 'utf8')).replace(fixed, raw);
  assert.notEqual(original.replace(raw, fixed), original);
  for (const member of [esm, umd]) {
    await mkdir(dirname(join(temporary, member)), {recursive: true});
    await writeFile(join(temporary, member), original);
  }
  await writeFile(join(temporary, manifestPath), manifest);
  await writeFile(lockPath, lock.replaceAll('0.0.83', '0.0.84'));
  assert.throws(() => prepareExplorerXYFlowTypes(temporary), /Unexpected XYFlow system dependency lock/u);
  await writeFile(lockPath, lock.replace(/sha512-a\/\/eDjez3/u, 'sha512-x//edjez3'));
  assert.throws(() => prepareExplorerXYFlowTypes(temporary), /Unexpected XYFlow system dependency lock/u);
  await writeFile(lockPath, lock);
  await writeFile(join(temporary, manifestPath), manifest.replace('0.0.83', '0.0.82'));
  assert.throws(() => prepareExplorerXYFlowTypes(temporary), /Unexpected installed XYFlow system package/u);
  await writeFile(join(temporary, manifestPath), manifest);
  await writeFile(join(temporary, umd), original + '\n');
  assert.throws(() => prepareExplorerXYFlowTypes(temporary), /Unexpected XYFlow declaration bytes/u);
  assert.equal(await readFile(join(temporary, esm), 'utf8'), original);
  await writeFile(join(temporary, umd), original);
  const runtime = join(temporary, installation, 'dist/esm/index.js');
  await writeFile(runtime, 'export {};\n');
  prepareExplorerXYFlowTypes(temporary);
  prepareExplorerXYFlowTypes(temporary);
  for (const member of [esm, umd]) {
    assert.equal(await readFile(join(temporary, member), 'utf8'), original.replace(raw, fixed));
  }
  assert.equal(await readFile(runtime, 'utf8'), 'export {};\n');
  assert.equal(await readFile(join(temporary, manifestPath), 'utf8'), manifest);
  assert.equal(await readFile(lockPath, 'utf8'), lock);
});
