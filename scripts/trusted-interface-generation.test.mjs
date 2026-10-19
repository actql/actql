import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
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

test('genuine checked generator outputs qualify original compiler and action projections but serialized copies never do', t => {
  const root = process.env.ACTQL_I6_INPUT_ROOT ?? process.cwd();
  const foreign = mkdtempSync(join(tmpdir(), 'actql-foreign-generation-'));
  t.after(() => rmSync(foreign, {recursive: true}));
  const inputSource = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: root, encoding: 'utf8'}), '');
  const checked = interfaceGenerationFreshness(root);
  assert.equal(new Set(checked.checked).size, checked.checked.length);
  assert(checked.checked.includes('lowering-registry-vectors.mjs'));
  assert(checked.checked.includes('native-cli-default-assets.mjs'));
  assert(checked.checked.includes('compilation-manifests.mjs'));
  assert(checked.checked.includes('catalog-body-dependencies.mjs'));
  assert(checked.checked.includes('check-stage-semantics.mjs'));
  assert(checked.checked.includes('current-timestamp-expression-contract.mjs'));
  for (const name of ['query-acquisition-contract.mjs', 'query-process-evidence.mjs',
    'query-two-receipt.mjs', 'query-resource-scopes.mjs', 'check-query-evidence-fixtures.mjs',
    'fixed-compute-capacity.mjs', 'managed-runtime-vectors.mjs']) {
    assert(checked.checked.includes(name));
  }
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

// Shadow only the selected original input; all other files remain read-only
// links. Never mutate the producer root or reinterpret generated proof DATA.
function shadowOriginal(root, relative) {
  const scratch = mkdtempSync(join(tmpdir(), 'actql-query-freshness-'));
  const parts = relative.split('/');
  let source = root, target = scratch;
  for (const selected of parts) {
    for (const entry of readdirSync(source)) {
      if (entry === selected || entry === '.git' || entry === '_build') continue;
      symlinkSync(join(source, entry), join(target, entry));
    }
    source = join(source, selected); target = join(target, selected);
    if (selected !== parts.at(-1)) mkdirSync(target);
    else writeFileSync(target, readFileSync(source));
  }
  return scratch;
}

test('ordinary genuine freshness refuses a stale query dependency before qualification', t => {
  const root = process.env.ACTQL_I6_INPUT_ROOT ?? process.cwd();
  const relative = 'spec/contracts/actql-query-acquisition.json';
  const scratch = shadowOriginal(root, relative);
  t.after(() => rmSync(scratch, {recursive: true}));
  const path = join(scratch, relative), body = JSON.parse(readFileSync(path));
  body.dependencies.canonical_value_contract.cid = 'sha256:08c311d9a05b323ea6fde184981a965773ee71059c61bf3a830ab0e295c21947';
  writeFileSync(path, JSON.stringify(body));
  assert.throws(() => interfaceGenerationFreshness(scratch), error => {
    assert.match(String(error), /query-acquisition-contract\.mjs/u);
    assert.match(String(error), /canonical_value_contract/u);
    return true;
  });
});

test('ordinary genuine freshness refuses an older actual query verifier pin', t => {
  const root = process.env.ACTQL_I6_INPUT_ROOT ?? process.cwd();
  const relative = 'src/sourceview_resolution/query_acquisition.mbt';
  const scratch = shadowOriginal(root, relative);
  t.after(() => rmSync(scratch, {recursive: true}));
  const path = join(scratch, relative);
  const source = readFileSync(path, 'utf8');
  const changed = source.replace(/(pub fn query_acquisition_contract_cid\(\) -> String \{\s*)"sha256:[a-f0-9]{64}"/u,
    '$1"sha256:355aaf391cdf44afc51dbb520117305db992fcfa51c0a5714192e82071d7b6c1"');
  assert.notEqual(changed, source);
  writeFileSync(path, changed);
  assert.throws(() => interfaceGenerationFreshness(scratch), /Stale actual verifier pin/u);
});

test('ordinary genuine freshness refuses a stale fixed-input fragment dependency', t => {
  const root = process.env.ACTQL_I6_INPUT_ROOT ?? process.cwd();
  const relative = 'spec/contracts/actql-fixed-compute-capacity.json';
  const scratch = shadowOriginal(root, relative);
  t.after(() => rmSync(scratch, {recursive: true}));
  const path = join(scratch, relative), body = JSON.parse(readFileSync(path));
  body.dependencies.fragment.cid = 'sha256:b924311d35a118ab7ba0944690f6175606d8fcea0fdb89ad8bb8071fa7f589e3';
  writeFileSync(path, JSON.stringify(body));
  assert.throws(() => interfaceGenerationFreshness(scratch), error => {
    assert.match(String(error), /fixed-compute-capacity\.mjs/u);
    assert.match(String(error), /fragment/u);
    return true;
  });
});

test('ordinary genuine freshness refuses a stale managed-profile dependency before proof', t => {
  const root = process.env.ACTQL_I6_INPUT_ROOT ?? process.cwd();
  const relative = 'spec/contracts/actql-managed-retained-execution.json';
  const scratch = shadowOriginal(root, relative);
  t.after(() => rmSync(scratch, {recursive: true}));
  const path = join(scratch, relative), body = JSON.parse(readFileSync(path));
  body.dependencies.fixed_compute_capacity.cid = 'sha256:65d84800fb462f842e4ba38118c3e23b2441a7d1620fbf979705439d8b9dad8d';
  writeFileSync(path, JSON.stringify(body));
  assert.throws(() => interfaceGenerationFreshness(scratch), /fixed-compute capacity dependency is stale/u);
});

// A stale interpretation CID must fail the normal generation gate before the
// emitted Unit can carry a contract different from its independent oracle.
test('ordinary genuine freshness refuses a stale Program grammar interpretation pin', t => {
  const root = process.env.ACTQL_I6_INPUT_ROOT ?? process.cwd();
  const relative = 'src/check_environment/program_grammar.generated.mbt';
  const scratch = shadowOriginal(root, relative);
  t.after(() => rmSync(scratch, {recursive: true}));
  const path = join(scratch, relative);
  const original = readFileSync(path, 'utf8');
  const stale = original.replace(/sha256:[a-f0-9]{64}/u, 'sha256:' + '0'.repeat(64));
  assert.notEqual(stale, original);
  writeFileSync(path, stale);
  assert.throws(() => interfaceGenerationFreshness(scratch), error => {
    assert.match(String(error), /catalog-body-dependencies\.mjs/u);
    return true;
  });
});

// A current expression body must be the actual Stage pointer used by closure.
test('ordinary genuine freshness refuses a stale Stage expression contract pin', t => {
  const root = process.env.ACTQL_I6_INPUT_ROOT ?? process.cwd();
  const relative = 'src/program_references/stage_expression_contract.generated.mbt';
  const scratch = shadowOriginal(root, relative);
  t.after(() => rmSync(scratch, {recursive: true}));
  const path = join(scratch, relative);
  const original = readFileSync(path, 'utf8');
  const stale = original.replace(/sha256:[a-f0-9]{64}/u, 'sha256:' + '0'.repeat(64));
  assert.notEqual(stale, original);
  writeFileSync(path, stale);
  assert.throws(() => interfaceGenerationFreshness(scratch), /check-stage-semantics\.mjs/u);
});
