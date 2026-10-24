// Physical storage accounting only. Common supplies the four per-kind
// contract ceilings from its exact issuance emitters; no schema copies here.
const bytes = value => new TextEncoder().encode(value).byteLength;
export function completedPublicationCapacity(plan, definitions, request, attempt, resultBounds, frontier) {
  const ceiling = plan.contractLimits.maxWireBytes;
  let requiredBytes = 0, objectCount = 0, maxObjectBytes = 0;
  const add = size => {
    if (!Number.isSafeInteger(size) || size < 0 ||
        !Number.isSafeInteger(requiredBytes + size)) {
      throw new RangeError('RunPublicationPreflightCapacityOverflow');
    }
    requiredBytes += size; objectCount++;
    maxObjectBytes = Math.max(maxObjectBytes, size);
  };
  // Identical semantic identities dedup exactly as persistContracts does.
  // Do not dedup unobserved payload/schema/content identities by task or alias.
  const known = new Map();
  for (const contract of [plan.runDefinition, plan.invocation, ...definitions,
    ...plan.results.map(result => result.retention), request, attempt]) {
    const previous = known.get(contract.identity);
    if (previous !== undefined && previous !== contract.wire) {
      throw new TypeError('ConflictingPublicationContractIdentity');
    }
    if (previous === undefined) { known.set(contract.identity, contract.wire); add(bytes(contract.wire)); }
  }
  if (resultBounds !== undefined && (!Array.isArray(resultBounds) ||
      resultBounds.length !== plan.results.length)) {
    throw new TypeError('InvalidPublicationContractByteBounds');
  }
  for (let index = 0; index < plan.results.length; index++) {
    add(plan.outputLimits.maxWireBytes);
    const schema = plan.outputLimits.maxSchemaBytes ?? ceiling;
    add(schema);
    const bounds = resultBounds === undefined
      ? [ceiling, ceiling, ceiling, ceiling] : resultBounds[index];
    if (!Array.isArray(bounds) || bounds.length !== 4 ||
        !bounds.every(value => Number.isSafeInteger(value) && value >= 0 && value <= ceiling)) {
      throw new TypeError('InvalidPublicationContractByteBounds');
    }
    for (const bound of bounds) add(bound);
  }
  // Capture retains its admitted ceiling until its own full nested proof.
  // Durable objects coexist; never replace this sum by a transient peak max.
  const manifest = frontier?.manifest ?? ceiling;
  if (!Number.isSafeInteger(manifest) || manifest < 0 || manifest > ceiling) {
    throw new TypeError('InvalidPublicationManifestByteBound');
  }
  add(manifest);
  const receipt = frontier?.receipt ?? ceiling;
  if (!Number.isSafeInteger(receipt) || receipt < 0 || receipt > ceiling) {
    throw new TypeError('InvalidPublicationReceiptByteBound');
  }
  add(receipt);
  add(ceiling);
  const current = frontier?.current;
  const obligations = frontier === undefined
    ? [ceiling, ceiling, ceiling, ceiling, ceiling, ceiling]
    : [frontier.index, current?.preparing, current?.committing,
      current?.publicationUnknown, current?.terminal,
      frontier.possibleForeignWinnerTerminal];
  if (!obligations.every(value => Number.isSafeInteger(value) && value >= 0 && value <= ceiling)) {
    throw new TypeError('InvalidPublicationFrontierByteBounds');
  }
  // The final obligation belongs to a distinct winner attempt. A resolved
  // foreign commit can append its missing success AND cancel this attempt;
  // no retained winner preflight token is assumed to fund that extra write.
  for (const bound of obligations) add(bound);
  if (!Number.isSafeInteger(objectCount)) throw new RangeError('RunPublicationPreflightCapacityOverflow');
  return Object.freeze({requiredBytes, objectCount, maxObjectBytes});
}
