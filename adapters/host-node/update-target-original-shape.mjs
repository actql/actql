// Closed bounded syntax only. Core owners still admit all original semantics.
import {canonicalJson, contentCid, bytesCid} from './local-account-config.mjs';
import {canonicalJson as valueJson} from '../../packages/sdk/host-port.mjs';

// The existing request-journal admission-evidence ceiling. Count retained
// strings before any serialization, including their JSON escape expansion.
const maximum = 65_536;
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join(',') === [...keys].sort().join(',');
const wire = value => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && Buffer.byteLength(value) <= maximum;
const stringBytes = value => {
  if (!wire(value)) return Infinity;
  let bytes = Buffer.byteLength(value) + 2;
  for (const character of value) {
    if (character === '"' || character === '\\' || '\b\t\n\f\r'.includes(character)) bytes++;
    else if (character.charCodeAt(0) < 32) bytes += 5;
    if (bytes > maximum) return Infinity;
  }
  return bytes;
};

function originalBytes(value, materialKey) {
  if (!Array.isArray(value.installations) || value.installations.length > 1024) return Infinity;
  // Small fixed envelope/member key overhead is conservative. No growing
  // object is serialized merely to discover that it was already too large.
  let bytes = 256 + stringBytes(value[materialKey]);
  for (const installation of value.installations) {
    bytes += 128 + stringBytes(installation?.cid) + stringBytes(installation?.wire);
    if (bytes > maximum) return Infinity;
  }
  return bytes;
}

export function installationsShape(values) {
  if (!Array.isArray(values) || values.length === 0 || values.length > 1024 ||
      new Set(values.map(value => value?.cid)).size !== values.length) return false;
  let bytes = 2;
  try {
    return values.every(value => {
      if (!exact(value, ['cid', 'wire']) || !cid(value.cid) || !wire(value.wire)) return false;
      bytes += 128 + stringBytes(value.cid) + stringBytes(value.wire);
      if (bytes > maximum) return false;
      const body = JSON.parse(value.wire);
      return exact(body, ['connector_registration', 'connector_revision', 'runtime_bundle_cid',
        'binding_cid', 'connection', 'profile', 'continuation_binding']) &&
        canonicalJson(body) === value.wire && contentCid(body) === value.cid;
    });
  } catch { return false; }
}

export function updateTargetPreparedOriginalShape(value) {
  return exact(value, ['preparedWire', 'compiledPlanCid', 'installations']) &&
    wire(value.preparedWire) && cid(value.compiledPlanCid) &&
    originalBytes(value, 'preparedWire') <= maximum && installationsShape(value.installations);
}

export function updateTargetRunOriginalShape(value, evidence) {
  if (!exact(value, ['materialsWire', 'installations']) || !wire(value.materialsWire) ||
      originalBytes(value, 'materialsWire') > maximum ||
      !installationsShape(value.installations)) return false;
  try {
    const body = JSON.parse(value.materialsWire);
    return body.version === 'actql-remote-run-materials/0.1' &&
      wire(body.effect_target_selections_json) &&
      (evidence === undefined || body.prepared_invocation === evidence.prepared &&
        body.run_authorization === evidence.authorization);
  } catch { return false; }
}

// The optional field is part of the already admitted original Run body, so
// deleting it changes the independently selected Run CID. It is not a second
// journal marker. The tuple wire is the Core's canonical array preimage.
export function runUpdateSelectionCid(runDefinition) {
  const body = JSON.parse(runDefinition.wire);
  const identity = body.effect_target_selections_cid;
  if (identity !== undefined && !cid(identity)) throw new TypeError('InvalidEffectTargetSelectionCid');
  return identity;
}

export function updateTargetSelectionsCid(selections) {
  if (!Array.isArray(selections) || selections.length === 0 || selections.length > 1024) {
    throw new TypeError('InvalidEffectTargetSelections');
  }
  let bytes = 2;
  const keys = ['stage_index', 'effect_id', 'target_ref', 'mapping_ref', 'mapping_cid',
    'check_environment_cid', 'installation_binding_cid', 'installation_owner_cid'];
  for (const selection of selections) {
    if (!exact(selection, keys) || !Number.isSafeInteger(selection.stage_index) ||
        selection.stage_index < 0) throw new TypeError('InvalidEffectTargetSelections');
    bytes += 256;
    for (const key of keys.slice(1)) bytes += stringBytes(selection[key]);
    if (bytes > maximum) throw new TypeError('InvalidEffectTargetSelections');
  }
  return bytesCid(valueJson(selections, {dataKeys: true}));
}
