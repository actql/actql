import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {interfaceAttributes, javascriptInterface} from './interface-inventory.mjs';
import {checkInterfaceOwners, checkedOriginalInterface} from './check-interface-owners.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const hash = source => createHash('sha256').update(source).digest('hex');
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-required-interface-'));
  t.after(() => rmSync(root, {recursive: true}));
  const put = (path, value) => {
    mkdirSync(dirname(join(root, path)), {recursive: true});
    writeFileSync(join(root, path), value);
  };
  put('outside/sdk/package.json', JSON.stringify({name: '@example/sdk', exports: './entry.mjs'}));
  put('outside/sdk/entry.mjs', "export {read} from './owner.mjs';\n");
  put('outside/sdk/owner.mjs', 'export function read(value) {return value;}\n');
  put('owner.md', 'Existing original source, authority, Unknown and cleanup responsibility');
  const declaration = path => {
    const source = readFileSync(join(root, path), 'utf8'), syntax = javascriptInterface(source);
    return {module: path, sha256: hash(source), ...syntax, role: 'physical-io',
      responsibilityFacet: 'primary', owner: 'original physical boundary',
      contracts: [{operations: ['<module>', ...syntax.operations.map(value => value.name)], exports: syntax.exports,
        attributes: Object.fromEntries(interfaceAttributes.map(name => [name,
          [{path: 'owner.md', anchor: 'Existing original source, authority, Unknown and cleanup responsibility'}]]))}]};
  };
  const declarations = ['outside/sdk/entry.mjs', 'outside/sdk/owner.mjs'].map(declaration);
  const save = () => put('elsewhere/interface-boundaries.json', JSON.stringify(declarations));
  const check = (policy, manifests = []) => {
    save();
    const result = spawnSync('npm', ['--prefix', repository, 'run', 'check:interfaces', '--', '--root', root,
      ...manifests.flatMap(value => ['--manifest', value])], {cwd: root, encoding: 'utf8', timeout: 8000});
    assert.equal(result.error, undefined);
    if (policy) {
      assert.equal(result.status, 1, result.stdout + result.stderr);
      assert.match(result.stderr, policy);
    } else {
      assert.equal(result.status, 0, result.stdout + result.stderr);
      assert.match(result.stdout, /"primaryComplete":true/u);
    }
    return result;
  };
  execFileSync('git', ['init', '-q'], {cwd: root});
  return {root, put, declaration, declarations, check};
}

test('the ordinary required command accepts actual manifest imports and safe helper extraction', t => {
  const f = fixture(t);
  f.check();
  f.put('neutral/extracted.mjs', 'export const value = 1;');
  f.put('outside/sdk/owner.mjs', "import {value} from '../../neutral/extracted.mjs';\nexport function read(input) {return input + value;}\n");
  f.declarations[1] = f.declaration('outside/sdk/owner.mjs');
  f.declarations.push(f.declaration('neutral/extracted.mjs'));
  f.check(undefined, ['outside/sdk/package.json']);
});

test('the ordinary required command refuses a reachable unregistered helper outside original directories', t => {
  const f = fixture(t);
  f.put('new-sdk/helper.mjs', 'export const value = 1;');
  f.put('outside/sdk/entry.mjs', "export {value} from '../../new-sdk/helper.mjs';");
  f.declarations[0] = f.declaration('outside/sdk/entry.mjs');
  f.check(/Unregistered distributed interfaces: new-sdk\/helper.mjs/u);
});

test('the ordinary required command refuses an unregistered export after its source digest is updated', t => {
  const f = fixture(t);
  const source = 'export function read(value) {return value;}\nexport const unregistered = 1;';
  f.put('outside/sdk/owner.mjs', source); f.declarations[1].sha256 = hash(source);
  f.check(/Unregistered interface export: outside\/sdk\/owner.mjs/u);
});

test('the ordinary required command refuses stale source hashes and missing operation contracts', t => {
  const f = fixture(t);
  f.declarations[1].sha256 = '0'.repeat(64);
  f.check(/Unreviewed interface implementation/u);
  f.declarations[1] = f.declaration('outside/sdk/owner.mjs');
  f.declarations[1].contracts[0].operations.pop();
  f.check(/Missing operation contract/u);
});

test('the ordinary required command refuses unresolved runtime imports rather than accepting entry-only coverage', t => {
  const f = fixture(t);
  f.put('outside/sdk/entry.mjs', 'export const load = name => import(name);');
  f.declarations[0] = f.declaration('outside/sdk/entry.mjs');
  f.check(/Unresolved interface syntax/u);
});

test('the ordinary required command requires primary responsibility beyond supplemental module union', t => {
  const f = fixture(t);
  f.declarations[1].responsibilityFacet = 'supplemental';
  f.check(/Missing primary interface responsibilities: outside\/sdk\/owner.mjs/u);
});

test('the ordinary required command discovers new Python distribution helpers without folder-role inference', t => {
  const f = fixture(t);
  f.put('new-language/pyproject.toml', '[build-system]\nbuild-backend="setuptools.build_meta"\n[project]\nname="new-owner"\nversion="0.0.1"\n[tool.setuptools.packages.find]\nwhere=["src"]\n');
  f.put('new-language/src/owner/__init__.py', 'def unknown_as_unsent(value):\n    return value\n');
  f.check(/Unregistered distributed interfaces: new-language\/src\/owner\/__init__.py/u);
});

test('lexical runtime references need their actual builder target mapping and preserve unknown/shadowed refusals', async () => {
  const calls = [];
  const resolveRuntimeImport = reference => {calls.push(reference); return reference.kind === 'module-url' ? [reference.specifier] : undefined;};
  const source = "const target = new URL('./retained.mjs', import.meta.url); export const load = () => import(target.href);";
  const positive = javascriptInterface(source, {resolveRuntimeImport});
  assert.deepEqual(positive.imports, ['./retained.mjs']);
  assert.deepEqual(calls, [{kind: 'module-url', specifier: './retained.mjs'}]);
  for (const text of [source.replace('() =>', 'target =>'), source + "target.href = './foreign.mjs';",
    source.replace('const target', 'let target') + "target = new URL('./foreign.mjs', import.meta.url);",
    "export const load = name => import(name);", "const URL = custom; " + source]) {
    assert(javascriptInterface(text, {resolveRuntimeImport}).unresolvedSyntax.length, text);
  }
  assert(javascriptInterface(source).unresolvedSyntax.length, 'a lexical hint alone never qualifies an artifact');
  const packageCalls = [];
  const packageSource = "export async function load() {let resolved; try {resolved = import.meta.resolve('@owner/runtime');} catch {} return import(resolved);}";
  assert.deepEqual(javascriptInterface(packageSource, {resolveRuntimeImport: reference => {
    packageCalls.push(reference); return [reference.specifier];
  }}).unresolvedSyntax, []);
  assert.deepEqual(packageCalls, [{kind: 'package-resolution', specifier: '@owner/runtime'}]);
});


test('actual member-derived dormant inputs need primary coverage and checked source evidence cannot be copied', async t => {
  const f = fixture(t);
  f.put('neutral/dormant.mjs', 'export const value = 1;');
  f.check();
  await assert.rejects(checkInterfaceOwners(f.root, {authoredEntrances: ['neutral/dormant.mjs']}),
    /Unregistered distributed interfaces: neutral\/dormant.mjs/u);
  f.declarations.push(f.declaration('neutral/dormant.mjs')); f.check();
  const checked = await checkInterfaceOwners(f.root, {authoredEntrances: ['neutral/dormant.mjs']});
  const original = checkedOriginalInterface(f.root, 'neutral/dormant.mjs', checked);
  assert.equal(original.module, 'neutral/dormant.mjs');
  assert.throws(() => checkedOriginalInterface(f.root, original.module, structuredClone(checked)),
    /Untrusted checked interface source/u);
  checked.modules.find(value => value.module === original.module).sha256 = '0'.repeat(64);
  assert.equal(checkedOriginalInterface(f.root, original.module, checked).sha256, original.sha256);
});
