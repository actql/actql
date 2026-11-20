///|
test "original integer context has an independent incremental representation bound" {
  // Existing tariff: H = 16 bytes; R/W = 8 bytes and a UTF16 code unit = 2 bytes.
  assert_eq(request_integer_context_data_bytes(1L), Some(1472L))
  assert_eq(request_integer_context_data_bytes(5L), Some(7360L))
  assert_eq(request_integer_context_data_bytes(0L), Some(0L))
  assert_eq(request_integer_context_data_bytes(-1L), None)
  assert_eq(request_integer_context_data_bytes(9223372036854775807L), None)
}

///|
test "original integer context is funded before lowerer entry and short grow retains the same request" {
  let (environment, publication) = request_query_publication_fixture()
  let source = "WITH t AS (SELECT 9007199254740993 AS v) SELECT MOD(v,2) AS x FROM t"
  for retention in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let parsed = parse_request_query_syntax(
      parent,
      input,
      source,
      @frontend.Sql,
    ).unwrap()
    let selected = parent.query_syntax.unwrap()
    let catalog = @source_publication.prepared_published_query_catalog(
      publication, environment,
    ).unwrap()
    let copy = @source_publication.prepared_published_request_copy_geometry(
      publication, environment,
    ).unwrap()
    let bytes = request_query_lowering_data_bytes(selected, None, catalog, copy).unwrap()
    let tokens = @query_syntax.token_count(@query_syntax.query_source(parsed)).to_int64()
    assert_true(bytes >= tokens * 1472L)
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
      lower_request_published_query(
        parent,
        input,
        publication,
        environment,
        None,
      )
      is Err(Request(Capacity(_))),
    )
    let original = selected.lowering.unwrap()
    assert_true(parent.phase == QueryLoweringQuoted && original.output is None)
    assert_true(physical_equal(selected.query.unwrap().unwrap(), parsed))
    assert_eq(original.quote, (base.0 + bytes, base.1 + bytes))
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    let output = lower_request_published_query(
      parent,
      input,
      publication,
      environment,
      None,
    ).unwrap()
    assert_true(physical_equal(selected.lowering.unwrap(), original))
    assert_true(
      physical_equal(parent.held_program.unwrap(), output.0.program.unwrap()),
    )
    assert_true(
      lower_request_published_query(
        parent,
        input,
        publication,
        environment,
        None,
      )
      is Err(Request(WrongPhase)),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
