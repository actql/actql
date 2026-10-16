import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {compilerBindingTargets} from './generate-js-compiler-bindings.mjs';
import {actionBindingOutputs} from './generate-js-action-bindings.mjs';
import {pathToFileURL} from 'node:url';
import {interfaceGenerationFreshness} from './interface-generation-freshness.mjs';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {javascriptInterface} from './interface-inventory.mjs';

test('existing Owner references change only by explicit primary/supplemental annotation', () => {
  for (const owner of interfaceOwnerDeclarations(process.cwd())) {
    const original = JSON.parse(execFileSync('git',
      ['show', `41e3fc8c2b4bbc1bf6d76c672b583f41576116d5:${owner.id}`], {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024}));
    const current = JSON.parse(readFileSync(owner.id));
    const declarations = Array.isArray(current) ? current : current.declarations;
    for (const value of declarations) {
      const expected = owner.id === 'scripts/interface-owners/js-bindings/interface-boundaries.json' &&
        !original.generated.some(output => output.module === value.module) ? 'supplemental' : 'primary';
      assert.equal(value.responsibilityFacet, expected);
      delete value.responsibilityFacet;
    }
    assert.deepEqual(current, original, owner.id);
  }
});

test('genuine checked generator outputs qualify original compiler and action projections but serialized copies never do', t => {
  const root = process.env.ACTQL_I6_INPUT_ROOT ?? process.cwd();
  const foreign = mkdtempSync(join(tmpdir(), 'actql-foreign-generation-'));
  t.after(() => rmSync(foreign, {recursive: true}));
  const inputSource = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: root, encoding: 'utf8'}), '');
  const checked = interfaceGenerationFreshness(root);
  const original = interfaceOwnerDeclarations(process.cwd()).find(owner =>
    owner.id === 'scripts/interface-owners/js-bindings/interface-boundaries.json');
  const actions = [...actionBindingOutputs(pathToFileURL(join(root, '/'))).keys()].filter(module => module.endsWith('.mjs'));
  assert.equal(actions.length, 3);
  const targets = [...compilerBindingTargets, ...actions];
  const declarations = original.declarations.filter(value => targets.includes(value.module));
  assert.equal(declarations.length, 9);
  const modules = targets.map(module => {
    const bytes = readFileSync(join(root, module));
    return {module, sha256: createHash('sha256').update(bytes).digest('hex'),
      ...javascriptInterface(bytes.toString('utf8'))};
  });
  const options = {root, modules, owners: [{id: original.id, declarations}]};
  const result = interfaceOwnerCoverage({...options, generated: checked.generated});
  assert.equal(result.covered, 9);
  assert.equal(result.primaryComplete, true);
  assert.throws(() => interfaceOwnerCoverage({...options, generated: structuredClone(checked.generated)}),
    /Untrusted generated interface qualification/u);
  assert.throws(() => {checked.generated[0].sha256 = '0'.repeat(64);}, TypeError);
  assert.throws(() => interfaceOwnerCoverage({...options, root: foreign, generated: checked.generated}),
    /another source root/u);
  assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: root, encoding: 'utf8'}), '');
  const source = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  const evidence = join(process.cwd(), '_build', 'interface-evidence');
  mkdirSync(evidence, {recursive: true});
  writeFileSync(join(evidence, `trusted-generation-${source.slice(0, 12)}.json`),
    JSON.stringify({source, inputSource, inputRoot: root, qualification: checked.qualification,
      checked: checked.checked, originalModules: modules.map(({module, sha256}) => ({module, sha256})),
      result, allI6: 'incomplete', newProductE2E: 0}, null, 2) + '\n');
});
