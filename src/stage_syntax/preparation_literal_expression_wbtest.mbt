///|
fn preparation_operand_program(steps : String) -> Program {
  parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[" +
    steps +
    "],\"results\":{\"rows\":{\"from\":\"v\"}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"s\",\"result\":\"rows\"}}}}",
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 40, },
      tree: {
        max_nodes: 1000,
        max_depth: 40,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
}

///|
test "preparation geometry keeps expression-looking Values literal text as data" {
  let program = preparation_operand_program(
    "{\"as\":\"v\",\"meta\":{\"note\":\"a + b\"},\"values\":{\"schema\":{\"x\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"x\":{\"literal\":\"derive(x + y) 😀\"}}]}}",
  )
  let original = program_preparation_data(program)
  assert_false(original.may_contain_expression_syntax)
  assert_eq(original.operations, 1)
  assert_eq(original.initial_fields, 1)
  assert_true(physical_equal(original, program_preparation_data(program)))
}

///|
test "preparation geometry preserves expression allowance for a later operand" {
  let program = preparation_operand_program(
    "{\"as\":\"v\",\"values\":{\"rows\":[]}},{\"as\":\"p\",\"filter\":\"x + 1 > 0\"}",
  )
  assert_true(program_preparation_data(program).may_contain_expression_syntax)
}

///|
test "preparation geometry does not prove unknown operands expression free" {
  let program = preparation_operand_program(
    "{\"as\":\"v\",\"unknown_operand\":{\"body\":\"x + y\"}}",
  )
  assert_true(program_preparation_data(program).may_contain_expression_syntax)
}

///|
test "derived field growth counts output names instead of nested expression nodes" {
  let program = preparation_operand_program(
    "{\"as\":\"v\",\"derive\":{\"cells\":{\"array\":[" +
    "{\"literal\":0},".repeat(39) +
    "{\"literal\":0}]}}}",
  )
  let original = program_preparation_data(program)
  assert_eq(original.possible_growth, 1)
  assert_true(original.may_contain_expression_syntax)
  assert_true(physical_equal(original, program_preparation_data(program)))
}

///|
test "derived nested objects retain both independent output field names" {
  let program = preparation_operand_program(
    "{\"as\":\"v\",\"derive\":{\"first\":{\"object\":{\"inner\":{\"literal\":1}}},\"second\":\"first.inner + 1\"}}",
  )
  assert_eq(program_preparation_data(program).possible_growth, 2)
}

///|
test "unknown object operands retain their conservative subtree growth" {
  let program = preparation_operand_program(
    "{\"as\":\"v\",\"unknown_operand\":{\"body\":{\"array\":[{\"literal\":0}]}}}",
  )
  assert_eq(program_preparation_data(program).possible_growth, 5)
  assert_true(program_preparation_data(program).may_contain_expression_syntax)
}

///|
test "ranking fusion schema growth does not multiply input and weight inventories" {
  for inputs in [1, 257] {
    let others = "\"r\",".repeat(inputs - 1) + "\"r\""
    let weights = "1,".repeat(inputs) + "1"
    let program = preparation_operand_program(
      "{\"as\":\"v\",\"merge_rankings\":{\"with\":[" +
      others +
      "],\"by\":[],\"candidate\":\"id\",\"rank\":\"position\",\"k\":1,\"score_policy\":{\"rrf\":{\"rank_constant\":1,\"weights\":[" +
      weights +
      "],\"rank_window\":1}}}}",
    )
    let data = program_preparation_data(program)
    assert_eq(data.possible_growth, 3)
    assert_true(data.may_contain_expression_syntax)
    assert_true(physical_equal(data, program_preparation_data(program)))
    // Input/weight bodies remain part of the separately priced source tree.
    assert_true(program_usage(program).tree.nodes > inputs * 2)
  }
}

///|
test "ranking fusion schema growth retains every grouping field" {
  let program = preparation_operand_program(
    "{\"as\":\"v\",\"merge_rankings\":{\"with\":\"r\",\"by\":[\"tenant\",\"query\",\"tenant\"],\"candidate\":\"id\",\"score\":\"relevance\",\"k\":1,\"score_policy\":\"max\"}}",
  )
  // Duplicate groups may later be removed by semantic checking; the raw
  // constructor quote conservatively retains their complete declared count.
  assert_eq(program_preparation_data(program).possible_growth, 6)
}

///|
test "ranking fusion with an unrecognized grouping shape keeps subtree backing" {
  for
    operand in [
      "{\"with\":[\"a\",\"b\"],\"candidate\":\"id\"}", "{\"with\":[\"a\",\"b\"],\"by\":{\"unknown\":[1,2,3]},\"candidate\":\"id\"}",
    ] {
    let program = preparation_operand_program(
      "{\"as\":\"v\",\"merge_rankings\":" + operand + "}",
    )
    assert_true(program_preparation_data(program).possible_growth > 3)
    assert_true(program_preparation_data(program).may_contain_expression_syntax)
  }
}
