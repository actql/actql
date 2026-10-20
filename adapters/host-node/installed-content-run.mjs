// Installed transport for the original checked Content component. Compute,
// byte laws, identity and publication remain in their existing common owners.
import {checked} from '../host-common/runtime-result.mjs';
import {contentCid} from './local-account-config.mjs';
import {localOutputLimits, localContractLimits,
  serializationTaskPublicationPlan} from './local-values-plan.mjs';
import {runGeneratedContentPrefix, identifyGeneratedContentInput,
  writeGeneratedContent, stopGeneratedContentPrefix} from './generated-content-write.mjs';
import {issueStoredGeneratedContent, retainGeneratedContentEvidence} from './generated-content-holding.mjs';
import {serializationPublicationExecution} from './serialization-result-publication.mjs';
import {publishCompletedEffectFreeRun} from '../host-common/completed-run-publication.mjs';
import {installEffectContentFamily} from './installed-content-family.mjs';
import {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

export function installNodeContentRun({moon, core, registry, values, fragment, ordered,
  namespaceId, authorityScopeCid, storeAuthorityCid, ownerPrincipal, now, authorize,
  faultInjection, assertRunCurrent, preparedRunRequired = false,
  prepareKeyedManagedRun, borrowKeyedManagedLedger}) {
  const control = core.contentGenerationControl;
  const publications = core.publicationControl;
  const bodies = {registry, values, fragment, ordered};
  // Fixed installed finite ceilings; they never come from request JSON.
  const prefixLimits = Object.freeze({maxRows: localOutputLimits.maxRows,
    maxWork: 1000000, maxEntries: 100000, maxValueBytes: 1000000,
    maxValueNodes: 100000, maxValueDepth: 64, maxFrames: 256});
  const generationLimits = Object.freeze({maxRows: localOutputLimits.maxRows,
    maxBytes: localOutputLimits.maxWireBytes, maxValueNodes: 100000,
    maxValueDepth: 64, maxFrames: 256});
  const referenceLimits = Object.freeze({maxBytes: 16384, maxNodes: 256,
    maxDepth: 32, maxTextUnits: 16384});
  const completionLimits = Object.freeze({maxNodes: 1000, maxTextBytes: 100000,
    maxDepth: 64, maxWork: 100000, maxNameBytes: 16384});
  const identitySlots = 4 * localOutputLimits.maxWireNodes + 8 * localOutputLimits.maxColumns;
  const workspace = control.workspaceCapacity({generation: generationLimits,
    reference: referenceLimits, contract: localContractLimits,
    output: localOutputLimits, identitySlots});
  const acquiredLedgers = new WeakMap();
  const preparedRuns = new WeakMap();
  const preparedKeyedRuns = new WeakMap();
  let preparedRunCount = 0;
  const installedBinding = plan => {
    const definition = JSON.parse(plan.runDefinition.wire);
    const graphPolicy = publications.compiledSerializationPolicy(plan.compiled);
    if (graphPolicy === undefined) throw new Error('ContentPolicyMissing');
    return {graphPolicy, binding: {
      content_store_id: namespaceId, content_store_cid: storeAuthorityCid,
      workspace_scope_cid: authorityScopeCid, storage_scope: 'workspace',
      retention_class: 'local-content', expires_at: definition.valid_until,
      availability_evidence_cid: contentCid({version: 'actql-installed-local-policy/0.1',
        name: 'content-availability', storeAuthorityCid, runDefinitionCid: plan.runDefinition.identity,
        expiresAt: definition.valid_until}), effective_data_policy_cid: graphPolicy.cid,
      data_classification: JSON.parse(graphPolicy.wire).classification,
      issuer_contract_cid: contentCid({version: 'actql-installed-local-policy/0.1',
        name: 'content-issuer', storeAuthorityCid, authorityScopeCid}),
      capture_authority_cid: authorityScopeCid,
    }};
  };
  const execute = async ({preparedProgram, plan, store, principalId, signal, retainExecution,
    acquiredContent}, intermediate) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (plan.kind !== (intermediate ? 'infer' : 'serialization') ||
        plan.serializationGraph === undefined || principalId !== ownerPrincipal ||
        store.storeAuthorityCid !== storeAuthorityCid || typeof retainExecution !== 'function') {
      throw new TypeError('InvalidInstalledContentRun');
    }
    const {task, step} = plan.serializationGraph;
    const definition = JSON.parse(plan.runDefinition.wire);
    const key = {namespaceId, authorityScopeCid, runDefinitionCid: plan.runDefinition.identity};
    let retired = false;
    const live = () => !retired && store.status().closed === false &&
      Date.parse(now()) < Date.parse(definition.valid_until) && authorize(principalId) === true;
    if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
    const source = acquiredContent?.captured.capture.source();
    const capacity = control.prefixCapacity(preparedProgram, task, step,
      bodies, prefixLimits, workspace, source);
    let ledger;
    if (acquiredContent === undefined && preparedRunRequired) {
      const original = preparedRuns.get(preparedProgram);
      if (original === undefined || original.plan !== plan || original.attempted ||
          original.failure !== undefined || original.capacity.retainedBytes !== capacity.retainedBytes ||
          original.capacity.executionBytes !== capacity.executionBytes) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      // Consume before fallible currentness or prefix construction. Failure
      // remains attached to this Run, never a new scalar-ledger fallback.
      original.attempted = true;
      assertRunCurrent();
      ledger = original.ledger;
    } else ledger = acquiredContent === undefined
      ? checked(moon.clientProgramAcquisitionLedger(1, 0, 0n,
        capacity.retainedBytes, capacity.executionBytes, 0)) : acquiredContent.ledger;
    if (acquiredContent !== undefined && acquiredLedgers.get(ledger) !== plan.compiled) {
      throw new TypeError('Foreign Content acquisition ledger');
    }
    let prefix, input, writer, physical, byteHolding, retained, publication;
    let failureCleanup, cleanupFlight, cleaned = false, generatedRetained = false;
    let work = 0n;
    const remainingWork = () => Number(BigInt(prefixLimits.maxWork) - work);
    const chargeWork = delta => {
      if (!Number.isInteger(delta) || delta < 0) throw new Error('InvalidGeneratedContentWork');
      work += BigInt(delta);
      return work <= BigInt(prefixLimits.maxWork);
    };
    const retirement = new Map();
    // Retain this composition before allocating any child. Failed children and
    // Store retirement keep their original handles; retry never redispatches.
    const cleanup = () => {
      if (cleaned) return Promise.resolve(true);
      if (cleanupFlight !== undefined) return cleanupFlight;
      let flight;
      flight = (async () => {
        if (prefix !== undefined) control.prefixCancel(prefix);
        if (input !== undefined) control.inputCancel(input);
        if (failureCleanup !== undefined) {
          const status = await failureCleanup.retry();
          if (status.pending) return false;
          failureCleanup = undefined;
        }
        if (writer !== undefined) {
          await writer.cancel();
          if (writer.status().reservationHeld === true) return false;
        }
        if (physical?.prepared.status().pending === true) await physical.prepared.release();
        // Release can decline while the same prepared object remains owned.
        // Do not settle the prefix or forget this handle before its actual ACK.
        if (physical?.prepared.status().pending === true) return false;
        // Confirm the exact original index before selecting lawful retirement.
        // A failed observation retains custody; it is not proof of no commit.
        const committed = await store.confirmCommittedIndex(key);
        // Intermediate bytes have their own committed generation/evidence
        // holdings and declared lifetime. A Model approval wait or unknown
        // outcome has no public index; that is not permission to delete them.
        if (committed === undefined && !generatedRetained) {
          retired = true;
          for (const holding of retained?.holdings ?? []) await holding.abort();
          for (const cid of [byteHolding?.holding_cid,
            ...(retained?.bindings ?? []).map(binding => binding.holdingCid)].filter(Boolean)) {
            let child = retirement.get(cid);
            if (child === undefined) {
              child = (await store.retirePhysicalHolding(cid)).cleanup;
              retirement.set(cid, child);
            }
            if (child.status().pending) await child.retry();
            if (child.status().pending) return false;
          }
        }
        if (prefix !== undefined) {
          if (!stopGeneratedContentPrefix({control, prefix, chargeWork})) return false;
        }
        cleaned = true;
        return true;
      })().finally(() => { if (cleanupFlight === flight) cleanupFlight = undefined; });
      cleanupFlight = flight;
      return flight;
    };
    retainExecution(Object.freeze({close: cleanup, cleanup, cleanupPending: () => !cleaned,
      resourceUsage: () => moon.clientProgramMultiCapturedLedgerUsage(ledger),
      cumulativeWork: () => work}));
    try {
      signal?.throwIfAborted();
      const capturedProof = acquiredContent === undefined ? undefined
        : publications.bindCheckedClientSerializationCapture(preparedProgram,
          plan.serializationGraph, acquiredContent.captured, acquiredContent);
      prefix = control.prefix(preparedProgram, task, step, bodies, prefixLimits, ledger, workspace,
        source, acquiredContent?.keyedLookup);
      await faultInjection?.('content_workspace_reserved', {capacity});
      const output = await runGeneratedContentPrefix({control, prefix, remainingWork, chargeWork, signal});
      const barrier = control.prepare(preparedProgram, task, step, 10000);
      const encoder = control.encoder(barrier, generationLimits);
      input = control.bindInput(barrier, output, encoder);
      const inputEvidence = await identifyGeneratedContentInput({control, compiled: plan.compiled,
        input, limits: localOutputLimits, maxWorkspaceSlots: identitySlots,
        identityLimits: localContractLimits, remainingWork, chargeWork, signal, captured: capturedProof});
      await faultInjection?.('content_input_identified', {work, signal});
      signal?.throwIfAborted();
      writer = store.createPreparedObjectWriter(generationLimits.maxBytes);
      const generated = await writeGeneratedContent({control, input, writer, remainingWork, chargeWork, signal});
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
      // The checked generation graph supplies its admitted policy; do not
      // infer classification from a filename or synthetic data values.
      const {graphPolicy, binding} = installedBinding(plan);
      const candidate = control.candidate(encoder, binding, referenceLimits);
      const description = control.inspect(candidate);
      physical = await writer.seal(generated.contentCid);
      byteHolding = {version: 'actql-local-physical-holding/0.1', namespace: 'content',
        holding_cid: publications.checkedClientSerializationByteHoldingCid(plan.compiled,
          plan.runDefinition, storeAuthorityCid), manifest_cid: description.identity,
        objects: [{cid: physical.cid, byte_count: physical.bytes}]};
      await store.commitPhysicalHolding(byteHolding, [physical.prepared]);
      const content = await issueStoredGeneratedContent({store, control, candidate,
        holdingCid: byteHolding.holding_cid, workspaceScopeCid: authorityScopeCid,
        effectiveDataPolicyCid: graphPolicy.cid, available: live,
        authorize: () => live(), limits: referenceLimits});
      const generation = control.complete(plan.compiled, plan.runDefinition, input,
        inputEvidence, candidate, content, live, completionLimits);
      await retainGeneratedContentEvidence({store, publications, compiled: plan.compiled,
        generation, signal, retainHoldings(_holdings, recovery) { retained = recovery; }});
      if (intermediate) {
        generatedRetained = true;
        const capturedContentRecovery = acquiredContent?.keyedContent?.recoveryInventory();
        if (acquiredContent?.keyedContent !== undefined && capturedContentRecovery === undefined) {
          throw new Error('InstalledCapturedContentInventoryUnavailable');
        }
        return Object.freeze({generation,
          capturedContentRecovery,
          capturedContentBinding: acquiredContent?.keyedContent?.sourceBinding,
          sourceEvidence: acquiredContent === undefined ? [] :
            [acquiredContent.sourceEvidence, acquiredContent.keyedSourceEvidence].filter(Boolean),
          recoveryBindings: retained.bindings,
          // The Model fixed-input receipt authenticates this exact inventory
          // together with its original rows. It is not fresh generation proof.
          recovery: Object.freeze({referenceWire: description.wire,
            binding: Object.freeze({...binding}), byteHoldingCid: byteHolding.holding_cid,
            bindings: Object.freeze(retained.bindings.map(value => Object.freeze({...value})))})});
      }
      publication = serializationTaskPublicationPlan({moon, control: publications,
        preparedProgram, admitted: plan, generation, authorityScopeCid,
        namespaceId, storeAuthorityCid, now,
        sourceEvidence: acquiredContent === undefined ? [] :
          [acquiredContent.sourceEvidence, acquiredContent.keyedSourceEvidence].filter(Boolean)});
      const execution = serializationPublicationExecution({moon, core, compiled: plan.compiled,
        preparedProgram, generation, contractLimits: localContractLimits, remainingWork, chargeWork});
      await publishCompletedEffectFreeRun({...publication, execution, store, control: publications, signal});
    } catch (error) {
      if (error?.cleanupPending === true && error.cleanupHandle !== undefined) {
        failureCleanup = error.cleanupHandle;
      }
      throw error;
    }
  };
  const run = options => execute(options, false);
  // The ordinary trusted Host prepares this exact checked Run before durable
  // admission. This Ledger expresses managed limits; platform allocation is
  // the supplier, and no successful allocation, authority or physical ACK is
  // inferred from these numbers. Store/native children keep their own duties.
  run.prepareRun = ({preparedProgram, plan}) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function') {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    assertRunCurrent();
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (plan.kind !== 'serialization' || plan.serializationGraph === undefined ||
        moon.clientProgramAcquisitionCount(preparedProgram) !== 0) {
      throw new TypeError('InstalledContentRunPreparationUnsupported');
    }
    const prior = preparedRuns.get(preparedProgram);
    if (prior !== undefined) {
      if (prior.plan !== plan || prior.attempted) throw new TypeError('ForeignInstalledContentRun');
      if (prior.failure !== undefined) throw prior.failure;
      return;
    }
    if (preparedRunCount === 4096) throw new TypeError('InstalledContentRunLimit');
    preparedRunCount++;
    const original = {plan, attempted: false, capacity: undefined, ledger: undefined, failure: undefined};
    preparedRuns.set(preparedProgram, original);
    try {
      const {task, step} = plan.serializationGraph;
      original.capacity = control.prefixCapacity(preparedProgram, task, step,
        bodies, prefixLimits, workspace);
      original.ledger = checked(moon.clientProgramAcquisitionLedger(1, 0, 0n,
        original.capacity.retainedBytes, original.capacity.executionBytes, 0));
      assertRunCurrent();
    } catch (error) {original.failure = error; throw error;}
  };
  // The selected existing Source owner creates the same-Run Content parent
  // before durable admission or I/O. This finite prefix recipe is DATA; the
  // callback must retain its real Resource original and partial cleanup.
  run.prepareManagedKeyedRun = ({preparedProgram, plan, request}) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function' ||
        typeof prepareKeyedManagedRun !== 'function' || typeof borrowKeyedManagedLedger !== 'function') {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    assertRunCurrent();
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (plan.kind !== 'serialization' || plan.serializationGraph === undefined) {
      throw new TypeError('InstalledContentRunPreparationUnsupported');
    }
    const prior = preparedKeyedRuns.get(preparedProgram);
    if (prior !== undefined) {
      // requestOf may reproject the same checked immutable request value.
      // This only selects an already retained preparation; it cannot issue
      // another admission. The typed borrower still checks the original Run.
      const scope = prior.request === request ? undefined : moon.clientRequestScopeCid(request);
      if (prior.plan !== plan || prior.request !== request &&
          (typeof scope !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(scope) ||
            scope !== moon.clientRequestScopeCid(prior.request) ||
            moon.clientRequestIntentCid(request) !== moon.clientRequestIntentCid(prior.request))) {
        throw new TypeError('ForeignInstalledContentRun');
      }
      if (prior.failure !== undefined) throw prior.failure;
      return;
    }
    if (preparedRunCount === 4096) throw new TypeError('InstalledContentRunLimit');
    preparedRunCount++;
    const original = {plan, request, recipe: undefined, failure: undefined};
    preparedKeyedRuns.set(preparedProgram, original);
    try {
      const {task, step} = plan.serializationGraph;
      const prefix = control.prefixCapacity(preparedProgram, task, step,
        bodies, prefixLimits, workspace, true);
      original.recipe = Object.freeze({...bodies, task, step,
        prefixRetainedBytes: prefix.retainedBytes, prefixExecutionBytes: prefix.executionBytes});
      if (prepareKeyedManagedRun(preparedProgram, request, original.recipe) !== undefined) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      assertRunCurrent();
    } catch (cause) {original.failure = cause; throw cause;}
  };
  run.captureKeyed = options => installRunKeyedContentCapture({moon, publications,
    control: core.contentCaptureControl, namespaceId, authorityScopeCid, storeAuthorityCid,
    ownerPrincipal, now, authorize, ...options});
  // The caller retains this original frame on its existing Model/input owner
  // before allocation. Authentication supplies metadata only; the original
  // Source gate and physical Store must independently confirm current access
  // and every holding. This never opens a Source request or a payload writer.
  run.recoverKeyed = async ({preparedProgram, plan, store, principalId, signal, ledger,
    modelController, inputToken, keyedSource, retainExecution}) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const original = modelController.capturedContent(inputToken, plan.runDefinition.identity);
    if (original === undefined || typeof keyedSource?.adapter?.verifyKeyedRead !== 'function') {
      throw new TypeError('InstalledCapturedContentRecoveryUnavailable');
    }
    const originalBinding = modelController.capturedContentBinding(inputToken, plan.runDefinition.identity);
    const currentBinding = () => keyedSource.adapter.keyedRecoveryBinding(keyedSource.prepared);
    const recheckBinding = () => {
      if (originalBinding === undefined ||
          canonicalValueJson(originalBinding) !== canonicalValueJson(currentBinding())) {
        throw new TypeError('InstalledCapturedContentBindingMismatch');
      }
    };
    recheckBinding();
    const inputAvailable = () => {
      try { return modelController.capturedContent(inputToken, plan.runDefinition.identity) === original; }
      catch { return false; }
    };
    const verifyRead = async () => {
      signal?.throwIfAborted();
      recheckBinding();
      if (!inputAvailable()) throw new Error('InstalledContentAuthorityUnavailable');
      await keyedSource.adapter.verifyKeyedRead({preparedProgram,
        keyedAcquisition: keyedSource.acquisition, preparedKeyed: keyedSource.prepared,
        sourceAccess: keyedSource.sourceAccess, signal});
      signal?.throwIfAborted();
      recheckBinding();
      if (!inputAvailable()) throw new Error('InstalledContentAuthorityUnavailable');
    };
    // The caller supplies its declared shared Run Ledger. No parallel Ledger
    // or sampled-row capacity is introduced for restoring captured references.
    const capacity = keyedSource.adapter.keyedLedgerCapacity(keyedSource.acquisition);
    let frame;
    frame = run.captureKeyed({preparedProgram, plan, acquisition: keyedSource.acquisition,
      ledger, maxBytes: capacity.maxBytes, maxWork: capacity.maxWork, store, principalId,
      signal, inputAvailable, sourceBinding: originalBinding,
      retainExecution: child => retainExecution(Object.freeze({...child,
        // Allocation/confirmation can fail after the owner is retained. Keep
        // the exact receiver with that same cleanup responsibility for retry.
        get recoveryFrame() { return frame; },
        retryRecovery: () => frame.recoverInventory({keyedAcquisition: keyedSource.acquisition,
          inventory: original, verifyRead}),
      }))});
    await frame.recoverInventory({keyedAcquisition: keyedSource.acquisition,
      inventory: original, verifyRead});
    return frame;
  };
  // The enclosing Model custody retains this same child before allocation.
  // No second Run, encoder, publication or dispatch cleanup owner is created.
  run.generate = options => execute(options, true);
  run.effectFamily = ({prepared, plan, store, principalId, signal, restored}) =>
    installEffectContentFamily({moon, control, publications, bodies,
      prepared, plan, store, principalId, ownerPrincipal, now, authorize, signal,
      namespaceId, authorityScopeCid, storeAuthorityCid, installedBinding,
      referenceLimits, completionLimits,
      outputLimits: localOutputLimits, faultInjection, restored});
  // Resolve this before physical acquisition. The selected Source capacity is
  // opaque and requirement-bound in the common owner, never estimated from rows.
  run.prepareAcquiredLedger = ({preparedProgram, plan, sourceCapacity}) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const {task, step} = plan.serializationGraph;
    const prefix = control.prefixCapacity(preparedProgram, task, step,
      bodies, prefixLimits, workspace, true);
    const ledger = moon.clientProgramPrepareSerializationCapturedLedger(preparedProgram,
      task, sourceCapacity.capacity, sourceCapacity.transferBytes, sourceCapacity.executionBytes,
      prefix.retainedBytes, prefix.executionBytes, registry, values, fragment, ordered);
    if (ledger === undefined) throw new TypeError('Content acquisition capacity unavailable');
    acquiredLedgers.set(ledger, plan.compiled);
    return ledger;
  };
  run.prepareKeyedLedger = ({preparedProgram, plan, direct, acquisition, capacity, capturedContent = false}) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (preparedRunRequired) {
      const original = preparedKeyedRuns.get(preparedProgram);
      if (original === undefined || original.plan !== plan || original.failure !== undefined ||
          !capturedContent || typeof borrowKeyedManagedLedger !== 'function') {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      assertRunCurrent();
      const ledger = borrowKeyedManagedLedger(preparedProgram, original.request, original.recipe,
        direct, acquisition, capacity);
      if (ledger === undefined) throw new TypeError('InstalledContentRunPreparationUnavailable');
      assertRunCurrent();
      acquiredLedgers.set(ledger, plan.compiled);
      return ledger;
    }
    const {task, step} = plan.serializationGraph;
    const prefix = control.prefixCapacity(preparedProgram, task, step,
      bodies, prefixLimits, workspace, true);
    const ledger = moon.clientProgramPrepareKeyedSerializationCapturedLedger(preparedProgram,
      direct.capacity, acquisition, capacity.capacity,
      [direct.transferBytes, capacity.transferBytes], [direct.executionBytes, capacity.executionBytes],
      capacity.maxBytes, capacity.maxWork, registry, values, fragment, ordered,
      task, step, prefix.retainedBytes, prefix.executionBytes, capturedContent);
    if (ledger === undefined) throw new TypeError('Content keyed acquisition capacity unavailable');
    acquiredLedgers.set(ledger, plan.compiled);
    return ledger;
  };
  // Reopen only authenticated original Model-input custody. These handles
  // borrow durable holdings; they cannot regenerate, recapture or retire bytes.
  run.recover = async ({preparedProgram, preparedEffect, plan, store, principalId, signal,
    restoredInput, retainExecution}) => {
    if (preparedEffect !== undefined) {
      preparedProgram = publications.checkedClientCompiledEffectProgram(plan.compiled, preparedEffect);
    }
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if ((plan.kind !== 'infer' && !(plan.kind === 'effect' && preparedEffect !== undefined)) ||
        plan.serializationGraph === undefined ||
        principalId !== ownerPrincipal || store.storeAuthorityCid !== storeAuthorityCid ||
        typeof retainExecution !== 'function' || restoredInput?.savedScope === undefined) {
      throw new TypeError('InvalidInstalledContentRecovery');
    }
    let retired = false;
    const definition = JSON.parse(plan.runDefinition.wire);
    const live = () => !retired && restoredInput.token.available === true &&
      store.status().closed === false && Date.parse(now()) < Date.parse(definition.valid_until) &&
      authorize(principalId) === true;
    retainExecution(Object.freeze({cleanupPending: () => !retired,
      async close() { retired = true; return true; },
      async cleanup() { retired = true; return true; }}));
    const recheck = () => {
      signal?.throwIfAborted();
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
    };
    recheck();
    const original = restoredInput.snapshot.contentGeneration;
    const closed = (value, fields) => value !== null && typeof value === 'object' &&
      !Array.isArray(value) && Object.keys(value).sort().join(',') === fields.slice().sort().join(',');
    const {graphPolicy, binding} = installedBinding(plan);
    const fields = ['referenceWire', 'binding', 'byteHoldingCid', 'bindings'];
    if (preparedEffect !== undefined) fields.push('completion');
    if (!closed(original, fields) ||
        preparedEffect !== undefined && (!closed(original.completion, ['binding', 'descriptorWire', 'rows']) ||
          typeof original.completion.binding !== 'string' ||
          typeof original.completion.descriptorWire !== 'string' ||
          !Array.isArray(original.completion.rows) || original.completion.rows.length !== 1 ||
          original.completion.rows.some(row => typeof row !== 'string')) ||
        typeof original.referenceWire !== 'string' ||
        !closed(original.binding, Object.keys(binding)) ||
        Object.keys(binding).some(name => original.binding[name] !== binding[name]) ||
        original.byteHoldingCid !== publications.checkedClientSerializationByteHoldingCid(
          plan.compiled, plan.runDefinition, storeAuthorityCid) ||
        !Array.isArray(original.bindings) || original.bindings.length !== 3 ||
        original.bindings.some((value, index) =>
          !closed(value, ['name', 'semanticCid', 'wire', 'holdingCid']) ||
          value.name !== ['content_input_artifact', 'content_evidence', 'content_generation'][index])) {
      throw new TypeError('InstalledContentRecoveryBindingMismatch');
    }
    const evidence = [];
    for (const value of original.bindings) {
      recheck();
      if (await store.confirmPrivateEvidence(value) === undefined) {
        throw new Error('InstalledContentRecoveryEvidenceUnavailable');
      }
      recheck();
      evidence.push(publications.admitRunEvidence(value.name, value.wire,
        {maxWireBytes: 16384, maxNodes: 256, maxDepth: 16}));
      if (evidence.at(-1).identity !== value.semanticCid) {
        throw new TypeError('InstalledContentRecoveryEvidenceMismatch');
      }
    }
    const candidate = control.recoveryCandidate(original.referenceWire, binding, referenceLimits);
    let storedOriginal;
    const content = await issueStoredGeneratedContent({store, control, candidate,
      holdingCid: original.byteHoldingCid, workspaceScopeCid: authorityScopeCid,
      effectiveDataPolicyCid: graphPolicy.cid, available: live,
      authorize: () => live(), limits: referenceLimits,
      retainOriginal: value => { storedOriginal = value; }});
    recheck();
    const generation = control.recover(plan.compiled, plan.runDefinition, plan.inferGraph,
      restoredInput.savedScope, original.bindings[2].semanticCid,
      {input: evidence[0], derivation: evidence[1], generation: evidence[2]}, candidate, content);
    const current = publications.checkedClientSerializationRecoveryBindings(
      plan.compiled, generation, storeAuthorityCid);
    if (current.length !== original.bindings.length || current.some((value, index) =>
      ['name', 'semanticCid', 'wire', 'holdingCid'].some(name => value[name] !== original.bindings[index][name]))) {
      throw new TypeError('InstalledContentRecoveryEvidenceMismatch');
    }
    recheck();
    const completion = preparedEffect === undefined ? undefined
      : publications.prepareCheckedClientRetainedContentOutput(plan.compiled, plan.runDefinition,
        generation, storeAuthorityCid, original.completion, live);
    await faultInjection?.('effect_content_generation_recovered', {
      holdingCid: original.byteHoldingCid,
    });
    recheck();
    return Object.freeze({generation, recovery: original, completion, storedOriginal,
      capturedContentRecovery: restoredInput.capturedContent,
      capturedContentBinding: restoredInput.capturedContentBinding});
  };
  return Object.freeze(run);
}
