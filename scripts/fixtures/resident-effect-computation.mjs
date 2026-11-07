// The existing real-process harness supplies TLS, a signed production binary,
// SQLite journals and the same outbound gateway. This case exercises private
// Effect computation only: it does not invent approval or public publication.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, readFile, readdir, stat} from 'node:fs/promises';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {canonicalText} from '../check-canonical-json.mjs';

export const residentEffectSourceContractCid =
  'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3';

// The shared Effect fixture declares ordinary query acquisition. This Native
// realization additionally uses both validation and query receipts. Declare
// that exact installed contract before admission; do not weaken selection.
export async function residentEffectSourceEnvironment(repository) {
  const environment = JSON.parse(await readFile(join(repository,
    'packages/run-host-core/fixtures/source-compute-effect.environment.json'), 'utf8'));
  const receipts = JSON.parse(await readFile(join(repository,
    'spec/contracts/actql-query-two-receipt.json'), 'utf8'));
  const cid = body => 'sha256:' + createHash('sha256').update(canonicalText(body)).digest('hex');
  const members = environment.connector_capabilities.filter(member =>
    member.source_ref === 'connector://crm/main/r#v' &&
    member.source_contract_cid === residentEffectSourceContractCid);
  assert.equal(members.length, 1, 'same original Effect Source capability');
  const member = members[0];
  member.capability_contract_cids = [...new Set([
    ...member.capability_contract_cids, cid(receipts),
  ])].sort();
  delete environment.evidence_bundle_cid;
  return canonicalText({...environment, evidence_bundle_cid: cid(environment)});
}

export function prepareResidentEffectComputation({runHost, programText,
  environmentWire, createdAt, validUntil, physicalCid, coordinatorAuthority}) {
  const environment = runHost.admitEnvironment(environmentWire,
    JSON.parse(environmentWire).evidence_bundle_cid, {rela: true});
  const prepared = runHost.prepareEffect(programText, 'json', environment);
  const compilation = runHost.compileEffect(prepared);
  assert.deepEqual(JSON.parse(runHost.effectSourceInputBinding(compilation)), {
    source_ref: 'connector://crm/main/r#v', source_contract_cid: residentEffectSourceContractCid});
  assert.deepEqual(runHost.effectExecutionShape(prepared, compilation),
    {taskCount: 2, acquisitionCount: 1, effectCount: 1});
  const allowed = runHost.issueAllowedEffectRun(prepared, compilation, {
    executionContextCid: physicalCid('resident-execution-context'),
    hostPolicyCid: physicalCid('resident-host-policy'), expiresAt: validUntil});
  const original = runHost.issueEffectRunDefinition(allowed,
    'resident-scope', 'resident-run-1', createdAt, validUntil);
  const definition = runHost.privateRunDefinition(original);
  const materials = runHost.issueEffectRunMaterials(allowed, original,
    {environment, environmentWire, document: programText, format: 'json'});
  const restored = runHost.admitEffectRunMaterials(materials, definition.cid, {rela: true});
  assert.deepEqual(runHost.privateRunDefinition(restored.definition), definition);
  assert.deepEqual(runHost.privateEffectRunEvidence(restored.allowed),
    runHost.privateEffectRunEvidence(allowed));
  assert.equal(runHost.issueEffectRunMaterials(restored.allowed, restored.definition,
    {environment, environmentWire, document: programText, format: 'json'}), materials);
  const edge = runHost.prepareEffectRetainedTaskInputEdge(restored.allowed, restored.definition);
  const request = runHost.prepareEffectRequest(restored.prepared, restored.compilation,
    coordinatorAuthority, 'resident-effect-request');
  return {definition: {wire: definition.wire, identity: definition.cid}, materials,
    retainedPrepared: restored.prepared, retainedCompilation: restored.compilation,
    retainedAdmission: restored.allowed, retainedDefinition: restored.definition,
    edge, request};
}

export async function runResidentEffectComputation({runHost, siteControl, coordinator,
  root, runtimeRoot, extra, startSite, setCurrentSite, within, waitFor, entries,
  settledQuery, gateway, ensureOutputReceiver, dispatchFor, materialsEnvelope,
  bindingBody, materials, preparedEffect, definition, validUntil, coordinatorAuthority,
  siteKey, runtimeBundleCid, physicalCid, budget, issuerCapability, operationCapability,
  expectedRows, expectedSchemaCid, retainedCoordinatorRecords, reservedPayloadBytes,
  pendingIntents}) {
  const sourceGrantCid = physicalCid('retained-source-grant');
  const destinationGrantCid = physicalCid('retained-destination-grant');
  const routeCapabilityCid = physicalCid('retained-route');
  const retainedRoot = join(root, 'retained-input');
  await mkdir(retainedRoot, {mode: 0o700});
  const site = startSite([...extra, '--retained-input-root', retainedRoot,
    '--retained-source-grant-cid', sourceGrantCid,
    '--retained-destination-grant-cid', destinationGrantCid,
    '--retained-route-capability-cid', routeCapabilityCid,
    '--retained-consumer-engine-bytes', '67108864']);
  setCurrentSite(site);
  const producerDispatch = dispatchFor('resident-effect-producer', 1);
  await ensureOutputReceiver(producerDispatch);
  await within(gateway.dispatch({dispatch: producerDispatch, inputBindingBody: bindingBody,
    dispatchEnvelope: materialsEnvelope(producerDispatch)}), 'Effect producer dispatch');
  await settledQuery(producerDispatch, 'Effect producer');
  assert.equal((await entries()).length, 1);
  const producer = runHost.prepareRetainedInputProducer(preparedEffect.edge, () => ({
    authority: coordinatorAuthority,
    durableRecordWire: retainedCoordinatorRecords.get(siteControl.identity(producerDispatch)).wire}));
  const current = {
    siteBindingCurrent: (key, generation, bundle) => key === siteKey && generation === 1 &&
      bundle === runtimeBundleCid && site.child.exitCode === null && site.child.signalCode === null,
    authority: () => coordinatorAuthority, nowUnixMs: () => BigInt(Date.now()),
    authorized: (dispatchCid, wire) => dispatchCid === siteControl.identity(producerDispatch) &&
      JSON.parse(wire).source_grant_cid === sourceGrantCid &&
      JSON.parse(wire).destination_grant_cid === destinationGrantCid &&
      JSON.parse(wire).route_capability_cid === routeCapabilityCid,
  };
  const limits = {maxChunks: 8, maxManifestBytes: 65536,
    maxReferencedBytes: 1048576n, maxBindingBytes: 1048576};
  const planLimits = {maxChunks: limits.maxChunks, maxManifestBytes: limits.maxManifestBytes,
    maxReferencedBytes: limits.maxReferencedBytes};
  const intent = runHost.prepareRetainedInputIntent(producer, {
    sourceGrantCid, destinationGrantCid, routeCapabilityCid,
    transferAttempt: 'resident-effect-input-1', transferMaxBytes: 1048576n,
    transferExpiresUnixMs: BigInt(Date.parse(validUntil))});
  const plan = await within(gateway.retainedPlan({dispatch: producerDispatch,
    intent, current, limits: planLimits}), 'Effect input plan');
  const transferred = await within(gateway.retainedTransfer({dispatch: producerDispatch, plan}),
    'Effect input physical Transfer');
  const reply = await within(gateway.retainedCurrent({dispatch: producerDispatch, plan,
    queryId: 'effect-receiver-before-consumer', limits: planLimits}), 'current Effect receiver custody');
  const receiver = runHost.retainedInputCurrentReplyFacts(reply);
  const receipt = runHost.retainedInputResultFacts(transferred).receipt;
  assert.deepEqual(receiver.receipt, receipt);
  assert.equal(JSON.parse(receiver.transferRecordWire).request_cid,
    runHost.retainedInputPlanFacts(plan).transfer.cid);
  const input = runHost.prepareRetainedTaskInput(producer, receipt, 'direct-destination',
    {...current, readTransfer: () => receiver.transferRecordWire}, limits);
  const consumerBinding = runHost.retainedTaskInputFacts(input).wire;
  const issued = runHost.issueEffectRetainedTaskDispatch(preparedEffect.retainedAdmission,
    preparedEffect.retainedDefinition, preparedEffect.request, {
      taskAttempt: 1, dispatchId: 'resident-effect-consumer', siteKey, siteGeneration: 1,
      runtimeBundleCid, connectorRegistration: 'local', connectorRevision: 'local/1',
      strategyRevision: 'strategy/1', obligationsCid: physicalCid('resident-obligations'),
      budgetCid: siteControl.budgetIdentity(budget),
      evidenceIssuerCapabilityCid: issuerCapability, grantCid: operationCapability}, input);
  const consumerDispatch = siteControl.admitJson(issued.wire, issued.cid);
  await ensureOutputReceiver(consumerDispatch);
  const consumerEnvelope = coordinator.pollDispatchMaterialsJson(
    coordinator.admitDispatchJson(issued.wire, issued.cid), consumerBinding, 1048576, materials);
  await within(gateway.dispatch({dispatch: consumerDispatch, inputBindingBody: consumerBinding,
    dispatchEnvelope: consumerEnvelope}), 'Effect consumer holder relay');
  const terminal = await settledQuery(consumerDispatch, 'Effect consumer');
  assert.equal((await entries()).length, 2);
  const subject = siteControl.managedOutputSubjectProjection(terminal.subject);
  assert.equal(subject[4], expectedSchemaCid, 'independent checked output schema');
  // Inspect test-owned physical bytes using the exact saved file custody. This
  // proves private computation; it grants no input/approval/publication right.
  const database = new DatabaseSync(join(root, 'journal.sqlite3'), {readOnly: true});
  let custody;
  try {
    database.exec('PRAGMA busy_timeout = 5000');
    const files = database.prepare('SELECT CAST(body AS TEXT) AS body FROM actql_records WHERE namespace=?')
      .all('site_output_file').map(row => JSON.parse(row.body));
    custody = files.find(value => value.request_cid === issued.cid);
    assert.ok(custody, 'original consumer sealed file custody');
    assert.equal(custody.material_generation, subject[1]);
    assert.equal(custody.manifest_cid, subject[7]);
  } finally { database.close(); }
  const path = join(retainedRoot, 'output-' + custody.occurrence);
  const physical = await stat(path, {bigint: true});
  assert.equal(String(physical.dev), custody.device);
  assert.equal(String(physical.ino), custody.inode);
  assert.equal(String(physical.size), custody.size);
  const bytes = await readFile(path);
  assert.equal('sha256:' + createHash('sha256').update(bytes).digest('hex'), custody.content_cid);
  assert.deepEqual(JSON.parse(bytes.toString('utf8')), expectedRows);
  await within(gateway.dispatch({dispatch: consumerDispatch, inputBindingBody: consumerBinding,
    dispatchEnvelope: consumerEnvelope}), 'exact Effect consumer replay');
  assert.equal((await entries()).length, 2, 'replay cannot execute either task again');
  assert.equal(site.lines.filter(line => line.kind === 'source-acquisition-entered').length, 1);
  assert.equal(site.lines.some(line => line.kind === 'output-delivered'), false);
  assert.equal(pendingIntents().length, 0, 'no public Output intent before approval');
  await within(gateway.release({dispatch: consumerDispatch}), 'private consumer release');
  await within(gateway.release({dispatch: producerDispatch}), 'private producer release');
  await waitFor(() => site.lines.some(line => line.kind === 'retained-holder-settled'),
    'private task reservations released');
  const capacity = site.lines.find(line => line.kind === 'retained-holder-settled');
  for (const key of ['active_operations', 'active_transfers', 'holdings',
    'cleanup_responsibilities', 'held_bytes', 'reserved_retention_bytes', 'reserved_execution_bytes']) {
    assert.equal(capacity[key], '0', key);
  }
  assert.deepEqual(await readdir(retainedRoot), []);
  for (const dispatch of [producerDispatch, consumerDispatch]) {
    assert.equal((await within(gateway.query({dispatch}), 'private task cleanup observation')).state[2], 2);
  }
  assert.equal(reservedPayloadBytes(), 0);
  assert.equal(pendingIntents().length, 0);
  assert.equal((await entries()).length, 2);
  assert.equal(new Set((await entries()).map(line => line.split(' ')[1])).size, 2);
  const retainedOwners = site.lines.filter(line => line.kind === 'effect-computation-custody-retained');
  assert.deepEqual(new Set(retainedOwners.map(line => line.request_cid)),
    new Set([siteControl.identity(producerDispatch), issued.cid]));
  site.child.kill('SIGTERM');
  await within(site.exited, 'private Effect control shutdown');
  const bundles = new DatabaseSync(join(runtimeRoot, '.actql-runtime-bundle.sqlite3'), {readOnly: true});
  try {
    const catalog = bundles.prepare('SELECT body FROM actql_records WHERE namespace=? AND record_key=?')
      .get('runtime_bundle', 'catalog');
    assert.deepEqual(JSON.parse(Buffer.from(catalog.body).toString('utf8'))
      .entries.flatMap(entry => entry.holds), []);
  } finally { bundles.close(); }
  console.log(JSON.stringify({kind: 'native-private-effect-computation-verified',
    runDefinitionCid: definition.identity, producerDispatchCid: siteControl.identity(producerDispatch),
    consumerDispatchCid: issued.cid, checkedTasks: 2, sourceAcquisitions: 1,
    producerEntries: 1, consumerEntries: 1, rows: expectedRows, schemaCid: expectedSchemaCid,
    receiverCurrentQueried: true, receiverDatabaseReadForBinding: false,
    privateTaskCleanup: true, siteCapacity: capacity, receiverHoldingReclaimed: true,
    actualComputationOwnersRetained: true,
    pendingIntents: 0, reservedPayloadBytes: 0, effectExecutionNotRequested: true,
    checkpointCaptured: false, approvalCommitted: false, publicResultPublished: false,
    effectRunReleased: false, publicCloudAcceptance: false}));
}
