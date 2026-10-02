///|
test "Infer item capacity retains actual Program proofs and Contract ceilings" {
  let prepared = client_infer_prefix_test_program()
  let item_limit = prepare_client_infer_item_limit(
    prepared, 2, 1000000, 1000000, 100000, 100,
  ).unwrap()
  let checked = @strategy.graph_program(prepared.graph)
  assert_true(@checked.infer_item_limit_matches(item_limit, checked, 0, 2))
  assert_false(@checked.infer_item_limit_matches(item_limit, checked, 0, 1))
  assert_false(
    @checked.infer_item_limit_matches(
      item_limit,
      @strategy.graph_program(client_infer_prefix_test_program().graph),
      0,
      2,
    ),
  )
  // The normal Values/assert_rows prefix proves one input row. This is an
  // independent source bound, not the runtime count or the ModelTask ceiling.
  assert_eq(@checked.infer_item_limit_maximum(item_limit), 1L)
  assert_true(@checked.infer_item_limit_proof_count(item_limit) > 0)
  let mut host = false
  let mut task = false
  let mut input = false
  for index in 0..<@checked.infer_item_limit_witness_count(item_limit) {
    let witness = @checked.infer_item_limit_witness_at(item_limit, index).unwrap()
    match @capacity_law.name(@capacity.law(witness)) {
      "actql.host.infer-items" => {
        assert_eq(@capacity.value(witness), 1000L)
        host = true
      }
      "actql.contract.model-task-items" => {
        assert_eq(@capacity.value(witness), 2L)
        task = true
      }
      "actql.bound.infer-distinct-keys" => {
        assert_eq(@capacity.value(witness), 1L)
        input = true
      }
      _ => ()
    }
  }
  assert_true(host && task && input)
}

///|
test "Infer item capacity retains authored guard and rejects foreign steps" {
  let prepared = client_infer_prefix_test_program(
    host_items=2,
    item_guard="\"max_items\":1,",
  )
  let limit = prepare_client_infer_item_limit(
    prepared, 2, 1000000, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(@checked.infer_item_limit_maximum(limit), 1L)
  let mut guard_found = false
  for index in 0..<@checked.infer_item_limit_witness_count(limit) {
    let witness = @checked.infer_item_limit_witness_at(limit, index).unwrap()
    if @capacity_law.name(@capacity.law(witness)) == "actql.guard.infer-items" {
      assert_eq(@capacity.value(witness), 1L)
      guard_found = true
    }
  }
  assert_true(guard_found)
  for step in [-1, 0, 1, 3] {
    assert_true(
      prepare_client_infer_item_limit(
        prepared, step, 1000000, 1000000, 100000, 100,
      )
      is Err(UnsupportedProgram),
    )
  }
  assert_true(
    prepare_client_infer_item_limit(prepared, 2, 0, 1000000, 100000, 100)
    is Err(Preparation(@checked.UnitBuildFailure::BudgetExceeded)),
  )
}

///|
test "Infer item capacity derives each minimum without runtime count feedback" {
  let three =
    #|[{"id":"a","text":"hello"},{"id":"b","text":"hello"},{"id":"c","text":"hello"}]
  for
    (prepared, expected) in [
      (client_infer_prefix_test_program(input_rows=three), 2L),
      (client_infer_prefix_test_program(input_rows=three, host_items=1), 1L),
      (client_infer_prefix_test_program(input_rows="[]"), 0L),
    ] {
    let limit = prepare_client_infer_item_limit(
      prepared, 2, 1000000, 1000000, 100000, 100,
    ).unwrap()
    assert_eq(@checked.infer_item_limit_maximum(limit), expected)
  }
  let supplied = @decode.admit(
    @source.parse_json("{\"limit\":1}", {
      max_input_bytes: 100,
      max_nodes: 10,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 10,
      max_depth: 10,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    },
  ).unwrap()
  let prepared = client_infer_prefix_test_program(
    input_rows=three,
    item_guard="\"max_items\":{\"$param\":\"limit\"},",
    parameters="\"params\":{\"limit\":{\"type\":\"number\",\"nullable\":false}},",
    supplied=Some(supplied),
  )
  let limit = prepare_client_infer_item_limit(
    prepared, 2, 1000000, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(@checked.infer_item_limit_maximum(limit), 1L)
  let mut guard_found = false
  for index in 0..<@checked.infer_item_limit_witness_count(limit) {
    let witness = @checked.infer_item_limit_witness_at(limit, index).unwrap()
    if @capacity_law.name(@capacity.law(witness)) == "actql.guard.infer-items" {
      assert_eq(@capacity.value(witness), 1L)
      guard_found = true
    }
  }
  assert_true(guard_found)
}
