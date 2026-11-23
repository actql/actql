// The explicit Project Mock's real file writes, through the existing Row
// Effect owner. No live Salesforce request/credential, hidden mirror, automatic
// approval, replacement Run or permission derived from a profile is supplied.
import {createHash} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {authorizationDispatchFacts, assertAuthorizationAccountCurrent}
  from '../host-common/authorization-gate.mjs';
import {retainInstalledRowEffectAdapter, installedRowEffectConstructionLimits,
  prepareInstalledTargetPlanRecipes} from '../host-node/installed-row-effect.mjs';
import {prepareInstalledPhysicalWritePlanRecipe} from '../host-node/installed-effect-plan.mjs';
import {installedUpdateTargets, composeInstalledEffects} from '../host-node/installed-effect-inventory.mjs';
import {createMockFileTarget} from '../host-node/mock-file-target.mjs';
import {retainInstalledHostInitializationFailure} from '../host-node/installed-host-cleanup.mjs';
import {declaredProjectMockFootprintConstructionGeometry} from '../host-node/declared-project-catalog-construction.mjs';

const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const wire = value => canonicalJson(value, {dataKeys: true});
const hash = value => 'sha256:' + createHash('sha256').update(wire(value)).digest('hex');
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const closed = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
// Canonical DATA snapshots must also seal nested arrays/objects. These carry
// no original capabilities; current grants and physical owners stay separate.
const snapshot = value => {
  const freeze = entry => {
    if (entry !== null && typeof entry === 'object') {
      for (const child of Object.values(entry)) freeze(child);
      Object.freeze(entry);
    }
    return entry;
  };
  return freeze(JSON.parse(wire(value)));
};
const installations = new WeakMap();
const updateKinds = Object.freeze(['update']);
const deleteKinds = Object.freeze(['delete']);
const guardedKinds = Object.freeze(['update', 'delete']);
const updateRequestKeys = Object.freeze(['binding', 'mapping', 'target', 'value', 'version', 'before']);
const deleteRequestKeys = Object.freeze(['binding', 'mapping', 'target', 'version', 'before']);
const noFields = Object.freeze([]);
const operationOf = target => target.write.operation ?? 'update';
const recoveryKind = kind => kind === 'delete' ? 'mock-file-row-delete' : 'mock-file-row-update';
const responseAction = kind => kind === 'delete' ? 'deleted' : 'updated';
const targetLimits = Object.freeze({maxFileBytes: 1048576, maxRows: 100,
  maxNodes: 16384, maxDepth: 32, maxWork: 16777216, maxResponseBytes: 65536,
  maxEffects: 16});
const synchronous = value => {
  if (value === undefined) return;
  if (value instanceof Promise) void value.catch(() => {});
  fail('InvalidMockFileCurrentFence');
};
const ports = Object.freeze({
  admit: 'clientProgramRelationAdmitDocument',
  project: 'clientProgramRelationProjectTargetDocument',
  observe: 'clientProgramRelationObserveTarget',
  before: 'clientProgramRelationTargetBefore',
  version: 'clientProgramRelationTargetVersion',
  update: 'clientProgramRelationPrepareTargetUpdate',
  delete: 'clientProgramRelationPrepareTargetDelete',
  construction: 'clientProgramInstalledSourceConstructionCapacity',
});

// Internal DATA codec, shared by the actual locked writer and its component
// controls. It borrows the original Catalog/Common; it owns no file, Account,
// request admission, dispatch claim or current/cleanup capability.
export function createMockFileRowCodec({bundle, original, call}) {
  const admit = (bytes, target) => {
    const originalDocument = checked(call('admit', bytes, targetLimits.maxFileBytes,
      targetLimits.maxNodes, targetLimits.maxDepth, targetLimits.maxRows, targetLimits.maxWork));
    const projections = new Map();
    for (const source of bundle.sources) for (const model of source.physical) {
      const writable = source === original && model === target.physical
        ? target.write.writable_fields ?? noFields : model.writableFields;
      projections.set(model, checked(call('project', originalDocument, model.declaration,
        model.resource, model.itemsPath, model.keyPath, model.primaryIdentity, writable)));
    }
    const selected = projections.get(target.physical);
    if (selected === undefined) fail('InvalidInstalledMockEffect');
    return {originalDocument, projections, selected};
  };
  const observe = (document, target) => {
    const row = checked(call('observe', document.selected, original.declaration, target));
    const beforeWire = call('before', row), versionCid = call('version', row);
    if (typeof beforeWire !== 'string' || !cid(versionCid)) fail('InvalidMockTargetObservation');
    const before = snapshot(JSON.parse(beforeWire));
    return {row, before, versionCid, beforeWire};
  };
  return Object.freeze({admit, observe,
    replace(operation, bytes, target, record, physicalOperation) {
      if (operation !== 'update' && operation !== 'delete') fail('InvalidMockEffectRequest');
      // Re-admit the latest WHOLE document supplied by the SAME locked file
      // owner, then replace only the original row's admitted spans.
      physicalOperation?.chargeBytes(BigInt(bytes.length));
      const document = admit(bytes, target), observed = observe(document, record.target);
      if (observed.versionCid !== record.version || wire(observed.before) !== wire(record.before)) {
        fail('MockTargetVersionConflict');
      }
      const replacement = checked(operation === 'delete'
        ? call('delete', document.selected, observed.row, record.version, targetLimits.maxWork)
        : call('update', document.selected, observed.row, record.version, wire(record.value), targetLimits.maxWork));
      physicalOperation?.chargeBytes(BigInt(replacement.length));
      return replacement;
    },
  });
}

// Complete logical row identities inside ONE unchanged physical boundary.
// The checked Catalog has already refused overlapping collection paths.
// Resource/Mapping aliases and values/versions are deliberately absent from
// the object identity: aliases cannot disguise the same physical row.
export function mockFileRowFootprint({bindingCid, target, selectors}) {
  if (!cid(bindingCid) || !Array.isArray(selectors) || selectors.length > targetLimits.maxRows ||
      selectors.some(value => typeof value !== 'string' || !value.isWellFormed())) {
    fail('InvalidMockEffectFootprint');
  }
  const physical = target.physical;
  const scheme = {kind: 'mock-file-row-update',
    identity_fields: ['items_path', 'key_path', 'primary_identity', 'identity']};
  return Object.freeze({kind: 'exact_targets', provider_namespace: 'local-mock-file',
    provider_boundary_cid: bindingCid, resource_kind: target.write.resource,
    resource_identity_scheme_cid: hash(scheme),
    provider_object_identity_cids: Object.freeze(selectors.map(identity => hash({
      items_path: physical.itemsPath, key_path: physical.keyPath,
      primary_identity: physical.primaryIdentity, identity}))),
  });
}

export async function installPreparedProjectMockEffects({moon, mockPreparation,
  baseEnvironmentWire, authorizationFor, principalId, runtimeBundleCid, bindingCid, bindingFor,
  ledgerRoot, assertCurrent, effectResources, installationServices, io, observeWrite}) {
  if (typeof mockPreparation?.originalsForRuntime !== 'function' ||
      typeof mockPreparation.constructWritableRuntime !== 'function' ||
      typeof authorizationFor !== 'function' || typeof assertCurrent !== 'function' ||
      typeof principalId !== 'string' || !cid(runtimeBundleCid) ||
      (typeof bindingFor !== 'function' && !cid(bindingCid))) fail('InvalidInstalledMockEffect');
  const resourceMethods = Object.fromEntries(['bindRunOriginal', 'assertCurrent', 'limits'].map(name => {
    const field = effectResources === null || typeof effectResources !== 'object'
      ? undefined : Object.getOwnPropertyDescriptor(effectResources, name);
    if (field === undefined || !Object.hasOwn(field, 'value') ||
        typeof field.value !== 'function') fail('InstalledMockEffectResourcesUnavailable');
    return [name, field.value];
  }));
  const resources = Object.freeze(Object.fromEntries(Object.entries(resourceMethods)
    .map(([name, method]) => [name, (...args) => Reflect.apply(method, effectResources, args)])));
  const bundle = mockPreparation.originalsForRuntime(moon);
  if (!Array.isArray(bundle.writables) || bundle.writables.length === 0) fail('InstalledMockWritableTargetUnavailable');
  function current() {
    synchronous(assertCurrent());
    if (mockPreparation.originalsForRuntime(moon) !== bundle) fail('ForeignInstalledMockPreparation');
  }
  current();
  const methods = Object.fromEntries(Object.entries(ports).map(([name, port]) => [name, moon?.[port]]));
  if (!Object.values(methods).every(value => typeof value === 'function')) fail('InstalledMockTargetRuntimeUnavailable');
  const call = (name, ...args) => Reflect.apply(methods[name], moon, args);
  // The complete metadata implementation is held before the first file owner,
  // source-driver registry or source/alias vector is constructed.
  const implementation = await mockPreparation.constructWritableRuntime(moon, 'root', undefined, () => {
    const file = createMockFileTarget({dataPath: bundle.dataPath, maxBytes: targetLimits.maxFileBytes,
      assertCurrent: current, observeWrite, ...(io === undefined ? {} : {io})});
    return {file, sources: bundle.sources.filter(source => source.writes.length !== 0)};
  });
  const {file, sources} = implementation;
  let resourceObservation;
  try {
    const installed = await composeInstalledEffects(sources,
      {moon, baseEnvironmentWire, installationServices}, async (original, _options, retain) => {
        const prepared = original.effectPrepared, catalogue = original.catalogue;
        if (typeof original.effectMember?.load !== 'function' || prepared?.declaration !== original.declaration ||
            prepared.environment === undefined) fail('InstalledSourceInitializationUnavailable');
        const selectedBinding = bindingFor === undefined ? sources.length === 1 ? bindingCid : undefined
          : bindingFor(original);
        if (!cid(selectedBinding)) fail('ForeignInstalledMockSourceBinding');
        const authorization = await authorizationFor(catalogue.connection);
        current();
        const constructed = await mockPreparation.constructWritableRuntime(moon, 'source', original, () => {
          const targets = bundle.writables.filter(target => target.source === original);
          if (targets.some(target => target.mapping === undefined || target.mapping.body !== target.write.mappingWire ||
              target.physical.declaration !== original.declaration)) fail('InvalidInstalledMockEffect');
          const spec = targets[0].write;
          const constructed = mockRowEffectDriver({bundle, original, targets,
            bindingCid: selectedBinding, principalId, authorization, current, call, resources, file});
          if (targets.every(target => target.write.permission === spec.permission &&
              target.write.observe_permission === spec.observe_permission)) {
            return {...constructed, targets,
              managedPlanRecipe: mockFileEffectPlanRecipe(moon, bundle, spec.permission, spec.observe_permission)};
          }
          const recipes = Object.create(null);
          for (const {mapping, write} of targets) {
            const targetReadOperation = write.observe_permission;
            recipes[mapping.mappingCid] = Object.freeze({targetReadOperation,
              recipe: mockFileEffectPlanRecipe(moon, bundle, write.permission, targetReadOperation)});
          }
          return {...constructed, targets,
            managedTargetPlanRecipes: prepareInstalledTargetPlanRecipes(prepared.mappings, Object.freeze(recipes))};
        });
        const {driver, site, targets, managedPlanRecipe, managedTargetPlanRecipes} = constructed;
        // Every driver observes this SAME physical file. Reuse an existing
        // original observer for whole-project custody instead of allocating
        // another Run registry. This selects no grant or dispatch authority.
        resourceObservation ??= constructed.resourceObservation;
        try {
          // A member is consumed ONCE with ALL of its original prepared
          // mappings. Logical routing happens inside this same installed driver.
          const effect = await original.effectMember.load({moon, mappings: prepared.mappings,
            environmentWire: prepared.environment.wire, connectorId: catalogue.connectorId,
            connectorRegistration: catalogue.registration, connectorRevision: catalogue.revision,
            connection: catalogue.connection, site, authorization, runtimeBundleCid,
            bindingCid: selectedBinding, ledgerRoot, driver, managedPlanRecipe,
            ...(managedTargetPlanRecipes === undefined ? {} : {managedTargetPlanRecipes}), effectResources: resources,
            limits: {maxRows: targetLimits.maxRows}});
          retain(effect);
          current();
          const projection = await mockPreparation.constructWritableRuntime(moon, 'aliases', original, () => {
            const aliases = targets.flatMap(target => target.write.aliases.map(name =>
              Object.freeze({name, targetRef: target.mapping.target})));
            return retainInstalledRowEffectAdapter(effect, Object.freeze({...effect,
              queryUpdateTargets: installedUpdateTargets(effect, aliases)}));
          });
          installations.set(projection, constructed.resourceObservation);
          return projection;
        } catch (cause) {
          try {await site.close();} catch (cleanup) {
            throw Object.assign(new Error('InstalledMockEffectCleanupPending', {cause}),
              {code: 'InstalledMockEffectCleanupPending', cleanupPending: true,
                cleanupHandle: Object.freeze({status: site.status, retry: site.close}), cleanup});
          }
          throw cause;
        }
      });
    if (resourceObservation === undefined) fail('InstalledMockWritableTargetUnavailable');
    installations.set(installed, resourceObservation);
    return installed;
  } catch (cause) {
    // Existing aggregate custody drains the original failure and this shared
    // physical owner independently. Unknown/missing ACKs stay pending.
    throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: {close: file.close}});
  }
}

// One finite file operation window. Common supplies parser/control tariffs;
// only the actual declared projections and file/replacement buffers vary here.
// Returned request/response DATA has the existing JSON recipe and output guard.
export function mockFileEffectPlanRecipe(moon, bundle, operation, targetReadOperation) {
  const bytes = BigInt(targetLimits.maxFileBytes), nodes = BigInt(targetLimits.maxNodes);
  const projections = BigInt(bundle.sources.reduce((sum, source) => sum + source.physical.length, 0));
  const workspace = Object.freeze({nodes: 4n * nodes * projections,
    text: bytes * projections, wire: bytes});
  const zero = Object.freeze({nodes: 0n, text: 0n, wire: 0n});
  const capacity = value => checked(moon.clientProgramInstalledSourceConstructionCapacity(
    0n, 0n, 0n, value.nodes, value.text, value.wire));
  const decode = checked(moon.clientProgramInstalledFileEffectConstructionCapacity(
    capacity(zero), targetLimits.maxFileBytes, targetLimits.maxNodes, targetLimits.maxDepth));
  // The guarded request child drops the parser and document when the original
  // file read closes. Keep the complete simultaneous peak, while the row's
  // immutable request uses the separate retained request envelope.
  const requestConstruction = checked(moon.clientProgramInstalledFileEffectConstructionCapacity(
    capacity(workspace), targetLimits.maxFileBytes, targetLimits.maxNodes, targetLimits.maxDepth));
  // Projection owns checked values, admitted wrappers and row/cell indexes;
  // the file decoder is separate. Replacement Bytes coexist with original
  // file backing. Write additionally copies replacement Bytes into its Buffer.
  const construction = Object.freeze({retained: zero,
    workspace: Object.freeze({...workspace, wire: 2n * bytes})});
  const inputLimits = installedRowEffectConstructionLimits({maxRows: targetLimits.maxRows});
  let footprintCapacity;
  if (bundle.writables.length > 1) {
    const geometry = declaredProjectMockFootprintConstructionGeometry(bundle.writables,
      targetLimits.maxRows, targetLimits.maxFileBytes);
    footprintCapacity = capacity(geometry.workspace);
  }
  return prepareInstalledPhysicalWritePlanRecipe({moon, operation, inputLimits,
    construction, physicalConstruction: decode, requestConstruction, targetReadOperation,
    ...(footprintCapacity === undefined ? {} : {footprintCapacity}),
    limits: Object.freeze({maxRequestBytes: targetLimits.maxFileBytes,
      maxRecoveryBytes: targetLimits.maxFileBytes, maxResponseBytes: targetLimits.maxResponseBytes,
      maxOutcomeBytes: targetLimits.maxResponseBytes, maxTransferBytes: 2 * targetLimits.maxFileBytes})});
}

// Only this actual factory result retains the physical file owner. A copied
// adapter, limits object or status shape cannot supply its cleanup receipts.
export function observeInstalledMockEffectResources(effect) {
  const original = installations.get(effect);
  if (original === undefined) fail('ForeignInstalledMockEffect');
  return original;
}

// Local physical use has no remote Credential. The private use identity below
// records the original current Account/Checkpoint decision; it grants nothing.
// The generic Row Effect still admits the same Preview and durable row claim
// before calling send, and persists the observed bytes before settlement.
function mockRowEffectDriver({bundle, original, targets, bindingCid, principalId,
  authorization, current, call, resources, file}) {
  const maximum = targetLimits.maxFileBytes, work = targetLimits.maxWork;
  const catalogue = original.catalogue, profile = targets[0].write;
  const changes = (value, target) => value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length > 0 &&
    Object.keys(value).every(name => (target.write.update_fields ?? target.write.writable_fields).includes(name));
  const requests = new WeakMap(), descriptions = new WeakMap(), grants = new WeakMap();
  const codec = createMockFileRowCodec({bundle, original, call});
  const {admit, observe} = codec;
  const retainedRuns = new WeakSet();
  // A plural member description adds ONE borrowed target link. The existing
  // same-Run control constructor admits its explicit logical allowance before
  // that field exists. This is not global inventory funding or authority.
  const targetDescriptionCapacity = targets.length === 1 ? undefined
    : checked(call('construction', 1n, 0n, 0n, 1n, 0n, 0n));
  function targetForRecord(record) {
    const target = targets.find(value => value.mapping.mappingCid === record?.mapping);
    if (target === undefined) fail('InvalidMockEffectRequest');
    return target;
  }
  function runCurrent(runOriginal) {
    current();
    if (runOriginal === null || typeof runOriginal !== 'object') fail('ForeignMockEffectRun');
    synchronous(resources.assertCurrent(runOriginal));
    retainedRuns.add(runOriginal);
  }
  function retainRun(runOriginal) {
    // Cleanup of a known original remains reachable after authority/currentness
    // changes. A previously unseen object still requires the nominal owner.
    if (runOriginal === null || typeof runOriginal !== 'object' ||
        !retainedRuns.has(runOriginal)) runCurrent(runOriginal);
    return runOriginal;
  }
  const resourceObservation = Object.freeze({
    limits(runOriginal) {runCurrent(runOriginal); return targetLimits;},
    statusFor(runOriginal) {return file.statusFor(retainRun(runOriginal));},
    closeFor(runOriginal) {return file.closeFor(retainRun(runOriginal));},
  });
  function memberCurrent(member) {
    current();
    if (member === null || typeof member !== 'object') fail('ForeignMockEffectMember');
    const target = targets.find(value => member.resource === value.write.resource &&
      member.kind === operationOf(value) && member.mapping?.mappingCid === value.mapping.mappingCid &&
      member.mapping?.mappingRef === value.mapping.mappingRef);
    if (target === undefined) fail('ForeignMockEffectMember');
    return target;
  }
  function description(value, runOriginal, target) {
    current();
    const original = descriptions.get(value);
    if (original === undefined || runOriginal !== undefined &&
        original.runOriginal !== runOriginal) fail('ForeignMockTargetDescription');
    if (target !== undefined && (original.target ?? targets[0]) !== target) fail('ForeignMockTargetDescription');
    runCurrent(original.runOriginal);
    return original;
  }
  function describe({member, runInvocationCid, dispatchRequestCid, runOriginal, controlConstruction}) {
    const target = memberCurrent(member);
    runCurrent(runOriginal);
    const limits = resources.limits(runOriginal);
    if (!closed(limits, Object.keys(targetLimits)) || Object.entries(targetLimits)
      .some(([name, maximum]) => !Number.isSafeInteger(limits[name]) || limits[name] < maximum)) {
      fail('InstalledMockEffectLimitsUnavailable');
    }
    if (!cid(runInvocationCid) || !cid(dispatchRequestCid)) fail('ForeignMockTargetDescription');
    const construct = () => {
      const value = Object.freeze({});
      descriptions.set(value, Object.freeze({runInvocationCid, dispatchRequestCid, runOriginal,
        ...(targets.length === 1 ? {} : {target})}));
      return value;
    };
    if (targetDescriptionCapacity === undefined) return construct();
    if (typeof controlConstruction !== 'function') fail('InstalledMockTargetConstructionUnavailable');
    return controlConstruction(undefined, construct, [], targetDescriptionCapacity);
  }
  function decisionCurrent(decision, kind, resource) {
    current();
    const facts = authorizationDispatchFacts(decision);
    if (facts?.principal !== principalId || facts.configurationCid !== authorization.configurationCid ||
        decision.action !== 'dispatch' || decision.tuple?.connection !== catalogue.connection ||
        decision.tuple?.resource !== resource ||
        decision.tuple?.operation !== (kind === 'read' ? 'read' : 'effect') ||
        decision.boundary !== (kind === 'read' ? 'acquisition' : 'effect_commit') ||
        (kind === 'write' && (decision.basis !== 'resumed' ||
          !cid(decision.checkpointCid) || !cid(decision.resolutionCid)))) {
      fail('MockTargetNotAuthorized');
    }
    assertAuthorizationAccountCurrent(decision);
    current();
  }
  function issue(kind, {operation, decision, resource, runInvocationCid,
    dispatchRequestCid, subjectCid, maxUses}) {
    if (!targets.some(target => target.write.resource === resource &&
        operation === (kind === 'read' ? target.write.observe_permission : target.write.permission)) ||
        !cid(runInvocationCid) ||
        !cid(dispatchRequestCid) || (kind === 'read' && maxUses !== 1) ||
        (kind === 'write' && (!cid(subjectCid) || decision?.subjectCid !== subjectCid))) {
      fail('MockTargetNotAuthorized');
    }
    decisionCurrent(decision, kind, resource);
    const proof = Object.freeze({});
    grants.set(proof, {operation, decision, runInvocationCid, dispatchRequestCid, subjectCid, used: false});
    return Object.freeze({proof});
  }
  function consume(kind, supplied, selected, target) {
    const grant = grants.get(supplied?.proof), original = description(selected, undefined, target);
    if (grant === undefined || grant.used ||
        grant.operation !== (kind === 'read' ? target.write.observe_permission : target.write.permission) ||
        grant.runInvocationCid !== original.runInvocationCid ||
        grant.dispatchRequestCid !== original.dispatchRequestCid ||
        grant.decision.tuple.resource !== target.write.resource ||
        typeof supplied.useId !== 'string' || Buffer.byteLength(supplied.useId) > 4096) {
      fail('ForeignMockTargetUse');
    }
    decisionCurrent(grant.decision, kind, target.write.resource);
    grant.used = true;
    return Object.freeze({grant,
      useCid: hash({kind: 'mock-file-' + kind, binding_cid: bindingCid,
        invocation_cid: grant.runInvocationCid, dispatch_request_cid: grant.dispatchRequestCid,
        subject_cid: grant.subjectCid ?? null, use_id: supplied.useId,
        configuration_cid: authorizationDispatchFacts(grant.decision).configurationCid,
        checkpoint_cid: grant.decision.checkpointCid ?? null,
        resolution_cid: grant.decision.resolutionCid ?? null})});
  }
  const useCurrent = (use, kind, target) => {
    if (use !== undefined) decisionCurrent(use.grant.decision, kind, target.write.resource);
  };
  function own(request, runOriginal) {
    current();
    const record = requests.get(request);
    if (record === undefined || runOriginal !== undefined &&
        record.runOriginal !== runOriginal) fail('ForeignMockEffectRequest');
    return record;
  }
  function requestFrom(record, runOriginal) {
    runCurrent(runOriginal);
    const target = targetForRecord(record), {write: spec, mapping, beforeFields} = target;
    const deleting = operationOf(target) === 'delete';
    if (!closed(record, deleting ? deleteRequestKeys : updateRequestKeys) ||
        record.binding !== bindingCid || record.mapping !== mapping.mappingCid ||
        typeof record.target !== 'string' || !record.target.isWellFormed() ||
        (!deleting && !changes(record.value, target)) || !cid(record.version) || !closed(record.before, beforeFields) ||
        record.before[spec.primary_identity] !== record.target || Buffer.byteLength(wire(record)) > maximum) {
      fail('InvalidMockEffectRequest');
    }
    const before = snapshot(record.before);
    const original = Object.freeze(deleting ? {...record, before} : {...record, value: snapshot(record.value), before});
    // This is the canonical wire already needed for the original request CID.
    // Retain it for SAME-child output geometry instead of serializing again.
    const retainedWire = wire(original);
    const request = Object.freeze({});
    requests.set(request, Object.freeze({record: original,
      cid: 'sha256:' + createHash('sha256').update(retainedWire).digest('hex'),
      runOriginal, retainedWire}));
    return request;
  }
  function readChild({member, selector, value, current: selected, authorizationForRow, signal,
    runOriginal}) {
    const target = memberCurrent(member), mapping = target.mapping;
    description(selected, runOriginal, target);
    runCurrent(runOriginal);
    let use, output;
    const child = file.readChild({signal, runOriginal,
      assertCurrent: () => {runCurrent(runOriginal); useCurrent(use, 'read', target);},
      async authorize() {use = consume('read', await authorizationForRow(), selected, target);},
      consume(bytes) {
        const document = admit(bytes, target), observed = observe(document, selector);
        const deleting = member.kind === 'delete';
        if (deleting) {
          if (value !== undefined) fail('InvalidMockEffectRequest');
        } else {
          checked(call('update', document.selected, observed.row, observed.versionCid, wire(value), work));
        }
        const request = requestFrom({binding: bindingCid, mapping: mapping.mappingCid,
          target: selector, ...(deleting ? {} : {value}), version: observed.versionCid, before: observed.before}, runOriginal);
        const original = requests.get(request);
        requests.set(request, Object.freeze({...original, observedAt: selected}));
        output = Object.freeze({request, requestCid: original.cid});
        return output;
      }});
    return Object.freeze({prepare: child.prepare, release: child.release, retry: child.retry, status: child.status,
      retainedOutputWire(value) {
        if (value !== output || output === undefined || child.status().pending !== false) {
          fail('ForeignMockEffectRequest');
        }
        return own(output.request, runOriginal).retainedWire;
      }});
  }
  async function retireChild(child, failed, primary) {
    let cleanup, cleanupFailed = false;
    try {
      const result = await child.release();
      if (result?.pending !== false || child.status().pending !== false) fail('MockFileCleanupPending');
    } catch (cause) {cleanup = cause; cleanupFailed = true;}
    if (cleanupFailed) throw Object.assign(new Error('MockFileCleanupPending',
      {cause: failed ? primary : cleanup}), {code: 'MockFileCleanupPending', cleanupPending: true,
      cleanupHandle: Object.freeze({status: child.status, retry: child.retry})});
    if (failed) throw primary;
  }
  const recover = ({durable, recorded, body, memberIndexes, runOriginal}) => {
    current();
    runCurrent(runOriginal);
    if (!Array.isArray(body?.effects)) fail('InvalidMockEffectRecovery');
    const selected = memberIndexes ?? body.effects.map((_, index) => index);
    if (!Array.isArray(durable?.connectorRecovery) || !Array.isArray(recorded?.members) ||
        body.effects.length > targetLimits.maxEffects || !Array.isArray(selected) ||
        selected.length > targetLimits.maxEffects) {
      fail('InvalidMockEffectRecovery');
    }
    const restored = [], currents = [];
    let previous = -1;
    for (const index of selected) {
      if (!Number.isSafeInteger(index) || index <= previous || index >= body.effects.length) {
        fail('InvalidMockEffectRecovery');
      }
      previous = index;
      const member = body.effects[index];
      if (member.effect_kind !== 'update' && member.effect_kind !== 'delete') fail('InvalidMockEffectRecovery');
      const target = targetForRecord({mapping: member.resolved_mapping_contract_cid});
      const entries = durable.connectorRecovery.filter(entry => entry.memberIndex === index);
      if (operationOf(target) !== member.effect_kind || entries.length !== 1 || entries[0].kind !== recoveryKind(member.effect_kind) ||
          typeof entries[0].wire !== 'string' || Buffer.byteLength(entries[0].wire) > maximum) {
        fail('InvalidMockEffectRecovery');
      }
      const data = JSON.parse(entries[0].wire);
      if (!closed(data, ['binding', 'requests']) || data.binding !== bindingCid ||
          hash(data) !== entries[0].observationCid || !Array.isArray(data.requests) ||
          data.requests.length > targetLimits.maxRows ||
          data.requests.length !== body.effects[index]?.changes.length) {
        fail('InvalidMockEffectRecovery');
      }
      const requests = data.requests.map(record => {
        if (record?.mapping !== target.mapping.mappingCid) fail('InvalidMockEffectRecovery');
        return requestFrom(record, runOriginal);
      });
      // The common owner separately matches every rebuilt CID/target/value to
      // its original sealed Preview and durable row claim; this is DATA only.
      restored.push(requests);
      currents.push(undefined);
    }
    return {requests: restored, currents};
  };
  const firstKind = operationOf(targets[0]);
  const supportedKinds = targets.every(target => operationOf(target) === firstKind)
    ? firstKind === 'delete' ? deleteKinds : updateKinds : guardedKinds;
  const driver = Object.freeze({
    kinds: supportedKinds, targetRead: Object.freeze({operation: profile.observe_permission}),
    writeOperation: member => memberCurrent(member).write.permission, describe,
    prepareRequest() {fail('MockOriginalTargetObservationRequired');},
    prepareRequestChild: readChild,
    requestFacts(request) {const {record} = own(request); return {value: record.value, target: record.target};},
    requestCid: request => own(request).cid,
    recheckRequests({member, entries, current: selected, runOriginal}) {
      const target = memberCurrent(member);description(selected, runOriginal, target);runCurrent(runOriginal);
      for (const entry of entries) {
        if (targetForRecord(own(entry.request, runOriginal).record) !== target) fail('ForeignMockEffectRequest');
      }
    },
    async observeTargets({member, entries, current: selected, authorizationForRow, signal, runOriginal, ownedReadChild}) {
      const target = memberCurrent(member);description(selected, runOriginal, target);runCurrent(runOriginal);
      const result = [];
      for (const [index, entry] of entries.entries()) {
        const original = own(entry.request, runOriginal), {record} = original;
        if (targetForRecord(record) !== target) fail('ForeignMockEffectRequest');
        if (original.observedAt === selected) {
          result.push({identity: record.target, versionCid: record.version, before: record.before});
          continue;
        }
        let use, primary, observed, retainedWire, failed = false;
        const constructChild = () => {
          const child = file.readChild({signal, runOriginal,
          assertCurrent: () => {runCurrent(runOriginal); useCurrent(use, 'read', target);},
          async authorize() {use = consume('read', await authorizationForRow(index), selected, target);},
          consume(bytes) {const value = observe(admit(bytes, target), record.target);
            // Reuse the already emitted native before wire. Only the two
            // original scalar fields need their ordinary JSON string quoting.
            retainedWire = '{"before":' + value.beforeWire + ',"identity":' + wire(record.target) +
              ',"versionCid":' + wire(value.versionCid) + '}';
            return Object.freeze({identity: record.target, versionCid: value.versionCid, before: value.before});}});
          return Object.freeze({status: child.status, release: child.release, retry: child.retry,
            retainedOutputWire(value) {
              if (value !== observed || failed || observed === undefined || child.status().pending !== false) {
                fail('ForeignMockTargetObservation');
              }
              return retainedWire;
            },
            async prepare() {
              try {observed = await child.prepare();} catch (cause) {primary = cause; failed = true;}
              // The detached before/version DATA cannot retain the file's
              // parser. Observe its real close ACK before this window ends.
              await retireChild(child, failed, primary);
              return observed;
            }});
        };
        observed = ownedReadChild === undefined ? await constructChild().prepare()
          : await ownedReadChild(constructChild, index);
        result.push(observed);
      }
      return result;
    },
    footprint({member, entries}) {
      const target = memberCurrent(member);
      if (bundle.writables.length === 1) return {providerNamespace: 'local-mock-file',
        resourceKind: target.write.resource, boundaryCid: bindingCid};
      const selectors = entries.map(entry => {
        const {record} = own(entry.request);
        if (targetForRecord(record) !== target) fail('ForeignMockEffectRequest');
        return record.target;
      });
      return mockFileRowFootprint({bindingCid, target, selectors});
    },
    recoveryEntry({member, entries}) {
      const data = {binding: bindingCid, requests: entries.map(entry => own(entry.request).record)};
      const body = wire(data);
      if (Buffer.byteLength(body) > maximum) fail('MockEffectRecoveryLimit');
      return {kind: recoveryKind(member.kind), observationCid: hash(data), wire: body};
    },
    recoverRequests: recover, recoverMemberRequests: recover,
    async send({member, request, current: selected, authorization: supplied, signal, runOriginal, physicalOperation}) {
      const target = memberCurrent(member);description(selected, runOriginal, target);runCurrent(runOriginal);
      const {record, cid: requestCid} = own(request, runOriginal);
      if (targetForRecord(record) !== target) fail('ForeignMockEffectRequest');
      let use, primary, failed = false;
      const child = file.updateChild({signal, runOriginal,
        assertCurrent: () => {runCurrent(runOriginal); useCurrent(use, 'write', target);},
        authorize() {use = consume('write', supplied, selected, target);},
        replace(bytes) {
          return codec.replace(member.kind, bytes, target, record, physicalOperation);
        }});
      try {
        physicalOperation?.retainPhysicalChild(child);
        await child.prepare();
      } catch (cause) {primary = cause; failed = true;}
      await retireChild(child, failed, primary);
      current();
      return Object.freeze({observation: Object.freeze({useCid: use.useCid, statusCode: 200,
        body: Buffer.from(wire({request_cid: requestCid, target: record.target, action: responseAction(member.kind)}))})});
    },
    project({request, observation}) {
      const {record, cid: requestCid} = own(request);
      const action = responseAction(operationOf(targetForRecord(record)));
      if (!cid(observation?.useCid) || observation.statusCode !== 200 ||
          !(observation.body instanceof Uint8Array) ||
          observation.body.length > targetLimits.maxResponseBytes) {
        return {kind: 'unknown'};
      }
      let response;
      try {response = JSON.parse(Buffer.from(observation.body).toString('utf8'));}
      catch {return {kind: 'unknown'};}
      if (!closed(response, ['request_cid', 'target', 'action']) ||
          response.request_cid !== requestCid || response.target !== record.target || response.action !== action) {
        return {kind: 'unknown'};
      }
      // The private physical receipt distinguishes DELETE, while the admitted
      // applied outcome's optional action describes only create/update.
      return {kind: 'typed-success-response', outcome: {state: 'applied',
        ...(action === 'updated' ? {action} : {}), result: {id: record.target}}};
    },
  });
  const site = Object.freeze({issueReadGrant: options => issue('read', options),
    issueEffectGrant: options => issue('write', options), status: file.status, close: file.close});
  return {driver, site, resourceObservation};
}
