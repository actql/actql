///|
fn supplied_schema(prepared : Prepared) -> @schema.Schema {
  @carrier.complete_schema(
    @carrier.relation_rows(
      @local_input.carrier(entry_at(prepared, 0).unwrap().1),
    ).unwrap(),
  ).unwrap()
}

///|
test "schema assertions retain exact stage declarations without authenticating input evidence" {
  let prepared = prepare(parsed(), 0, caps()).unwrap()
  let schema = supplied_schema(prepared)
  let supplied = [("b", schema), ("a", schema)]
  let assertions = reconcile_schemas(prepared, supplied, caps()).unwrap()
  supplied.clear()
  assert_true(physical_equal(schema_inputs(assertions), prepared))
  for i in 0..<2 {
    let agreement = schema_agreement_at(assertions, i).unwrap()
    assert_true(
      physical_equal(
        @local_input.schema_declaration(agreement),
        entry_at(prepared, i).unwrap().1,
      ),
    )
    assert_true(physical_equal(@local_input.supplied_schema(agreement), schema))
  }
  assert_true(schema_agreement_at(assertions, -1) is None)
  assert_true(schema_agreement_at(assertions, 2) is None)
  assert_true(
    @local_input.schema_primary_key(schema_agreement_at(assertions, 0).unwrap())
    is Some(_),
  )
  assert_true(
    @local_input.schema_primary_key(schema_agreement_at(assertions, 1).unwrap())
    is None,
  )
  // Reconciliation does not mutate the source-only registration handles.
  let stage = checked(@stage_local_inputs.source(prepared), [
    input_at(prepared, 0).unwrap(),
    input_at(prepared, 1).unwrap(),
  ])
  assert_true(attach(prepared, stage, max_work=100000) is Ok(_))
}

///|
test "partial schema assertions do not invent evidence for omitted slots" {
  let prepared = prepare(parsed(), 0, caps()).unwrap()
  let schema = supplied_schema(prepared)
  let assertions = reconcile_schemas(prepared, [("b", schema)], caps()).unwrap()
  assert_true(schema_agreement_at(assertions, 0) is None)
  assert_true(schema_agreement_at(assertions, 1) is Some(_))
  let empty = reconcile_schemas(prepared, [], caps()).unwrap()
  assert_true(schema_agreement_at(empty, 0) is None)
  assert_true(schema_agreement_at(empty, 1) is None)
  assert_true(
    reconcile_schemas(prepared, [("missing", schema)], caps())
    is Err(UnknownInput("missing")),
  )
  assert_true(
    reconcile_schemas(prepared, [("a", schema), ("a", schema)], caps())
    is Err(DuplicateInput("a")),
  )
}

///|
test "late assertion failure exposes no partial schema batch" {
  let prepared = prepare(parsed(), 0, caps()).unwrap()
  let empty = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  assert_true(
    reconcile_schemas(prepared, [("b", empty), ("a", empty)], caps())
    is Err(Assertion("a", @local_input.TypeMismatch)),
  )
  let source = @stage_local_inputs.source(prepared)
  let reread = prepare(source, 0, caps()).unwrap()
  let assertions = reconcile_schemas(reread, [("b", empty)], caps()).unwrap()
  assert_false(physical_equal(schema_inputs(assertions), prepared))
  assert_true(
    physical_equal(
      @local_input.schema_declaration(
        schema_agreement_at(assertions, 1).unwrap(),
      ),
      entry_at(reread, 1).unwrap().1,
    ),
  )
}

///|
test "schema assertions share source and all supplied type budgets" {
  let prepared = prepare(parsed(), 0, caps()).unwrap()
  let schema = supplied_schema(prepared)
  let supplied = [("a", schema), ("b", schema)]
  let used = schema_assertion_usage(
    reconcile_schemas(prepared, supplied, caps()).unwrap(),
  )
  let exact = {
    ..caps(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(reconcile_schemas(prepared, supplied, exact) is Ok(_))
  for
    limit in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      reconcile_schemas(prepared, supplied, limit) is Err(BudgetExceeded),
    )
  }
  assert_true(
    reconcile_schemas(prepared, supplied, { ..exact, max_work: -1, })
    is Err(InvalidLimits),
  )
}
