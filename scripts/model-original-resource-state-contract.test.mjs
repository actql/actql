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
  const wire = '["actql-original-ledger-state/0.1",["17","2","3","11","10","7"],["17","0","0","0","0","0","0","10","7","10"],["0","0","0"],null,[["0","0","0"],["0","0","0"],["0","0","0"]],"-3",["1","0","0",true,true,false,"reading",true],["-1","0","3","2",true,false,null,null,[false,false,false],null],[["-2","0","7","5",true,false,null,null,[false,false,false],null]],[],[]]';
  assert.equal(Buffer.byteLength(wire), 360);
  assert.equal(createHash('sha256').update(wire).digest('hex'),
    '274329df872dc6b95ba33089f7a822419cb91c3169d893342df24fa6c2126da2');
  const schema = originalResourceDocumentSchema();
  assert.equal(schema.prefixItems.length, 12);
  assert.equal(schema.items, false);
  assert.deepEqual(schema.prefixItems[0], {const: 'actql-original-ledger-state/0.1'});
  assert.equal(schema.prefixItems[8].prefixItems.length, 10);
  assert.equal(schema.prefixItems[9].items.prefixItems.length, 10);
  assert.equal(schema.prefixItems[10].items.prefixItems.length, 4);
  assert.equal(schema.prefixItems[11].items.prefixItems.length, 3);
});
