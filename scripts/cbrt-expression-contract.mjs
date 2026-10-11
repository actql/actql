import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const cbrtLaws = {
  cbrt: {
    signature: 'Exactly one finite binary64 Number operand; the result is Number and is nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC, Decimal or non-finite overload is admitted.',
    typing: 'Return Number with the operand nullability. Type-check the sole operand without evaluating it; the finite Number domain admits positive, negative, zero, subnormal and largest finite magnitudes.',
    value: 'Return the real cube root, including negative inputs. Either zero sign produces canonical positive zero. NULL produces NULL. There is no additional value-domain failure for an admitted finite Number; reject non-finite operands and preserve the existing arithmetic failure for an unexpected non-finite result.',
    algorithm: "Use the same pinned portable MoonBit core Double cbrt primitive in src/scalar_numeric_kernel on JS, WebAssembly and Native (source manifest sha256:254e734f8e44242b835b0a6c2505011b5eea6b9883dfa3db8c1b74e061757e0b), through the existing canonical scalar owner and finite-result validation. Do not substitute pow(x, 1/3), logarithmic reconstruction or a frontend/Host evaluator. The compatibility target is the GoogleSQL finite-FLOAT64 cube-root operation. Preserve every existing numeric accuracy and exception contract. Identical admitted inputs and selected semantic contracts preserve exact logical Number bits across targets; no live-BigQuery last-bit equivalence is claimed.",
    evaluation: 'Demand the sole child exactly once and preserve its failure before strict NULL propagation. Preserve enclosing lazy demand, retained roots, logical operand/result and control charges, live-value and workspace limits, and cooperative cancellation. Reuse the common continuation and canonical unary scalar evaluator.',
    identity: 'The closed source is {cbrt: expression} and the closed machine node is {op: cbrt, body: expression_node}. CBRT selects this same direct unary operation. Retain the node and sole child without folding or duplication, including constants; earlier pinned contract bodies retain their identities.',
  },
};
const operations = Object.keys(cbrtLaws);

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
  for (const name of operations) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
    assert.equal([...productions[0][1].matchAll(new RegExp(`"${escaped}"`, 'gu'))].length, 1,
      `${name} missing or duplicated in common function_name production`);
  }
}

export function updateCbrtContracts(expressions, protocol, grammar, write = false) {
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
  assert.deepEqual(counts, {source: 7, node: 3}, 'CBRT schema embedding count');
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
    for (const name of operations) expressions.laws[name] = structuredClone(cbrtLaws[name]);
    expressions.grammar_sha256 = grammarHash;
  } else {
    for (const name of operations) assert.deepEqual(expressions.laws[name], cbrtLaws[name], `stale ${name} law`);
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
    updateCbrtContracts(...bodies, grammar, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  console.log('GoogleSQL finite Number CBRT contracts verified:', updateCbrtContracts(...bodies, grammar));
}
