import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {test} from 'node:test';
import {interfaceAttributes, javascriptClosure, assertInterfaceCoverage}
  from './interface-inventory.mjs';
import {typescriptInterfaceClosure} from './typescript-interface-inventory.mjs';

for (const [language, extension, closure] of [
  ['TypeScript', 'ts', typescriptInterfaceClosure],
  ['JavaScript', 'mjs', javascriptClosure],
]) test(`${language} runtime-dependent imports cannot silently disappear from strict interface admission`, t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-dynamic-interface-'));
  t.after(() => rmSync(root, {recursive: true}));
  writeFileSync(join(root, 'owner.md'), 'Existing original physical module loading boundary');
  const entry = `entry.${extension}`, peer = `outside-owner.${extension}`;
  writeFileSync(join(root, peer), 'export const value = 1;\n');
  const registration = module => ({...module, role: 'physical-io', owner: 'original physical module boundary',
    contracts: [{operations: ['<module>', ...module.operations.map(op => op.name)], exports: module.exports,
      attributes: Object.fromEntries(interfaceAttributes.map(name => [name,
        [{path: 'owner.md', anchor: 'Existing original physical module loading boundary'}]]))}]});
  // Same positive and refusal as the original independent counterexample.
  writeFileSync(join(root, entry), `export const load = () => import('./${peer}');\n`);
  const positive = closure(root, [entry]);
  assert.equal(positive.length, 2);
  assert.equal(assertInterfaceCoverage({root, modules: positive, declarations: positive.map(registration)}), 2);
  writeFileSync(join(root, entry), 'export const load = name => import(name);\n');
  assert.throws(() => {
    const actual = closure(root, [entry]);
    for (const module of actual) assert.equal(module.sha256,
      createHash('sha256').update(readFileSync(join(root, module.module))).digest('hex'));
    return assertInterfaceCoverage({root, modules: actual, declarations: actual.map(registration)});
  }, /Unresolved interface syntax/u);
});

for (const [language, extension, closure] of [
  ['TypeScript', 'ts', typescriptInterfaceClosure],
  ['JavaScript', 'mjs', javascriptClosure],
]) test(`${language} keeps closed import/require targets but does not evaluate runtime target expressions`, t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-import-targets-'));
  t.after(() => rmSync(root, {recursive: true}));
  const entry = `entry.${extension}`, peer = `owner.${extension}`;
  writeFileSync(join(root, peer), 'export const value = 1;');
  for (const expression of [`import(\`./${peer}\`)`, `import('./owner.' + '${extension}')`, `require('./${peer}')`]) {
    writeFileSync(join(root, entry), `export const load = () => ${expression};`);
    const actual = closure(root, [entry]);
    assert.equal(actual.length, 2, expression);
    assert(actual.every(module => !module.unresolvedSyntax?.length), expression);
  }
  for (const expression of ['require(name)', 'import(prefix + name)', 'import(`${prefix}${name}`)']) {
    writeFileSync(join(root, entry), `export const load = (name, prefix) => ${expression};`);
    assert(closure(root, [entry]).some(module => module.unresolvedSyntax?.length), expression);
  }
});
