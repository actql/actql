///|
fn execution_for(
  sequence : @lower.PreparedSequence,
  work : Int64,
  limits? : LogicalLimits? = None,
) -> OrderedExecution raise {
  guard @lower.sequence_step(sequence, 1) is Some(@lower.RowStep(kernel)) else {
    fail("kernel")
  }
  let references = @lower.prepare_ordered_references(kernel, {
    max_references: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let contract = admit_ordered_contract(
    registered_relation_contracts(),
    registered_ordered(),
    registry_limits(),
  ).unwrap()
  let params = prepare_ordered_params(contract, references)
  let context = prepare_ordered_limits(
    params,
    limits.unwrap_or({
      max_input_rows: 2L,
      max_value_bytes: 31L,
      max_live_value_bytes: 78L,
      max_work: work,
    }),
    100L,
    1000L,
  ).unwrap()
  { contexts: [context], max_bytes: 1000, max_nodes: 1000, max_depth: 100, }
}

///|
test "single sequence driver enforces ordered limits through values filter select" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"},{\"total\":\"old + a\"}]},{\"filter\":\"total > 1\"},{\"select\":[\"total\",\"a\"]}",
    ),
  )
  let execution = execution_for(sequence, 84L)
  let contracts = registered_relation_contracts()
  let run = fn(config) {
    evaluate_sequence_components(
      contracts,
      sequence,
      [],
      ["select_3"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      ordered=config,
    )
  }
  let completed = match run(execution) {
    Ok(v) => v
    Err(OrderedContext(i, _)) => fail("context \{i}")
    Err(Rows(i, LogicalRows(_))) => fail("logical \{i}")
    Err(Rows(i, Evaluation(r, s, _))) => fail("eval \{i} \{r} \{s}")
    Err(Rows(i, _)) => fail("rows \{i}")
    Err(_) => fail("other")
  }
  let table = test_row_store(completed).tables[3].unwrap().table
  assert_eq(table.names, ["total", "a"])
  assert_eq(table.rows.length(), 1)
  assert_true(table.rows[0][0] is Number(3.0))
  assert_true(table.rows[0][1] is Number(2.0))
  assert_true(test_row_store(completed).tables[0] is None)
  assert_true(test_row_store(completed).tables[1] is None)
  assert_true(test_row_store(completed).tables[2] is None)
  // Same immutable configuration creates fresh enforcement state per execution.
  assert_true(run(execution) is Ok(_))
  assert_true(run(execution_for(sequence, 83L)) is Err(Rows(1, _)))
  assert_true(run({ ..execution, max_bytes: 30, }) is Err(Rows(1, _)))
  assert_true(run({ ..execution, max_nodes: 1, }) is Err(Rows(1, _)))
  assert_true(run({ ..execution, max_depth: 0, }) is Err(Rows(1, _)))
}

///|
test "sequence preflight rejects duplicate foreign and missing ordered contexts" {
  let source = ",{\"derive\":[{\"unused\":\"1 / b\"}]}"
  let sequence = prepared_sequence(row_owner(source))
  let config = execution_for(sequence, 1000L)
  let contracts = registered_relation_contracts()
  let run = fn(execution) {
    evaluate_sequence_components(
      contracts,
      sequence,
      [],
      ["derive_1"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      ordered=execution,
    )
  }
  assert_true(run(config) is Err(Rows(1, Evaluation(0, 0, _))))
  // These errors precede the failing unused expression above.
  assert_true(
    run({ ..config, contexts: [], })
    is Err(Rows(1, MissingOrderedResourceContext)),
  )
  assert_true(
    run({ ..config, contexts: [config.contexts[0], config.contexts[0]], })
    is Err(OrderedContext(1, ForeignKernel)),
  )
  assert_true(
    run(execution_for(prepared_sequence(row_owner(source)), 1000L))
    is Err(OrderedContext(1, ForeignKernel)),
  )
  assert_true(run({ ..config, max_bytes: -1, }) is Err(InvalidLimits))
  let other = prepared_sequence(row_owner(",{\"derive\":{\"x\":\"a\"}}"))
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      other,
      [],
      ["derive_1"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      ordered=config,
    )
    is Err(OrderedContext(1, ForeignKernel)),
  )
}
