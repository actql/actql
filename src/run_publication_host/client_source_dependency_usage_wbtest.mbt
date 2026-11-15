///|
// Independent JSON tree observer: keys are not encoder value nodes.
fn source_dependency_json_nodes(value : Json) -> Int {
  match value {
    Array(values) => {
      let mut total = 1
      for value in values {
        total += source_dependency_json_nodes(value)
      }
      total
    }
    Object(values) => {
      let mut total = 1
      for _, value in values {
        total += source_dependency_json_nodes(value)
      }
      total
    }
    _ => 1
  }
}

///|
fn source_dependency_usage_fixture() -> (ClientKeyedLookupInput, () -> Bool) raise {
  let row = "[{\"path\":\"é.txt\",\"resource\":" +
    keyed_work_resource() +
    ",\"version\":\"v0\"}]"
  let (lookup, cleanup, _) = keyed_work_original_fixture(row, 1, 1000000)
  (lookup, cleanup)
}

///|
fn source_dependency_scanned_identity(
  lookup : ClientKeyedLookupInput,
) -> (@query.CapturedInputSource, @query.CapturedSourceRelationIdentity) raise {
  guard lookup.left.composed is Some(original) && original.sources is [source] else {
    fail("original Source")
  }
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 1000000,
    max_depth: 20,
    max_work: 1000000,
  }
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 1000000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let basis_r = lookup.retained_bytes
  let basis_e = lookup.execution_bytes
  let start = @query.captured_source_cell_identity_start_capacity(source).unwrap()
  keyed_lookup_body_grow(lookup, basis_r, basis_e, 0L, Some(start)).unwrap()
  let scan = @query.start_captured_source_cell_identity(
    source,
    1,
    values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 1000000, max_nodes: 10000, max_depth: 20, },
    1000000,
    100000,
    1000000,
  ).unwrap()
  defer @query.cancel_captured_source_cell_identity(scan) |> ignore
  let first = @query.captured_source_cell_identity_next_capacity(scan).unwrap()
  let r = @execution.execution_capacity_retained_bytes(first)
  let e = @execution.execution_capacity_execution_bytes(first)
  for
    short in [
      @execution.execution_capacity(r - 1L, e).unwrap(),
      @execution.execution_capacity(r - 1L, e - 1L).unwrap(),
    ] {
    let before = @query.captured_source_cell_identity_work(scan)
    assert_eq(
      @query.advance_captured_source_cell_identity(scan, 7, short).unwrap(),
      (false, 0),
    )
    assert_eq(@query.captured_source_cell_identity_work(scan), before)
  }
  let mut finished = false
  for _ in 0..<10000 {
    let next = @query.captured_source_cell_identity_next_capacity(scan).unwrap()
    keyed_lookup_body_grow(lookup, basis_r, basis_e, 0L, Some(next)).unwrap()
    if @query.advance_captured_source_cell_identity(scan, 7, next).unwrap().0 {
      finished = true
      break
    }
  }
  assert_true(finished)
  (source, @query.finish_captured_source_cell_identity(scan).unwrap())
}

///|
test "Source encoder facts retain exact UTF8 and node dimensions on the original funded scan" {
  let (lookup, cleanup) = source_dependency_usage_fixture()
  defer assert_true(cleanup())
  let (source, identity) = source_dependency_scanned_identity(lookup)
  let (body, schema) = @query.captured_source_relation_dependency_bodies(
    identity, source,
  ).unwrap()
  let usage = @query.captured_source_relation_dependency_usage(identity, source).unwrap()
  assert_eq(usage.logical_bytes, @utf8.encode(body).length())
  assert_eq(usage.schema_bytes, @utf8.encode(schema).length())
  assert_eq(
    usage.logical_nodes,
    source_dependency_json_nodes(@json.parse(body)),
  )
  assert_eq(
    usage.schema_nodes,
    source_dependency_json_nodes(@json.parse(schema)),
  )
  assert_true(usage.logical_bytes > body.length())
  assert_true(
    usage.logical_nodes > @query.captured_source_relation_row_count(identity),
  )
  // Clearing the one original retained-body owner also retires its facts.
  @query.clear_captured_source_relation_dependency_bodies(identity)
  assert_true(
    @query.captured_source_relation_dependency_usage(identity, source) is None,
  )
  assert_true(
    @query.captured_source_relation_dependency_bodies(identity, source) is None,
  )
}

///|
test "equal Source CIDs never transfer encoder facts and stopped originals cannot lend them" {
  let (lookup, cleanup) = source_dependency_usage_fixture()
  let (other, other_cleanup) = source_dependency_usage_fixture()
  defer assert_true(other_cleanup())
  let (source, identity) = source_dependency_scanned_identity(lookup)
  let (foreign, other_identity) = source_dependency_scanned_identity(other)
  assert_eq(
    @query.captured_source_relation_logical_cid(identity),
    @query.captured_source_relation_logical_cid(other_identity),
  )
  assert_eq(
    @query.captured_source_relation_schema_cid(identity),
    @query.captured_source_relation_schema_cid(other_identity),
  )
  assert_true(
    @query.captured_source_relation_dependency_usage(identity, foreign) is None,
  )
  assert_true(
    @query.captured_source_relation_dependency_bodies(identity, foreign) is None,
  )
  assert_true(
    @query.captured_source_relation_dependency_usage(identity, source)
    is Some(_),
  )
  assert_true(cleanup())
  assert_true(
    @query.captured_source_relation_dependency_usage(identity, source) is None,
  )
}
