import {encode} from '../bounded-session/action-inputs.mjs';
import {actionInputs, hash, sharedFiles, mutationSnapshotExtras} from './inputs.mjs';
import {readCatalog} from './actions.mjs';
import {sealReceipt, canonicalReceipt, mutationIds} from './receipts.mjs';

const bytes = value => Buffer.from(`${encode(value)}\n`);
export function costFixture(reused = false, fullCatalog = false) {
  // Hand-authored timing/receipt fixture, not an isolated mutation execution.
  const catalog = readCatalog();
  if (!fullCatalog) {
    catalog.actions = catalog.actions.filter(action => ['model', 'mutations-js'].includes(action.id));
    catalog.actions.forEach(action => {action.dependencies = [];});
  }
  const context = {candidateRevision: 'b'.repeat(40), runId: 30, runAttempt: 1};
  const origin = {repository: 'actql/actql', repositoryId: 1, workflowId: 2, workflowPath: '.github/workflows/ci.yml',
    testedRevision: context.candidateRevision, runHeadRevision: context.candidateRevision,
    runId: context.runId, runAttempt: context.runAttempt, jobId: 4, event: 'pull_request', branch: 'feature'};
  const runtime = {profile: 'controlled-test-runtime', unresolved: []}, state = {context, origin, runtime};
  const files = new Map([...sharedFiles, ...mutationSnapshotExtras,
    ...['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs', 'mutations.mjs', 'evidence.mjs'].map(path => `proofs/bounded-session/${path}`),
    ...['bounded_execution', 'connectors/local', 'query_integration'].map(path => `src/${path}/moon.pkg`)].map(path => [path, path]));
  for (const name of ['check.mjs', 'Composition.lean', 'CompositionClaims.lean', 'Events.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs'])
    files.set(`proofs/events-bridge/${name}`, name);
  for (const action of catalog.actions) if (action.package) files.set(`${action.package}/moon.pkg`, '');
  const tree = {entries: new Map([...files.keys()].map(path => [path, {mode: '100644', kind: 'blob'}])),
    read: path => Buffer.from(path.endsWith('moon.pkg') ? '' : files.get(path))};
  const receipts = catalog.actions.map(action => {
    const from = reused && action.id === 'mutations-js' ? {...origin, testedRevision: 'a'.repeat(40),
      runHeadRevision: 'a'.repeat(40), runId: 3, runAttempt: 2, event: 'workflow_dispatch', branch: 'main'} : origin;
    return sealReceipt({origin: {...from}, action: structuredClone(action), inputs: actionInputs({tree, revision: from.testedRevision, action, runtime}),
      output: action.kind === 'formal-model' ? `Checked ${action.minimumUnits} theorems, expected claim types and axiom dependencies\n` :
        action.id === 'mutations-js' ? mutationIds.map(id => `${id}: detected by replacement tests`).join('\n') :
          `Total tests: ${action.minimumUnits}, passed: ${action.minimumUnits}, failed: 0.\n`,
      status: 0, milliseconds: action.kind === 'formal-model' ? 11 : 17});
  });
  const acquisition = {context, milliseconds: 7, actions: receipts.map(receipt => ({actionId: receipt.action.id,
    acquisition: reused && receipt.action.id === 'mutations-js' ? 'reused' : 'fresh', candidateActionKey: receipt.inputs.key,
    origin: {revision: receipt.origin.testedRevision, runId: receipt.origin.runId, runAttempt: receipt.origin.runAttempt,
      actionKey: receipt.inputs.key, receiptDigest: hash(canonicalReceipt(receipt))}}))};
  const comparison = {context, costs: {checkpointMilliseconds: 1, transferMilliseconds: 2, inspectionMilliseconds: 3, totalMilliseconds: 5}};
  const collection = {runtimeObservation: {milliseconds: 2, entries: 3, bytes: 4, inputDigest: hash(encode(runtime))},
    isolatedPreparationMilliseconds: 3, stagedSourceBytes: 100, comparison: comparison.costs, acquisitionMilliseconds: 7};
  const collectionBytes = bytes(collection), certificate = {context, milliseconds: 13, collectionCostsDigest: hash(collectionBytes)};
  const isolatedExecution = reused ? null : {owner: '30:1:4', costs: {preparationMilliseconds: 3,
    buildMilliseconds: 4, executionMilliseconds: 6, inspectionMilliseconds: 2, closeMilliseconds: 2}};
  return {state, catalog, acquisition, comparison, receipts, collectionBytes, certificate, isolatedExecution};
}

