// Shared Client tarballs are used only for the exact checkout they were
// packed from: every build input a pack reads, not only packages/.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {appendFile, copyFile, cp, mkdir, mkdtemp, readFile, rename, rm, writeFile} from
  'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, relative, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import fsPromises from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import './npm-pack-json.test.mjs';
import './normal-pack-source-inputs.test.mjs';
import {packClientPackages, packedClientPackage, pinnedDuckDBPackage} from
  './packed-client-packages.mjs';

const tarball = name => `actql-${name}-0.0.0-development.tgz`;
const git = (repository, ...args) => execFileSync('git', args,
  {cwd: repository, encoding: 'utf8'});

// Exercise the actual packed wrapper callback without running a producer or
// replacing its import decisions with a second test implementation.
async function readOpeningImportRewriter(repository, path, installedHost) {
  const {parse} = await import('acorn');
  const source = await readFile(new URL('./test-packed-read-opening.mjs', import.meta.url), 'utf8');
  const callbacks = [], supports = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.property.name === 'replace' &&
        node.arguments[1]?.type === 'ArrowFunctionExpression' &&
        node.arguments[1].params.map(parameter => parameter.name).join(',') === 'original,quote,specifier') {
      callbacks.push(node);
    }
    if (node.type === 'VariableDeclarator' && node.id.name === 'support') supports.push(node.init);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(callbacks.length, 1);
  assert.equal(supports.length, 1);
  const call = callbacks[0], callback = call.arguments[1];
  const support = supports[0].elements.map(value => value.value);
  const pattern = new RegExp(call.arguments[0].regex.pattern, call.arguments[0].regex.flags);
  const replacement = Function('relative', 'resolve', 'pathToFileURL', 'repository', 'path', 'support', 'installedHost',
    `return (${source.slice(callback.start, callback.end)});`)(
      relative, resolve, pathToFileURL, repository, path, support, installedHost);
  const rewrite = text => text.replace(pattern, replacement);
  rewrite.support = support;
  return rewrite;
}

test('packed read-opening stages its complete authored static helper closure', async () => {
  const {parse} = await import('acorn');
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const first = await readOpeningImportRewriter(repository,
    'adapters/host-node/client-read-opening.fixture.mjs', '/installed-local-node');
  for (const path of first.support.filter(path => path.endsWith('.mjs'))) {
    const syntax = parse(await readFile(join(repository, path), 'utf8'),
      {sourceType: 'module', ecmaVersion: 'latest'});
    for (const declaration of syntax.body) {
      const specifier = declaration.source?.value;
      if (!specifier?.startsWith('.')) continue;
      const target = relative(repository, resolve(repository, path, '..', specifier));
      if (/(?:\.fixture|\.test|\.child)\.mjs$/u.test(target)) {
        assert(first.support.includes(target), `Missing authored helper: ${path} -> ${target}`);
      }
    }
  }
  const path = 'adapters/host-node/funded-client-preparation.fixture.mjs';
  const source = await readFile(join(repository, path), 'utf8');
  const imported = source.split('\n').find(line => line.includes('sdk/internal/private-source-preparation.mjs'));
  assert(imported);
  const rewrite = await readOpeningImportRewriter(repository, path, '/installed-local-node');
  assert.equal(rewrite(imported), "import {freezeInput} from '@actql/sdk/_internal/source-preparation';");
  const manifest = JSON.parse(await readFile(join(repository, 'packages/sdk/package.json'), 'utf8'));
  assert.equal(manifest.exports['./_internal/source-preparation'], './internal/private-source-preparation.mjs');
});

test('packed capacity group includes every existing policy and recovery entrance', async () => {
  const {parse} = await import('acorn');
  const source = await readFile(new URL('./test-packed-read-opening.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const declaration = syntax.body.filter(node => node.type === 'VariableDeclaration')
    .flatMap(node => node.declarations).find(node => node.id.name === 'groups');
  assert(declaration);
  const groups = declaration.init.elements.map(node => Object.fromEntries(
    node.properties.map(property => [property.key.name, property.value.value])));
  // Two fixed configuration checks, Local/HTTPS installation for each of two
  // authored policies, and two recovery cases on each original transport.
  const capacityCases = 2 + 2 * 2 + 2 * 2;
  assert.equal(groups.find(group => group.name === 'installed-capacity').count, capacityCases);
  assert.equal(groups.reduce((count, group) => count + group.count, 0), 52);
  assert.match(source, /publicRowPolicyAdmission: 2, publicHttpRowPolicyInstallation: 2/u);
});

test('packed read-opening imports the public installed wire entry without checkout fallback', async t => {
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const root = await mkdtemp(join(tmpdir(), 'actql-packed-read-wire-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const installed = join(root, 'node_modules/@actql/client-wire');
  await mkdir(installed, {recursive: true});
  const manifest = JSON.parse(await readFile(new URL('../packages/client-wire/package.json', import.meta.url), 'utf8'));
  assert.equal(manifest.exports['.'].default, './index.mjs');
  for (const name of ['package.json', ...manifest.files]) {
    await copyFile(new URL(`../packages/client-wire/${name}`, import.meta.url), join(installed, name));
  }
  const path = 'adapters/host-node/client-read-opening.fixture.mjs';
  const fixture = await readFile(join(repository, path), 'utf8');
  const imports = fixture.match(/^import \{prepareClientHostRequest\} from ['"][^'"]+['"];$/gmu);
  assert.equal(imports?.length, 1, 'Exercise the authored fixture import');
  const rewrite = await readOpeningImportRewriter(repository, path, join(root, 'node_modules/@actql/local-node'));
  const rewritten = rewrite(imports[0]);
  assert.equal(rewritten, "import {prepareClientHostRequest} from '@actql/client-wire';");
  const consumer = join(root, 'wire-consumer.mjs');
  await writeFile(consumer, rewritten + '\nexport {prepareClientHostRequest};\n' +
    "export const entry = import.meta.resolve('@actql/client-wire');\n");
  const imported = await import(pathToFileURL(consumer));
  const wire = await import(pathToFileURL(join(installed, 'index.mjs')));
  assert.equal(typeof imported.prepareClientHostRequest, 'function');
  assert.strictEqual(imported.prepareClientHostRequest, wire.prepareClientHostRequest);
  assert.equal(imported.entry, pathToFileURL(await fsPromises.realpath(join(installed, 'index.mjs'))).href);
  // The checkout still contains the public module, but a missing installed
  // entry must refuse rather than resolving that checkout module as fallback.
  await rm(join(installed, 'index.mjs'));
  assert.throws(() => execFileSync(process.execPath, [consumer], {
    cwd: root, encoding: 'utf8', timeout: 10000, stdio: 'pipe',
  }), error => error.status === 1 && /ERR_MODULE_NOT_FOUND/u.test(error.stderr));
});

test('packed read-opening still refuses private unknown and foreign fixture imports', async () => {
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const rewrite = await readOpeningImportRewriter(repository,
    'adapters/host-node/client-read-opening.fixture.mjs', '/not-selected/installed-local-node');
  for (const path of [
    '../../packages/client-wire/private.mjs',
    '../../packages/client-wire/client-host.generated.js',
    '../../packages/client-wire/index.mjs/extra',
    '../../packages/client-wire/index.mjs?private',
    '../../packages/sdk/private.mjs',
    '../../packages/node/private.mjs',
    '../../packages/local-node/private.mjs',
    '../../packages/foreign/index.mjs',
    '../../../foreign/index.mjs',
  ]) {
    assert.throws(() => rewrite(`import {value} from '${path}';`), /Unpackaged fixture import:/u);
  }
});

test('packed row-limit fixture selects the installed public Node and HTTP Host entries', async t => {
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const root = await mkdtemp(join(tmpdir(), 'actql-packed-read-node-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = 'adapters/host-node/client-values-row-limit.test.mjs';
  const fixture = await readFile(join(repository, path), 'utf8');
  const rewrite = await readOpeningImportRewriter(repository, path,
    join(root, 'node_modules/@actql/local-node'));
  for (const [file, entry] of [['node/index.mjs', '@actql/node'],
    ['local-node/http-host.mjs', '@actql/local-node/http-host']]) {
    const declarations = fixture.split('\n').filter(line =>
      line.startsWith('import ') && line.includes(`../../packages/${file}`));
    assert.equal(declarations.length, 1, 'Exercise the current authored import');
    assert(rewrite(declarations[0]).endsWith(`from '${entry}';`));
  }
  for (const name of ['node', 'sdk']) await cp(join(repository, 'packages', name),
    join(root, 'node_modules/@actql', name), {recursive: true});
  const consumer = join(root, 'consumer.mjs');
  await writeFile(consumer, rewrite(fixture.split('\n').find(line =>
    line.includes("from '../../packages/node/index.mjs'"))) +
    '\nexport {open};\nexport const entry = import.meta.resolve(\'@actql/node\');\n');
  const loaded = await import(pathToFileURL(consumer));
  assert.equal(typeof loaded.open, 'function');
  assert.equal(loaded.entry, pathToFileURL(await fsPromises.realpath(
    join(root, 'node_modules/@actql/node/index.mjs'))).href);
  await rm(join(root, 'node_modules/@actql/node/index.mjs'));
  assert.throws(() => execFileSync(process.execPath, [consumer], {
    cwd: root, encoding: 'utf8', timeout: 10000, stdio: 'pipe',
  }), error => error.status === 1 && /ERR_MODULE_NOT_FOUND/u.test(error.stderr));
});

test('packed missing-generated-asset probe enters its actual wire owner', async t => {
  const {parse} = await import('acorn');
  const root = await mkdtemp(join(tmpdir(), 'actql-packed-wire-asset-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const wire = join(root, 'node_modules/@actql/client-wire');
  await cp(new URL('../packages/client-wire/', import.meta.url), wire, {recursive: true});
  // Keep the actual lazy facade installed. Importing it alone need not load
  // an unused wire module and therefore cannot qualify this missing-asset check.
  for (const name of ['node', 'sdk']) await cp(new URL(`../packages/${name}/`, import.meta.url),
    join(root, 'node_modules/@actql', name), {recursive: true});
  const source = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const probes = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id.name === 'negative' &&
        node.init?.callee?.name === 'spawnSync') probes.push(node.init.arguments[1]);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(probes.length, 1);
  const args = probes[0].elements.map(element => element.value);
  const run = () => spawnSync(process.execPath, args,
    {cwd: root, encoding: 'utf8', timeout: 10000});
  assert.equal(run().status, 0, 'Complete wire package loads');
  const asset = join(wire, 'publication.generated.js');
  await rename(asset, asset + '.omitted');
  const negative = run();
  assert.equal(negative.error, undefined);
  assert.equal(negative.signal, null);
  assert.equal(negative.status, 1);
  assert.match(negative.stderr, /ERR_MODULE_NOT_FOUND/u);
  assert.match(negative.stderr, /publication\.generated\.js/u);
  const lazy = spawnSync(process.execPath, ['--input-type=module', '-e',
    "await import('@actql/node')"], {cwd: root, encoding: 'utf8', timeout: 10000});
  assert.equal(lazy.status, 0, lazy.stderr);
});

test('installed Explorer oracle accepts the complete read-only browser capabilities', async t => {
  const {parse} = await import('acorn');
  const {cp, copyFile} = await import('node:fs/promises');
  const {pathToFileURL} = await import('node:url');
  const root = await mkdtemp(join(tmpdir(), 'actql-explorer-capability-oracle-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const packages = join(root, 'node_modules/@actql');
  await mkdir(packages, {recursive: true});
  await cp(new URL('../packages/client-wire/', import.meta.url),
    join(packages, 'client-wire'), {recursive: true});
  const ui = join(packages, 'explorer-ui');
  await mkdir(ui);
  for (const name of ['package.json', 'read-model.mjs', 'checkpoint-review.mjs',
    'cancellation.mjs', 'presentation-limits.mjs']) {
    await copyFile(new URL(`../packages/explorer-ui/${name}`, import.meta.url), join(ui, name));
  }
  const browser = join(root, 'browser-source.mjs');
  await copyFile(new URL('../packages/explorer/browser-source.mjs', import.meta.url), browser);
  const {createExplorerBrowserSource} = await import(pathToFileURL(browser));
  // These are the explicit read-only public Client capabilities. This unit
  // exercises wire admission and the installed fixture's exact assertion,
  // without opening a Host, creating a Run or claiming package acceptance.
  const declared = {plan: true, run: true, resultMetadata: true,
    resultPayload: false, control: false, sample: false, cancellation: false,
    checkpointList: true, checkpointReview: true};
  const source = createExplorerBrowserSource({origin: 'http://127.0.0.1:12345',
    now: () => 0, async fetch() {
      return Response.json({csrf: 'a'.repeat(43), scopeEpoch: 0,
        expiresAt: 300000, capabilities: declared});
    }});
  t.after(() => source.close());
  const capabilities = await source.connect('operator-supplied-bootstrap');
  const fixture = await readFile(new URL('./fixtures/explorer-installed-readonly.mjs',
    import.meta.url), 'utf8');
  const assertions = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.object.name === 'assert' && node.callee.property.name === 'deepEqual' &&
        node.arguments[0]?.type === 'Identifier' && node.arguments[0].name === 'capabilities') {
      assertions.push(node);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(parse(fixture, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(assertions.length, 1, 'Exercise the actual nonzero installed capability oracle');
  const originalAssertion = fixture.slice(assertions[0].start, assertions[0].end);
  Function('assert', 'capabilities', originalAssertion)(assert, capabilities);
});

test('acquired-source consumers read the native adapter pin explicitly', async t => {
  const repository = await mkdtemp(join(tmpdir(), 'actql-duckdb-pin-'));
  t.after(() => rm(repository, {recursive: true, force: true}));
  const adapter = join(repository, 'adapters/connectors/duckdb/node');
  await mkdir(adapter, {recursive: true});
  const manifest = join(adapter, 'package.json');
  await writeFile(manifest, JSON.stringify({dependencies: {'@duckdb/node-api': '1.2.3-r.4'}}));
  assert.equal(await pinnedDuckDBPackage(repository), '@duckdb/node-api@1.2.3-r.4');
  await writeFile(manifest, '{}');
  await assert.rejects(pinnedDuckDBPackage(repository), /MissingPinnedDuckDBDependency/u);
});

test('packed public-query staging covers every eagerly loaded Graph fixture', async () => {
  const consumer = await readFile(new URL('./graph-public-host.test.mjs', import.meta.url), 'utf8');
  const producer = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const fixtures = [...consumer.matchAll(/readFile\(new URL\('\.\/(fixtures\/[^']+)', import\.meta\.url\)/gu)]
    .map(match => match[1]);
  assert(fixtures.length > 0, 'the consumer must declare actual fixture dependencies');
  // This is a staging-source contract, not execution evidence. Packed CI also
  // runs the consumer in an external installation with no checkout fallback.
  for (const fixture of fixtures) {
    assert(producer.includes(`await writeFile(join(root, '${fixture}'),\n  await readFile(join(repository, 'scripts/${fixture}')));`),
      `Packed public-query staging omitted ${fixture}`);
  }
});

// A repository with one file in each build input directory, an ignored
// generated directory, and one packed tarball shared through a manifest.
async function fixture(t, {names = ['sdk']} = {}) {
  const base = await mkdtemp(join(tmpdir(), 'actql-packed-client-'));
  t.after(() => rm(base, {recursive: true, force: true}));
  const repository = join(base, 'repository');
  for (const directory of ['packages/sdk', 'src', 'adapters', 'spec',
    'scripts', '_build']) {
    await mkdir(join(repository, directory), {recursive: true});
  }
  for (const file of ['packages/sdk/index.mjs', 'src/core.mbt',
    'adapters/host.mjs', 'spec/contract.json', 'scripts/generate.mjs',
    'README.md']) {
    await writeFile(join(repository, file), `${file}\n`);
  }
  await writeFile(join(repository, '.gitignore'), '_build/\n');
  git(repository, 'init', '-q');
  git(repository, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid',
    'add', '.');
  git(repository, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid',
    'commit', '-q', '-m', 'fixture');
  const shared = join(base, 'shared');
  const pack = name => writeFile(join(shared, tarball(name)),
    `${name} packed\n`);
  await packClientPackages({repository, destination: shared, names,
    pack});
  const destination = join(base, 'install');
  await mkdir(destination);
  const previous = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  process.env.ACTQL_PACKED_CLIENT_PACKAGES = shared;
  t.after(() => {
    if (previous === undefined) delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
    else process.env.ACTQL_PACKED_CLIENT_PACKAGES = previous;
  });
  const reuse = () => packedClientPackage({repository, name: 'sdk',
    destination, pack: () => assert.fail('packed again instead of reusing')});
  return {base, repository, shared, destination, pack, reuse};
}

// Execute the real consumer's package-acquisition statements with the original
// canonical helper. The npm port is explicit; this is not prepack or runtime
// acceptance, and the remaining installed smoke assertions are untouched.
async function runHostPackageAcquisition(repository, installation, run) {
  const {parse} = await import('acorn');
  const source = await readFile(new URL('./test-packed-run-host-core.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const acquiresPackage = node => {
    if (node === null || typeof node !== 'object') return false;
    if (node.type === 'CallExpression' && node.callee.type === 'Identifier' &&
        (node.callee.name === 'packedClientPackage' ||
          node.callee.name === 'run' && node.arguments[0]?.value === 'npm' &&
          node.arguments[1]?.elements?.[0]?.value === 'pack')) return true;
    return Object.values(node).some(value => Array.isArray(value)
      ? value.some(acquiresPackage) : acquiresPackage(value));
  };
  const selected = tree.body.filter(acquiresPackage);
  assert(selected.length > 0, 'Exercise the actual consumer package acquisition');
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  return new AsyncFunction('repository', 'installation', 'run', 'packedClientPackage', 'join',
    selected.map(node => source.slice(node.start, node.end)).join('\n'))(
    repository, installation, run, packedClientPackage, join);
}

test('Run Host packed consumer reuses both original tarballs without another prepack', async t => {
  const {repository, destination} = await fixture(t, {names: ['run-host-core', 'client-wire']});
  await runHostPackageAcquisition(repository, destination,
    () => assert.fail('The packed Run Host consumer started another npm pack'));
  for (const name of ['run-host-core', 'client-wire']) {
    assert.equal(await readFile(join(destination, tarball(name)), 'utf8'), `${name} packed\n`);
  }
});

test('Run Host shared packages refuse a dirty original checkout without repacking', async t => {
  const {repository, destination} = await fixture(t, {names: ['run-host-core', 'client-wire']});
  await appendFile(join(repository, 'src/core.mbt'), 'changed\n');
  await assert.rejects(runHostPackageAcquisition(repository, destination,
    () => assert.fail('Dirty shared inputs cannot select another pack')), /build inputs changed/u);
  assert.deepEqual(await fsPromises.readdir(destination), []);
});

test('Run Host shared packages refuse another clean revision without repacking', async t => {
  const {repository, destination} = await fixture(t, {names: ['run-host-core', 'client-wire']});
  git(repository, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid',
    'commit', '-q', '--allow-empty', '-m', 'different original revision');
  await assert.rejects(runHostPackageAcquisition(repository, destination,
    () => assert.fail('A different revision cannot select another pack')),
  /were packed from [0-9a-f]+, not this checkout/u);
  assert.deepEqual(await fsPromises.readdir(destination), []);
});

test('Run Host shared packages retain the verified first copy when the second digest refuses', async t => {
  const {repository, shared, destination} = await fixture(t, {names: ['run-host-core', 'client-wire']});
  await appendFile(join(shared, tarball('client-wire')), 'changed\n');
  await assert.rejects(runHostPackageAcquisition(repository, destination,
    () => assert.fail('A changed shared tarball cannot select another pack')), /changed after packing/u);
  assert.deepEqual(await fsPromises.readdir(destination), [tarball('run-host-core')]);
  assert.equal(await readFile(join(destination, tarball('run-host-core')), 'utf8'), 'run-host-core packed\n');
});

test('Run Host default acquisition preserves both lifecycle-enabled original npm commands', async t => {
  const {repository, destination} = await fixture(t, {names: ['run-host-core', 'client-wire']});
  delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  const calls = [];
  await runHostPackageAcquisition(repository, destination,
    (command, args, cwd) => { calls.push({command, args, cwd}); });
  assert.deepEqual(calls, ['run-host-core', 'client-wire'].map(name => ({
    command: 'npm', args: ['pack', '--pack-destination', destination, '--json'],
    cwd: join(repository, 'packages', name),
  })));
});

test('an unchanged checkout reuses the shared tarball as packed', async t => {
  const {repository, destination, reuse} = await fixture(t);
  // Generated output and scratch outside the build inputs do not count.
  await writeFile(join(repository, '_build', 'generated.js'), 'generated\n');
  await mkdir(join(repository, '.native-tests'));
  await writeFile(join(repository, '.native-tests', 'scratch'), 'scratch\n');
  await reuse();
  assert.equal(await readFile(join(destination, tarball('sdk')), 'utf8'),
    'sdk packed\n');
});

for (const file of ['src/core.mbt', 'adapters/host.mjs', 'spec/contract.json',
  'scripts/generate.mjs', 'packages/sdk/index.mjs', 'README.md']) {
  test(`a tracked change to ${file} refuses the shared tarball`, async t => {
    const {repository, reuse} = await fixture(t);
    await appendFile(join(repository, file), 'changed\n');
    await assert.rejects(reuse(), /build inputs changed/u);
  });
}

for (const file of ['src/new.mbt', 'adapters/new.mjs', 'spec/new.json',
  'scripts/new.mjs', 'packages/sdk/new.mjs']) {
  test(`an untracked ${file} refuses the shared tarball`, async t => {
    const {repository, reuse} = await fixture(t);
    await writeFile(join(repository, file), 'new\n');
    await assert.rejects(reuse(), /build inputs changed/u);
  });
}

test('another revision refuses the shared tarball', async t => {
  const {repository, reuse} = await fixture(t);
  await appendFile(join(repository, 'src/core.mbt'), 'committed\n');
  git(repository, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid',
    'commit', '-q', '-am', 'next');
  await assert.rejects(reuse(), /were packed from [0-9a-f]+, not this checkout/u);
});

test('a tarball changed after packing is refused', async t => {
  const {shared, reuse} = await fixture(t);
  await appendFile(join(shared, tarball('sdk')), 'tampered\n');
  await assert.rejects(reuse(), /changed after packing/u);
});

test('a shared copy with different destination bytes refuses before new lineage', async t => {
  const {shared, destination, reuse} = await fixture(t);
  const original = await readFile(join(shared, tarball('sdk')));
  const copy = fsPromises.copyFile;
  let copies = 0;
  t.mock.method(fsPromises, 'copyFile', async (...args) => {
    await copy(...args);
    if (args[1] === join(destination, tarball('sdk'))) {
      copies++;
      // Model a source/copy race deterministically without changing the
      // expected shared digest or adding a product-only test hook.
      await appendFile(args[1], 'changed during copy\n');
    }
  });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  await assert.rejects(reuse(), /changed while copying/u);
  assert.equal(copies, 1);
  assert.deepEqual(await readFile(join(shared, tarball('sdk'))), original);
});

test('no manifest is recorded from a dirty checkout or one changed while packing',
  async t => {
    const {base, repository} = await fixture(t);
    await appendFile(join(repository, 'src/core.mbt'), 'dirty\n');
    await assert.rejects(packClientPackages({repository,
      destination: join(base, 'dirty'), names: ['sdk'], pack: name =>
        writeFile(join(base, 'dirty', tarball(name)), 'x\n')}),
    /Build inputs differ from HEAD/u);
    git(repository, 'checkout', '--', 'src/core.mbt');
    const destination = join(base, 'during');
    await assert.rejects(packClientPackages({repository, destination,
      names: ['sdk'], pack: async name => {
        await writeFile(join(destination, tarball(name)), 'x\n');
        await appendFile(join(repository, 'adapters/host.mjs'), 'edited\n');
      }}), /Build inputs changed while packing/u);
    await assert.rejects(readFile(join(destination,
      'packed-client-packages.json')), {code: 'ENOENT'});
  });

test('separate same-revision checkouts reuse artifact bytes into independent consumers', async t => {
  const {base, repository, shared} = await fixture(t);
  const second = join(base, 'second-checkout');
  git(base, 'clone', '--quiet', repository, second);
  for (const [index, checkout] of [repository, second].entries()) {
    const destination = join(base, `consumer-${index}`);
    await mkdir(destination);
    await packedClientPackage({repository: checkout, name: 'sdk', destination,
      pack: () => assert.fail('the consumer repacked shared packages')});
  }
  await appendFile(join(base, 'consumer-0', tarball('sdk')), 'consumer mutation\n');
  assert.equal(await readFile(join(base, 'consumer-1', tarball('sdk')), 'utf8'), 'sdk packed\n');
  assert.equal(await readFile(join(shared, tarball('sdk')), 'utf8'), 'sdk packed\n');
  await appendFile(join(second, 'src/core.mbt'), 'consumer source change\n');
  await assert.rejects(packedClientPackage({repository: second, name: 'sdk',
    destination: join(base, 'consumer-1'), pack: () => assert.fail('repacked')}),
  /build inputs changed/u);
});
