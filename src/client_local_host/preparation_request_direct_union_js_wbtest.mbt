///|
fn direct_union_terminal_detail(issue : ClientRequestTerminalIssue) -> String {
  match issue {
    Preparation(ProgramCheck(original)) =>
      match original {
        Capacity(_) => "ProgramCheck.Capacity"
        Check(_) => "ProgramCheck.Check"
        Catalog(_) => "ProgramCheck.Catalog"
        SourceRegistration(_) => "ProgramCheck.SourceRegistration"
        TopologyEntry(_) => "ProgramCheck.TopologyEntry"
        Prelude(_) => "ProgramCheck.Prelude"
        Compilation(_) => "ProgramCheck.Compilation"
        EffectInput(_) => "ProgramCheck.EffectInput"
        EffectCompilation(_) => "ProgramCheck.EffectCompilation"
        SourceInput(_) => "ProgramCheck.SourceInput"
        Work(_) => "ProgramCheck.Work"
        ChangedInputs => "ProgramCheck.ChangedInputs"
        WrongPhase => "ProgramCheck.WrongPhase"
        Overflow => "ProgramCheck.Overflow"
        RequestPolicySubjects(_) => "ProgramCheck.RequestPolicySubjects"
      }
    Preparation(original) => @debug.to_string(original)
    CheckOutcome(@checked.Rejected(diagnostic)) =>
      match @checked.diagnostic_cause(diagnostic) {
        Units(BudgetExceeded) => "Units.BudgetExceeded"
        Units(Encoding(original)) =>
          "Units.Encoding:" + @debug.to_string(original)
        Units(UnconvertedProofInput) => "Units.UnconvertedProofInput"
        Units(AmbiguousProofInput) => "Units.AmbiguousProofInput"
        Units(PublicationHost(original)) =>
          "Units.PublicationHost:" + @debug.to_string(original)
        _ => {
          let original : Error = @checked.diagnostic_cause(diagnostic)
          @debug.render(Repr(original), max_depth=20)
        }
      }
    QueryLowering(Publication(Frontend(QueryLowering(Admission(original))))) =>
      @debug.to_string(original)
    _ => {
      let original : Error = issue
      @debug.render(Repr(original), max_depth=20)
    }
  }
}

///|
test "default Request Query selects actual generated Stage inventory without raising authored or explicit policy" {
  let (environment, publication) = request_query_publication_fixture()
  for count in [10, 11, 24, 25, 40] {
    for cte in [false, true] {
      let parts : Array[String] = []
      for i in 0..<count {
        parts.push("SELECT " + (i % 3).to_string() + " AS n")
      }
      let union = parts.join(" UNION ALL ")
      let query = if cte {
        "WITH all_rows AS (" + union + ") SELECT n FROM all_rows"
      } else {
        union
      }
      let (parent, input) = native_driver_parent(query)
      match
        prepare_request_default_source_computation_check(
          parent,
          input,
          request_document_test_source(query, "sql"),
          native_json_reader,
          environment,
          publication,
          [],
          None,
          @publication_host.client_standard_effect_computation_limits(),
        ) {
        Err(issue) => {
          let detail = direct_union_terminal_detail(issue)
          abort_request_preparation_after_cleanup(parent).unwrap()
          fail(
            count.to_string() +
            (if cte { "-cte:" } else { "-direct:" }) +
            detail,
          )
        }
        Ok(_) => ()
      }
      let program = parent.held_program.unwrap()
      let stages = @syntax.stage_count(program)
      assert_eq(stages, if cte { 1 } else { 3 * count })
      let selected = parent.computation_limits.unwrap().checking.compilation
      assert_eq(selected.structure.stages, stages)
      assert_eq(
        selected.work,
        if cte {
          10000000
        } else {
          (3 * count + 31) / 32 * 10000000
        },
      )
      assert_eq(parent._observed_query_parse_calls, 1L)
      assert_eq(parent._observed_query_lower_calls, 1L)
      assert_eq(
        parent.program_check.unwrap()._observed_semantic_check_calls,
        1L,
      )
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
  assert_eq(
    @publication_host.client_standard_program_preparation_limits().checking.input.max_stages,
    32,
  )
  assert_eq(
    @publication_host.client_standard_program_preparation_limits().checking.compilation.structure.stages,
    32,
  )
}

///|
test "explicit tiny Query Stage budget retains its original typed refusal and Request cleanup" {
  let query = "SELECT 1 AS n UNION ALL SELECT 1 AS n"
  let (parent, input) = native_driver_parent(query)
  let (environment, publication) = request_query_publication_fixture()
  let standard = @publication_host.client_standard_program_preparation_limits()
  let selected = {
    ..standard,
    checking: {
      ..standard.checking,
      input: { ..standard.checking.input, max_stages: 1, },
    },
  }
  let outcome = prepare_request_native_source_computation_check(
    parent,
    input,
    request_document_test_source(query, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    selected,
    @publication_host.client_standard_effect_computation_limits(),
  )
  assert_true(
    outcome
    is Err(
      QueryLowering(
        Publication(
          Frontend(QueryLowering(Admission(Structure(StageLimit, ..))))
        )
      )
    ),
  )
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "same Request CTE task sequence selects its original full step count beyond the old default" {
  let (environment, publication) = request_query_publication_fixture(
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
  )
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for (count, aggregate) in [(25, true), (40, false)] {
    let parts : Array[String] = []
    for i in 0..<count {
      parts.push("SELECT " + (i % 3).to_string() + " AS n")
    }
    let query = "WITH all_rows AS (" +
      parts.join(" UNION ALL ") +
      (if aggregate {
        ") SELECT SUM(n) AS total FROM all_rows"
      } else {
        ") SELECT n FROM all_rows"
      })
    let (parent, input) = native_driver_parent(query)
    prepare_request_default_source_computation_check(
      parent,
      input,
      request_document_test_source(query, "sql"),
      native_json_reader,
      environment,
      publication,
      [],
      None,
      @publication_host.client_standard_effect_computation_limits(),
    ).unwrap()
    assert_eq(
      finish_request_checked_computation(
        parent, input, environment, publication,
      ).unwrap(),
      Pure,
    )
    let prepared = parent.compiled_program.unwrap()
    let graph = @publication_host.prepared_client_graph(prepared)
    let original = @strategy.graph_task_owner(graph, 0).unwrap()
    let steps = @lower.node_count(@lower.bound_preparation(original))
    assert_true(steps > 100)
    assert_true(
      @lower.prepare_sequence(
        original,
        @publication_host.client_standard_values_sequence_limits(),
      )
      is Err(@lower.SequenceLimit),
    )
    assert_true(
      @publication_host.prepared_client_values_task_sequence_limits(
        prepared, -1,
      )
      is None,
    )
    let selected = @publication_host.prepared_client_values_task_sequence_limits(
      prepared, 0,
    ).unwrap()
    assert_eq(selected.max_steps, steps)
    let sequences = prepare_client_local_sequences_owned(
      Pure(prepared),
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      compilation_limits=Some(
        request_program_compilation_limits(parent, input).unwrap(),
      ),
    ).unwrap()
    assert_eq(sequences.length(), @strategy.graph_task_count(graph))
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "default Query repeated entry keeps the selected original limits and does not check twice" {
  let query = "SELECT 1 AS n UNION ALL SELECT 1 AS n"
  let (parent, input) = native_driver_parent(query)
  let (environment, publication) = request_query_publication_fixture()
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(query, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let selected = parent.computation_limits.unwrap()
  let checks = parent.program_check.unwrap()._observed_semantic_check_calls
  assert_true(
    prepare_request_default_source_computation_check(
      parent,
      input,
      request_document_test_source(query, "sql"),
      native_json_reader,
      environment,
      publication,
      [],
      None,
      @publication_host.client_standard_effect_computation_limits(),
    )
    is Err(Preparation(WrongPhase)),
  )
  assert_true(physical_equal(parent.computation_limits.unwrap(), selected))
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  assert_eq(
    parent.program_check.unwrap()._observed_semantic_check_calls,
    checks,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "explicit tiny checking work keeps its original typed refusal on the same Request" {
  let query = "SELECT 1 AS n"
  let (parent, input) = native_driver_parent(query)
  let (environment, publication) = request_query_publication_fixture()
  let standard = @publication_host.client_standard_program_preparation_limits()
  let selected = {
    ..standard,
    checking: {
      ..standard.checking,
      compilation: { ..standard.checking.compilation, work: 0, },
    },
  }
  let outcome = prepare_request_native_source_computation_check(
    parent,
    input,
    request_document_test_source(query, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    selected,
    @publication_host.client_standard_effect_computation_limits(),
  )
  assert_true(
    outcome
    is Err(
      Preparation(
        ProgramCheck(Check(@checked.CapacityInputs(@context.BudgetExceeded)))
      )
    ),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "default Query callback reentry cannot replace its selected original or repeat checking" {
  let query = "SELECT 1 AS n UNION ALL SELECT 1 AS n"
  let (environment, publication) = request_query_publication_fixture()
  let input = [1]
  let original : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let armed = Ref(false)
  let inside = Ref(false)
  let refused = Ref(0)
  let preserved = Ref(true)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if armed.val && !inside.val {
        inside.val = true
        let parent = original.val.unwrap()
        let selected = parent.computation_limits
        if prepare_request_default_source_computation_check(
            parent,
            input,
            request_document_test_source(query, "sql"),
            native_json_reader,
            environment,
            publication,
            [],
            None,
            @publication_host.client_standard_effect_computation_limits(),
          )
          is Err(Preparation(WrongPhase)) {
          refused.val += 1
        }
        let same = match selected {
          Some(limits) =>
            parent.computation_limits is Some(actual) &&
            physical_equal(actual, limits)
          None => parent.computation_limits is None
        }
        preserved.val = preserved.val && same
        inside.val = false
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  original.val = Some(parent)
  reserve_request_snapshot(parent, input, 256L, 256L).unwrap()
  armed.val = true
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(query, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  armed.val = false
  assert_true(refused.val > 0)
  assert_true(preserved.val)
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  assert_eq(parent.program_check.unwrap()._observed_semantic_check_calls, 1L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
