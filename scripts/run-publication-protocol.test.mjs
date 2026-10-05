import assert from 'node:assert/strict';
import test from 'node:test';
import {emitSchema} from './run-publication-protocol.mjs';

test('Run review singleton claim is exact without admitting arbitrary tuple literals', () => {
  assert.doesNotThrow(() => emitSchema({const: ['invocation_scope_approved']}));
  for (const schema of [
    {const: []}, {const: ['a', 'b']}, {const: [null]},
    {type: 'string', const: ['a']}, {const: ['a'], minItems: 2},
  ]) assert.throws(() => emitSchema(schema), /Unsupported/);
});

test('generator rejects unsupported number constraints', () => {
  for (const schema of [
    {type: 'number', const: 1},
    {type: 'number', enum: [1, 2]},
    {type: 'number', minimum: 0, maximum: 1},
  ]) {
    assert.throws(() => emitSchema(schema), /Unsupported number/);
  }
});

test('generator rejects silently ignored constraints in other branches', () => {
  for (const schema of [
    {type: 'null', minLength: 1},
    {type: 'boolean', minimum: 0},
    {type: 'string', minimum: 0},
    {type: 'integer', minLength: 1},
    {type: 'array', minProperties: 1},
    {type: 'object', minItems: 1},
    {type: 'object', propertyNames: {
      not: {pattern: '^actql_', minLength: 2},
    }},
    {type: 'string', const: 1},
    {type: 'integer', enum: ['1']},
  ]) {
    assert.throws(() => emitSchema(schema), /Unsupported|Conflicting/);
  }
});

test('generator retains supported literal and property-name constraints', () => {
  for (const schema of [
    {type: 'integer', minimum: 0, maximum: 1},
    {type: 'string', const: 'value', minLength: 1},
    {type: 'boolean', const: false},
    {type: 'object', propertyNames: {not: {pattern: '^actql_'}}},
  ]) {
    assert.doesNotThrow(() => emitSchema(schema));
  }
});

test('generator preserves operation-specific array ceilings', () => {
  assert.doesNotThrow(() => emitSchema({
    type: 'array', items: {}, maxItems: 4096,
  }));
});

test('generator keeps object-scoped Effect branch constraints', () => {
  assert.doesNotThrow(() => emitSchema({
    type: 'object',
    properties: {kind: {enum: ['command', 'create']}},
    allOf: [{oneOf: [
      {properties: {kind: {const: 'command'}}, required: ['contract']},
      {properties: {kind: {const: 'create'}}, required: ['mapping']},
    ]}],
  }));
  assert.throws(() => emitSchema({
    allOf: [{properties: {kind: {const: 'command'}}}],
  }), /Unsupported typeless/);
});

test('generator keeps Effect receipt conditional and exclusion rules', () => {
  assert.doesNotThrow(() => emitSchema({
    type: 'object',
    properties: {state: {enum: ['unknown', 'applied']}},
    allOf: [{if: {properties: {state: {const: 'unknown'}},
      required: ['state']}, then: {required: ['reason']},
    else: {not: {required: ['reason']}}}],
    oneOf: [{required: ['command_id'],
      not: {required: ['operation_ref']}},
    {required: ['operation_ref'],
      not: {anyOf: [{required: ['command_id']},
        {required: ['idempotency_key']}]}}],
  }));
  assert.throws(() => emitSchema({then: {required: ['reason']}}),
    /requires if/);
  assert.throws(() => emitSchema({anyOf: []}), /Empty.*anyOf/);
});
