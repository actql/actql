import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {cpSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {test} from 'node:test';
import {interfaceAttributes, javascriptInterface} from './interface-inventory.mjs';
import {typescriptInterface} from './typescript-interface-inventory.mjs';
import {checkInterfaceOwners} from './check-interface-owners.mjs';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {releaseInterfaceCheck} from './release-interface-check.mjs';
import {stagePackage, unpack} from './package-release.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
function fixture(t) {
  const scratch = mkdtempSync(join(tmpdir(), 'actql-release-authored-types-'));
  t.after(() => rmSync(scratch, {recursive: true, force: true}));
  const repository = join(scratch, 'repository');
  const put = (path, text) => {
    mkdirSync(dirname(join(repository, path)), {recursive: true});
    writeFileSync(join(repository, path), text);
  };
  put('package.json', '{"private":true}\n');
  put('scripts/package-release.mjs', readFileSync(new URL('./package-release.mjs', import.meta.url)));
  put('LICENSE', readFileSync(new URL('../LICENSE', import.meta.url)));
  put('owner.md', 'Original source, type boundary, authority, lifetime, Unknown and cleanup');
  const cohortText = readFileSync(new URL('../release/client-cohort.json', import.meta.url), 'utf8');
  const cohort = JSON.parse(cohortText), declarations = [];
  const names = ['index.mjs', 'index.d.ts', 'dormant.d.mts', 'dormant.d.cts'];
  for (const name of cohort.packages) {
    const files = name === 'client-wire' ? names : names.slice(0, 2);
    put(`packages/${name}/package.json`, JSON.stringify({name: `@actql/${name}`, type: 'module',
      private: true, version: '0.0.0-development', files,
      exports: {'.': {types: './index.d.ts', default: './index.mjs'}}}));
    for (const file of files) {
      const module = `packages/${name}/${file}`;
      const text = file === 'index.mjs' ? 'export const formats = ["sql", "json"];\n'
        : 'export type Format = "sql" | "json"; export const formats: readonly Format[];\n';
      put(module, text);
      const syntax = file.endsWith('.mjs') ? javascriptInterface(text) : typescriptInterface(text, module);
      declarations.push({module, sha256: hash(text), ...syntax, role: 'wire-boundary',
        responsibilityFacet: 'primary', owner: 'original fixture type/runtime boundary',
        contracts: [{operations: ['<module>'], exports: syntax.exports,
          attributes: Object.fromEntries(interfaceAttributes.map(attribute => [attribute,
            [{path: 'owner.md', anchor: 'Original source, type boundary, authority, lifetime, Unknown and cleanup'}]]))}]});
    }
  }
  const save = () => put('elsewhere/interface-boundaries.json', JSON.stringify(declarations));
  save();
  const git = (...args) => execFileSync('git', args, {cwd: repository, encoding: 'utf8'}).trim();
  git('init', '-q', '--initial-branch=main'); git('add', '.');
  git('-c', 'user.name=ActQL Test', '-c', 'user.email=test@example.invalid', '-c', 'commit.gpgsign=false',
    'commit', '-qm', 'test: original authored type and runtime inputs');
  return {scratch, repository, put, names, cohort, cohortText, declarations, save,
    source: git('rev-parse', 'HEAD')};
}

test('actual required caller retains all member-derived declaration variants and their primary obligations', async t => {
  const f = fixture(t);
  const options = {manifests: ['packages/client-wire/package.json'],
    authoredEntrances: f.names.map(name => `packages/client-wire/${name}`)};
  const result = await checkInterfaceOwners(f.repository, options);
  assert.equal(result.result.primaryCovered, 4);
  for (const file of f.names.slice(1)) assert(result.modules.some(value => value.module.endsWith(file)));
  const index = f.declarations.findIndex(value => value.module === 'packages/client-wire/dormant.d.cts');
  const [declaration] = f.declarations.splice(index, 1); f.save();
  await assert.rejects(checkInterfaceOwners(f.repository, options),
    /Unregistered distributed interfaces: packages\/client-wire\/dormant.d.cts/u);
  f.declarations.push(declaration); declaration.sha256 = '0'.repeat(64); f.save();
  await assert.rejects(checkInterfaceOwners(f.repository, options), /Unreviewed interface implementation/u);
});

test('real client-wire Source caller accepts its authored type entrance through genuine generation checks', async () => {
  const checked = await checkInterfaceOwners(process.cwd(), {manifests: ['packages/client-wire/package.json'],
    authoredEntrances: ['packages/client-wire/index.d.ts']});
  assert(checked.result.primaryComplete);
  assert(checked.modules.find(value => value.module === 'packages/client-wire/index.d.ts')
    .exports.includes('clientSourceFormats'));
  assert.equal(checked.freshness.checked.length, 15);
});

test('actual release verifier and installed caller retain type/default entrances and exact member refusal', async t => {
  const f = fixture(t), directory = join(f.scratch, 'release'), development = join(directory, 'development');
  mkdirSync(development, {recursive: true});
  const packages = [], tarballs = {}, consumer = join(f.scratch, 'consumer');
  mkdirSync(join(consumer, 'node_modules/@actql'), {recursive: true});
  // Tiny synthetic archives exercise the original normal staging/verifier.
  // They are not a product producer or a compiled/runtime acceptance receipt.
  for (const name of f.cohort.packages) {
    const original = join(f.scratch, `original-${name}`); mkdirSync(original);
    cpSync(join(f.repository, 'packages', name), join(original, 'package'), {recursive: true});
    const archive = join(development, `actql-${name}-0.0.0-development.tgz`);
    execFileSync('tar', ['-czf', archive, '-C', original, 'package']);
    const item = await stagePackage({archive, destination: directory, name,
      cohort: f.cohort, license: join(f.repository, 'LICENSE')});
    packages.push(item); tarballs[name] = item.originalSha256;
    const payload = await unpack(join(directory, item.file), join(f.scratch, `installed-${name}`));
    renameSync(payload, join(consumer, 'node_modules/@actql', name));
  }
  writeFileSync(join(development, 'packed-client-packages.json'), JSON.stringify({revision: f.source, tarballs}));
  writeFileSync(join(directory, 'release.json'), JSON.stringify({version: 'actql-package-release/0.1',
    sourceSha: f.source, preparedAt: new Date().toISOString(), cohort: f.cohort,
    recipeSha256: hash(readFileSync(join(f.repository, 'scripts/package-release.mjs'))),
    cohortSha256: hash(f.cohortText), toolchain: {node: process.version},
    generation: 'normal-prepack-then-metadata-and-license-only', packages}));
  const installed = join(consumer, 'node_modules/@actql/client-wire');
  assert.equal(installedInterfaceInventory(installed).modules.length, 4);
  const admission = await releaseInterfaceCheck({repository: f.repository, directory});
  const report = await admission.verifyConsumer(consumer, ['client-wire']);
  assert.equal(report.reports[0].coverage.primaryCovered, 4);
  assert.equal(report.reports[0].dependencies.modules, 1);
  writeFileSync(join(installed, 'index.d.ts'), 'export const formats: readonly string[];\n');
  await assert.rejects(admission.verifyConsumer(consumer, ['client-wire']), /Changed installed release members/u);
});
