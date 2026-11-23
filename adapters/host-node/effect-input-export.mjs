import {installedEffectDependencyOriginal} from '../host-common/installed-effect-dependency-original.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {createPinnedEffectSourceDependencies} from './effect-source-dependencies.mjs';
import {createPinnedEffectSourcePayloads} from './effect-source-payload.mjs';
import {createPinnedEffectSourceHoldings} from './effect-source-holdings.mjs';
import {exportPinnedEffectInput, exportPinnedEffectLocalResult} from './effect-source-stream.mjs';
import {releasePreparedResults} from
  '../host-common/completed-run-publication.mjs';

const preparedEffectSourceOwners = new WeakMap();
const preparedEffectSourceSets = new WeakMap();
const adoptedEffectSourceDependencies = new WeakSet();

const {preparePinnedEffectSourcePayload, preparePinnedEffectSourcePayloadOwned} =
  createPinnedEffectSourcePayloads(preparedEffectSourceOwners);

const {preparePinnedEffectDependencyInventory, retainPinnedEffectDependencyPayloads} =
  createPinnedEffectSourceDependencies({
    preparedEffectSourceOwners, preparedEffectSourceSets, adoptedEffectSourceDependencies,
  });

// Prepare every pinned member under one retention policy. The private optional
// vector preserves each original occurrence's source binding; it is not a new
// identity domain or permission to share another installation's custody.
// MoonBit alone decides whether two members own the same live Result view.
// The caller retains the pins and receives every distinct physical owner;
// durable holdings remain independent even when members share these bytes.
export async function preparePinnedEffectSourceSet({
  maxMembers, maxGroupingWork, memberSourceBindings, commandWorkspaces, publishedTargets, ...options
}) {
  if (options.localEvidenceContext?.catalogDeferred === true && options.dependencyConstruction === undefined) {
    throw new TypeError('MissingOriginalCatalogConstruction');
  }
  const {moon, inputs, control, signal} = options;
  if(options.dependencyConstruction!==undefined){
    const original=installedEffectDependencyOriginal(options.dependencyConstruction,moon);
    // Reuse the actual existing original-input entrance; a foreign registered
    // Run cannot lend its earlier index reservation to this source vector.
    checked(moon.clientProgramInstalledEffectCapturedInputInventoryRetain(
      original.parent,original.prepared,original.request,original.plan,inputs));
    original.current();
  }
  if (!Number.isSafeInteger(maxMembers) || maxMembers < 1 ||
      !Number.isSafeInteger(maxGroupingWork) || maxGroupingWork < 0 ||
      typeof moon?.clientProgramEffectInputCount !== 'function' ||
      typeof moon?.clientProgramEffectInputsShareView !== 'function' ||
      typeof moon?.clientProgramEffectInputStage !== 'function' ||
      typeof control?.publicationPreparedReleaseAction !== 'function' ||
      typeof control?.publicationCleanupOwnerAction !== 'function' ||
      options.memberIndex !== undefined ||
      options.proposalMemberIndexes !== undefined || options.publishedTarget !== undefined) {
    throw new TypeError('InvalidEffectSourceSet');
  }
  const count = moon.clientProgramEffectInputCount(inputs);
  if (!Number.isSafeInteger(count) || count < 1 || count > maxMembers) {
    throw new RangeError('EffectSourceMemberLimit');
  }
  // Private phase views are retained by the original capture before this
  // asynchronous export. Only Common can match one to its Run/member/limits.
  let workspaces;
  let hasCommandWorkspace = false;
  if (commandWorkspaces !== undefined) {
    if (!Array.isArray(commandWorkspaces) || !Object.isFrozen(commandWorkspaces) ||
        commandWorkspaces.length !== count) {
      throw new TypeError('InvalidEffectCommandWorkspaces');
    }
    workspaces = [];
    for (let index = 0; index < count; index++) {
      const slot = Object.getOwnPropertyDescriptor(commandWorkspaces, index);
      if (slot === undefined || !Object.hasOwn(slot, 'value')) {
        throw new TypeError('InvalidEffectCommandWorkspaces');
      }
      workspaces.push(slot.value);
      hasCommandWorkspace ||= slot.value !== undefined;
    }
    Object.freeze(workspaces);
  }
  // The capture owns these originals. Snapshot dense own-data slots without
  // inspecting, cloning or reissuing a target; Common checks its occurrence.
  let targets;
  let hasPublishedTarget = false;
  if (publishedTargets !== undefined) {
    if (!Array.isArray(publishedTargets) || !Object.isFrozen(publishedTargets) ||
        publishedTargets.length !== count) {
      throw new TypeError('InvalidEffectPublishedTargets');
    }
    targets = [];
    for (let index = 0; index < count; index++) {
      const slot = Object.getOwnPropertyDescriptor(publishedTargets, index);
      if (slot === undefined || !Object.hasOwn(slot, 'value')) {
        throw new TypeError('InvalidEffectPublishedTargets');
      }
      targets.push(slot.value);
      hasPublishedTarget ||= slot.value !== undefined;
    }
    Object.freeze(targets);
    if (hasPublishedTarget && typeof options.onProposalRow !== 'function') {
      throw new TypeError('InvalidEffectPublishedTargets');
    }
  }
  let bindings;
  if (memberSourceBindings !== undefined) {
    if (!Array.isArray(memberSourceBindings) ||
        !Object.isFrozen(memberSourceBindings) ||
        memberSourceBindings.length !== count) {
      throw new TypeError('InvalidEffectMemberSourceBindings');
    }
    bindings = [];
    for (let index = 0; index < count; index++) {
      const slot = Object.getOwnPropertyDescriptor(memberSourceBindings, index);
      const entry = slot?.value;
      const member = Object.getOwnPropertyDescriptor(entry ?? {}, 'memberIndex');
      const binding = Object.getOwnPropertyDescriptor(entry ?? {}, 'sourceBindingCid');
      if (entry === null || typeof entry !== 'object' ||
          !Object.isFrozen(entry) || member?.value !== index ||
          typeof binding?.value !== 'string' ||
          binding.value.length !== 71 ||
          !/^sha256:[0-9a-f]{64}$/u.test(binding.value)) {
        throw new TypeError('InvalidEffectMemberSourceBindings');
      }
      bindings.push(binding.value);
    }
    Object.freeze(bindings);
  }
  let remaining = maxGroupingWork;
  if (bindings !== undefined) {
    // A dependent Result is also an import producer. Splitting its source
    // bindings requires an independently admitted dependency inventory; never
    // silently flatten that inventory to one representative member.
    if (options.localEvidenceContext?.acquiredEvidence !== undefined ||
        options.localEvidenceContext?.acquiredEvidenceByUnit !== undefined ||
        options.localEvidenceContext?.modelOriginalByUnit !== undefined ||
        typeof moon.clientProgramEffectResultImportCount !== 'function') {
      throw new TypeError('UnsupportedDependentEffectMemberSourceBindings');
    }
    for (let index = 0; index < count; index++) {
      if (remaining === 0) throw new RangeError('EffectSourceGroupingLimit');
      remaining--;
      const table = moon.clientProgramEffectTableInputAt?.(inputs, index);
      const stage = table === undefined ? moon.clientProgramEffectInputStage(
        moon.clientProgramEffectInputAt(inputs, index))
        : moon.clientProgramEffectTableInputStage(table);
      const imports = moon.clientProgramEffectResultImportCount(options.checkedOwner, stage);
      if (!Number.isSafeInteger(imports) || imports !== 0) {
        throw new TypeError('UnsupportedDependentEffectMemberSourceBindings');
      }
    }
  }
  // A source-free Model is not itself an imported Local Result. Preserve
  // the existing self-contained capture when no Effect input imports another
  // Unit; a populated dependency inventory would have no admitted roots.
  const importedSourceFree = bindings === undefined &&
    options.localEvidenceContext?.sourceFreeDependencyClosure === true &&
    Array.from({length: count}, (_, index) => {
      const table = moon.clientProgramEffectTableInputAt?.(inputs, index);
      const input = moon.clientProgramEffectInputAt(inputs, index);
      const stage = table === undefined ? moon.clientProgramEffectInputStage(input)
        : moon.clientProgramEffectTableInputStage(table);
      return moon.clientProgramEffectResultImportCount(options.checkedOwner, stage) > 0;
    }).some(Boolean);
  if (options.localEvidenceContext?.acquiredEvidence !== undefined ||
      options.localEvidenceContext?.modelOriginalByUnit !== undefined || importedSourceFree) {
    return prepareDependentEffectSourceSet({...options, commandWorkspaces: workspaces, publishedTargets: targets},
      count, maxGroupingWork, hasCommandWorkspace, hasPublishedTarget);
  }
  const groups = [];
  // Every source Unit Manifest covers all checked Result declarations, even
  // when an ordinary Effect consumes only a subset. These extra exports use
  // the retained capture; they are neither new Effect members nor source reads.
  const manifestResults = [];
  const resultCount = moon.clientProgramEffectLocalResultCount(inputs);
  if (!Number.isSafeInteger(resultCount) || resultCount < 0 || resultCount > 4096) {
    throw new RangeError('EffectManifestResultLimit');
  }
  if (resultCount > remaining) throw new RangeError('EffectSourceGroupingLimit');
  remaining -= resultCount;
  for (let resultIndex = 0; resultIndex < resultCount; resultIndex++) {
    const result = moon.clientProgramEffectLocalResultAt(inputs, resultIndex);
    if (result === undefined) throw new TypeError('UnavailableEffectManifestResult');
    manifestResults.push({resultIndex, result,
      unitIndex: moon.clientProgramEffectLocalResultStage(result)});
  }
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
    const group = groups.find(value => {
      const sameView = shares(value[0], index);
      return sameView && workspaces?.[value[0]] === undefined &&
        workspaces?.[index] === undefined && targets?.[value[0]] === undefined &&
        targets?.[index] === undefined && (bindings === undefined ||
        bindings[value[0]] === bindings[index]);
    });
    if (group === undefined) {
      groups.push([index]);
    }
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
        commandWorkspace: workspaces?.[indexes[0]],
        publishedTarget: targets?.[indexes[0]],
        ...(bindings === undefined ? {} : {
          sourceBindingCid: bindings[indexes[0]],
        }),
        ...(owned.onProposalRow === undefined ? {} : {
          proposalMemberIndexes: indexes,
        }),
      }, manifestSet);
      payloads.push(payload);
      for (const memberIndex of indexes) {
        members[memberIndex] = Object.freeze({memberIndex, payload});
      }
    }
    for (const entry of manifestResults) {
      if (!manifestSet.has(entry.unitIndex)) continue;
      const already = payloads.some(payload => {
        if (remaining === 0) throw new RangeError('EffectSourceGroupingLimit');
        remaining--;
        const owner = preparedEffectSourceOwners.get(payload);
        return !owner.tableInput && owner.memberIndex !== undefined &&
          moon.clientProgramEffectLocalResultMatchesMember(
            inputs, entry.resultIndex, owner.memberIndex);
      });
      if (!already) payloads.push(await preparePinnedEffectSourcePayloadOwned({
        ...owned, memberIndex: undefined, onProposalRow: undefined,
      }, manifestSet, {resultIndex: entry.resultIndex, sourceFree: true}));
    }
    for (const unit of manifestSet.values()) {
      unit.manifest = control.issueLocalEffectResultManifest(
        owned.checkedOwner, unit.invocation, unit.artifacts,
        owned.contractLimits);
    }
    const memberPayloads = new Set(members.map(member => member.payload));
    const temporary = payloads.filter(payload => !memberPayloads.has(payload));
    if (temporary.length > 0) {
      const released = new Error('TemporaryEffectManifestPayloadsReleased');
      try { await releasePreparedResults(temporary, released, control); }
      catch (error) { if (error !== released) throw error; }
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
    const result = Object.freeze({payloads: Object.freeze(payloads.filter(value => memberPayloads.has(value)).map(value =>
      finalized.get(value))), members: Object.freeze(members.map(member =>
      Object.freeze({...member, payload: finalized.get(member.payload)})))});
    preparedEffectSourceSets.set(result, Object.freeze({runtime:moon,store: owned.store,
      control: owned.control, contractLimits: owned.contractLimits,
      dependencyConstruction: owned.dependencyConstruction,
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
async function prepareDependentEffectSourceSet(options, memberCount, maxWork,
  hasCommandWorkspace, hasPublishedTarget) {
  const {moon, inputs, control, checkedOwner, signal, contractLimits} = options;
  if (hasCommandWorkspace &&
      typeof moon.clientProgramBeginEffectLocalCommandKeyWorkspace !== 'function') {
    // No substitution of a member import or caller-supplied byte allowance
    // for the original Local Result receiver.
    throw new TypeError('EffectCommandDependencyWorkspaceUnavailable');
  }
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
  // Private Table occurrences inhabit a separate namespace. Only the
  // existing captured borrow proof can share one export across members.
  const tables = [];
  for (let member = 0; member < memberCount; member++) {
    signal?.throwIfAborted();
    spend();
    const table = moon.clientProgramEffectTableInputAt(inputs, member);
    if (table === undefined) continue;
    if (memberIndexes.has(member)) throw new TypeError('DuplicateEffectDependencyMember');
    let shared;
    for (const entry of tables) {
      spend();
      if (moon.clientProgramEffectInputsShareView(inputs, entry.members[0], member)) {
        shared = entry;
        break;
      }
    }
    if (shared === undefined) {
      spend();
      if (!moon.clientProgramEffectInputsShareView(inputs, member, member)) {
        throw new TypeError('UnavailableEffectSource');
      }
      const unitIndex = moon.clientProgramEffectTableInputStage(table);
      if (!Number.isSafeInteger(unitIndex) || unitIndex < 0) {
        throw new TypeError('InvalidEffectDependencyOrder');
      }
      shared = {tableInput: true, unitIndex, members: []};
      tables.push(shared);
      selected.push(shared);
      if (!units.has(unitIndex)) units.set(unitIndex, []);
      units.get(unitIndex).push(shared);
    }
    memberIndexes.add(member);
    shared.members.push(member);
  }
  // Complete each original Unit before any of its consumers. Table entries
  // are never considered public Result import producers.
  selected.sort((left, right) => left.unitIndex - right.unitIndex);
  const orderedUnits = [...units.entries()].sort((left, right) => left[0] - right[0]);
  if (memberIndexes.size !== memberCount) {
    throw new TypeError('IncompleteEffectDependencyMembers');
  }
  // Complete original membership/grouping before any Store writer. A key
  // scope belongs to exactly one member even when the original view is shared.
  // Separate physical exports retain one original logical Manifest entry.
  const distinctMembers = hasCommandWorkspace || hasPublishedTarget;
  for (const entry of selected) {
    const groups = [];
    let unkeyed;
    for (const member of distinctMembers ? entry.members : []) {
      spend();
      const commandWorkspace = options.commandWorkspaces?.[member];
      const publishedTarget = options.publishedTargets?.[member];
      if ((commandWorkspace !== undefined || publishedTarget !== undefined) && entry.tableInput) {
        throw new TypeError('EffectCommandDependencyWorkspaceUnavailable');
      }
      spend();
      if (moon.clientProgramEffectInputsShareView(inputs, entry.members[0], member) !== true) {
        throw new TypeError('ForeignEffectProposalSource');
      }
      if (commandWorkspace !== undefined || publishedTarget !== undefined) groups.push([member]);
      else if (unkeyed === undefined) {
        unkeyed = [member];
        groups.push(unkeyed);
      } else unkeyed.push(member);
    }
    entry.groups = !distinctMembers ? [entry.members]
      : groups.length === 0 ? [[]] : groups;
    entry.payloads = [];
    entry.memberPayloads = new Map();
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
    for (const [unitIndex, entries] of orderedUnits) {
      signal?.throwIfAborted();
      const staticSelection = options.dependencyConstruction === undefined ? checked(
        moon.clientProgramEffectLocalStaticBodies(checkedOwner, unitIndex,
          staticEntriesRemaining, Math.min(contractLimits.maxWireBytes, dependencyText.remaining),
          contractLimits.maxNodes, contractLimits.maxDepth))
        : (()=>{
          const original=installedEffectDependencyOriginal(options.dependencyConstruction,moon);
          const value=checked(moon.clientProgramInstalledEffectStaticDependencyBodies(original.parent,
            original.prepared,original.request,original.plan,inputs,unitIndex,
            contractLimits.maxWireBytes,contractLimits.maxNodes,contractLimits.maxDepth));
          original.current();return value;
        })();
      const staticBodies = Object.freeze(staticSelection.map(pair => {
        if (options.dependencyConstruction === undefined) staticEntriesRemaining--;
        const wire = moon.clientProgramEffectLocalDependencyBodyJson(runtimeField(pair, 1));
        const bytes = Buffer.byteLength(wire, 'utf8');
        if (options.dependencyConstruction === undefined) {
          if (bytes > dependencyText.remaining) throw new RangeError('EffectDependencyBodyByteLimit');
          dependencyText.remaining -= bytes;
        }
        return Object.freeze({kind: runtimeField(pair, 0),
          cid: moon.clientProgramEffectLocalDependencyBodyCid(runtimeField(pair, 1)), wire});
      }));
      const imports = moon.clientProgramEffectResultImportCount(
        checkedOwner, unitIndex);
      if (!Number.isSafeInteger(imports) || imports < 0 || imports > remaining) {
        throw new RangeError('EffectDependencyImportLimit');
      }
      const retainedUnit = owned.localEvidenceContext.originalUnitResults?.get(unitIndex);
      const originalUnit = retainedUnit?.results?.manifest === undefined ? undefined : retainedUnit;
      let dependency = originalUnit?.value;
      if (originalUnit !== undefined) {
        for (const original of originalUnit.results.artifacts) {
          control.bindOriginalEffectUnitArtifact(checkedOwner, inputs, original.artifact,
            owned.localEvidenceContext);
        }
      } else if (imports === 0) {
        dependency = owned.localEvidenceContext.acquiredEvidenceByUnit?.[unitIndex]
          ?? (unitIndex === 0 ? owned.localEvidenceContext.acquiredEvidence : undefined);
        if (dependency === undefined &&
            owned.localEvidenceContext.sourceFreeDependencyClosure === true) {
          dependency = control.issueSourceFreeEffectEvidence(checkedOwner,
            unitIndex, owned.contractLimits);
        }
        if (dependency === undefined && owned.localEvidenceContext.modelOriginalByUnit?.[unitIndex] === undefined) {
          throw new TypeError('MissingEffectSourceEvidence');
        }
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
            if (entry.tableInput) continue;
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
      const model = owned.localEvidenceContext.modelOriginalByUnit?.[unitIndex];
      if (model !== undefined && originalUnit === undefined) {
        dependency = control.issueOriginalModelEffectEvidence(model,
          owned.localEvidenceContext.modelRetention,
          imports === 0 ? undefined : dependency, owned.contractLimits, options.dependencyConstruction !== undefined);
      }
      if (dependency.catalogDeferred === true && options.dependencyConstruction === undefined) {
        throw new TypeError('MissingOriginalCatalogConstruction');
      }
      const unit = {invocation: dependency.invocation, artifacts: []};
      const manifestSet = new Map([[unitIndex, unit]]);
      for (const entry of entries) {
        const originalArtifact = originalUnit === undefined || entry.tableInput ? undefined
          : originalUnit.results.artifacts.find(original =>
            original.name === moon.clientProgramEffectLocalResultName(entry.result))?.artifact;
        if (originalUnit !== undefined && !entry.tableInput && originalArtifact === undefined) {
          throw new TypeError('OriginalEffectUnitResultUnavailable');
        }
        for (const indexes of entry.groups) {
          signal?.throwIfAborted();
          const proposes = owned.onProposalRow !== undefined && indexes.length > 0;
          const payload = await preparePinnedEffectSourcePayloadOwned({
            ...owned, memberIndex: indexes[0],
            commandWorkspace: owned.commandWorkspaces?.[indexes[0]],
            publishedTarget: owned.publishedTargets?.[indexes[0]],
            onProposalRow: proposes ? owned.onProposalRow : undefined,
            ...(proposes ? {proposalMemberIndexes: indexes} : {}),
          }, manifestSet, {resultIndex: entry.resultIndex, tableInput: entry.tableInput, dependency,
            dependencyText, dependencyConstruction: options.dependencyConstruction, staticBodies,
            ...(originalUnit === undefined || entry.tableInput ? {} : {
              originalArtifact,
            })}, entry.payloads.length > 0);
          payloads.push(payload);
          entry.payloads.push(payload);
          entry.payload ??= payload;
          for (const member of indexes) entry.memberPayloads.set(member, payload);
        }
      }
      const manifest = originalUnit === undefined
        ? control.issueLocalEffectResultManifest(checkedOwner, unit.invocation, unit.artifacts, owned.contractLimits)
        : control.reuseOriginalEffectUnitManifest(checkedOwner, unit.invocation, unit.artifacts,
          originalUnit.results.manifest);
      manifests.set(unitIndex, manifest);
      for (const entry of entries) {
        const finalized = new Map();
        entry.payloads = entry.payloads.map(previous => {
          const value = Object.freeze({...previous, localManifest: manifest});
          preparedEffectSourceOwners.set(value, preparedEffectSourceOwners.get(previous));
          finalized.set(previous, value);
          return value;
        });
        entry.payload = finalized.get(entry.payload);
        for (const [member, previous] of entry.memberPayloads) {
          entry.memberPayloads.set(member, finalized.get(previous));
        }
      }
    }
    signal?.throwIfAborted();
    const members = new Array(memberCount);
    for (const entry of selected) {
      for (const memberIndex of entry.members) {
        members[memberIndex] = Object.freeze({memberIndex,
          payload: entry.memberPayloads.get(memberIndex)});
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
        await releasePreparedResults(temporary.flatMap(entry => entry.payloads),
          released, control);
      } catch (error) {
        if (error !== released) throw error;
      }
    }
    const result = Object.freeze({
      payloads: Object.freeze(retained.flatMap(entry => entry.payloads)),
      members: Object.freeze(members),
      dependencies: Object.freeze(retained.map(entry => Object.freeze({
        resultIndex: entry.resultIndex, unitIndex: entry.unitIndex,
        payload: entry.payload,
      }))),
    });
    preparedEffectSourceSets.set(result, Object.freeze({runtime:moon,store: owned.store,
      control: owned.control, contractLimits: owned.contractLimits,
      dependencyConstruction: owned.dependencyConstruction,
      runDefinition: Object.freeze({...owned.localEvidenceContext.runDefinition})}));
    return result;
  } catch (error) {
    await releasePreparedResults(payloads, error, control);
    throw error;
  }
}

const {commitPinnedEffectSourceHolding, preparePinnedEffectSourceHoldings, readPinnedEffectTableInput} =
  createPinnedEffectSourceHoldings({
    preparedEffectSourceOwners, preparedEffectSourceSets, adoptedEffectSourceDependencies,
  });
export {commitPinnedEffectSourceHolding, preparePinnedEffectSourceHoldings, readPinnedEffectTableInput};
export {readRecoveredEffectTableInput} from './effect-source-holdings.mjs';
export {exportPinnedEffectInput, exportPinnedEffectLocalResult};
export {preparePinnedEffectDependencyInventory, retainPinnedEffectDependencyPayloads};
export {preparePinnedEffectSourcePayload};
