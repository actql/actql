import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {cpSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {test} from 'node:test';
import ts from 'typescript';
import {interfaceAttributes, javascriptInterface} from './interface-inventory.mjs';
import {typescriptInterface} from './typescript-interface-inventory.mjs';
import {checkInterfaceOwners} from './check-interface-owners.mjs';
import {trustedCompilerBindingOutputs} from './interface-generation-freshness.mjs';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {installedDeclarationEmits} from './installed-interface-correspondence.mjs';
import {releaseInterfaceCheck} from './release-interface-check.mjs';
import {stagePackage, unpack} from './package-release.mjs';

import type {BinaryLike} from 'node:crypto';
import type {TestContext} from 'node:test';

type Cohort = Parameters<typeof stagePackage>[0]['cohort'];
type PackedItem = Awaited<ReturnType<typeof stagePackage>>;
type CheckError = {errors?: {text: string}[]};
type FixtureDeclaration = (ReturnType<typeof javascriptInterface> | ReturnType<typeof typescriptInterface>) &
  {module: string; sha256: string; role: string; responsibilityFacet: string; owner: string;
    contracts: {operations: string[]; exports: string[];
      attributes: Record<string, {path: string; anchor: string}[]>}[]};

const hash = (value: BinaryLike) => createHash('sha256').update(value).digest('hex');
function fixture(t: TestContext) {
  const scratch = mkdtempSync(join(tmpdir(), 'actql-release-authored-types-'));
  t.after(() => rmSync(scratch, {recursive: true, force: true}));
  const repository = join(scratch, 'repository');
  const put = (path: string, text: string | Buffer) => {
    mkdirSync(dirname(join(repository, path)), {recursive: true});
    writeFileSync(join(repository, path), text);
  };
  put('package.json', '{"private":true}\n');
  put('scripts/package-release.mjs', readFileSync(new URL('./package-release.mjs', import.meta.url)));
  put('LICENSE', readFileSync(new URL('../LICENSE', import.meta.url)));
  put('owner.md', 'Original source, type boundary, authority, lifetime, Unknown and cleanup');
  const cohortText = readFileSync(new URL('../release/client-cohort.json', import.meta.url), 'utf8');
  const cohort = JSON.parse(cohortText) as Cohort, declarations: FixtureDeclaration[] = [];
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
      declarations.push({module, sha256: hash(text), ...syntax, role: 'public-wire-codec',
        responsibilityFacet: 'primary', owner: 'original fixture type/runtime boundary',
        contracts: [{operations: ['<module>'], exports: syntax.exports,
          attributes: Object.fromEntries(interfaceAttributes.map(attribute => [attribute,
            [{path: 'owner.md', anchor: 'Original source, type boundary, authority, lifetime, Unknown and cleanup'}]]))}]});
    }
  }
  const save = () => put('elsewhere/interface-boundaries.json', JSON.stringify(declarations));
  save();
  const git = (...args: string[]) => execFileSync('git', args, {cwd: repository, encoding: 'utf8'}).trim();
  git('init', '-q', '--initial-branch=main'); git('add', '.');
  git('-c', 'user.name=ActQL Test', '-c', 'user.email=test@example.invalid', '-c', 'commit.gpgsign=false',
    'commit', '-qm', 'test: original authored type and runtime inputs');
  return {scratch, repository, put, names, cohort, cohortText, declarations, save, git,
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
  f.declarations.push(declaration); declaration.exports.pop(); f.save();
  await assert.rejects(checkInterfaceOwners(f.repository, options), /Unregistered interface export/u);
});

test('emitted declaration uses its Git author and original inferred dependency before installed admission', t => {
  const f = fixture(t), base = 'packages/client-wire/';
  f.put('.gitignore', '/packages/client-wire/projected.mjs\n/packages/client-wire/projected.d.mts\n');
  f.put('tsconfig.base.json', JSON.stringify({compilerOptions: {target: 'ES2022', module: 'NodeNext',
    strict: true, noLib: true, types: [], noEmitOnError: true}}));
  f.put('tsconfig.tooling.json', JSON.stringify({extends: './tsconfig.base.json',
    compilerOptions: {declaration: true}, include: ['packages/client-wire/*.mts']}));
  f.put('package-lock.json', JSON.stringify({packages: {'node_modules/typescript': {version: ts.version}}}));
  f.put(base + 'globals.d.ts', 'interface Array<T> {} interface Boolean {} interface CallableFunction {} ' +
    'interface Function {} interface IArguments {} interface NewableFunction {} interface Number {} ' +
    'interface Object {} interface RegExp {} interface String {}\n');
  f.put(base + 'model.mts', 'export const original = "original" as const;\n');
  const author = base + 'projected.mts', declaration = base + 'projected.d.mts', runtime = base + 'projected.mjs';
  f.put(author, '/// <reference path="./globals.d.ts" />\nimport {original} from "./model.mjs";\n' +
    'export const read = () => original;\n');
  f.git('add', '.');
  f.git('-c', 'user.name=ActQL Test', '-c', 'user.email=test@example.invalid', '-c', 'commit.gpgsign=false',
    'commit', '-qm', 'test: original inferred declaration inputs');
  const source = f.git('rev-parse', 'HEAD');
  f.put(declaration, 'export declare const read: () => "forged";\n');
  assert.deepEqual(installedDeclarationEmits(f.repository, source, [declaration, runtime]).get(declaration),
    {author, sha256: hash('export declare const read: () => "original";\n')});
  assert.throws(() => installedDeclarationEmits(f.repository, source, [declaration]), /paired runtime/u);
  f.put(base + 'model.mts', 'export const original = "changed" as const;\n');
  assert.throws(() => installedDeclarationEmits(f.repository, source, [declaration, runtime]),
    /Changed original TypeScript dependency/u);
});

test('real client-wire Source caller accepts its authored type entrance through genuine generation checks', async () => {
  const checked = await checkInterfaceOwners(process.cwd(), {manifests: ['packages/client-wire/package.json'],
    authoredEntrances: ['packages/client-wire/index.d.ts']});
  assert(checked.result.primaryComplete);
  assert(checked.modules.find(value => value.module === 'packages/client-wire/index.d.ts')!
    .exports.includes('clientSourceFormats'));
  assert.ok(trustedCompilerBindingOutputs(process.cwd(), checked.generatedQualification).length,
    'the same source owner must have actually verified its generated outputs');
});

test('member-derived declarations do not exempt a genuine dynamic runtime value import', async t => {
  const f = fixture(t);
  const text = "const target = new URL('./index.d.ts', import.meta.url); export const load = () => import(target.href);";
  f.put('packages/client-wire/index.mjs', text);
  const declaration = f.declarations.find(value => value.module === 'packages/client-wire/index.mjs')!;
  Object.assign(declaration, javascriptInterface(text), {sha256: hash(text)});
  declaration.contracts[0].operations = ['<module>', ...declaration.operations.map(value => value.name)];
  declaration.contracts[0].exports = declaration.exports; f.save();
  await assert.rejects(checkInterfaceOwners(f.repository, {manifests: ['packages/client-wire/package.json'],
    authoredEntrances: ['packages/client-wire/index.d.ts']}),
  failure => (failure as CheckError).errors?.some(value => /must be initialized/u.test(value.text)));
});

test('actual release verifier and installed caller retain type/default entrances and exact member refusal', async t => {
  const f = fixture(t), directory = join(f.scratch, 'release'), development = join(directory, 'development');
  mkdirSync(development, {recursive: true});
  const packages: PackedItem[] = [], tarballs: Record<string, string> = {}, consumer = join(f.scratch, 'consumer');
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
