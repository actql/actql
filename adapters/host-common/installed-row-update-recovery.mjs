import {canonicalJson} from '../../packages/sdk/host-port.mjs';

const encode = value => canonicalJson(value, {dataKeys: true});

function fail(code) {
  throw Object.assign(new Error(code), {code});
}

// The admitted Preview and its claims keep their original global member
// indexes. Only a connector's retained request codec can restore a row.
export function restoreInstalledRowUpdateMembers(context, maxMembers, invalidCode, restoreMember) {
  const {durable, recorded, members, memberIndexes} = context;
  if (!Array.isArray(members) || members.length < 1 || members.length > maxMembers ||
      !Array.isArray(durable?.connectorRecovery) || durable.connectorRecovery.length > members.length ||
      !Array.isArray(recorded?.members) || recorded.members.length !== members.length) fail(invalidCode);
  const indexes = memberIndexes ?? members.map((_, index) => index);
  if (!Array.isArray(indexes) || indexes.length < 1 || indexes.length > members.length ||
      indexes.some((index, offset) => !Number.isSafeInteger(index) || index < 0 || index >= members.length ||
        offset > 0 && index <= indexes[offset - 1])) fail(invalidCode);
  const byIndex = new Map();
  for (const entry of durable.connectorRecovery) {
    if (!Number.isSafeInteger(entry?.memberIndex) || entry.memberIndex < 0 || entry.memberIndex >= members.length ||
        byIndex.has(entry.memberIndex)) fail(invalidCode);
    byIndex.set(entry.memberIndex, entry);
  }
  const requests = new Array(indexes.length);
  for (let position = 0; position < indexes.length; position++) {
    if (position in indexes) {
      const index = indexes[position];
      requests[position] = restoreMember(context, index, byIndex.get(index));
    }
  }
  return Object.freeze({requests: Object.freeze(requests)});
}

// Check each reconstructed row against its original claim and approved Preview.
export function assertInstalledRowUpdateClaim(rebuilt, facts, claims, changes, row, foreignCode) {
  if (rebuilt.requestCid !== claims[row].canonicalRequestCid ||
      encode(facts.value) !== encode(changes[row].after?.value) ||
      encode(facts.target) !== encode(changes[row].target_row_identity)) fail(foreignCode);
}
