import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const repeatReverseLaws = {
  repeat: {
    signature: 'Exactly two ordered operands: STRING followed by finite Number. Return String with the union of operand nullabilities. Untyped NULL takes the unique positional signature. No implicit conversion, BYTES, Decimal or distinct INT64 overload is admitted.',
    typing: 'Return an otherwise unconstrained String; drop input minimum and maximum length bounds because a dynamic count can be zero or expand the input. Do not evaluate the count during typing.',
    value: 'After strict NULL propagation, require a nonnegative integral Number count. This explicitly adapts the GoogleSQL INT64 count to the existing finite binary64 domain, without a safe-integer or INT64 cap. Reject negative and fractional counts before an empty-input shortcut. A zero count or an empty String returns empty, including empty input with a very large valid count. Otherwise concatenate the complete input scalar sequence count times without normalization.',
    evaluation: 'Demand both children exactly once, left to right, and preserve any child failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value/output-byte and workspace limits, and cooperative cancellation. Check the non-null count domain before any bounded integer conversion. Prove a nonempty repetition count fits bounded execution using existing storage limits before narrowing. Admit complete output storage through existing resource owners before allocation; do not impose a new scalar count cap or decrement a huge binary64 count. Reuse the common continuation; no frontend or Host evaluator is introduced.',
    identity: 'The closed source is {repeat: [expression, expression]} and the closed machine node is {op: repeat, body: [expression_node, expression_node]}. REPEAT selects this same ordered binary operation. Retain the node and each child without folding or duplication; earlier pinned contract bodies retain their identities.',
  },
  reverse: {
    signature: 'Exactly one STRING operand; return String with the operand nullability. Untyped NULL takes the unique STRING signature. No implicit conversion, BYTES or distinct INT64 overload is admitted.',
    typing: 'Preserve the complete input String contract, including min_length, max_codepoints and max_utf8_bytes: reversal changes neither scalar count nor encoded byte count.',
    value: 'Return the input Unicode scalar sequence in reverse order. Preserve every complete scalar, including astral characters and U+0000, without normalization or grapheme segmentation. Do not reverse UTF-16 code units or encoded bytes. Empty input returns empty. NULL produces NULL.',
    evaluation: 'Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value/output-byte and workspace limits, and cooperative cancellation. Admit complete output storage before construction and reuse the common continuation; no frontend or Host evaluator is introduced.',
    identity: 'The closed source is {reverse: expression} and the closed machine node is {op: reverse, body: expression_node}. REVERSE selects this same direct unary operation. Retain the node and sole child without folding or duplication; earlier pinned contract bodies retain their identities.',
  },
};
const operations = Object.keys(repeatReverseLaws);

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
  const body = name === 'repeat' ? {type: 'array', minItems: 2, maxItems: 2, items: child} : child;
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

export function updateRepeatReverseContracts(expressions, protocol, grammar, write = false) {
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
  assert.deepEqual(counts, {source: 14, node: 6}, 'REPEAT/REVERSE schema embedding count');
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
    for (const name of operations) expressions.laws[name] = structuredClone(repeatReverseLaws[name]);
    expressions.grammar_sha256 = grammarHash;
  } else {
    for (const name of operations) assert.deepEqual(expressions.laws[name], repeatReverseLaws[name], `stale ${name} law`);
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
    updateRepeatReverseContracts(...bodies, grammar, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  console.log('GoogleSQL STRING repeat/reverse contracts verified:', updateRepeatReverseContracts(...bodies, grammar));
}
