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
import {prepareRecoveredCommandContent} from './recovered-command-content.mjs';
import {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

export function installNodeContentRun({moon, core, registry, values, fragment, ordered,
  namespaceId, authorityScopeCid, storeAuthorityCid, ownerPrincipal, now, authorize,
  faultInjection, assertRunCurrent, preparedRunRequired = false,
  prepareKeyedManagedRun, borrowKeyedManagedLedger, prepareSerializationManagedRun,
  prepareModelManagedRun, retainPreparation}) {
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
  function releasePreparationAliases(managed, inputHolder) {
    const original = this;
    if (original.retired === true) return;
    const prepared = original.prepared;
    if ((preparedRuns.get(prepared) !== original && preparedKeyedRuns.get(prepared) !== original) ||
        original.managed !== managed && managed !== undefined) throw new TypeError('ForeignInstalledContentRun');
    if (managed !== undefined) {
      // The original Host invokes this only inside its checked retirement
      // operation. Do not repeat its fallible current/payload observation.
      if (managed.retiringContent !== true || managed.prepared !== prepared ||
          managed.request !== original.request) throw new TypeError('InstalledContentRunCleanupPending');
    } else if (original.managed?.value !== undefined || inputHolder === undefined ||
        original.inputHolder !== inputHolder ||
        moon.clientProgramPreparationBorrowRead(inputHolder) !== prepared ||
        moon.clientProgramPreparationBorrowRetirementStarted(inputHolder) !== true) {
      throw new TypeError('InstalledContentRunCleanupPending');
    }
    if (original.localPreparation !== undefined) {
      Reflect.apply(original.localPreparation.releaseAliases, original.localPreparation, [managed, inputHolder]);
    }
    if (preparedRunCount <= 0) throw new TypeError('InvalidInstalledContentPreparationCount');
    // The original Host captured this pure cut before retaining the record.
    // Spend it before a consumed parent return can fail; partial construction
    // reaches this point only through the SAME Request abort/holder fence.
    if (typeof original.releaseSelection !== 'function') throw new TypeError('ForeignInstalledContentRun');
    Reflect.apply(original.releaseSelection, undefined, [prepared]);
    for (const key of Object.keys(original)) original[key] = undefined;
    original.retired = true;
    preparedRunCount--;
  }
  function retainOriginalPreparation(prepared, original) {
    Object.defineProperty(original, 'releaseAliases', {value: releasePreparationAliases});
    try { retainPreparation(prepared, original); }
    catch (cause) {
      // The fixed retainer refuses before taking this record. No constructor
      // or physical child has started; its unaccepted slot is not a Run.
      if (original.inputHolder === undefined) {
        for (const key of Object.keys(original)) original[key] = undefined;
        original.retired = true; preparedRunCount--;
      }
      throw cause;
    }
  }
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
    acquiredContent}, intermediate = false) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (plan.kind !== (intermediate ? 'infer' : 'serialization') ||
        plan.serializationGraph === undefined || principalId !== ownerPrincipal ||
        store.storeAuthorityCid !== storeAuthorityCid || typeof retainExecution !== 'function') {
      throw new TypeError('InvalidInstalledContentRun');
    }
    const {task, step} = plan.serializationGraph;
    let selectedOutputLimits = localOutputLimits, selectedIdentitySlots = identitySlots;
    let selectedGenerationLimits;
    if (!intermediate) {
      const compiledLimits = publications.checkedClientSerializationGenerationLimits(
        plan.compiled, plan.serializationGraph);
      selectedGenerationLimits = Object.freeze({...generationLimits,
        maxRows: Math.min(generationLimits.maxRows, compiledLimits.maxRows),
        maxBytes: Math.min(generationLimits.maxBytes, compiledLimits.maxBytes)});
    }
    const definition = JSON.parse(plan.runDefinition.wire);
    const key = {namespaceId, authorityScopeCid, runDefinitionCid: plan.runDefinition.identity};
    let retired = false;
    const live = () => !retired && store.status().closed === false &&
      Date.parse(now()) < Date.parse(definition.valid_until) && authorize(principalId) === true;
    if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
    const source = acquiredContent?.captured.capture.source();
    let ledger, managed, capacity, selectedKeyed;
    if (acquiredContent === undefined || intermediate) {
      const original = preparedRuns.get(preparedProgram);
      if (original === undefined || original.retired || original.plan !== plan || original.attempted ||
          original.failure !== undefined || original.managed === undefined || original.managed.closed) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      // Consume before fallible currentness or prefix construction. Failure
      // remains attached to this Run, never a new scalar-ledger fallback.
      if (acquiredContent !== undefined && (original.model === undefined ||
          original.acquiredLedger !== acquiredContent.ledger ||
          typeof acquiredContent.captured?.capture?.originalRowCapture !== 'function' ||
          typeof control.startRequestAcquiredPrefix !== 'function')) {
        throw new TypeError('InstalledModelCapturedContentPreparationUnavailable');
      }
      if (intermediate) {
        if (original.generationLimits === undefined) throw new TypeError('InstalledContentRunPreparationUnavailable');
        selectedGenerationLimits = original.generationLimits;
        selectedOutputLimits = original.outputLimits;
        selectedIdentitySlots = original.identitySlots;
      }
      original.attempted = true;
      assertRunCurrent();
      managed = original.managed; capacity = original.capacity;
      if (acquiredContent !== undefined) ledger = acquiredContent.ledger;
    } else if (preparedRunRequired) {
      const original = preparedKeyedRuns.get(preparedProgram);
      if (original === undefined || original.retired || original.plan !== plan || original.attempted ||
          original.failed || original.managed === undefined || original.managed.closed ||
          original.managed.selectedKeyed === undefined) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      // The original Request owns this exact prefix/provider and its source
      // bindings. Consume before fallible current/data projection; no old
      // capacity/start reconstruction or scalar Ledger can recover a failure.
      original.attempted = true;
      assertRunCurrent();
      managed = original.managed; selectedKeyed = managed.selectedKeyed;
      capacity = control.requestKeyedPrefixCapacity(selectedKeyed);
      ledger = acquiredContent.ledger;
    } else {
      capacity = control.prefixCapacity(preparedProgram, task, step, bodies, prefixLimits, workspace, source);
      // The source-free case already selected its same Request above. This
      // remaining explicit acquired route borrows its original Source Ledger.
      ledger = acquiredContent.ledger;
    }
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
      // Install the existing flight before entering any callback, including
      // synchronous cancellation. Reentry joins this same cleanup operation.
      flight = Promise.resolve().then(async () => {
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
        for (const holding of retained?.holdings ?? []) {
          await holding.abort();
          // False can mean an already committed holding. Its original owner
          // must still have reconciled and released every prepared child.
          const status = holding.status();
          if (status.operationPending !== false || status.preparedPending !== false ||
              (status.committed !== true && status.abandoned !== true)) return false;
        }
        // A retained intermediate generation keeps its original committed
        // holdings for the Model's fixed-input receipt, including Unknown.
        // Unreturned/failed generation stays on this same cleanup record.
        if (committed === undefined && !generatedRetained) {
          retired = true;
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
        // The actual writer/prepared/holding/Store duties above acknowledged
        // cleanup. Forget only this execution's aliases before fallible native
        // prefix settlement; the same managed Run retains a pending prefix.
        input = undefined;
        writer = undefined;
        physical = undefined;
        byteHolding = undefined;
        retained = undefined;
        publication = undefined;
        retirement.clear();
        if (managed !== undefined) {
          prefix = undefined;
          // This also retrieves cleanup after the original start retained a
          // prefix but threw before returning it to this JS caller.
          const acknowledged = selectedKeyed === undefined
            ? control.cleanupRequestPrefix(managed.value, managed.serialization)
            : control.cleanupRequestKeyedPrefix(managed.value, selectedKeyed);
          if (acknowledged !== true) return false;
          if (ledger !== undefined) acquiredLedgers.delete(ledger);
        } else if (prefix !== undefined) {
          if (!stopGeneratedContentPrefix({control, prefix, chargeWork})) return false;
          prefix = undefined;
        }
        cleaned = true;
        return true;
      }).finally(() => { if (cleanupFlight === flight) cleanupFlight = undefined; });
      cleanupFlight = flight;
      return flight;
    };
    retainExecution(Object.freeze({close: cleanup, cleanup, cleanupPending: () => !cleaned,
      resourceUsage: () => managed === undefined ? moon.clientProgramMultiCapturedLedgerUsage(ledger)
        : checked(moon.clientProgramInstalledManagedRunAccounting(managed.value)),
      cumulativeWork: () => work}));
    try {
      signal?.throwIfAborted();
      const capturedProof = acquiredContent === undefined ? undefined
        : publications.bindCheckedClientSerializationCapture(preparedProgram,
          plan.serializationGraph, acquiredContent.captured, acquiredContent);
      prefix = managed === undefined
        ? control.prefix(preparedProgram, task, step, bodies, prefixLimits, ledger, workspace,
          source, acquiredContent?.keyedLookup)
        : selectedKeyed === undefined
          ? acquiredContent === undefined
            ? control.startRequestPrefix(managed.value, preparedProgram, managed.serialization)
            : control.startRequestAcquiredPrefix(managed.value, preparedProgram, managed.serialization,
              acquiredContent.captured.capture.originalRowCapture())
          : control.startRequestKeyedPrefix(managed.value, preparedProgram, selectedKeyed,
            source, acquiredContent.keyedLookup);
      await faultInjection?.('content_workspace_reserved', {capacity});
      const output = await runGeneratedContentPrefix({control, prefix, remainingWork, chargeWork, signal});
      const barrier = control.prepare(preparedProgram, task, step, 10000);
      const encoder = control.encoder(barrier, selectedGenerationLimits);
      input = control.bindInput(barrier, output, encoder);
      const inputEvidence = await identifyGeneratedContentInput({control, compiled: plan.compiled,
        input, limits: selectedOutputLimits, maxWorkspaceSlots: selectedIdentitySlots,
        identityLimits: localContractLimits, remainingWork, chargeWork, signal, captured: capturedProof});
      await faultInjection?.('content_input_identified', {work, signal});
      signal?.throwIfAborted();
      writer = store.createPreparedObjectWriter(selectedGenerationLimits.maxBytes);
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
  const run = options => execute(options);
  // The ordinary trusted Host prepares this exact checked Run before durable
  // admission. This Ledger expresses managed limits; platform allocation is
  // the supplier, and no successful allocation, authority or physical ACK is
  // inferred from these numbers. Store/native children keep their own duties.
  run.prepareRun = ({preparedProgram, plan, request}) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function' ||
        typeof prepareSerializationManagedRun !== 'function' || typeof retainPreparation !== 'function' || request === undefined) {
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
      if (prior.retired || prior.plan !== plan || prior.request !== request || prior.attempted) throw new TypeError('ForeignInstalledContentRun');
      if (prior.failed) throw prior.failure;
      return;
    }
    if (preparedRunCount === 4096) throw new TypeError('InstalledContentRunLimit');
    preparedRunCount++;
    const original = {prepared: preparedProgram, plan, request, attempted: false, capacity: undefined, managed: undefined,
      inputHolder: undefined, localPreparation: undefined, releaseSelection: undefined, contentControl: control,
      retired: false, failed: false, failure: undefined};
    preparedRuns.set(preparedProgram, original);
    try {
      retainOriginalPreparation(preparedProgram, original);
      // Retain the SAME Host bag before current/requirements projections.
      // The Request constructor owns the provider and original compilation.
      original.managed = prepareSerializationManagedRun(preparedProgram, request, plan, prefixLimits, workspace, original);
      if (original.managed === undefined || original.managed.value === undefined ||
          original.managed.serialization === undefined) throw new TypeError('InstalledContentRunPreparationUnavailable');
      original.capacity = control.requestPrefixCapacity(original.managed.serialization);
      assertRunCurrent();
    } catch (error) {if (!original.retired) {original.failed = true; original.failure = error;} throw error;}
  };
  // Intermediate Model generation uses the same Request/Run as its Model
  // Scope. Retain the original Content record before the Host constructor;
  // no separate Content completion, adoption or scalar Ledger is selected.
  run.prepareModelRun = ({preparedProgram, plan, request, model}) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function' ||
        typeof prepareModelManagedRun !== 'function' || typeof retainPreparation !== 'function' ||
        request === undefined) throw new TypeError('InstalledContentRunPreparationUnavailable');
    assertRunCurrent();
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const acquisitions = moon.clientProgramAcquisitionCount(preparedProgram);
    if (plan.kind !== 'infer' || plan.serializationGraph === undefined ||
        (acquisitions !== 0 && acquisitions !== 1) ||
        model?.compiled !== plan.compiled || model.runDefinition !== plan.runDefinition ||
        model.graph !== plan.inferGraph || model.serializationGraph !== plan.serializationGraph) {
      throw new TypeError('InstalledContentRunPreparationUnsupported');
    }
    const prior = preparedRuns.get(preparedProgram);
    if (prior !== undefined) {
      if (prior.retired || prior.plan !== plan || prior.request !== request || prior.model !== model ||
          prior.attempted) throw new TypeError('ForeignInstalledContentRun');
      if (prior.failed) throw prior.failure;
      return;
    }
    if (preparedRunCount === 4096) throw new TypeError('InstalledContentRunLimit');
    preparedRunCount++;
    const original = {prepared: preparedProgram, plan, request, model, attempted: false,
      capacity: undefined, managed: undefined, inputHolder: undefined, localPreparation: undefined,
      releaseSelection: undefined, contentControl: control, prefixLimits,
      generationLimits: undefined, outputLimits: undefined, identitySlots: undefined,
      workspace: undefined, retired: false, failed: false, failure: undefined};
    preparedRuns.set(preparedProgram, original);
    try {
      retainOriginalPreparation(preparedProgram, original);
      const compiledLimits = publications.checkedClientSerializationGenerationLimits(
        plan.compiled, plan.serializationGraph);
      assertRunCurrent();
      if (preparedRuns.get(preparedProgram) !== original || original.retired ||
          original.plan !== plan || original.request !== request || original.model !== model) {
        throw new TypeError('ForeignInstalledContentRun');
      }
      // Select once from the same nominal compilation before constructing the
      // workspace. Execution uses this retained bound and cannot reissue it.
      original.generationLimits = Object.freeze({...generationLimits,
        maxRows: Math.min(generationLimits.maxRows, compiledLimits.maxRows),
        maxBytes: Math.min(generationLimits.maxBytes, compiledLimits.maxBytes)});
      // Only the SAME checked JSON-leaf input permits a closed row/column
      // node bound. This never constrains the preceding prefix's input rows,
      // and recursive/opaque inputs keep their original separate profile.
      const rows = original.generationLimits.maxRows;
      const fields = compiledLimits.jsonLeafFields;
      const wireNodes = fields === undefined ? undefined : 1 + rows * (1 + fields);
      const valueNodes = fields === undefined ? undefined : 1 + rows * (1 + 2 * fields);
      if (fields !== undefined && (!Number.isSafeInteger(fields) || fields < 0 ||
          !Number.isSafeInteger(wireNodes) || !Number.isSafeInteger(valueNodes))) {
        throw new TypeError('InvalidInstalledContentInputShape');
      }
      original.outputLimits = fields === undefined ? localOutputLimits : Object.freeze({...localOutputLimits,
        maxRows: rows, maxValueNodes: Math.min(localOutputLimits.maxValueNodes, valueNodes),
        maxWireNodes: Math.min(localOutputLimits.maxWireNodes, wireNodes),
        maxLogicalWireNodes: Math.min(localOutputLimits.maxLogicalWireNodes, wireNodes + 3),
        maxColumns: Math.min(localOutputLimits.maxColumns, fields)});
      // Three existing writer quotas, column summaries and the live stepped
      // measure/key continuation are distinct. No row-sized JSON copy exists.
      original.identitySlots = fields === undefined ? identitySlots
        : 2 * original.outputLimits.maxWireNodes + original.outputLimits.maxLogicalWireNodes +
          8 * original.outputLimits.maxColumns + 2 * original.outputLimits.maxValueDepth + 4;
      original.workspace = control.workspaceCapacity({generation: original.generationLimits,
        reference: referenceLimits, contract: localContractLimits,
        output: original.outputLimits, identitySlots: original.identitySlots});
      assertRunCurrent();
      if (preparedRuns.get(preparedProgram) !== original || original.retired ||
          original.plan !== plan || original.request !== request || original.model !== model) {
        throw new TypeError('ForeignInstalledContentRun');
      }
      model.contentPreparation = original;
      original.managed = prepareModelManagedRun(preparedProgram, request, model);
      if (original.managed?.value === undefined || original.managed.serialization === undefined) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      original.capacity = control.requestPrefixCapacity(original.managed.serialization);
      assertRunCurrent();
    } catch (error) {if (!original.retired) {original.failed = true; original.failure = error;} throw error;}
  };
  run.generate = options => execute(options, true);
  // The selected existing Source owner creates the same-Run Content parent
  // before durable admission or I/O. This finite prefix recipe is DATA; the
  // callback must retain its real Resource original and partial cleanup.
  run.prepareManagedKeyedCompilation = ({preparedProgram, serializationGraph, request, keyedAcquisition}) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function' || request === undefined ||
        typeof prepareKeyedManagedRun !== 'function' || typeof borrowKeyedManagedLedger !== 'function' ||
        typeof retainPreparation !== 'function') {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    assertRunCurrent();
    if (serializationGraph === undefined || keyedAcquisition === undefined ||
        moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition, preparedProgram) !== true) {
      throw new TypeError('ForeignInstalledContentRun');
    }
    const prior = preparedKeyedRuns.get(preparedProgram);
    if (prior !== undefined) {
      if (prior.retired || prior.serializationGraph !== serializationGraph || prior.keyedAcquisition !== keyedAcquisition ||
          prior.request !== request) throw new TypeError('ForeignInstalledContentRun');
      if (prior.failed) throw prior.failure;
      if (prior.managed.closed || prior.managed.contentCompilation === undefined) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      return prior.managed.contentCompilation;
    }
    if (preparedRunCount === 4096) throw new TypeError('InstalledContentRunLimit');
    preparedRunCount++;
    const original = {prepared: preparedProgram, serializationGraph, plan: undefined, request, keyedAcquisition, attempted: false,
      recipe: undefined, managed: undefined, inputHolder: undefined, localPreparation: undefined, releaseSelection: undefined,
      contentControl: control, retired: false, failed: false, failure: undefined};
    preparedKeyedRuns.set(preparedProgram, original);
    try {
      retainOriginalPreparation(preparedProgram, original);
      const {task, step} = serializationGraph;
      original.recipe = Object.freeze({...bodies, task, step, keyedAcquisition,
        prefixLimits, workspace});
      original.managed = prepareKeyedManagedRun(preparedProgram, request, serializationGraph, original.recipe, original);
      if (original.managed === undefined || original.managed.value === undefined ||
          original.managed.selectedKeyed === undefined || original.managed.contentCompilation === undefined) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      assertRunCurrent();
      return original.managed.contentCompilation;
    } catch (cause) {if (!original.retired) {original.failed = true; original.failure = cause;} throw cause;}
  };
  // Compilation/adoption belongs to the original Request before Run definition.
  // This later call only binds the SAME issuer's completed plan to that holder.
  run.prepareManagedKeyedRun = ({preparedProgram, plan, request, keyedAcquisition}) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function') {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    assertRunCurrent();
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const original = preparedKeyedRuns.get(preparedProgram);
    if (original === undefined || original.retired) throw new TypeError('InstalledContentRunPreparationUnavailable');
    const scope = original.request === request ? undefined : moon.clientRequestScopeCid(request);
    if (plan.kind !== 'serialization' || plan.serializationGraph !== original.serializationGraph ||
        original.keyedAcquisition !== keyedAcquisition || original.plan !== undefined && original.plan !== plan ||
        original.request !== request && (typeof scope !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(scope) ||
          scope !== moon.clientRequestScopeCid(original.request) ||
          moon.clientRequestIntentCid(request) !== moon.clientRequestIntentCid(original.request))) {
      throw new TypeError('ForeignInstalledContentRun');
    }
    if (original.failed) throw original.failure;
    if (original.managed.closed || original.managed.value === undefined) {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    original.plan = plan;
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
  run.prepareEffectFamily = ({facts, store, principalId, retainCleanup}) => {
    const compiled = publications.adoptCheckedClientEffectSerializationRun(facts.allowed, facts.runDefinition);
    const plan = Object.freeze({kind: 'effect', compiled, runDefinition: facts.runDefinition,
      serializationGraph: publications.compiledSerializationGraph(compiled)});
    const managedOriginal = Object.freeze({
      inputRows: publications.checkedClientSerializationInputRows(compiled, plan.serializationGraph),
      prepare(workspace, physical, retain) {
      return publications.prepareCheckedClientEffectContentOriginal(facts.prepared, compiled,
        facts.compilation, facts.runDefinition, plan.serializationGraph, bodies, workspace, physical, retain);
    }});
    const family = run.effectFamily({prepared: facts.prepared, plan, store, principalId,
      retainCleanup, managedOriginal});
    return Object.freeze({family, plan, preparation: family.preparation});
  };
  run.effectFamily = ({prepared, plan, store, principalId, signal, restored, retainCleanup, managedOriginal}) =>
    installEffectContentFamily({moon, control, publications, bodies,
      prepared, plan, store, principalId, ownerPrincipal, now, authorize, signal, managedOriginal,
      namespaceId, authorityScopeCid, storeAuthorityCid, installedBinding,
      referenceLimits, completionLimits,
      outputLimits: localOutputLimits, faultInjection, restored, retainCleanup});
  run.prepareRecoveredCommandContent = options => prepareRecoveredCommandContent({
    ...options, moon, publications, control, ownerPrincipal, storeAuthorityCid,
    authorityScopeCid, now, authorize, installedBinding, referenceLimits});
  // Resolve this before physical acquisition. The selected Source capacity is
  // opaque and requirement-bound in the common owner, never estimated from rows.
  run.prepareAcquiredLedger = ({preparedProgram, plan, sourceCapacity}) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (preparedRunRequired) {
      const original = preparedRuns.get(preparedProgram), managed = original?.managed;
      if (original === undefined || original.retired || original.failed || original.attempted ||
          original.acquiredLedgerAttempted || original.plan !== plan || original.model === undefined ||
          managed === undefined || managed.closed || managed.value === undefined ||
          sourceCapacity.managedRun !== managed.value ||
          typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      original.acquiredLedgerAttempted = true;
      const parent = managed.value, request = original.request;
      try {
        assertRunCurrent();
        if (preparedRuns.get(preparedProgram) !== original || original.retired || original.failed ||
            original.plan !== plan || original.request !== request ||
            original.managed !== managed || managed.closed || managed.value !== parent) {
          throw new TypeError('ForeignInstalledContentRun');
        }
        const ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(parent,
          preparedProgram, request, [sourceCapacity.capacity], [sourceCapacity.transferBytes],
          [sourceCapacity.executionBytes], registry, values, fragment, ordered));
        // This getter borrows the existing Ledger, so a callback that retired
        // the record creates no new child. Never resurrect its spent aliases.
        if (preparedRuns.get(preparedProgram) !== original || original.retired || original.failed ||
            original.plan !== plan || original.request !== request ||
            original.managed !== managed || managed.closed || managed.value !== parent) {
          throw new TypeError('ForeignInstalledContentRun');
        }
        original.acquiredLedger = ledger;
        assertRunCurrent();
        if (preparedRuns.get(preparedProgram) !== original || original.retired || original.failed ||
            original.plan !== plan || original.request !== request ||
            original.managed !== managed || managed.closed || managed.value !== parent) {
          throw new TypeError('ForeignInstalledContentRun');
        }
        acquiredLedgers.set(ledger, plan.compiled);
        return ledger;
      } catch (cause) {
        if (!original.retired) {original.failed = true; original.failure = cause;}
        throw cause;
      }
    }
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
      if (original === undefined || original.retired || original.plan !== plan || original.failed ||
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
