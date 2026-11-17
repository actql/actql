///|
test "same Request query syntax uses one original current and refuses reentry without a second parse" {
  let input = [1]
  let calls = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let flags = Ref(0)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      calls.val += 1
      if action.val is Some(run) {
        run()
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  action.val = Some(() => {
    if parse_request_query_syntax(
        parent,
        input,
        "SELECT 1 AS id",
        @frontend.Sql,
      )
      is Err(Request(WrongPhase)) {
      flags.val += 1
    }
    if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
      flags.val += 2
    }
  })
  let before = calls.val
  let query = parse_request_query_syntax(
    parent,
    input,
    "SELECT 1 AS id",
    @frontend.Sql,
  ).unwrap()
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 3)
  let selected = parent.query_syntax.unwrap()
  assert_true(physical_equal(selected.query.unwrap().unwrap(), query))
  assert_true(
    physical_equal(prepared_request_query_syntax(parent, input).unwrap(), query),
  )
  assert_eq(
    request_query_syntax_work(parent, input).unwrap(),
    (selected.known_work, selected.counters_complete),
  )
  assert_eq(calls.val - before, 1)
  assert_true(
    parent.phase == QuerySyntaxParsed &&
    selected.known_work > 0L &&
    selected.counters_complete,
  )
  assert_true(
    parse_request_query_syntax(parent, input, "SELECT 1 AS id", @frontend.Sql)
    is Err(Request(WrongPhase)),
  )
  assert_true(
    @resources.begin_preparation_phase_work64(
      parent.capacity,
      input,
      @resources.LexicalScan,
      1L,
    )
    is Err(AlreadyClaimed),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.query_syntax is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "same Request query syntax preserves short grow quote input and original failure work" {
  for retention in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let source = "SELECT 1 AS id"
    let bytes = request_query_syntax_data_bytes(source).unwrap()
    let base = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - base.0 - bytes + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - base.1 - bytes + 1L
      },
    ).unwrap()
    assert_true(
      parse_request_query_syntax(parent, input, source, @frontend.Sql)
      is Err(Request(Capacity(_))),
    )
    let original = parent.query_syntax.unwrap()
    assert_true(parent.phase == QuerySyntaxQuoted && original.query is None)
    assert_true(
      parse_request_query_syntax(parent, input, "SELECT 2 AS id", @frontend.Sql)
      is Err(Request(ForeignOriginal)),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    parse_request_query_syntax(parent, input, source, @frontend.Sql).unwrap()
    |> ignore
    assert_true(physical_equal(parent.query_syntax.unwrap(), original))
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  assert_true(
    parse_request_query_syntax(parent, input, "SELECT (1 +", @frontend.Sql)
    is Err(Frontend(_)),
  )
  assert_true(
    parent.phase == QuerySyntaxFailed &&
    parent.query_syntax.unwrap().known_work > 0L,
  )
  assert_true(
    @resources.begin_preparation_phase_work64(
      parent.capacity,
      input,
      @resources.LexicalScan,
      1L,
    )
    is Err(AlreadyClaimed),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "selected lexical work retains same quote and refuses replacement before parsing" {
  for retention in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let source = "SELECT 7 AS n"
    let bytes = request_query_syntax_data_bytes(source, lexical_work=Some(64)).unwrap()
    assert_eq(bytes - request_query_syntax_data_bytes(source).unwrap(), 152L)
    let base = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - base.0 - bytes + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - base.1 - bytes + 1L
      },
    ).unwrap()
    let refusal = parse_request_query_syntax(
      parent,
      input,
      source,
      @frontend.Sql,
      lexical_work=Some(64),
    )
    assert_true(
      if retention {
        refusal is Err(Request(Capacity(Resource(RetentionLimit))))
      } else {
        refusal is Err(Request(Capacity(Resource(ExecutionLimit))))
      },
    )
    let original = parent.query_syntax.unwrap()
    assert_eq(original.lexical_work, Some(64))
    assert_true(original.query is None)
    assert_eq(parent._observed_query_parse_calls, 0L)
    assert_true(
      parse_request_query_syntax(
        parent,
        input,
        source,
        @frontend.Sql,
        lexical_work=Some(65),
      )
      is Err(Request(ForeignOriginal)),
    )
    assert_true(physical_equal(parent.query_syntax.unwrap(), original))
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    parse_request_query_syntax(
      parent,
      input,
      source,
      @frontend.Sql,
      lexical_work=Some(64),
    ).unwrap()
    |> ignore
    assert_true(physical_equal(parent.query_syntax.unwrap(), original))
    assert_eq(parent._observed_query_parse_calls, 1L)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "explicit Source lexical work stays on its original selected small budget" {
  let document = "SELECT 7 AS n"
  let (parent, input) = native_driver_parent(document)
  let (environment, publication) = request_query_publication_fixture()
  let original = @publication_host.client_standard_program_preparation_limits()
  let limits = { ..original, lowering: { ..original.lowering, max_work: 1, }, }
  let refusal = prepare_request_native_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    limits,
    @publication_host.client_standard_effect_computation_limits(),
  )
  assert_true(
    refusal
    is Err(
      QuerySyntax(
        Frontend(
          @frontend.QuerySyntax(
            { issue: @query_syntax.Limit(@query_syntax.Work), .. }
          )
        )
      )
    ),
  )
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 0L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
