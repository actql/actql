import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {setImmediate} from 'node:timers/promises';
import {createHostObservationConnection} from '../host-common/observation.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {flowPresentation} from '../../packages/explorer-ui/flow-model.mjs';
import {staticExplanationReadModel} from '../../packages/explorer-ui/read-model.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';
import {twoModelDealReviewProgram} from '../../scripts/fixtures/deal-review-two-models.mjs';

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
    for (const [item, stage, input, connector, resource, request] of [
      [opportunities, 0, 0, 'salesforce', 'Opportunity', 'direct'],
      [files, 1, 0, 'drive', 'files', 'direct'],
      [contents, 2, 2, 'drive', 'contents', 'keyed'],
    ]) {
      assert.equal(item.source_view.connector, connector);
      assert.equal(item.source_view.resource, resource);
      assert.equal(item.request_kind, request);
      assert.equal(item.link_state, 'linked');
      assert.deepEqual(item.stage_input, {kind: 'stage_input', stage_ordinal: stage, input_port_ordinal: input});
      const consumers = map.steps.flatMap(step => step.ports.filter(port => port.role === 'input' &&
        port.source.kind === 'stage_input' && port.source.stage_ordinal === stage &&
        port.source.input_port_ordinal === input).map(port => ({step_id: step.step_id, port_id: port.port_id})));
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
    assert.equal(english.story.narrative.summary,
      'Read from "salesforce", "drive". Join inputs. Ask "model-task:deal-review.v1". Filter rows. Return "updates". Plan to update "Opportunity" in "salesforce".');
    assert.equal(japanese.story.narrative.summary,
      '"salesforce"、"drive" から読み取る。入力を結合する。"model-task:deal-review.v1" に問い合わせる。行を絞り込む。"updates" を結果として返す。"salesforce" の "Opportunity" を更新する計画。');
    for (const [presentation, redaction] of [[english, /\[redacted /u], [japanese, /\[非開示 /u]]) {
      const filter = presentation.story.occurrences.find(step => step.operator === 'filter');
      assert.equal(filter.explanation.meaning.predicate.state, 'projected');
      assert.match(filter.explanation.text, /"review"\."value"\."changed"/u);
      assert.match(filter.explanation.text, redaction);
      assert.doesNotMatch(filter.explanation.text, /"ok"/u);
      assert.doesNotMatch(presentation.story.narrative.summary, /"ok"|"review"|aql_chain_column_/u);
    }
    const englishJoins = english.story.occurrences.filter(step => step.operator === 'join');
    const japaneseJoins = japanese.story.occurrences.filter(step => step.operator === 'join');
    assert.match(englishJoins[0].explanation.text, /Match "Opportunity" from "salesforce" with "files" from "drive" on "name"/u);
    assert.match(englishJoins[1].explanation.text, /the joined rows with "contents" from "drive" on the Source keys "resource", "version"/u);
    assert.match(japaneseJoins[0].explanation.text, /"salesforce" の "Opportunity".*"name"/u);
    assert.deepEqual(english.plan.stageResultLinks, context.stage_result_links);
    assert.equal(context.stage_result_links.length, 2);
    const flow = flowPresentation(english.plan);
    for (const {producer, consumer} of context.stage_result_links) {
      const edge = flow.edges.find(edge => edge.id === consumer.port_id);
      assert.equal(edge?.source, producer.step_id);
      assert.equal(edge.sourceHandle, producer.port_id);
      assert.equal(edge.target, consumer.step_id);
      assert.equal(edge.targetHandle, consumer.port_id);
    }
    const foreign = structuredClone(explanation);
    const [first, second] = foreign.context.stage_result_links;
    first.producer.step_id = second.consumer.step_id;
    assert.throws(() => staticExplanationReadModel(foreign, {render, locale: 'en'}),
      {code: 'ExplorerInvalidExplanation'});
    foreign.context.stage_result_links = [second, structuredClone(second)];
    assert.throws(() => staticExplanationReadModel(foreign, {render, locale: 'en'}),
      {code: 'ExplorerInvalidExplanation'});
    assert.doesNotMatch(english.story.narrative.summary, /[0-9]+ logical joins/u);
    assert.deepEqual(english.story.narrative.clauses.find(clause => clause.kind === 'join').step_ids,
      facts.steps.filter(step => step.operator === 'join').map(step => step.step_id));
    assert.equal(english.context[3].text, 'Apply model task "model-task:deal-review.v1" to each input row');
    assert.equal(japanese.context[3].text, 'モデルタスク "model-task:deal-review.v1" を各入力行に適用');
    assert.equal(english.context[4].text, 'Declare Result "updates"');
    assert.match(english.context[5].text, /Declared write update "connector:\/\/salesforce\/Opportunity".*Contract minimum approval: required.*Current decision unknown/u);
    assert.match(japanese.context[5].text, /^宣言された書き込み 更新 /u);
    assert.match(japanese.context[5].text, /契約上の最低承認要件 必要.*現在の判断は不明/u);
    assert.equal(englishJoins.length, 3);
    assert.deepEqual(japaneseJoins.map(step => step.stepId), englishJoins.map(step => step.stepId));
    assert(englishJoins.every(step => step.explanation.text.includes('Null keys:')));
    assert(japaneseJoins.every(step => step.explanation.text.includes('NULLキー:')));
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


test('installed static SDK explains effect-free SQL, Source JOIN and Source INFER without starting a Run', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-static-pure-',
    label: 'effect-free static Explanation'});
  const project = scaffoldProject(join(scratch.path, 'project'), 'deal-review-mock');
  const cwd = process.cwd();
  let client, primary, phase = 'open';
  process.chdir(project.directory);
  try {
    const target = await readFile('mock/data.json');
    const records = [];
    const authorization = {accountConfiguration: JSON.stringify({
      version: 'actql-execution-account-config/0.1', account_id: 'effect-free-static',
      entries: [{entry_id: 'describe', outcome: 'allow', principal: {all: true}, connection: {all: true},
        resource: {any_of: ['run']}, operation: {any_of: ['read']}, exclusions: []}],
    })};
    const observation = createHostObservationConnection({include: ['source', 'infer', 'compute', 'effect', 'run'],
      deliver: record => records.push(record)});
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
      installation: {directory: '.actql-node', authorization, observation}});
    const original = await readFile('deal-review.aql', 'utf8');
    const readOnly = original.split('|> EFFECT')[0].trim();
    assert.notEqual(readOnly, original);
    for (const [label, source, format, expected] of [
      ['SELECT', 'SELECT 1 AS answer', 'sql', ['result']],
      ['JOIN', 'SELECT o.id AS id FROM salesforce.opportunities AS o\n' +
        'JOIN drive.files AS f ON f.name = o.name\n|> RESULT joined', 'aql',
        ['source', 'source', 'result']],
      ['INFER', readOnly, 'aql', ['source', 'source', 'source', 'model_task', 'result']],
    ]) {
      phase = label;
      const {plan, facts, context, version} = await client.explain(source, {format});
      assert.equal(version, 'actql-static-explanation/0.1');
      assert.equal(plan.version, 'actql-plan-view/0.1');
      assert.equal(plan.provider_io, 0);
      assert.equal(context.binding.compiled_plan_cid, plan.compiled_plan_cid);
      assert.equal(context.binding.program_definition_cid, plan.logical_map.program_definition_cid);
      assert.equal(facts.parameter_values_cid, context.binding.parameter_values_cid);
      assert.equal(context.binding.logical_map_cid, plan.logical_map.self_cid);
      assert.equal(facts.logical_map_cid, plan.logical_map.self_cid);
      assert.deepEqual(context.items.map(item => item.kind), expected);
      assert.deepEqual(facts.steps.map(step => step.step_id), plan.logical_map.steps.map(step => step.step_id));
      if (label === 'JOIN') assert(facts.steps.some(step => step.meaning.kind === 'join'));
      if (label === 'INFER') {
        const model = context.items.find(item => item.kind === 'model_task');
        assert.equal(model.task_id, 'model-task:deal-review.v1');
        assert.deepEqual(model.input_bindings.map(input => input.role).sort(), ['NextStep', 'StageName', 'notes']);
      }
    }
    phase = 'first close';
    await client.close();
    client = undefined;
    assert.deepEqual(await readFile('mock/data.json'), target);
    const status = observation.status();
    assert.deepEqual(status.loss, {});
    assert.equal(status.closed, true);
    assert.equal(status.dropped, 0);
    assert(!records.some(record => record.attributes['actql.run.definition_cid'] !== undefined ||
      ['attempt_started', 'task_started', 'application_observed', 'write_observed'].includes(record.event)));
    const journal = new DatabaseSync(join('.actql-node', 'requests', 'client-requests.sqlite3'), {readOnly: true});
    try {assert.equal(journal.prepare('SELECT COUNT(*) AS total FROM client_requests').get().total, 0);}
    finally {journal.close();}
  } catch (error) {
    primary = error;
    t.diagnostic(JSON.stringify({phase, retainedScratch: scratch.path, code: error?.code}));
  } finally {
    try {await client?.close();}
    catch (error) {primary = primary === undefined ? error :
      new AggregateError([primary, error], 'Effect-free explanation and cleanup failed');}
    finally {process.chdir(cwd);}
  }
  if (primary !== undefined) throw primary;
  scratch.passed();
  scratch.close();
});

// Two original Sources exercise the ordinary and larger Effect Run
// admissions before a fresh Host opens the committed originals.
for (const [name, declaredSources] of [['churn-risk', 2], ['deal-review', 3]]) {
  test(`installed Saved Context restores original ${name} Plan and Facts after Host close`, async t => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-saved-context-',
      label: `original ${name} Saved Context`});
    const project = scaffoldProject(join(scratch.path, 'project'), `${name}-mock`);
    const cwd = process.cwd();
    let client, primary, phase = 'initialization';
    const close = async () => {
      const original = client;
      client = undefined;
      await original?.close();
    };
    process.chdir(project.directory);
    try {
      const before = await readFile('mock/data.json');
      const records = [];
      const open = () => connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
        installation: {directory: '.actql-node',
          observation: createHostObservationConnection({deliver: record => records.push(record)})}});
      client = await open();
      phase = 'submit original';
      const run = await client.startSource(await readFile(`${name}.aql`, 'utf8'),
        {format: 'aql', stopBefore: 'commit'});
      assert.equal((await run.wait()).status, 'waiting_checkpoint');
      const ref = structuredClone(run.ref);
      const originalStarts = () => records.filter(record =>
        ['attempt_started', 'task_started', 'write_observed'].includes(record.event) &&
        record.attributes['actql.run.definition_cid'] === ref.runDefinitionCid);
      for (let turn = 0; turn < 512 && originalStarts().filter(record =>
        record.operation === 'source' && record.event === 'attempt_started').length < 2;
        turn++) await setImmediate();
      assert.equal(originalStarts().filter(record =>
        record.operation === 'source' && record.event === 'attempt_started').length, 2);
      phase = 'warm Saved Context';
      const warm = await run.explainContext();
      assert.deepEqual(warm.run_ref, ref);
      assert.equal(warm.explanation.state, 'projected');
      const {plan, context, facts} = warm.explanation.view;
      assert.deepEqual(context.items.map(item => item.kind),
        [...Array(declaredSources).fill('source'), 'model_task', 'result', 'effect_set']);
      assert.equal(context.stage_result_links.length, 2);
      assert.deepEqual((await run.plan()).plan_view, plan);
      assert.equal(context.binding.logical_map_cid, plan.logical_map.self_cid);
      assert.equal(facts.logical_map_cid, plan.logical_map.self_cid);
      phase = 'warm legacy Facts';
      assert.deepEqual((await run.explain()).explanation.facts, facts);
      phase = 'original Host close';
      await close();
      const starts = originalStarts();
      assert(starts.some(record => record.operation === 'infer' && record.event === 'attempt_started'));
      assert(!starts.some(record => record.event === 'write_observed'));
      phase = 'cold Host reopen and attach';
      client = await open();
      const saved = await client.attach(ref);
      phase = 'cold Saved Context';
      assert.deepEqual(await saved.explainContext(), warm);
      assert.deepEqual((await saved.plan()).plan_view, plan);
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
      await close();
      assert.deepEqual(originalStarts(), starts);
      assert.deepEqual(await readFile('mock/data.json'), before);
    } catch (error) {
      primary = error;
      t.diagnostic(JSON.stringify({phase, retainedScratch: scratch.path, code: error?.code}));
    } finally {
      try {await close();}
      catch (error) {
        t.diagnostic(JSON.stringify({phase: 'first Host close', code: error?.code,
          cause: error?.cause?.code}));
        primary = primary === undefined ? error
        : new AggregateError([primary, error], 'Saved Context read and Host cleanup failed');}
      finally {process.chdir(cwd);}
    }
    if (primary !== undefined) throw primary;
    scratch.passed();
    scratch.close();
  });
}

test('public Effectful Explain projects one checked parameter, field and redacted literal without admitting a Run', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-effectful-explain-inputs-',
    label: 'ordinary Effectful Explain checked Model inputs'});
  const project = scaffoldProject(join(scratch.path, 'project'), 'deal-review-mock');
  const program = twoModelDealReviewProgram(projectTemplateFiles('deal-review-mock'));
  const [review, , apply] = program.stages;
  program.stages = [review, apply];
  apply.inputs.confirmed.result.stage = review.id;
  for (const step of apply.steps) {
    if (step.select !== undefined) step.select = step.select.filter(name => name !== 'confirmation');
  }
  for (const result of Object.values(apply.results)) {
    result.fields = result.fields.filter(name => name !== 'confirmation');
  }
  program.params = {input_text: {type: 'string', nullable: false}};
  const privateLiteral = 'effectful_fixture_private_literal';
  const privateValues = ['effectful_fixture_param_a', 'effectful_fixture_param_b'];
  review.steps.find(step => step.infer !== undefined).infer.input = {
    StageName: {$param: 'input_text'}, NextStep: {literal: privateLiteral}, notes: {field: 'notes'},
  };

  const records = [];
  const observer = createHostObservationConnection({include: ['source', 'infer', 'compute', 'effect', 'run'],
    deliver: record => records.push(record)});
  const cwd = process.cwd();
  const target = join(project.directory, 'mock/data.json');
  const initialTarget = await readFile(target);
  let client, primary;
  process.chdir(project.directory);
  try {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
      installation: {directory: '.actql-node', observation: observer}});
    const parameterCids = [];
    for (const input_text of privateValues) {
      const parameters = {input_text};
      const response = await client.explain(program, {parameters});
      const {plan, facts, context} = response;
      assert.equal(plan.version, 'actql-effectful-static-plan-view/0.1');
      assert.equal(plan.provider_io, 0);
      assert.equal(context.binding.parameter_values_cid, plan.parameter_values_cid);
      assert.equal(facts.parameter_values_cid, plan.parameter_values_cid);
      assert.equal(context.binding.logical_map_cid, plan.computation.plan_view.logical_map.self_cid);
      const model = context.items.find(item => item.kind === 'model_task');
      assert.equal(model.task_id, 'model-task:deal-review.v1');
      assert.deepEqual(Object.fromEntries(model.input_bindings.map(({role, binding}) => [role, binding])), {
        StageName: {state: 'parameter', name: 'input_text'}, NextStep: {state: 'redacted'},
        notes: {state: 'field', name: 'notes'},
      });
      const parameter = model.input_bindings.find(item => item.role === 'StageName');
      assert.deepEqual(parameter.type, {kind: 'string', nullable: false, projection: 'shape_and_nullability'});
      const wire = JSON.stringify(response);
      for (const undisclosed of [...privateValues, privateLiteral]) assert(!wire.includes(undisclosed));
      parameterCids.push(plan.parameter_values_cid);
    }
    assert.notEqual(...parameterCids);
  } catch (error) {primary = error;}
  finally {
    try {await client?.close();}
    catch (error) {primary = primary === undefined ? error
      : new AggregateError([primary, error], 'Effectful Explain and first Host close failed');}
    finally {process.chdir(cwd);}
  }
  if (primary !== undefined) throw primary;
  assert.deepEqual(await readFile(target), initialTarget);
  const status = observer.status();
  assert.equal(status.closed, true);
  assert.equal(status.dropped, 0);
  assert.deepEqual(status.loss, {});
  assert(!records.some(record => record.attributes['actql.run.definition_cid'] !== undefined ||
    ['attempt_started', 'task_started', 'application_observed', 'write_observed'].includes(record.event)));

  // Read the actual normal Journal after its first close. Provider I/O=0 and
  // absence of delivery markers alone cannot prove no durable Run was admitted.
  const journal = new DatabaseSync(join(project.directory, '.actql-node', 'requests', 'client-requests.sqlite3'),
    {readOnly: true});
  try {assert.equal(journal.prepare('SELECT COUNT(*) AS total FROM client_requests').get().total, 0);}
  finally {journal.close();}
  scratch.passed();
  scratch.close();
});
test('a cold Saved Result has no live managed resource observation', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-saved-resource-observation-',
    label: 'cold Saved Result resource observation'});
  const project = scaffoldProject(join(scratch.path, 'project'), 'deal-review-mock');
  const cwd = process.cwd();
  let client, primary;
  process.chdir(project.directory);
  try {
    const open = observation => connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
      installation: {directory: '.actql-node', observation}});
    client = await open(undefined);
    const execution = await client.startSource('SELECT 1 AS answer', {format: 'sql'});
    assert.equal((await execution.wait()).status, 'succeeded');
    const ref = structuredClone(execution.ref);
    await client.close();
    client = undefined;

    const records = [];
    const observer = createHostObservationConnection({include: ['compute'],
      deliver: record => records.push(record)});
    client = await open(observer);
    const saved = await client.attach(ref);
    assert.deepEqual(await saved.result('main').all(), [{answer: 1}]);
    await client.close();
    client = undefined;
    const status = observer.status();
    assert.equal(status.closed, true);
    assert.equal(status.dropped, 0);
    assert.deepEqual(status.loss, {});
    assert.deepEqual(records, [], 'A cold Result does not create a live managed resource observation');
  } catch (error) {
    primary = error;
    t.diagnostic(JSON.stringify({retainedScratch: scratch.path, code: error?.code}));
  } finally {
    try {await client?.close();}
    catch (error) {primary = primary === undefined ? error :
      new AggregateError([primary, error], 'Saved Result read and Host cleanup failed');}
    finally {process.chdir(cwd);}
  }
  if (primary !== undefined) throw primary;
  scratch.passed();
  scratch.close();
});
