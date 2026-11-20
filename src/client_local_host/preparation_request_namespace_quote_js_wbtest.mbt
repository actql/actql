///|
test "namespace fixed Scope and ScriptSources fields have an independent incremental quote" {
  assert_eq(request_query_namespace_scope_fields_bytes(0L), Some(0L))
  // Twenty original constructor sites, one eight-byte reference each.
  assert_eq(request_query_namespace_scope_fields_bytes(1L), Some(160L))
  assert_eq(request_query_namespace_scope_fields_bytes(2L), Some(320L))
  assert_true(request_query_namespace_scope_fields_bytes(-1L) is None)
  assert_true(
    request_query_namespace_scope_fields_bytes(9223372036854775807L) is None,
  )
}

///|
test "namespace fixed fields are reserved on the original Request before lowerer entry" {
  let (environment, publication) = request_query_publication_fixture()
  for retained in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let document = "SELECT 1 AS n"
    let parsed = parse_request_query_syntax(
      parent,
      input,
      document,
      @frontend.Sql,
    ).unwrap()
    assert_eq(@query_syntax.token_count(@query_syntax.query_source(parsed)), 5)
    let catalog = @source_publication.prepared_published_query_catalog(
      publication, environment,
    ).unwrap()
    let usage = @checked.source_catalog_usage(catalog)
    let baseline = request_snapshot_data_bytes(
      document.length().to_int64() +
      usage.bytes.to_int64() +
      usage.nodes.to_int64() +
      1L,
      document.length().to_int64() +
      usage.bytes.to_int64() +
      usage.nodes.to_int64() +
      1L,
    ).unwrap()
    let expected = baseline + 800L
    assert_eq(
      request_query_lowering_data_bytes(
        parent.query_syntax.unwrap(),
        None,
        catalog,
        (0, 0L),
      ),
      Some(expected),
    )
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retained {
        limits.retained_bytes - before.0 - expected + 1L
      } else {
        0L
      },
      if retained {
        0L
      } else {
        limits.execution_bytes - before.1 - expected + 1L
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
    assert_eq(parent._observed_query_lower_calls, 0L)
    assert_eq(parent._observed_query_parse_calls, 1L)
    let selected = parent.query_syntax.unwrap().lowering.unwrap()
    assert_eq(selected.quote, (before.0 + expected, before.1 + expected))
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    let result = lower_request_published_query(
      parent,
      input,
      publication,
      environment,
      None,
    ).unwrap()
    assert_true(result.0.program is Some(_))
    assert_eq(parent._observed_query_lower_calls, 1L)
    assert_eq(parent._observed_query_parse_calls, 1L)
    assert_true(
      physical_equal(parent.query_syntax.unwrap().lowering.unwrap(), selected),
    )
    assert_true(
      physical_equal(
        parent.query_syntax.unwrap().query.unwrap().unwrap(),
        parsed,
      ),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
