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
  strpos: {
    signature: 'Exactly two string operands; the result is a finite number and is nullable exactly when either operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.',
    value: 'Return the 1-based Unicode scalar position of the first exact occurrence of the second string in the first, or canonical positive zero when absent. An empty second string returns 1 for every non-null first string, including the empty string. Count Unicode scalars, not UTF-8 bytes, UTF-16 code units or grapheme clusters. Default binary comparison preserves retained values without normalization, case folding, trimming or locale rules. Either NULL operand produces NULL. Positions are exact integer values in the existing bounded string domain, represented by ActQL finite binary64 number rather than the GoogleSQL INT64 type.',
    evaluation: 'Evaluate the value and then the subvalue once each when demanded, including both children when the first produces NULL. Apply strict NULL only after both evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Matching preserves logical operand charges; physical search work remains bounded and cancellable.',
    identity: 'The closed source form is {strpos: [value, subvalue]}; the machine node is {op: strpos, body: [value_node, subvalue_node]}. Retain the node and both ordered children in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
  round: {
    signature: 'Exactly one finite binary64 number operand; the result is number with the operand nullability. Untyped NULL takes the unique number signature. No implicit conversion, decimal overload, non-finite value, precision argument or rounding-mode argument is admitted.',
    value: 'Return the nearest integer, rounding exact halfway cases away from zero. Preserve already integral numbers, including the largest finite magnitudes. Use the existing ActQL arithmetic canonical positive zero rule. NULL produces NULL.',
    evaluation: 'Evaluate the sole child exactly once when demanded, then apply the value rule. Preserve the child failure, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. ROUND introduces no secondary evaluation or value-domain failure for an admitted finite number.',
    identity: 'The closed source form is {round: expression}; the closed machine node is {op: round, body: expression_node}. Retain the ROUND node and its child in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
  trunc: {
    signature: 'Exactly one finite binary64 number operand; the result is number with the operand nullability. Untyped NULL takes the unique number signature. No implicit conversion, decimal overload, non-finite value, precision argument or rounding-mode argument is admitted.',
    value: 'Return the integer obtained by discarding the fractional part toward zero. Preserve already integral numbers, including the largest finite magnitudes. Use the existing ActQL arithmetic canonical positive zero rule. NULL produces NULL.',
    evaluation: 'Evaluate the sole child exactly once when demanded, then apply the value rule. Preserve the child failure, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. TRUNC introduces no secondary evaluation or value-domain failure for an admitted finite number.',
    identity: 'The closed source form is {trunc: expression}; the closed machine node is {op: trunc, body: expression_node}. Retain the TRUNC node and its child in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
  trim: {
    signature: "One string value operand, or exactly two string operands consisting of value and explicit character set; the result is string and is nullable exactly when any operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.",
    value: "Remove the longest leading and trailing sequences of Unicode code points belonging to the selected set. When the set is omitted, use the pinned Unicode 16.0 White_Space set: U+0009..U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000..U+200A, U+2028, U+2029, U+202F, U+205F and U+3000. An explicit set is the code points of the second string, independently of order and duplicates; an empty set leaves the value unchanged. Membership is not substring, grapheme-cluster or normalized matching. Combining marks are independently removable even when part of a different combining sequence. Preserve the exact remaining Unicode scalar sequence without normalization, case folding or line-break conversion. An empty value remains empty; a value consisting entirely of set members becomes empty. U+FEFF, U+200B and U+180E are excluded from the omitted set but can be explicit members. Either NULL operand produces NULL.",
    evaluation: "Evaluate each demanded operand exactly once in authored order, value before explicit set, including the second child after a NULL value. Apply strict NULL only after all demanded child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Trimming preserves all logical operand charges; physical set membership, scanning, exact output sizing and construction remain bounded and cancellable.",
    identity: "The closed source forms are {trim: expression} and {trim: [value, characters]}; the machine node is {op: trim, body: expression_node} or {op: trim, body: [value_node, characters_node]} respectively. Preserve existing unary canonical bytes. Retain the authored operation and every ordered child, including empty, duplicate or reordered set expressions, even when the value is unchanged. Earlier expression and scalar-law contract CIDs retain their earlier meanings and do not acquire the explicit-set overload.",
  },
  ltrim: {
    signature: "One string value operand, or exactly two string operands consisting of value and explicit character set; the result is string and is nullable exactly when any operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.",
    value: "Remove the longest leading sequence only of Unicode code points belonging to the selected set. When the set is omitted, use the pinned Unicode 16.0 White_Space set: U+0009..U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000..U+200A, U+2028, U+2029, U+202F, U+205F and U+3000. An explicit set is the code points of the second string, independently of order and duplicates; an empty set leaves the value unchanged. Membership is not substring, grapheme-cluster or normalized matching. Combining marks are independently removable even when part of a different combining sequence. Preserve the exact remaining Unicode scalar sequence without normalization, case folding or line-break conversion. An empty value remains empty; a value consisting entirely of set members becomes empty. U+FEFF, U+200B and U+180E are excluded from the omitted set but can be explicit members. Either NULL operand produces NULL.",
    evaluation: "Evaluate each demanded operand exactly once in authored order, value before explicit set, including the second child after a NULL value. Apply strict NULL only after all demanded child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Trimming preserves all logical operand charges; physical set membership, scanning, exact output sizing and construction remain bounded and cancellable.",
    identity: "The closed source forms are {ltrim: expression} and {ltrim: [value, characters]}; the machine node is {op: ltrim, body: expression_node} or {op: ltrim, body: [value_node, characters_node]} respectively. Preserve existing unary canonical bytes. Retain the authored operation and every ordered child, including empty, duplicate or reordered set expressions, even when the value is unchanged. Earlier expression and scalar-law contract CIDs retain their earlier meanings and do not acquire the explicit-set overload.",
  },
  rtrim: {
    signature: "One string value operand, or exactly two string operands consisting of value and explicit character set; the result is string and is nullable exactly when any operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.",
    value: "Remove the longest trailing sequence only of Unicode code points belonging to the selected set. When the set is omitted, use the pinned Unicode 16.0 White_Space set: U+0009..U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000..U+200A, U+2028, U+2029, U+202F, U+205F and U+3000. An explicit set is the code points of the second string, independently of order and duplicates; an empty set leaves the value unchanged. Membership is not substring, grapheme-cluster or normalized matching. Combining marks are independently removable even when part of a different combining sequence. Preserve the exact remaining Unicode scalar sequence without normalization, case folding or line-break conversion. An empty value remains empty; a value consisting entirely of set members becomes empty. U+FEFF, U+200B and U+180E are excluded from the omitted set but can be explicit members. Either NULL operand produces NULL.",
    evaluation: "Evaluate each demanded operand exactly once in authored order, value before explicit set, including the second child after a NULL value. Apply strict NULL only after all demanded child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Trimming preserves all logical operand charges; physical set membership, scanning, exact output sizing and construction remain bounded and cancellable.",
    identity: "The closed source forms are {rtrim: expression} and {rtrim: [value, characters]}; the machine node is {op: rtrim, body: expression_node} or {op: rtrim, body: [value_node, characters_node]} respectively. Preserve existing unary canonical bytes. Retain the authored operation and every ordered child, including empty, duplicate or reordered set expressions, even when the value is unchanged. Earlier expression and scalar-law contract CIDs retain their earlier meanings and do not acquire the explicit-set overload.",
  },
  sign: {
    signature: 'Exactly one finite binary64 number operand; the result is number with the operand nullability. Untyped NULL takes the unique number signature. No implicit conversion, decimal overload or non-finite value is admitted.',
    value: 'Return exactly -1 for a negative finite number, canonical positive zero for either zero sign, and exactly 1 for a positive finite number. This includes subnormal and largest finite magnitudes. NULL produces NULL.',
    evaluation: 'Evaluate the sole child exactly once when demanded, then apply the value rule. Preserve the child failure, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. SIGN introduces no secondary evaluation or value-domain failure for an admitted finite number.',
    identity: 'The closed source form is {sign: expression}; the closed machine node is {op: sign, body: expression_node}. Retain the SIGN node and its child in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
};
const templates = {starts_with: 'contains', ends_with: 'contains', strpos: 'contains', sign: 'abs', trim: 'abs', ltrim: 'abs', rtrim: 'abs', round: 'abs', trunc: 'abs'};

// Unicode 16.0 PropList.txt White_Space, not host-language trim or regex \s.
export const trimWhiteSpaceCodePoints = [
  '0009..000D', '0020', '0085', '00A0', '1680', '2000..200A',
  '2028', '2029', '202F', '205F', '3000',
];
export function updateTrimScalarLaw(scalar, write = false) {
  assert.equal(scalar.unicode.data_version, '16.0', 'TRIM Unicode data version');
  const expected = {trim: 'unicode-white-space',
    ltrim: 'unicode-white-space-leading', rtrim: 'unicode-white-space-trailing',
    trim_white_space_code_points: trimWhiteSpaceCodePoints,
    trim_character_set: 'unicode-code-point-membership',
    trim_empty_character_set: 'preserve-value'};
  if (write) Object.assign(scalar.unicode, structuredClone(expected));
  else for (const [key, value] of Object.entries(expected)) {
    assert.deepEqual(scalar.unicode[key], value, `stale TRIM scalar law ${key}`);
  }
}

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
        if (['trim', 'ltrim', 'rtrim'].includes(name)) {
          const key = kind === 'source' ? name : 'body';
          const unary = expected.properties[key];
          expected.properties[key] = {oneOf: [unary, {type: 'array',
            minItems: 2, maxItems: 2, items: structuredClone(unary)}]};
        }
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
  const scalarPath = 'spec/dependencies/aoa-rela-scalar-laws.json';
  const aoaPath = 'spec/contracts/actql-aoa.json';
  const scalar = JSON.parse(readFileSync(scalarPath, 'utf8'));
  const aoa = JSON.parse(readFileSync(aoaPath, 'utf8'));
  if (process.argv.includes('--write')) {
    updateTrimScalarLaw(scalar, true);
    aoa.rela_scalar_law_manifest_cid = machineCid(scalar);
    writeFileSync(scalarPath, JSON.stringify(scalar, null, 2) + '\n');
    writeFileSync(aoaPath, JSON.stringify(aoa, null, 2) + '\n');
    updateGoogleScalarContracts(...bodies, grammar, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  updateTrimScalarLaw(scalar);
  assert.equal(aoa.rela_scalar_law_manifest_cid, machineCid(scalar), 'TRIM scalar manifest pin');
  console.log('GoogleSQL STRING boundary/search/TRIM/LTRIM/RTRIM and finite-number SIGN/ROUND/TRUNC contracts verified:',
    updateGoogleScalarContracts(...bodies, grammar));
}
