import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {isDeepStrictEqual} from 'node:util';
import {checkDeriveBinding} from './derive-binding-schema.mjs';
const stages = JSON.parse(readFileSync('spec/contracts/actql-stage-contracts.json', 'utf8'));
const schema = checkDeriveBinding(stages);

// Test-only interpreter for this closed schema's keywords; unexpected additions
// fail rather than silently skip a constraint. Hashes below are shape placeholders,
// not claims of admitted evidence, ownership, backend support or identity.
function valid(s, v) {
  const known = ['type','properties','required','additionalProperties','const','enum','pattern','minLength','items','minItems','allOf','if','then'];
  for (const k of Object.keys(s)) assert.ok(known.includes(k), k);
  if (s.type === 'object' && (v === null || typeof v !== 'object' || Array.isArray(v))) return false;
  if (s.type === 'array' && !Array.isArray(v)) return false;
  if (s.type === 'string' && typeof v !== 'string') return false;
  if (Object.hasOwn(s, 'const') && !isDeepStrictEqual(v, s.const)) return false;
  if (s.enum && !s.enum.some(x => isDeepStrictEqual(x, v))) return false;
  if (typeof v === 'string' && (v.length < (s.minLength ?? 0) || s.pattern && !new RegExp(s.pattern).test(v))) return false;
  if (Array.isArray(v) && (v.length < (s.minItems ?? 0) || s.items && !v.every(x => valid(s.items, x)))) return false;
  if (v !== null && typeof v === 'object' && !Array.isArray(v)) {
    if (s.required?.some(k => !Object.hasOwn(v, k))) return false;
    for (const [k, x] of Object.entries(v)) {
      if (s.properties?.[k]) {if (!valid(s.properties[k], x)) return false;}
      else if (s.additionalProperties === false) return false;
    }
  }
  if (s.allOf && !s.allOf.every(x => valid(x, v))) return false;
  if (s.if && valid(s.if, v) && s.then && !valid(s.then, v)) return false;
  return true;
}
const hash = 'sha256:' + 'a'.repeat(64);
const base = {version:'actql-derive-binding/0.1', aoa_node_cid:hash,
  input_contract_cid:hash, output_contract_cid:hash, mode:'snapshot_map',
  input_passthrough:true, failure_scope:'row-binding-expression', limits_cid:hash,
  bindings:[], self_cid:hash};
const slot = {name:'x', checked_expression_cid:hash, context_contract_cid:hash};

test('snapshot accepts empty evidence; ordered form requires a binding', () => {
  for (const [mode, bindings, expected] of [
    ['snapshot_map', [], true], ['snapshot_map', [slot], true],
    ['ordered_array', [], false], ['ordered_array', [slot], true],
    ['ordered_array', [slot, {...slot, name:'y'}], true],
  ]) assert.equal(valid(schema, {...base, mode, bindings}), expected);
});

test('empty snapshot does not bypass closed evidence or binding shape', () => {
  for (const key of schema.required) {
    const v = {...base}; delete v[key]; assert.equal(valid(schema, v), false, key);
  }
  for (const change of [{mode:'other'}, {bindings:null}, {bindings:[{}]},
    {extra:true}, {input_passthrough:false}, {failure_scope:'slot'},
    {bindings:[{...slot, extra:true}]}]) assert.equal(valid(schema, {...base, ...change}), false);
});
