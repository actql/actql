import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const arrayOffsetLaws = {
  "array_offset": {
    "signature": "Exactly two operands in value-then-index order: a typed Array and a finite Number index. Preserve the item contract and return it conservatively nullable. Untyped NULL index takes the unique Number signature; an untyped NULL receiver needs array type context. No implicit conversion or distinct INT64 overload is added.",
    "value": "After both demanded children succeed, return NULL if either operand is NULL. Otherwise require an integral Number index. Indexes are zero-based. Negative or outside-array indexes fail evaluation. Fractional indexes fail evaluation. Compare in the Number domain against the bounded array length before integer narrowing, so huge integral offsets follow the same out-of-range rule rather than an arbitrary safe-integer limit.",
    "evaluation": "Evaluate receiver then index exactly once, eagerly. Child failures precede NULL propagation and index-domain checks. Retain enclosing lazy demand, root leases, logical work, live-value and workspace budgets, and cancellation through the existing typed-subscript owner. SAFE changes only the operation-owned out-of-range outcome, never suppressing failures in child expressions.",
    "identity": "The closed source is {array_offset: {value: receiver, index: offset}}; the closed machine node is {op: array_offset, body: {value: receiver_node, index: offset_node}}. SQL OFFSET and bare array indexing maps to this common owner without folding, duplication or frontend evaluation. Existing common subscript semantics and identities are unchanged."
  },
  "array_safe_offset": {
    "signature": "Exactly two operands in value-then-index order: a typed Array and a finite Number index. Preserve the item contract and return it conservatively nullable. Untyped NULL index takes the unique Number signature; an untyped NULL receiver needs array type context. No implicit conversion or distinct INT64 overload is added.",
    "value": "After both demanded children succeed, return NULL if either operand is NULL. Otherwise require an integral Number index. Indexes are zero-based. Negative or outside-array indexes return NULL. Fractional indexes fail evaluation. Compare in the Number domain against the bounded array length before integer narrowing, so huge integral offsets follow the same out-of-range rule rather than an arbitrary safe-integer limit.",
    "evaluation": "Evaluate receiver then index exactly once, eagerly. Child failures precede NULL propagation and index-domain checks. Retain enclosing lazy demand, root leases, logical work, live-value and workspace budgets, and cancellation through the existing typed-subscript owner. SAFE changes only the operation-owned out-of-range outcome, never suppressing failures in child expressions.",
    "identity": "The closed source is {array_safe_offset: {value: receiver, index: offset}}; the closed machine node is {op: array_safe_offset, body: {value: receiver_node, index: offset_node}}. SQL SAFE_OFFSET maps to this common owner without folding, duplication or frontend evaluation. Existing common subscript semantics and identities are unchanged."
  }
};
const operations = Object.keys(arrayOffsetLaws);

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
  const body = name === 'len' ? child : {type: 'object', additionalProperties: false,
    required: ['value', 'index'], properties: {value: child, index: child}};
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

export function updateArrayOffsetContracts(expressions, protocol, grammar, write = false) {
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
  assert.deepEqual(counts, {source: 14, node: 6}, 'array offset schema embedding count');
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
    for (const name of operations) expressions.laws[name] = structuredClone(arrayOffsetLaws[name]);
    expressions.grammar_sha256 = grammarHash;
  } else {
    for (const name of operations) assert.deepEqual(expressions.laws[name], arrayOffsetLaws[name], `stale ${name} law`);
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
    updateArrayOffsetContracts(...bodies, grammar, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  console.log('GoogleSQL array offset contracts verified:', updateArrayOffsetContracts(...bodies, grammar));
}
