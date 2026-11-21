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
  return Object.freeze({requests: Object.freeze(indexes.map(index => restoreMember(context, index, byIndex.get(index))))});
}
