// The explicit Project Mock's real file UPDATE, through the existing Row
// Effect owner. No live Salesforce request/credential, hidden mirror, automatic
// approval, replacement Run or permission derived from a profile is supplied.
import {createHash} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {authorizationDispatchFacts, assertAuthorizationAccountCurrent}
  from '../host-common/authorization-gate.mjs';
import {retainInstalledRowEffectAdapter, installedRowEffectConstructionLimits} from '../host-node/installed-row-effect.mjs';
import {prepareInstalledPhysicalWritePlanRecipe} from '../host-node/installed-effect-plan.mjs';
import {installedUpdateTargets} from '../host-node/installed-effect-inventory.mjs';
import {createMockFileTarget} from '../host-node/mock-file-target.mjs';

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
});

export async function installPreparedProjectMockEffects({moon, mockPreparation,
  baseEnvironmentWire, authorizationFor, principalId, runtimeBundleCid, bindingCid,
  ledgerRoot, assertCurrent, effectResources, io}) {
  if (typeof mockPreparation?.originalsForRuntime !== 'function' ||
      typeof authorizationFor !== 'function' || typeof assertCurrent !== 'function' ||
      typeof principalId !== 'string' || !cid(runtimeBundleCid) || !cid(bindingCid)) {
    fail('InvalidInstalledMockEffect');
  }
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
  if (bundle.writable === undefined) fail('InstalledMockWritableTargetUnavailable');
  const {source: original, write: spec} = bundle.writable, catalogue = original.catalogue;
  const prepared = original.effectPrepared;
  if (typeof original.effectMember?.load !== 'function' ||
      prepared?.declaration !== original.declaration || prepared.environment === undefined) {
    fail('InstalledSourceInitializationUnavailable');
  }
  const mapping = prepared.mappings.find(value => value.resource === spec.resource);
  if (mapping === undefined || mapping.body !== spec.mappingWire) fail('InvalidInstalledMockEffect');
  const physical = original.physical.find(value => value.resource === spec.resource);
  if (physical === undefined || physical.declaration !== original.declaration) fail('InvalidInstalledMockEffect');
  function current() {
    const observed = assertCurrent();
    if (observed !== undefined) {
      if (observed instanceof Promise) void observed.catch(() => {});
      fail('InvalidMockFileCurrentFence');
    }
    if (mockPreparation.originalsForRuntime(moon) !== bundle) fail('ForeignInstalledMockPreparation');
  }
  current();
  const methods = Object.fromEntries(Object.entries(ports).map(([name, port]) => [name, moon?.[port]]));
  if (!Object.values(methods).every(value => typeof value === 'function')) {
    fail('InstalledMockTargetRuntimeUnavailable');
  }
  const call = (name, ...args) => Reflect.apply(methods[name], moon, args);
  const authorization = await authorizationFor(catalogue.connection);
  current();
  const {driver, site, resourceObservation} = mockRowEffectDriver({bundle, original, spec, physical, mapping, bindingCid,
    principalId, authorization, current, call, resources, io});
  try {
    const managedPlanRecipe = mockFileEffectPlanRecipe(moon, bundle, spec.permission, spec.observe_permission);
    const effect = await original.effectMember.load({moon,
      mappings: prepared.mappings,
      environmentWire: prepared.environment.wire, connectorId: catalogue.connectorId,
      connectorRegistration: catalogue.registration, connectorRevision: catalogue.revision,
      connection: catalogue.connection, site, authorization, runtimeBundleCid,
      bindingCid, ledgerRoot, driver, managedPlanRecipe, effectResources: resources,
      limits: {maxRows: targetLimits.maxRows}});
    current();
    const aliases = spec.aliases.map(name => Object.freeze({name,
      targetRef: mapping.target}));
    const installed = retainInstalledRowEffectAdapter(effect, Object.freeze({...effect,
      queryUpdateTargets: installedUpdateTargets(effect, aliases)}));
    installations.set(installed, resourceObservation);
    return installed;
  } catch (cause) {
    try {await site.close();} catch (cleanup) {
      throw Object.assign(new Error('InstalledMockEffectCleanupPending', {cause}),
        {code: 'InstalledMockEffectCleanupPending', cleanupPending: true,
          cleanupHandle: Object.freeze({status: site.status, retry: site.close}), cleanup});
    }
    throw cause;
  }
}

// One finite file operation window. Common supplies parser/control tariffs;
// only the actual declared projections and file/replacement buffers vary here.
// Returned request/response DATA has the existing JSON recipe and output guard.
function mockFileEffectPlanRecipe(moon, bundle, operation, targetReadOperation) {
  const bytes = BigInt(targetLimits.maxFileBytes), nodes = BigInt(targetLimits.maxNodes);
  const projections = BigInt(bundle.sources.reduce((sum, source) => sum + source.physical.length, 0));
  const workspace = Object.freeze({nodes: 4n * nodes * projections,
    text: bytes * projections, wire: bytes});
  const zero = Object.freeze({nodes: 0n, text: 0n, wire: 0n});
  const capacity = value => checked(moon.clientProgramInstalledSourceConstructionCapacity(
    0n, 0n, 0n, value.nodes, value.text, value.wire));
  const decode = checked(moon.clientProgramInstalledFileEffectConstructionCapacity(
    capacity(zero), targetLimits.maxFileBytes, targetLimits.maxNodes, targetLimits.maxDepth));
  const requestConstruction = checked(moon.clientProgramComposeInstalledSourceConstructionCapacity(
    capacity(workspace), [decode]));
  // Projection owns checked values, admitted wrappers and row/cell indexes;
  // the file decoder is separate. Replacement Bytes coexist with original
  // file backing. Write additionally copies replacement Bytes into its Buffer.
  const construction = Object.freeze({retained: zero,
    workspace: Object.freeze({...workspace, wire: 2n * bytes})});
  const inputLimits = installedRowEffectConstructionLimits({maxRows: targetLimits.maxRows});
  return prepareInstalledPhysicalWritePlanRecipe({moon, operation, inputLimits,
    construction, physicalConstruction: decode, requestConstruction, targetReadOperation,
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
function mockRowEffectDriver({bundle, original, spec, physical, mapping, bindingCid, principalId,
  authorization, current, call, resources, io}) {
  const maximum = targetLimits.maxFileBytes, work = targetLimits.maxWork;
  const catalogue = original.catalogue;
  const beforeFields = Object.keys(physical.schema);
  const changes = value => value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length > 0 && Object.keys(value).every(name => spec.writable_fields.includes(name));
  const requests = new WeakMap(), descriptions = new WeakMap(), grants = new WeakMap();
  const retainedRuns = new WeakSet();
  const file = createMockFileTarget({dataPath: bundle.dataPath,
    maxBytes: maximum, assertCurrent: current, ...(io === undefined ? {} : {io})});
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
    if (member.kind !== 'update' || member.resource !== spec.resource ||
        member.mapping.mappingCid !== mapping.mappingCid ||
        member.mapping.mappingRef !== mapping.mappingRef) fail('ForeignMockEffectMember');
  }
  function description(value, runOriginal) {
    current();
    const original = descriptions.get(value);
    if (original === undefined || runOriginal !== undefined &&
        original.runOriginal !== runOriginal) fail('ForeignMockTargetDescription');
    runCurrent(original.runOriginal);
    return original;
  }
  function describe({member, runInvocationCid, dispatchRequestCid, runOriginal}) {
    memberCurrent(member);
    runCurrent(runOriginal);
    const limits = resources.limits(runOriginal);
    if (!closed(limits, Object.keys(targetLimits)) || Object.entries(targetLimits)
      .some(([name, maximum]) => !Number.isSafeInteger(limits[name]) || limits[name] < maximum)) {
      fail('InstalledMockEffectLimitsUnavailable');
    }
    if (!cid(runInvocationCid) || !cid(dispatchRequestCid)) fail('ForeignMockTargetDescription');
    const value = Object.freeze({});
    descriptions.set(value, Object.freeze({runInvocationCid, dispatchRequestCid, runOriginal}));
    return value;
  }
  function decisionCurrent(decision, kind) {
    current();
    const facts = authorizationDispatchFacts(decision);
    if (facts?.principal !== principalId || facts.configurationCid !== authorization.configurationCid ||
        decision.action !== 'dispatch' || decision.tuple?.connection !== catalogue.connection ||
        decision.tuple?.resource !== spec.resource ||
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
    const expected = kind === 'read' ? spec.observe_permission : spec.permission;
    if (operation !== expected || resource !== spec.resource || !cid(runInvocationCid) ||
        !cid(dispatchRequestCid) || (kind === 'read' && maxUses !== 1) ||
        (kind === 'write' && (!cid(subjectCid) || decision?.subjectCid !== subjectCid))) {
      fail('MockTargetNotAuthorized');
    }
    decisionCurrent(decision, kind);
    const proof = Object.freeze({});
    grants.set(proof, {kind, decision, runInvocationCid, dispatchRequestCid, subjectCid, used: false});
    return Object.freeze({proof});
  }
  function consume(kind, supplied, selected) {
    const grant = grants.get(supplied?.proof), original = description(selected);
    if (grant === undefined || grant.kind !== kind || grant.used ||
        grant.runInvocationCid !== original.runInvocationCid ||
        grant.dispatchRequestCid !== original.dispatchRequestCid ||
        typeof supplied.useId !== 'string' || Buffer.byteLength(supplied.useId) > 4096) {
      fail('ForeignMockTargetUse');
    }
    decisionCurrent(grant.decision, kind);
    grant.used = true;
    return Object.freeze({grant,
      useCid: hash({kind: 'mock-file-' + kind, binding_cid: bindingCid,
        invocation_cid: grant.runInvocationCid, dispatch_request_cid: grant.dispatchRequestCid,
        subject_cid: grant.subjectCid ?? null, use_id: supplied.useId,
        configuration_cid: authorizationDispatchFacts(grant.decision).configurationCid,
        checkpoint_cid: grant.decision.checkpointCid ?? null,
        resolution_cid: grant.decision.resolutionCid ?? null})});
  }
  const useCurrent = use => {if (use !== undefined) decisionCurrent(use.grant.decision, use.grant.kind);};
  function admit(bytes) {
    const originalDocument = checked(call('admit', bytes, maximum,
      targetLimits.maxNodes, targetLimits.maxDepth, targetLimits.maxRows, work));
    const projections = new Map();
    for (const source of bundle.sources) for (const model of source.physical) {
      const writable = source === original && model === physical ? spec.writable_fields : model.writableFields;
      projections.set(model, checked(call('project', originalDocument, model.declaration,
        model.resource, model.itemsPath, model.keyPath, model.primaryIdentity, writable)));
    }
    const selected = projections.get(physical);
    if (selected === undefined) fail('InvalidInstalledMockEffect');
    return {originalDocument, projections, selected};
  }
  function observe(document, target) {
    const row = checked(call('observe', document.selected, original.declaration, target));
    const beforeWire = call('before', row), versionCid = call('version', row);
    if (typeof beforeWire !== 'string' || !cid(versionCid)) fail('InvalidMockTargetObservation');
    const before = snapshot(JSON.parse(beforeWire));
    return {row, before, versionCid};
  }
  function own(request, runOriginal) {
    current();
    const record = requests.get(request);
    if (record === undefined || runOriginal !== undefined &&
        record.runOriginal !== runOriginal) fail('ForeignMockEffectRequest');
    return record;
  }
  function requestFrom(record, runOriginal) {
    runCurrent(runOriginal);
    if (!closed(record, ['binding', 'mapping', 'target', 'value', 'version', 'before']) ||
        record.binding !== bindingCid || record.mapping !== mapping.mappingCid ||
        typeof record.target !== 'string' || !record.target.isWellFormed() ||
        !changes(record.value) || !cid(record.version) || !closed(record.before, beforeFields) ||
        record.before[spec.primary_identity] !== record.target || Buffer.byteLength(wire(record)) > maximum) {
      fail('InvalidMockEffectRequest');
    }
    const value = snapshot(record.value), before = snapshot(record.before);
    const original = Object.freeze({...record, value, before});
    const request = Object.freeze({});
    requests.set(request, Object.freeze({record: original, cid: hash(original), runOriginal}));
    return request;
  }
  function readChild({member, selector, value, current: selected, authorizationForRow, signal,
    runOriginal}) {
    memberCurrent(member);
    description(selected, runOriginal);
    runCurrent(runOriginal);
    let use;
    return file.readChild({signal, runOriginal,
      assertCurrent: () => {runCurrent(runOriginal); useCurrent(use);},
      async authorize() {use = consume('read', await authorizationForRow(), selected);},
      consume(bytes) {
        const document = admit(bytes), observed = observe(document, selector);
        // Validate the Mapping body with Common before sealing the request.
        checked(call('update', document.selected, observed.row, observed.versionCid, wire(value), work));
        const request = requestFrom({binding: bindingCid, mapping: mapping.mappingCid,
          target: selector, value, version: observed.versionCid, before: observed.before}, runOriginal);
        const original = requests.get(request);
        requests.set(request, Object.freeze({...original, observedAt: selected}));
        return Object.freeze({request, requestCid: original.cid});
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
      const entries = durable.connectorRecovery.filter(entry => entry.memberIndex === index);
      if (entries.length !== 1 || entries[0].kind !== 'mock-file-row-update' ||
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
      const requests = data.requests.map(record => requestFrom(record, runOriginal));
      // The common owner separately matches every rebuilt CID/target/value to
      // its original sealed Preview and durable row claim; this is DATA only.
      restored.push(requests);
      currents.push(undefined);
    }
    return {requests: restored, currents};
  };
  const driver = Object.freeze({
    kinds: Object.freeze(['update']), targetRead: Object.freeze({operation: spec.observe_permission}),
    writeOperation: () => spec.permission, describe,
    prepareRequest() {fail('MockOriginalTargetObservationRequired');},
    prepareRequestChild: readChild,
    requestFacts(request) {const {record} = own(request); return {value: record.value, target: record.target};},
    requestCid: request => own(request).cid,
    recheckRequests({member, entries, current: selected, runOriginal}) {
      memberCurrent(member); description(selected, runOriginal); runCurrent(runOriginal);
      for (const entry of entries) own(entry.request, runOriginal);
    },
    async observeTargets({member, entries, current: selected, authorizationForRow, signal, runOriginal, ownedReadChild}) {
      memberCurrent(member); description(selected, runOriginal); runCurrent(runOriginal);
      const result = [];
      for (const [index, entry] of entries.entries()) {
        const original = own(entry.request, runOriginal), {record} = original;
        if (original.observedAt === selected) {
          result.push({identity: record.target, versionCid: record.version, before: record.before});
          continue;
        }
        let use, primary, observed, failed = false;
        const constructChild = () => {
          const child = file.readChild({signal, runOriginal,
          assertCurrent: () => {runCurrent(runOriginal); useCurrent(use);},
          async authorize() {use = consume('read', await authorizationForRow(index), selected);},
          consume(bytes) {const value = observe(admit(bytes), record.target);
            return {identity: record.target, versionCid: value.versionCid, before: value.before};}});
          return Object.freeze({status: child.status, release: child.release, retry: child.retry,
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
    footprint: () => ({providerNamespace: 'local-mock-file', resourceKind: spec.resource, boundaryCid: bindingCid}),
    recoveryEntry({entries}) {
      const data = {binding: bindingCid, requests: entries.map(entry => own(entry.request).record)};
      const body = wire(data);
      if (Buffer.byteLength(body) > maximum) fail('MockEffectRecoveryLimit');
      if (Buffer.byteLength(body) > maximum) fail('MockEffectRecoveryLimit');
      return {kind: 'mock-file-row-update', observationCid: hash(data), wire: body};
    },
    recoverRequests: recover, recoverMemberRequests: recover,
    async send({member, request, current: selected, authorization: supplied, signal, runOriginal, physicalOperation}) {
      memberCurrent(member); description(selected, runOriginal); runCurrent(runOriginal);
      const {record, cid: requestCid} = own(request, runOriginal);
      let use, primary, failed = false;
      const child = file.updateChild({signal, runOriginal,
        assertCurrent: () => {runCurrent(runOriginal); useCurrent(use);},
        authorize() {use = consume('write', supplied, selected);},
        replace(bytes) {
          physicalOperation?.chargeBytes(BigInt(bytes.length));
          const document = admit(bytes), observed = observe(document, record.target);
          if (observed.versionCid !== record.version || wire(observed.before) !== wire(record.before)) {
            fail('MockTargetVersionConflict');
          }
          const replacement = checked(call('update', document.selected, observed.row, record.version, wire(record.value), work));
          physicalOperation?.chargeBytes(BigInt(replacement.length));
          return replacement;
        }});
      try {
        physicalOperation?.retainPhysicalChild(child);
        await child.prepare();
      } catch (cause) {primary = cause; failed = true;}
      await retireChild(child, failed, primary);
      current();
      return Object.freeze({observation: Object.freeze({useCid: use.useCid, statusCode: 200,
        body: Buffer.from(wire({request_cid: requestCid, target: record.target, action: 'updated'}))})});
    },
    project({request, observation}) {
      const {record, cid: requestCid} = own(request);
      if (!cid(observation?.useCid) || observation.statusCode !== 200 ||
          !(observation.body instanceof Uint8Array) ||
          observation.body.length > targetLimits.maxResponseBytes) {
        return {kind: 'unknown'};
      }
      let response;
      try {response = JSON.parse(Buffer.from(observation.body).toString('utf8'));}
      catch {return {kind: 'unknown'};}
      if (!closed(response, ['request_cid', 'target', 'action']) ||
          response.request_cid !== requestCid || response.target !== record.target || response.action !== 'updated') {
        return {kind: 'unknown'};
      }
      return {kind: 'typed-success-response', outcome: {state: 'applied', action: 'updated', result: {id: record.target}}};
    },
  });
  const site = Object.freeze({issueReadGrant: options => issue('read', options),
    issueEffectGrant: options => issue('write', options), status: file.status, close: file.close});
  return {driver, site, resourceObservation};
}
