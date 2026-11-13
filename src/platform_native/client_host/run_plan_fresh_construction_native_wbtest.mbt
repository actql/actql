///|
test "fresh plan funded orchestration preserves exact small plan bytes and stops on each refusal" {
  let (_, prepared, compiled, definition) = journal_test_run(
    "fresh-plan-recipe", "fresh-plan-recipe-run",
  )
  let old = capture_native_run_plan_original(prepared, compiled, definition).unwrap()
  let mut calls = 0
  let mut valid_quotes = true
  let funded = capture_native_run_plan_original(
    prepared,
    compiled,
    definition,
    before_construction=Some((retained, execution, raw) => {
      valid_quotes = valid_quotes &&
        retained >= 0L &&
        execution >= retained &&
        raw > 0L
      calls += 1
      Ok(())
    }),
  ).unwrap()
  assert_eq(funded.original.view, old.original.view)
  assert_true(valid_quotes)
  assert_true(calls >= 3)
  for fail_at in 1..<=calls {
    let mut current = 0
    let result = capture_native_run_plan_original(
      prepared,
      compiled,
      definition,
      before_construction=Some((_, _, _) => {
        current += 1
        if current == fail_at {
          Err(CapacityExceeded)
        } else {
          Ok(())
        }
      }),
    )
    assert_true(result is Err(CapacityExceeded))
    assert_eq(current, fail_at)
  }
}

///|
test "fresh static codec quote requires body and complete schemas rather than a missing validator" {
  for
    name in ["logical_step_key", "logical_port_key", "logical_map", "plan_view"] {
    assert_true(
      native_fresh_plan_codec_layout(name, (65537, 1000, 16), 30) is Some(_),
    )
  }
  assert_true(
    native_fresh_plan_codec_layout("carrier_contract", (1000, 100, 8), 0)
    is None,
  )
  assert_true(
    native_fresh_plan_codec_layout("logical_map", (0, 100, 8), 0) is None,
  )
}

///|
test "fresh plan funding does not authorize a foreign checked owner" {
  let (_, prepared, _, _) = journal_test_run("foreign-plan", "foreign-run")
  let (_, original, compiled, definition) = journal_test_run(
    "original-plan", "original-run",
  )
  // Equal program bytes do not replace the original checked owner.
  assert_eq(
    @host.prepared_client_identity(prepared).program_definition_cid,
    @host.prepared_client_identity(original).program_definition_cid,
  )
  let mut calls = 0
  let result = capture_native_run_plan_original(
    prepared,
    compiled,
    definition,
    before_construction=Some((_, _, _) => {
      calls += 1
      Ok(())
    }),
  )
  assert_true(result is Err(ForeignRun))
  assert_eq(calls, 0)
}

///|
// The callback observes construction DATA; actual ordinary-parent admission is
// covered separately. This oracle exercises the real large typed issuer and
// keeps its bytes identical without transferring the old codec allowance.
test "fresh funded projection preserves UNION 11 17 24 issuer bytes" {
  let assets = @host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("packaged Environment evidence missing")
  }
  let environment = @host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
  ).unwrap()
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  for branches in [11, 17, 24] {
    let selects : Array[String] = []
    for i in 0..<branches {
      selects.push("SELECT \{i} AS v")
    }
    let context = @frontend.bind_query_context([], cid).unwrap()
    let lowered = @frontend.lower(
      "WITH t AS (" +
      selects.join(" UNION ALL ") +
      ") SELECT SUM(v) AS n FROM t",
      @frontend.Sql,
      Some(context),
    ).unwrap()
    let prepared = @host.prepare_parsed_effect_free_client_program(
      lowered.program.unwrap(),
      environment,
      None,
      @host.client_standard_program_preparation_limits(),
    ).unwrap()
    let limits = @host.client_standard_pure_compilation_limits()
    let tasks = @host.issue_prepared_client_task_compilation(
      prepared,
      manifests,
      @host.prepared_client_values_sequence_limits(prepared),
      limits.max_facts,
      limits.max_witnesses,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ).unwrap()
    let compiled = @host.issue_client_task_compiled_run(
      prepared,
      tasks,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    ).unwrap()
    let (bytes, nodes, depth) = @host.prepared_client_artifact_limits(prepared)
    let expected = @host.client_compiled_run_static_plan_view(
      compiled, prepared, bytes, nodes, depth,
    ).unwrap()
    assert_true(expected.length() > 65536)
    let mut calls = 0
    let actual = native_funded_static_plan_view(prepared, compiled, (_, _, _) => {
      calls += 1
      Ok(())
    }).unwrap()
    assert_eq(actual, expected)
    assert_true(calls >= 3)
  }
}
