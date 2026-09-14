///|
test "score registration retains candidate keys and exact stored owners" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let snapshot = snapshot_in_stage(
    "s",
    "a",
    schema_fields(),
    scores=Some(
      "{\"id\":{\"domain\":\"d\",\"normalization\":\"n\",\"range\":[0,10]}}",
    ),
  )
  let (environment, members) = environment_for([snapshot])
  let inputs = reconcile_environment(
    prepared,
    index,
    environment,
    members,
    caps(),
  ).unwrap()
  let (_, first) = environment_input_at(inputs, 0).unwrap()
  let (_, again) = environment_input_at(inputs, 0).unwrap()
  guard first is @pipeline.RelationEvidenceInput(a) &&
    again is @pipeline.RelationEvidenceInput(b) else {
    fail("combined score and key evidence")
  }
  assert_true(physical_equal(a, b))
  assert_true(environment_score_snapshot_at(inputs, 1) is None)
  assert_true(environment_score_snapshot_at(inputs, -1) is None)
  let retained = environment_score_snapshot_at(inputs, 0).unwrap()
  assert_eq(@snapshot.cid(retained), @snapshot.cid(snapshot))
  let stage = checked(source, [
    environment_input_at(inputs, 0).unwrap(),
    environment_input_at(inputs, 1).unwrap(),
  ])
  assert_true(attach_reconciled(inputs, stage, max_work=100000) is Ok(_))
  let pipeline = @collection.pipeline(@stages.collection(stage))
  assert_true(@pipeline.input_key(pipeline, 0) is Some(_))
  let ranked = @pipeline.ranking_evidence(pipeline, @pipeline.Input(0)).unwrap()
  let score = @evidence.ranking_score_at(ranked, Unqualified("id")).unwrap()
  assert_eq(@evidence.declared_score_contract(score).domain, "d")
  let foreign = reconcile_environment(
    prepared,
    index,
    environment,
    members,
    caps(),
  ).unwrap()
  assert_true(
    attach_reconciled(foreign, stage, max_work=100000) is Err(ForeignInput("a")),
  )
  let used = environment_usage(inputs)
  let exact = {
    ..caps(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(
    reconcile_environment(prepared, index, environment, members, exact) is Ok(_),
  )
  for
    limit in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    let result = reconcile_environment(
      prepared, index, environment, members, limit,
    )
    assert_true(
      result is Err(BudgetExceeded) || result is Err(Snapshots(BudgetExceeded)),
    )
  }
}
