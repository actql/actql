import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';
import {freezeInput} from '../../packages/sdk/internal/private-source-preparation.mjs';

// Existing caller tests use the actual Request/Resource owner and compiler.
// Only the installation identity/current port is supplied by this fixture;
// no shaped preparation, standalone Root or fallback compiler is admitted.
export async function fundedClientPreparation(t, {moon, environment, allowEffects = false, http = false,
  valuesMaxRows, retainedRelationOutput = false}) {
  const fixture = await openFundedClientPreparation({moon, environment, allowEffects, http,
    valuesMaxRows, retainedRelationOutput});
  t.after(fixture.close);
  return http ? Object.freeze({prepare: fixture.prepare, prepareRequest: fixture.prepareRequest,
    prepareSubmit: fixture.prepareSubmit, submission: fixture.submission}) : fixture.prepare;
}

// Process fixtures have their own finally block, not a Node TestContext.
// Both entrances use this SAME owner and its original teardown below.
export async function openFundedClientPreparation({moon, environment, allowEffects = false, http = false,
  valuesMaxRows, sequenceContracts, retainedRelationOutput = false}) {
  if (typeof retainedRelationOutput !== 'boolean') {
    throw new TypeError('InvalidFixtureRetainedOutputProfile');
  }
  if (valuesMaxRows !== undefined && (!Number.isSafeInteger(valuesMaxRows) ||
      valuesMaxRows < 1 || valuesMaxRows > 2147483647 || allowEffects)) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
  const suppliedContracts = sequenceContracts === undefined ? undefined :
    {values: sequenceContracts.values, fragment: sequenceContracts.fragment, ordered: sequenceContracts.ordered};
  const publication = {environmentCid: moon.clientProgramCheckingEnvironmentCid(environment), aliases: []};
  const preparedEnvironment = moon.clientProgramPreparePublicSourceEnvironment(environment, JSON.stringify(publication));
  assert.ok(preparedEnvironment);
  const registry = await readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
  const contracts = JSON.parse(await readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  const admission = checked(moon.clientPrepareInstalledSequenceContracts(registry,
    suppliedContracts === undefined ? JSON.stringify(contracts.execution_contracts['REL.values']) : suppliedContracts.values,
    suppliedContracts === undefined ? JSON.stringify(contracts.execution_contracts['ACTQL.expression_fragment/0.1']) : suppliedContracts.fragment,
    suppliedContracts === undefined ? JSON.stringify(contracts.execution_contracts['REL.derive.ordered']) : suppliedContracts.ordered));
  const host = {};
  const originals = {host, generation: host,
    installation: {sequenceContractOriginal: {moon, admission}}};
  const httpRegistry = http ? createEmbeddedHostRegistry((left, right) => left === right) : undefined;
  httpRegistry?.registerPreparation(host, originals.installation, host);
  const context = Object.freeze({runtime: moon, environment, preparedEnvironment, retainedRelationOutput,
    ...(valuesMaxRows === undefined ? {} : {valuesMaxRows})});
  const connection = Object.freeze({mode: 'local', owner: 'local',
    consentRefs: Object.freeze([]), runners: Object.freeze([])});
  const receipts = new Set(), requestReceipts = new WeakMap(), retained = new Map();
  let closed = false, prepare;
  const current = actual => {
    assert.strictEqual(actual, originals); assert.equal(closed, false);
    httpRegistry?.assertPreparation(host, originals.installation, host);
  };
  const retireOriginal = prepared => {
    assert.equal(retained.has(prepared), true, 'Retire only the same retained caller alias');
    const kind = retained.get(prepared);
    retained.delete(prepared);
    if (kind === 'effect_free') prepare.retireOriginal(prepared);
  };
  const view = await prepareOrdinarySourceManagedInstallation(originals, {
    validator: current, retainedValidator: current,
    preparationContext(actual) {current(actual); return context;},
    retireInitialPreparation(actual, prepared) {
      current(actual);
      retireOriginal(prepared);
      // Effect membership is weak; clearing this fixture's actual alias is
      // followed by the manager returning its same typed Effect borrower.
    },
  }, false);
  prepare = installNodeClientProgramPreparation({moon, environment, allowEffects, valuesMaxRows,
    async getFundedPreparation(request, selected, verifier, signal) {
      assert.strictEqual(selected, environment);
      // HTTP already retained this SAME original before snapshot/dispatch.
      // Direct component calls remain their separate explicit fixture entry.
      if (!requestReceipts.has(request)) {
        const input = request.kind === 'program' ? request.input : request.input.text;
        const receipt = view.beforeSourceSnapshot(request.kind, input, {parameters: request.parameters}, connection);
        receipts.add(receipt);
        const body = view.captureSourceSnapshot(receipt, request, snapshotClientRequest);
        view.bindSourceSnapshot(receipt, body);
        view.bindSourceRequest(receipt, body, request);
      }
      const original = await view.fundedPreparation(request, selected, verifier, signal);
      assert.equal(retained.has(original.prepared), false);
      retained.set(original.prepared, original.kind);
      return original;
    }});
  const close = async () => {
    if (closed) return;
    for (const receipt of receipts) view.finishSourceProducer(receipt, 'returned');
    assert.equal(retained.size, 0);
    assert.deepEqual(await view.close(), {pending: false});
    prepare.retireReferences();
    httpRegistry?.retirePreparation(host, originals.installation, host);
    closed = true;
  };
  if (!http) return Object.freeze({prepare, close, manager: view, retireOriginal,
    installedContracts: admission});
  const originalRequest = request => httpRegistry.originalSourceRequest(host,
    originals.installation, host, request);
  const prepareRequest = (operation, request) => {
    current(originals);
    let settle;
    const pending = new Promise(resolve => {settle = resolve;});
    httpRegistry.retainRequest(host, originals.installation, host, request, pending);
    let receipt, body = request, finished = false;
    const finish = terminal => {
      if (finished) return;
      try {
        if (receipt !== undefined) {
          view.finishSourceProducer(receipt, terminal);
          receipts.delete(receipt);
        }
        finished = true;
      } finally {settle();}
    };
    try {
      if (['plan', 'submit', 'submit-intent', 'submit-named-intent', 'restart-intent'].includes(operation)) {
        receipt = view.beforeSourceSnapshot(request.kind, request.input, request, request.connection);
        receipts.add(receipt);
        body = view.captureSourceSnapshot(receipt, request, snapshotClientRequest);
        view.assertSourceSnapshotCurrent(receipt);
        freezeInput(body);
        view.bindSourceSnapshot(receipt, body);
        view.bindSourceRequest(receipt, body, request);
        requestReceipts.set(request, receipt);
        if (operation !== 'plan' && operation !== 'submit') view.intentCid(receipt, body);
      }
      return Object.freeze({body,
        beforeReply() {
          current(originals);
          // A completed dispatch may already have severed its input. The
          // original pending ingress still belongs to this SAME registry;
          // do not re-read a spent pre-adoption Core input to send its reply.
          assert.strictEqual(originalRequest(request), request);
        },
        bindRequest(derived) {
          httpRegistry.bindSourceRequest(host, originals.installation, host, request, derived);
        }, finish});
    } catch (cause) {
      try {finish('failed');} catch { /* SAME manager retains failed cleanup for teardown. */ }
      throw cause;
    }
  };
  const assertSubmittedIntent = prepare.assertSubmittedIntent;
  assert.equal(typeof assertSubmittedIntent, 'function');
  const prepareSubmit = Object.freeze(Object.assign(
    (request, selected) => prepare(originalRequest(request), selected), {
      assertSubmittedIntent: (prepared, intent) =>
        Reflect.apply(assertSubmittedIntent, prepare, [prepared, intent]),
    }));
  return Object.freeze({prepare, prepareRequest, close, manager: view, retireOriginal, originalRequest,
    installedContracts: admission,
    prepareSubmit,
    submission: Object.freeze({
      bindOwnedRequest(parent, derived) {
        httpRegistry.bindSourceRequest(host, originals.installation, host, parent, derived);
      },
      submittedIntentOriginal(request) {return view.submittedIntentOriginal(originalRequest(request));},
    })});
}
