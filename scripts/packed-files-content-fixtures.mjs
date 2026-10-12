// Bundle only authored test fixtures. Product modules remain external imports
// from the consumer's actual installed distributions, never copied source.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {isBuiltin} from 'node:module';
import {lstat, mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join, relative, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {build} from 'esbuild';

const fixtureDirectory = 'adapters/host-node/fixtures/';
export const contentFixtureFiles = Object.freeze([
  'content-command-restart.mjs', 'content-command-host.fixture.mjs',
  'content-command.fixture.mjs', 'content-command-custody.fixture.mjs',
  'generated-content.fixture.mjs', 'file-listing-source.fixture.mjs',
  'generated-model-installation.fixture.mjs',
].map(name => fixtureDirectory + name).concat([
  'adapters/site-node/https-exchange-fixture.mjs',
  'scripts/fixtures/model-provider-binding-fixture.mjs',
]));
export const contentFixtureData = Object.freeze([
  'spec/local-check-environment.json',
  'spec/contracts/actql-numeric-reduction.json',
  'spec/dependencies/actql-graph-laws.json',
  'src/stage_results/infer_program_test.mbt',
]);
export const contentProductFiles = Object.freeze([
  'adapters/host-common/runtime-result.mjs',
  'adapters/host-common/runtime-core.mjs',
  'adapters/store-local/publication-store.mjs',
  'adapters/host-node/generated-content-holding.mjs',
  'adapters/host-node/embedded-local.mjs',
  'adapters/host-node/installed-connectors.mjs',
  'adapters/host-node/installed-row-source.mjs',
  'adapters/host-node/installed-row-effect.mjs',
  'adapters/host-node/installed-host-policy.mjs',
]);
const inside = (root, path) => {
  const suffix = relative(root, path);
  return suffix === '' || suffix !== '..' && !suffix.startsWith('../') && !isAbsolute(suffix);
};
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
async function regularFile(root, name) {
  const path = join(root, name), stat = await lstat(path);
  assert.ok(stat.isFile() && !stat.isSymbolicLink() && inside(root, await realpath(path)),
    `PackedContentFileEscaped:${name}`);
  return path;
}

export async function stagePackedContentFixtures({repository, application}) {
  repository = await realpath(repository);
  application = await realpath(application);
  assert.ok(!inside(repository, application) && !inside(application, repository),
    'PackedContentApplicationMustBeExternal');
  const packageRoot = join(application, 'node_modules/@actql/local-node');
  assert.equal(await realpath(packageRoot), packageRoot, 'PackedContentPackageLink');
  const fixtures = new Set(contentFixtureFiles.map(name => join(repository, name)));
  const externals = new Map();
  for (const name of contentProductFiles) {
    const path = await regularFile(packageRoot, name);
    externals.set(join(repository, name), pathToFileURL(path).href);
  }
  await regularFile(packageRoot,
    '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
  externals.set(join(repository,
    '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js'),
  '@actql/local-node/runtime');
  const sdkRoot = join(application, 'node_modules/@actql/sdk');
  assert.equal(await realpath(sdkRoot), sdkRoot, 'PackedContentSDKLink');
  await regularFile(sdkRoot, 'index.mjs');
  externals.set(join(repository, 'packages/sdk/index.mjs'), '@actql/sdk');
  const entry = fixtureDirectory + 'content-command-restart.mjs';
  const output = join(application, entry);
  await mkdir(dirname(output), {recursive: true});
  const result = await build({absWorkingDir: repository, entryPoints: [join(repository, entry)],
    outfile: output, bundle: true, platform: 'node', format: 'esm', target: 'node22',
    write: false, metafile: true, logLevel: 'silent', plugins: [{name: 'installed-content-only',
      setup(builder) {
        // esbuild evaluates plugin filters with Go RE2, not JavaScript flags.
        builder.onResolve({filter: /.*/}, args => {
          if (isBuiltin(args.path)) return {path: args.path, external: true};
          if (args.namespace === 'packed-public-client' &&
              ['@actql/local-node', '@actql/local-node/http-host'].includes(args.path)) {
            return {path: args.path, external: true};
          }
          const path = args.kind === 'entry-point' ? resolve(args.path)
            : resolve(dirname(args.importer), args.path);
          // Exercise the public package entrance, including its Local option
          // validation, instead of reaching through to a private Host entry.
          if (path === join(repository, 'adapters/host-node/embedded-local.mjs')) {
            return {path: 'public-client', namespace: 'packed-public-client'};
          }
          if (externals.has(path)) return {path: externals.get(path), external: true};
          if (fixtures.has(path)) return {path};
          throw new Error(`UndeclaredPackedContentImport:${relative(repository, path)}`);
        });
        builder.onLoad({filter: /.*/}, async args => {
          if (args.namespace === 'packed-public-client') return {contents:
            'export {connect as connectEmbeddedLocal} from "@actql/local-node";\n' +
            'export {openInstalledRemoteHttpHost} from "@actql/local-node/http-host";\n', loader: 'js'};
          assert.ok(fixtures.has(args.path), 'ProductSourceCannotBeBundled');
          await regularFile(repository, relative(repository, args.path));
          return {contents: await readFile(args.path, 'utf8'), loader: 'js'};
        });
      }}]});
  assert.equal(result.outputFiles.length, 1);
  const bytes = result.outputFiles[0].contents;
  assert.ok(!Buffer.from(bytes).includes(Buffer.from(repository)), 'CheckoutPathInPackedFixture');
  const allowedImports = new Set([...externals.values(),
    '@actql/local-node', '@actql/local-node/http-host']);
  const imports = Object.values(result.metafile.outputs).flatMap(value => value.imports);
  assert.ok(imports.every(value => value.external &&
    (isBuiltin(value.path) || allowedImports.has(value.path))), 'UnverifiedPackedFixtureImport');
  await writeFile(output, bytes, {flag: 'wx'});
  const inputs = [];
  for (const name of [...contentFixtureFiles, ...contentFixtureData]) {
    const source = await regularFile(repository, name), original = await readFile(source);
    inputs.push({path: name, bytes: original.length, sha256: sha256(original),
      role: contentFixtureData.includes(name) ? 'independent-data' : 'authored-fixture'});
    if (contentFixtureData.includes(name)) {
      const target = join(application, name);
      await mkdir(dirname(target), {recursive: true});
      await writeFile(target, original, {flag: 'wx'});
      assert.deepEqual(await readFile(target), original);
    }
  }
  return {entry: output, bundleSha256: sha256(bytes), inputs,
    productImports: [...new Set(imports.filter(value => !isBuiltin(value.path))
      .map(value => value.path))].sort(),
    copiedProductSources: 0};
}
