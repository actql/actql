///|
fn infer_program(text : String) -> Result[@program.Program, Issue] {
  compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  )
}

///|
test "INFER KEEP establishes a new scope without old aliases or hidden columns" {
  for
    suffix in [
      "SELECT y", "SELECT before.x", "SELECT before.y + 1 AS y", "WHERE before.y = 1",
      "SELECT x |> ORDER BY before.x", "SET x = before.x", "EXTEND before.x AS z",
    ] {
    assert_true(
      infer_program(
        "FROM pair AS before |> INFER score ITEM KEY (x) INPUT (n = y) KEEP (x) AS assessment |> " +
        suffix,
      )
      is Err(_),
      msg=suffix,
    )
  }
  let program = infer_program(
    "FROM pair AS before |> INFER score ITEM KEY (x) INPUT (n = y) KEEP (x) AS assessment |> SELECT x, assessment.value.risk AS risk",
  ).unwrap()
  assert_true(semantic(program).contains("\"property\""))
  assert_true(semantic(program).contains("\"fields\":[\"x\",\"risk\"]"))
}

///|
test "KEEP expands the selected row or original range snapshot in fixed order" {
  for keep in ["*", "before.*", "`BEFORE`.*"] {
    let program = infer_program(
      "FROM pair AS before |> INFER score ITEM KEY (x) INPUT (n = y) KEEP (" +
      keep +
      ") AS assessment",
    ).unwrap()
    assert_true(
      semantic(program).contains("\"fields\":[\"x\",\"y\",\"assessment\"]"),
    )
  }
  let program = infer_program(
    "FROM pair AS before |> SET y = x |> INFER score ITEM KEY (x) INPUT (n = y) KEEP (y AS current, before.y AS original) AS assessment",
  ).unwrap()
  let body = semantic(program)
  assert_true(body.contains("\"current\":\"right.aql_pipe_set_2\""))
  assert_true(body.contains("\"original\":\"right.y\""))
}

///|
test "INFER rejects duplicate keys, output collisions and unresolved input roles" {
  for
    clause in [
      "ITEM KEY (x, x) INPUT () AS assessment", "ITEM KEY (x, before.x) INPUT () AS assessment",
      "ITEM KEY (unknown) INPUT () AS assessment", "ITEM KEY (x) INPUT (n = unknown) AS assessment",
      "ITEM KEY (x) INPUT (n = x, n = y) AS assessment", "ITEM KEY (x) INPUT () KEEP (x, before.x) AS assessment",
      "ITEM KEY (x) INPUT () KEEP (x AS assessment) AS assessment", "ITEM KEY (x) INPUT () KEEP (missing.*) AS assessment",
    ] {
    assert_true(
      infer_program("FROM pair AS before |> INFER score " + clause) is Err(_),
      msg=clause,
    )
  }
}

///|
test "INFER Program admission is not common checker or execution support" {
  let program = infer_program(
    "FROM pair |> INFER score ITEM KEY (x) INPUT (n = y) AS assessment",
  ).unwrap()
  // No checked owner is manufactured while the shared infer checker is absent.
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Rejected(error) =>
      assert_eq(
        @check.diagnostic_category(error),
        @check.UnsupportedImplementation,
      )
    _ => fail("the common infer owner is not implemented")
  }
}

///|
test "nested object references lower independently of model acquisition" {
  let program = infer_program(
    "FROM pair |> AS t |> WHERE x.risk = 'high' |> SELECT x.risk AS risk",
  ).unwrap()
  assert_true(
    semantic(program).contains(
      "\"property\":{\"name\":\"risk\",\"value\":{\"field\":\"x\"}}",
    ),
  )
  // x is numeric here: the frontend resolves names, the common checker rejects
  // the property type. It must not invent an object contract from the spelling.
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is Rejected(_),
  )
}

///|
test "nested INFER output ORDER uses one hidden property slot and preserves scope" {
  let program = infer_program(
    "FROM pair AS before |> INFER score ITEM KEY (x) INPUT (n = y) KEEP (x) AS assessment |> ORDER BY assessment.value.risk, assessment.value.risk DESC",
  ).unwrap()
  let body = semantic(program)
  assert_true(
    body.contains(
      "\"derive\":{\"aql_pipe_sort_4\":{\"property\":{\"name\":\"risk\",\"value\":{\"property\":{\"name\":\"value\",\"value\":{\"field\":\"assessment\"}}}}}}",
    ),
  )
  assert_true(
    body.contains(
      "\"sort\":[{\"dir\":\"asc\",\"field\":\"aql_pipe_sort_4\",\"nulls\":\"first\"},{\"dir\":\"desc\",\"field\":\"aql_pipe_sort_4\",\"nulls\":\"last\"}]",
    ),
  )
  assert_true(body.contains("\"select\":[\"x\",\"assessment\"]"))
  assert_true(
    infer_program(
      "FROM pair AS before |> INFER score ITEM KEY (x) INPUT (n = y) AS assessment |> ORDER BY before.y + 1",
    )
    is Err(_),
  )
}

///|
test "INFER internal producer names do not collide with the bound input" {
  for source_name in ["aql_infer_input_0", "aql_infer_outcome_0"] {
    let base = pair_context()
    let seed = @wire.admit(
      @source.parse_json(
        "{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false},\"y\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"" +
        source_name +
        "\"}",
        construction_limits().source.source,
      ).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    let context = {
      ..base,
      inputs: [
        { ..base.inputs[0], name: source_name, source: GeneratedValues(seed), },
      ],
    }
    let query = @query.parse_query(
      "FROM pair |> INFER score ITEM KEY (x) INPUT (n = y) AS assessment",
      syntax_limits(),
    ).unwrap()
    let body = semantic(compile(query, context, construction_limits()).unwrap())
    assert_true(body.contains("\"as\":\"" + source_name + "_\""))
  }
}
