import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {registerExpressionFragment, checkRegistration} from './expression-fragment-registration.mjs';

export const unaryTimestampLaw = {
  signature: 'The closed unary try_timestamp choice consumes an original String or admitted Timestamp and returns nullable Timestamp. Immediate NULL propagates. No Number, Signed64, Decimal, Boolean, Date, structured, Any or unresolved-domain promotion.',
  string: 'Use the same canonical UTC Z/calendar admission as CAST/to_timestamp, retaining the existing 3..9 fractional precision and canonical spelling. Only malformed Timestamp spelling or calendar input returns NULL. No trimming, inferred timestamp pattern, offset normalization, Host Date, locale or clock.',
  identity: 'Preserve the admitted Timestamp value without manufacturing String input, a pattern, a parser profile or a Host envelope. Retain the authored try_timestamp node and original operand in source, lowering, emission and re-admission.',
  demand: 'Demand the original child exactly once under the same scalar/Run/current/work/value/root and workspace owners. Child, cancellation, bounds, allocation, engine and retirement failures propagate; they never become NULL. Surrounding lazy demand remains unchanged.',
  compatibility: 'Unary has the closed body {value}; explicit patterned try_timestamp retains the distinct closed {value,pattern} body, prior bytes, pattern-first validation and all original profile/envelope duties. An explicit NULL or malformed pattern is never an omitted pattern. This does not widen operational clocks or issue authority.',
};
export const unaryTimestampProfileException = ' Unary try_timestamp is the existing bounded canonical Timestamp conversion, not a patterned text-time evaluation. Its original String conversion retains real scalar work and bounds; admitted Timestamp identity has no invented String/pattern envelope. Explicit value+pattern occurrences keep every existing pattern/profile/envelope obligation.';

const scopes = [
  ['expression', 'schemas/expression/$defs/expression', 'source'],
  ['expression', 'schemas/expression_node/$defs/expression', 'node'],
  ['expression', 'schemas/fragment/$defs/source_expression', 'source'],
  ['expression', 'schemas/fragment/$defs/machine_expression', 'node'],
  ['expression', 'schemas/predicate_consumer/$defs/source_expression', 'source'],
  ['expression', 'schemas/predicate_consumer/$defs/machine_expression', 'node'],
  ...['executable_plan', 'plan_document'].flatMap(name => ['predicate', 'value_expression'].map(part =>
    ['protocol', `artifact_schemas/${name}/${name === 'plan_document' ? 'properties/plan/' : ''}properties/execution_material/properties/program/$defs/${part}`, 'source'])),
];
const read = name => JSON.parse(readFileSync(name, 'utf8'));
const bodyOf = (value, kind) => kind === 'source' ? value.properties?.try_timestamp
  : value.properties?.op?.const === 'try_timestamp' ? value.properties.body : undefined;

export function updateUnaryTimestampContracts(expression, protocol, scalar, write = false) {
  const roots = {expression, protocol}, counts = {source: 0, node: 0};
  const plans = scopes.map(([owner, path, kind]) => {
    const scope = path.split('/').reduce((value, key) => value?.[key], roots[owner]);
    assert.ok(Array.isArray(scope?.oneOf), `missing existing scope ${owner}/${path}`);
    const matches = scope.oneOf.filter(value => bodyOf(value, kind));
    const patterned = matches.filter(value => bodyOf(value, kind).required?.join(',') === 'value,pattern');
    assert.equal(patterned.length, 1, 'one unchanged explicit-pattern alternative');
    const originalBody = bodyOf(patterned[0], kind);
    assert.equal(originalBody.additionalProperties, false);
    assert.ok(originalBody.properties.pattern && originalBody.properties.value);
    const body = {type: 'object', additionalProperties: false, required: ['value'],
      properties: {value: structuredClone(originalBody.properties.value)}};
    const expected = kind === 'source'
      ? {type: 'object', additionalProperties: false, required: ['try_timestamp'], properties: {try_timestamp: body}}
      : {type: 'object', additionalProperties: false, required: ['op', 'body'], properties: {op: {const: 'try_timestamp'}, body}};
    const unary = matches.filter(value => bodyOf(value, kind).required?.join(',') === 'value');
    assert.ok(unary.length <= 1 && matches.length === 1 + unary.length, 'closed two-choice timestamp operation');
    if (unary.length) assert.deepEqual(unary[0], expected);
    counts[kind]++;
    return {scope, expected, unary};
  });
  assert.deepEqual(counts, {source: 7, node: 3});
  for (const {scope, expected, unary} of plans) {
    if (!unary.length) { assert.ok(write, 'missing closed unary choice'); scope.oneOf.push(expected); }
  }
  if (write) {
    expression.laws.try_timestamp_unary = structuredClone(unaryTimestampLaw);
    scalar.conversion_truth_table.try_timestamp_unary = structuredClone(unaryTimestampLaw);
    for (const name of ['pure_profile_admission', 'profile_binding']) {
      if (expression.laws[name].includes(unaryTimestampProfileException)) continue;
      const marker = ' A try_number occurrence whose original checked operand is Number';
      const at = expression.laws[name].indexOf(marker);
      assert.ok(at >= 0, 'retain complete earlier Number identity exception');
      expression.laws[name] = expression.laws[name].slice(0, at) + unaryTimestampProfileException + expression.laws[name].slice(at);
    }
  } else {
    assert.deepEqual(expression.laws.try_timestamp_unary, unaryTimestampLaw);
    assert.deepEqual(scalar.conversion_truth_table.try_timestamp_unary, unaryTimestampLaw);
    for (const name of ['pure_profile_admission', 'profile_binding']) assert.ok(expression.laws[name].includes(unaryTimestampProfileException));
  }
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) {
    if (write) protocol.artifact_schema_cids[name] = machineCid(schema);
    else assert.equal(protocol.artifact_schema_cids[name], machineCid(schema));
  }
  if (write) protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas));
  return counts;
}

export function verifyUnaryTimestampContracts(write = false) {
  const paths = ['spec/contracts/actql-expressions.json', 'spec/contracts/actql-protocol-schemas.json', 'spec/dependencies/aoa-rela-scalar-laws.json'];
  const bodies = paths.map(read), counts = updateUnaryTimestampContracts(...bodies, write);
  const aoaPath = 'spec/contracts/actql-aoa.json', aoa = read(aoaPath), registry = read(aoa.pipeline_registry_file);
  if (write) {
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
    aoa.expression_contract_cid = machineCid(bodies[0]);
    aoa.rela_scalar_law_manifest_cid = machineCid(bodies[2]);
    registerExpressionFragment(aoa, bodies[0], registry);
    writeFileSync(aoa.pipeline_registry_file, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(aoaPath, JSON.stringify(aoa, null, 2) + '\n');
  }
  checkRegistration(aoa, bodies[0], registry);
  return counts;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log('Unary canonical TRY_TIMESTAMP contract:', verifyUnaryTimestampContracts(process.argv.includes('--write')));
}
