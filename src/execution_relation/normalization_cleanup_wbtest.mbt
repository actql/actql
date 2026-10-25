///|
fn normalization_cleanup_expression(expression : String) -> @lower.Expression {
  let unsigned =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":4096,"max_input_utf8_bytes":16384,"max_output_bytes":1048576,"max_pattern_bytes":1,"max_replacements":1,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let cid = "sha256:" + @sha.hex(@utf8.encode(unsigned))
  let wire = unsigned.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  let environment = @client_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"sealed-string","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"text":{"type":"string","nullable":false}},"rows":[{"text":"12.5"}]},"as":"input"},{"derive":{"n":{"try_number":{"value":{"field":"text"}}}},"as":"parsed"}],"results":{"r":{"from":"parsed","fields":["n"]}}}],"results":{"r":{"from":{"stage":"main","result":"r"}}}}
  let document = document.replace(
    old="{\"try_number\":{\"value\":{\"field\":\"text\"}}}",
    new="\"" + expression + "\"",
  )
  let prepared = @client_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @client_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let owner = @strategy.graph_task_owner(
    @client_host.prepared_client_graph(prepared),
    0,
  ).unwrap()
  let sequence = prepared_sequence(owner)
  guard @lower.sequence_step(sequence, 1) is Some(@lower.RowStep(kernel)) else {
    abort("normalization row kernel")
  }
  @lower.binding_at(@lower.kernel_bindings(kernel).unwrap(), 0).unwrap().1
}

///|
test "normalization cancellation releases sorting measurement and construction roots" {
  for operation in ["nfkc", "case_fold"] {
    let expression = normalization_cleanup_expression(operation + "(text)")
    for scenario in 0..<6 {
      let phase = scenario % 3
      let logical = text_expression_budget(1000000L, 1000000L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(20000)
      let frame = expression_frame(
        expression,
        Map([("text", Text("A" + "\u{0315}\u{0300}".repeat(80)))]),
        [],
        { remaining: 1000000, max_frames: 10, },
        workspace,
        Some(expression_roots(logical, 10)),
      ).unwrap()
      let mut reached = false
      for _ in 0..<100000 {
        let before = frame.budget.remaining
        assert_true(advance_expression_frame(frame) is Ok(None))
        assert_true(before - frame.budget.remaining <= 64)
        if frame.state is TextFunction(state) &&
          (if phase == 0 {
            state.normalization_phase == 1 &&
            state.normalization.unwrap().ordering > 2
          } else if phase == 1 {
            state.normalization_phase == 2 &&
            !state.building &&
            state.units > 32
          } else {
            state.building && state.position > 32
          }) {
          reached = true
          break
        }
      }
      assert_true(reached)
      assert_true(workspace.live > 0)
      let work = logical.work
      if scenario >= 3 {
        frame.budget.remaining = 0
        assert_true(
          advance_expression_frame(frame) is Err({ kind: ControlLimit, .. }),
        )
      } else {
        close_expression_frame(frame)
      }
      close_expression_frame(frame)
      assert_eq(
        (logical.work, logical.live, workspace.live),
        (work, borrowed.bytes, 0),
      )
      assert_false(borrowed.released)
      assert_true(
        advance_expression_frame(frame)
        is Err({ kind: InvalidControlLimits, .. }),
      )
      release_logical_root(logical, borrowed).unwrap()
      assert_eq(logical.live, 0L)
    }
  }
}

///|
test "normalization workspace refusal releases admitted input roots" {
  for operation in ["nfkc", "case_fold"] {
    let expression = normalization_cleanup_expression(operation + "(text)")
    let logical = text_expression_budget(1000000L, 1000000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    // Enough for child admission, but not the normalization 18-slot expansion.
    let workspace = row_workspace(100)
    let frame = expression_frame(
      expression,
      Map([("text", Text("A" + "\u{0315}\u{0300}".repeat(80)))]),
      [],
      { remaining: 1000000, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for _ in 0..<10000 {
      result = advance_expression_frame(frame)
      if !(result is Ok(None)) {
        break
      }
    }
    assert_true(result is Err({ kind: WorkspaceLimit, .. }))
    close_expression_frame(frame)
    assert_eq((logical.live, workspace.live), (borrowed.bytes, 0))
    assert_false(borrowed.released)
    release_logical_root(logical, borrowed).unwrap()
    assert_eq(logical.live, 0L)
  }
}
