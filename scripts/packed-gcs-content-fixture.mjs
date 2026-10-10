// Package-external fixture staging, never a checkout runtime overlay.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {isBuiltin} from 'node:module';
import {lstat, mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join, relative, resolve} from 'node:path';
import {build} from 'esbuild';

export const packedGcsFixtureInputs = Object.freeze([
  'scripts/fixtures/gcs-packed-client.fixture.mjs',
  'scripts/gcs-files-content-environment.mjs',
  'scripts/gcs-files-content-credential.mjs',
  'adapters/site-node/https-exchange-fixture.mjs',
]);
const productImports = new Set(['@actql/local-node', '@actql/local-node/http-host',
  '@actql/sdk', '@actql/sdk/host-port']);
const inside = (root, path) => {
  const suffix = relative(root, path);
  return suffix === '' || suffix !== '..' && !suffix.startsWith('../') && !isAbsolute(suffix);
};
export async function stagePackedGcsFixture({repository, application}) {
  repository = await realpath(repository);
  application = await realpath(application);
  assert.ok(!inside(repository, application) && !inside(application, repository), 'GcsConsumerMustBeExternal');
  const allowed = new Set(packedGcsFixtureInputs.map(path => join(repository, path)));
  const inputs = [];
  for (const path of packedGcsFixtureInputs) {
    const source = join(repository, path), stat = await lstat(source);
    assert.ok(stat.isFile() && !stat.isSymbolicLink() && inside(repository, await realpath(source)),
      `InvalidPackedGcsFixture:${path}`);
    const bytes = await readFile(source);
    inputs.push({path, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')});
  }
  const output = join(application, 'gcs-public.fixture.mjs');
  await mkdir(dirname(output), {recursive: true});
  const bundled = await build({absWorkingDir: repository,
    entryPoints: [join(repository, packedGcsFixtureInputs[0])], outfile: output,
    bundle: true, platform: 'node', format: 'esm', target: 'node22', write: false,
    metafile: true, logLevel: 'silent', plugins: [{name: 'only-authorized-gcs-fixture', setup(builder) {
      builder.onResolve({filter: /.*/}, args => {
        if (isBuiltin(args.path) || productImports.has(args.path)) return {path: args.path, external: true};
        const path = args.kind === 'entry-point' ? resolve(args.path) : resolve(dirname(args.importer), args.path);
        assert.ok(allowed.has(path), `UndeclaredPackedGcsImport:${relative(repository, path)}`);
        return {path};
      });
      builder.onLoad({filter: /.*/}, async args => {
        assert.ok(allowed.has(args.path), 'ProductSourceMustNotBeBundled');
        return {contents: await readFile(args.path, 'utf8'), loader: 'js'};
      });
    }}]});
  assert.equal(bundled.outputFiles.length, 1);
  const bytes = bundled.outputFiles[0].contents;
  assert.equal(Buffer.from(bytes).includes(Buffer.from(repository)), false, 'CheckoutPathInGcsConsumer');
  const imports = Object.values(bundled.metafile.outputs).flatMap(output => output.imports);
  assert.ok(imports.every(item => item.external && (isBuiltin(item.path) || productImports.has(item.path))));
  await writeFile(output, bytes, {flag: 'wx'});
  return {entry: output, sha256: createHash('sha256').update(bytes).digest('hex'), inputs,
    productImports: [...productImports], copiedProductSources: 0};
}
