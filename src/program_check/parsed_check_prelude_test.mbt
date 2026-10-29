///|
test "original semantic prelude continues full or retained Catalog and is consumed once" {
  for retained in [false, true] {
    let (_, program, environment, evidence, limits) = public_input_fixture(
      generated=true,
      repeated=true,
    )
    let catalog = if retained {
      Some(
        @program_check.prepare_source_catalog(environment, {
          max_work: 10000000,
          max_bytes: 1000000,
          max_nodes: 100000,
          max_depth: 100,
        }).unwrap(),
      )
    } else {
      None
    }
    let input = @program_check.prepare_parsed_check_input(
      program,
      environment,
      None,
      evidence,
      limits,
      source_catalog=catalog,
    ).unwrap()
    let (result, spent) = @program_check.observe_parsed_check_prelude(input)
    assert_true(
      spent > 0 &&
      spent < @program_check.parsed_check_input_semantic_work(input),
    )
    let prelude = result.unwrap()
    evidence.clear()
    let checked = public_checked(
      @program_check.finish_parsed_check_prelude(prelude).unwrap(),
    )
    assert_eq(@program_check.unit_count(checked), 2)
    let imported = @program_check.unit_result_import_at(checked, 1, 0).unwrap()
    assert_eq(imported.producer_node_id, "producer")
    assert_eq(imported.result_name, "out")
    assert_true(
      @program_check.finish_parsed_check_prelude(prelude)
      is Err(AlreadyConsumed),
    )
  }
}

///|
test "semantic prelude retains original missing Parameter evidence through the real checker" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let program = @syntax.parse(
    text.replace(old=",\"default\":1", new=""),
    limits.input,
    format=Json,
    source_path="semantic-prelude.actql",
  ).unwrap()
  let original = @program_check.prepare_parsed_check_input(
    program,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let prelude = @program_check.observe_parsed_check_prelude(original).0.unwrap()
  guard @program_check.finish_parsed_check_prelude(prelude).unwrap()
    is NeedsInputs(requests) else {
    fail("lost original missing Parameter")
  }
  let request = @program_check.input_request_at(requests, 0).unwrap()
  assert_true(physical_equal(request.program, program))
  assert_true(physical_equal(request.environment, environment))
  guard request.kind is ParameterValue(declaration) else {
    fail("not a Parameter request")
  }
  assert_eq(declaration.name, "n")
  assert_eq(
    @decode.cursor_span(@parameters.declaration_source(declaration)).source_path,
    "semantic-prelude.actql",
  )
}
