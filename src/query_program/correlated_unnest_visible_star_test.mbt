///|
// An independent ordinary UNNEST Program retains the parent's original array
// and duplicate/NULL elements; SELECT star only chooses its visible columns.
fn correlated_unnest_visible_star_expected() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    correlated_unnest_seed() +
    (
      #|,{"from":"parents","derive":{"aql_unnest_array_4":{"field":"items"}}},{"unnest":{"column":"aql_unnest_array_4","as":"aql_unnest_element_5","with_index":"aql_unnest_offset_6"}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"aql_unnest_offset_6","dir":"asc","nulls":"first"}]},{"select":["id","items",{"element":"aql_unnest_element_5"},{"position":"aql_unnest_offset_6"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","items","element","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "correlated UNNEST visible star has an independent checked common Program" {
  assert_true(
    @check.check_parsed(
      correlated_unnest_visible_star_expected(),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "correlated UNNEST star chooses parent columns scalar element and offset" {
  let expected = semantic(correlated_unnest_visible_star_expected())
  for
    text in [
      "SELECT * FROM parents p CROSS JOIN UNNEST(p.items) element WITH OFFSET position ORDER BY p.id, position",
      "FROM parents p |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position |> SELECT * |> ORDER BY p.id, position",
    ] {
    let actual = match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        correlated_unnest_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedProjection) =>
        fail("correlated UNNEST cannot establish star column scope")
      Err(_) => fail("unexpected correlated UNNEST refusal")
    }
    assert_eq(semantic(actual), expected, msg=text)
  }
}

///|
test "correlated UNNEST star checks the changed current array instead of the initial schema" {
  let context = {
    ..correlated_unnest_context(),
    parameter_declarations: Some(
      @parameters.read_declarations(
        Some(
          unnest_value_cursor(
            (
              #|{"replacement":{"type":"object","nullable":false,"fields":{"code":{"type":"number","nullable":false}}}}
            ),
          ),
        ),
        {
          max_parameters: 10,
          max_nodes: 1000,
          max_depth: 100,
          max_text_bytes: 10000,
        },
      ).unwrap(),
    ),
  }
  let program = compile(
    @query.parse_query(
      "FROM parents p |> SET items = [@replacement] |> CROSS JOIN UNNEST(items) e |> SELECT id, e.* |> ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      program,
      check_environment(),
      Some(unnest_value_cursor("{\"replacement\":{\"code\":9}}")),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("the independently typed current ARRAY needs no Source")
  }
  assert_true(semantic(program).contains("\"fields\":[\"id\",\"code\"]"))
  // The range snapshot remains the original scalar ARRAY, not SET's objects.
  assert_true(
    compile(
      @query.parse_query(
        "FROM parents p |> SET items = [@replacement] |> CROSS JOIN UNNEST(p.items) e |> SELECT e.*",
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

///|
test "correlated UNNEST type inspection retains input and resource refusals" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT * FROM parents p CROSS JOIN UNNEST(p.id) e",
        syntax_limits(),
      ).unwrap(),
      correlated_unnest_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: InvalidArguments, origin: Some(_), })),
  )
  assert_true(
    compile(
      @query.parse_query(
        "FROM parents p |> SELECT id, items |> CROSS JOIN UNNEST(p.items) e |> SELECT *",
        syntax_limits(),
      ).unwrap(),
      correlated_unnest_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: UnknownReference, origin: Some(_), })),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT * FROM parents p CROSS JOIN UNNEST(p.items) e",
        syntax_limits(),
      ).unwrap(),
      correlated_unnest_context(),
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: WorkLimit, .. })),
  )
}

///|
test "correlated nullable object star matches an independent complete Program" {
  let seed =
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"object","nullable":true,"fields":{"code":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}}}},"rows":[{"id":2,"items":[{"code":20,"label":null},null,{"code":20,"label":null}]},{"id":1,"items":[{"code":10,"label":"a"}]},{"id":3,"items":[]},{"id":4,"items":null}]},"as":"parents"}
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    seed +
    (
      #|,{"from":"parents","derive":{"aql_unnest_array_4":{"field":"items"}}},{"unnest":{"column":"aql_unnest_array_4","as":"aql_unnest_element_5","with_index":"aql_unnest_offset_6"}},{"derive":{"aql_unnest_field_7":{"property":{"value":{"field":"aql_unnest_element_5"},"name":"code"}},"aql_unnest_field_8":{"property":{"value":{"field":"aql_unnest_element_5"},"name":"label"}}}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"aql_unnest_offset_6","dir":"asc","nulls":"first"}]},{"select":["id",{"code":"aql_unnest_field_7"},{"label":"aql_unnest_field_8"},{"position":"aql_unnest_offset_6"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","code","label","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  let context = {
    ..correlated_unnest_context(),
    inputs: [
      {
        relation: [{ value: "parents", quoted: false, }],
        name: "parents",
        source: GeneratedValues(unnest_value_cursor(seed)),
        visible_fields: ["id", "items"],
        graph_bindings: [],
      },
    ],
  }
  for
    text in [
      "SELECT p.id, e.*, position FROM parents p CROSS JOIN UNNEST(p.items) e WITH OFFSET position ORDER BY p.id, position",
      "FROM parents p |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position |> ORDER BY p.id, position",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "joined parent retains the declared ARRAY parameter for correlated expansion" {
  let declarations = @parameters.read_declarations(
    Some(
      unnest_value_cursor(
        (
          #|{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}}
        ),
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  // The captured public Host uses the shared script input-binding path.
  let program = match
    compile_query_script(
      @query.parse_query_script(
        "SELECT p.id, element, position FROM parents p JOIN (SELECT 1 AS key) k ON p.id = k.key MAX_OUTPUT_ROWS 4 CROSS JOIN UNNEST(@items) element WITH OFFSET position ORDER BY p.id, position",
        syntax_limits(),
      ).unwrap(),
      {
        ..correlated_unnest_context(),
        parameter_declarations: Some(declarations),
      },
      construction_limits(),
    ) {
    Ok(program) => program
    Err(Expression({ issue: UnknownReference, .. })) =>
      fail("joined lowering: UnknownReference")
    Err(ExpressionTyping({ kind: UnknownParameter(name), .. })) =>
      fail("joined lowering: UnknownParameter " + name)
    Err(UnsupportedCte) => fail("joined lowering: UnsupportedCte")
    Err(UnsupportedJoin) => fail("joined lowering: UnsupportedJoin")
    Err(UnknownColumn) => fail("joined lowering: UnknownColumn")
    Err(AmbiguousColumn) => fail("joined lowering: AmbiguousColumn")
    Err(_) => fail("unexpected joined lowering refusal")
  }
  match
    @check.check_parsed(
      program,
      check_environment(),
      Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("the joined Values parent requires no Source")
  }
}
