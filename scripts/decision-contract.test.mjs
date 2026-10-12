import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkDecisionSchemas, decisionSchemas, initialJevProfile} from './decision-contract.mjs';
import {decisionVectors, taskFixture, promptFixture, generationFixture} from './decision-vectors.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {createHash} from 'node:crypto';
import {occurrences, violations} from './check-owned-contract-versions.mjs';

test('Decision registration preserves the old ModelTask schema and all original evidence/bundle schemas', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  checkDecisionSchemas(registry);
  assert.equal(registry.schema_cids.model_task,
    'sha256:19408a610dbc52552bff3a7f97f25a120a66688e7db4f41383c91c9298f02dd2');
  assert.equal(registry.schemas.model_task.properties.schema.const, 'actql.model_task/0.1');
  assert.deepEqual(registry.schemas.model_task.properties.task_kind, {const: 'structured_generate'});
  assert(!Object.hasOwn(registry.schemas.model_task.properties, 'decision_config'));
  // M0a does not migrate historical embedded evidence or readers.
  assert.equal(registry.artifact_schema_cids.model_invocation_evidence,
    'sha256:9b883bf32553da51b01bd88ff912f460eb2308034b33a591a18f7f6e91c38b27');
  assert.equal(registry.artifact_schema_cids.model_capture_bundle,
    'sha256:9e4c76623e09216b81f70ca5573b90dc6f17f4a8754638345da2f8ec617507ba');
});

test('Task kind is a closed discriminator; no dummy settings or aliases', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  const {task, prompt, answers, profile} = decisionSchemas(registry.schemas.model_task);
  assert.deepEqual(task.properties.task_kind.enum, ['structured_generate', 'decision']);
  assert.deepEqual(task.oneOf[0].required, ['generation_config']);
  assert.equal(task.oneOf[0].properties.decision_config, false);
  assert.deepEqual(task.oneOf[1].required, ['decision_config']);
  assert.equal(task.oneOf[1].properties.generation_config, false);
  assert.equal(prompt.properties.format.const, 'actql.decision_prompt/0.1');
  assert(!Object.hasOwn(prompt.properties, 'schema'));
  for (const question of prompt.properties.questions.items.oneOf) {
    assert(Object.hasOwn(question.properties, 'type'));
    assert(!Object.hasOwn(question.properties, 'kind'));
    assert(!Object.hasOwn(question.properties, 'criteria'));
    assert.deepEqual(question.properties.instructions, {type: 'string'});
    assert(question.required.includes('instructions'));
    if (question.properties.options) assert.deepEqual(
      question.properties.options.items.properties.description, {type: 'string'});
    if (question.properties.levels) assert.deepEqual(question.properties.levels.items, {type: 'string'});
  }
  // Generic answer shape does not impose a provider's decimal precision.
  assert(!JSON.stringify(answers).includes('multipleOf'));
  assert.equal(profile.properties.decimal_precision.const, 2);
  assert.equal(initialJevProfile.arithmetic_margin, 0.000001);
  assert.deepEqual(initialJevProfile, {
    format: 'actql.decision_probability_profile/0.1', profile: 'typesafe_jev_2dp',
    decimal_precision: 2, half_unit: 0.005, arithmetic_margin: 0.000001,
    grid_margin_scaled: 0.0000000001,
  });
  assert.equal('sha256:' + createHash('sha256').update(canonicalText(initialJevProfile)).digest('hex'),
    'sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f');
});

test('Independent literal vectors retain raw instructions, unusual IDs and reproducible bytes', () => {
  const hash = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
  for (const [body, self] of [[taskFixture, 'contract_cid'],
    [generationFixture, 'contract_cid'], [promptFixture, 'self_cid']]) {
    const core = {...body}; delete core[self];
    assert.equal(body[self], hash(core));
  }
  const {corpus, moon, arithmetic, guard} = decisionVectors();
  assert.equal(readFileSync('portability/corpus/decision-contracts.json', 'utf8'), JSON.stringify(corpus, null, 2) + '\n');
  for (const [path, expected] of [
    ['src/check_environment/decision_vectors.generated_test.mbt', moon],
    ['src/check_environment/decision_arithmetic.generated_wbtest.mbt', arithmetic],
    ['src/client_infer_host/decision_admission.generated_wbtest.mbt', guard],
  ]) assert.equal(readFileSync(path, 'utf8'), expected);
  assert(promptFixture.payload.questions[0].instructions.includes('\r\ne\u0301'));
  assert(Object.hasOwn(corpus.answers[0].body, '__proto__'));
  assert.equal(corpus.answers.length, 27);
});

test('The reviewed Task revision is allowed only in frozen contexts', () => {
  const inventory = JSON.parse(readFileSync('scripts/owned-contract-version-legacy.json', 'utf8'));
  const revision = ['actql.model_task/', '0', '.', '2'].join('');
  const path = 'src/check_environment/model_tasks.mbt';
  const source = readFileSync(path, 'utf8');
  const found = occurrences(source, path).filter(item => item.token === revision);
  assert.equal(found.length, 2);
  assert.equal(violations(found, inventory).length, 0);
  assert.equal(violations([...found, found[0]], inventory).length, 1);
  assert.equal(violations(found.map(item => ({...item, path: 'unreviewed.mbt'})), inventory).length, 2);
  const changed = occurrences(source.replace(revision, revision + '-unreviewed'), path)
    .filter(item => item.token === revision + '-unreviewed');
  assert.equal(changed.length, 1);
  assert.equal(violations(changed, inventory).length, 1);
});
