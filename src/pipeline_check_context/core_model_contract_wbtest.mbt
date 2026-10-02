///|
fn core_model_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn core_model_operation() -> @pipeline.CheckedOperation {
  // Fixed task/schema CIDs come from the independently hashed ModelTask vector.
  let body =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    body +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @fixture_sha.hex(@wire_utf8.encode(prefix + suffix))
  let wire = @environment.read(
    @wire_utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix,
    ),
    cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 20, },
  ).unwrap()
  let tasks = @environment.check_model_tasks(wire, {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 20,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 100000,
  }).unwrap()
  let source =
    #|[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"rows"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}]
  let pipeline = @pipeline.check(
    core_model_cursor(source),
    [],
    None,
    None,
    {
      max_steps: 3,
      max_work: 100000,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
      max_tokens: 1000,
    },
    model_tasks=Some(tasks),
  ).unwrap()
  @pipeline.step_at(pipeline, 2).unwrap().operation
}

///|
fn core_model_builder(limits : CoreContractLimits) -> CoreContractBuilder {
  {
    limits,
    roots: [],
    bodies: [],
    seen: {},
    dependencies: {},
    work: 0,
    edges: 0,
    hash_limits: { max_bytes: 0, max_nodes: 0, max_depth: 0, },
    hash_bytes: 0,
    hash_nodes: 0,
  }
}

///|
test "model acquisition keeps exact task dependencies and source occurrences" {
  let operation = core_model_operation()
  let limits : CoreContractLimits = {
    max_work: 18,
    max_roots: 10,
    max_bodies: 4,
    max_edges: 8,
  }
  let builder = core_model_builder(limits)
  core_operation_count_root(builder, operation, 2, 3, 1)
  core_operation_count_root(builder, operation, 2, 3, 4)
  assert_eq(builder.work, 18)
  assert_eq(builder.edges, 8)
  assert_eq(builder.bodies.length(), 4)
  let expected = [
    "sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560", "sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7",
    "sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ]
  for index, root in builder.roots {
    assert_eq(
      root.site,
      OperationModelContract(2, 3, if index < 5 { 1 } else { 4 }, index % 5),
    )
    assert_eq(core_contract_cid(root.body), expected[index % 5])
  }
  let links = builder.dependencies.get(expected[0]).unwrap()
  assert_eq(links.targets.length(), 3)
  for
    short in [
      { ..limits, max_work: 17, },
      { ..limits, max_roots: 9, },
      { ..limits, max_bodies: 3, },
      { ..limits, max_edges: 7, },
    ] {
    let bounded = core_model_builder(short)
    let outcome = try {
      core_operation_count_root(bounded, operation, 2, 3, 1)
      core_operation_count_root(bounded, operation, 2, 3, 4)
      Ok(())
    } catch {
      CoreContractStop(issue) => Err(issue)
    }
    assert_eq(outcome, Err(BudgetExceeded))
  }
}
