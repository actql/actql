import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {checkOrderedRegistration} from './ordered-derive-contract.mjs';

const originalQueryTime = {
  "current_timestamp": {
    "signature": "Zero operands and a non-null Timestamp result. CURRENT_TIMESTAMP() and {current_timestamp:[]} select one canonical computation operation; static checking and compilation never sample a clock.",
    "value": "For one original query invocation, every demanded occurrence, row, fragment and continuation reads the same admitted Run definition created_at. Keep the actual canonical UTC precision without manufacturing finer digits.",
    "binding": "The same selected Host captures a fresh original wall-clock observation at new invocation admission, before dependent Source requests and execution. Existing preparation may retain that original before compilation; the final admitted Run definition must bind exactly the same created_at and checked Program, requests, compilation and invocation. A stale policy creation time, caller String, copied identity, generic callback or user flag is not that original.",
    "source": "Discharge declared query-time dependencies only from the same original invocation preparation and final Run binding. Preserve unresolved or foreign UnboundRequest refusal; resource_ref host_bindings retain their original meaning. The physical predicate projection and downstream evaluator use the same original without rewriting the authored graph, introducing a hidden Parameter or evaluating SQL in a Host.",
    "recovery": "Persist the admitted original through the same confirmed request Journal before dependent dispatch. Lookup, racing issuers and cold recovery use the winning saved Run, never a replacement sample or second Run. Distinct query-invocation scopes are not collapsed into one Run-level field. Old Runs without this operation retain their bytes.",
    "evaluation": "Preserve surrounding lazy demand, original root lifetimes, logical value charges, control/workspace limits and cancellation. A demanded expression without its original execution context is unavailable; do not fabricate a value. An undemanded branch performs no clock read.",
    "authority": "Query time is computation data only. It grants no Account, Source, Model, Effect, resource, expiry, retention or authorization-clock authority; operational clock contracts remain unchanged.",
    "identity": "The closed source is {current_timestamp:[]} and the closed machine node is {op:current_timestamp,body:[]}. Retain that zero-argument node in canonical emission; never fold it to an authored Timestamp literal. Earlier complete contract bodies keep their original identities.",
    "proof_status": "implementation-required-same-Run-Host-Source-and-recovery"
  }
};
export const fixedIntervalLaw = {
  signature: 'Timestamp and exact signed64 amount with a fixed literal unit ns|us|ms|s|m|h|d; result is Timestamp with strict operand nullability.',
  source: 'TIMESTAMP_ADD(value, INTERVAL amount UNIT), TIMESTAMP_SUB(value, INTERVAL amount UNIT), and Timestamp +/- INTERVAL amount UNIT lower to timestamp_add/sub(value, amount, literal_unit). DAY=24 hours; HOUR=60 minutes; MINUTE=60 seconds. No timezone, DST, month or year adjustment.',
  amount: 'The original integral source token is retained exactly, not parsed through Number. The immediate canonical decimal String atom receives signed64 context at this consumer; int64 fields and Parameters keep their nominal checked domain. Nonliteral Number, Decimal and Text do not promote. Full min/max remain exact and subtraction does not negate min_int64 in Int64.',
  duration: 'Multiply the exact signed integer by the fixed nanosecond factor without binary64 conversion; add/subtract with exact signed carry and preserve original fractional nanoseconds. Calendar/range overflow fails existing ArithmeticFailure.',
  demand: 'Preserve original left-to-right eager child evaluation, strict NULL, surrounding lazy demand, root leases, logical value/work accounting, bounded workspace and cancellation. No first-class unbounded Interval value or general int64 arithmetic overload.',
  compatibility: 'Existing date_add Number-bit duration law, short structured units, all former value/clock shapes and operational clock purposes are unchanged.',
  proof_status: 'implementation-required-original-context-and-supported-backend-consumers',
};
export const currentTimestampLaws = {
  ...originalQueryTime,
  timestamp_add: structuredClone(fixedIntervalLaw),
  timestamp_sub: structuredClone(fixedIntervalLaw),
};
type Operation = keyof typeof currentTimestampLaws;
const operations = Object.keys(currentTimestampLaws) as Operation[];
type Kind = 'source' | 'node';
type Scope = [owner: 'expressions' | 'protocol', path: string, kind: Kind, reference: string];
type Schema = {$ref?: string; type?: string; additionalProperties?: boolean; required?: string[];
  properties?: Record<string, Schema>; const?: unknown; oneOf?: Schema[];
  minItems?: number; maxItems?: number; items?: false; prefixItems?: Schema[]; enum?: string[]};
type Registration = Parameters<typeof checkOrderedRegistration>;
type Expressions = Registration[1] & {grammar: string; grammar_sha256: string;
  laws: Record<string, unknown>; schemas: Record<string, unknown>};
type Protocol = Registration[3] & {artifact_schemas: Record<string, unknown>;
  artifact_schema_cids: Record<string, string>; artifact_registry_cid: string};
type Scalar = {time: {operational_clocks: unknown; date_add: unknown;
  query_time?: typeof currentTimestampLaws.current_timestamp; fixed_interval?: typeof fixedIntervalLaw}};
const read = <Value,>(path: string): Value => JSON.parse(readFileSync(path, 'utf8'));

// These are the declared common-expression embeddings, not a global spelling
// replacement. Each child reference remains local to its owning schema scope.
const scopes: Scope[] = [
  ['expressions', 'schemas/expression/$defs/expression', 'source', 'expression'],
  ['expressions', 'schemas/expression_node/$defs/expression', 'node', 'expression'],
  ['expressions', 'schemas/fragment/$defs/source_expression', 'source', 'source_expression'],
  ['expressions', 'schemas/fragment/$defs/machine_expression', 'node', 'machine_expression'],
  ['expressions', 'schemas/predicate_consumer/$defs/source_expression', 'source', 'source_expression'],
  ['expressions', 'schemas/predicate_consumer/$defs/machine_expression', 'node', 'machine_expression'],
  ...['executable_plan', 'plan_document'].flatMap(artifact => {
    const prefix = artifact === 'plan_document' ? 'properties/plan/' : '';
    return ['predicate', 'value_expression'].map<Scope>(definition => ['protocol',
      `artifact_schemas/${artifact}/${prefix}properties/execution_material/properties/program/$defs/${definition}`,
      'source', 'value_expression']);
  }),
];
const named = (shape: Schema, name: string, kind: Kind) => kind === 'source'
  ? shape.required?.includes(name) || Object.hasOwn(shape.properties ?? {}, name)
  : shape.properties?.op?.const === name;
function shape(name: Operation | 'len', kind: Kind, reference: string): Schema {
  const body: Schema = name === 'len' ? {$ref: `#/$defs/${reference}`} : name === 'current_timestamp'
    ? {type: 'array', minItems: 0, maxItems: 0, items: false}
    : {type: 'array', minItems: 3, maxItems: 3, items: false,
      prefixItems: [{$ref: `#/$defs/${reference}`}, {$ref: `#/$defs/${reference}`},
        kind === 'source' ? {type: 'object', additionalProperties: false, required: ['literal'], properties: {literal: {enum: ['ns', 'us', 'ms', 's', 'm', 'h', 'd']}}} : {type: 'object', additionalProperties: false, required: ['op', 'body'], properties: {op: {const: 'literal'}, body: {enum: ['ns', 'us', 'ms', 's', 'm', 'h', 'd']}}}]};
  return kind === 'source'
    ? {type: 'object', additionalProperties: false, required: [name], properties: {[name]: body}}
    : {type: 'object', additionalProperties: false, required: ['op', 'body'],
      properties: {op: {const: name}, body}};
}
function walk(value: unknown, visit: (node: Schema) => void) {
  if (!value || typeof value !== 'object') return;
  visit(value as Schema);
  for (const child of Object.values(value)) walk(child, visit);
}
function requireGrammar(grammar: string) {
  // Comments or a similarly named function do not register a function token.
  const source = grammar.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const productions = [...source.matchAll(/\bfunction_name\s*=([^;]+);/gu)];
  assert.equal(productions.length, 1, 'one common function_name production');
  const body = productions[0]?.[1];
  assert.ok(body, 'common function_name body');
  for (const name of operations) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
    assert.equal([...body.matchAll(new RegExp(`"${escaped}"`, 'gu'))].length, 1,
      `${name} missing or duplicated in common function_name production`);
  }
}

export function updateCurrentTimestampContracts(expressions: Expressions, protocol: Protocol, grammar: string, write = false) {
  requireGrammar(grammar);
  const roots = {expressions, protocol};
  const counts = {source: 0, node: 0};
  // Preflight every scope and duplicate before mutating even in write mode.
  const plans = scopes.flatMap(([owner, path, kind, reference]) => operations.map(name => {
    const scope = path.split('/').reduce<unknown>((value, key) =>
      value && typeof value === 'object' ? (value as Record<string, unknown>)[key] : undefined, roots[owner]) as Schema | undefined;
    assert.ok(scope && Array.isArray(scope.oneOf), `missing ${owner}/${path} expression scope`);
    const choices = scope.oneOf;
    const templates = choices.filter(candidate => named(candidate, 'len', kind));
    assert.equal(templates.length, 1, `unique local len template at ${owner}/${path}`);
    assert.deepEqual(templates[0], shape('len', kind, reference),
      `closed local len template at ${owner}/${path}`);
    const matches = choices.filter(candidate => named(candidate, name, kind));
    assert.ok(matches.length <= 1, `duplicate ${kind} ${name} shape at ${owner}/${path}`);
    counts[kind]++;
    return {scope, choices, kind, name, previous: matches[0], expected: shape(name, kind, reference)};
  }));
  assert.deepEqual(counts, {source: 7 * operations.length, node: 3 * operations.length}, 'owned temporal schema embedding count');
  const ownedScopes = new Set(plans.map(plan => plan.scope));
  for (const root of [expressions.schemas, protocol.artifact_schemas]) walk(root, value => {
    if (!Array.isArray(value.oneOf)) return;
    for (const kind of ['source', 'node'] as const) {
      if (value.oneOf.some(candidate => named(candidate, 'len', kind) || operations.some(name => named(candidate, name, kind)))) {
        assert.ok(ownedScopes.has(value), `unregistered ${kind} expression scope`);
      }
    }
  });
  assert.ok(expressions.laws && protocol.artifact_schema_cids,
    'existing expression law and protocol identity owners');
  for (const {choices, kind, name, previous, expected} of plans) {
    if (write) {
      if (previous) choices[choices.indexOf(previous)] = expected;
      else choices.push(expected);
    } else assert.deepEqual(previous, expected, `stale ${kind} ${name} shape`);
  }
  const grammarHash = createHash('sha256').update(grammar).digest('hex');
  if (write) {
    for (const name of operations) expressions.laws[name] = structuredClone(currentTimestampLaws[name]);
    expressions.grammar_sha256 = grammarHash;
  } else {
    for (const name of operations) assert.deepEqual(expressions.laws[name], currentTimestampLaws[name], `stale ${name} law`);
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

export function updateQueryTimeScalarLaw(scalar: Scalar, write = false) {
  assert.ok(scalar.time && scalar.time.operational_clocks && scalar.time.date_add,
    'existing temporal and operational-clock owners');
  if (write) scalar.time.query_time = structuredClone(currentTimestampLaws.current_timestamp);
  else assert.deepEqual(scalar.time.query_time, currentTimestampLaws.current_timestamp,
    'stale query-time scalar law');
  if (write) scalar.time.fixed_interval = structuredClone(fixedIntervalLaw);
  else assert.deepEqual(scalar.time.fixed_interval, fixedIntervalLaw, 'stale exact fixed-interval law');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const expressionPath = 'spec/contracts/actql-expressions.json';
  const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
  const expressions = read<Expressions>(expressionPath), protocol = read<Protocol>(protocolPath);
  const grammar = readFileSync(expressions.grammar, 'utf8');
  const scalarPath = 'spec/dependencies/aoa-rela-scalar-laws.json';
  const aoaPath = 'spec/contracts/actql-aoa.json';
  const scalar = read<Scalar>(scalarPath);
  const aoa = read<Registration[0] & {rela_scalar_law_manifest_cid: string}>(aoaPath);
  const write = process.argv.includes('--write');
  const counts = updateCurrentTimestampContracts(expressions, protocol, grammar, write);
  updateQueryTimeScalarLaw(scalar, write);
  if (write) {
    aoa.rela_scalar_law_manifest_cid = machineCid(scalar);
    aoa.expression_contract_cid = machineCid(expressions);
  }
  assert.equal(aoa.rela_scalar_law_manifest_cid, machineCid(scalar), 'query-time scalar law pin');
  assert.equal(aoa.expression_contract_cid, machineCid(expressions), 'query-time expression law pin');
  if (write) {
    writeFileSync(expressionPath, JSON.stringify(expressions, null, 2) + '\n');
    writeFileSync(protocolPath, JSON.stringify(protocol, null, 2) + '\n');
    writeFileSync(scalarPath, JSON.stringify(scalar, null, 2) + '\n');
    writeFileSync(aoaPath, JSON.stringify(aoa, null, 2) + '\n');
  }
  if (!write) checkOrderedRegistration(aoa, expressions,
    read<Registration[2]>('spec/contracts/actql-stage-contracts.json'), protocol, read<Registration[4]>(aoa.pipeline_registry_file));
  console.log('Original query-time contracts verified:', counts);
}
