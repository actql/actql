// One installed Source material owns every Environment construction and every
// borrowed admitted original. This is not a wire/CID admission cache.
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {installedSourceEnvironmentConstructionReader, isInstalledSourceInitializationRetired} from './installed-host-services.mjs';
import {composeAdmittedCheckEnvironmentOriginals} from './installed-check-environment.mjs';
import {installedEnvironmentParseConstructionGeometry,
  installedEnvironmentDocumentConstructionGeometry,
  installedEnvironmentCompositionConstructionGeometry} from './installed-check-environment-construction.mjs';

const owners = new WeakMap(), originals = new WeakMap();
const sections = Object.freeze(['command_contracts', 'connector_capabilities', 'connector_catalogs',
  'contract_registry', 'mapping_contracts', 'model_task_contracts', 'schema_snapshots', 'source_views']);
const fail = code => {throw Object.assign(new TypeError(code), {code});};
// Fused into the already-funded parse/freeze traversal, not another read or
// parse to discover a budget. The census is private immutable constructor DATA.
function freezeDocument(document, wire) {
  const counts = {bytes: Buffer.byteLength(wire), nodes: 0, depth: 0, fields: 0,
    objects: 0, arrays: 0, rootFields: 0, maxFields: 0, keyUtf16Units: 0,
    maxKeyUtf16Units: 0, members: 0, snapshots: 0, catalogs: 0, manifestEntries: 0};
  function visit(value, depth) {
    counts.nodes++;
    counts.depth = Math.max(counts.depth, depth);
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

export function composeInstalledSourceEnvironment(services, moon, baseInput, sourceInput, effectInput) {
  if (services === null || typeof services !== 'object') fail('ForeignInstalledHostServices');
  let owner = owners.get(services);
  if (owner === undefined) {owner = {busy: false, failed: false, cause: undefined, base: undefined};owners.set(services, owner);}
  if (owner.failed) throw owner.cause;
  if (owner.busy) fail('InstalledEnvironmentConstructionReentry');
  owner.busy = true;
  try {
    const reader = installedSourceEnvironmentConstructionReader(services, moon);
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
      if (record === undefined || record.services !== services || record.moon !== moon || record.reader !== reader) {
        fail('ForeignInstalledEnvironmentOriginal');
      }
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
      return construct(() => {
        const capacity = moon.clientProgramCheckEnvironmentFromWireConstructionCapacity(raw);
        if (capacity === undefined) fail('InstalledEnvironmentModelConstructionUnavailable');return capacity;
      }, () => {
        const admitted = moon.clientProgramCheckEnvironmentFromWire(raw, false, false, true, false, false, false, false);
        if (admitted === undefined) fail('InstalledCheckEnvironmentConflict');
        const value = Object.freeze({runtime: moon, body, wire, evidenceCid, admitted});
        originals.set(value, {services, moon, reader, counts});return value;
      });
    };
    const input = value => {
      if (value === undefined) return undefined;
      if (typeof value !== 'string') {borrow(value);return value;}
      if (Buffer.byteLength(value) > 16 * 1024 * 1024) fail('InstalledCheckEnvironmentConflict');
      const parsed = js(() => installedEnvironmentParseConstructionGeometry(value),
        () => freezeDocument(JSON.parse(value), value));
      const verified = js(() => installedEnvironmentDocumentConstructionGeometry(parsed.document), () => {
        const document = parsed.document;
        if (document === null || typeof document !== 'object' || Array.isArray(document) || value !== canonicalJson(document)) {
          fail('InstalledCheckEnvironmentConflict');
        }
        const {evidence_bundle_cid: evidenceCid, ...body} = document;
        if (evidenceCid !== contentCid(body)) fail('InstalledCheckEnvironmentConflict');
        return Object.freeze({body: Object.freeze(body), evidenceCid});
      });
      return admit(value, verified.evidenceCid, verified.body, parsed.counts);
    };
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
    const composed = js(() => installedEnvironmentCompositionConstructionGeometry(base.body, source?.body, effect?.body), () =>
      composeAdmittedCheckEnvironmentOriginals(base, source, effect, (wire, evidenceCid, body) => {
        sealComposedBody(body);
        return Object.freeze({wire, evidenceCid, body,
          counts: mergedCounts(baseRecord, sourceRecord, effectRecord, wire, body)});
      }));
    if (originals.has(composed)) {borrow(composed);return composed;}
    const result = admit(composed.wire, composed.evidenceCid, composed.body, composed.counts);
    current();return result;
  } catch (cause) {owner.failed = true;owner.cause = cause;throw cause;}
  finally {owner.busy = false;}
}

// Only the existing Source retirement ACK authorizes dropping this retained
// construction state. Pending cleanup must keep both originals and failure.
export function releaseRetiredInstalledEnvironmentComposition(services) {
  if (!isInstalledSourceInitializationRetired(services)) fail('InstalledSourceRetirementPending');
  owners.delete(services);
}
