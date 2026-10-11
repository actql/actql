import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const evaluation = 'Evaluate every supplied child once in authored order: value, length, then optional pattern. Apply strict NULL only after all children succeed and before length/pattern domain validation. A NULL or zero requested length never suppresses a demanded child failure. Preserve the first child failure, enclosing lazy demand, cancellation, control work, logical work, live-value/output-byte limits and workspace limits. Use the existing scalar text continuation for cooperative scalar counting, boundary location, exact output sizing and construction. Admit every output byte and storage unit before allocating the output buffer; never allocate a repeated pattern or whole intermediate output first.';
const commonSignature = 'STRING value and a safe-integer-valued finite binary64 number length. Untyped NULL takes the positional signature. Result is STRING with nullability from every supplied operand. No implicit conversions, BYTES, collation or full GoogleSQL INT64 domain is admitted.';
const scalarRule = 'Lengths count Unicode scalars, not bytes, UTF-16 units or grapheme clusters. Preserve astral characters, combining marks, NUL and line breaks exactly without normalization. Negative, nonintegral or unsafe lengths fail only on a demanded non-null call.';
export const padSidesLaws = {
  left: {
    signature: commonSignature + ' Exactly two arguments. Retain known input max_codepoints/max_utf8_bytes and drop min_length.',
    value: 'Return the requested leftmost scalars, or the entire input if length is at least the input scalar count. Zero length returns empty. ' + scalarRule,
    evaluation,
    identity: 'The closed source is {left: [value, length]}; the machine node is {op: left, body: [value, length]}. SQL LEFT selects this operation. Preserve both authored children without folding or duplication.',
  },
  right: {
    signature: commonSignature + ' Exactly two arguments. Retain known input max_codepoints/max_utf8_bytes and drop min_length.',
    value: 'Return the requested rightmost scalars, or the entire input if length is at least the input scalar count. Zero length returns empty. ' + scalarRule,
    evaluation,
    identity: 'The closed source is {right: [value, length]}; the machine node is {op: right, body: [value, length]}. SQL RIGHT selects this operation. Preserve both authored children; do not expand to a substring expression that evaluates length twice.',
  },
  lpad: {
    signature: commonSignature + ' Exactly two or three arguments, with optional STRING pattern. Drop input String bounds because a dynamic requested length can expand beyond them.',
    value: 'If requested length does not exceed input scalar length, return that many leftmost input scalars. Otherwise prepend repeated pattern scalars, using only the needed prefix of the last repetition, to produce the requested length. The omitted pattern is U+0020; an explicit empty pattern fails even for truncation, equal or zero length. ' + scalarRule,
    evaluation,
    identity: 'The closed source is {lpad: [value, length, pattern?]}; the machine node is {op: lpad, body: [value, length, pattern?]}. SQL LPAD selects this operation. Preserve omission as omission, distinct from explicit NULL or an explicit space pattern.',
  },
  rpad: {
    signature: commonSignature + ' Exactly two or three arguments, with optional STRING pattern. Drop input String bounds because a dynamic requested length can expand beyond them.',
    value: 'If requested length does not exceed input scalar length, return that many leftmost input scalars. Otherwise append repeated pattern scalars, using only the needed prefix of the last repetition, to produce the requested length. The omitted pattern is U+0020; an explicit empty pattern fails even for truncation, equal or zero length. ' + scalarRule,
    evaluation,
    identity: 'The closed source is {rpad: [value, length, pattern?]}; the machine node is {op: rpad, body: [value, length, pattern?]}. SQL RPAD selects this operation. Preserve omission as omission, distinct from explicit NULL or an explicit space pattern.',
  },
};
const names = Object.keys(padSidesLaws);
function visit(value, write, counts) {
  if (!value || typeof value !== 'object') return;
  if (Array.isArray(value.oneOf)) for (const kind of ['source', 'node']) {
    const named = (shape, name) => kind === 'source'
      ? shape.additionalProperties === false && shape.required?.length === 1 && shape.required[0] === name
      : shape.properties?.op?.const === name;
    const templates = value.oneOf.filter(shape => named(shape, 'replace'));
    if (!templates.length) continue;
    assert.equal(templates.length, 1, 'ambiguous local replace template');
    const array = templates[0].properties[kind === 'source' ? 'replace' : 'body'];
    assert.equal(array.type, 'array');
    assert.equal(typeof array.items.$ref, 'string', 'local child reference');
    for (const name of names) {
      const expected = structuredClone(templates[0]);
      if (kind === 'source') {
        expected.required = [name];
        expected.properties = {[name]: {type:'array', minItems:2,
          maxItems: name.endsWith('pad') ? 3 : 2, items: structuredClone(array.items)}};
      } else {
        expected.properties.op.const = name;
        expected.properties.body = {type:'array', minItems:2,
          maxItems: name.endsWith('pad') ? 3 : 2, items: structuredClone(array.items)};
      }
      const matches = value.oneOf.filter(shape => named(shape, name));
      assert.ok(matches.length <= 1, `duplicate ${name} shape`);
      if (write) {
        if (matches.length) value.oneOf[value.oneOf.indexOf(matches[0])] = expected;
        else value.oneOf.push(expected);
      } else assert.deepEqual(matches[0], expected, `stale ${kind} ${name} shape`);
      counts[name][kind]++;
    }
  }
  for (const child of Object.values(value)) visit(child, write, counts);
}
export function updatePadSidesContracts(expressions, protocol, grammar, write = false) {
  const counts = Object.fromEntries(names.map(name => [name,{source:0,node:0}]));
  for(const name of names) assert.match(grammar,new RegExp(`\\| "${name}"(?:\\s|\\|)`,'u'));
  visit(expressions.schemas,write,counts);
  visit(protocol.artifact_schemas,write,counts);
  for(const name of names) {
    assert.deepEqual(counts[name],{source:7,node:3},`missing ${name} schema embedding`);
    if(write) expressions.laws[name]=structuredClone(padSidesLaws[name]);
    else assert.deepEqual(expressions.laws[name],padSidesLaws[name]);
  }
  const grammarHash=createHash('sha256').update(grammar).digest('hex');
  if(write) expressions.grammar_sha256=grammarHash;
  else assert.equal(expressions.grammar_sha256,grammarHash,'stale expression grammar pin');
  for(const [name,schema] of Object.entries(protocol.artifact_schemas)) {
    if(write) protocol.artifact_schema_cids[name]=machineCid(schema);
    else assert.equal(protocol.artifact_schema_cids[name],machineCid(schema));
  }
  if(write) protocol.artifact_registry_cid=machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid,machineCid(protocol.artifact_schemas));
  return counts;
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  const paths=['spec/contracts/actql-expressions.json','spec/contracts/actql-protocol-schemas.json'];
  const bodies=paths.map(path=>JSON.parse(readFileSync(path,'utf8')));
  const grammar=readFileSync(bodies[0].grammar,'utf8');
  if(process.argv.includes('--write')) {
    updatePadSidesContracts(...bodies,grammar,true);
    bodies.forEach((body,i)=>writeFileSync(paths[i],JSON.stringify(body,null,2)+'\n'));
  }
  console.log('STRING padding and side-slice contracts verified:',updatePadSidesContracts(...bodies,grammar));
}
