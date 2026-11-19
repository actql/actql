///|
// Actual phased Request parser/checker/compiler and its SAME Prepared owner.
// This component supplies a nominal Ledger, not physical Native backing,
// Account/Run admission, old state or a cleanup ACK.

///|
test "original Source normalization reserves its audit before construction at exact and one-short lanes" {
  for retention in [true, false] {
    let environment = @publication_host.admit_client_check_environment(
      source_query_original_environment,
      "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ).unwrap()
    let (parent, child, _, input) = registration_parent_fixture(
      text=source_query_original_document,
      environment=Some(environment),
      computation_limits=Some(
        (
          @publication_host.client_standard_program_preparation_limits(),
          @publication_host.client_standard_effect_computation_limits(),
        ),
      ),
    )
    assert_true(
      finish_program_check_preparation(child).unwrap() is @checked.Checked(_),
    )
    let prepared = compile_program_check_preparation(
      child,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    assert_true(
      physical_equal(
        continue_request_program_preparation(parent, input).unwrap(),
        prepared,
      ),
    )
    let sources = @publication_host.prepared_client_normalization_source_count(
      prepared,
    )
    assert_true(parent.phase == ProgramCompiled)
    assert_true(parent.computation_limits is Some(_))
    // The existing single Source has five execution bindings. This cached
    // occurrence bound is not a claim of five distinct completion entries.
    assert_eq(sources, 5L)
    let additional = request_original_normalization_audit_extent_cost(prepared).unwrap()
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let remaining = if retention {
      limits.retained_bytes - usage.held_bytes - usage.reserved_retention_bytes
    } else {
      limits.execution_bytes - usage.reserved_execution_bytes
    }
    assert_true(remaining > additional)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        remaining - additional + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        remaining - additional + 1L
      },
    ).unwrap()
    let refused = prepare_request_program_normalization(parent, input)
    let expected_refusal = if retention {
      refused is Err(Preparation(Capacity(Resource(RetentionLimit))))
    } else {
      refused is Err(Preparation(Capacity(Resource(ExecutionLimit))))
    }
    if !expected_refusal {
      match refused {
        Err(issue) => {
          let original : Error = issue
          fail(@debug.to_string(original))
        }
        Ok(_) => fail("one-short original audit entered its constructor")
      }
    }
    let selected = parent.program_normalization.unwrap()
    assert_true(selected.audit is None)
    assert_eq(selected.charged_work, 0L)
    assert_true(physical_equal(selected.original, prepared))
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        remaining - additional
      } else {
        0L
      },
      if retention {
        0L
      } else {
        remaining - additional
      },
    ).unwrap()
    let original = prepare_request_program_normalization(parent, input).unwrap()
    assert_true(selected.audit is Some(_))
    assert_true(physical_equal(parent.program_normalization.unwrap(), selected))
    assert_true(
      physical_equal(
        prepare_request_program_normalization(parent, input).unwrap(),
        original,
      ),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "ordinary direct forty UNION branches retain original normalization through same Request" {
  let statements : Array[String] = []
  for index in 0..<40 {
    statements.push("SELECT \{index} AS n")
  }
  let sql = statements.join(" UNION ALL ")
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(sql)
  let captured = request_native_test_value(
    "{\"format\":\"sql\",\"text\":\"" + sql + "\"}",
  )
  let prepared = prepare_request_default_source_computation_check(
    parent,
    input,
    captured,
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
    // Exact installed Native submitted Source result convention.
    public_primary=false,
  )
  match prepared {
    Err(CheckOutcome(@checked.Rejected(diagnostic))) =>
      match @checked.diagnostic_cause(diagnostic) {
        Units(ProofConversion(cause)) => raise cause
        Units(cause) => raise cause
        cause => raise cause
      }
    Err(issue) => {
      let original : Error = issue
      fail(@debug.to_string(original))
    }
    Ok(_) => ()
  }
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Pure,
  )
  let original = parent.compiled_program.unwrap()
  assert_true(
    @publication_host.issue_prepared_client_local_normalization(original)
    is Err(CommonInventory(BudgetExceeded)),
  )
  let result = prepare_request_program_normalization(parent, input)
  let cause = match result {
    Ok(_) => "issued"
    Err(Normalization(CommonInventory(BudgetExceeded))) =>
      "common-inventory-budget"
    Err(issue) => {
      let original : Error = issue
      fail(@debug.to_string(original))
    }
  }
  let (charged, spent, complete) = request_program_normalization_work(
    parent, input,
  ).unwrap()
  assert_true(complete)
  assert_true(charged > 16809L)
  assert_eq(charged, spent)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(cause, "issued")
}

///|
fn normalization_request_control_fixture(
  current? : () -> Bool = () => true,
) -> (ClientRequestPreparation[Array[Int]], Array[Int]) raise {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input, current~),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let sql = "SELECT 7 AS n"
  reserve_request_snapshot(
    parent,
    input,
    sql.length().to_int64() + 32L,
    sql.length().to_int64() + 32L,
  ).unwrap()
  let (environment, publication) = request_query_publication_fixture()
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_native_test_value("{\"format\":\"sql\",\"text\":\"SELECT 7 AS n\"}"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
    public_primary=false,
  ).unwrap()
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Pure,
  )
  (parent, input)
}

///|
test "normalization Request fences foreign and current reentry and retains the same original once" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, input) = normalization_request_control_fixture(current=() => {
    if action.val is Some(run) {
      run()
    }
    true
  })
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    prepare_request_program_normalization(parent, [1])
    is Err(Preparation(ForeignOriginal)),
  )
  assert_true(parent.program_normalization is None)
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  let refused = Ref(false)
  action.val = Some(() => {
    action.val = None
    let nested = prepare_request_program_normalization(parent, input)
      is Err(Preparation(WrongPhase))
    let cleanup = abort_request_preparation_after_cleanup(parent)
      is Err(WrongPhase)
    refused.val = nested && cleanup
  })
  let original = prepare_request_program_normalization(parent, input).unwrap()
  assert_true(refused.val)
  let work = request_program_normalization_work(parent, input).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  let reused = prepare_request_program_normalization(parent, input).unwrap()
  assert_true(physical_equal(original, reused))
  assert_eq(request_program_normalization_work(parent, input), Some(work))
  assert_eq(@resources.ledger_usage(parent.ledger), usage)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.program_normalization is None)
  assert_true(
    prepare_request_program_normalization(parent, input)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "normalization Request current refusal keeps its unentered audit and original cleanup" {
  let current = Ref(true)
  let (parent, input) = normalization_request_control_fixture(current=() => {
    current.val
  })
  let before = @resources.ledger_usage(parent.ledger)
  current.val = false
  assert_true(
    prepare_request_program_normalization(parent, input)
    is Err(Preparation(Capacity(_))),
  )
  let original = parent.program_normalization.unwrap()
  assert_true(
    original.audit is None && original.work is None && original.result is None,
  )
  assert_eq(original.charged_work, 0L)
  assert_eq(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.program_normalization is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "normalization Request cached success checks original current without repeating its audit" {
  let current = Ref(true)
  let calls = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, input) = normalization_request_control_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    current.val
  })
  let original = prepare_request_program_normalization(parent, input).unwrap()
  let audit = parent.program_normalization.unwrap().audit.unwrap()
  let work = request_program_normalization_work(parent, input)
  let refused = Ref(false)
  action.val = Some(() => {
    action.val = None
    refused.val = prepare_request_program_normalization(parent, input)
      is Err(Preparation(WrongPhase)) &&
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase)
  })
  let before = calls.val
  let cached = prepare_request_program_normalization(parent, input).unwrap()
  assert_true(physical_equal(original, cached))
  assert_true(refused.val)
  assert_eq(calls.val, before + 1)
  assert_eq(request_program_normalization_work(parent, input), work)
  current.val = false
  assert_true(
    prepare_request_program_normalization(parent, input)
    is Err(Preparation(Capacity(_))),
  )
  assert_true(
    physical_equal(audit, parent.program_normalization.unwrap().audit.unwrap()),
  )
  assert_eq(request_program_normalization_work(parent, input), work)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.program_normalization is None)
  assert_true(
    prepare_request_program_normalization(parent, input)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "normalization Request first cached original checks current before its first entrance" {
  let current = Ref(true)
  let calls = Ref(0)
  let (parent, input) = normalization_request_control_fixture(current=() => {
    calls.val += 1
    current.val
  })
  let original = @publication_host.issue_prepared_client_local_normalization(
    parent.compiled_program.unwrap(),
  ).unwrap()
  assert_true(parent.program_normalization is None)
  let usage = @resources.ledger_usage(parent.ledger)
  current.val = false
  let before = calls.val
  assert_true(
    prepare_request_program_normalization(parent, input)
    is Err(Preparation(Capacity(_))),
  )
  assert_eq(calls.val, before + 1)
  assert_true(parent.program_normalization is None)
  assert_true(request_program_normalization_work(parent, input) is None)
  assert_true(
    physical_equal(
      original,
      @publication_host.prepared_client_local_normalization_original(
        parent.compiled_program.unwrap(),
      ).unwrap(),
    ),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), usage)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(
    prepare_request_program_normalization(parent, input)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "normalization preserves Native preborrow construction and rejects late borrow order" {
  let (parent, input) = normalization_request_control_fixture()
  let borrow = borrow_request_program_plan_input(parent, input).unwrap()
  let observed = match prepare_request_program_normalization(parent, input) {
    Ok(_) => "issued"
    Err(Preparation(WrongPhase)) => "request-wrong-phase-after-plan-borrow"
    Err(issue) => {
      let original : Error = issue
      @debug.to_string(original)
    }
  }
  @resources.return_preparation_body_borrow(borrow).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(observed, "request-wrong-phase-after-plan-borrow")
  let (parent, input) = normalization_request_control_fixture()
  let original = prepare_request_program_normalization(parent, input).unwrap()
  let work = request_program_normalization_work(parent, input).unwrap()
  let borrow = borrow_request_program_plan_input(parent, input).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(borrow).unwrap(),
      parent.compiled_program.unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      original,
      @publication_host.prepared_client_local_normalization_original(
        parent.compiled_program.unwrap(),
      ).unwrap(),
    ),
  )
  assert_eq(request_program_normalization_work(parent, input), Some(work))
  @resources.return_preparation_body_borrow(borrow).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "normalization audit excludes unrelated admitted catalogue data from its same Program quote" {
  let original_quotes : Array[Int64] = []
  let checker_quotes : Array[Int64] = []
  let journals : Array[String] = []
  for catalogue in [0, 100] {
    // Both are genuine admitted environments. The second has unused immutable
    // contracts; the authored Program, Parameter and executed pipelines match.
    let (parent, input, prepared) = request_model_input_fixture(
      authored=Some(
        (
          #|{"version":"actql/0.1","id":"literal-audit","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
        ),
      ),
      catalog_registry_count=catalogue,
      normalization_profile=Some(
        @publication_host.client_standard_program_preparation_limits(),
      ),
    )
    let sources = @publication_host.prepared_client_normalization_source_count(
      prepared,
    )
    assert_eq(sources, 0L)
    original_quotes.push(
      request_original_normalization_audit_extent_cost(prepared).unwrap(),
    )
    checker_quotes.push(
      request_normalization_audit_extent_cost(
        parent.program_data.unwrap(),
        sources,
      ).unwrap(),
    )
    let original = match prepare_request_program_normalization(parent, input) {
      Ok(value) => value
      Err(issue) =>
        fail(
          "actual original catalogue " +
          catalogue.to_string() +
          ": " +
          (match issue {
            Preparation(Capacity(Resource(RetentionLimit))) => "RetentionLimit"
            Preparation(Capacity(Resource(ExecutionLimit))) => "ExecutionLimit"
            Preparation(Capacity(InvalidExtent)) => "InvalidExtent"
            Preparation(Capacity(_)) => "OtherCapacity"
            Preparation(Work(_)) => "Work"
            Preparation(_) => "OtherPreparation"
            Normalization(CommonInventory(CompletionObserved)) =>
              "CompletionObserved"
            Normalization(CommonInventory(BudgetExceeded)) => "AuditBudget"
            Normalization(CommonInventory(_)) => "OtherAudit"
            Normalization(Evidence(_)) => "Evidence"
            Normalization(_) => "OtherNormalization"
          }),
        )
    }
    journals.push(
      @publication.run_evidence_value_json(
        @publication_host.prepared_client_local_normalization_evidence(
          prepared, original,
        ).unwrap(),
      ),
    )
    assert_true(
      physical_equal(
        original,
        @publication_host.prepared_client_local_normalization_original(prepared).unwrap(),
      ),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
  assert_true(checker_quotes[1] > checker_quotes[0])
  assert_eq(original_quotes[1], original_quotes[0])
  assert_eq(journals[1], journals[0])
}

///|
test "Values normalization control bound excludes rows and keeps non-Values conservative" {
  for rows in [1, 51] {
    for filtering in [false, true] {
      let row_wire = "{\"id\":1},".repeat(rows)
      let body = row_wire[:row_wire.length() - 1].to_owned()
      let filtered = if filtering {
        ",{\"from\":\"seed\",\"where\":\"id >= 0\",\"as\":\"filtered\"}"
      } else {
        ""
      }
      let result = if filtering { "filtered" } else { "seed" }
      let authored = "{\"version\":\"actql/0.1\",\"id\":\"audit-control\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
        body +
        "]},\"as\":\"seed\"}" +
        filtered +
        "],\"results\":{\"rows\":{\"from\":\"" +
        result +
        "\",\"fields\":[\"id\"]}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
      let (parent, input, prepared) = request_model_input_fixture(
        authored=Some(authored),
        normalization_profile=Some(
          @publication_host.client_standard_program_preparation_limits(),
        ),
      )
      let (demand, _, nodes) = @publication_host.prepared_client_normalization_audit_data(
        prepared,
      )
      assert_eq(demand.authored_literal_rows, rows)
      assert_eq(demand.authored_literal_cells, rows)
      if filtering {
        assert_true(nodes > 4)
      } else {
        // One Values step + one Stage Result + one public export + inventory.
        assert_eq(nodes, 4)
      }
      let original = prepare_request_program_normalization(parent, input).unwrap()
      assert_true(
        physical_equal(
          original,
          @publication_host.prepared_client_local_normalization_original(
            prepared,
          ).unwrap(),
        ),
      )
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}
