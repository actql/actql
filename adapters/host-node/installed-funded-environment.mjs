// One installed Source material owns every Environment construction and every
// borrowed admitted original. This is not a wire/CID admission cache.
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {installedSourceEnvironmentConstructionReader, isInstalledSourceInitializationRetired} from './installed-host-services.mjs';
import {composeAdmittedCheckEnvironmentOriginals} from './installed-check-environment.mjs';
import {admitInstalledCalendar} from './installed-calendar.mjs';
import {installedEnvironmentParseConstructionGeometry,
  installedEnvironmentDocumentConstructionStages,
  installedEnvironmentCompositionConstructionGeometry} from './installed-check-environment-construction.mjs';

const owners = new WeakMap(), originals = new WeakMap();
const sections = Object.freeze(['command_contracts', 'connector_capabilities', 'connector_catalogs',
  'contract_registry', 'mapping_contracts', 'model_task_contracts', 'schema_snapshots', 'source_views']);
const fail = code => {throw Object.assign(new TypeError(code), {code});};
// Fused into the already-funded parse/freeze traversal, not another read or
// parse to discover a budget. The census is private immutable constructor DATA.
function freezeDocument(document, wire) {
  const counts = {bytes: Buffer.byteLength(wire), nodes: 0, depth: 0, fields: 0,
    objects: 0, arrays: 0, rootFields: 0, maxFields: 0, keyUtf16Units: 0, valueUtf16Units: 0,
    maxKeyUtf16Units: 0, members: 0, snapshots: 0, catalogs: 0, manifestEntries: 0};
  function visit(value, depth) {
    counts.nodes++;
    counts.depth = Math.max(counts.depth, depth);
    if (typeof value === 'string') counts.valueUtf16Units += value.length;
    if (value === null || typeof value !== 'object') return;
    if (Array.isArray(value)) {
      counts.arrays++;
      for (const child of value) visit(child, depth + 1);
    } else {
      counts.objects++;
      const keys = Object.keys(value);
      if (depth === 1) counts.rootFields = keys.length;
      counts.fields += keys.length; counts.nodes += keys.length;
      counts.maxFields = Math.max(counts.maxFields, keys.length);
      for (const key of keys) {
        counts.keyUtf16Units += key.length;
        counts.maxKeyUtf16Units = Math.max(counts.maxKeyUtf16Units, key.length);
        visit(value[key], depth + 1);
      }
    }
    Object.freeze(value);
  }
  visit(document, 1);
  for (const section of sections) if (Array.isArray(document?.[section])) counts.members += document[section].length;
  counts.snapshots = Array.isArray(document?.schema_snapshots) ? document.schema_snapshots.length : 0;
  counts.catalogs = Array.isArray(document?.connector_catalogs) ? document.connector_catalogs.length : 0;
  counts.manifestEntries = Array.isArray(document?.connector_manifest?.connectors) ? document.connector_manifest.connectors.length : 0;
  return Object.freeze({document, counts: Object.freeze(counts)});
}

function mergedCounts(base, source, effect, wire, body) {
  // A merge only borrows member trees. Summed original censuses conservatively
  // cover deduplication and the new shallow envelope without traversing them.
  const result = {bytes: Buffer.byteLength(wire), nodes: 4, depth: 1, fields: 1,
    objects: 1, arrays: 0, rootFields: Object.keys(body).length + 1, maxFields: 0,
    keyUtf16Units: 'evidence_bundle_cid'.length, maxKeyUtf16Units: 'evidence_bundle_cid'.length,
    members: 0, snapshots: 0, catalogs: 0, manifestEntries: 0};
  for (const record of [base, source, effect]) if (record !== undefined) {
    const value = record.counts;
    for (const name of ['nodes', 'fields', 'objects', 'arrays', 'keyUtf16Units']) result[name] += value[name];
    result.depth = Math.max(result.depth, value.depth + 1);
    result.maxFields = Math.max(result.maxFields, value.maxFields);
    result.maxKeyUtf16Units = Math.max(result.maxKeyUtf16Units, value.maxKeyUtf16Units);
  }
  result.maxFields = Math.max(result.maxFields, result.rootFields);
  for (const section of sections) result.members += body[section].length;
  result.snapshots = body.schema_snapshots.length;result.catalogs = body.connector_catalogs.length;
  result.manifestEntries = body.connector_manifest?.connectors.length ?? 0;
  return Object.freeze(result);
}

function sealComposedBody(body) {
  for (const section of sections) Object.freeze(body[section]);
  if (body.connector_manifest !== undefined) {
    Object.freeze(body.connector_manifest.connectors);Object.freeze(body.connector_manifest);
  }
  return Object.freeze(body);
}

// Bound synchronously while the nominal reader is first issued, before any
// provider receives it. This capability remains only in the existing owner
// index; it is never returned through the provider-facing reader.
export function bindInstalledEnvironmentConstruction(services, reader, begin) {
  let owner = owners.get(services);
  if (owner === undefined) {
    owner = {busy: false, failed: false, cause: undefined, base: undefined}; owners.set(services, owner);
  }
  if (owner.reader !== undefined || typeof begin !== 'function') fail('ForeignInstalledEnvironmentOwner');
  owner.reader = reader; owner.begin = begin;
  return (moon, value, document, body) => retainInstalledEnvironmentNativeOriginal(services, moon, value, document, body);
}

// Only the fixed original Source Environment constructor registers this DATA.
// Its real native body and census were reserved before construction; equality
// of a wire/CID or a copied DTO cannot register or recover this association.
function retainInstalledEnvironmentNativeOriginal(services, moon, value, document, body) {
  const owner = owners.get(services);
  if (owner?.reader === undefined || originals.has(value) || !Object.isFrozen(value)) {
    fail('ForeignInstalledEnvironmentOriginal');
  }
  const {counts} = freezeDocument(document, value.wire);
  Object.freeze(body);
  originals.set(value, {services, moon, reader: owner.reader, counts,
    native: Object.freeze({wire: value.wire, evidenceCid: value.evidenceCid, body}), admittedOriginal: undefined});
  (owner.nativeOriginals ??= new Set()).add(value);
}

export function composeInstalledSourceEnvironment(services, moon, baseInput, sourceInput, effectInput) {
  return composeEnvironment(services, moon, baseInput, sourceInput, effectInput);
}

// Admit this exact retained member wire on the same existing Source material.
// Selector namespace construction needs each original Environment, not another
// equal merge or an unfunded compatibility check. No wire/CID cache is added.
export function readInstalledSourceEnvironment(services, moon, wire) {
  return composeEnvironment(services, moon, undefined, wire, undefined, undefined, true);
}

// The final Host checker consumes exact DATA text (including decomposed public
// Task text). Core performs complete canonical/member validation. Every native
// constructor below borrows its real original from the same funded parse.
export function readInstalledHostEnvironment(services, moon, wire,
  {textTime, calendar, calendarArtifact, numericProfileCid, graphLawCid}) {
  const reader = installedSourceEnvironmentConstructionReader(services, moon);
  const owner = owners.get(services);
  if (owner === undefined || owner.failed || owner.busy || owner.reader !== reader) {
    fail('ForeignInstalledEnvironmentOwner');
  }
  owner.busy = true;
  try {
    const construct = (capacity, project) => reader.prepareNativeInput(Object.freeze({capacity, project}));
    const parsed = construct(() => {
      const {retained, workspace} = installedEnvironmentParseConstructionGeometry(wire);
      return checked(moon.clientProgramInstalledSourceConstructionCapacity(
        retained.nodes, retained.text, retained.wire, workspace.nodes, workspace.text, workspace.wire));
    }, () => freezeDocument(JSON.parse(wire), wire));
    const counts = parsed.counts, evidenceCid = parsed.document.evidence_bundle_cid;
    const raw = construct(() => moon.clientProgramCheckEnvironmentWireConstructionCapacity(
      counts.bytes, counts.nodes, counts.depth, counts.fields, counts.objects, counts.arrays,
      counts.rootFields, counts.maxFields, counts.keyUtf16Units, counts.maxKeyUtf16Units,
      counts.members, counts.snapshots, counts.catalogs, counts.manifestEntries), () => {
        const value = moon.clientProgramReadCheckEnvironmentWire(wire, evidenceCid);
        if (value === undefined) fail('InstalledCheckEnvironmentConflict');
        return value;
      });
    // The original raw reader validated the complete SAME document. A mismatched
    // empty/populated selection refuses through its distinct quantity/bridge.
    const populated = parsed.document.model_task_contracts.length > 0;
    const quote = populated ? moon.clientProgramCheckEnvironmentModelFromWireConstructionCapacity
      : moon.clientProgramCheckEnvironmentFromWireConstructionCapacity;
    const admit = populated ? moon.clientProgramCheckEnvironmentModelFromWireWithGraphProfile
      : moon.clientProgramCheckEnvironmentFromWireWithGraphProfile;
    const base = construct(() => Reflect.apply(quote, moon, [raw]), () => {
      const value = Reflect.apply(admit, moon, [raw,
        textTime, true, true, true, true, calendar, false, numericProfileCid, graphLawCid]);
      if (value === undefined) fail('InstalledCheckEnvironmentConflict');
      return value;
    });
    // Keep the actual selected checker with the same funded native original
    // before using it to publish the Environment.
    const admitted = admitInstalledCalendar(moon, base, calendarArtifact, construct, counts.maxFields);
    // This exact raw original and checker remain retained by the parent. No
    // independently reconstructed DTO becomes a publication matcher here.
    return construct(() => checked(moon.clientProgramInstalledSourceConstructionCapacity(
      BigInt(counts.rootFields + 12), 0n, 0n, 0n, 0n, 0n)), () => {
        const {evidence_bundle_cid: ignored, ...body} = parsed.document;
        void ignored;
        const value = Object.freeze({runtime: moon, admitted, raw, wire, evidenceCid,
          body: Object.freeze(body)});
        originals.set(value, {services, moon, reader, counts, raw});
        return value;
      });
  } catch (cause) {owner.failed = true; owner.cause = cause; throw cause;}
  finally {owner.busy = false;}
}

// Completion adopts the SAME already-held native/Core original. The existing
// Core publication matcher is a nominal join, not a CID/Boolean authority.
// A copied DTO, changed wire or independently constructed final Environment
// cannot avoid its own construction/admission quantity through this entrance.
export function assertInstalledEnvironmentPublicationOriginal(services, moon, value, prepared, wire) {
  const reader = installedSourceEnvironmentConstructionReader(services, moon);
  const record = originals.get(value);
  if (record === undefined || record.native !== undefined || record.retired === true ||
      record.services !== services || record.moon !== moon || record.reader !== reader ||
      value.wire !== wire || typeof moon.clientProgramPublicSourceEnvironmentMatches !== 'function' ||
      moon.clientProgramPublicSourceEnvironmentMatches(prepared, value.admitted) !== true) {
    fail('ForeignInstalledEnvironmentOriginal');
  }
}

// Only these two Common inventory folds own a replaceable local prefix. Their
// synchronous acceptance checks precede its retirement; base/member originals
// and normal escaped composition results retain their original custody.
export function composeInstalledInventoryEnvironment(services, moon, baseInput, sourceInput, effectInput, accept) {
  return composeEnvironment(services, moon, baseInput, sourceInput, effectInput, accept);
}

function composeEnvironment(services, moon, baseInput, sourceInput, effectInput, accept, readOnly = false) {
  if (services === null || typeof services !== 'object') fail('ForeignInstalledHostServices');
  let owner = owners.get(services);
  if (owner === undefined) {
    owner = {busy: false, failed: false, cause: undefined, base: undefined}; owners.set(services, owner);
  }
  if (owner.failed) throw owner.cause;
  if (owner.busy) fail('InstalledEnvironmentConstructionReentry');
  owner.busy = true;
  try {
    const reader = installedSourceEnvironmentConstructionReader(services, moon);
    if (owner.reader !== reader) fail('ForeignInstalledEnvironmentOwner');
    const current = () => {
      if (installedSourceEnvironmentConstructionReader(services, moon) !== reader) fail('ForeignInstalledEnvironmentOwner');
    };
    const construct = (capacity, project) => reader.prepareNativeInput(Object.freeze({capacity, project}));
    const js = (geometry, project) => construct(() => {
      const {retained, workspace} = geometry();
      return checked(moon.clientProgramInstalledSourceConstructionCapacity(
        retained.nodes, retained.text, retained.wire, workspace.nodes, workspace.text, workspace.wire));
    }, project);
    const borrow = value => {
      const record = originals.get(value);
      if (record === undefined || record.native !== undefined || record.services !== services || record.moon !== moon || record.reader !== reader || record.retired === true) {
        fail('ForeignInstalledEnvironmentOriginal');
      }
      if (accept === undefined && record.release !== undefined) record.escaped = true;
      current();return record;
    };
    const admit = (wire, evidenceCid, body, counts) => {
      const raw = construct(() => {
        const capacity = moon.clientProgramCheckEnvironmentWireConstructionCapacity(counts.bytes, counts.nodes,
          counts.depth, counts.fields, counts.objects, counts.arrays, counts.rootFields, counts.maxFields,
          counts.keyUtf16Units, counts.maxKeyUtf16Units, counts.members, counts.snapshots,
          counts.catalogs, counts.manifestEntries);
        if (capacity === undefined) fail('InstalledEnvironmentWireCapacityUnavailable');
        return capacity;
      }, () => {
        const value = moon.clientProgramReadCheckEnvironmentWire(wire, evidenceCid);
        if (value === undefined) fail('InstalledCheckEnvironmentConflict');return value;
      });
      // The index retains this exact raw original. Fund that coheld alias
      // separately before its first insertion; composing it with a provider
      // peak would incorrectly retain the checker's completed workspace.
      construct(() => checked(moon.clientProgramInstalledSourceConstructionCapacity(
        1n,0n,0n,0n,0n,0n)), () => raw);
      return construct(() => {
        const capacity = moon.clientProgramCheckEnvironmentFromWireConstructionCapacity(raw);
        if (capacity === undefined) fail('InstalledEnvironmentModelConstructionUnavailable');
        return capacity;
      }, () => {
        const admitted = moon.clientProgramCheckEnvironmentFromWire(raw, false, false, true, false, false, false, false);
        if (admitted === undefined) fail('InstalledCheckEnvironmentConflict');
        const value = Object.freeze({runtime: moon, body, wire, evidenceCid, admitted});
        originals.set(value, {services, moon, reader, counts, raw});return value;
      });
    };
    const input = value => {
      if (value === undefined) return undefined;
      if (typeof value !== 'string') {
        const original = originals.get(value);
        if (original?.native !== undefined) {
          if (original.services !== services || original.moon !== moon || original.reader !== reader) {
            fail('ForeignInstalledEnvironmentOriginal');
          }
          current();
          if (original.admittedOriginal === undefined) {
            const native = original.native;
            // Core's SAME real wire reader verifies canonical bytes, body CID
            // and every ordered/unused member before semantic admission. The
            // body is this actual writer's frozen output, not JSON.parse of
            // arbitrary numeric wire or a cached permission/current decision.
            original.admittedOriginal = admit(native.wire, native.evidenceCid, native.body, original.counts);
          }
          borrow(original.admittedOriginal);
          return original.admittedOriginal;
        }
        borrow(value);return value;
      }
      if (Buffer.byteLength(value) > 16 * 1024 * 1024) fail('InstalledCheckEnvironmentConflict');
      const parsed = js(() => installedEnvironmentParseConstructionGeometry(value),
        () => freezeDocument(JSON.parse(value), value));
      const stages = installedEnvironmentDocumentConstructionStages(parsed.document);
      const compared = js(() => stages.comparison, () => {
        const document = parsed.document;
        if (document === null || typeof document !== 'object' || Array.isArray(document) || value !== canonicalJson(document)) {
          fail('InstalledCheckEnvironmentConflict');
        }
        return Object.freeze({document});
      });
      const verified = js(() => stages.body, () => {
        const document = compared.document;
        const {evidence_bundle_cid: evidenceCid, ...body} = document;
        if (evidenceCid !== contentCid(body)) fail('InstalledCheckEnvironmentConflict');
        return Object.freeze({body: Object.freeze(body), evidenceCid});
      });
      return admit(value, verified.evidenceCid, verified.body, parsed.counts);
    };
    if (readOnly) {const value = input(sourceInput);current();return value;}
    let base;
    if (owner.base === undefined) {base = input(baseInput);if (base === undefined) fail('InstalledCheckEnvironmentConflict');owner.base = base;}
    else {
      base = owner.base;borrow(base);
      if (baseInput !== base && baseInput !== base.wire) fail('ForeignInstalledEnvironmentBase');
    }
    const source = input(sourceInput);
    const effect = effectInput === sourceInput ? source : input(effectInput);
    const baseRecord = borrow(base), sourceRecord = source === undefined ? undefined : borrow(source),
      effectRecord = effect === undefined ? undefined : borrow(effect);
    // Ordinary construction may run inside the same pending metadata load.
    // Only a retiring inventory prefix requires a quiescent range capture.
    const finish = accept === undefined ? undefined : owner.begin();
    const composed = js(() => installedEnvironmentCompositionConstructionGeometry(base.body, source?.body, effect?.body), () =>
      composeAdmittedCheckEnvironmentOriginals(base, source, effect, (wire, evidenceCid, body) => {
        sealComposedBody(body);
        return Object.freeze({wire, evidenceCid, body,
          counts: mergedCounts(baseRecord, sourceRecord, effectRecord, wire, body)});
      }));
    const result = originals.has(composed) ? composed :
      admit(composed.wire, composed.evidenceCid, composed.body, composed.counts);
    const record = borrow(result);
    if (accept !== undefined) {
      const release = finish();
      if (typeof accept !== 'function') fail('ForeignInstalledEnvironmentOwner');
      const accepted = accept(result);
      if (typeof accepted !== 'boolean') fail('InvalidInstalledEnvironmentAcceptance');
      current();
      // An existing original never becomes an inventory-owned prefix merely
      // by borrowing it. A fresh merge owns only its new shallow containers,
      // canonical wire and native admission, not the member trees it borrows.
      if (result !== source && result !== effect && result !== base) {record.release = release; record.escaped = accepted;}
      else {if (accepted) record.escaped = true; release();}
      // A one-sided manifest merge may borrow its old envelope, not only
      // member leaves. Keep that prior prefix until normal parent retirement.
      const borrowsPriorManifest = source?.body.connector_manifest !== undefined &&
        result.body.connector_manifest === source.body.connector_manifest;
      if (sourceRecord?.release !== undefined && sourceRecord.escaped !== true &&
          source !== result && !borrowsPriorManifest) {
        sourceRecord.release(); sourceRecord.release = undefined; sourceRecord.retired = true;
      }
    }
    current();return result;
  } catch (cause) {owner.failed = true;owner.cause = cause;throw cause;}
  finally {owner.busy = false;}
}

// The final Host selects profiles on this SAME admitted WireEnvironment. The
// earlier intermediate checker stays retained; no body is copied, credited
// back or reclassified as current authority. Changed wires and Calendar's
// distinct artifact constructor keep their independent complete route.
export function admitInstalledSourceFinalEnvironment(services, moon, value,
  {textTime, numericProfileCid, graphLawCid}) {
  const owner = owners.get(services), record = originals.get(value);
  const reader = installedSourceEnvironmentConstructionReader(services, moon);
  if (owner === undefined || owner.failed || owner.busy || owner.reader !== reader ||
      record === undefined || record.native !== undefined || record.retired === true ||
      record.services !== services || record.moon !== moon || record.reader !== reader ||
      record.raw === undefined || typeof textTime !== 'boolean' ||
      typeof numericProfileCid !== 'string' || typeof graphLawCid !== 'string') {
    fail('ForeignInstalledEnvironmentOriginal');
  }
  const quote = moon.clientProgramCheckEnvironmentFromWireConstructionCapacity;
  const admit = moon.clientProgramCheckEnvironmentFromWireWithGraphProfile;
  if (typeof quote !== 'function' || typeof admit !== 'function') {
    fail('InstalledFinalEnvironmentRuntimeUnavailable');
  }
  owner.busy = true;
  try {
    const current = () => {
      if (owners.get(services) !== owner || owner.reader !== reader ||
          originals.get(value) !== record || record.retired === true) {
        fail('ForeignInstalledEnvironmentOriginal');
      }
    };
    // Resource performs original currentness before/after these latched
    // synchronous callbacks. Do not reenter its public reader from inside
    // capacity/project; there check only our already captured nominal parts.
    const currentReader = () => {
      if (installedSourceEnvironmentConstructionReader(services, moon) !== reader) {
        fail('ForeignInstalledEnvironmentOriginal');
      }
      current();
    };
    currentReader();
    const result = reader.prepareNativeInput(Object.freeze({capacity() {
      current();
      const native = Reflect.apply(quote, moon, [record.raw]);
      if (native === undefined) fail('InstalledEnvironmentModelConstructionUnavailable');
      // Final DTO/index records, returned association and the selected numeric
      // profile wrapper borrow originals. They own no new body/text backing.
      const controls = checked(moon.clientProgramInstalledSourceConstructionCapacity(8n,0n,0n,0n,0n,0n));
      return checked(moon.clientProgramComposeInstalledSourceConstructionCapacity(controls,[native]));
    }, project() {
      current();
      const admitted = Reflect.apply(admit, moon, [record.raw,textTime,true,true,true,true,false,false,
        numericProfileCid,graphLawCid]);
      if (admitted === undefined) fail('InstalledCheckEnvironmentConflict');
      current();
      const result = Object.freeze({runtime:moon,body:value.body,wire:value.wire,
        evidenceCid:value.evidenceCid,admitted});
      originals.set(result,{services,moon,reader,counts:record.counts,raw:record.raw});
      return result;
    }}));
    currentReader();return result;
  } catch (cause) {owner.failed=true;owner.cause=cause;throw cause;}
  finally {owner.busy=false;}
}

// Only the existing Source retirement ACK authorizes dropping this retained
// construction state. Pending cleanup must keep both originals and failure.
export function releaseRetiredInstalledEnvironmentComposition(services) {
  if (!isInstalledSourceInitializationRetired(services)) fail('InstalledSourceRetirementPending');
  for (const value of owners.get(services)?.nativeOriginals ?? []) originals.delete(value);
  owners.delete(services);
}
