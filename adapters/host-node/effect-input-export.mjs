import {installedEffectDependencyOriginal} from '../host-common/installed-effect-dependency-original.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {createHash} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {checkedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {advanceEffectCommandKey} from './effect-command-key.mjs';
import {createPinnedEffectSourceDependencies} from './effect-source-dependencies.mjs';
import {createPinnedEffectSourceHoldings} from './effect-source-holdings.mjs';
import {exportPinnedEffectInput, exportPinnedEffectLocalResult, exportPinnedResult} from './effect-source-stream.mjs';
import {releasePreparedResults} from
  '../host-common/completed-run-publication.mjs';

const preparedEffectSourceOwners = new WeakMap();
const preparedEffectSourceSets = new WeakMap();
const adoptedEffectSourceDependencies = new WeakSet();

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
  onProposalRow, proposalMemberIndexes, proposalLimits, onOriginalArtifact,
  commandWorkspace, onCommandKey, publishedTarget,
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
      (onOriginalArtifact !== undefined && typeof onOriginalArtifact !== 'function') ||
      (onCommandKey !== undefined && typeof onCommandKey !== 'function') ||
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
  if (commandWorkspace !== undefined &&
      (proposalMembers?.length !== 1 || proposalMembers[0] !== memberIndex ||
        local?.tableInput === true ||
        (local !== undefined && moon.clientProgramEffectLocalResultMatchesMember(
          inputs, local.resultIndex, memberIndex) !== true))) {
    throw new TypeError('ForeignEffectCommandWorkspaceRoute');
  }
  if (publishedTarget !== undefined &&
      (proposalMembers?.length !== 1 || proposalMembers[0] !== memberIndex ||
        local?.tableInput === true)) {
    throw new TypeError('ForeignEffectPublishedTargetRoute');
  }
  signal?.throwIfAborted();
  const selectedResult = local === undefined || local.tableInput ? undefined :
    moon.clientProgramEffectLocalResultAt(inputs, local.resultIndex);
  const tableInput = local === undefined || local.tableInput
    ? moon.clientProgramEffectTableInputAt?.(inputs, memberIndex) : undefined;
  const table = tableInput !== undefined;
  if (table && (onProposalRow !== undefined ||
      typeof control.issueSourceFreeLocalEffectTableArtifact !== 'function' ||
      typeof control.issueEffectTableSourceArtifactFromExport !== 'function')) {
    throw new TypeError('InvalidPrivateTableSourceExport');
  }
  const localDefinition = local?.originalArtifact !== undefined
    ? control.originalEffectUnitArtifactDefinition(local.originalArtifact)
    : checked(local === undefined || table
    ? table ? moon.clientProgramIssueCapturedEffectTableInputLocalDefinition(
      checkedOwner, inputs, memberIndex,
      contractLimits.maxWireBytes, contractLimits.maxNodes, contractLimits.maxDepth)
    : moon.clientProgramIssueCapturedEffectInputLocalResultDefinition(
      checkedOwner, inputs, memberIndex,
      contractLimits.maxWireBytes, contractLimits.maxNodes,
      contractLimits.maxDepth)
    : moon.clientProgramIssueLocalEffectResultDefinition(checkedOwner,
      moon.clientProgramEffectLocalResultStage(selectedResult),
      moon.clientProgramEffectLocalResultName(selectedResult),
      contractLimits.maxWireBytes, contractLimits.maxNodes,
      contractLimits.maxDepth));
  const localResultDefinition = Object.freeze({
    identity: table ? moon.clientProgramLocalEffectTableDefinitionCid(localDefinition)
      : moon.clientProgramLocalEffectResultDefinitionCid(localDefinition),
    wire: table ? moon.clientProgramLocalEffectTableDefinitionJson(localDefinition)
      : moon.clientProgramLocalEffectResultDefinitionJson(localDefinition),
  });
  const unitIndex = local !== undefined && !table
    ? moon.clientProgramEffectLocalResultStage(selectedResult)
    : manifestSet === undefined ? undefined :
    table ? moon.clientProgramEffectTableInputStage(tableInput)
      : moon.clientProgramEffectInputStage(
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
    for (const index of commandWorkspace === undefined ? proposalMembers ?? [] : []) {
      proposalPlans.push(checked(publishedTarget === undefined
        ? moon.clientProgramEffectProposalBegin(
          inputs, index, proposalBounds.maxFields, proposalBounds.maxWork)
        : moon.clientProgramEffectProposalBeginWithTarget(
          inputs, index, proposalBounds.maxFields, proposalBounds.maxWork, publishedTarget)));
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
  const dependent = local !== undefined && local.sourceFree !== true;
  const relationChunks = dependent ? [] : undefined;
  let schemaBody;
  let sourceSchema;
  const retainText = text => {
    if (local.dependencyConstruction !== undefined) {
      const original=installedEffectDependencyOriginal(local.dependencyConstruction,moon);
      checked(moon.clientProgramInstalledEffectDependencyTextRetain(original.parent,
        original.prepared,original.request,original.plan,text));
      original.current();
    } else {
      const bytes = Buffer.byteLength(text, 'utf8');
      if (bytes > local.dependencyText.remaining) throw new RangeError('EffectDependencyBodyByteLimit');
      local.dependencyText.remaining -= bytes;
    }
    return text;
  };
  try {
    if (dependent) retainText('{"sort":"relation","value":}');
    const summary = await exportPinnedResult({
      moon, execution, inputs, memberIndex, limits, signal,
      commandWorkspace,
      ...(commandWorkspace === undefined ? {} : {
        async prepareProposal() {
          let key;
          try {
            key = checked(moon.clientProgramStartEffectCommandKeyWorkspace(commandWorkspace));
          } finally {
            moon.clientProgramEffectCommandKeyWorkspaceSynchronousEnd(commandWorkspace);
          }
          await advanceEffectCommandKey(moon, key, signal, 256);
          if (onCommandKey !== undefined && onCommandKey(memberIndex, key) !== undefined) {
            throw new TypeError('InvalidEffectCommandKeyProjection');
          }
          proposalPlans.push(checked(publishedTarget === undefined
            ? moon.clientProgramEffectProposalBeginWithKey(
              inputs, memberIndex, proposalBounds.maxFields, proposalBounds.maxWork, key)
            : moon.clientProgramEffectProposalBeginWithTargetAndKey(
              inputs, memberIndex, proposalBounds.maxFields, proposalBounds.maxWork, publishedTarget, key)));
        },
      }),
      localResultIndex: table ? undefined : local?.resultIndex,
      ...(onProposalRow === undefined ? {} : {
        canonicalRowLimits: {maxNodes: proposalBounds.maxNodes,
          maxDepth: proposalBounds.maxDepth,
          maxUtf16Units: proposalBounds.maxUtf16Units},
        onCanonicalRow: async (index, row) => {
          for (const [planIndex, proposalMemberIndex] of
            proposalMembers.entries()) {
            // This pure common projection examines an already captured row.
            // Its refusal is not an uncertain provider dispatch or Store I/O.
            const projected = checkedEffectPreparation(moon.clientProgramEffectProposalRow(
              proposalPlans[planIndex], row, index,
              proposalBounds.maxFields, proposalBounds.maxWork,
              proposalBounds.maxBytes, proposalBounds.maxNodes,
              proposalBounds.maxDepth));
            await onProposalRow(proposalMemberIndex, index,
              Object.freeze({selectorWire: runtimeField(projected, 0),
                changesWire: runtimeField(projected, 1)}));
          }
        },
      }),
      onReceipt: (input, receipt, importing) => {
        // Retain the original exported schema even when this private Effect
        // input is not a dependent or publicly named Result.
        sourceSchema = Object.freeze({
          cid: moon.clientProgramEffectInputExportSchemaCid(receipt),
          wire: moon.clientProgramEffectInputExportSchemaWire(receipt),
        });
        if (dependent) {
          schemaBody = Object.freeze({kind: 'relation_schema',
            cid: sourceSchema.cid, wire: retainText(sourceSchema.wire),
          });
        }
        localResultArtifact = local?.originalArtifact !== undefined
          ? control.reuseOriginalEffectUnitArtifact(checkedOwner, inputs, local.originalArtifact, importing, receipt)
          : table && dependent
          ? control.issueDependentLocalEffectTableArtifact(checkedOwner,
            inputs, memberIndex, importing, local.dependency, localDefinition,
            receipt, retention, localContext, contractLimits)
          : local === undefined
          ? table ? control.issueSourceFreeLocalEffectTableArtifact(
            checkedOwner, inputs, memberIndex, importing, localDefinition,
            localInvocationToken, receipt, retention, localContext, contractLimits)
          : control.issueSourceFreeLocalEffectResultArtifact(
          checkedOwner, inputs, memberIndex, importing, localDefinition,
          localInvocationToken, receipt, retention, localContext,
          contractLimits)
          : local.sourceFree ? control.issueSourceFreeExportedLocalEffectResultArtifact(
            checkedOwner, inputs, importing, localDefinition, localInvocationToken,
            receipt, retention, localContext, contractLimits)
          : control.issueDependentLocalEffectResultArtifact(checkedOwner,
            inputs, importing, local.dependency, localDefinition, receipt,
            retention, localContext, contractLimits);
        if (onOriginalArtifact !== undefined && proposalMembers !== undefined) {
          for (const originalMember of proposalMembers) {
            // The same original export still owns its reference backing here.
            // The capture must retain the Artifact before a fallible adoption;
            // normal export finally remains responsible for the old receipt.
            if (onOriginalArtifact(localResultArtifact, originalMember) !== undefined) {
              throw new TypeError('InvalidEffectOriginalArtifactProjection');
            }
          }
        }
        if (local !== undefined && !table) {
          if (memberIndex === undefined) return undefined;
          if (!moon.clientProgramEffectLocalResultMatchesMember(
            inputs, local.resultIndex, memberIndex)) {
            throw new TypeError('ForeignEffectMemberExport');
          }
          input = moon.clientProgramEffectInputAt(inputs, memberIndex);
        }
        return (table ? control.issueEffectTableSourceArtifactFromExport
          : control.issueEffectSourceArtifactFromExport)(
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
      summary, schema: sourceSchema,
      localResultDefinition,
      localInvocation,
      localResultArtifact,
      localManifest,
      ...(!dependent ? {} : {dependencyBodies: Object.freeze([
        ...local.dependency.bodies,
        ...(local.dependency.catalogBodies ?? []),
        ...local.staticBodies,
        ...localEvidenceContext.retentionDependencies,
        ...(localEvidenceContext.resultDataPolicy === undefined ? [] :
          [localEvidenceContext.resultDataPolicy]),
        ...(localEvidenceContext.acquisitionDependencies ?? []),
        ...(localEvidenceContext.acquiredCatalogBodies
          ?? localEvidenceContext.acquiredEvidence?.catalogBodies ?? []),
        schemaBody,
        Object.freeze({kind: 'relation_value', cid: summary.logicalCid,
          wire: '{"sort":"relation","value":' + relationChunks.join('') + '}'}),
      ])}),
      physical: Object.freeze({cid: sealed.cid, bytes: sealed.bytes}),
      prepared: sealed.prepared,
    });
    preparedEffectSourceOwners.set(payload, Object.freeze({
      store, checkedOwner, inputs, memberIndex, localInvocationToken, unitIndex,
      tableInput: table,
      contractLimits: Object.freeze({...contractLimits}),
    }));
    // Preserve every independently issued original for its member's custody.
    // Common deduplicates only the canonical named entry after checking the
    // exact live Result origin; it still retains each physical witness.
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

const {commitPinnedEffectSourceHolding, preparePinnedEffectSourceHoldings, readPinnedEffectTableInput} =
  createPinnedEffectSourceHoldings({
    preparedEffectSourceOwners, preparedEffectSourceSets, adoptedEffectSourceDependencies,
  });
export {commitPinnedEffectSourceHolding, preparePinnedEffectSourceHoldings, readPinnedEffectTableInput};
export {readRecoveredEffectTableInput} from './effect-source-holdings.mjs';
export {exportPinnedEffectInput, exportPinnedEffectLocalResult};
export {preparePinnedEffectDependencyInventory, retainPinnedEffectDependencyPayloads};
