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
