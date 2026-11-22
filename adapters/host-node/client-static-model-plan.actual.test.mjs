import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setImmediate} from 'node:timers/promises';
import {createHostObservationConnection} from '../host-common/observation.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {staticExplanationReadModel} from '../../packages/explorer-ui/read-model.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

// Actual imported installed static service, original public template and
// current Common bridge. This is a source-checkout caller regression, not
// packed RC execution, a Model invocation or an Effect approval/write.
for (const [template, program, target] of [
  ['churn-risk-mock', 'churn-risk.aql', 'connector://salesforce/Account'],
  ['deal-review-mock', 'deal-review.aql', 'connector://salesforce/Opportunity'],
]) {
  test(`installed static Plan retains original ${template} INFER and Effect without executing either`, async () => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-static-model-',
      label: `original ${template} static Plan`});
    const project = scaffoldProject(join(scratch.path, 'project'), template);
    const before = await readFile(join(project.directory, 'mock/data.json'));
    const source = await readFile(join(project.directory, program), 'utf8');
    const cwd = process.cwd();
    let client, primary;
    process.chdir(project.directory);
    try {
      client = await connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
        installation: {directory: '.actql-node'}});
      const plan = await client.plan(source, {format: 'aql'});
      assert.equal(plan.version, 'actql-effectful-static-plan-view/0.1');
      assert.equal(plan.computation.scope, 'computation_component');
      assert.equal(plan.computation.plan_view.logical_map.steps.filter(step => step.operator === 'infer').length, 1);
      assert.equal(plan.effect_set.members.length, 1);
      assert.equal(plan.effect_set.members[0].effect_kind, 'update');
      assert.equal(plan.effect_set.members[0].contract.declared_target, target);
      assert.deepEqual(await readFile(join(project.directory, 'mock/data.json')), before);

    } catch (error) {primary = error;}
    finally {
      try {await client?.close();}
      catch (error) {primary = primary === undefined ? error :
        new AggregateError([primary, error], 'Original static Plan and cleanup failed');}
      finally {process.chdir(cwd);}
    }
    if (primary !== undefined) throw primary;
    scratch.passed();
    scratch.close();
  });
}

test('installed static Explanation retains the original deal-review Source, Model, Result and Effect declarations', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-static-explanation-',
    label: 'original deal-review static Explanation'});
  const project = scaffoldProject(join(scratch.path, 'project'), 'deal-review-mock');
  const dataPath = join(project.directory, 'mock/data.json');
  const before = await readFile(dataPath);
  const source = await readFile(join(project.directory, 'deal-review.aql'), 'utf8');
  const accountConfiguration = JSON.stringify({version: 'actql-execution-account-config/0.1',
    account_id: 'static-explanation-test', entries: [{entry_id: 'read-original', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {any_of: ['run']},
      operation: {any_of: ['read']}, exclusions: []}]});
  const cwd = process.cwd();
  let client, primary;
  process.chdir(project.directory);
  try {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
      installation: {directory: '.actql-node', authorization: {accountConfiguration}}});
    const explanation = await client.explain(source, {format: 'aql'});
    const {version, plan, facts, context} = explanation;
    assert.equal(version, 'actql-static-explanation/0.1');
    assert.equal(plan.observation, 'static');
    assert.equal(plan.provider_io, 0);
    const original = plan.computation.plan_view;
    const map = original.logical_map;
    assert.deepEqual(context.binding, {program_definition_cid: plan.program_definition_cid,
      parameter_values_cid: plan.parameter_values_cid, check_environment_cid: plan.check_environment_cid,
      compiled_plan_cid: original.compiled_plan_cid, logical_map_cid: map.self_cid});
    assert.equal(facts.logical_map_cid, map.self_cid);
    assert.deepEqual(context.items.map(item => item.kind),
      ['source', 'source', 'source', 'model_task', 'result', 'effect_set']);
    const [opportunities, files, contents, model, result, effects] = context.items;
    for (const [item, stage, connector, resource, request] of [
      [opportunities, 0, 'salesforce', 'Opportunity', 'direct'],
      [files, 1, 'drive', 'files', 'direct'],
      [contents, 2, 'drive', 'contents', 'keyed'],
    ]) {
      assert.equal(item.source_view.connector, connector);
      assert.equal(item.source_view.resource, resource);
      assert.equal(item.request_kind, request);
      assert.equal(item.link_state, 'linked');
      assert.deepEqual(item.stage_input, {kind: 'stage_input', stage_ordinal: stage, input_port_ordinal: 0});
      const consumers = map.steps.flatMap(step => step.ports.filter(port => port.role === 'input' &&
        port.source.kind === 'stage_input' && port.source.stage_ordinal === stage &&
        port.source.input_port_ordinal === 0).map(port => ({step_id: step.step_id, port_id: port.port_id})));
      assert(consumers.length > 0);
      assert.deepEqual(item.consuming_ports, consumers);
    }
    const joinKeys = facts.steps.filter(step => step.meaning.kind === 'join')
      .map(step => step.meaning.keys.map(key => key.right));
    // Two authored Source joins followed by the compiler's INFER join-back.
    assert.deepEqual(joinKeys, [['name'], ['resource', 'version'], ['id']]);
    assert.equal(model.task_id, 'model-task:deal-review.v1');
    assert.equal(model.dispatch_unit, 'input_row');
    assert.deepEqual(model.input_bindings.map(input => input.role).sort(), ['NextStep', 'StageName', 'notes']);
    assert.deepEqual(model.output_fields.map(field => field.name), ['changed', 'next_step', 'stage']);
    const modelStep = map.steps.find(step => step.step_id === model.producer.step_id);
    assert.equal(modelStep?.operator, 'infer');
    assert(modelStep.ports.some(port => port.role === 'output' && port.port_id === model.producer.port_id));
    assert.equal(result.name, 'updates');
    const resultStep = map.steps.find(step => step.step_id === result.producer.step_id);
    assert(resultStep?.ports.some(port => port.role === 'output' && port.port_id === result.producer.port_id));
    assert.equal(effects.unit_id, plan.effect_set.unit_id);
    assert.equal(effects.members.length, 1);
    const [{declaration, write_fields: writes}] = effects.members;
    assert.deepEqual(declaration, plan.effect_set.members[0]);
    assert.equal(declaration.effect_kind, 'update');
    assert.equal(declaration.contract.declared_target, 'connector://salesforce/Opportunity');
    assert.deepEqual(declaration.input, {kind: 'result', result_name: 'aql_private_update'});
    assert.deepEqual(declaration.minimum_approval, {kind: 'contract_minimum', value: 'required'});
    assert.deepEqual(plan.observations.approval, {state: 'unknown', reason: 'not_observed'});
    assert.deepEqual(plan.observations.preview, {state: 'unavailable', reason: 'not_sealed'});
    assert.equal(writes.state, 'declared');
    assert.deepEqual([...writes.fields].sort(), ['NextStep', 'StageName']);
    assert.doesNotMatch(JSON.stringify({facts, context}), /"(?:prompt|instructions)"|Review only the current stage/);

    // The same public response reaches the Explorer renderer in both
    // languages without a second Plan read or reopening a producer.
    const {renderStaticExplanationNarrative} = await import('@actql/local-node/_internal/explanation-narrative');
    const render = (view, locale) => {
      assert.equal(view, explanation);
      return renderStaticExplanationNarrative(canonicalJson(view, {dataKeys: true}), locale);
    };
    const english = staticExplanationReadModel(explanation, {render, locale: 'en'});
    const japanese = staticExplanationReadModel(explanation, {render, locale: 'ja'});
    for (const presentation of [english, japanese]) {
      assert.equal(presentation.plan.logicalMapCid, map.self_cid);
      assert.deepEqual(presentation.story.occurrences.map(step => step.stepId),
        map.steps.map(step => step.step_id));
      assert.deepEqual(presentation.context.map(item => item.origin), context.items);
      assert.doesNotMatch(JSON.stringify(presentation), /"(?:prompt|instructions)"|Review only the current stage/);
    }
    assert.equal(english.context[3].text, 'Apply model task "model-task:deal-review.v1" to each input row');
    assert.equal(japanese.context[3].text, 'モデルタスク "model-task:deal-review.v1" を各入力行に適用');
    assert.equal(english.context[4].text, 'Declare Result "updates"');
    assert.match(english.context[5].text, /Declared write update "connector:\/\/salesforce\/Opportunity".*Contract minimum approval: required.*Current decision unknown/u);
    assert.match(japanese.context[5].text, /^宣言された書き込み 更新 /u);
    assert.match(japanese.context[5].text, /契約上の最低承認要件 必要.*現在の判断は不明/u);
    assert.equal(english.story.occurrences.filter(step => step.operator === 'join' &&
      step.explanation.text.includes(' join on: ')).length, 3);
    assert.equal(japanese.story.occurrences.filter(step => step.operator === 'join' &&
      step.explanation.text.includes(' 結合のキー: ')).length, 3);
    assert.deepEqual(await readFile(dataPath), before);
  } catch (error) {primary = error;}
  finally {
    try {await client?.close();}
    catch (error) {primary = primary === undefined ? error :
      new AggregateError([primary, error], 'Original static Explanation and cleanup failed');}
    finally {process.chdir(cwd);}
  }
  if (primary !== undefined) throw primary;
  scratch.passed();
  scratch.close();
});


// One real ordinary Run and a fresh embedded Host generation. Its cold read
// only uses the original committed Journal and never supplies the AQL again.
test('installed Saved Context uses the retained original after Host close and reopen', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-saved-context-',
    label: 'original churn-risk Saved Context'});
  const project = scaffoldProject(join(scratch.path, 'project'), 'churn-risk-mock');
  const cwd = process.cwd();
  let client, primary, phase = 'initialization';
  process.chdir(project.directory);
  try {
    const before = await readFile('mock/data.json');
    const records = [];
    const open = () => connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
      installation: {directory: '.actql-node',
        observation: createHostObservationConnection({deliver: record => records.push(record)})}});
    client = await open();
    phase = 'submit original';
    const run = await client.startSource(await readFile('churn-risk.aql', 'utf8'),
      {format: 'aql', stopBefore: 'commit'});
    assert.equal((await run.wait()).status, 'waiting_checkpoint');
    const ref = structuredClone(run.ref);
    const originalAttempts = () => records.filter(record =>
      record.event === 'attempt_started' && ['source', 'model', 'effect'].includes(record.operation) &&
      record.attributes['actql.run.definition_cid'] === ref.runDefinitionCid);
    for (let turn = 0; turn < 512 && originalAttempts().filter(record => record.operation === 'source').length < 2;
      turn++) await setImmediate();
    const attempts = originalAttempts();
    assert.equal(attempts.filter(record => record.operation === 'source').length, 2);
    phase = 'warm Saved Context';
    const warm = await run.explainContext();
    assert.deepEqual(warm.run_ref, ref);
    assert.equal(warm.explanation.state, 'projected');
    const {plan, context, facts} = warm.explanation.view;
    assert.deepEqual(context.items.map(item => item.kind), ['source', 'source', 'model_task', 'result', 'effect_set']);
    assert.equal(context.binding.logical_map_cid, plan.logical_map.self_cid);
    assert.equal(facts.logical_map_cid, plan.logical_map.self_cid);
    phase = 'warm legacy Facts';
    assert.deepEqual((await run.explain()).explanation.facts, facts);
    for (const record of attempts) assert.notEqual(record.operation, 'effect');
    phase = 'original Host close';
    await client.close();
    client = undefined;
    phase = 'cold Host reopen and attach';
    client = await open();
    const saved = await client.attach(ref);
    phase = 'cold Saved Context';
    assert.deepEqual(await saved.explainContext(), warm);
    phase = 'cold legacy Facts';
    assert.deepEqual((await saved.explain()).explanation.facts, facts);
    phase = 'cold Explorer Saved Context';
    const {harness} = await import('../../packages/explorer/gateway-test.fixture.mjs');
    const explorer = harness({client});
    try {
      const session = await explorer.connect();
      const response = await explorer.read('run-explanation-context', {ref, locale: 'ja'}, session);
      assert.equal(response.status, 200);
      const {data} = await response.json();
      assert.deepEqual(data.runRef, ref);
      assert.equal(data.explanation.state, 'projected');
      assert.equal(data.plan.logicalMapCid, plan.logical_map.self_cid);
      assert.equal(data.explanation.story.factsCid, facts.self_cid);
      assert.equal(data.explanation.story.scope, 'computation_component');
      assert.deepEqual(data.explanation.context.map(item => item.origin), context.items);
      assert.match(data.explanation.context.find(item => item.origin.kind === 'model_task').text,
        /を各入力行に適用/u);
    } finally {await explorer.gateway.close();}
    await setImmediate();
    assert.deepEqual(originalAttempts(), attempts);
    assert.deepEqual(await readFile('mock/data.json'), before);
  } catch (error) {
    primary = error;
    t.diagnostic(JSON.stringify({phase, retainedScratch: scratch.path, code: error?.code}));
  } finally {
    try {await client?.close();}
    catch (error) {primary = primary === undefined ? error
      : new AggregateError([primary, error], 'Saved Context read and Host cleanup failed');}
    finally {process.chdir(cwd);}
  }
  if (primary !== undefined) throw primary;
  scratch.passed();
  scratch.close();
});
