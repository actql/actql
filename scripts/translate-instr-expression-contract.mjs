import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const translateInstrLaws = {
  "translate": {
    "signature": "Exactly three ordered STRING operands: value, source and target. Return String with the union of all operand nullabilities. Untyped NULL takes the unique STRING signature. No implicit conversion, BYTES, collation or regex overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Preserve only the value input max_codepoints bound when present; drop min_length because deletion can empty the result and max_utf8_bytes because substitution can expand encoded width.",
    "value": "After all demanded children succeed and strict NULL propagation, translate each original Unicode scalar at most once using its index in source to select the corresponding target scalar. Leave absent scalars unchanged, delete source scalars with no corresponding target, and ignore surplus target scalars. Reject every duplicate source scalar even when unused or when the value is empty. Mapping is simultaneous, not cascading. Preserve exact astral scalars, combining marks and NUL without normalization or grapheme segmentation.",
    "evaluation": "Demand every child exactly once in authored left-to-right order and preserve any child failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value/output-byte and workspace limits, and cooperative cancellation. Admit scratch and complete output storage through existing resource owners before allocation; do not add an arbitrary scalar cap or a frontend/Host evaluator.",
    "identity": "The closed source is {translate: [value, source, target]} and the closed machine node is {op: translate, body: [value_node, source_node, target_node]}. TRANSLATE selects this same ordered ternary operation. Retain every authored child without folding or duplication, including constants; earlier pinned contract bodies retain their identities."
  },
  "instr": {
    "signature": "Two to four ordered operands: STRING value, STRING subvalue, optional finite Number position and optional finite Number occurrence. Return Number with the union of all supplied operand nullabilities. Untyped NULL takes each unique positional signature. No implicit conversion, BYTES, collation, regex or distinct INT64 overload is admitted.",
    "typing": "Type-check every authored operand without evaluating it. Return Number, nullable exactly when any supplied operand is nullable. Omitted position and occurrence each mean one at evaluation; omission does not add an operand or narrow the type.",
    "value": "After all demanded children succeed and strict NULL propagation, require integral nonzero position and integral positive occurrence in the existing finite binary64 Number domain. This explicitly adapts GoogleSQL INT64 parameters without a safe-integer or INT64 cap. Match exact Unicode scalar sequences; return the 1-based scalar start position of the requested occurrence, or zero if unreachable. Positive position searches forward from that 1-based start; negative position searches backward from scalar length plus position plus one. Count overlapping matches separately. For empty subvalue, match the length-plus-one boundaries: positive position starts at that boundary, while negative position starts at scalar length plus position plus two. Each further occurrence advances one boundary in the search direction; return zero beyond either edge. Empty value and empty subvalue return one at default position/occurrence. Preserve exact strings without normalization.",
    "evaluation": "Demand every supplied child exactly once in authored left-to-right order, preserving later child errors after an earlier NULL, before strict NULL propagation and operation-domain checks. Validate Number integrality and sign before shortcuts or bounded integer conversion. Compare valid positions and occurrences against bounded scalar/boundary counts before narrowing; huge unreachable integral values return zero without huge binary64 decrement loops. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation through existing owners. No new scalar cap, frontend evaluator or Host evaluator is introduced.",
    "identity": "The closed source is {instr: [value, subvalue, position?, occurrence?]} and the closed machine node retains the corresponding two-to-four ordered expression nodes in {op: instr, body: [...]}. INSTR selects this same operation. Preserve authored omission and explicit defaults as distinct identities; do not insert synthetic default children, fold constants, duplicate children or rewrite INSTR as STRPOS. Earlier pinned contract bodies retain their identities."
  }
};
const operations = Object.keys(translateInstrLaws);

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
  const body = name === 'translate' ? {type: 'array', minItems: 3, maxItems: 3, items: child}
    : name === 'instr' ? {type: 'array', minItems: 2, maxItems: 4, items: child} : child;
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

export function updateTranslateInstrContracts(expressions, protocol, grammar, write = false) {
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
  assert.deepEqual(counts, {source: 14, node: 6}, 'TRANSLATE/INSTR schema embedding count');
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
    for (const name of operations) expressions.laws[name] = structuredClone(translateInstrLaws[name]);
    expressions.grammar_sha256 = grammarHash;
  } else {
    for (const name of operations) assert.deepEqual(expressions.laws[name], translateInstrLaws[name], `stale ${name} law`);
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
    updateTranslateInstrContracts(...bodies, grammar, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  console.log('GoogleSQL STRING translate/instr contracts verified:', updateTranslateInstrContracts(...bodies, grammar));
}
