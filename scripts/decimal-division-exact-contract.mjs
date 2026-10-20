import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const divisionPolicies = ['half_even', 'half_up', 'toward_zero', 'floor', 'ceiling', 'exact'];
export const divisionLaw = {
  authoring: "SQL, Pipe and Common expression text decimal_divide(left,right,scale) emit the complete five-field body with precision38, the same static integer scale0..38 and division-only rounding exact. Retain both original children in order. Explicit five-argument policies preserve their meanings; no omitted fields are admitted by machine readers. The two-argument scale policy is not supplied by this rule.",
  value: "After both demanded children succeed and NULL propagation, compute the original exact coefficient ratio at the selected target scale. exact requires zero remainder and a fitting coefficient; inexactness, zero divisor and overflow fail with the existing arithmetic failure. The five explicit rounding policies keep their old behavior. No frontend evaluator, binary64 quotient, promotion or losslessness inference from a rounded value is permitted.",
  typing: "The left operand is Decimal and the divisor is Decimal or original safe-integer Number. Only an immediate literal NULL left receives the nullable declared Decimal target; only an immediate literal NULL divisor receives the resolved left Decimal contract, including contextualized literal NULL. This context proves no non-null input and never types an unknown field or Parameter or converts Number, Signed64 or String.",
  demand: "Both original children remain demanded exactly once in source order, including after a NULL child. Child error, control, cancellation, workspace, live-value and root retirement semantics remain unchanged; NULL does not suppress a demanded failure. Quantize never admits exact.",
  identity: "The operation, operand order, five required fields and old explicit-mode expression body bytes remain unchanged. exact is an added division policy at initial0.1, with genuinely changed containing contracts and pins; historical bodies retain their original identities. Authoring spans remain the original source.",
};

function visit(value, write, counts) {
  if (!value || typeof value !== 'object') return;
  const source = value.properties?.decimal_divide;
  const machine = value.properties?.op?.const === 'decimal_divide' ? value.properties?.body : undefined;
  const schema = source ?? machine;
  if (schema) {
    assert.equal(schema.additionalProperties, false);
    assert.deepEqual(schema.required, ['left', 'right', 'precision', 'scale', 'rounding']);
    const policies = schema.properties.rounding;
    assert.ok([5, 6].includes(policies.enum.length), 'closed division policy alternatives');
    assert.deepEqual(policies.enum, write ? divisionPolicies.slice(0, policies.enum.length) : divisionPolicies);
    if (write) policies.enum = [...divisionPolicies];
    counts[source ? 'source' : 'machine']++;
  }
  for (const child of Object.values(value)) visit(child, write, counts);
}

export function updateDecimalDivisionContracts(expressions, protocol, scalar, write = false) {
  const counts = {source: 0, machine: 0};
  visit(expressions.schemas, write, counts);
  visit(protocol.artifact_schemas, write, counts);
  assert.deepEqual(counts, {source: 7, machine: 3}, 'complete declared division embeddings');
  if (write) {
    expressions.laws.decimal_divide = structuredClone(divisionLaw);
    scalar.decimal.division = structuredClone(divisionLaw);
  } else {
    assert.deepEqual(expressions.laws.decimal_divide, divisionLaw);
    assert.deepEqual(scalar.decimal.division, divisionLaw);
  }
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) {
    if (write) protocol.artifact_schema_cids[name] = machineCid(schema);
    else assert.equal(protocol.artifact_schema_cids[name], machineCid(schema), `stale artifact ${name}`);
  }
  if (write) protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas));
  return counts;
}

export function verifyDecimalDivisionContracts(write = false) {
  const paths = ['spec/contracts/actql-expressions.json', 'spec/contracts/actql-protocol-schemas.json',
    'spec/dependencies/aoa-rela-scalar-laws.json'];
  const bodies = paths.map(path => JSON.parse(readFileSync(path, 'utf8')));
  const counts = updateDecimalDivisionContracts(...bodies, write);
  if (write) {
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
    const aoaPath = 'spec/contracts/actql-aoa.json';
    const aoa = JSON.parse(readFileSync(aoaPath, 'utf8'));
    aoa.rela_scalar_law_manifest_cid = machineCid(bodies[2]);
    writeFileSync(aoaPath, JSON.stringify(aoa, null, 2) + '\n');
  }
  return counts;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log('Decimal division closed policy/NULL contracts:', verifyDecimalDivisionContracts(process.argv.includes('--write')));
}
