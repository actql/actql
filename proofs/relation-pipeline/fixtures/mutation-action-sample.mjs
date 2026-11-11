// Controlled registration and receipt fixtures only; no actual executions or provenance.
import {hash} from '../../ci-evidence/inputs.mjs';
import {mutationSourceInputs} from '../mutation-actions.mjs';
import {mutationPart, mutationReportPath} from '../mutation-parts.mjs';
import {mutationNamesByPart} from '../proof-parts.mjs';
import {variants} from '../mutation-registry.mjs';
import {executionCommand} from '../fixture.mjs';
const digest = value => hash(JSON.stringify(value));
const revision = 'a'.repeat(40), targets = ['js', 'wasm', 'native'];
export function inputTree() {
  const paths = ['adapters/host-node/ordinary-node-resource-runtime.cjs', 'scripts/owned-scratch.mjs', 'scripts/native-cxx-link-driver.sh', 'scripts/ar',
    'toolchain.json', 'moon.mod', 'package.json', 'package-lock.json', '.github/workflows/ci.yml',
    'docs/spec/language.md', 'docs/spec/execution.md', 'src/query_integration/moon.pkg',
    'vendor/package/data', 'proofs/bounded-session/check.mjs', 'proofs/relation-chain/check.mjs',
    'proofs/relation-capacity/check.mjs', 'proofs/relation-pipeline/mutation-actions.mjs',
    'proofs/ci-evidence/check.mjs', 'proofs/ci-evidence/Reuse.lean', 'proofs/ci-evidence/Claims.lean',
    'proofs/ci-evidence/inputs.mjs', 'proofs/ci-evidence/package-configurations.mjs',
    'proofs/ci-evidence/receipts.mjs', 'proofs/ci-evidence/transport.mjs',
    'scripts/ci-artifact-reader.mjs', 'scripts/ci-main-base.mjs',
    ...variants.map(entry => entry.path)];
  const contents = new Map([...new Set(paths)].map(path => [path, Buffer.from(`synthetic ${path}`)]));
  return {entries: new Map([...contents.keys()].map(path => [path, {kind: 'blob', mode: '100644'}])),
    read: path => contents.get(path), contents};
}
export function snapshot(tree) {
  const sources = Object.fromEntries([...tree.entries.keys()].filter(path => !path.startsWith('proofs/ci-evidence/') && !['scripts/ci-artifact-reader.mjs', 'scripts/ci-main-base.mjs'].includes(path))
    .sort().map(path => [path, hash(tree.read(path))]));
  return {sources, digest: digest(sources)};
}
function sample(part, mode, source, decision) {
  const workspaces = {mutable: {id: `${part}-mutable`, root: `/synthetic/${part}/mutable`},
    pristine: {id: `${part}-pristine`, root: `/synthetic/${part}/pristine`}};
  const restorationOwner = {id: `${part}-new-owner`, root: workspaces.mutable.root};
  return {version: 'actql-relation-pipeline-mutations/0.1', part: mutationPart(part),
    closure: {mutable: true, pristine: true, restoration: true, sourceRestored: true},
    workspaces, restorationOwner, source, revision, toolchain: {moonc: 'synthetic compiler'}, mode, decision,
    seed: mode === 'explore' ? 105106 : null, explorationTarget: mode === 'explore' ? 'js' : null,
    searchDomain: 'controlled domain', meaning: 'controlled evidence',
    results: mutationNamesByPart[part].map(name => {
      const site = variants.find(entry => entry.name === name).path;
      const changedSources = {...source.sources, [site]: hash(name)};
      const changed = {sources: changedSources, digest: digest(changedSources)};
      const minimal = {id: name, rows: [{id: 'row-identity', values: {k: null, text: 'e\u0301'}}],
        steps: [{id: 'step-0', op: 'select'}]};
      function execution(phase, target, workspace, source, correspondence) {
        const id = `${part}-${mode}-${name}-${phase}-${target}`;
        const observation = {id, rows: [[null, 'e\u0301']], columns: ['k', 'text'],
          schemaColumns: ['k', 'text'], wireRows: [{k: null, text: 'e\u0301'}],
          kind: correspondence ? 'complete' : 'failed', correspondence, checked: true, registered: true,
          work: 3, orderOrigin: 'input:0', faults: correspondence ? [] : [{kind: 'synthetic mismatch'}],
          stageValues: [{rows: [[null, 'e\u0301']]}]};
        const command = executionCommand(target);
        const boundary = {target, command, role: workspace === workspaces.pristine ? 'pristine' : 'mutable',
          workspace: workspace.id, root: workspace.root, sourceDigest: source.digest};
        const receipt = {target, command, compiler: 'synthetic compiler', exit: 0,
          sourceDigest: source.digest, correspondence, boundary, buildIdentity: digest(boundary),
          cases: [{id, testCase: minimal, caseDigest: digest(minimal), program: {source: 'input', steps: 'steps'}, observation}]};
        return {path: `.artifacts/relation-pipeline/${id}.json`, receipt, digest: digest(receipt)};
      }
      const mutated = targets.map(target => execution('mutated', target, workspaces.mutable, changed, false));
      const healthy = targets.map(target => execution('pristine', target, workspaces.pristine, source, true));
      const restored = targets.map(target => execution('post-restore', target, restorationOwner, source, true));
      const search = mode === 'explore' ? ['search', 'shrink'].map(phase => execution(phase, 'js', workspaces.mutable, changed, false)) : [];
      const observations = entries => Object.fromEntries(entries.map(entry => [entry.receipt.target, entry.receipt.cases[0].observation]));
      return {name, owner: part, site, source: changed, originalDigest: source.sources[site], mutatedDigest: changed.sources[site],
        anchor: {fault: name}, original: minimal, minimal, killed: true, localMinimal: mode === 'explore',
        ...(mode === 'explore' ? {history: [{attempted: 1, accepted: -1}], finalCandidates: [minimal],
          finalObservations: [search.at(-1).receipt.cases[0].observation]} : {}),
        executions: [...search, ...mutated], replay: observations(mutated), healthy: observations(healthy), healthyExecutions: healthy,
        postRestore: {executions: restored, observations: observations(restored)}};
    })};
}
export function cohort(required = true) {
  const tree = inputTree(), source = snapshot(tree), decision = {required, revision};
  const sourceInputs = mutationSourceInputs({tree, source});
  const reports = Object.keys(mutationNamesByPart).flatMap(part => (required ? ['fixed', 'explore'] : ['fixed'])
    .map(mode => {const report = sample(part, mode, source, decision);
      return {path: mutationReportPath(part, mode), bytesDigest: hash(`${JSON.stringify(report, null, 2)}\n`), report};}));
  const auditedReceipts = new Map();
  for (const {report} of reports) for (const result of report.results) {
    for (const entry of [...result.executions, ...result.healthyExecutions, ...result.postRestore.executions])
      auditedReceipts.set(entry.path, {receiptDigest: entry.digest, bytesDigest: hash(`${JSON.stringify(entry.receipt)}\n`)});
  }
  return {tree, source, decision, sourceInputs, reports, auditedReceipts};
}
