import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const substringLaw = {
  signature: 'STRING value and safe-integer-valued number start, with an optional safe-integer-valued number length. Result is STRING, nullable exactly when any supplied operand is nullable. Untyped NULL takes the unique positional signature. Retain input max_codepoints and max_utf8_bytes ceilings, but not min_length; do not evaluate length to derive a type. No implicit conversion or BYTES overload is admitted. The number domain is ActQL finite binary64, not the full GoogleSQL INT64 domain.',
  value: 'Count Unicode scalars. Positive start is one-based. Zero or a start smaller than negative input scalar length selects the first scalar. Other negative starts count backward from the end, with -1 selecting the last scalar. A start beyond the input returns empty. Omitted length retains the remaining suffix; zero length returns empty; positive length retains at most that many scalars. Negative, fractional or unsafe length, or fractional or unsafe start, fails on a demanded non-null call. Clamp before index addition so safe-integer endpoints cannot overflow. Preserve retained scalars exactly, including NUL, astral, combining and line-break sequences, without normalization.',
  evaluation: 'Evaluate value, start and supplied length exactly once in authored order. Apply strict NULL after all supplied children succeed and before index-domain checks. A NULL child never suppresses a later demanded child failure. Preserve enclosing lazy demand, first-failure order, cancellation, workspace, logical work, live-value and output-byte limits. Cooperative scalar counting, boundary location, exact sizing and construction use the existing scalar expression continuation; no Host substring call, secondary evaluator or result remeasurement substitutes for the owner.',
  identity: 'The common source is {substring: {value, start, length?}} and the machine node is {op: substring, body: {value, start, length?}}. Preserve omitted length as omitted, distinct from explicit NULL or a supplied length. SQL SUBSTR and SUBSTRING are aliases of this common operation. This current initial-0.1 contract supersedes the inherited fixed-three-argument interval and text-time profile membership for substring. Earlier pinned bodies keep their original meaning and CIDs.',
  admission: 'Substring is an ordinary scalar operation, requiring no text-time profile, HostEnvelope or text-time policy. Nested profile operations retain their own profile, pattern, envelope and input-preflight obligations, including in unselected branches. Known input String maxima remain conservative output maxima; otherwise surrounding profile operations retain RuntimePreflight under their selected Host limits. No substring-specific profile extent is invented. Previously derived profile extents across a substring may fall back to this conservative preflight; this ownership migration does not claim identical plan admission for every earlier nested profile expression.',
};
const envelopeLaw = 'actql-text-time-bound-laws/0.1 retains pinned Unicode/regex/time bound laws for current profile operations. split_part output ceiling equals input bytes. utf8_truncate uses min(input bytes,max_bytes) for a bound nonnegative safe-integer literal limit, otherwise input bytes. Substring is owned by its scalar law, not a text-time envelope. Bound arithmetic is exact. Parent profile expressions consume child checked extents or retained runtime input preflight. Envelope self-CID excludes only envelope_cid; arguments_cid binds canonical argument subtrees. Demand predicates are outer-to-inner, with earlier branch not_true, selected branch true and coalesce null tests; aggregate arguments begin with their own filter true. No re-evaluation of demand values; no enforcement on undemanded rows; input admission and whole-unit scopes remain enforced.';
const operations = ['split_part', 'utf8_truncate', 'try_number', 'parse_timestamp', 'format_timestamp', 'regex_match', 'regex_extract', 'regex_replace', 'nfkc', 'case_fold', 'try_timestamp'];

function walk(value, fn) {
  if (!value || typeof value !== 'object') return;
  fn(value);
  for (const child of Object.values(value)) walk(child, fn);
}
function namedShape(shape, kind) {
  return kind === 'source' ? shape.required?.length === 1 && shape.required[0] === 'substring'
    : shape.properties?.op?.const === 'substring';
}
function currentShapes(root, write) {
  const counts = {source: 0, node: 0, envelopes: 0};
  walk(root, value => {
    if (Array.isArray(value.oneOf)) for (const kind of ['source', 'node']) {
      const matches = value.oneOf.filter(shape => namedShape(shape, kind));
      if (!matches.length) continue;
      assert.equal(matches.length, 1, `duplicate ${kind} substring alternative`);
      const sibling = value.oneOf.filter(shape => kind === 'source'
        ? shape.required?.length === 1 && shape.required[0] === 'split_part'
        : shape.properties?.op?.const === 'split_part');
      assert.equal(sibling.length, 1, `missing ${kind} local expression scope`);
      const ref = (kind === 'source' ? sibling[0].properties.split_part
        : sibling[0].properties.body).properties.value.$ref;
      assert.equal(typeof ref, 'string');
      const body = {type: 'object', additionalProperties: false, required: ['value', 'start'],
        properties: {value: {$ref: ref}, start: {$ref: ref}, length: {$ref: ref}}};
      const expected = kind === 'source'
        ? {type: 'object', additionalProperties: false, required: ['substring'], properties: {substring: body}}
        : {type: 'object', additionalProperties: false, required: ['op', 'body'], properties: {op: {const: 'substring'}, body}};
      if (write) value.oneOf[value.oneOf.indexOf(matches[0])] = expected;
      else assert.deepEqual(matches[0], expected, `stale ${kind} substring shape`);
      counts[kind]++;
    }
    const operation = value.properties?.operation;
    if (operation?.enum?.includes('split_part') && operation.enum.includes('regex_replace')) {
      if (write) operation.enum = [...operations];
      else assert.deepEqual(operation.enum, operations, 'substring is not a current profile envelope');
      counts.envelopes++;
    }
  });
  return counts;
}
function profileShapes(production, write) {
  const expression = production.schemas.text_time_expression;
  const barrier = production.schemas.text_time_evaluation_barrier;
  for (const shape of [expression, barrier.properties.expressions.additionalProperties]) {
    assert.ok(Array.isArray(shape.oneOf));
    if (write) shape.oneOf = shape.oneOf.filter(value => !namedShape(value, 'source'));
    assert.equal(shape.oneOf.filter(value => namedShape(value, 'source')).length, 0,
      'substring remains in the current text-time profile source schema');
    assert.deepEqual(shape.oneOf.map(value=>value.required?.[0]).sort(), [...operations].sort());
  }
  for (const shape of [production.schemas.text_time_evaluation_envelope,
    barrier.properties.evaluations.items]) {
    if (write) shape.properties.operation.enum = [...operations];
    else assert.deepEqual(shape.properties.operation.enum, operations);
  }
  for (const [name, schema] of Object.entries(production.schemas)) {
    if (write) production.schema_cids[name] = machineCid(schema);
    else assert.equal(production.schema_cids[name], machineCid(schema), `stale ${name} pin`);
  }
  const {registry_cid: previous, ...body} = production;
  if (write) production.registry_cid = machineCid(body);
  else assert.equal(previous, machineCid(body), 'stale production profile registry');
}
export function updateSubstringContracts(expressions, protocol, production, write = false) {
  const current = currentShapes(expressions.schemas, write);
  const embedded = currentShapes(protocol.artifact_schemas, write);
  assert.deepEqual(current, {source: 3, node: 3, envelopes: 3});
  assert.deepEqual(embedded, {source: 4, node: 0, envelopes: 0});
  profileShapes(production, write);
  if (write) {
    expressions.laws.substring = structuredClone(substringLaw);
    expressions.laws.envelopes = envelopeLaw;
  } else {
    assert.deepEqual(expressions.laws.substring, substringLaw);
    assert.equal(expressions.laws.envelopes, envelopeLaw);
  }
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) {
    if (write) protocol.artifact_schema_cids[name] = machineCid(schema);
    else assert.equal(protocol.artifact_schema_cids[name], machineCid(schema));
  }
  if (write) protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas));
  return {current, embedded};
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const paths = ['spec/contracts/actql-expressions.json', 'spec/contracts/actql-protocol-schemas.json',
    'spec/contracts/actql-production-profile-schemas.json'];
  const bodies = paths.map(path => JSON.parse(readFileSync(path, 'utf8')));
  if (process.argv.includes('--write')) {
    updateSubstringContracts(...bodies, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  console.log('GoogleSQL STRING SUBSTR/SUBSTRING contracts verified:', updateSubstringContracts(...bodies));
}
