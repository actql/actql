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
    // Five tokens: fixed fields800 plus new capture/resolver controls1920.
    let expected = baseline + 2720L
    assert_eq(
      request_query_lowering_data_bytes(
        parent.query_syntax.unwrap(),
        None,
        catalog,
        (0, 0L),
        publication,
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

///|
test "namespace container inventory has independent complete representation units" {
  let selected = request_query_namespace_construction(
    2L,
    (1, 1, 1, 0, 0),
    (0L, 0L),
    (0, 0),
    0L,
    false,
    false,
  ).unwrap()
  // Records48; growing arrays20/92items =>60H536R40W;
  // maps2/2entries =>22H58R68W; actual quotation controls21H2R42W.
  // Owned original/fold text128UTF16. No engine layout or product emitter oracle.
  assert_true(
    selected.0 ==
    {
      record_headers: 151L,
      reference_slots: 740L,
      scalar_words: 214L,
      owned_utf16_units: 128L,
      owned_wire_bytes: 0L,
    },
  )
  assert_eq(
    @execution.preparation_representation_cost(selected.0),
    Some(10304L),
  )
  assert_eq(selected.1, 20)
  assert_eq(selected.2, 64L)
  let unused = request_query_namespace_construction(
    2L,
    (1, 1, 1, 0, 0),
    (0L, 0L),
    (999999, 999999),
    0L,
    false,
    false,
  ).unwrap()
  assert_true(unused.0 == selected.0)
  assert_eq(unused.1, selected.1)
  assert_eq(unused.2, selected.2)
  assert_eq(request_query_namespace_controls_bytes(1L), Some(384L))
  assert_true(
    request_query_namespace_construction(
      0L,
      (1, 1, 1, 0, 0),
      (0L, 0L),
      (0, 0),
      0L,
      false,
      false,
    )
    is None,
  )
  assert_true(
    request_query_namespace_construction(
      2L,
      (1, 1, 0, 0, 0),
      (0L, 0L),
      (0, 0),
      0L,
      false,
      false,
    )
    is None,
  )
  assert_true(
    request_query_namespace_construction(
      2L,
      (1, 1, 1, 0, 0),
      (-1L, 0L),
      (0, 0),
      0L,
      false,
      false,
    )
    is None,
  )
  assert_true(
    request_query_namespace_construction(
      2147483647L,
      (2147483647, 2147483647, 2147483647, 2147483647, 2147483647),
      (65536L, 0L),
      (0, 65536),
      0L,
      true,
      true,
    )
    is None,
  )
}

///|
test "namespace full container and material quote refuses one-short before actual row lowering" {
  let (environment, publication) = request_query_publication_fixture()
  for retained in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let source = "WITH t AS (SELECT 1, 2 AS n) SELECT t AS row FROM t"
    let parsed = parse_request_query_syntax(
      parent,
      input,
      source,
      @frontend.Sql,
    ).unwrap()
    let catalog = @source_publication.prepared_published_query_catalog(
      publication, environment,
    ).unwrap()
    let copy = @source_publication.prepared_published_request_copy_geometry(
      publication, environment,
    ).unwrap()
    let bytes = request_query_lowering_data_bytes(
      parent.query_syntax.unwrap(),
      None,
      catalog,
      copy,
      publication,
    ).unwrap()
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    // This uses the ordinary finite preparation policy, not a raised fixture cap.
    assert_true(bytes < limits.retained_bytes - before.0)
    assert_true(bytes < limits.execution_bytes - before.1)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retained {
        limits.retained_bytes - before.0 - bytes + 1L
      } else {
        0L
      },
      if retained {
        0L
      } else {
        limits.execution_bytes - before.1 - bytes + 1L
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
    let selected = parent.query_syntax.unwrap().lowering.unwrap()
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    let lowered = lower_request_published_query(
      parent,
      input,
      publication,
      environment,
      None,
    ).unwrap()
    assert_true(lowered.0.program is Some(_))
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
