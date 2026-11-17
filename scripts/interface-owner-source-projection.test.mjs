import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {interfaceAttributes, javascriptInterface} from './interface-inventory.mjs';
import {moonOperations, moonApiInterface} from './moon-interface-inventory.mjs';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {projectOwnerSources, projectOwnerSourceUpdates} from './interface-owner-source-projection.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-owner-update-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();
  git(['init', '--quiet']);
  git(['config', 'user.email', 'fixture@example.invalid']);
  git(['config', 'user.name', 'Independent fixture']);
  const write = (path, text) => {
    mkdirSync(join(root, path, '..'), {recursive: true});
    writeFileSync(join(root, path), text);
  };
  const commit = () => {
    git(['add', '.']);
    git(['commit', '--quiet', '-m', 'test: retain independent source fixture']);
    return git(['rev-parse', 'HEAD']);
  };
  write('owner.md', 'Original read boundary and original runtime representation');
  write('outside/connector.mjs', 'export function read(value) {return value;}');
  const base = commit();
  const options = source => ({source, base, paths: ['outside']});
  const original = projectOwnerSources(root, {...options(base), all: true}).modules[0];
  const declaration = {...original, role: 'physical-io', owner: 'Existing physical Owner',
    responsibilityFacet: 'primary', contracts: [{operations: ['<module>', 'read'], exports: ['read'],
      attributes: Object.fromEntries(interfaceAttributes.map(name =>
        [name, [{path: 'owner.md', anchor: 'Original read boundary'}]]))}]};
  const check = (source, declarations, extra = {}) => interfaceOwnerCoverage({root,
    modules: projectOwnerSources(root, {...options(source), all: true}).modules,
    owners: [{id: 'original', declarations}], ...extra});
  return {root, git, write, commit, base, options, declaration, check};
}

test('body-only optional snapshots preserve Git syntax and existing owner contracts', t => {
  const f = fixture(t), original = structuredClone(f.declaration);
  f.write('outside/connector.mjs', 'export function read(value) {return value ?? null;}');
  const source = f.commit();
  // Dirty checkout bytes do not replace the selected immutable Git original.
  f.write('outside/connector.mjs', 'throw new Error("must not execute product");');
  const report = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.equal(report.updates.length, 1);
  const update = report.updates[0];
  assert.equal(update.status, 'changed');
  assert.deepEqual(update.mechanicalFields, ['sha256']);
  assert.deepEqual(update.candidate.contracts, original.contracts);
  for (const key of ['role', 'owner', 'responsibilityFacet']) assert.equal(update.candidate[key], original[key]);
  assert.deepEqual(f.declaration, original, 'candidate generation never mutates a declaration');
  assert.equal(f.check(source, [original]).primaryComplete, true,
    'ownership and syntax checks do not certify behavior through a digest acknowledgement');
  assert.equal(f.check(source, [update.candidate]).primaryComplete, true,
    'syntax/reference gate is separate from semantic review, not an automatic review receipt');
});

test('private extraction stays with the module while a new public export requires its contract', t => {
  const f = fixture(t);
  f.write('outside/connector.mjs', 'function helper(value) {return value;} export function read(value) {return helper(value);} export const extra = 1;');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.deepEqual(update.difference.operations.added, []);
  assert.deepEqual(update.difference.exports.added, ['extra']);
  assert.deepEqual(update.candidate.contracts, f.declaration.contracts);
  assert.throws(() => f.check(source, [update.candidate]), /Missing operation contract/u);
  const reviewed = structuredClone(update.candidate);
  reviewed.contracts[0].exports.push('extra');
  assert.equal(f.check(source, [reviewed]).primaryComplete, true);
});

test('new outside-directory modules get syntax candidates without inferred Owner role or ten references', t => {
  const f = fixture(t);
  f.write('outside/new-host.mjs', 'export const prepare = value => value;');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.equal(update.status, 'unregistered');
  for (const key of ['role', 'owner', 'responsibilityFacet', 'contracts']) assert.equal(key in update.candidate, false);
  assert.throws(() => f.check(source, [f.declaration]), /Unregistered distributed interfaces/u);
  assert.throws(() => f.check(source, [f.declaration, update.candidate]), /Unclassified interface responsibility facet/u);
});

test('removed-only and empty diffs are diagnostic candidates, never weakened ordinary projection or admission', t => {
  const f = fixture(t);
  assert.throws(() => projectOwnerSources(f.root, f.options(f.base)), /No owner product sources/u);
  assert.deepEqual(projectOwnerSourceUpdates(f.root, f.options(f.base), [f.declaration]).updates, []);
  rmSync(join(f.root, 'outside/connector.mjs'));
  f.write('outside/control.test.mjs', 'export const authority = true;');
  const source = f.commit();
  const {updates} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.equal(updates.length, 1);
  assert.equal(updates[0].module, 'outside/connector.mjs');
  assert.equal(updates[0].status, 'removed');
  assert.equal(updates[0].candidate, null);
  assert.deepEqual(updates[0].difference.operations.removed, ['read']);
  assert.deepEqual(updates[0].difference.exports.removed, ['read']);
});

test('candidate syntax cannot self-approve raw compiler access, missing primary, or forged generation', t => {
  const f = fixture(t);
  f.write('outside/connector.mjs', 'export function read(value) {return value["_0"];}');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.deepEqual(update.candidate.compilerFields, ['_0']);
  assert.throws(() => f.check(source, [update.candidate]), /Compiler representation outside generated binding/u);
  const forged = {...update.candidate, role: 'generated-binding'};
  assert.throws(() => f.check(source, [forged]), /Unverified generated binding/u);
  assert.throws(() => f.check(source, [forged], {generated: [{module: forged.module,
    sha256: forged.sha256, generator: {path: 'owner.md', anchor: 'Original read boundary'},
    freshness: {path: 'owner.md', anchor: 'Original read boundary'}}]}), /Untrusted generated interface qualification/u);
  const supplemental = {...f.declaration, responsibilityFacet: 'supplemental'};
  assert.throws(() => f.check(f.base, [supplemental]), /Missing primary interface responsibilities/u);
});

test('operation parameter changes and removals remain visible and duplicate facets are not concatenated', t => {
  const f = fixture(t);
  f.write('outside/connector.mjs', 'export function read(original, current) {return current ?? original;}');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.deepEqual(update.difference.operations.changed, ['read']);
  assert.deepEqual(update.candidate.operations[0].parameters, ['original', 'current']);
  assert.throws(() => projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration, f.declaration]),
    /Duplicate owner update declaration/u);
});

test('copied references are not auto-approved or replaced when their original anchor disappears', t => {
  const f = fixture(t);
  f.write('outside/connector.mjs', 'export function read(value) {return value ?? null;}');
  f.write('owner.md', 'A different boundary cannot approve the original contract');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.deepEqual(update.candidate.contracts, f.declaration.contracts);
  assert.throws(() => f.check(source, [update.candidate]), /Missing interface reference:/u);
});


// Narrow reviewed construction references; not a distribution closure or runtime proof.
const root = fileURLToPath(new URL('../', import.meta.url));
// Explicit reviewed paths; this list cannot admit an unknown distributed module.
const modules = [
  "adapters/host-common/authorization-gate.mjs",
  "adapters/host-node/account-construction.mjs",
  "adapters/host-node/client-checkpoints.mjs",
  "adapters/host-node/embedded-local.mjs",
  "adapters/host-node/infer-operation.mjs",
  "adapters/host-node/installed-funded-environment.mjs",
  "adapters/host-node/installed-host-services.mjs",
  "adapters/host-node/installed-model.mjs",
  "adapters/host-node/installed-project-model-tasks.mjs",
  "adapters/host-node/installed-row-source.mjs",
  "adapters/host-node/local-account-config.mjs",
  "adapters/host-node/ordinary-local-account.mjs",
  "src/canonical_json/source_conversion_extent.mbt",
  "src/check_environment/model_task_construction.mbt",
  "src/check_environment/public_model_task_construction.mbt",
  "src/check_environment/public_model_task_environment_construction.mbt",
  "src/check_environment/public_model_task_normalization.mbt",
  "src/client_local_host/preparation_host_account.mbt",
  "src/client_local_host/preparation_request_capture_body.mbt",
  "src/client_local_host/preparation_request_content_body.mbt",
  "src/client_local_host/preparation_request_model_body.mbt",
  "src/client_local_host/preparation_request_normalization.mbt",
  "src/client_local_host/preparation_request_normalization_layout.mbt",
  "src/client_local_host/preparation_request_parent.mbt",
  "src/client_local_host/preparation_request_program_body.mbt",
  "src/cmd/native_client/local_account_preparation.mbt",
  "src/cmd/native_client/local_command_business_preparation.mbt",
  "src/cmd/native_client/local_command_business_request.mbt",
  "src/cmd/native_client/local_command_diagnostic.mbt",
  "src/cmd/native_client/local_command_preparation.mbt",
  "src/cmd/native_client/local_publisher_diagnostic.mbt",
  "src/connectors_builtin_node/client_account_construction_bridge.mbt",
  "src/connectors_builtin_node/client_check_environment_construction_bridge.mbt",
  "src/connectors_builtin_node/client_model_task_construction_bridge.mbt",
  "src/connectors_builtin_node_rela/client_check_environment_construction_bridge.mbt",
  "src/connectors_builtin_node_rela/client_model_task_construction_bridge.mbt",
  "src/execution_authorization/construction.mbt",
  "src/physical_resources/preparation_account_read.mbt",
  "src/physical_resources/preparation_phase_work.mbt",
  "src/platform_native/client_host/local_account_construction.mbt",
  "src/platform_native/client_host/submitted_preparation.mbt",
  "src/platform_native/client_host/submitted_request_preparation.mbt",
  "src/program_check/local_common_normalization.mbt",
  "src/program_check/local_common_normalization_construction.mbt",
  "src/run_publication_host/client_environment.mbt",
  "src/run_publication_host/client_infer_call_scope.mbt",
  "src/run_publication_host/client_infer_scope_snapshot_construction.mbt",
  "src/run_publication_host/client_local_normalization.mbt",
  "src/run_publication_host/client_local_normalization_preparation.mbt",
  "src/run_publication_host/client_model_defaults_construction.mbt",
  "src/source_value/yaml_construction_extent.mbt"
];
const sidecars = [
  "scripts/interface-owners/connector-functional/interface-boundaries.json",
  "scripts/interface-owners/core-functional/interface-boundaries.json",
  "scripts/interface-owners/host-functional/interface-boundaries.json",
  "scripts/interface-owners/host-primary/interface-boundaries.json",
  "scripts/interface-owners/js-bindings/interface-boundaries.json",
  "scripts/interface-owners/model-provider/interface-boundaries.json",
  "scripts/interface-owners/python-local/interface-boundaries.json",
  "src/check_environment/wire-admission-construction-interface-boundaries.json",
  "src/client_local_host/ordered-direct-inputs-interface-boundaries.json"
];
const actual = modules.map(module => {
  const bytes = readFileSync(new URL('../'+module, import.meta.url)), source = bytes.toString('utf8');
  return {module, sha256:createHash('sha256').update(bytes).digest('hex'),
    ...(module.endsWith('.mbti') ? moonApiInterface(source) : module.endsWith('.mbt')
      ? {exports:[],operations:moonOperations(source)} : javascriptInterface(source))};
});
const owners = sidecars.map(id => {
  const value = JSON.parse(readFileSync(new URL('../'+id, import.meta.url), 'utf8'));
  return {id,declarations:(Array.isArray(value)?value:value.declarations).filter(row=>modules.includes(row.module))};
});
// The raw embedded entrance still needs the real dependency Owner/artifact
// mapping. Keep that unresolved result; this focused reference check cannot
// manufacture the missing six-root closure qualification.
const unresolved = actual.filter(row=>row.unresolvedSyntax?.length);
const resolvedSource = actual.filter(row=>!row.unresolvedSyntax?.length);
const check = (selectedOwners=owners, selectedModules=resolvedSource) => interfaceOwnerCoverage({root,
  modules:selectedModules,owners:selectedOwners,requireComplete:true});

test('reviewed Account Model construction checks51 syntax snapshots and50 Source references without resolving runtime entrances', () => {
  assert.deepEqual(unresolved.map(row=>row.module),['adapters/host-node/embedded-local.mjs']);
  const embedded=unresolved[0];
  for(const owner of owners) for(const declaration of owner.declarations.filter(row=>row.module===embedded.module)) {
    assert.deepEqual(declaration.exports,embedded.exports);
    assert.deepEqual(declaration.operations,embedded.operations.filter(value=>!embedded.privateOperations.includes(value.name)));
  }
  assert.throws(()=>check(owners,actual),/Unresolved interface syntax/u);
  const result=check();
  assert.equal(result.complete,true);assert.equal(result.primaryComplete,true);
  assert.equal(result.modules,50);assert.deepEqual(result.missing,[]);assert.deepEqual(result.missingPrimary,[]);
});

test('construction ownership cannot admit an unknown module from a snapshot', () => {
  const account=actual.find(row=>row.module==='adapters/host-node/account-construction.mjs');
  const without=owners.map(owner=>({...owner,declarations:owner.declarations.filter(row=>row.module!==account.module)}));
  assert.throws(()=>check(without),/Unregistered distributed interfaces/u);
});

test('reviewed construction references retain operation membership and real design or authored test anchors', () => {
  const altered=structuredClone(owners);
  const owner=altered.find(row=>row.declarations.some(d=>d.module==='adapters/host-node/account-construction.mjs'));
  const declaration=owner.declarations.find(row=>row.module==='adapters/host-node/account-construction.mjs');
  declaration.contracts[0].operations.pop();
  assert.throws(()=>check(altered),/Missing operation contract/u);
  const changed=structuredClone(owners);
  changed.find(row=>row.id===owner.id).declarations.find(row=>row.module===declaration.module)
    .contracts[0].attributes.identity[0].anchor='Unreviewed replacement identity';
  assert.throws(()=>check(changed),/Missing interface reference/u);
});

test('empty and populated CheckEnvironment constructors retain distinct Source proof domains', () => {
  const wire=owners.find(row=>row.id==='src/check_environment/wire-admission-construction-interface-boundaries.json');
  for(const module of ['src/connectors_builtin_node/client_check_environment_construction_bridge.mbt',
    'src/connectors_builtin_node_rela/client_check_environment_construction_bridge.mbt']) {
    const d=wire.declarations.find(row=>row.module===module);
    const empty=d.contracts.find(c=>c.operations.includes('client_program_check_environment_from_wire_construction_capacity'));
    const populated=d.contracts.find(c=>c.operations.includes('client_program_check_environment_model_from_wire_construction_capacity'));
    assert(empty&&populated&&empty!==populated);
    assert(empty.attributes.responsibility.some(ref=>ref.anchor==='- Responsibility:'));
    assert(populated.attributes.responsibility.some(ref=>ref.anchor==='- Populated responsibility:'));
    assert(!empty.operations.includes('client_program_check_environment_model_from_wire_with_graph_profile'));
    assert(populated.operations.includes('client_program_check_environment_model_from_wire_with_graph_profile'));
  }
});

// Explicit final construction/cold/physical tail; Source references only.
const finalTailModules = [
  "adapters/host-node/installed-row-effect.mjs",
  "adapters/host-node/infer-evaluation-evidence.mjs",
  "adapters/host-node/infer-operation.mjs",
  "adapters/host-node/installed-composed-infer-run.mjs",
  "adapters/host-node/installed-infer-run.mjs",
  "src/client_local_host/installed_effect_operation_demand.mbt",
  "src/client_local_host/installed_mock_model_plan.mbt",
  "src/client_local_host/preparation_request_effect_body.mbt",
  "src/client_local_host/preparation_request_program_body.mbt",
  "src/connectors_builtin_node/client_installed_effect_model_plan_bridge.mbt",
  "src/run_publication_host/client_model_read_preparation.mbt",
  "src/client_local_host/preparation_request_models_plan.mbt",
  "adapters/host-node/infer-capture-custody.mjs",
  "adapters/local-node/installed-project-mock-answers.mjs",
  "adapters/host-node/local-account-config.mjs",
  "adapters/host-node/installed-effect-managed-run.mjs",
  "adapters/host-node/account-construction.mjs",
  "adapters/host-node/acquired-effect-computation.mjs",
  "adapters/host-node/embedded-local.mjs",
  "src/model_execution/execution.mbt",
  "adapters/local-node/carrier-snapshot.mjs",
  "adapters/connectors/local/host/installed-project-file-effects.mjs"
];
const finalTailSidecars = [
  "scripts/interface-owners/connector-functional/interface-boundaries.json",
  "scripts/interface-owners/core-functional/interface-boundaries.json",
  "scripts/interface-owners/durable-observation/interface-boundaries.json",
  "scripts/interface-owners/host-functional/interface-boundaries.json",
  "scripts/interface-owners/host-primary/interface-boundaries.json",
  "scripts/interface-owners/js-bindings/interface-boundaries.json",
  "scripts/interface-owners/model-provider/interface-boundaries.json",
  "scripts/interface-owners/store-physical/interface-boundaries.json",
  "src/client_local_host/ordered-direct-inputs-interface-boundaries.json",
  "src/connectors/local/files-interface-boundaries.json"
];
const finalTailActual = finalTailModules.map(module => {
  const bytes=readFileSync(new URL('../'+module,import.meta.url)), source=bytes.toString('utf8');
  return {module,sha256:createHash('sha256').update(bytes).digest('hex'),
    ...(module.endsWith('.mbt')?{exports:[],operations:moonOperations(source)}:javascriptInterface(source))};
});
const finalTailOwners=finalTailSidecars.map(id=>{
  const value=JSON.parse(readFileSync(new URL('../'+id,import.meta.url),'utf8'));
  return {id,declarations:(Array.isArray(value)?value:value.declarations).filter(d=>finalTailModules.includes(d.module))};
});
const finalTailResolved=finalTailActual.filter(row=>!row.unresolvedSyntax?.length);
const checkFinalTail=(selectedOwners=finalTailOwners,selectedModules=finalTailResolved)=>
  interfaceOwnerCoverage({root,modules:selectedModules,owners:selectedOwners,requireComplete:true});

test('stable Model File cold Mock Account and row publication tail retains22 exact syntax and21 resolved Source contracts',()=>{
  const unresolved=finalTailActual.filter(row=>row.unresolvedSyntax?.length);
  assert.deepEqual(unresolved.map(row=>row.module),['adapters/host-node/embedded-local.mjs']);
  for(const owner of finalTailOwners) for(const declaration of owner.declarations.filter(d=>d.module===unresolved[0].module)) {
    assert.deepEqual(declaration.exports,unresolved[0].exports);
    assert.deepEqual(declaration.operations,unresolved[0].operations.filter(value=>!unresolved[0].privateOperations.includes(value.name)));
  }
  assert.throws(()=>checkFinalTail(finalTailOwners,finalTailActual),/Unresolved interface syntax/u);
  const checked=checkFinalTail();assert.equal(checked.complete,true);assert.equal(checked.primaryComplete,true);
  assert.equal(checked.modules,21);assert.deepEqual(checked.missing,[]);
});

test('final tail Source references cannot bless missing numeric-span ownership or foreign anchors',()=>{
  const original=finalTailResolved.find(d=>d.module==='src/run_publication_host/client_model_read_preparation.mbt');
  const altered=structuredClone(finalTailOwners);
  const preparation=altered.flatMap(o=>o.declarations).find(d=>d.module===original.module);
  preparation.contracts[0].operations=preparation.contracts[0].operations.filter(name=>name!=='grow_client_model_read_preparation_consumer_span');
  assert.throws(()=>checkFinalTail(altered),/Missing operation contract/u);
  const foreign=structuredClone(finalTailOwners);
  const mock=foreign.flatMap(o=>o.declarations).find(d=>d.module==='adapters/local-node/installed-project-mock-answers.mjs');
  const projection=mock.contracts.find(c=>c.exports.includes('prepareInstalledMockRegistrySelection'));
  projection.attributes.identity.push({path:'docs/design/model-provider-registration.md',anchor:'A copied inventory funds registry selection'});
  assert.throws(()=>checkFinalTail(foreign),/Missing interface reference/u);
});
