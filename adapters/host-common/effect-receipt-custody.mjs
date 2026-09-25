// Physical evidence viewing and final publication share one exact issued
// set owner. Receipt wires alone do not prove saved response custody.
const issuedSets = new WeakMap();

const fail = () => {
  throw Object.assign(new Error('EffectSetReceiptEvidenceNotOwned'), {
    code: 'EffectSetReceiptEvidenceNotOwned',
  });
};

export function retainIssuedEffectSetReceipt({set, members, ledger, preview}) {
  if (!set || typeof set.wire !== 'string' ||
      !Array.isArray(members) || members.length === 0 ||
      members.some(member => typeof member?.wire !== 'string') ||
      !ledger || !preview) fail();
  const own = contract => Object.freeze({
    name: contract.name,
    identityField: contract.identityField,
    identity: contract.identity,
    wire: contract.wire,
  });
  const value = Object.freeze({set: own(set),
    members: Object.freeze(members.map(own))});
  issuedSets.set(value, Object.freeze({ledger, preview}));
  return value;
}

export function issuedEffectSetReceiptWires(value, ledger, preview) {
  const owner = issuedSets.get(value);
  if (owner?.ledger !== ledger || owner?.preview !== preview ||
      typeof value?.set?.wire !== 'string' ||
      !Array.isArray(value.members)) fail();
  return Object.freeze({
    setWire: value.set.wire,
    memberWires: Object.freeze(value.members.map(member => member.wire)),
  });
}
