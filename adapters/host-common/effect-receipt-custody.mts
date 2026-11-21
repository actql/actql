// Physical evidence viewing and final publication share one exact issued
// set owner. Receipt wires alone do not prove saved response custody.
// Unchecked field views retain the existing runtime validation and issued-set
// WeakMap as the only evidence of original ownership.
type ContractFields = {readonly name?: unknown; readonly identityField?: unknown; readonly identity?: unknown; readonly wire?: unknown};
type IssuedFields = {readonly set?: ContractFields; readonly members?: readonly ContractFields[]};
const issuedSets = new WeakMap<object, {ledger: unknown; preview: unknown}>();

const fail = (): never => {
  throw Object.assign(new Error('EffectSetReceiptEvidenceNotOwned'), {
    code: 'EffectSetReceiptEvidenceNotOwned',
  });
};

export function retainIssuedEffectSetReceipt({set, members, ledger, preview}: {set: ContractFields; members: readonly ContractFields[]; ledger: unknown; preview: unknown}) {
  if (!set || typeof set.wire !== 'string' ||
      !Array.isArray(members) || members.length === 0 ||
      members.some(member => typeof member?.wire !== 'string') ||
      !ledger || !preview) fail();
  const own = (contract: ContractFields) => Object.freeze({
    name: contract.name,
    identityField: contract.identityField,
    identity: contract.identity,
    wire: contract.wire as string,
  });
  const value = Object.freeze({set: own(set),
    members: Object.freeze(members.map(own))});
  issuedSets.set(value, Object.freeze({ledger, preview}));
  return value;
}

export function issuedEffectSetReceiptWires(value: IssuedFields, ledger: unknown, preview: unknown): Readonly<{
  setWire: string; memberWires: readonly string[];
}> {
  const owner = issuedSets.get(value);
  if (owner?.ledger !== ledger || owner?.preview !== preview ||
      typeof value?.set?.wire !== 'string' ||
      !Array.isArray(value.members)) fail();
  return Object.freeze({
    setWire: value.set!.wire as string,
    // The WeakMap only receives frozen copies of validated string wires.
    memberWires: Object.freeze(value.members!.map(member => member.wire as string)),
  });
}
