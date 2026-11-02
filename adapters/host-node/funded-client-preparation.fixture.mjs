import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';

// Existing caller tests use the actual Request/Resource owner and compiler.
// Only the installation identity/current port is supplied by this fixture;
// no shaped preparation, standalone Root or fallback compiler is admitted.
export async function fundedClientPreparation(t, {moon, environment, allowEffects = false}) {
  const publication = {environmentCid: moon.clientProgramCheckingEnvironmentCid(environment), aliases: []};
  const preparedEnvironment = moon.clientProgramPreparePublicSourceEnvironment(environment, JSON.stringify(publication));
  assert.ok(preparedEnvironment);
  const registry = await readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
  const contracts = JSON.parse(await readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  const admission = checked(moon.clientPrepareInstalledSequenceContracts(registry,
    JSON.stringify(contracts.execution_contracts['REL.values']),
    JSON.stringify(contracts.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(contracts.execution_contracts['REL.derive.ordered'])));
  const originals = {installation: {sequenceContractOriginal: {moon, admission}}};
  const context = Object.freeze({runtime: moon, environment, preparedEnvironment, retainedRelationOutput: false});
  const connection = Object.freeze({mode: 'local', owner: 'local',
    consentRefs: Object.freeze([]), runners: Object.freeze([])});
  const receipts = [], retained = new Map();
  let closed = false, prepare;
  const current = actual => {assert.strictEqual(actual, originals); assert.equal(closed, false);};
  const view = await prepareOrdinarySourceManagedInstallation(originals, {
    validator: current, retainedValidator: current,
    preparationContext(actual) {current(actual); return context;},
    retireInitialPreparation(actual, prepared) {
      current(actual);
      assert.equal(retained.has(prepared), true, 'Retire only the same retained caller alias');
      const kind = retained.get(prepared);
      retained.delete(prepared);
      if (kind === 'effect_free') prepare.retireOriginal(prepared);
      // Effect membership is weak; clearing this fixture's actual alias is
      // followed by the manager returning its same typed Effect borrower.
    },
  }, false);
  prepare = installNodeClientProgramPreparation({moon, environment, allowEffects,
    async getFundedPreparation(request, selected, verifier, signal) {
      assert.strictEqual(selected, environment);
      const input = request.kind === 'program' ? request.input : request.input.text;
      const receipt = view.beforeSourceSnapshot(request.kind, input, {parameters: request.parameters}, connection);
      receipts.push(receipt);
      const body = view.captureSourceSnapshot(receipt, request, snapshotClientRequest);
      view.bindSourceSnapshot(receipt, body);
      view.bindSourceRequest(receipt, body, request);
      const original = await view.fundedPreparation(request, selected, verifier, signal);
      assert.equal(retained.has(original.prepared), false);
      retained.set(original.prepared, original.kind);
      return original;
    }});
  t.after(async () => {
    for (const receipt of receipts) view.finishSourceProducer(receipt, 'returned');
    assert.equal(retained.size, 0);
    assert.deepEqual(await view.close(), {pending: false});
    prepare.retireReferences(); closed = true;
  });
  return prepare;
}
