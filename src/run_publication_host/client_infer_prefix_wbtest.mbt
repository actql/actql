///|
fn client_infer_prefix_test_program(
  result_fields? : String = "[\"id\",\"outcome\",\"value\"]",
  strict? : Bool = false,
) -> PreparedClientProgram {
  // Reuse the independently hashed ModelTask typing vector. These dependency
  // CIDs prove installation identity, not provider or egress authority.
  let task =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let unsigned = run_materials_environment_wire
    .replace(
      old="\"evidence_bundle_cid\":\"" + run_materials_environment_cid + "\",",
      new="",
    )
    .replace(
      old="\"model_task_contracts\":[]",
      new="\"model_task_contracts\":[" + task + "]",
    )
  let cid = "sha256:" + @sha.hex(@utf8.encode(unsigned))
  let wire = unsigned.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  let environment = admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let source =
    #|{"version":"actql/0.1","id":"infer-prefix","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"input"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}],"results":{"captured":{"from":"captured","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"captured"}}}}
  prepare_effect_free_client_program(
    source
    .replace(
      old="\"fields\":[\"id\",\"outcome\",\"value\"]",
      new="\"fields\":" + result_fields,
    )
    .replace(
      old="\"key\":\"id\",\"input\":",
      new=if strict {
        "\"key\":\"id\",\"on_non_success\":\"fail\",\"input\":"
      } else {
        "\"key\":\"id\",\"input\":"
      },
    ),
    Json,
    environment,
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "Infer prefix compilation preserves the checked owner and pure limits" {
  let prepared = client_infer_prefix_test_program()
  let owner = client_infer_prefix_owner(prepared, 0, 2).unwrap()
  let infer_output = @lower.node_at(@lower.bound_preparation(owner), 2).unwrap()
  guard @lower.payload(infer_output) is @lower.Infer(infer) else {
    abort("checked Infer fixture")
  }
  assert_eq(
    @lower.infer_output_binding(owner, 2, infer, @pipeline.Step(1)),
    Some(@lower.node_id(infer_output)),
  )
  assert_true(
    @lower.infer_output_binding(owner, 1, infer, @pipeline.Step(1)) is None,
  )
  assert_true(
    @lower.infer_output_binding(owner, 2, infer, @pipeline.Step(0)) is None,
  )
  let foreign_owner = client_infer_prefix_owner(
    client_infer_prefix_test_program(),
    0,
    2,
  ).unwrap()
  assert_true(
    @lower.infer_output_binding(foreign_owner, 2, infer, @pipeline.Step(1))
    is None,
  )
  assert_true(
    physical_equal(
      owner,
      @strategy.graph_task_owner(prepared.graph, 0).unwrap(),
    ),
  )
  let limits = run_materials_limits().sequence
  let sequence = @lower.prepare_sequence_prefix(owner, 1, limits).unwrap()
  assert_true(physical_equal(@lower.sequence_owner(sequence), owner))
  assert_eq(@lower.sequence_count(sequence), 2)
  assert_true(
    @lower.prepare_sequence(owner, limits)
    is Err(@lower.KernelFailure(2, @lower.MissingKernelNode)),
  )
  let fragment = issue_prepared_client_infer_prefix_fragment(
    prepared,
    0,
    2,
    { ..limits, max_steps: 2, },
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(fragment.node_id, "task_0_before_infer_2")
  assert_eq(fragment.output_carrier, "relation")
  let output = @lower.node_at(@lower.bound_preparation(owner), 1).unwrap()
  assert_eq(fragment.output_port, @lower.node_id(output))
  let contract = client_task_carrier_contract(
    @lower.node_output_carrier(output),
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(fragment.output_contract_cid, contract.1)
  assert_true(
    issue_prepared_client_infer_prefix_fragment(
      prepared,
      0,
      2,
      { ..limits, max_steps: 1, },
      100000,
      10000,
      100,
    )
    is Err(Pipeline(Sequence(@lower.SequenceLimit))),
  )
  assert_true(
    issue_prepared_client_infer_prefix_fragment(
      prepared, 0, 2, limits, 1, 10000, 100,
    )
    is Err(Pipeline(ClientTaskPipelineIssue::Encoding)),
  )
  assert_true(
    issue_prepared_client_infer_prefix_fragment(
      prepared, 0, 2, limits, 0, 10000, 100,
    )
    is Err(InvalidLimits),
  )
  assert_true(client_infer_prefix_owner(prepared, 1, 2) is None)
  for step in [0, 1, 3] {
    assert_true(client_infer_prefix_owner(prepared, 0, step) is None)
  }
  assert_true(
    issue_prepared_client_task_fragment(prepared, 0, limits, 100000, 10000, 100)
    is Err(
      Pipeline(Sequence(@lower.KernelFailure(2, @lower.MissingKernelNode)))
    ),
  )
  assert_true(
    issue_prepared_client_task_plan_graph(prepared, limits, 100000, 10000, 100)
    is Err(
      Fragment(
        Pipeline(Sequence(@lower.KernelFailure(2, @lower.MissingKernelNode)))
      )
    ),
  )
}
