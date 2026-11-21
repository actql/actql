import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';
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
    const {version, plan, facts, context} = await client.explain(source, {format: 'aql'});
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
