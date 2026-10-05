import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const closed = properties => ({type:'object', additionalProperties:false,
  required:Object.keys(properties), properties});
export const sourceTypedLiteral = closed({typed_literal:closed({
  type:{const:'json'}, value:{type:'string'},
})});
export const nodeTypedLiteral = closed({op:{const:'typed_literal'},
  body:closed({$json:{}})});
export const typedJsonWireLaw = {
  version: 'actql-json-value-wire/0.1',
  representation: 'Every non-SQL-NULL JSON typed cell is the closed object {$json: payload}. SQL NULL is null and requires a nullable contract. Other typed scalar representations are unchanged.',
  admission: 'Decode the envelope only in explicit typed-wire admission under a checked JSON contract. Raw authored JSON is not a wire envelope. An object payload containing $json is enclosed again. Reject old untagged JSON cells; no fallback.',
  payload: 'Retain JSON null, finite canonical numbers, booleans, exact Unicode strings, arrays in order and objects with exact data keys sorted by UTF-16. Typed references and other typed values are not JSON payloads.',
  bounds: 'Physical wire byte, node and depth accounting includes the envelope. Logical payload accounting counts the JSON payload once. Failure never truncates a value.',
};
export const typedJsonLaw = {
  version:'actql-typed-json-literal/0.1',
  source:'A closed typed_literal {type: json, value: decoded JSON text} is an opaque expression leaf. JSON text is data, never expression syntax, a Parameter hole or reference authority.',
  output:'The complete JSON value has the existing non-null json contract. JSON null, boolean, number and string are distinct from SQL NULL and ordinary scalar contracts. Existing literal null is SQL NULL; existing ordinary scalar literal inference and object/array literal inference are unchanged.',
  decoding:'Decode standard JSON without NFC or newline normalization of data keys or string values. Keep the first occurrence of each exact decoded duplicate object key. Parse and bound the complete input, including discarded duplicates. Preserve array order. Sort object keys by UTF-16 only for canonical encoding.',
  numbers:'Use the existing finite binary64 value domain without silent rounding. The original decimal token must roundtrip mathematically through the shortest binary64 decimal spelling; reject precision loss, non-finite values and negative zero explicitly. This is a bounded numeric subset of GoogleSQL JSON, not support for its complete signed/unsigned integer domain. Number token length is at most 1500 characters.',
  bounds:'JSON depth is at most 500 and is additionally bounded by the caller depth ceiling. Charge complete decoded source nodes, decoded text and parsing work, including discarded duplicate values. Existing value, expression, canonical-wire and execution ceilings remain applicable. No truncation or partial result is permitted.',
  runtime:'The common Value owner retains a JSON domain around an immutable JSON-only payload. Typed runtime recheck rejects a bare scalar or object for a JSON contract; JSON payloads cannot contain typed dates, decimals, vectors or opaque references. IS NULL tests SQL NULL, so JSON null is not SQL NULL.',
  wire:'Every non-SQL-NULL JSON cell uses the closed canonical typed-wire envelope {$json: payload}; SQL NULL uses null and requires a nullable contract. Decode this envelope only under a checked JSON contract and an explicit typed-wire entry. An ordinary JSON object with a $json member is payload and is enclosed again; authored raw data never selects a type or authority by its keys.',
  identity:'Canonical typed-wire bytes and expression nodes distinguish JSON domains from ordinary scalars and SQL NULL. JSON data keys retain their Unicode scalar sequence. Existing identifier normalization remains separate. Bound wire byte measurements include the envelope. Storage/replay uses the same typed-wire contract and exact pins; old untagged typed JSON wire is not accepted as the new format.',
  consumers:'Graph Delta and snapshot identity-body parsers consume an explicitly checked JSON payload through the common read-only accessor. Their semantic body format is not the typed-cell envelope. No graph identity, execution owner or authority is invented by this conversion.',
};

function visit(value, source, node, write) {
  if (!value || typeof value !== 'object') return;
  if (Array.isArray(value.oneOf)) {
    if (value.oneOf.some(v => v.required?.length === 1 && v.required[0] === 'literal')) {
      const found = value.oneOf.find(v => v.required?.length === 1 && v.required[0] === 'typed_literal');
      if (write) {
        if (found) Object.assign(found, structuredClone(source));
        else value.oneOf.push(structuredClone(source));
      } else assert.deepEqual(found, source, 'stale source typed JSON literal schema');
    }
    if (value.oneOf.some(v => v.properties?.op?.const === 'literal')) {
      const found = value.oneOf.find(v => v.properties?.op?.const === 'typed_literal');
      if (write) {
        if (found) Object.assign(found, structuredClone(node));
        else value.oneOf.push(structuredClone(node));
      } else assert.deepEqual(found, node, 'stale typed JSON expression node schema');
    }
  }
  for (const child of Object.values(value)) visit(child, source, node, write);
}

export function updateTypedJsonContracts(expressions, protocol, write = false) {
  visit(expressions, sourceTypedLiteral, nodeTypedLiteral, write);
  visit(protocol, sourceTypedLiteral, nodeTypedLiteral, write);
  const literalLaw = {...typedJsonLaw, wire_contract_cid: machineCid(typedJsonWireLaw)};
  if (write) {
    expressions.laws.typed_json_literal = literalLaw;
    expressions.laws.typed_json_wire = structuredClone(typedJsonWireLaw);
  } else {
    assert.deepEqual(expressions.laws.typed_json_literal, literalLaw);
    assert.deepEqual(expressions.laws.typed_json_wire, typedJsonWireLaw);
  }
  for (const [name, body] of Object.entries(protocol.artifact_schemas)) {
    if (write) protocol.artifact_schema_cids[name] = machineCid(body);
    else assert.equal(protocol.artifact_schema_cids[name], machineCid(body));
  }
  if (write) protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const paths = ['spec/contracts/actql-expressions.json', 'spec/contracts/actql-protocol-schemas.json'];
  const bodies = paths.map(path => JSON.parse(readFileSync(path, 'utf8')));
  if (process.argv.includes('--write')) {
    updateTypedJsonContracts(...bodies, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  const pinPath = 'src/run_publication/json_wire_contract.generated.mbt';
  const pin = '// Generated by scripts/typed-json-literal-contract.mjs. Do not edit.\n\n///|\nfn json_value_wire_contract_cid() -> String {\n  ' + JSON.stringify(machineCid(typedJsonWireLaw)) + '\n}\n';
  if (process.argv.includes('--write')) writeFileSync(pinPath, pin);
  else assert.equal(readFileSync(pinPath, 'utf8'), pin, 'stale JSON value wire pin');
  const clientPinPath = 'packages/sdk/json-value-wire.generated.mjs';
  const clientPin = '// Generated from the common typed JSON wire law. Do not edit.\n' +
    '// Run: node scripts/typed-json-literal-contract.mjs --write\n' +
    'export const jsonValueWireContractCid = ' + JSON.stringify(machineCid(typedJsonWireLaw)) + ';\n';
  if (process.argv.includes('--write')) writeFileSync(clientPinPath, clientPin);
  else assert.equal(readFileSync(clientPinPath, 'utf8'), clientPin, 'stale Client JSON value wire pin');
  updateTypedJsonContracts(...bodies);
  console.log('Typed JSON source/node schemas, law and artifact pins verified.');
}
