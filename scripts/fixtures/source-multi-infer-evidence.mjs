// Independent application inputs and expected results. Neither is extracted
// from a checker, planner, Model response, or Evidence manifest.
import {canonical, cid, configuration as singleConfiguration} from './installed-infer-fixture.mjs';
export const sourceRows = Object.freeze([
  Object.freeze({id: 2, amount: 'é\n'}),
  Object.freeze({id: 1, amount: 'e\u0301\r'}),
]);

const inferStage = (id, target, contract) => ({id,
  inputs: {items: {result: {stage: 'source', result: 'rows'}}},
  steps: [{assert_rows: {unique_by: ['id']}},
    {infer: {contract, key: 'id', input: {text: {field: 'amount'}}}, as: target}],
  results: {rows: {from: target, fields: ['id', 'outcome', 'value']}},
});

export const program = {
  version: 'actql/0.1', id: 'source-multi-infer-evidence',
  stages: [{id: 'source', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{filter: 'id = id'}, {select: ['id', 'amount'], as: 'captured'}],
    results: {rows: {from: 'captured', fields: ['id', 'amount']}}},
  inferStage('first', 'first_assessment', 'model-task:first-assessment.v1'),
  inferStage('second', 'second_assessment', 'model-task:second-assessment.v1'),
  {id: 'combine', inputs: {
    first: {result: {stage: 'first', result: 'rows'}},
    second: {result: {stage: 'second', result: 'rows'}},
  }, steps: [{from: 'first', join: {with: 'second', kind: 'inner', cardinality: 'one_to_one',
    max_output_rows: 2, on: [{left: 'id', right: 'id'}], select: {
      id: 'left.id', first_outcome: 'left.outcome', first: 'left.value',
      second_outcome: 'right.outcome', second: 'right.value',
    }}}, {sort: [{id: 'asc'}], as: 'ordered'}],
  results: {rows: {from: 'ordered', fields: ['id', 'first_outcome', 'first', 'second_outcome', 'second']}}}],
  results: {answer: {from: {stage: 'combine', result: 'rows'}}},
};

export const expected = Object.freeze([
  {id: 1, first_outcome: 'ok', first: {risk: 'low', reason: 'e\u0301\r'},
    second_outcome: 'ok', second: {risk: 'low', reason: 'e\u0301\r'}},
  {id: 2, first_outcome: 'ok', first: {risk: 'low', reason: 'é\n'},
    second_outcome: 'ok', second: {risk: 'low', reason: 'é\n'}},
]);

// The same typed key in two logical INFERs is two legitimate occurrences.
// Source row order is deliberately the reverse of canonical key order.
export const expectedItems = Object.freeze([
  {target: 'first_assessment', key: [1], keyContracts: [{type: 'number', nullable: false}], text: 'e\u0301\r'},
  {target: 'first_assessment', key: [2], keyContracts: [{type: 'number', nullable: false}], text: 'é\n'},
  {target: 'second_assessment', key: [1], keyContracts: [{type: 'number', nullable: false}], text: 'e\u0301\r'},
  {target: 'second_assessment', key: [2], keyContracts: [{type: 'number', nullable: false}], text: 'é\n'},
]);

// Independent typed key preimages under actql-model-input-key/0.1. The same
// number key has the same typed identity in both independent logical INFERs.
export const expectedInputKeyCids = Object.freeze(Object.fromEntries([1, 2].map(value => [value,
  cid({version: 'actql-model-input-key/0.1', components: [{field: 'id',
    value_contract_cid: cid({nullable: false, type: 'number'}), value_cid: cid(value)}]})])));

// Authored from the Source and Model contracts, including non-success NULL
// output in the default outcomes mode. Never inferred from Result output.
const assessmentContract = {type: 'object', nullable: true, additional_properties: false,
  fields: {reason: {type: 'string', nullable: true}, risk: {type: 'string', nullable: false}}};
export const expectedColumns = Object.freeze([
  {name: 'id', contract: {type: 'number', nullable: false}},
  {name: 'first_outcome', contract: {type: 'string', nullable: false}},
  {name: 'first', contract: assessmentContract},
  {name: 'second_outcome', contract: {type: 'string', nullable: false}},
  {name: 'second', contract: assessmentContract},
]);

export const instructionsA = 'Classify exact lowercase urgent.';
export const instructionsB = 'Classify urgency without case sensitivity.';
export const unchangedInstructions = 'Return the original text independently.';
const selectionRows = [{id: 2, amount: 'ordinary'}, {id: 1, amount: 'URGENT'}];
const finalRows = [{id: 2, amount: 'not urgent'}, {id: 1, amount: 'urgent'}];
// The labels and expected rows are authored independently of provider output.
// Final cases are not exposed to selection or used to revise the winner.
export const scenarios = {
  unicode: {rows: sourceRows, expected, firstInstructions: 'Return the original text.',
    secondInstructions: unchangedInstructions},
  A: {rows: selectionRows, firstInstructions: instructionsA, secondInstructions: unchangedInstructions,
    expected: [
      {id: 1, first_outcome: 'ok', first: {risk: 'low', reason: 'URGENT'}, second_outcome: 'ok', second: {risk: 'low', reason: 'URGENT'}},
      {id: 2, first_outcome: 'ok', first: {risk: 'low', reason: 'ordinary'}, second_outcome: 'ok', second: {risk: 'low', reason: 'ordinary'}},
    ]},
  B: {rows: selectionRows, firstInstructions: instructionsB, secondInstructions: unchangedInstructions,
    expected: [
      {id: 1, first_outcome: 'ok', first: {risk: 'high', reason: 'URGENT'}, second_outcome: 'ok', second: {risk: 'low', reason: 'URGENT'}},
      {id: 2, first_outcome: 'ok', first: {risk: 'low', reason: 'ordinary'}, second_outcome: 'ok', second: {risk: 'low', reason: 'ordinary'}},
    ]},
  final: {rows: finalRows, firstInstructions: instructionsB, secondInstructions: unchangedInstructions,
    expected: [
      {id: 1, first_outcome: 'ok', first: {risk: 'high', reason: 'urgent'}, second_outcome: 'ok', second: {risk: 'low', reason: 'urgent'}},
      {id: 2, first_outcome: 'ok', first: {risk: 'low', reason: 'not urgent'}, second_outcome: 'ok', second: {risk: 'low', reason: 'not urgent'}},
    ]},
};

export function modelConfiguration(base, {firstInstructions = 'Return the original text.',
  secondInstructions = 'Return the original text independently.'} = {}) {
  const configurations = [firstInstructions, secondInstructions].map((instructions, index) => {
    const configured = singleConfiguration(base, {instructions});
    const environment = JSON.parse(configured.installation.environmentWire);
    delete environment.evidence_bundle_cid;
    const task = environment.model_task_contracts[0];
    delete task.contract_cid;
    task.task_id = index === 0 ? 'model-task:first-assessment.v1' : 'model-task:second-assessment.v1';
    const taskCid = cid(task);
    environment.model_task_contracts = [{...task, contract_cid: taskCid}];
    const execution = JSON.parse(configured.installation.executionContracts[0].bodyWire);
    delete execution.self_cid;
    execution.model_task_contract_cid = taskCid;
    // Two independently admitted item calls, without provider batching/retries.
    execution.max_total_attempts = 2;
    execution.max_total_duration_ms = 1000;
    execution.max_total_wire_bytes = 133072;
    execution.max_total_token_reservation = 66;
    return {taskCid, task: environment.model_task_contracts[0],
      dependencies: configured.installation.dependencyBodies,
      execution: {modelTaskCid: taskCid, cid: cid(execution),
        bodyWire: canonical({...execution, self_cid: cid(execution)})}};
  });
  const environment = structuredClone(base);
  delete environment.evidence_bundle_cid;
  environment.model_task_contracts = configurations.map(value => value.task)
    .sort((a, b) => cid(a) < cid(b) ? -1 : cid(a) > cid(b) ? 1 : 0);
  const dependencies = new Map(configurations.flatMap(value => value.dependencies)
    .map(value => [value.cid, value]));
  // Preserve these same authored DATA originals for the funded Request reader.
  // Freezing changes no contract bytes, identity or admission expectation.
  return {tasks: configurations.map(value => value.task), installation: Object.freeze({
    environmentWire: canonical({...environment, evidence_bundle_cid: cid(environment)}),
    executionContracts: Object.freeze(configurations.map(value => Object.freeze(value.execution))),
    dependencyBodies: Object.freeze([...dependencies.values()]),
  })};
}

// Reissue the owned synthetic Source metadata together. This declares the
// original input's policy; it never relabels Model output provenance.
export function sourceEnvironment(original, hostProfile) {
  const source = structuredClone(original);
  const policy = source.contract_registry.find(value => value.kind === 'data_policy');
  const {cid: oldPolicy, ...policyBody} = policy;
  if (cid(policyBody) !== oldPolicy) throw new Error('SourceFixturePolicyMismatch');
  policy.body.classification = 'public';
  policy.cid = cid({...policyBody, body: policy.body});
  const schema = source.contract_registry.find(value => value.kind === 'carrier_schema');
  const {cid: oldSchema, ...schemaBody} = schema;
  if (cid(schemaBody) !== oldSchema) throw new Error('SourceFixtureSchemaMismatch');
  schema.body.fields.amount = {nullable: true, type: 'string'};
  schema.cid = cid({...schemaBody, body: schema.body});
  const view = source.source_views[0];
  const {contract_cid: oldView, ...viewBody} = view;
  if (cid(viewBody) !== oldView) throw new Error('SourceFixtureViewMismatch');
  view.output.data_policy.cid = policy.cid;
  view.output.schema.cid = schema.cid;
  view.contract_cid = cid({...viewBody, output: view.output});
  const catalog = source.connector_catalogs[0];
  catalog.contracts = structuredClone(source.contract_registry).sort((a, b) => a.cid < b.cid ? -1 : a.cid > b.cid ? 1 : 0);
  catalog.source_views = [structuredClone(view)];
  delete catalog.catalog_cid;
  catalog.catalog_cid = cid(catalog);
  for (const capability of source.connector_capabilities) {
    capability.source_contract_cid = view.contract_cid;
    capability.source_view_contract_cid = view.contract_cid;
    capability.capability_contract_cids.push('sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d');
    capability.capability_contract_cids.sort();
  }
  for (const snapshot of source.schema_snapshots) {
    snapshot.carrier_schema_contract_cid = schema.cid;
    snapshot.source_contract_cid = view.contract_cid;
    snapshot.source_view_contract_cid = view.contract_cid;
    snapshot.source_data_policy_cid = policy.cid;
    snapshot.data_classification = 'public';
  }
  source.host_policy_profile = hostProfile;
  delete source.evidence_bundle_cid;
  source.evidence_bundle_cid = cid(source);
  return source;
}
