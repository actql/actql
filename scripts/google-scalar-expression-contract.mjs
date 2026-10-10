import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const stringSignature = 'Exactly two string operands; the result is boolean and is nullable exactly when either operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.';
const stringEvaluation = 'Evaluate the value and then the prefix or suffix once each when demanded, including both children when the first produces NULL. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Exact matching does not skip logical operand charges.';
export const googleScalarLaws = {
  starts_with: {
    signature: stringSignature,
    value: 'Return whether the second string is an exact prefix of the first, using their retained Unicode scalar sequences with default binary comparison. The empty prefix matches every non-null string, including the empty string. A longer prefix does not match. No normalization, case folding, trimming or locale rule is applied. Either NULL operand produces NULL.',
    evaluation: stringEvaluation,
    identity: 'The closed source form is {starts_with: [value, prefix]}; the machine node is {op: starts_with, body: [value_node, prefix_node]}. Retain the node and both ordered children in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
  ends_with: {
    signature: stringSignature,
    value: 'Return whether the second string is an exact suffix of the first, using their retained Unicode scalar sequences with default binary comparison. The empty suffix matches every non-null string, including the empty string. A longer suffix does not match. No normalization, case folding, trimming or locale rule is applied. Either NULL operand produces NULL.',
    evaluation: stringEvaluation,
    identity: 'The closed source form is {ends_with: [value, suffix]}; the machine node is {op: ends_with, body: [value_node, suffix_node]}. Retain the node and both ordered children in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
  sign: {
    signature: 'Exactly one finite binary64 number operand; the result is number with the operand nullability. Untyped NULL takes the unique number signature. No implicit conversion, decimal overload or non-finite value is admitted.',
    value: 'Return exactly -1 for a negative finite number, canonical positive zero for either zero sign, and exactly 1 for a positive finite number. This includes subnormal and largest finite magnitudes. NULL produces NULL.',
    evaluation: 'Evaluate the sole child exactly once when demanded, then apply the value rule. Preserve the child failure, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. SIGN introduces no secondary evaluation or value-domain failure for an admitted finite number.',
    identity: 'The closed source form is {sign: expression}; the closed machine node is {op: sign, body: expression_node}. Retain the SIGN node and its child in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
};
const templates = {starts_with: 'contains', ends_with: 'contains', sign: 'abs'};

// Copy shapes, not semantics, and keep each embedding's local expression refs.
function visit(value, write, counts) {
  if (!value || typeof value !== 'object') return;
  if (Array.isArray(value.oneOf)) {
    for (const kind of ['source', 'node']) {
      const named = (candidate, name) => kind === 'source'
        ? candidate.additionalProperties === false &&
          candidate.required?.length === 1 && candidate.required[0] === name
        : candidate.properties?.op?.const === name;
      for (const [name, template] of Object.entries(templates)) {
        const shapes = value.oneOf.filter(candidate => named(candidate, template));
        if (!shapes.length) continue;
        assert.equal(shapes.length, 1, `ambiguous ${template} expression schema`);
        const expected = structuredClone(shapes[0]);
        if (kind === 'source') {
          expected.required = [name];
          expected.properties = {[name]: expected.properties[template]};
        } else expected.properties.op.const = name;
        const matches = value.oneOf.filter(candidate => named(candidate, name));
        assert.ok(matches.length <= 1, `duplicate ${name} schema`);
        if (write) {
          if (matches.length) value.oneOf[value.oneOf.indexOf(matches[0])] = expected;
          else value.oneOf.splice(value.oneOf.indexOf(shapes[0]) + 1, 0, expected);
        } else assert.deepEqual(matches[0], expected, `stale ${kind} ${name} schema`);
        counts[name][kind]++;
      }
    }
  }
  for (const child of Object.values(value)) visit(child, write, counts);
}

export function updateGoogleScalarContracts(expressions, protocol, grammar, write = false) {
  const counts = Object.fromEntries(Object.keys(templates).map(name =>
    [name, {source: 0, node: 0}]));
  for (const name of Object.keys(templates)) {
    assert.match(grammar, new RegExp(`\\| "${name}"(?:\\s|\\|)`, 'u'),
      `${name} missing from expression grammar`);
  }
  visit(expressions.schemas, write, counts);
  visit(protocol.artifact_schemas, write, counts);
  for (const [name, count] of Object.entries(counts)) {
    assert.ok(count.source > 0 && count.node > 0, `missing ${name} expression schemas`);
    if (write) expressions.laws[name] = structuredClone(googleScalarLaws[name]);
    else assert.deepEqual(expressions.laws[name], googleScalarLaws[name], `stale ${name} law`);
  }
  const grammarSha256 = createHash('sha256').update(grammar).digest('hex');
  if (write) expressions.grammar_sha256 = grammarSha256;
  else assert.equal(expressions.grammar_sha256, grammarSha256, 'stale expression grammar pin');
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) {
    if (write) protocol.artifact_schema_cids[name] = machineCid(schema);
    else assert.equal(protocol.artifact_schema_cids[name], machineCid(schema));
  }
  if (write) protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas));
  return counts;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const paths = ['spec/contracts/actql-expressions.json', 'spec/contracts/actql-protocol-schemas.json'];
  const bodies = paths.map(path => JSON.parse(readFileSync(path, 'utf8')));
  const grammar = readFileSync(bodies[0].grammar, 'utf8');
  if (process.argv.includes('--write')) {
    updateGoogleScalarContracts(...bodies, grammar, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  console.log('GoogleSQL STRING boundary and finite-number SIGN contracts verified:',
    updateGoogleScalarContracts(...bodies, grammar));
}
