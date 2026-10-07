// Explicit Host configuration of the existing capacity contract. This is
// neither caller Program input nor an adapter-owned policy override.
import contract from '../../spec/contracts/actql-capacity-host-policy.json' with {type: 'json'};
import {canonicalJson, contentCid} from './local-account-config.mjs';

const snapshots = new WeakSet();
const fail = cause => {
  throw Object.assign(new TypeError('InvalidInstalledHostCapacityPolicy', {cause}),
    {code: 'InvalidInstalledHostCapacityPolicy'});
};

export function snapshotHostCapacityPolicy(value) {
  if (value === undefined) return undefined;
  if (value !== null && typeof value === 'object' && snapshots.has(value)) return value;
  try {
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.getPrototypeOf(value) !== Object.prototype) fail('PolicyShape');
    // Read each application-owned field once before any asynchronous boundary.
    // The registered contract is flat; no private/nested object is retained.
    const entries = Object.entries(value);
    const shape = contract.schema;
    const keys = new Set(entries.map(([key]) => key));
    if (entries.length > Object.keys(shape.properties).length ||
        shape.required.some(key => !keys.has(key))) fail('PolicyFields');
    for (const [key, item] of entries) {
      const rule = shape.properties[key];
      if (!Object.hasOwn(shape.properties, key) || (Object.hasOwn(rule, 'const') ? item !== rule.const :
        !Number.isSafeInteger(item) || Object.is(item, -0) ||
          item < rule.minimum || item > rule.maximum)) fail('PolicyField');
    }
    const snapshot = Object.freeze(Object.fromEntries(entries));
    snapshots.add(snapshot);
    return snapshot;
  } catch { fail('PolicySnapshot'); }
}

export function selectInstalledHostEnvironment(moon, baseWire, selection) {
  const policy = snapshotHostCapacityPolicy(selection);
  if (policy === undefined) return baseWire;
  const {evidence_bundle_cid: ignored, ...body} = JSON.parse(baseWire);
  void ignored;
  body.host_policy_profile = {...body.host_policy_profile, capacity: policy};
  const evidenceCid = contentCid(body);
  const wire = canonicalJson({...body, evidence_bundle_cid: evidenceCid});
  if (moon.clientProgramCheckEnvironment(wire, evidenceCid,
    false, false, true, false, false, false, false) === undefined) fail('PolicyAdmission');
  return wire;
}
