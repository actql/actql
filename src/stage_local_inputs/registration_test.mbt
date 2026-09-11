///|
test "reconciled registration exposes stronger schemas without proving declared keys" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let (environment, members) = environment_for([
    snapshot_for("a", schema_fields()),
    snapshot_for("b", schema_fields()),
  ])
  let inputs = reconcile_environment(
    prepared,
    index,
    environment,
    members,
    caps(),
  ).unwrap()
  let a = environment_input_at(inputs, 0).unwrap()
  let b = environment_input_at(inputs, 1).unwrap()
  guard a.1 is @pipeline.KeyedInput(key) else {
    fail("expected conditional primary key")
  }
  assert_false(@evidence.key_pending(key).is_empty())
  guard b.1 is @pipeline.CarrierInput(carrier) else {
    fail("expected typed Relation")
  }
  assert_true(
    @carrier.complete_schema(@carrier.relation_rows(carrier).unwrap())
    is Some(_),
  )
  let source_b = input_at(prepared, 1).unwrap()
  guard source_b.1 is @pipeline.CarrierInput(original) else {
    fail("expected source Relation")
  }
  assert_true(
    @carrier.complete_schema(@carrier.relation_rows(original).unwrap()) is None,
  )
  let stage = checked(source, [b, a])
  let result = attach_reconciled(inputs, stage, max_work=100000).unwrap()
  assert_true(physical_equal(reconciled_inputs(result), inputs))
  assert_true(physical_equal(reconciled_stage(result), stage))
  assert_eq(
    reconciled_work(result),
    environment_usage(inputs).work + @stages.collection_work(stage) + 4,
  )
  assert_true(
    attach_reconciled(inputs, stage, max_work=reconciled_work(result)) is Ok(_),
  )
  assert_true(
    attach_reconciled(inputs, stage, max_work=reconciled_work(result) - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    attach_reconciled(inputs, stage, max_work=-1) is Err(InvalidLimits),
  )
  assert_true(environment_input_at(inputs, -1) is None)
  assert_true(environment_input_at(inputs, 2) is None)
  // The source-only route cannot accept substituted schema/key owners.
  assert_true(
    attach(prepared, stage, max_work=100000) is Err(ForeignInput("a")),
  )
  let old_stage = checked(source, [input_at(prepared, 0).unwrap(), source_b])
  assert_true(
    attach_reconciled(inputs, old_stage, max_work=100000)
    is Err(ForeignInput("a")),
  )
  let equivalent = reconcile_environment(
    prepared,
    index,
    environment,
    members,
    caps(),
  ).unwrap()
  assert_true(
    attach_reconciled(equivalent, stage, max_work=100000)
    is Err(ForeignInput("a")),
  )
}

///|
test "absent schema evidence preserves original registration rather than inventing types" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let (environment, _) = environment_for([])
  let inputs = reconcile_environment(prepared, index, environment, [], caps()).unwrap()
  let stage = checked(source, [
    input_at(prepared, 0).unwrap(),
    input_at(prepared, 1).unwrap(),
  ])
  assert_true(attach_reconciled(inputs, stage, max_work=100000) is Ok(_))
  let other = parsed()
  let other_inputs = prepare(other, 0, caps()).unwrap()
  let other_stage = checked(other, [
    input_at(other_inputs, 0).unwrap(),
    input_at(other_inputs, 1).unwrap(),
  ])
  assert_true(
    attach_reconciled(inputs, other_stage, max_work=100000) is Err(ForeignStage),
  )
}
