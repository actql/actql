// Independent acceptance input for #182. One Program owns every operation;
// the harness installs fixtures and submits it, never runs its stages itself.
export const databaseRows = {
  left: [{id: 2, amount: 20}, {id: 1, amount: 10}, {id: 4, amount: 40}],
  right: [{id: 3, amount: 300}, {id: 1, amount: 100}, {id: 2, amount: 200}],
};

export const expectedClassified = [
  {id: 1, left_amount: 10, right_amount: 100, risk: 'low'},
  {id: 2, left_amount: 20, right_amount: 200, risk: 'high'},
];
export const expectedUpdates = [{id: 2, left_amount: 20, right_amount: 200,
  risk: 'high', target_id: 'a00000000000002', next_name: 'review-required'}];
export const expectedWrites = [{id: 'a00000000000002',
  body: {Name: 'review-required'}}];
export const expectedModelInputs = [100, 200];
export const classifiedColumns = [
  {name: 'id', contract: {type: 'number', nullable: false}},
  {name: 'left_amount', contract: {type: 'number', nullable: true}},
  {name: 'right_amount', contract: {type: 'number', nullable: true}},
  // Outcome filtering does not refine the nullable captured value contract.
  {name: 'risk', contract: {type: 'string', nullable: true}},
];
export const updateColumns = [...classifiedColumns,
  // These two authored string literals each contain exactly 15 UTF-8 bytes.
  {name: 'target_id', contract: {type: 'string', nullable: false, max_utf8_bytes: 15}},
  {name: 'next_name', contract: {type: 'string', nullable: false, max_utf8_bytes: 15}},
];

export function compositionProgram(mappingRef) {
  const acquire = (id, connector) => ({id,
    inputs: {remote: {connector, resource: 'r'}},
    // Match A's acquired-input fixture: non-null IDs compare equal to themselves.
    // Both field leaves retain their admitted source policy before INFER.
    steps: [{filter: 'id = id'},
      {select: ['id', 'amount'], as: 'captured'}],
    results: {rows: {from: 'captured', fields: ['id', 'amount']}},
  });
  return {version: 'actql/0.1', id: 'fixture.composed-infer-effect', stages: [
    acquire('acquire_left', 'crm/main'),
    acquire('acquire_right', 'crm/right'),
    {id: 'classify', inputs: {
      left_rows: {result: {stage: 'acquire_left', result: 'rows'}},
      right_rows: {result: {stage: 'acquire_right', result: 'rows'}},
    }, steps: [
      {from: 'left_rows', join: {with: 'right_rows', kind: 'inner',
        on: [{left: 'id', right: 'id'}], max_output_rows: 10,
        select: {id: 'left.id', left_amount: 'left.amount',
          right_amount: 'right.amount'}}},
      {assert_rows: {unique_by: ['id']}, as: 'joined'},
      {infer: {contract: 'model-task:composition-risk.v1', key: 'id',
        input: {score: {field: 'right_amount'}}}, as: 'inferred'},
      // The existing KEEP lowering: retain original columns by exact key.
      {join: {with: 'joined', kind: 'inner', cardinality: 'one_to_one',
        on: [{left: 'id', right: 'id'}], select: {
          id: 'right.id', left_amount: 'right.left_amount',
          right_amount: 'right.right_amount', outcome: 'left.outcome',
          value: 'left.value'}}},
      {filter: {eq: [{field: 'outcome'}, {literal: 'ok'}]}},
      {derive: {risk: {property: {value: {field: 'value'}, name: 'risk'}}}},
      {select: ['id', 'left_amount', 'right_amount', 'risk']},
      {sort: [{id: 'asc'}], as: 'ordered'},
    ], results: {rows: {from: 'ordered',
      fields: ['id', 'left_amount', 'right_amount', 'risk']}}},
    {id: 'apply', inputs: {
      classified: {result: {stage: 'classify', result: 'rows'}},
    }, steps: [
      {filter: {eq: [{field: 'risk'}, {literal: 'high'}]}},
      {derive: {target_id: {literal: 'a00000000000002'},
        next_name: {literal: 'review-required'}}, as: 'updates'},
    ], results: {rows: {from: 'updates', fields: [
      'id', 'left_amount', 'right_amount', 'risk', 'target_id', 'next_name',
    ]}}, effects: {save: {update: {
      target: 'connector://crm-main/Test_Record__c', mapping: mappingRef,
      from: {result: 'rows'}, id: 'target_id',
      set: {Name: {field: 'next_name'}},
    }}}},
  ], results: {
    classified: {from: {stage: 'classify', result: 'rows'}},
    updates: {from: {stage: 'apply', result: 'rows'}},
  }};
}

// Installed contract and deterministic test provider remain separate from the
// Program. No real service, credential, charge or external write is involved.
export async function modelConfiguration(baseEnvironment) {
  const {canonical, cid} = await import('./installed-infer-fixture.mjs');
  const input = {type: 'object', nullable: false,
    additional_properties: false,
    fields: {score: {type: 'number', nullable: true}}};
  const output = {type: 'object', nullable: false,
    additional_properties: false,
    fields: {risk: {type: 'string', nullable: false}}};
  const bodies = [
    {version: 'actql-model-prompt/0.1', payload: {
      format: 'composition-risk/0.1', instructions: 'Classify the score.'}},
    {version: 'actql-model-retry-policy/0.1', retryable_failures: []},
    {version: 'actql-model-backoff/0.1', delays_ms: []},
  ].map(body => ({cid: cid(body),
    bodyWire: canonical({...body, self_cid: cid(body)})}));
  const task = {schema: 'actql.model_task/0.1',
    task_id: 'model-task:composition-risk.v1', version: '1',
    task_kind: 'structured_generate',
    authored_model_selector: 'composition-risk-model',
    connector_id: 'models/composition', input_contract: input,
    input_schema_cid: cid(input), output_contract: output,
    output_schema_cid: cid(output), prompt_template_cid: bodies[0].cid,
    max_items: 2, generation_config: {max_output_tokens: 32,
      seed_requested: -7, temperature: 0, top_p: 1},
    data_handling: {accepted_classifications: ['public', 'internal'],
      allowed_regions: ['fixture-region'],
      contract_cid: `sha256:${'a'.repeat(64)}`,
      retention: 'none', training_use: 'forbidden'},
    retrieval_policy: 'none', streaming: false, tool_policy: 'none'};
  const taskCid = cid(task);
  const {evidence_bundle_cid: ignored, ...environment} = baseEnvironment;
  void ignored;
  environment.model_task_contracts = [{...task, contract_cid: taskCid}];
  const execution = {version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: taskCid,
    retry_classification_contract_cid: bodies[1].cid,
    backoff_contract_cid: bodies[2].cid,
    max_attempts_per_slot: 1, max_total_attempts: 2,
    max_total_cost_units: 0, max_total_duration_ms: 1000,
    max_total_wire_bytes: 133072, max_total_token_reservation: 66,
    media_input_contracts: {}, default_publication: 'outcomes'};
  return {taskCid, installation: {
    environmentWire: canonical({...environment,
      evidence_bundle_cid: cid(environment)}),
    executionContracts: [{modelTaskCid: taskCid, cid: cid(execution),
      bodyWire: canonical({...execution, self_cid: cid(execution)})}],
    dependencyBodies: bodies,
  }};
}

export function registerCompositionModel(moon, taskCid, record, {cleanup = () => true} = {}) {
  const checked = value => {
    if (value?.$tag !== 1) throw new Error('CompositionModelAdmissionFailed');
    return value._0;
  };
  return [{providerId: 'models/composition',
    invoke() { throw new Error('UnpreparedCompositionModelCall'); },
    validatePrompt(actual, selector, wire) {
      return actual === taskCid && selector === 'composition-risk-model' &&
        JSON.parse(wire).format === 'composition-risk/0.1';
    },
    quantityCapacity: {
      limits: {tokens: 66n, costUnits: 0n, durationMs: 1000n},
      perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
    observeEgress: () => ({_0: 'public', _1: 'fixture-region',
      _2: false, _3: false}),
    physicalPreflight: request => moon.clientProgramModelRequestPreflight(
      () => ({_0: true, _1: checked(moon.clientProgramModelPhysicalRequestPlan(
        request, 1000n, 33n, 0n, 500n, () => {
          const score = JSON.parse(moon.clientProgramModelRequestInput(
            request, 'score'));
          record(score);
          return moon.clientProgramModelResponse(request,
            JSON.stringify({risk: score >= 200 ? 'high' : 'low'}),
            'composition-risk-model', 'composition-request-' + score,
            1n, 2n, new Date().toISOString());
        }))}), cleanup),
  }];
}

// These databases contain only this fixture's authored public rows. Reissue
// the declaration graph as a unit; do not relabel a captured provider result.
export async function publicFixtureEnvironment(original) {
  const {cid} = await import('./installed-infer-fixture.mjs');
  const environment = structuredClone(original);
  const policy = environment.contract_registry.find(item =>
    item.kind === 'data_policy');
  const {cid: oldPolicy, ...policyBody} = policy;
  if (cid(policyBody) !== oldPolicy) throw new Error('InvalidFixturePolicy');
  policy.body.classification = 'public';
  policy.cid = cid({...policyBody, body: policy.body});
  const view = environment.source_views[0];
  const {contract_cid: oldView, ...viewBody} = view;
  if (cid(viewBody) !== oldView) throw new Error('InvalidFixtureView');
  view.output.data_policy.cid = policy.cid;
  view.contract_cid = cid({...viewBody, output: view.output});
  for (const capability of environment.connector_capabilities) {
    if (capability.source_contract_cid !== oldView ||
        capability.source_view_contract_cid !== oldView) {
      throw new Error('InvalidFixtureSourceCapability');
    }
    capability.source_contract_cid = view.contract_cid;
    capability.source_view_contract_cid = view.contract_cid;
  }
  const catalog = environment.connector_catalogs[0];
  catalog.contracts = environment.contract_registry.map(item =>
    structuredClone(item)).sort((a, b) => a.cid < b.cid ? -1 : a.cid > b.cid ? 1 : 0);
  catalog.source_views = [structuredClone(view)];
  delete catalog.catalog_cid;
  catalog.catalog_cid = cid(catalog);
  for (const snapshot of environment.schema_snapshots) {
    snapshot.source_contract_cid = view.contract_cid;
    snapshot.source_view_contract_cid = view.contract_cid;
    snapshot.source_data_policy_cid = policy.cid;
    snapshot.data_classification = 'public';
  }
  delete environment.evidence_bundle_cid;
  environment.evidence_bundle_cid = cid(environment);
  return environment;
}

// Isolate the D-owned acquisition-to-Effect handoff while the acquired Infer
// owner is developed by A. This does not stand in for the full Program above.
export function twoSourceEffectProgram(mappingRef) {
  const full = compositionProgram(mappingRef);
  const joined = full.stages[2];
  const apply = full.stages[3];
  return {...full, id: 'fixture.two-source-effect', stages: [
    full.stages[0], full.stages[1],
    {...joined, steps: [joined.steps[0],
      {filter: 'right_amount >= 200'},
      {derive: {risk: {literal: 'high'}}}, ...apply.steps.slice(1)],
    results: apply.results, effects: apply.effects},
  ], results: {updates: {from: {stage: 'classify', result: 'rows'}}}};
}
