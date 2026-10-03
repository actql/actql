import {createHash} from 'node:crypto';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {releasePreparedResults, retainCompletedEffectDependencyPayloads} from
  '../host-common/completed-run-publication.mjs';

const preparedEffectSourceOwners = new WeakMap();
const preparedEffectSourceSets = new WeakMap();
const adoptedEffectSourceDependencies = new WeakSet();

// Assemble existing owned Results, never caller-authored roots. Additional
// acquisition/checked-environment bodies must close those exact references;
// MoonBit rejects missing, foreign, conflicting or unused dependencies.
export function preparePinnedEffectDependencyInventory({
  sources, store, control, contractLimits, dependencies = [],
}) {
  const owner = preparedEffectSourceSets.get(sources);
  if (owner?.store !== store || owner?.control !== control ||
      !Array.isArray(sources?.dependencies) ||
      !Array.isArray(dependencies) || dependencies.length > 4096) {
    throw new TypeError('InvalidEffectDependencySetOwner');
  }
  const bodies = [];
  const append = body => {
    if (bodies.length >= 4096) throw new RangeError('EffectDependencyEntryLimit');
    bodies.push(body);
  };
  // A Manifest is a dependency only when an actual consumer import names
  // it. The final Effect source Artifact is itself a root, not an import
  // of its own Manifest. MoonBit revalidates every observation/Manifest edge.
  const importedManifests = new Set();
  for (const {payload} of sources.dependencies) {
    for (const body of payload.dependencyBodies) {
      if (body.kind === 'result_import_observation') {
        importedManifests.add(JSON.parse(body.wire).producer_local_manifest_cid);
      }
    }
  }
  for (const {payload} of sources.dependencies) {
    for (const body of payload.dependencyBodies) append(body);
    for (const [kind, wire] of [
      ['result_artifact', payload.localResultArtifact.wire],
      ['derivation_evidence', payload.localResultArtifact.derivationWire],
      ['ordering_evidence', payload.localResultArtifact.orderingWire],
      ['local_result_definition', payload.localResultDefinition.wire],
      ['local_computation', payload.localInvocation.wire],
    ]) append({kind, wire});
    if (importedManifests.has(payload.localManifest.identity)) {
      append({kind: 'local_manifest', wire: payload.localManifest.wire});
    }
  }
  for (const body of dependencies) append(body);
  return control.prepareLocalEffectDependencyInventory(
    sources.members.map(({payload}) => payload.localResultArtifact),
    bodies, contractLimits);
}

// Only this export set can transfer its payload owners. Public Result names
// are not invented for upstream-only local Results. Durable capture is a
// later obligation of the same completed owner.
export function retainPinnedEffectDependencyPayloads({
  sources, execution, store, storedResults, control, runDefinition,
}) {
  const owner = preparedEffectSourceSets.get(sources);
  if (owner === undefined || owner.store !== store || owner.control !== control ||
      !Array.isArray(sources.dependencies)) {
    throw new TypeError('InvalidEffectDependencySetOwner');
  }
  const bindings = retainCompletedEffectDependencyPayloads({execution, store,
    storedResults, control, runDefinition,
    dependencyInventoryWire: preparePinnedEffectDependencyInventory({
      sources, store, control, contractLimits: owner.contractLimits,
    }),
    dependencies: sources.dependencies.map(({payload}) => ({
      artifact: payload.localResultArtifact,
      physical: payload.physical, prepared: payload.prepared,
    })),
  });
  adoptedEffectSourceDependencies.add(sources);
  return bindings;
}

// Prepare every pinned member under one retention and source-binding policy.
// MoonBit alone decides whether two members own the same live Result view.
// The caller retains the pins and receives every distinct physical owner;
// durable holdings remain independent even when members share these bytes.
export async function preparePinnedEffectSourceSet({
  maxMembers, maxGroupingWork, ...options
}) {
  const {moon, inputs, control, signal} = options;
  if (!Number.isSafeInteger(maxMembers) || maxMembers < 1 ||
      !Number.isSafeInteger(maxGroupingWork) || maxGroupingWork < 0 ||
      typeof moon?.clientProgramEffectInputCount !== 'function' ||
      typeof moon?.clientProgramEffectInputsShareView !== 'function' ||
      typeof moon?.clientProgramEffectInputStage !== 'function' ||
      typeof control?.publicationPreparedReleaseAction !== 'function' ||
      typeof control?.publicationCleanupOwnerAction !== 'function' ||
      options.memberIndex !== undefined ||
      options.proposalMemberIndexes !== undefined) {
    throw new TypeError('InvalidEffectSourceSet');
  }
  const count = moon.clientProgramEffectInputCount(inputs);
  if (!Number.isSafeInteger(count) || count < 1 || count > maxMembers) {
    throw new RangeError('EffectSourceMemberLimit');
  }
  if (options.localEvidenceContext?.acquiredEvidence !== undefined) {
    return prepareDependentEffectSourceSet(options, count, maxGroupingWork);
  }
  const groups = [];
  let remaining = maxGroupingWork;
  const shares = (left, right) => {
    if (remaining === 0) throw new RangeError('EffectSourceGroupingLimit');
    remaining--;
    return moon.clientProgramEffectInputsShareView(inputs, left, right) ===
      true;
  };
  // Finish bounded grouping before creating any Store reservation.
  for (let index = 0; index < count; index++) {
    signal?.throwIfAborted();
    if (!shares(index, index)) throw new TypeError('UnavailableEffectSource');
    const group = groups.find(value => shares(value[0], index));
    if (group === undefined) groups.push([index]);
    else group.push(index);
  }
  const owned = {...options,
    contractLimits: Object.freeze({...options.contractLimits}),
    localEvidenceContext: Object.freeze({...options.localEvidenceContext}),
    proposalLimits: options.proposalLimits === undefined ? undefined :
      Object.freeze({...options.proposalLimits}),
  };
  const payloads = [];
  const members = new Array(count);
  const manifestSet = new Map();
  try {
    for (const indexes of groups) {
      const payload = await preparePinnedEffectSourcePayloadOwned({
        ...owned, memberIndex: indexes[0],
        ...(owned.onProposalRow === undefined ? {} : {
          proposalMemberIndexes: indexes,
        }),
      }, manifestSet);
      payloads.push(payload);
      for (const memberIndex of indexes) {
        members[memberIndex] = Object.freeze({memberIndex, payload});
      }
    }
    for (const unit of manifestSet.values()) {
      unit.manifest = control.issueLocalEffectResultManifest(
        owned.checkedOwner, unit.invocation, unit.artifacts,
        owned.contractLimits);
    }
    // Expose payloads only after every Unit's complete Manifest is admitted.
    const finalized = new Map();
    for (const payload of payloads) {
      const owner = preparedEffectSourceOwners.get(payload);
      const unit = manifestSet.get(owner.unitIndex);
      const value = Object.freeze({...payload, localManifest: unit.manifest});
      preparedEffectSourceOwners.set(value, owner);
      finalized.set(payload, value);
    }
    signal?.throwIfAborted();
    const result = Object.freeze({payloads: Object.freeze(payloads.map(value =>
      finalized.get(value))), members: Object.freeze(members.map(member =>
      Object.freeze({...member, payload: finalized.get(member.payload)})))});
    preparedEffectSourceSets.set(result, Object.freeze({store: owned.store,
      control: owned.control, contractLimits: owned.contractLimits,
      runDefinition: Object.freeze({...owned.localEvidenceContext.runDefinition})}));
    return result;
  } catch (error) {
    // This is the existing MoonBit-controlled publication cleanup path, not
    // a second Effect cleanup state machine. Pending owners escape on error.
    await releasePreparedResults(payloads, error, control);
    throw error;
  }
}

// Produce complete required local Manifests in checked producer order. The
// retained read owner, rather than these JS coordinates, proves every edge.
// All prepared payloads stay under the existing publication cleanup owner.
async function prepareDependentEffectSourceSet(options, memberCount, maxWork) {
  const {moon, inputs, control, checkedOwner, signal, contractLimits} = options;
  if (!Array.isArray(options.localEvidenceContext.retentionDependencies)) {
    throw new TypeError('MissingEffectRetentionDependencyBodies');
  }
  const count = moon.clientProgramEffectLocalResultCount(inputs);
  if (!Number.isSafeInteger(count) || count < 1 || count > 4096) {
    throw new RangeError('EffectDependencyResultLimit');
  }
  let remaining = maxWork;
  const spend = () => {
    if (remaining === 0) throw new RangeError('EffectSourceGroupingLimit');
    remaining--;
  };
  const units = new Map();
  const selected = [];
  const memberIndexes = new Set();
  for (let resultIndex = 0; resultIndex < count; resultIndex++) {
    signal?.throwIfAborted();
    spend();
    const result = moon.clientProgramEffectLocalResultAt(inputs, resultIndex);
    if (result === undefined) throw new TypeError('UnavailableEffectDependency');
    const unitIndex = moon.clientProgramEffectLocalResultStage(result);
    if (!Number.isSafeInteger(unitIndex) || unitIndex < 0 ||
        (selected.length > 0 && unitIndex < selected.at(-1).unitIndex)) {
      throw new TypeError('InvalidEffectDependencyOrder');
    }
    const members = [];
    for (let member = 0; member < memberCount; member++) {
      spend();
      if (!moon.clientProgramEffectLocalResultMatchesMember(
        inputs, resultIndex, member)) continue;
      if (memberIndexes.has(member)) {
        throw new TypeError('DuplicateEffectDependencyMember');
      }
      memberIndexes.add(member);
      members.push(member);
    }
    const entry = {result, resultIndex, unitIndex, members};
    selected.push(entry);
    if (!units.has(unitIndex)) units.set(unitIndex, []);
    units.get(unitIndex).push(entry);
  }
  if (memberIndexes.size !== memberCount) {
    throw new TypeError('IncompleteEffectDependencyMembers');
  }
  const owned = {...options,
    contractLimits: Object.freeze({...contractLimits}),
    localEvidenceContext: Object.freeze({...options.localEvidenceContext}),
    proposalLimits: options.proposalLimits === undefined ? undefined :
      Object.freeze({...options.proposalLimits}),
  };
  const payloads = [];
  const manifests = new Map();
  // Bound retained preimage text across the complete export set, not per
  // Result. The final inventory admission also counts metadata and envelope.
  const dependencyText = {remaining: 16 * 1024 * 1024};
  let staticEntriesRemaining = 4096;
  try {
    for (const [unitIndex, entries] of units) {
      signal?.throwIfAborted();
      const staticBodies = Object.freeze(checked(
        moon.clientProgramEffectLocalStaticBodies(checkedOwner, unitIndex,
          staticEntriesRemaining,
          Math.min(contractLimits.maxWireBytes, dependencyText.remaining),
          contractLimits.maxNodes, contractLimits.maxDepth),
      ).map(pair => {
        staticEntriesRemaining--;
        const wire = moon.clientProgramEffectLocalDependencyBodyJson(pair._1);
        const bytes = Buffer.byteLength(wire, 'utf8');
        if (bytes > dependencyText.remaining) {
          throw new RangeError('EffectDependencyBodyByteLimit');
        }
        dependencyText.remaining -= bytes;
        return Object.freeze({kind: pair._0,
          cid: moon.clientProgramEffectLocalDependencyBodyCid(pair._1), wire});
      }));
      const imports = moon.clientProgramEffectResultImportCount(
        checkedOwner, unitIndex);
      if (!Number.isSafeInteger(imports) || imports < 0 || imports > remaining) {
        throw new RangeError('EffectDependencyImportLimit');
      }
      let dependency;
      if (imports === 0) {
        dependency = owned.localEvidenceContext.acquiredEvidenceByUnit?.[unitIndex]
          ?? (unitIndex === 0 ? owned.localEvidenceContext.acquiredEvidence : undefined);
        if (dependency === undefined) throw new TypeError('MissingEffectSourceEvidence');
      } else {
        const observations = [];
        for (let index = 0; index < imports; index++) {
          spend();
          const captured = checked(moon.clientProgramEffectCaptureResultImport(
            inputs, unitIndex, index, remaining));
          let producer;
          for (const entry of selected) {
            if (entry.unitIndex >= unitIndex) break;
            spend();
            if (moon.clientProgramEffectResultImportMatches(
              captured, inputs, unitIndex, entry.result)) {
              producer = entry;
              break;
            }
          }
          if (producer?.payload === undefined) {
            throw new TypeError('MissingEffectImportProducer');
          }
          observations.push(control.issueEffectResultImportObservation(
            checkedOwner, inputs, captured, manifests.get(producer.unitIndex),
            producer.payload.localResultArtifact, owned.contractLimits));
        }
        dependency = control.issueImportedEffectEvidence(checkedOwner,
          inputs, unitIndex, observations, owned.contractLimits);
      }
      const unit = {invocation: dependency.invocation, artifacts: []};
      const manifestSet = new Map([[unitIndex, unit]]);
      for (const entry of entries) {
        const proposes = owned.onProposalRow !== undefined &&
          entry.members.length > 0;
        entry.payload = await preparePinnedEffectSourcePayloadOwned({
          ...owned, memberIndex: entry.members[0],
          onProposalRow: proposes ? owned.onProposalRow : undefined,
          ...(proposes ? {proposalMemberIndexes: entry.members} : {}),
        }, manifestSet, {resultIndex: entry.resultIndex, dependency,
          dependencyText, staticBodies});
        payloads.push(entry.payload);
      }
      const manifest = control.issueLocalEffectResultManifest(checkedOwner,
        unit.invocation, unit.artifacts, owned.contractLimits);
      manifests.set(unitIndex, manifest);
      for (const entry of entries) {
        const previous = entry.payload;
        entry.payload = Object.freeze({...previous, localManifest: manifest});
        preparedEffectSourceOwners.set(entry.payload,
          preparedEffectSourceOwners.get(previous));
      }
    }
    signal?.throwIfAborted();
    const members = new Array(memberCount);
    for (const entry of selected) {
      for (const memberIndex of entry.members) {
        members[memberIndex] = Object.freeze({memberIndex, payload: entry.payload});
      }
    }
    // Complete Manifests are needed while issuing consumer import evidence.
    // Their complete payload sets are durable dependencies only when an
    // actual import names that Manifest. In the final Unit, keep Effect
    // roots, not unrelated public Results. MoonBit still admits the exact
    // closure and rejects missing, foreign and unused bodies.
    const importedManifests = new Set();
    for (const entry of selected) {
      for (const body of entry.payload.dependencyBodies) {
        if (body.kind === 'result_import_observation') {
          importedManifests.add(JSON.parse(body.wire).producer_local_manifest_cid);
        }
      }
    }
    const retained = [];
    const temporary = [];
    for (const entry of selected) {
      const needed = entry.members.length > 0 ||
        importedManifests.has(entry.payload.localManifest.identity);
      (needed ? retained : temporary).push(entry);
    }
    if (temporary.length > 0) {
      const released = new Error('TemporaryEffectManifestPayloadsReleased');
      try {
        await releasePreparedResults(temporary.map(entry => entry.payload),
          released, control);
      } catch (error) {
        if (error !== released) throw error;
      }
    }
    const result = Object.freeze({
      payloads: Object.freeze(retained.map(entry => entry.payload)),
      members: Object.freeze(members),
      dependencies: Object.freeze(retained.map(entry => Object.freeze({
        resultIndex: entry.resultIndex, unitIndex: entry.unitIndex,
        payload: entry.payload,
      }))),
    });
    preparedEffectSourceSets.set(result, Object.freeze({store: owned.store,
      control: owned.control, contractLimits: owned.contractLimits,
      runDefinition: Object.freeze({...owned.localEvidenceContext.runDefinition})}));
    return result;
  } catch (error) {
    await releasePreparedResults(payloads, error, control);
    throw error;
  }
}

/**
 * Stream one pinned Effect source through the shared checked Result view.
 * The installed Site owns physical reading; MoonBit owns generation matching,
 * row admission, projection, ordering, and logical identity. This is not an
 * Effect Preview or a mutation permit. The caller retains the input pin.
 */
export async function exportPinnedEffectInput(options) {
  return exportPinnedResult({...options, localResultIndex: undefined});
}

// Upstream dependency Results use the same bounded exporter and physical
// import bridge. They are not fictitious Effect members or public Results.
export async function exportPinnedEffectLocalResult({resultIndex, ...options}) {
  if (!Number.isSafeInteger(resultIndex) || resultIndex < 0) {
    throw new TypeError('InvalidEffectLocalResult');
  }
  return exportPinnedResult({...options, memberIndex: undefined,
    localResultIndex: resultIndex});
}

async function exportPinnedResult({
  moon, execution, inputs, memberIndex, limits, onChunk,
  onReceipt, onCanonicalRow, canonicalRowLimits,
  signal, advanceQuantum = 256, localResultIndex,
}) {
  if (typeof onChunk !== 'function' ||
      (onReceipt !== undefined && typeof onReceipt !== 'function') ||
      (onCanonicalRow !== undefined &&
        (typeof onCanonicalRow !== 'function' ||
          !Number.isSafeInteger(canonicalRowLimits?.maxNodes) ||
          canonicalRowLimits.maxNodes < 1 ||
          !Number.isSafeInteger(canonicalRowLimits?.maxDepth) ||
          canonicalRowLimits.maxDepth < 1 ||
          !Number.isSafeInteger(canonicalRowLimits?.maxUtf16Units) ||
          canonicalRowLimits.maxUtf16Units < 0)) ||
      !Number.isSafeInteger(advanceQuantum) || advanceQuantum <= 0) {
    throw new TypeError('InvalidEffectInputExport');
  }
  const rowLimits = onCanonicalRow === undefined ? undefined :
    Object.freeze({maxNodes: canonicalRowLimits.maxNodes,
      maxDepth: canonicalRowLimits.maxDepth,
      maxUtf16Units: canonicalRowLimits.maxUtf16Units});
  signal?.throwIfAborted();
  const local = localResultIndex !== undefined;
  const input = local
    ? moon.clientProgramEffectLocalResultAt(inputs, localResultIndex)
    : moon.clientProgramEffectInputAt(inputs, memberIndex);
  if (input === undefined) {
    throw new TypeError('MissingEffectInput');
  }
  const task = local ? moon.clientProgramEffectLocalResultTask(input)
    : moon.clientProgramEffectInputTask(input);
  const physical = execution.effectPhysicalSource(task);
  if (physical === undefined && !local) {
    throw new TypeError('MissingEffectPhysicalSource');
  }
  let importing, preparation, stream, receipt, exportOwner;
  try {
    if (physical === undefined) {
      exportOwner = checked(moon.clientProgramEffectLocalResultExportStart(
        inputs, localResultIndex, limits));
      preparation = moon.clientProgramEffectLocalResultExportPreparation(
        exportOwner);
    } else {
      importing = checked(local
        ? moon.clientProgramEffectLocalManagedInputBegin(inputs,
          localResultIndex, physical.completed, physical.material, limits)
        : moon.clientProgramEffectManagedInputBegin(input,
          physical.completed, physical.material, limits));
      preparation = await physical.withRows(
        row => checked(moon.clientProgramEffectManagedInputAppend(
          importing, row)), signal,
        () => checked(moon.clientProgramEffectManagedInputFinish(importing)),
      );
      if (local) {
        exportOwner = checked(moon.clientProgramEffectLocalManagedExportOwner(
          inputs, localResultIndex, importing));
      }
    }
    for (;;) {
      signal?.throwIfAborted();
      const progress = checked(moon.clientProgramEffectInputExportAdvance(
        preparation, advanceQuantum));
      if (progress._0) break;
      if (progress._1 <= 0) {
        throw new Error('EffectInputExportDidNotAdvance');
      }
      await yieldEventLoop(undefined, {signal});
    }
    stream = checked(moon.clientProgramEffectInputExportReady(preparation));
    for (;;) {
      signal?.throwIfAborted();
      if (onCanonicalRow === undefined) {
        const chunk = checked(moon.clientProgramEffectInputExportNext(stream));
        if (chunk === undefined) break;
        await onChunk(chunk);
      } else {
        const row = checked(moon.clientProgramEffectInputExportNextCanonicalRow(
          stream, rowLimits.maxNodes, rowLimits.maxDepth,
          rowLimits.maxUtf16Units));
        if (row === undefined) break;
        await onCanonicalRow(row._0, row._2);
        await onChunk(row._1);
      }
    }
    signal?.throwIfAborted();
    const finished = checked(moon.clientProgramEffectInputExportFinish(stream));
    receipt = finished._0;
    await onChunk(finished._1);
    if (local && moon.clientProgramEffectLocalResultExportMatchesReceipt(
      inputs, exportOwner, receipt) !== true) {
      throw new TypeError('ForeignEffectLocalResultReceipt');
    }
    const artifact = onReceipt === undefined
      ? undefined : await onReceipt(input, receipt,
        local ? exportOwner : importing);
    return Object.freeze({
      fields: moon.clientProgramEffectInputExportFields(receipt),
      logicalCid: moon.clientProgramEffectInputExportLogicalCid(receipt),
      schemaCid: moon.clientProgramEffectInputExportSchemaCid(receipt),
      rowCount: moon.clientProgramEffectInputExportRowCount(receipt),
      ...(artifact === undefined ? {} : {artifact}),
    });
  } finally {
    if (receipt !== undefined) {
      moon.clientProgramEffectInputExportReleaseReceipt(receipt);
    }
    if (stream !== undefined) {
      moon.clientProgramEffectInputExportCancel(stream);
    } else if (preparation !== undefined) {
      moon.clientProgramEffectInputExportCancelPreparation(preparation);
    }
    if (importing !== undefined) {
      moon.clientProgramEffectManagedInputCancel(importing);
    }
  }
}

/**
 * Prepare bounded bytes from the exact checked input. The returned Store
 * owner must be committed to an independent holding or explicitly released.
 * Neither sealing bytes nor this summary claims a completed Captured Run.
 */
export async function preparePinnedEffectSourcePayload(options) {
  return preparePinnedEffectSourcePayloadOwned(options);
}

async function preparePinnedEffectSourcePayloadOwned({
  moon, checkedOwner, execution, inputs, memberIndex, limits, store, maxBytes,
  control, invocation, retention, sourceBindingCid, contractLimits, signal,
  localEvidenceContext,
  onProposalRow, proposalMemberIndexes, proposalLimits,
}, manifestSet, local) {
  if (typeof store?.createPreparedObjectWriter !== 'function' ||
      typeof store.storeAuthorityCid !== 'string' ||
      typeof moon?.clientProgramIssueCapturedEffectInputLocalResultDefinition !==
        'function' ||
      typeof moon?.clientProgramIssueCapturedEffectInputLocalInvocation !==
        'function' ||
      checkedOwner === undefined ||
      !['maxWireBytes', 'maxNodes', 'maxDepth'].every(key =>
        Number.isSafeInteger(contractLimits?.[key]) &&
        contractLimits[key] > 0) ||
      typeof control?.issueEffectSourceArtifactFromExport !== 'function' ||
      typeof control?.issueSourceFreeLocalEffectResultArtifact !== 'function' ||
      typeof control?.issueLocalEffectResultManifest !== 'function' ||
      typeof sourceBindingCid !== 'string' ||
      !['admission', 'runDefinition', 'runInvocation', 'observation'].every(
        key => localEvidenceContext?.[key] !== undefined) ||
      (proposalMemberIndexes !== undefined &&
        (onProposalRow === undefined ||
          !Array.isArray(proposalMemberIndexes) ||
          proposalMemberIndexes.length === 0 ||
          new Set(proposalMemberIndexes).size !==
            proposalMemberIndexes.length ||
          proposalMemberIndexes.some(index =>
            !Number.isSafeInteger(index) || index < 0))) ||
      (onProposalRow !== undefined &&
        (typeof onProposalRow !== 'function' ||
          !['maxFields', 'maxWork', 'maxBytes', 'maxNodes', 'maxDepth',
            'maxUtf16Units'].every(key =>
            Number.isSafeInteger(proposalLimits?.[key]) &&
            proposalLimits[key] >= 0) ||
          proposalLimits.maxBytes === 0 ||
          proposalLimits.maxNodes === 0 ||
          proposalLimits.maxDepth === 0)) ||
      !Number.isSafeInteger(maxBytes) || maxBytes < 0) {
    throw new TypeError('InvalidEffectSourceStore');
  }
  const proposalBounds = onProposalRow === undefined ? undefined :
    Object.freeze({maxFields: proposalLimits.maxFields,
      maxWork: proposalLimits.maxWork, maxBytes: proposalLimits.maxBytes,
      maxNodes: proposalLimits.maxNodes, maxDepth: proposalLimits.maxDepth,
      maxUtf16Units: proposalLimits.maxUtf16Units});
  const proposalMembers = onProposalRow === undefined ? undefined :
    Object.freeze([...(proposalMemberIndexes ?? [memberIndex])]);
  if (proposalMembers?.some(index =>
    moon.clientProgramEffectInputsShareView(inputs, memberIndex, index) !==
      true)) {
    throw new TypeError('ForeignEffectProposalSource');
  }
  signal?.throwIfAborted();
  const selectedResult = local === undefined ? undefined :
    moon.clientProgramEffectLocalResultAt(inputs, local.resultIndex);
  const localDefinition = checked(local === undefined
    ? moon.clientProgramIssueCapturedEffectInputLocalResultDefinition(
      checkedOwner, inputs, memberIndex,
      contractLimits.maxWireBytes, contractLimits.maxNodes,
      contractLimits.maxDepth)
    : moon.clientProgramIssueLocalEffectResultDefinition(checkedOwner,
      moon.clientProgramEffectLocalResultStage(selectedResult),
      moon.clientProgramEffectLocalResultName(selectedResult),
      contractLimits.maxWireBytes, contractLimits.maxNodes,
      contractLimits.maxDepth));
  const localResultDefinition = Object.freeze({
    identity: moon.clientProgramLocalEffectResultDefinitionCid(
      localDefinition),
    wire: moon.clientProgramLocalEffectResultDefinitionJson(localDefinition),
  });
  const unitIndex = local !== undefined
    ? moon.clientProgramEffectLocalResultStage(selectedResult)
    : manifestSet === undefined ? undefined :
    moon.clientProgramEffectInputStage(
      moon.clientProgramEffectInputAt(inputs, memberIndex));
  const localInvocationToken = manifestSet?.get(unitIndex)?.invocation ?? checked(
    moon.clientProgramIssueCapturedEffectInputLocalInvocation(
      checkedOwner, inputs, memberIndex,
      contractLimits.maxWireBytes, contractLimits.maxNodes,
      contractLimits.maxDepth));
  if (manifestSet !== undefined && !manifestSet.has(unitIndex)) {
    manifestSet.set(unitIndex, {invocation: localInvocationToken, artifacts: []});
  }
  const localInvocation = Object.freeze({
    identity: moon.clientProgramLocalEffectInvocationCid(
      localInvocationToken),
    wire: moon.clientProgramLocalEffectInvocationJson(
      localInvocationToken),
  });
  const localContext = Object.freeze({
    admission: localEvidenceContext.admission,
    runDefinition: localEvidenceContext.runDefinition,
    runInvocation: localEvidenceContext.runInvocation,
    observation: localEvidenceContext.observation,
  });
  const proposalPlans = [];
  try {
    for (const index of proposalMembers ?? []) {
      proposalPlans.push(checked(moon.clientProgramEffectProposalBegin(
        inputs, index, proposalBounds.maxFields, proposalBounds.maxWork)));
    }
  } catch (error) {
    for (const plan of proposalPlans) {
      moon.clientProgramEffectProposalCancel(plan);
    }
    throw error;
  }
  let writer;
  try {
    writer = store.createPreparedObjectWriter(maxBytes);
  } catch (error) {
    for (const plan of proposalPlans) {
      moon.clientProgramEffectProposalCancel(plan);
    }
    throw error;
  }
  let sealed;
  let localResultArtifact;
  let byteCount = 0;
  const digest = createHash('sha256');
  const relationChunks = local === undefined ? undefined : [];
  let schemaBody;
  const retainText = text => {
    const bytes = Buffer.byteLength(text, 'utf8');
    if (bytes > local.dependencyText.remaining) {
      throw new RangeError('EffectDependencyBodyByteLimit');
    }
    local.dependencyText.remaining -= bytes;
    return text;
  };
  try {
    if (local !== undefined) retainText('{"sort":"relation","value":}');
    const summary = await exportPinnedResult({
      moon, execution, inputs, memberIndex, limits, signal,
      localResultIndex: local?.resultIndex,
      ...(onProposalRow === undefined ? {} : {
        canonicalRowLimits: {maxNodes: proposalBounds.maxNodes,
          maxDepth: proposalBounds.maxDepth,
          maxUtf16Units: proposalBounds.maxUtf16Units},
        onCanonicalRow: async (index, row) => {
          for (const [planIndex, proposalMemberIndex] of
            proposalMembers.entries()) {
            const projected = checked(moon.clientProgramEffectProposalRow(
              proposalPlans[planIndex], row, index,
              proposalBounds.maxFields, proposalBounds.maxWork,
              proposalBounds.maxBytes, proposalBounds.maxNodes,
              proposalBounds.maxDepth));
            await onProposalRow(proposalMemberIndex, index,
              Object.freeze({selectorWire: projected._0,
                changesWire: projected._1}));
          }
        },
      }),
      onReceipt: (input, receipt, importing) => {
        if (local !== undefined) {
          schemaBody = Object.freeze({kind: 'relation_schema',
            cid: moon.clientProgramEffectInputExportSchemaCid(receipt),
            wire: retainText(moon.clientProgramEffectInputExportSchemaWire(
              receipt)),
          });
        }
        localResultArtifact = local === undefined
          ? control.issueSourceFreeLocalEffectResultArtifact(
          checkedOwner, inputs, memberIndex, importing, localDefinition,
          localInvocationToken, receipt, retention, localContext,
          contractLimits)
          : control.issueDependentLocalEffectResultArtifact(checkedOwner,
            inputs, importing, local.dependency, localDefinition, receipt,
            retention, localContext, contractLimits);
        if (local !== undefined) {
          if (memberIndex === undefined) return undefined;
          if (!moon.clientProgramEffectLocalResultMatchesMember(
            inputs, local.resultIndex, memberIndex)) {
            throw new TypeError('ForeignEffectMemberExport');
          }
          input = moon.clientProgramEffectInputAt(inputs, memberIndex);
        }
        return control.issueEffectSourceArtifactFromExport(
          input, receipt, invocation, retention, sourceBindingCid,
          store.storeAuthorityCid, contractLimits);
      },
      async onChunk(chunk) {
        if (typeof chunk !== 'string') {
          throw new TypeError('InvalidEffectSourceChunk');
        }
        const bytes = Buffer.byteLength(chunk, 'utf8');
        if (bytes > maxBytes - byteCount) {
          throw new RangeError('EffectSourceByteLimit');
        }
        if (relationChunks !== undefined) {
          relationChunks.push(retainText(chunk));
        }
        await writer.append(chunk);
        digest.update(chunk, 'utf8');
        byteCount += bytes;
      },
    });
    for (const plan of proposalPlans) {
      checked(moon.clientProgramEffectProposalFinish(plan,
        summary.rowCount));
    }
    const localManifest = manifestSet === undefined
      ? control.issueLocalEffectResultManifest(checkedOwner,
        localInvocationToken, [localResultArtifact], contractLimits)
      : undefined;
    const physicalCid = `sha256:${digest.digest('hex')}`;
    sealed = await writer.seal(physicalCid);
    if (sealed.cid !== physicalCid || sealed.bytes !== byteCount) {
      throw new Error('EffectSourcePhysicalIdentityMismatch');
    }
    const payload = Object.freeze({
      summary,
      localResultDefinition,
      localInvocation,
      localResultArtifact,
      localManifest,
      ...(local === undefined ? {} : {dependencyBodies: Object.freeze([
        ...local.dependency.bodies,
        ...local.staticBodies,
        ...localEvidenceContext.retentionDependencies,
        ...localEvidenceContext.acquisitionDependencies,
        ...(localEvidenceContext.acquiredCatalogBodies
          ?? localEvidenceContext.acquiredEvidence.catalogBodies),
        schemaBody,
        Object.freeze({kind: 'relation_value', cid: summary.logicalCid,
          wire: '{"sort":"relation","value":' + relationChunks.join('') + '}'}),
      ])}),
      physical: Object.freeze({cid: sealed.cid, bytes: sealed.bytes}),
      prepared: sealed.prepared,
    });
    preparedEffectSourceOwners.set(payload, Object.freeze({
      store, checkedOwner, inputs, memberIndex, localInvocationToken, unitIndex,
      contractLimits: Object.freeze({...contractLimits}),
    }));
    manifestSet?.get(unitIndex).artifacts.push(localResultArtifact);
    return payload;
  } catch (failure) {
    const pendingOwners = [];
    if (failure?.cleanupPending === true &&
        failure.cleanupHandle !== undefined) {
      pendingOwners.push(failure.cleanupHandle);
    }
    let cleanupError;
    try {
      if (sealed === undefined) await writer.cancel();
      else await sealed.prepared.release();
    } catch (error) {
      cleanupError = error;
      pendingOwners.push(Object.freeze({
        status: () => Object.freeze({pending: sealed === undefined
          ? writer.status().reservationHeld === true ||
            writer.status().custodyPending === true
          : sealed.prepared.status().pending === true}),
        retry: sealed === undefined
          ? () => writer.cancel() : () => sealed.prepared.retry(),
      }));
    }
    if (pendingOwners.some(owner => owner.status().pending === true)) {
      const error = new Error('EffectSourceCleanupPending', {cause: failure});
      error.cleanupPending = true;
      error.cleanupError = cleanupError;
      error.cleanupHandle = Object.freeze({
        status: () => Object.freeze({pending: pendingOwners.some(
          owner => owner.status().pending === true)}),
        async retry() {
          const errors = [];
          for (const owner of pendingOwners) {
            if (owner.status().pending !== true) continue;
            try { await owner.retry(); }
            catch (reason) { errors.push(reason); }
          }
          return Object.freeze({
            pending: pendingOwners.some(owner =>
              owner.status().pending === true),
            errors: Object.freeze(errors),
          });
        },
      });
      throw error;
    }
    throw failure;
  } finally {
    for (const plan of proposalPlans) {
      moon.clientProgramEffectProposalCancel(plan);
    }
  }
}

// Admission creates no physical holding and performs no Store I/O.
function admitPinnedEffectSourceHolding({
  payload, store, control, preview, memberIndex, invocation,
}) {
  const owner = preparedEffectSourceOwners.get(payload);
  if (owner?.store !== store ||
      typeof store?.commitPhysicalHolding !== 'function' ||
      typeof control?.admitCapturedEffectSourceArtifact !== 'function' ||
      typeof control?.capturedEffectSourceHoldingCid !== 'function' ||
      typeof control?.localEffectSourceMatches !== 'function' ||
      payload.summary.artifact === undefined) {
    throw new TypeError('InvalidEffectSourceHoldingOwner');
  }
  const source = control.admitCapturedEffectSourceArtifact(
    preview, memberIndex, invocation, payload.summary.artifact,
    store.storeAuthorityCid);
  if (control.localEffectSourceMatches(
    owner.checkedOwner, owner.inputs, memberIndex, payload.localManifest,
    owner.localInvocationToken, payload.localResultArtifact, source) !== true) {
    throw new TypeError('ForeignLocalEffectSource');
  }
  const localEvidence = control.admitLocalEffectSourceEvidence(
    owner.checkedOwner, owner.inputs, memberIndex, payload.localManifest,
    owner.localInvocationToken, payload.localResultArtifact, source,
    owner.contractLimits);
  const holdingCid = control.capturedEffectSourceHoldingCid(source);
  const record = Object.freeze({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'effect-source', holding_cid: holdingCid,
    manifest_cid: payload.summary.artifact.identity,
    objects: Object.freeze([Object.freeze({
      cid: payload.physical.cid, byte_count: payload.physical.bytes,
    })]),
  });
  return Object.freeze({source, memberIndex,
    artifact: payload.summary.artifact,
    localResultDefinition: payload.localResultDefinition,
    localInvocation: payload.localInvocation,
    localResultArtifact: payload.localResultArtifact,
    localManifest: payload.localManifest,
    localEvidence,
    holdingCid, record});
}

/**
 * Reconcile one exact physical holding without re-exporting the source. A
 * failed commit leaves the prepared owner with the caller for same-record
 * retry or explicit cleanup; it never authorizes another Compute attempt.
 */
export async function commitPinnedEffectSourceHolding(options) {
  const holding = admitPinnedEffectSourceHolding(options);
  const {store, payload, shareFromHoldingCid} = options;
  if (shareFromHoldingCid === undefined) {
    await store.commitPhysicalHolding(holding.record, [payload.prepared]);
  } else {
    if (typeof store.sharePhysicalHolding !== 'function' ||
        typeof shareFromHoldingCid !== 'string') {
      throw new TypeError('InvalidEffectSourceHoldingShare');
    }
    await store.sharePhysicalHolding(shareFromHoldingCid, holding.record);
  }
  return holding;
}

// Admit the entire inventory before the first durable write. Return exact
// responsibility records synchronously so a failed or lost commit reply
// cannot hide an already-created holding from the caller. There is no
// cross-member transaction: Store reconciliation uses the same records.
export function preparePinnedEffectSourceHoldings({
  sources, store, control, preview, invocation,
}) {
  const owner = preparedEffectSourceSets.get(sources);
  if (owner?.store !== store || owner?.control !== control ||
      typeof store?.commitPhysicalHolding !== 'function' ||
      typeof store?.sharePhysicalHolding !== 'function' ||
      typeof control?.capturedEffectSourceRecoveryInventoryValid !==
        'function') {
    throw new TypeError('InvalidEffectSourceSetOwner');
  }
  const commit = store.commitPhysicalHolding.bind(store);
  const share = store.sharePhysicalHolding.bind(store);
  const memberPayloads = new Set(sources.members.map(member => member.payload));
  if (sources.payloads.some(payload => !memberPayloads.has(payload)) &&
      !adoptedEffectSourceDependencies.has(sources)) {
    // This entry point commits member holdings only. It must not claim a
    // durable capture while upstream payload custody is still merely prepared.
    throw new TypeError('IncompleteEffectDependencyHoldings');
  }
  const firstByPayload = new Map();
  const entries = sources.members.map(({memberIndex, payload}) => {
    const holding = admitPinnedEffectSourceHolding({payload, store, control,
      preview, memberIndex, invocation});
    const first = firstByPayload.get(payload);
    if (first === undefined) firstByPayload.set(payload, holding.holdingCid);
    return Object.freeze({holding, payload, first});
  });
  const holdings = Object.freeze(entries.map(entry => entry.holding));
  if (control.capturedEffectSourceRecoveryInventoryValid(preview,
    holdings.map(({memberIndex, artifact}) => ({memberIndex, artifact}))) !==
      true) {
    throw new TypeError('IncompleteEffectSourceHoldings');
  }
  let flight;
  return Object.freeze({holdings,
    // Single-flight is physical I/O ownership, not an Effect retry decision.
    // A later call revalidates/re-syncs the Store's exact durable records.
    commit() {
      if (flight !== undefined) return flight;
      flight = (async () => {
        await store.retainEffectCaptureCustody(owner.runDefinition,
          holdings.map(holding => holding.record));
        for (const {holding, payload, first} of entries) {
          if (first === undefined) {
            await commit(holding.record, [payload.prepared]);
          } else {
            await share(first, holding.record);
          }
        }
        return holdings;
      })().finally(() => { flight = undefined; });
      return flight;
    },
  });
}
