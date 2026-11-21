// Physical evidence viewing and final publication share one exact issued
// set owner. Receipt wires alone do not prove saved response custody.
// Unchecked field views retain the existing runtime validation and issued-set
// WeakMap as the only evidence of original ownership.
type ContractFields = {readonly name?: unknown; readonly identityField?: unknown; readonly identity?: unknown; readonly wire?: unknown};
type IssuedFields = {readonly set?: ContractFields; readonly members?: readonly ContractFields[]};
const issuedSets = new WeakMap<object, {ledger: unknown; preview: unknown}>();

const fail: () => never = () => {
  throw Object.assign(new Error('EffectSetReceiptEvidenceNotOwned'), {
    code: 'EffectSetReceiptEvidenceNotOwned',
  });
};

export function retainIssuedEffectSetReceipt({set, members, ledger, preview}: {set: ContractFields; members: readonly ContractFields[]; ledger: unknown; preview: unknown}) {
  if (!set || !Array.isArray(members) || !ledger || !preview) fail();
  const count = members.length;
  if (!Number.isInteger(count) || count < 1 || count > 0xffffffff) fail();
  const own = (contract: ContractFields | undefined) => {
    const wire = contract?.wire;
    if (contract === undefined || typeof wire !== 'string') fail();
    return Object.freeze({
      name: contract.name,
      identityField: contract.identityField,
      identity: contract.identity,
      wire,
    });
  };
  const ownedSet = own(set);
  const ownedMembers = [];
  for (let index = 0; index < count; index++) ownedMembers.push(own(members[index]));
  const value = Object.freeze({set: ownedSet, members: Object.freeze(ownedMembers)});
  issuedSets.set(value, Object.freeze({ledger, preview}));
  return value;
}

export function issuedEffectSetReceiptWires(value: IssuedFields, ledger: unknown, preview: unknown): Readonly<{
  setWire: string; memberWires: readonly string[];
}> {
  const owner = issuedSets.get(value);
  if (owner === undefined || owner.ledger !== ledger || owner.preview !== preview ||
      typeof value?.set?.wire !== 'string' ||
      !Array.isArray(value.members)) fail();
  // Issuance only registers frozen copies of checked original wires.
  const original = value as ReturnType<typeof retainIssuedEffectSetReceipt>;
  return Object.freeze({
    setWire: original.set.wire,
    memberWires: Object.freeze(original.members.map(member => member.wire)),
  });
}
