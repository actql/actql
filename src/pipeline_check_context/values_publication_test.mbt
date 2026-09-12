///|
fn values_publication_index(rows : String) -> ProgramOperationResolutionIndex {
  let queries = cells_fixture(
    "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"number\",\"default\":1}",
    rows,
  )
  values_publication_queries_index(queries)
}

///|
fn values_publication_queries_index(
  queries : ProgramOperationQueries,
) -> ProgramOperationResolutionIndex {
  let requirements = operation_orders_requirements(
    operation_scalars_orders(
      operation_frames_scalars(
        operation_fills_frames(
          operation_ranges_fills(operation_queries_ranges(queries)),
        ),
      ),
    ),
  )
  index_program_operation_resolutions(
    resolution_profiles(requirements),
    10000000,
    1000,
  ).unwrap()
}

///|
fn values_publication_limits() -> ValuesPublicationLimits {
  {
    max_work: 10000000,
    max_values: 3,
    max_payload_bytes: 10000,
    max_payload_nodes: 10000,
    max_depth: 20,
    metadata: {
      max_bytes: 4000,
      max_nodes: 1000,
      max_depth: 20,
      max_candidates: 2,
    },
  }
}

///|
test "values resources close exact operation requirements as future execution checks" {
  let index = values_publication_index("[{\"x\":{\"$param\":\"n\"}}]")
  let before = operation_resolution_unresolved_count(index)
  let limits = values_publication_limits()
  let resolved = resolve_program_values_resources(index, limits).unwrap()
  assert_true(
    physical_equal(
      operation_resolution_requirements(index),
      operation_resolution_requirements(resolved),
    ),
  )
  assert_eq(operation_resolution_unresolved_count(resolved), before - 3)
  assert_eq(operation_resolution_unresolved_count(index), before)
  let closed = close_program_operations(resolved, 10000000, 1000).unwrap()
  let mut found = 0
  for i in 0..<operation_closure_count(closed) {
    if operation_closure_at(closed, i)
      is Some(ExecutionCheck(ValuesPublication(check))) {
      found += 1
      assert_true(
        physical_equal(
          check.site,
          operation_requirements_at(operation_resolution_requirements(index), i).unwrap(),
        ),
      )
      assert_true(
        physical_equal(check.recursive.rows.wire.bound.site, check.site),
      )
      assert_true(check.recursive_limit is None)
      assert_eq(
        operation_execution_phase(ValuesPublication(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(ValuesPublication(check)),
        RejectOperationOutput,
      )
    }
  }
  assert_eq(found, 3)
  let (payload_bytes, payload_nodes) = operation_resolution_values_usage(
    resolved,
  )
  assert_eq(payload_bytes, 27)
  assert_true(
    resolve_program_values_resources(index, {
      ..limits,
      max_payload_bytes: payload_bytes,
      max_payload_nodes: payload_nodes,
    })
    is Ok(_),
  )
  assert_true(
    resolve_program_values_resources(index, {
      ..limits,
      max_payload_nodes: payload_nodes - 1,
    })
    is Err(_),
  )
  assert_true(
    resolve_program_values_resources(index, {
      ..limits,
      max_work: operation_resolution_work(resolved),
    })
    is Ok(_),
  )
  assert_true(
    resolve_program_values_resources(index, {
      ..limits,
      max_work: operation_resolution_work(resolved) - 1,
    })
    is Err(_),
  )
  for
    short in [
      { ..limits, max_values: 2, },
      { ..limits, max_payload_bytes: 26, },
      { ..limits, max_payload_nodes: 1, },
      { ..limits, max_depth: 1, },
      { ..limits, max_values: -1, },
    ] {
    assert_true(resolve_program_values_resources(index, short) is Err(_))
    assert_eq(operation_resolution_unresolved_count(index), before)
  }
  assert_true(resolve_program_values_resources(index, limits) is Ok(_))
}

///|
test "statically excessive values rows cannot be deferred as successful resource closure" {
  let index = values_publication_index("[{\"x\":1},{\"x\":1}]")
  assert_true(
    resolve_program_values_resources(index, values_publication_limits())
    is Err(RowsExceeded(0)),
  )
  assert_true(operation_resolution_at(index, 0) is Some(Unresolved))
}

///|
test "recursive values execution checks expose selected fields and canonical scoped limits" {
  let rows = recursive_values_rows(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
    "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[1,2]}", "[{\"x\":{\"$param\":\"n\"}}]",
    5, 1,
  )
  let index = values_publication_queries_index(
    operation_cells_queries(rows.wire.bound.cells),
  )
  let resolved = resolve_program_values_resources(
    index,
    values_publication_limits(),
  ).unwrap()
  let closed = close_program_operations(resolved, 10000000, 1000).unwrap()
  let mut found = 0
  for i in 0..<operation_closure_count(closed) {
    if operation_closure_at(closed, i)
      is Some(ExecutionCheck(ValuesPublication(check))) {
      found += 1
      let limit = check.recursive_limit.unwrap()
      assert_eq(
        @wire.limit_cid(limit),
        "sha256:072cdb04cb8725d28e0ecd2ec618a02becb30ddcdac814284b8c0ade55f6ee00",
      )
      assert_eq(check.recursive.bytes, 5)
      assert_eq(check.recursive.type_depth, 1)
      assert_eq(values_recursive_field_at(check.recursive, 0), Some(0))
      assert_eq(values_recursive_field_at(check.recursive, -1), None)
      assert_eq(values_recursive_field_at(check.recursive, 1), None)
      assert_eq(@wire.limit_subject(limit), "values:checked-step:0:recursive")
      assert_eq(@derivation.minimum_value(@wire.limit_minimum(limit)), 5L)
      assert_eq(@wire.limit_enforcement(limit), @wire.EngineAtomic)
      assert_eq(@wire.claim_count(@wire.limit_claims(limit)), 1)
    }
  }
  assert_eq(found, 3)
}
