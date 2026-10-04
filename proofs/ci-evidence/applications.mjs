import assert from 'node:assert/strict';
import {encode} from '../bounded-session/action-inputs.mjs';
import {catalogPath, compareCatalogs, validateCatalog} from './actions.mjs';
import {actionInputs, compareInputs, gitTree, hash, sharedFiles} from './inputs.mjs';
import {readOriginReceipt} from './receipts.mjs';
import {checkPlan} from './check.mjs';
import {runtimeForAction} from './isolated-runtime.mjs';

export const applicationVersion = 'actql-verification-action-application/0.1';
const identity = value => hash(encode(value));
const exact = (value, fields) => assert.deepEqual(Object.keys(value ?? {}).sort(), [...fields].sort(), 'Missing/extra application field');

export function policyUnchanged(originTree, candidateTree) {
  return sharedFiles.every(path => {
    const a = originTree.entries.get(path), b = candidateTree.entries.get(path);
    return a?.kind === 'blob' && b?.kind === 'blob' && a.mode === b.mode &&
      hash(originTree.read(path)) === hash(candidateTree.read(path));
  });
}

// A receipt hash does not prove its source scope. Rebuild the origin manifest
// from actual Git, using its authenticated runtime observation. Candidate
// runtime is collected locally; it must not come from an origin's JSON.
export function applicability({action, receipt, originTree, candidateTree, candidateRevision, runtime, acquisition}) {
  assert(['fresh', 'reused'].includes(acquisition));
  assert.equal(encode(receipt.action), encode(action), 'Wrong action descriptor');
  const reconstructed = actionInputs({tree: originTree, revision: receipt.origin.testedRevision,
    action, runtime: receipt.inputs.inputs.runtime});
  assert.equal(encode(reconstructed), encode(receipt.inputs), 'Receipt does not describe actual origin Git inputs');
  const current = actionInputs({tree: candidateTree, revision: candidateRevision, action, runtime});
  const comparison = compareInputs(reconstructed, current);
  if (acquisition === 'reused') {
    assert(policyUnchanged(originTree, candidateTree), 'Changed reuse policy');
    assert(comparison.eligible, 'Different/open source or runtime input boundary');
  } else {
    assert.equal(receipt.origin.testedRevision, candidateRevision, 'Fresh observation from a different checkout');
    assert(comparison.equal, 'Fresh observation does not describe candidate runtime');
  }
  return current;
}

export function leanRecords(action, manifest, original, context, acquisition) {
  const required = {action: action.id, candidate: context.candidateRevision, kind: action.kind,
    target: action.target, scope: identity(action.profile), premises: identity(action.premises),
    inputs: manifest.key, minimumUnits: action.minimumUnits};
  const receipt = original.receipt;
  const application = {action: receipt.action.id, origin: receipt.origin.testedRevision,
    kind: receipt.action.kind, target: receipt.action.target, scope: identity(receipt.action.profile),
    premises: identity(receipt.action.premises), inputs: receipt.inputs.key, units: receipt.execution.units,
    authenticated: true, successful: true, reused: acquisition === 'reused',
    closed: manifest.unresolved.length === 0 && receipt.inputs.unresolved.length === 0,
    mainOrigin: receipt.origin.event === 'push' && receipt.origin.branch === 'main'};
  return {required, application};
}

// The complete inventory is reconstructed, never taken from the requested
// applications. A missing origin is not converted to a successful application.
export async function checkApplications({root, context, runtime, actionRuntimes = {}, protectedRevision, entries, request,
  treeAt = revision => gitTree(root, revision), read = readOriginReceipt, prove = checkPlan}) {
  const trees = new Map();
  const tree = revision => {
    if (!trees.has(revision)) trees.set(revision, treeAt(revision));
    return trees.get(revision);
  };
  const candidateTree = tree(context.candidateRevision), protectedTree = tree(protectedRevision);
  const catalog = validateCatalog(JSON.parse(candidateTree.read(catalogPath).toString('utf8')));
  const protectedCatalog = validateCatalog(JSON.parse(protectedTree.read(catalogPath).toString('utf8')));
  compareCatalogs(protectedCatalog, catalog);
  for (const original of protectedCatalog.actions) {
    assert.equal(encode(catalog.actions.find(action => action.id === original.id)), encode(original),
      'Changed protected registration requires a reviewed policy update');
  }
  assert(Array.isArray(entries) && entries.length === catalog.actions.length, 'Incomplete required applications');
  const byId = new Map();
  for (const entry of entries) {
    exact(entry, ['actionId', 'acquisition', 'archive', 'artifactId']);
    assert(catalog.actions.some(action => action.id === entry.actionId) && !byId.has(entry.actionId), 'Extra/duplicate action');
    assert(['fresh', 'reused'].includes(entry.acquisition));
    if (entry.acquisition === 'reused') assert(catalog.actions.some(action => action.id === entry.actionId &&
      protectedCatalog.actions.some(original => encode(original) === encode(action))), 'Unreviewed/changed reusable registration');
    byId.set(entry.actionId, entry);
  }
  const requirements = [], checked = [], applications = [];
  for (const action of catalog.actions) {
    const entry = byId.get(action.id);
    const original = await read({...entry, action, expected: context, request});
    const manifest = applicability({action, receipt: original.receipt,
      originTree: tree(original.receipt.origin.testedRevision), candidateTree,
      candidateRevision: context.candidateRevision, runtime: runtimeForAction(action, runtime, actionRuntimes), acquisition: entry.acquisition});
    const records = leanRecords(action, manifest, original, context, entry.acquisition);
    requirements.push(records.required); checked.push(records.application);
    applications.push({version: applicationVersion, candidateRevision: context.candidateRevision, actionId: action.id,
      acquisition: entry.acquisition, originReceiptDigest: original.receiptDigest,
      originRevision: original.receipt.origin.testedRevision, originRunId: original.receipt.origin.runId,
      originRunAttempt: original.receipt.origin.runAttempt, artifactId: original.artifactId,
      archiveDigest: original.archiveDigest, candidateActionKey: manifest.key, originActionKey: original.receipt.inputs.key,
      kind: action.kind, target: action.target, scopeDigest: identity({profile: action.profile, premises: action.premises}),
      checkerResult: 'accepted'});
  }
  const lean = prove(requirements, checked, {receiptDigests: applications.map(entry =>
    ({actionId: entry.actionId, digest: entry.originReceiptDigest}))});
  assert.equal(lean.accepted, true);
  return {version: 'actql-verification-family-result/0.1', context, protectedRevision,
    catalogDigest: identity(catalog), requiredActions: catalog.actions.map(action => action.id),
    applications, lean};
}
