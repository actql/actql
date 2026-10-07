// Compose independently published installation facts without turning either
// adapter's authority into the other's. Each input is admitted on its own;
// shared declarations are retained once only when their bodies are identical.
import {canonicalJson, contentCid} from './local-account-config.mjs';

const sections = Object.freeze([
  'command_contracts', 'connector_capabilities', 'connector_catalogs',
  'contract_registry', 'mapping_contracts', 'model_task_contracts',
  'schema_snapshots', 'source_views',
]);
const maxEnvironmentBytes = 16 * 1024 * 1024;

const refuse = cause => {
  throw Object.assign(new TypeError('InstalledCheckEnvironmentConflict',
    {cause}), {code: 'InstalledCheckEnvironmentConflict'});
};

function admittedDocument(moon, wire) {
  if (typeof wire !== 'string' ||
      Buffer.byteLength(wire, 'utf8') > maxEnvironmentBytes) {
    refuse('EnvironmentSize');
  }
  let document;
  try { document = JSON.parse(wire); }
  catch (error) { refuse(error); }
  if (document === null || typeof document !== 'object' ||
      Array.isArray(document) || wire !== canonicalJson(document)) {
    refuse('EnvironmentEncoding');
  }
  const {evidence_bundle_cid: evidenceCid, ...body} = document;
  if (evidenceCid !== contentCid(body) ||
      moon.clientProgramCheckEnvironment(wire, evidenceCid,
        false, false, true, false, false, false, false) === undefined) {
    refuse('EnvironmentAdmission');
  }
  return body;
}

function mergeMembers(left, right) {
  const members = new Map();
  // Both complete inputs were independently admitted. Coalesce only the
  // exact same member appearing in both publications, never a selector with
  // another body or a repeated member within one input.
  for (const member of [...left, ...right]) {
    const body = canonicalJson(member);
    members.set(body, member);
  }
  return [...members.values()].sort((a, b) => {
    const first = contentCid(a);
    const second = contentCid(b);
    return first < second ? -1 : first > second ? 1 : 0;
  });
}

function rejectConflictingSelectors(members, selector) {
  const seen = new Map();
  for (const member of members) {
    const key = selector(member);
    if (key === undefined) continue;
    const body = canonicalJson(member);
    if (seen.has(key) && seen.get(key) !== body) {
      refuse('ConflictingSelector');
    }
    seen.set(key, body);
  }
}

function mergeManifest(left, right) {
  if (left === undefined) return right;
  if (right === undefined) return left;
  if (left.version !== right.version ||
      !Array.isArray(left.connectors) ||
      !Array.isArray(right.connectors)) {
    refuse('ConnectorManifest');
  }
  rejectConflictingSelectors([...left.connectors, ...right.connectors],
    value => value.connector_id);
  return {version: left.version,
    connectors: mergeMembers(left.connectors, right.connectors)};
}

// The Host passes the resulting wire to its ordinary MoonBit checker and
// Checkpoint owner. This is not a union of read and commit permissions.
export function composeInstalledCheckEnvironment(moon, baseWire,
  sourceWire, effectWire) {
  const base = admittedDocument(moon, baseWire);
  const source = sourceWire === undefined ? undefined : admittedDocument(moon, sourceWire);
  const effect = effectWire === undefined ? undefined : admittedDocument(moon, effectWire);
  const allowedKeys = new Set([...Object.keys(base),
    'connector_manifest']);
  // Adapter publications extend this Host's base facts. Their number never
  // grants permission to replace its policy, version or supported sections.
  for (const member of [source, effect]) {
    if (member === undefined) continue;
    if (member.version !== base.version ||
        canonicalJson(member.host_policy_profile) !==
          canonicalJson(base.host_policy_profile) ||
        Object.keys(member).some(key => !allowedKeys.has(key)) ||
        sections.some(section => !Array.isArray(member[section]))) {
      refuse('EnvironmentBase');
    }
  }
  if (source === undefined && effect === undefined) return baseWire;
  if (source === undefined) return effectWire;
  if (effect === undefined) return sourceWire;
  rejectConflictingSelectors([...source.connector_catalogs,
    ...effect.connector_catalogs], value => value.connector_id);
  rejectConflictingSelectors([...source.source_views,
    ...effect.source_views], value => value.source_ref);
  rejectConflictingSelectors([...source.command_contracts,
    ...effect.command_contracts], value => value.command_ref);
  rejectConflictingSelectors([...source.mapping_contracts,
    ...effect.mapping_contracts], value => value.mapping_ref);
  for (const section of ['schema_snapshots', 'connector_capabilities']) {
    rejectConflictingSelectors([...source[section], ...effect[section]],
      value => value.source_ref === undefined ? undefined :
        `${value.source_ref}\0${value.read_mode}`);
  }
  const body = {...base};
  for (const section of sections) {
    body[section] = mergeMembers(source[section], effect[section]);
  }
  const manifest = mergeManifest(source.connector_manifest,
    effect.connector_manifest);
  if (manifest !== undefined) body.connector_manifest = manifest;
  const wire = canonicalJson({...body, evidence_bundle_cid:
    contentCid(body)});
  admittedDocument(moon, wire);
  return wire;
}

// A matching static declaration does not establish that two installed roles
// address the same physical Site or principal. Compare adapter-issued,
// non-secret bindings before either role can perform provider I/O.
export function verifyInstalledConnectorBindings(source, effect) {
  if (source === undefined || effect === undefined) return;
  const sourceIds = new Set(JSON.parse(source.environmentWire)
    .connector_catalogs.map(catalog => catalog.connector_id));
  const effectIds = new Set(JSON.parse(effect.environmentWire)
    .connector_catalogs.map(catalog => catalog.connector_id));
  const shared = [...sourceIds].filter(id => effectIds.has(id));
  if (shared.length === 0) return;
  function bindings(adapter, ids) {
    const result = new Map();
    for (const binding of adapter.connectorBindings ?? []) {
      if (typeof binding?.connectorId !== 'string' ||
          !ids.has(binding.connectorId) ||
          typeof binding.bindingCid !== 'string' ||
          !/^sha256:[0-9a-f]{64}$/u.test(binding.bindingCid) ||
          result.has(binding.connectorId)) refuse('ConnectorBinding');
      result.set(binding.connectorId, binding.bindingCid);
    }
    return result;
  }
  const sources = bindings(source, sourceIds);
  const effects = bindings(effect, effectIds);
  for (const id of shared) {
    if (sources.get(id) === undefined ||
        sources.get(id) !== effects.get(id)) {
      refuse('ConnectorBinding');
    }
  }
}
