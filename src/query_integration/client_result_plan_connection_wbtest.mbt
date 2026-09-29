///|
test "checked Result Plan routes ordering through a separate exact fragment" {
  let (_, environment, limits) = local_effect_export_fixture()
  let document =
    #|{"version":"actql/0.1","id":"result-plan-connection","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3},{"id":1},{"id":2}]},"as":"selected"}],"results":{"ordered":{"from":"selected","fields":["id"],"order_by":[{"id":"desc"}]},"unchanged":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"ordered"}},"original":{"from":{"stage":"source","result":"unchanged"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    limits.program,
  ).unwrap()
  let sequence : @lower.SequenceLimits = {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }
  assert_true(
    @publication_host.issue_prepared_client_direct_values_result_root(
      prepared, 0, sequence, 100000, 10000, 100,
    )
    is Err(RequiresResultTransformation),
  )
  let values = @publication_host.client_values_plan_graph_wire(
    @publication_host.issue_prepared_client_values_plan_graph(
      prepared, sequence, 100000, 10000, 100,
    ).unwrap(),
  )
  let tasks = @publication_host.client_task_plan_graph_wire(
    @publication_host.issue_prepared_client_task_plan_graph(
      prepared, sequence, 100000, 10000, 100,
    ).unwrap(),
  )
  // Independent structural expectation, not another call into the issuer.
  let expected_pipeline =
    #|{"output":"ordered","sources":{"input_0":{"sort":"relation"}},"steps":[{"id":"projected","in":["input_0"],"op":"REL.select","params":{"columns":["id"]}},{"id":"ordered","in":["projected"],"op":"REL.orderByStable","params":{"by":[{"dir":"desc","field":"id","nulls":"last"}]}}],"version":"aoa-pipeline/0.1"}
  let expected_root =
    #|{"name":"answer","ref":{"node_id":"result_0","port":"ordered"},"role":"requested_result"}
  let expected_edge =
    #|"to":{"node_id":"result_0","port":"input_0"}
  for graph in [values, tasks] {
    assert_true(graph.contains("\"pipeline\":" + expected_pipeline))
    assert_true(graph.contains(expected_root))
    assert_true(graph.contains(expected_edge))
    assert_false(graph.contains("\"node_id\":\"result_1\""))
  }
  assert_true(
    @publication_host.admit_prepared_client_values_plan_graph(
      prepared,
      values.replace(old="\"desc\"", new="\"asc\""),
      sequence,
      100000,
      10000,
      100,
    )
    is Err(MismatchedGraph),
  )
  assert_true(
    @publication_host.admit_prepared_client_task_plan_graph(
      prepared,
      tasks.replace(old="\"result_0\"", new="\"task_0\""),
      sequence,
      100000,
      10000,
      100,
    )
    is Err(MismatchedGraph),
  )
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  assert_true(
    @publication_host.issue_prepared_client_values_compilation(
      prepared, manifests, sequence, 32, 64, 100000, 10000, 100,
    )
    is Ok(_),
  )
  assert_true(
    @publication_host.issue_prepared_client_task_compilation(
      prepared, manifests, sequence, 32, 64, 100000, 10000, 100,
    )
    is Ok(_),
  )
  // The logical identity must include publication transformations, not just
  // the unchanged Values producer. Parse the independently changed Program.
  let ascending = @publication_host.prepare_effect_free_client_program(
    document.replace(old="\"desc\"", new="\"asc\""),
    Json,
    environment,
    None,
    limits.program,
  ).unwrap()
  let logical = fn(owner) {
    let compilation = @publication_host.issue_prepared_client_values_compilation(
      owner, manifests, sequence, 32, 64, 100000, 10000, 100,
    ).unwrap()
    let body = @publication.publication_contract_json(
      @publication_host.client_values_compilation_compiled_plan(compilation),
    )
    guard (@json.parse(body) catch { _ => abort("invalid JSON") })
      is Object(fields) else {
      abort("invalid compiled Plan")
    }
    fields.get("aoa_logical_cid").unwrap()
  }
  assert_false(logical(prepared) == logical(ascending))
  let policy = "sha256:" + "1".repeat(64)
  let compilation = @publication_host.issue_prepared_client_values_compilation(
    prepared, manifests, sequence, 32, 64, 100000, 10000, 100,
  ).unwrap()
  let compiled = @publication_host.issue_client_values_compiled_run(
    prepared, compilation, policy, policy, "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let selected = @publication_host.client_compiled_run_result_transformation(
      compiled, prepared, 0,
    )
    .unwrap()
    .unwrap()
  assert_true(
    @publication_host.client_result_transformation_matches(
      selected, prepared, 0,
    ),
  )
  assert_true(
    @publication_host.client_compiled_run_result_transformation(
      compiled, prepared, 1,
    )
    is Ok(None),
  )
  assert_true(
    @publication_host.client_compiled_run_result_transformation(
      compiled, prepared, 2,
    )
    is Err(ForeignOwner),
  )
  let duplicate = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    limits.program,
  ).unwrap()
  assert_true(
    @publication_host.client_compiled_run_result_transformation(
      compiled, duplicate, 0,
    )
    is Err(ForeignOwner),
  )
  assert_true(
    @publication_host.client_compiled_run_result_transformation(
      compiled, ascending, 0,
    )
    is Err(ForeignOwner),
  )
}
