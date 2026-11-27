import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {compileWireTemplate} from './wire-template-compiler.mjs';
import {structuralWireValidator} from './templates/structural-wire-validator.mjs';
import {buildClientPublicationWire} from
  './generate-client-publication-wire.mjs';

const runPath = 'spec/contracts/actql-run-publication.json';
const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
// The mutable fixture view describes only this test's deliberate mutations;
// it supplies neither runtime validation nor an admitted publication.
interface MutationRegistry {schemas: {delivery_attempt: {properties: {result_name: {
  minLength?: number; newRule?: boolean; type?: string;
}}}}}

const registries = {
  [runPath]: JSON.parse(await readFile(runPath, 'utf8')),
  [protocolPath]: JSON.parse(await readFile(protocolPath, 'utf8')),
} as Record<typeof runPath | typeof protocolPath, MutationRegistry>;

test('projected property-count constraints distinguish empty Effect-only inventories', async () => {
  const {project} = await import('./generate-client-publication-wire.mjs');
  const validate = structuralWireValidator();
  const schema = project({maxProperties: 0});
  assert.deepEqual(schema, {maxProperties: 0});
  assert.equal(validate({}, schema), true);
  assert.equal(validate({hidden: null}, schema), false);
  assert.equal(validate('unrelated', schema), true, 'Object bounds do not type arbitrary JSON');
  const lower = project({minProperties: 1});
  assert.equal(validate({}, lower), false);
  assert.equal(validate({declared: true}, lower), true);
});

test('selected full artifact projection preserves alternatives and composite constants', async () => {
  const {project} = await import('./generate-client-publication-wire.mjs');
  const schema = project({anyOf: [{const: ['first', 'second']}, {const: {original: true}}]}, {extended: true});
  const validate = structuralWireValidator({extended: true, compositeConstants: true});
  assert.equal(validate(['first', 'second'], schema), true);
  assert.equal(validate({original: true}, schema), true);
  for (const value of [['second', 'first'], ['first'], {original: false}, {original: true, extra: 1}]) {
    assert.equal(validate(value, schema), false);
  }
  assert.throws(() => project({anyOf: [{const: 1}]}), /UnsupportedPublicationSchema:anyOf/);
  assert.throws(() => project({format: 'invented'}, {extended: true}), /UnsupportedPublicationFormat/);
});

test('publication wire bindings match their registered schema owners',
  async () => {
    const output = buildClientPublicationWire(registries);
    assert.equal(output.module, await readFile(
      'packages/client-wire/publication.generated.js', 'utf8'));
    assert.equal(output.types, await readFile(
      'packages/client-wire/publication.generated.d.ts', 'utf8'));
  });

test('wire template compilation refuses a type error in the materialized module', () => {
  const schema = 'const schemas: Readonly<Record<string, WireSchema>> = {probe: {type: "string"}};';
  const invalidBinding = schema + 'const invalid: string = 7;';
  assert.throws(() => compileWireTemplate('interactive-control-wire', invalidBinding, '',
    [{name: 'check', type: 'string', schema: 'probe'}]), /InvalidWireTemplate:interactive-control-wire[\s\S]*TS2322/u);
});

test('owner schema changes invalidate generated Client bindings', () => {
  const changed = structuredClone(registries);
  changed[runPath].schemas.delivery_attempt.properties.result_name.minLength = 2;
  assert.notEqual(buildClientPublicationWire(changed).module,
    buildClientPublicationWire(registries).module);
  changed[runPath].schemas.delivery_attempt.properties.result_name.newRule =
    true;
  assert.throws(() => buildClientPublicationWire(changed),
    /UnsupportedPublicationSchema:newRule/u);
  delete changed[runPath].schemas.delivery_attempt.properties.result_name.newRule;
  changed[runPath].schemas.delivery_attempt.properties.result_name.type =
    'null';
  assert.throws(() => buildClientPublicationWire(changed),
    /UnsupportedPublicationType:null/u);
});

test('arrays of discriminated unions retain readonly array precedence', async () => {
  const {project, typeOf} = await import('./generate-client-publication-wire.mjs');
  assert.equal(typeOf(project({type: 'array', items: {oneOf: [
    {const: 'field'}, {const: 'items'},
  ]}})), 'readonly ("field" | "items")[]');
  assert.equal(typeOf(project({type: 'number'})), 'number');
});

test('readonly arrays group their union alternatives', async () => {
  const {project, typeOf} = await import('./generate-client-publication-wire.mjs');
  assert.equal(typeOf(project({type: 'array', items: {oneOf: [
    {const: 'generic'}, {const: 'located'},
  ]}})), 'readonly ("generic" | "located")[]');
});
