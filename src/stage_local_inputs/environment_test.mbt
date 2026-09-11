///|
fn environment_for(
  supplied : Array[@snapshot.Snapshot],
) -> (@environment.WireEnvironment, Array[@snapshot.EnvironmentSnapshot]) raise @encode.EncodeFailure {
  // Ownership tests reuse verified codecs; fixed wire identities live in the
  // independent Check Environment corpus, not in this helper.
  let sorted = supplied.copy()
  sorted.sort_by((a, b) => @snapshot.cid(a).compare(@snapshot.cid(b)))
  let rows = @encode.writer(100000, 10000, 100)
  @encode.begin_array(rows)
  for value in sorted {
    @snapshot.emit(value, rows)
  }
  @encode.end_array(rows)
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":" +
    @encode.finish(rows) +
    ",\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = @environment.read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  ).unwrap()
  let members = []
  for i in 0..<sorted.length() {
    members.push(
      @snapshot.read_member(
        @environment.member_at(environment, @environment.SchemaSnapshots, i).unwrap(),
        { max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      ).unwrap(),
    )
  }
  (environment, members)
}

///|
test "environment membership stays aligned with resolved snapshot bindings" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let (environment, supplied) = environment_for([
    snapshot_for("b", schema_fields()),
    snapshot_for("a", schema_fields()),
  ])
  let first = supplied[0]
  supplied[0] = supplied[1]
  supplied[1] = first
  let kept = supplied.copy()
  let checked = reconcile_environment(
    prepared,
    index,
    environment,
    supplied,
    caps(),
  ).unwrap()
  supplied.clear()
  assert_true(physical_equal(input_environment(checked), environment))
  let assertions = environment_assertions(checked)
  assert_true(physical_equal(snapshot_inputs(assertions), prepared))
  for i in 0..<kept.length() {
    let entry = environment_snapshot_at(checked, i).unwrap()
    assert_true(physical_equal(entry, kept[i]))
    let binding = snapshot_binding_at(assertions, i).unwrap()
    assert_true(
      physical_equal(
        bound_snapshot(binding),
        @snapshot.environment_snapshot(entry),
      ),
    )
    assert_true(physical_equal(@refs.input_index(bound_input(binding)), index))
  }
  assert_true(environment_snapshot_at(checked, -1) is None)
  assert_true(environment_snapshot_at(checked, 2) is None)
  assert_true(
    reconcile_environment(prepared, index, environment, [], caps()) is Ok(_),
  )
}

///|
test "equal environment bytes do not authorize mixing independently read members" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let snapshots = [
    snapshot_for("a", schema_fields()),
    snapshot_for("b", schema_fields()),
  ]
  let (environment, entries) = environment_for(snapshots)
  let (other, foreign) = environment_for(snapshots)
  assert_eq(@environment.cid(environment), @environment.cid(other))
  assert_true(
    reconcile_environment(
      prepared,
      index,
      environment,
      [entries[0], foreign[1]],
      caps(),
    )
    is Err(ForeignEnvironment(1)),
  )
  assert_true(
    reconcile_environment(
      prepared,
      index,
      environment,
      [entries[0], entries[0]],
      caps(),
    )
    is Err(Snapshots(Resolution(@refs.DuplicateReference(_)))),
  )
  let other_index = @refs.prepare(parsed(), {
    max_work: 10000,
    max_text_bytes: 10000,
  }).unwrap()
  assert_true(
    reconcile_environment(prepared, other_index, environment, entries, caps())
    is Err(Snapshots(ForeignProgram)),
  )
}

///|
test "environment reconciliation charges membership and full snapshot costs cumulatively" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let (environment, entries) = environment_for([
    snapshot_for("a", schema_fields()),
    snapshot_for("b", schema_fields()),
  ])
  let used = environment_usage(
    reconcile_environment(prepared, index, environment, entries, caps()).unwrap(),
  )
  let exact = {
    ..caps(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(
    reconcile_environment(prepared, index, environment, entries, exact) is Ok(_),
  )
  for
    limit in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_work: 1, },
    ] {
    assert_true(
      reconcile_environment(prepared, index, environment, entries, limit)
      is Err(EnvironmentIssue::BudgetExceeded),
    )
  }
  assert_true(
    reconcile_environment(prepared, index, environment, entries, {
      ..exact,
      max_work: -1,
    })
    is Err(InvalidLimits),
  )
}
