///|
fn snapshot_for(name : String, fields : String) -> @snapshot.Snapshot {
  snapshot_in_stage("s", name, fields)
}

///|
fn snapshot_in_stage(
  stage : String,
  name : String,
  fields : String,
  scores? : String? = None,
) -> @snapshot.Snapshot {
  // Linkage tests use the already independently tested snapshot reader, not an
  // independent hash oracle. Body bytes here are explicitly canonical.
  let bytes = @utf8.encode(
    "{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":" +
    fields +
    ",\"nullable\":false,\"type\":\"object\"}" +
    (match scores {
      None => ""
      Some(value) => ",\"score_contracts\":" + value
    }) +
    ",\"source_ref\":\"source:local/" +
    stage +
    "/" +
    name +
    "\",\"version\":\"actql-local-input-schema/0.1\"}",
  )
  @snapshot.read(bytes, "sha256:" + @sha.hex(bytes), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
}

///|
fn schema_fields() -> String {
  "{\"id\":{\"nullable\":false,\"type\":\"number\"}}"
}

///|
test "snapshot references and stronger schemas bind exact source declarations" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let b = snapshot_for("b", schema_fields())
  let a = snapshot_for("a", schema_fields())
  let supplied = [b, a]
  let checked = reconcile_snapshots(prepared, index, supplied, caps()).unwrap()
  supplied.clear()
  assert_eq(snapshot_count(checked), 2)
  assert_true(physical_equal(snapshot_inputs(checked), prepared))
  assert_true(
    physical_equal(schema_inputs(snapshot_assertions(checked)), prepared),
  )
  for (i, position, expected) in [(0, 1, b), (1, 0, a)] {
    let binding = snapshot_binding_at(checked, i).unwrap()
    assert_true(physical_equal(bound_snapshot(binding), expected))
    let input = bound_input(binding)
    let agreement = bound_schema(binding)
    assert_true(physical_equal(@refs.input_index(input), index))
    assert_true(
      physical_equal(
        @local_input.schema_declaration(agreement),
        entry_at(prepared, position).unwrap().1,
      ),
    )
    let cursor = @local_input.source(@local_input.schema_declaration(agreement))
    assert_eq(
      @decode.tree_index(cursor, @refs.declaration(input)),
      @decode.tree_index(cursor, cursor),
    )
    assert_true(
      physical_equal(
        @local_input.supplied_schema(agreement),
        @snapshot.schema(expected),
      ),
    )
  }
  assert_true(snapshot_binding_at(checked, -1) is None)
  assert_true(snapshot_binding_at(checked, 2) is None)
  let partial = reconcile_snapshots(prepared, index, [b], caps()).unwrap()
  assert_true(schema_agreement_at(snapshot_assertions(partial), 0) is None)
  assert_eq(
    snapshot_count(reconcile_snapshots(prepared, index, [], caps()).unwrap()),
    0,
  )
}

///|
test "snapshot binding rejects foreign source duplicate references and incompatible schema" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let a = snapshot_for("a", schema_fields())
  let other = @refs.prepare(parsed(), {
    max_work: 10000,
    max_text_bytes: 10000,
  }).unwrap()
  assert_true(
    reconcile_snapshots(prepared, other, [a], caps()) is Err(ForeignProgram),
  )
  assert_true(
    reconcile_snapshots(prepared, index, [a, a], caps())
    is Err(Resolution(@refs.DuplicateReference("source:local/s/a"))),
  )
  assert_true(
    reconcile_snapshots(
      prepared,
      index,
      [snapshot_for("unknown", "{}")],
      caps(),
    )
    is Err(Resolution(@refs.UnknownInput("s", "unknown"))),
  )
  assert_true(
    reconcile_snapshots(
      prepared,
      index,
      [snapshot_for("b", "{}"), snapshot_for("a", "{}")],
      caps(),
    )
    is Err(Assertions(Assertion("a", @local_input.TypeMismatch))),
  )
}

///|
test "snapshot reconciliation uses cumulative exact budgets" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let supplied = [
    snapshot_for("a", schema_fields()),
    snapshot_for("b", schema_fields()),
  ]
  let used = snapshot_usage(
    reconcile_snapshots(prepared, index, supplied, caps()).unwrap(),
  )
  let exact = {
    ..caps(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(reconcile_snapshots(prepared, index, supplied, exact) is Ok(_))
  for
    limit in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      reconcile_snapshots(prepared, index, supplied, limit)
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    reconcile_snapshots(prepared, index, supplied, { ..exact, max_work: -1, })
    is Err(InvalidLimits),
  )
}
