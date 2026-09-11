///|
fn caps() -> Limits {
  { max_work: 10000, max_text_bytes: 10000, }
}

///|
fn parsed_source() -> @stages.Source {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"a/b","inputs":{"rows":"relation","graph":"graph","connector":{"connector":"c","resource":"r"}},"steps":[],"results":{"out":{}},"effects":{"e":{}}},{"id":"a~1b","inputs":{"rows":"relation","~1":"events","result":{"result":{"stage":"a/b","result":"out"}},"receipt":{"receipt":{"stage":"a/b","effect":"e"}}},"steps":[],"results":{"out":{}}}],"results":{"out":{"from":{"stage":"a~1b","result":"out"}}}}
    ),
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn selector(stage : String, input : String) -> @reference.Reference {
  @reference.create(stage, input, max_bytes=1000).unwrap()
}

///|
test "local selectors resolve exact stage slots without conflating escaped names" {
  let source = parsed_source()
  let index = prepare(source, caps()).unwrap()
  let refs = [
    selector("a~1b", "rows"),
    selector("a/b", "rows"),
    selector("a/b", "graph"),
    selector("a~1b", "~1"),
  ]
  let resolved = resolve(index, refs, caps()).unwrap()
  refs.clear()
  assert_eq(count(resolved), 4)
  assert_true(physical_equal(resolved_index(resolved), index))
  assert_true(physical_equal(@stage_source_refs.source(index), source))
  for
    (i, expected_stage, expected_input) in [
      (0, 1, "rows"),
      (1, 0, "rows"),
      (2, 0, "graph"),
      (3, 1, "~1"),
    ] {
    let input = entry_at(resolved, i).unwrap()
    assert_eq(stage_index(input), expected_stage)
    assert_eq(@reference.input_name(input_reference(input)), expected_input)
    assert_true(physical_equal(input_index(input), index))
    let body = @decode.open_object(
      @syntax.stage_body(@stages.stage_at(source, expected_stage).unwrap()),
    ).unwrap()
    let inputs = @decode.open_object(@decode.required(body, "inputs").unwrap()).unwrap()
    let expected = @decode.required(inputs, expected_input).unwrap()
    assert_eq(
      @decode.cursor_path(declaration(input)),
      @decode.cursor_path(expected),
    )
    assert_eq(
      @decode.cursor_span(declaration(input)),
      @decode.cursor_span(expected),
    )
  }
  assert_true(entry_at(resolved, -1) is None)
  assert_true(entry_at(resolved, 4) is None)
  let other = prepare(parsed_source(), caps()).unwrap()
  let foreign = resolve(other, [selector("a/b", "rows")], caps()).unwrap()
  assert_false(
    physical_equal(input_index(entry_at(foreign, 0).unwrap()), index),
  )
  assert_false(physical_equal(@stage_source_refs.source(other), source))
}

///|
test "local resolution rejects imports connectors unknown names and repeated selectors" {
  let index = prepare(parsed_source(), caps()).unwrap()
  for
    (stage, input) in [
      ("a/b", "connector"),
      ("a~1b", "result"),
      ("a~1b", "receipt"),
    ] {
    assert_true(
      resolve(index, [selector(stage, input)], caps())
      is Err(NonLocalInput(s, n)) &&
      s == stage &&
      n == input,
    )
  }
  assert_true(
    resolve(index, [selector("unknown", "rows")], caps())
    is Err(UnknownStage("unknown")),
  )
  assert_true(
    resolve(index, [selector("a/b", "missing")], caps())
    is Err(UnknownInput("a/b", "missing")),
  )
  let duplicate = selector("a/b", "rows")
  assert_true(
    resolve(index, [duplicate, duplicate], caps())
    is Err(DuplicateReference("source:local/a~1b/rows")),
  )
  assert_true(
    resolve(index, [duplicate, selector("a~1b", "receipt")], caps())
    is Err(NonLocalInput("a~1b", "receipt")),
  )
  assert_eq(count(resolve(index, [], caps()).unwrap()), 0)
}

///|
test "indexing and batch lookup account for shared work and text boundaries" {
  let source = parsed_source()
  let index = prepare(source, caps()).unwrap()
  let used = index_usage(index)
  let exact : Limits = { max_work: used.work, max_text_bytes: used.text_bytes, }
  assert_true(prepare(source, exact) is Ok(_))
  assert_true(
    prepare(source, { ..exact, max_work: used.work - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare(source, { ..exact, max_text_bytes: used.text_bytes - 1, })
    is Err(BudgetExceeded),
  )
  let refs = [selector("a/b", "rows"), selector("a~1b", "rows")]
  let total = resolved_usage(resolve(index, refs, caps()).unwrap())
  assert_eq(total.work, used.work + 2)
  let final_limits : Limits = {
    max_work: total.work,
    max_text_bytes: total.text_bytes,
  }
  assert_true(resolve(index, refs, final_limits) is Ok(_))
  assert_true(
    resolve(index, refs, { ..final_limits, max_work: total.work - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    resolve(index, refs, {
      ..final_limits,
      max_text_bytes: total.text_bytes - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare(source, { ..caps(), max_work: -1, }) is Err(InvalidLimits),
  )
  assert_true(
    resolve(index, refs, { ..caps(), max_text_bytes: -1, })
    is Err(InvalidLimits),
  )
}
