import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {parameterPrograms} from './parameter-schema.mjs';
import {commandInputKeySchema, commandInputKeySchemas} from './command-input-key.mjs';
import {publishedCommandTargetSchemas} from './published-command-target.mjs';
import {withoutCreateValuesSchema} from './create-values.mjs';
const read = p => JSON.parse(readFileSync(p, 'utf8'));
const protocol = read('spec/contracts/actql-protocol-schemas.json');
const vectors = read('portability/corpus/command-input-keys.json');
const command = p => p.properties.effects.additionalProperties.oneOf
  .find(member => member.properties?.command).properties.command;

test('actual Program schemas retain all original declarations and add only optional Command input_key', () => {
  commandInputKeySchemas(protocol);
  const prior = read(vectors.previous_program_file);
  assert.equal(machineCid(prior), vectors.previous_program_cid);
  assert.deepEqual(prior, JSON.parse(execFileSync('git', ['show',
    vectors.previous_source + ':spec/contracts/actql-protocol-schemas.json'],
  {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024})).artifact_schemas.executable_plan
    .properties.execution_material.properties.program);
  const historical = structuredClone(prior);
  command(historical).properties.input_key = structuredClone(commandInputKeySchema);
  assert.equal(machineCid(historical), vectors.program_cid,
    'The original input-key-only preimage retains its original type grammar');
  for (const program of parameterPrograms(protocol)) {
    // Later adopted type constraints do not rewrite a historical full-schema
    // preimage. Compare the complete current Command against its original body.
    assert.deepEqual(command(withoutCreateValuesSchema(program)), command(historical));
    assert.deepEqual(command(program).properties.input_key, commandInputKeySchema);
    assert.equal(command(program).required.includes('input_key'), false);
  }
});

test('required original-input schema gate rejects omission nullability and unrelated mutations', () => {
  for (const mutate of [
    p => { delete command(p).properties.input_key; },
    p => { command(p).properties.input_key.type = ['string', 'null']; },
    p => { command(p).properties.input_key.minLength = 0; },
    p => { command(p).required.push('input_key'); },
    p => { command(p).properties.target.oneOf.pop(); },
  ]) {
    const changed = structuredClone(protocol);
    mutate(parameterPrograms(changed)[0]);
    assert.throws(() => {
      publishedCommandTargetSchemas(changed);
      commandInputKeySchemas(changed);
    });
  }
});

test('independent complete Programs retain absent bytes and separate target identifier from row ID', () => {
  assert.equal(vectors.qualification, 'Independent Python canonical JSON SHA-256; no product output or runtime evidence');
  for (const c of vectors.programs) {
    assert.equal(machineCid(c.program), c.cid);
    assert.equal(machineCid(c.prior_program), c.prior_cid);
    assert.notEqual(c.cid, c.prior_cid);
    const restored = structuredClone(c.program);
    assert.equal(restored.effects.send.command.input_key, 'row_id');
    delete restored.effects.send.command.input_key;
    assert.deepEqual(restored, c.prior_program);
    assert.deepEqual(c.program.effects.send.command.target, c.prior_program.effects.send.command.target);
    assert.deepEqual(c.program.effects.send.command.input, c.prior_program.effects.send.command.input);
    if (c.mode === 'identifier') {
      assert.equal(c.program.effects.send.command.target.published_command.identifier_field, 'address');
    }
  }
});
