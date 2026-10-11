import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const unicodeScalarLaws = {
  byte_length: {
    signature: 'Exactly one STRING operand; return Number with the operand nullability. Untyped NULL takes the unique STRING signature. No implicit conversion, BYTES or distinct INT64 overload is admitted.',
    value: 'Return the exact UTF-8 byte count of the complete String, with zero for empty input. Count encoded scalar bytes rather than UTF-16 code units, scalar count, grapheme clusters or JSON escaping. Preserve input Unicode scalars without normalization. NULL produces NULL.',
    evaluation: 'Demand the sole child exactly once before strict NULL propagation. Preserve child failures, enclosing lazy demand, retained roots, logical operand/result and control charges, live-value/output-byte and workspace limits, and cooperative cancellation. Reuse the common continuation; no frontend or Host evaluator is introduced.',
    identity: 'The closed source is {byte_length: expression} and the closed machine node is {op: byte_length, body: expression_node}. BYTE_LENGTH and OCTET_LENGTH select this same unary operation, including expression-text aliases. No separate octet_length canonical node is admitted. Retain the node and sole child without folding or duplication; earlier pinned contract bodies retain their identities.',
  },
  unicode: {
    signature: 'Exactly one STRING operand; return Number with the operand nullability. Untyped NULL takes the unique STRING signature. No implicit conversion, BYTES or distinct INT64 overload is admitted.',
    value: 'Return the Unicode scalar code point of the first scalar. Empty input and a first U+0000 both return zero. Astral characters return their complete code point, not a UTF-16 surrogate or UTF-8 byte. Combining marks are not normalized or segmented as graphemes. NULL produces NULL.',
    evaluation: 'Demand the sole child exactly once before strict NULL propagation. Preserve child failures, enclosing lazy demand, retained roots, logical operand/result and control charges, live-value/output-byte and workspace limits, and cooperative cancellation. Reuse the common continuation; no frontend or Host evaluator is introduced.',
    identity: 'The closed source is {unicode: expression} and the closed machine node is {op: unicode, body: expression_node}. UNICODE selects this same unary operation. Retain the node and sole child without folding or duplication; earlier pinned contract bodies retain their identities.',
  },
  chr: {
    typing: 'The result has max_codepoints 1 and max_utf8_bytes 4, with no invented minimum length; zero can produce empty. Derive these intrinsic maxima without evaluating the child.',
    signature: 'Exactly one finite Number operand; return String with the operand nullability. Untyped NULL takes the unique Number signature. No implicit conversion, Decimal, BYTES or distinct INT64 overload is admitted.',
    value: 'After strict NULL propagation, require an integral Number in [0, 55295] or [57344, 1114111]. Reject fractions, negative values, surrogate code points and values above U+10FFFF without truncation or wrapping. Zero returns the empty String; each other admitted code point returns exactly its one Unicode scalar, including noncharacters. NULL produces NULL.',
    evaluation: 'Demand the sole child exactly once, preserve its failure and enclosing lazy demand, and validate the non-null code point before bounded conversion. Preserve retained roots, logical operand/result and control charges, live-value/output-byte and workspace limits, and cooperative cancellation. Admit the complete String output bytes and storage before construction; no frontend or Host evaluator is introduced.',
    identity: 'The closed source is {chr: expression} and the closed machine node is {op: chr, body: expression_node}. CHR selects this same unary operation. Retain the node and sole child without folding or duplication; earlier pinned contract bodies retain their identities.',
  },
};
const operations = Object.keys(unicodeScalarLaws);

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
  const body = {$ref: `#/$defs/${reference}`};
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
  for (const name of [...operations, 'octet_length']) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
    assert.equal([...productions[0][1].matchAll(new RegExp(`"${escaped}"`, 'gu'))].length, 1,
      `${name} missing or duplicated in common function_name production`);
  }
}

export function updateUnicodeScalarContracts(expressions, protocol, grammar, write = false) {
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
    assert.ok(!scope.oneOf.some(candidate => named(candidate, 'octet_length', kind)), 'alias has no canonical schema');
    return {scope, kind, name, previous: matches[0], expected: shape(name, kind, reference)};
  }));
  assert.deepEqual(counts, {source: 21, node: 9}, 'Unicode scalar schema embedding count');
  const ownedScopes = new Set(plans.map(plan => plan.scope));
  for (const root of [expressions.schemas, protocol.artifact_schemas]) walk(root, value => {
    if (!Array.isArray(value.oneOf)) return;
    for (const kind of ['source', 'node']) {
      if (value.oneOf.some(candidate => named(candidate, 'len', kind) || [...operations, 'octet_length'].some(name => named(candidate, name, kind)))) {
        assert.ok(ownedScopes.has(value), `unregistered ${kind} expression scope`);
      }
    }
  });
  assert.ok(expressions.laws && protocol.artifact_schema_cids,
    'existing expression law and protocol identity owners');
  assert.ok(!Object.hasOwn(expressions.laws, 'octet_length'), 'alias has no canonical law');
  for (const {scope, kind, name, previous, expected} of plans) {
    if (write) {
      if (previous) scope.oneOf[scope.oneOf.indexOf(previous)] = expected;
      else scope.oneOf.push(expected);
    } else assert.deepEqual(previous, expected, `stale ${kind} ${name} shape`);
  }
  const grammarHash = createHash('sha256').update(grammar).digest('hex');
  if (write) {
    for (const name of operations) expressions.laws[name] = structuredClone(unicodeScalarLaws[name]);
    expressions.grammar_sha256 = grammarHash;
  } else {
    for (const name of operations) assert.deepEqual(expressions.laws[name], unicodeScalarLaws[name], `stale ${name} law`);
    assert.ok(!Object.hasOwn(expressions.laws, 'octet_length'), 'alias has no canonical law');
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
    updateUnicodeScalarContracts(...bodies, grammar, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  console.log('GoogleSQL STRING byte/code-point contracts verified:', updateUnicodeScalarContracts(...bodies, grammar));
}
