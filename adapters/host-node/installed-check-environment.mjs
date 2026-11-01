// Compose independently published installation facts without turning either
// adapter's authority into the other's. Each distinct complete input is admitted;
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

// One same-call construction record, not a path/CID cache or an execution
// permission. External wires are checked before this shared admission; an
// internally composed body already owns its exact encoding and evidence CID.
function admitEnvironment(moon, wire, evidenceCid, body) {
  const admitted = moon.clientProgramCheckEnvironment(wire, evidenceCid,
    false, false, true, false, false, false, false);
  if (admitted === undefined) refuse('EnvironmentAdmission');
  return Object.freeze({runtime: moon, body, wire, evidenceCid, admitted});
}

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
  if (evidenceCid !== contentCid(body)) refuse('EnvironmentAdmission');
  return admitEnvironment(moon, wire, evidenceCid, body);
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
  const retained = [...members.values()];
  if (retained.length < 2) return retained;
  return retained.map(member => ({member, cid: contentCid(member)}))
    .sort((a, b) => a.cid < b.cid ? -1 : a.cid > b.cid ? 1 : 0)
    .map(({member}) => member);
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

// The original role inputs are immutable DATA. Exact complete wire equality
// makes the Source and Effect publication the same semantic check input; it
// says nothing about their independent Sites, bindings or permissions.
// The constructor quote consumes this SAME selection before parsing/checking.
export function installedCheckEnvironmentInputs(baseWire, sourceWire, effectWire) {
  return [baseWire, sourceWire,
    typeof sourceWire === 'string' && sourceWire === effectWire ? undefined : effectWire];
}

// The Host passes the resulting wire to its ordinary MoonBit checker and
// Checkpoint owner. This is not a union of read and commit permissions.
export function composeInstalledCheckEnvironment(moon, baseWire,
  sourceWire, effectWire) {
  return composeInstalledCheckEnvironmentOriginal(moon, baseWire, sourceWire, effectWire).wire;
}

// The normal Host retains this SAME constructor's original metadata. Wire
// consumers above keep their existing interface without another admission.
// A later checker with different policy/flags still checks the final input.
export function composeInstalledCheckEnvironmentOriginal(moon, baseWire,
  sourceWire, effectWire) {
  const [baseInput, sourceInput, effectInput] = installedCheckEnvironmentInputs(baseWire, sourceWire, effectWire);
  const baseOriginal = admittedDocument(moon, baseInput);
  const sourceOriginal = sourceInput === undefined ? undefined : admittedDocument(moon, sourceInput);
  const effectOriginal = effectInput === undefined ? undefined : admittedDocument(moon, effectInput);
  const base = baseOriginal.body, source = sourceOriginal?.body, effect = effectOriginal?.body;
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
  if (source === undefined && effect === undefined) return baseOriginal;
  if (source === undefined) return effectOriginal;
  if (effect === undefined) return sourceOriginal;
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
  const evidenceCid = contentCid(body);
  const wire = canonicalJson({...body, evidence_bundle_cid: evidenceCid});
  if (Buffer.byteLength(wire, 'utf8') > maxEnvironmentBytes) refuse('EnvironmentSize');
  return admitEnvironment(moon, wire, evidenceCid, body);
}

// A matching static declaration does not establish that two installed roles
// address the same physical Site or principal. Compare adapter-issued,
// non-secret bindings before either role can perform provider I/O.
export function verifyInstalledConnectorBindings(source, effect) {
  function inventory(adapter) {
    const ids = new Set(adapter === undefined ? []
      : JSON.parse(adapter.environmentWire).connector_catalogs
        .map(catalog => catalog.connector_id));
    const result = new Map();
    const declared = adapter?.connectorBindings === undefined
      ? [] : adapter.connectorBindings;
    if (!Array.isArray(declared)) refuse('ConnectorBinding');
    for (const binding of declared) {
      if (typeof binding?.connectorId !== 'string' ||
          !ids.has(binding.connectorId) ||
          typeof binding.bindingCid !== 'string' ||
          !/^sha256:[0-9a-f]{64}$/u.test(binding.bindingCid) ||
          result.has(binding.connectorId)) refuse('ConnectorBinding');
      result.set(binding.connectorId, binding.bindingCid);
    }
    return {ids, bindings: result};
  }
  const sources = inventory(source), effects = inventory(effect);
  for (const id of sources.ids) {
    if (!effects.ids.has(id)) continue;
    if (sources.bindings.get(id) === undefined ||
        sources.bindings.get(id) !== effects.bindings.get(id)) {
      refuse('ConnectorBinding');
    }
  }
}
