import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const directTrigLaws = {
  "sin": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the sine of the angle in radians. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math sin primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {sin: expression} and the closed machine node is {op: sin, body: expression_node}. SIN selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "cos": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the cosine of the angle in radians. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math cos primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {cos: expression} and the closed machine node is {op: cos, body: expression_node}. COS selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "tan": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the tangent of the angle in radians. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math tan primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {tan: expression} and the closed machine node is {op: tan, body: expression_node}. TAN selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "asin": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the principal inverse sine in radians in [-pi/2, pi/2]; fail outside [-1, 1]. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math asin primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {asin: expression} and the closed machine node is {op: asin, body: expression_node}. ASIN selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "acos": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the principal inverse cosine in radians in [0, pi]; fail outside [-1, 1]. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math acos primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {acos: expression} and the closed machine node is {op: acos, body: expression_node}. ACOS selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "atan": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the principal inverse tangent in radians in [-pi/2, pi/2]. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math atan primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {atan: expression} and the closed machine node is {op: atan, body: expression_node}. ATAN selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "atan2": {
    "signature": "Exactly two ordered finite binary64 Number operands; return Number, nullable exactly when either operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when either operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the principal inverse tangent of first/second in radians in [-pi, pi], using both authored operand signs to choose the quadrant. Pass first then second directly to core atan2, without dividing or swapping. For raw finite signed-zero arguments, (+0, +0) and (-0, +0) produce canonical positive zero, (+0, -0) selects positive pi and (-0, -0) selects negative pi. Canonical public Number zero is positive, so the public (0, 0) result is positive zero. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math atan2 primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand both children exactly once in authored left-to-right order, preserving the first child failure and then the second child failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {atan2: [first, second]} and the closed machine node is {op: atan2, body: [first_node, second_node]}. ATAN2 selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "sinh": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the hyperbolic sine; overflow is an arithmetic failure. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math sinh primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {sinh: expression} and the closed machine node is {op: sinh, body: expression_node}. SINH selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "cosh": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the hyperbolic cosine; overflow is an arithmetic failure. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math cosh primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {cosh: expression} and the closed machine node is {op: cosh, body: expression_node}. COSH selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "tanh": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the hyperbolic tangent. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math tanh primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {tanh: expression} and the closed machine node is {op: tanh, body: expression_node}. TANH selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "asinh": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the inverse hyperbolic sine. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math asinh primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {asinh: expression} and the closed machine node is {op: asinh, body: expression_node}. ASINH selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "acosh": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the inverse hyperbolic cosine; fail for values less than 1. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math acosh primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {acosh: expression} and the closed machine node is {op: acosh, body: expression_node}. ACOSH selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "atanh": {
    "signature": "Exactly one finite binary64 Number operand; return Number, nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when the operand is nullable; runtime value-domain checks do not narrow static types.",
    "value": "Return the inverse hyperbolic tangent; fail unless -1 < value < 1, including failure at both endpoints. NULL produces NULL after all demanded children succeed. Reject non-finite operands; domain checks follow strict NULL propagation. Canonicalize every zero result to positive zero and preserve the existing arithmetic failure for any non-finite result.",
    "algorithm": "Use the selected target's pinned MoonBit core math atanh primitive and canonical finite-result validation. Do not reconstruct it from other operations or use a frontend/Host evaluator. Preserve every existing numeric accuracy and exception contract; general last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through the common continuation and canonical scalar evaluator.",
    "identity": "The closed source is {atanh: expression} and the closed machine node is {op: atanh, body: expression_node}. ATANH selects this same direct operation. Retain every authored child in order without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  }
};
const operations = Object.keys(directTrigLaws);

// These are the declared common-expression embeddings, not a global spelling
// replacement. Each child reference remains local to its owning schema scope.
const scopes = [
  ['expressions', 'schemas/expression/$defs/expression', 'source', 'expression'],
  ['expressions', 'schemas/expression_node/$defs/expression', 'node', 'expression'],
  ['expressions', 'schemas/fragment/$defs/source_expression', 'source', 'source_expression'],
  ['expressions', 'schemas/fragment/$defs/machine_expression', 'node', 'machine_expression'],
  ['expressions', 'schemas/predicate_consumer/$defs/source_expression', 'source', 'source_expression'],
  ['expressions', 'schemas/predicate_consumer/$defs/machine_expression', 'node', 'machine_expression'],
  ...['executable_plan', 'plan_document'].flatMap(artifact => {
    const prefix = artifact === 'plan_document' ? 'properties/plan/' : '';
    return ['predicate', 'value_expression'].map(definition => ['protocol',
      `artifact_schemas/${artifact}/${prefix}properties/execution_material/properties/program/$defs/${definition}`,
      'source', 'value_expression']);
  }),
];
const named = (shape, name, kind) => kind === 'source'
  ? shape.required?.includes(name) || Object.hasOwn(shape.properties ?? {}, name)
  : shape.properties?.op?.const === name;
function shape(name, kind, reference) {
  const child = {$ref: `#/$defs/${reference}`};
  const body = name === 'atan2' ? {type: 'array', minItems: 2, maxItems: 2, items: child} : child;
  return kind === 'source'
    ? {type: 'object', additionalProperties: false, required: [name], properties: {[name]: body}}
    : {type: 'object', additionalProperties: false, required: ['op', 'body'],
      properties: {op: {const: name}, body}};
}
function walk(value, visit) {
  if (!value || typeof value !== 'object') return;
  visit(value);
  for (const child of Object.values(value)) walk(child, visit);
}
function requireGrammar(grammar) {
  // Comments or a similarly named function do not register a function token.
  const source = grammar.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const productions = [...source.matchAll(/\bfunction_name\s*=([^;]+);/gu)];
  assert.equal(productions.length, 1, 'one common function_name production');
  for (const name of operations) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
    assert.equal([...productions[0][1].matchAll(new RegExp(`"${escaped}"`, 'gu'))].length, 1,
      `${name} missing or duplicated in common function_name production`);
  }
}

export function updateDirectTrigContracts(expressions, protocol, grammar, write = false) {
  requireGrammar(grammar);
  const roots = {expressions, protocol};
  const counts = {source: 0, node: 0};
  // Preflight every scope and duplicate before mutating even in write mode.
  const plans = scopes.flatMap(([owner, path, kind, reference]) => operations.map(name => {
    const scope = path.split('/').reduce((value, key) => value?.[key], roots[owner]);
    assert.ok(Array.isArray(scope?.oneOf), `missing ${owner}/${path} expression scope`);
    const templates = scope.oneOf.filter(candidate => named(candidate, 'len', kind));
    assert.equal(templates.length, 1, `unique local len template at ${owner}/${path}`);
    assert.deepEqual(templates[0], shape('len', kind, reference),
      `closed local len template at ${owner}/${path}`);
    const matches = scope.oneOf.filter(candidate => named(candidate, name, kind));
    assert.ok(matches.length <= 1, `duplicate ${kind} ${name} shape at ${owner}/${path}`);
    counts[kind]++;
    return {scope, kind, name, previous: matches[0], expected: shape(name, kind, reference)};
  }));
  assert.deepEqual(counts, {source: 91, node: 39}, 'direct trigonometric schema embedding count');
  const ownedScopes = new Set(plans.map(plan => plan.scope));
  for (const root of [expressions.schemas, protocol.artifact_schemas]) walk(root, value => {
    if (!Array.isArray(value.oneOf)) return;
    for (const kind of ['source', 'node']) {
      if (value.oneOf.some(candidate => named(candidate, 'len', kind) || operations.some(name => named(candidate, name, kind)))) {
        assert.ok(ownedScopes.has(value), `unregistered ${kind} expression scope`);
      }
    }
  });
  assert.ok(expressions.laws && protocol.artifact_schema_cids,
    'existing expression law and protocol identity owners');
  for (const {scope, kind, name, previous, expected} of plans) {
    if (write) {
      if (previous) scope.oneOf[scope.oneOf.indexOf(previous)] = expected;
      else scope.oneOf.push(expected);
    } else assert.deepEqual(previous, expected, `stale ${kind} ${name} shape`);
  }
  const grammarHash = createHash('sha256').update(grammar).digest('hex');
  if (write) {
    for (const name of operations) expressions.laws[name] = structuredClone(directTrigLaws[name]);
    expressions.grammar_sha256 = grammarHash;
  } else {
    for (const name of operations) assert.deepEqual(expressions.laws[name], directTrigLaws[name], `stale ${name} law`);
    assert.equal(expressions.grammar_sha256, grammarHash, 'stale expression grammar pin');
  }
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) {
    if (write) protocol.artifact_schema_cids[name] = machineCid(schema);
    else assert.equal(protocol.artifact_schema_cids[name], machineCid(schema), `stale ${name} schema CID`);
  }
  if (write) protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas), 'stale artifact registry CID');
  return counts;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const paths = ['spec/contracts/actql-expressions.json', 'spec/contracts/actql-protocol-schemas.json'];
  const bodies = paths.map(path => JSON.parse(readFileSync(path, 'utf8')));
  const grammar = readFileSync(bodies[0].grammar, 'utf8');
  if (process.argv.includes('--write')) {
    updateDirectTrigContracts(...bodies, grammar, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  console.log('GoogleSQL finite Number direct trigonometric contracts verified:', updateDirectTrigContracts(...bodies, grammar));
}
