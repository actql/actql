import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkModelProviderDefaultsSchema} from './model-provider-defaults-contract.mjs';
import {machineCid} from './actql-spec-family.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const registry = read('spec/contracts/actql-protocol-schemas.json');

test('original provider defaults DATA has an owned closed machine grammar', () => {
  checkModelProviderDefaultsSchema(registry);
  const schema = registry.schemas.model_provider_defaults;
  assert.deepEqual(schema.required, ['models']);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.default_model, {type: 'string', minLength: 1});
  assert.equal(schema.properties.models.items.additionalProperties, false);
  const generation = schema.properties.models.items.properties.generation_config;
  assert.equal(generation.additionalProperties, false);
  assert.deepEqual(generation.required, ['temperature', 'top_p', 'max_output_tokens']);
  assert.deepEqual(generation.properties.max_output_tokens,
    {type: 'integer', minimum: 1, maximum: 9007199254740991});
});

test('profile selection does not broaden historical explicit Task or binding bytes', () => {
  for (const [body, cid] of [
    [registry.schemas.model_task,
      'sha256:f0b78bb09840a99b56f6fe910be33b9f51dfcc6349834aa44bcc1b5de1e87a7f'],
    [registry.schemas.model_task_v02,
      'sha256:4d573d3b4ef25cfe72ad6d8c7bd1c9b13296e14801ea829f839f2461137c5734'],
    [registry.artifact_schemas.model_provider_binding,
      'sha256:a4a37e0016403b483aa267dca7aae6c682940d2b23343b95defbcac2a1ca92b3'],
  ]) assert.equal(machineCid(body), cid);
});

test('independent original configuration vectors retain exact text and changed identities', () => {
  const vectors = read('portability/corpus/model-provider-defaults.json');
  const identities = new Set();
  for (const entry of vectors.cases) {
    assert.equal('sha256:' + createHash('sha256').update(entry.wire).digest('hex'), entry.cid);
    identities.add(entry.cid);
  }
  assert.equal(identities.size, vectors.cases.length);
  const [first, second, decomposed] = vectors.cases.map(entry => JSON.parse(entry.wire));
  assert.equal(first.model_defaults.models[0].generation_config.max_output_tokens, 100);
  assert.equal(second.model_defaults.models[0].generation_config.max_output_tokens, 200);
  assert.equal(decomposed.model_defaults.default_model, 'e\u0301');
});
