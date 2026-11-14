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

///|
test "direct forty-branch Request compiles once then prepares every original task sequence" {
  let parts : Array[String] = []
  for i in 0..<40 {
    parts.push("SELECT " + (i % 3).to_string() + " AS n")
  }
  let query = parts.join(" UNION ALL ")
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
  let checked = parent.program_check.unwrap()
  assert_eq(checked._observed_semantic_check_calls, 1L)
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Pure,
  )
  let prepared = parent.compiled_program.unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
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
  assert_true(sequences.length() > 32)
  assert_eq(sequences.length(), @strategy.graph_task_count(graph))
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  assert_eq(checked._observed_semantic_check_calls, 1L)
  assert_true(parent.program_check is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "CTE forty-branch same Request continues through actual module body preparation" {
  let parts : Array[String] = []
  for i in 0..<40 {
    parts.push("SELECT " + (i % 3).to_string() + " AS n")
  }
  let query = "WITH all_rows AS (" +
    parts.join(" UNION ALL ") +
    ") SELECT n FROM all_rows"
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
  let checked = parent.program_check.unwrap()
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Pure,
  )
  let prepared = parent.compiled_program.unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  let original = @strategy.graph_task_owner(graph, 0).unwrap()
  let steps = @lower.node_count(@lower.bound_preparation(original))
  assert_eq(steps, 160)
  let shared = @publication_host.prepared_client_values_sequence_limits(
    prepared,
  )
  let task = @publication_host.prepared_client_values_task_sequence_limits(
    prepared, 0,
  ).unwrap()
  assert_eq(shared.max_steps, steps)
  assert_eq(task.max_steps, steps)
  // A genuinely smaller explicit caller selection is still refused by the
  // SAME original lowerer; neither common getter admits that narrower budget.
  assert_true(
    @lower.prepare_sequence(original, { ..shared, max_steps: 1, })
    is Err(@lower.SequenceLimit),
  )
  let factories = Ref(0)
  let outcome = prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=request_program_compilation_limits(parent, input).unwrap(),
    retained_output=false,
    provider_factory=_ => {
      factories.val += 1
      []
    },
  )
  let typed = match outcome {
    Ok(_) => "ok"
    Err(
      Construction(
        Graph(Fragment(AoA(Pipeline(Sequence(@lower.SequenceLimit)))))
      )
    ) => "Construction.Graph.Fragment.AoA.Pipeline.Sequence.SequenceLimit"
    Err(
      Construction(
        TaskGraph(Fragment(Pipeline(Sequence(@lower.SequenceLimit))))
      )
    ) => "Construction.TaskGraph.Fragment.Pipeline.Sequence.SequenceLimit"
    Err(Construction(Graph(_))) => "Construction.Graph.other"
    Err(Construction(TaskGraph(_))) => "Construction.TaskGraph.other"
    Err(Construction(_)) => "Construction.other"
    Err(Installed(Sequence(@lower.SequenceLimit))) =>
      "Installed.Sequence.SequenceLimit"
    Err(Installed(_)) => "Installed.other"
    Err(Preparation(Capacity(_))) => "Preparation.Capacity"
    Err(Preparation(_)) => "Preparation.other"
    Err(CapacityExceeded(_)) => "CapacityExceeded"
    Err(ValuesCompilation(_)) => "ValuesCompilation"
    Err(TaskCompilation(_)) => "TaskCompilation"
    Err(_) => "other original typed module issue"
  }
  println("CTE40_MODULE_TYPED=" + typed)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(checked._observed_semantic_check_calls, 1L)
  assert_eq(checked._observed_program_compile_calls, 1L)
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  assert_eq(typed, "ok")
  assert_eq(factories.val, 1)
}

///|
test "module full-sequence projection classifies only original typed budget refusals" {
  let failures : Array[ClientRequestProgramPlanIssue] = [
    Installed(Sequence(SequenceLimit)),
    Construction(Graph(Fragment(AoA(Pipeline(Sequence(SequenceLimit)))))),
    Construction(TaskGraph(Fragment(Pipeline(Sequence(SequenceLimit))))),
  ]
  for original in failures {
    assert_true(request_program_plan_issue_is_sequence_limit(original))
  }
  let uncertain : Array[ClientRequestProgramPlanIssue] = [
    Preparation(ForeignOriginal),
    Preparation(WrongPhase),
    Construction(Encoding),
  ]
  for original in uncertain {
    assert_false(request_program_plan_issue_is_sequence_limit(original))
  }
}

///|
test "ordinary encoded and native Program input share observed Stage and step bounds" {
  let (environment, publication) = request_query_publication_fixture()
  for (stages, steps) in [(33, 1), (1, 1025)] {
    let stage_bodies : Array[String] = []
    for stage in 0..<stages {
      let operations : Array[String] = [
        "{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"n\":1}]},\"as\":\"v0\"}",
      ]
      for step in 1..<steps {
        operations.push(
          "{\"from\":\"v" +
          (step - 1).to_string() +
          "\",\"select\":[\"n\"],\"as\":\"v" +
          step.to_string() +
          "\"}",
        )
      }
      stage_bodies.push(
        "{\"id\":\"s" +
        stage.to_string() +
        "\",\"inputs\":{},\"steps\":[" +
        operations.join(",") +
        "],\"results\":{\"rows\":{\"from\":\"v" +
        (steps - 1).to_string() +
        "\",\"fields\":[\"n\"]}}}",
      )
    }
    let document = "{\"version\":\"actql/0.1\",\"id\":\"observed-input\",\"stages\":[" +
      stage_bodies.join(",") +
      "],\"results\":{\"main\":{\"from\":{\"stage\":\"s" +
      (stages - 1).to_string() +
      "\",\"result\":\"rows\"}}}}"
    for native in [false, true] {
      let (parent, input) = native_driver_parent(document)
      let outcome = if native {
        prepare_request_native_computation_check(
          parent,
          input,
          request_native_test_value(document),
          native_json_reader,
          environment,
          publication,
          [],
          request_default_program_preparation_limits(parent, input).unwrap(),
          @publication_host.client_standard_effect_computation_limits(),
        )
      } else {
        prepare_request_default_source_computation_check(
          parent,
          input,
          request_document_test_source(document, "json"),
          native_json_reader,
          environment,
          publication,
          [],
          None,
          @publication_host.client_standard_effect_computation_limits(),
        )
      }
      let detail = match outcome {
        Ok(_) => "ok"
        Err(issue) => direct_union_terminal_detail(issue)
      }
      println(
        "OBSERVED_INPUT stages=" +
        stages.to_string() +
        " steps=" +
        steps.to_string() +
        " native=" +
        native.to_string() +
        " cause=" +
        detail,
      )
      if outcome is Ok(_) {
        assert_eq(@syntax.stage_count(parent.held_program.unwrap()), stages)
        assert_eq(
          parent.program_check.unwrap()._observed_semantic_check_calls,
          1L,
        )
      }
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
      assert_eq(detail, "ok")
    }
  }
}

///|
test "explicit small Program budget remains explicit after common observed selection" {
  let stage = "{\"id\":\"one\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"n\":1}]},\"as\":\"v\"}],\"results\":{\"rows\":{\"from\":\"v\",\"fields\":[\"n\"]}}}"
  let document = "{\"version\":\"actql/0.1\",\"id\":\"explicit-input\",\"stages\":[" +
    stage +
    "," +
    stage.replace(old="one", new="two") +
    "],\"results\":{\"main\":{\"from\":{\"stage\":\"two\",\"result\":\"rows\"}}}}"
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(document)
  let selected = request_default_program_preparation_limits(parent, input).unwrap()
  let explicit = {
    ..selected,
    checking: {
      ..selected.checking,
      input: { ..selected.checking.input, max_stages: 1, },
    },
  }
  let outcome = prepare_request_native_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "json"),
    native_json_reader,
    environment,
    publication,
    [],
    explicit,
    @publication_host.client_standard_effect_computation_limits(),
  )
  match outcome {
    Err(Preparation(ProgramJson(Syntax(issue)))) =>
      assert_true(issue is @syntax.Structure(@syntax.StageLimit, ..))
    _ =>
      fail(
        "explicit original Program Stage bound must refuse before semantic checking",
      )
  }
  assert_true(parent.program_check is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "ordinary Source lexical work follows its same retained document through checking" {
  let document = "SELECT 7 AS n" + " ".repeat(1000000)
  let (parent, input) = native_driver_parent(document)
  let (environment, publication) = request_query_publication_fixture()
  let outcome = prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  )
  let detail = match outcome {
    Ok(_) => "ok"
    Err(QuerySyntax(Frontend(@frontend.QuerySyntax(diagnostic)))) =>
      match diagnostic.issue {
        @query_syntax.Limit(@query_syntax.Work) => "original_lexical_work_limit"
        _ => "other_original_query_syntax"
      }
    Err(issue) => direct_union_terminal_detail(issue)
  }
  let calls = request_preparation_work_calls(parent)
  let observation = match parent.query_syntax {
    Some(query) => (query.known_work, query.counters_complete)
    None => (-1L, false)
  }
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  println(
    "LEXICAL_OBSERVED units=" +
    document.length().to_string() +
    " cause=" +
    detail,
  )
  assert_true(outcome is Ok(_))
  assert_eq(calls, (1L, 1L, 1L, 0L))
  assert_true(observation.1 && observation.0 >= document.length().to_int64())
}

///|
test "raw Native default selection consumes only its original funded wire without snapshot fiction" {
  let input = [71]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  assert_true(
    request_default_program_preparation_limits(parent, input)
    is Err(Preparation(Policy)),
  )
  reserve_request_native_intake_wire(parent, input, 4096).unwrap()
  let limits = request_default_program_preparation_limits(parent, input).unwrap()
  assert_eq(limits.checking.input.source.max_input_bytes, 4096)
  assert_eq(limits.checking.input.tree.max_nodes, 4096)
  assert_eq(limits.checking.compilation.structure.stages, 4096)
  assert_eq(
    limits.checking.input.source.max_depth,
    @publication_host.client_standard_program_preparation_limits().checking.input.source.max_depth,
  )
  assert_eq((parent.snapshot_units, parent.snapshot_values), (0L, 0L))
  assert_true(parent.submitted_intent is None && parent.snapshot_base is None)
  assert_true(
    request_default_program_preparation_limits(parent, [72])
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(request_source_lexical_work("SELECT 7 AS n"), Some(26))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
