import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {emitSchema} from './run-publication-protocol.mjs';
import {checkModelOriginalResourceStateSchema, modelOriginalResourceStateSchema,
  originalResourceDocumentSchema} from './model-original-resource-state-contract.mjs';

test('original Model resource binding is registered with exact current pins', () => {
  checkModelOriginalResourceStateSchema(JSON.parse(readFileSync(
    'spec/contracts/actql-protocol-schemas.json', 'utf8')));
});

test('original Model resource binding keeps closed originals and no self cycle', () => {
  const schema = modelOriginalResourceStateSchema();
  assert.equal(schema.additionalProperties, false);
  assert.equal(schema.properties.origin.additionalProperties, false);
  assert.equal(schema.properties.origin.required.length, 12);
  assert.equal(Object.hasOwn(schema.properties, 'self_cid'), false);
  assert.equal(Object.hasOwn(schema.properties.origin.properties, 'holding_cid'), false);
  assert.equal(schema.properties.origin.properties.run_id.pattern, undefined);
  assert.equal(schema.properties.origin.properties.run_definition_cid.pattern, '^sha256:[0-9a-f]{64}$');
  assert.doesNotThrow(() => emitSchema(schema));
});

test('original resource record positions retain the independent existing bytes', () => {
  // Saved original fixture, authored independently of the new schema/Writer.
  const wire = '["actql-original-ledger-state/0.1",["17","2","3","11","10","7"],["17","0","0","0","0","0","0","10","7","10","0","2","0"],["0","0","0"],null,[["0","0","0"],["0","0","0"],["0","0","0"]],["-3","0","0"],["1","0","0",true,true,false,"reading",true],["-1","0","3","2",true,false,null,null,[false,false,false],null,false,false],[["-2","0","7","5",true,false,null,null,[false,false,false],null,false,false]],[],[]]';
  assert.equal(Buffer.byteLength(wire), 406);
  assert.equal(createHash('sha256').update(wire).digest('hex'),
    '7ed6db2394d7eaa87d65b022a6bc78f722efaf7a0293115de52c09a89893aae9');
  const schema = originalResourceDocumentSchema();
  assert.equal(schema.prefixItems.length, 12);
  assert.equal(schema.items, false);
  assert.deepEqual(schema.prefixItems[0], {const: 'actql-original-ledger-state/0.1'});
  assert.equal(schema.prefixItems[2].prefixItems.length, 13);
  assert.equal(schema.prefixItems[6].prefixItems.length, 3);
  assert.equal(schema.prefixItems[8].prefixItems.length, 12);
  assert.equal(schema.prefixItems[9].items.prefixItems.length, 12);
  assert.equal(schema.prefixItems[10].items.prefixItems.length, 4);
  assert.equal(schema.prefixItems[11].items.prefixItems.length, 3);
});

test('complete original resource binding has independent raw UTF-8 bytes and CID', () => {
  const file = readFileSync('scripts/fixtures/model-original-resource-state-0.1.json', 'utf8');
  assert.equal(file.endsWith('\n'), true);
  const wire = file.slice(0, -1); // The fixture terminator is not artifact data.
  assert.equal(Buffer.byteLength(wire), 1713);
  assert.equal(createHash('sha256').update(wire).digest('hex'),
    '0c15b2030233db5aafb6ee124784d0e4e414ff8500ac9dc8ad5ee74b3b25a7cd');
  const body = JSON.parse(wire);
  assert.equal(body.origin.run_id, 'original-e\u0301\r\n');
  assert.equal(body.cut, null);
  assert.equal(body.resource_phase, 'preparation_base');
  assert.equal(new Set(Object.entries(body.origin).filter(([name]) => name !== 'run_id')
    .map(([, value]) => value)).size, 11);
  const stateWire = JSON.stringify(body.resource_state);
  assert.equal(Buffer.byteLength(stateWire), 406);
  assert.equal(`sha256:${createHash('sha256').update(stateWire).digest('hex')}`,
    body.resource_state_cid);
  const moon = readFileSync('src/run_publication/model_original_resource_document_wbtest.mbt', 'utf8');
  assert.ok(moon.includes(`#|${wire}`), 'actual Core reader consumes the same independent fixed bytes');
});
