// Fresh pipeline obligations use the existing incremental evidence checker.
// Source correspondence is not a closed runtime or an Actions trust witness.
import assert from 'node:assert/strict';
import {lstatSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {encode} from '../bounded-session/action-inputs.mjs';
import {gitTree, hash} from '../ci-evidence/inputs.mjs';
import {checkPlan} from '../ci-evidence/check.mjs';
import {mutationNamesByPart, planDigest} from './proof-parts.mjs';
import {inspectMutationPart, inspectArchivedMutationPart, mutationReportPath} from './mutation-parts.mjs';
import {executionCommand, fixturePath} from './fixture.mjs';

const parts = Object.keys(mutationNamesByPart);
const targets = ['js', 'wasm', 'native'];
const phases = ['mutated', 'pristine', 'post-restore'];
const directories = ['src', 'vendor', 'proofs/bounded-session', 'proofs/relation-chain',
  'proofs/relation-capacity', 'proofs/relation-pipeline'];
const snapshotFiles = ['adapters/host-node/ordinary-node-resource-runtime.cjs', 'scripts/owned-scratch.mjs', 'scripts/native-cxx-link-driver.sh',
  'scripts/ar', 'toolchain.json', 'moon.mod', 'package.json', 'package-lock.json',
  '.github/workflows/ci.yml', 'docs/spec/language.md', 'docs/spec/execution.md'];
const checkerFiles = ['proofs/ci-evidence/check.mjs', 'proofs/ci-evidence/Reuse.lean',
  'proofs/ci-evidence/Claims.lean', 'proofs/ci-evidence/inputs.mjs',
  'proofs/ci-evidence/package-configurations.mjs', 'proofs/ci-evidence/receipts.mjs',
  'proofs/ci-evidence/transport.mjs', 'scripts/ci-artifact-reader.mjs', 'scripts/ci-main-base.mjs'];
const residual = Object.freeze([
  'pipeline-runtime: inherited environment, OS/loader/libraries and external compiler tools are not closed',
  'pipeline-workspace: mutable build state and execution-time filesystem inputs need an isolated contract',
]);
const digest = value => hash(JSON.stringify(value));
const modes = decision => {
  assert.equal(typeof decision?.required, 'boolean', 'Missing independent exploration decision');
  return decision.required ? ['fixed', 'explore'] : ['fixed'];
};
export const mutationActionVersion = 'actql-pipeline-mutation-actions/0.1';

// Required coverage comes from the reviewed partition and current classifier,
// never from the available reports, executions or observations.
export function mutationActions(decision) {
  return mutationActionScope(decision, planDigest, mutationNamesByPart);
}
function mutationActionScope(decision, requiredPlanDigest, assignments) {
  return Object.keys(assignments).flatMap(part => modes(decision).flatMap(mode => targets.flatMap(target => phases.map(phase => ({
    id: `pipeline-${part.toLowerCase()}-${mode}-${target}-${phase}`,
    part, mode, target, phase, kind: 'tested-refinement', command: executionCommand(target),
    minimumUnits: assignments[part].length,
    profile: {planDigest: requiredPlanDigest, variants: [...assignments[part]], mode, phase,
      explorationTarget: mode === 'explore' ? 'js' : null, seed: mode === 'explore' ? 105106 : null},
    premises: ['existing-full-scientific-audit', 'exact-original-source-and-receipts',
      'independent-pristine-and-new-owner-restoration', 'finite-typed-relation-domain'],
  })))));
}

// Keep the current wide workspace inventory, independently enumerated from Git.
// Compare it to the existing source snapshot instead of trusting report paths.
// Adding a new snapshot dependency must update this adapter, not silently narrow it.
export function mutationSourceInputs({tree, source, root}) {
  const members = directories.map(path => ({path: `${path}/**`, members: [...tree.entries.keys()]
    .filter(file => file.startsWith(`${path}/`) && file !== fixturePath).sort()}));
  const paths = [...new Set([...members.flatMap(entry => entry.members), ...snapshotFiles])].sort();
  assert.deepEqual(Object.keys(source.sources).sort(), paths, 'Pipeline snapshot/input membership differs');
  assert.equal(source.digest, digest(source.sources), 'Pipeline snapshot digest differs');
  const selected = [...new Set([...paths, ...checkerFiles])].sort();
  for (const path of selected) {
    const entry = tree.entries.get(path);
    assert(entry?.kind === 'blob' && ['100644', '100755'].includes(entry.mode), `Missing/nonregular pipeline input: ${path}`);
  }
  tree.prefetch?.(selected);
  const files = selected.map(path => {
    const bytes = tree.read(path), entry = tree.entries.get(path), sha256 = hash(bytes);
    if (Object.hasOwn(source.sources, path)) assert.equal(sha256, source.sources[path], `Pipeline source bytes differ: ${path}`);
    if (root) {
      const actual = join(root, path), stat = lstatSync(actual);
      assert(stat.isFile(), `Nonregular working pipeline input: ${path}`);
      assert.equal(stat.mode & 0o111 ? '100755' : '100644', entry.mode, `Working pipeline input mode differs: ${path}`);
      assert.equal(hash(readFileSync(actual)), sha256, `Working pipeline input bytes differ: ${path}`);
    }
    return {path, mode: entry.mode, bytes: bytes.length, sha256};
  });
  const inputs = {files, directories: members, unresolved: [...residual]};
  return {...inputs, key: hash(encode(inputs))};
}

export function readMutationActionReports(directory, decision) {
  return parts.flatMap(part => modes(decision).map(mode => {
    const path = mutationReportPath(part, mode);
    const bytes = readFileSync(join(directory, path.slice('.artifacts/relation-pipeline/'.length)));
    const report = JSON.parse(bytes.toString('utf8'));
    assert(bytes.equals(Buffer.from(`${JSON.stringify(report, null, 2)}\n`)), 'Noncanonical pipeline original');
    return {path, bytesDigest: hash(bytes), report};
  }));
}

function scientificCase(entry) {
  // Only the receipt-owned observation ID is diagnostic. Preserve every other
  // field, including input row IDs, ordered rows/stages, NULL, schema and work.
  assert.equal(entry.observation.id, entry.id, 'Unbound pipeline observation');
  const {id: _id, ...observation} = entry.observation;
  return {testCase: entry.testCase, caseDigest: entry.caseDigest, program: entry.program, observation};
}

export function mutationActionObservation(report, action) {
  const registered = mutationActions(report.decision).find(entry => entry.id === action.id);
  assert.deepEqual(action, registered, 'Unregistered pipeline action scope');
  assert.equal(report.part.id, action.part, 'Foreign action part');
  assert.equal(report.mode, action.mode, 'Foreign action mode');
  inspectMutationPart(report);
  return projectMutationActionObservation(report, action);
}
// A read-only projection of one immutable original, explicitly separate from
// current action admission, runtime replay and authenticated Actions evidence.
export function archivedMutationActionObservations(bytes) {
  assert.equal(hash(bytes), '5ce6b98807105317e43a3496e08045ff403afad2081d9e8dfeca61ea146d9e22',
    'Changed immutable historical mutation bytes');
  const report = JSON.parse(bytes);
  inspectArchivedMutationPart(report);
  const actions = mutationActionScope(report.decision, report.part.planDigest,
    { [report.part.id]: report.part.variants }).filter(action => action.mode === 'fixed');
  return { authority: 'immutable-historical-projection', revision: report.revision,
    planDigest: report.part.planDigest,
    observations: actions.map(action => ({ action, ...projectMutationActionObservation(report, action) })) };
}
function projectMutationActionObservation(report, action) {
  const selected = report.results.map(result => {
    const list = action.phase === 'mutated' ? result.executions : action.phase === 'pristine'
      ? result.healthyExecutions : result.postRestore.executions;
    const executions = list.filter(entry => entry.receipt.target === action.target);
    assert(executions.length > 0, 'Missing action target/phase');
    return {result, executions};
  });
  const scientific = selected.map(({result, executions}) => ({name: result.name, site: result.site,
    originalDigest: result.originalDigest, mutatedDigest: result.mutatedDigest,
    anchor: result.anchor, original: result.original, minimal: result.minimal,
    localMinimal: result.localMinimal, ...(action.mode === 'explore' ? {
      history: result.history, finalCandidates: result.finalCandidates,
      // These are also present in the audited JS receipts. Remove only their IDs.
      finalObservations: result.finalObservations.map(({id: _id, ...rest}) => rest),
    } : {}), executions: executions.map(entry => entry.receipt.cases.map(scientificCase))}));
  const units = selected.reduce((sum, {executions}) => sum + executions.reduce((n, entry) => n + entry.receipt.cases.length, 0), 0);
  return {selected, scientificDigest: digest({profile: action.profile, target: action.target, observations: scientific}), units};
}

export function mutationActionRecords({reports, source, decision, sourceInputs, auditedReceipts}) {
  const actions = mutationActions(decision);
  const expected = parts.flatMap(part => modes(decision).map(mode => mutationReportPath(part, mode)));
  assert.deepEqual(reports.map(entry => entry.path), expected, 'Incomplete/duplicate mutation action reports');
  assert(auditedReceipts instanceof Map, 'Missing independent scientific receipt audit');
  assert.deepEqual(sourceInputs.unresolved, residual, 'Changed pipeline runtime boundary');
  assert.equal(sourceInputs.key, hash(encode({files: sourceInputs.files, directories: sourceInputs.directories,
    unresolved: sourceInputs.unresolved})), 'Changed pipeline source identity');
  const seen = new Set(), originals = new Map();
  for (const entry of reports) {
    const report = entry.report;
    assert.equal(entry.path, mutationReportPath(report.part.id, report.mode), 'Wrong mutation action report slot');
    assert.equal(entry.bytesDigest, hash(`${JSON.stringify(report, null, 2)}\n`), 'Changed original mutation report');
    const refs = inspectMutationPart(report, {source, decision});
    for (const execution of refs) {
      assert(!seen.has(execution.path), 'Receipt shared across action reports'); seen.add(execution.path);
      const audited = auditedReceipts.get(execution.path);
      assert(audited && audited.receiptDigest === execution.digest, 'Mutation receipt was not scientifically audited');
      assert.equal(execution.digest, digest(execution.receipt), 'Changed original mutation receipt');
      assert.equal(execution.receipt.exit, 0, 'Failed execution is not action evidence');
      assert.deepEqual(execution.receipt.command, executionCommand(execution.receipt.target), 'Wrong action execution command');
      assert.equal(execution.receipt.compiler, report.toolchain.moonc, 'Wrong action compiler');
      assert.match(audited.bytesDigest, /^[0-9a-f]{64}$/u, 'Missing original receipt bytes');
    }
    originals.set(`${report.part.id}-${report.mode}`, entry);
  }
  const records = actions.map(action => {
    const original = originals.get(`${action.part}-${action.mode}`), report = original.report;
    const {selected, scientificDigest, units} = mutationActionObservation(report, action);
    const receipts = selected.flatMap(({executions}) => executions.map(execution => ({
      path: execution.path, digest: execution.digest, bytesDigest: auditedReceipts.get(execution.path).bytesDigest,
      buildIdentity: execution.receipt.buildIdentity, owner: execution.receipt.boundary.workspace,
      observations: execution.receipt.cases.map(entry => entry.id),
    })));
    const key = hash(encode({action, sourceKey: sourceInputs.key}));
    const required = {action: action.id, candidate: decision.revision, kind: action.kind, target: action.target,
      scope: hash(encode(action.profile)), premises: hash(encode(action.premises)), inputs: key, minimumUnits: action.minimumUnits};
    const application = {action: action.id, origin: report.revision, kind: action.kind, target: action.target,
      scope: required.scope, premises: required.premises, inputs: key, units,
      authenticated: true, successful: true, reused: false, closed: false, mainOrigin: false};
    return {action, required, application, originalReportDigest: original.bytesDigest,
      scientificDigest, receipts};
  });
  return {version: mutationActionVersion, revision: decision.revision, planDigest,
    authority: 'existing-scientific-audit', actions: records, unresolved: [...residual], reuseAuthorized: false};
}

// Invoked only after the existing complete scientific audit succeeded. Lean's
// authenticated fact here means that audit's receipt binding, not Actions origin
// authentication. A separate future transport/policy must qualify reusable origins.
export function checkMutationActions({root, directory, source, decision, auditedReceipts}, {lean = 'lean'} = {}) {
  const started = performance.now();
  const tree = gitTree(root, decision.revision);
  const sourceInputs = mutationSourceInputs({tree, source, root});
  const records = mutationActionRecords({reports: readMutationActionReports(directory, decision),
    source, decision, sourceInputs, auditedReceipts});
  let leanOutput;
  const certificate = checkPlan(records.actions.map(entry => entry.required), records.actions.map(entry => entry.application),
    {lean, onOutput: output => { leanOutput = output; }});
  return {...records, sourceInputs, certificate, leanOutput, admissionMilliseconds: Math.round(performance.now() - started)};
}
