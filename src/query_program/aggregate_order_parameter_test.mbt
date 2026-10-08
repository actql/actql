///|
fn aggregate_order_parameter_expected(
  declarations : String,
  key : String,
) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"params\":" +
    declarations +
    ",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    ",{\"from\":\"objects\",\"derive\":{\"aql_aggregate_sort_5\":" +
    key +
    (
      #|}},{"group":{"by":[],"aggregates":{"names":{"fn":"string_agg","field":"name","max_bytes":10000,"order_by":[{"field":"aql_aggregate_sort_5","dir":"desc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"delimiter":"|"}}}},{"select":["names"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["names"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn aggregate_order_parameter_values(text : String) -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(text, construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
test "aggregate parameter order has independent checked scalar and nullable object Programs" {
  let scalar = aggregate_order_parameter_expected(
    "{\"key\":{\"type\":\"number\",\"nullable\":true}}", "{\"$param\":\"key\"}",
  )
  let object = aggregate_order_parameter_expected(
    "{\"cfg\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"rank\":{\"type\":\"number\",\"nullable\":true}}}}",
    "{\"property\":{\"name\":\"rank\",\"value\":{\"$param\":\"cfg\"}}}",
  )
  for
    (program, values) in [
      (scalar, "{\"key\":7}"),
      (scalar, "{\"key\":null}"),
      (object, "{\"cfg\":{\"rank\":7}}"),
      (object, "{\"cfg\":{\"rank\":null}}"),
      (object, "{\"cfg\":null}"),
    ] {
    assert_true(
      @check.check_parsed(
        program,
        check_environment(),
        Some(aggregate_order_parameter_values(values)),
        check_limits(),
      )
      is Checked(_),
      msg="independent Program uses existing parameter, property and aggregate owners",
    )
  }
}

///|
test "aggregate parameter ORDER lowers the original scalar and object receiver" {
  let declarations = "{\"key\":{\"type\":\"number\",\"nullable\":true}}"
  let expected = aggregate_order_parameter_expected(
    declarations, "{\"$param\":\"key\"}",
  )
  for
    text in [
      "SELECT STRING_AGG(name, '|' ORDER BY @key DESC NULLS LAST, id) AS names FROM objects",
      "FROM objects |> AGGREGATE STRING_AGG(name, '|' ORDER BY (@`KEY`) DESC NULLS LAST, id) AS names",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..aggregate_property_order_context(),
        parameter_declarations: Some(
          parameter_reference_declarations(declarations),
        ),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
  let declarations = "{\"cfg\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"rank\":{\"type\":\"number\",\"nullable\":true}}}}"
  let expected = aggregate_order_parameter_expected(
    declarations, "{\"property\":{\"name\":\"rank\",\"value\":{\"$param\":\"cfg\"}}}",
  )
  for
    text in [
      "SELECT STRING_AGG(name, '|' ORDER BY @cfg.rank DESC NULLS LAST, id) AS names FROM objects",
      "FROM objects |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((@`CFG`)).`rank` DESC NULLS LAST, id) AS names",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..aggregate_property_order_context(),
        parameter_declarations: Some(
          parameter_reference_declarations(declarations),
        ),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}

///|
test "aggregate parameter order leaves invalid bindings and members to the common checker" {
  let declarations = "{\"key\":{\"type\":\"number\",\"nullable\":true},\"cfg\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"rank\":{\"type\":\"number\",\"nullable\":true}}}}"
  let context = {
    ..aggregate_property_order_context(),
    parameter_declarations: Some(parameter_reference_declarations(declarations)),
  }
  let source = fn(key : String) {
    "SELECT STRING_AGG(name, '|' ORDER BY " +
    key +
    ", id) AS names FROM objects"
  }
  for key in ["@absent", "@cfg.missing", "@key.rank", "@cfg"] {
    let actual = compile(
      @query.parse_query(source(key), syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(
          aggregate_order_parameter_values("{\"key\":7,\"cfg\":{\"rank\":7}}"),
        ),
        check_limits(),
      )
      is Rejected(_),
      msg=key,
    )
  }
  let actual = compile(
    @query.parse_query(source("@key"), syntax_limits()).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(
      actual,
      check_environment(),
      Some(aggregate_order_parameter_values("{\"cfg\":{\"rank\":7}}")),
      check_limits(),
    )
    is NeedsInputs(_),
  )
  assert_true(
    @check.check_parsed(
      actual,
      check_environment(),
      Some(
        aggregate_order_parameter_values(
          "{\"key\":\"private-value\",\"cfg\":{\"rank\":7}}",
        ),
      ),
      check_limits(),
    )
    is Rejected(_),
  )
}

///|
test "aggregate parameter order preserves DISTINCT scope and numeric ordinal refusals" {
  let context = {
    ..aggregate_property_order_context(),
    parameter_declarations: Some(
      parameter_reference_declarations("{\"key\":{\"type\":\"number\"}}"),
    ),
  }
  for
    text in [
      "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY @key) AS names FROM objects",
      "FROM objects |> AGGREGATE STRING_AGG(DISTINCT name, '|' ORDER BY @key) AS names",
      "SELECT STRING_AGG(name, '|' ORDER BY 1) AS names FROM objects", "SELECT STRING_AGG(name, '|' ORDER BY @key + 1) AS names FROM objects",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        context,
        construction_limits(),
      )
      is Err(UnsupportedAggregate),
      msg=text,
    )
  }
  let query = @query.parse_query(
    "SELECT STRING_AGG(name, '|' ORDER BY @key) AS names FROM objects",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(
      query,
      {
        ..context,
        parameter_declarations: Some(
          parameter_reference_declarations(
            "{\"key\":{\"type\":\"number\"},\"KEY\":{\"type\":\"number\"}}",
          ),
        ),
      },
      construction_limits(),
    )
    is Err(InvalidContext),
  )
  assert_true(
    compile(query, context, { ..construction_limits(), max_expression_work: 1, })
    is Err(Expression({ issue: WorkLimit, .. })),
  )
}

///|
test "aggregate parameter order preserves DISTINCT argument identity across parameter spelling" {
  let declarations = "{\"label\":{\"type\":\"string\",\"nullable\":true}}"
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"params\":" +
    declarations +
    ",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    (
      #|,{"from":"objects","derive":{"aql_aggregate_sort_5":{"$param":"label"}}},{"group":{"by":[],"aggregates":{"names":{"fn":"string_agg","expr":{"$param":"label"},"distinct":true,"max_bytes":10000,"order_by":[{"field":"aql_aggregate_sort_5","dir":"asc","nulls":"first"}],"delimiter":"|"}}}},{"select":["names"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["names"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for value in ["\"kept\"", "null"] {
    assert_true(
      @check.check_parsed(
        expected,
        check_environment(),
        Some(aggregate_order_parameter_values("{\"label\":" + value + "}")),
        check_limits(),
      )
      is Checked(_),
    )
  }
  for
    text in [
      "SELECT STRING_AGG(DISTINCT @label, '|' ORDER BY @LABEL) AS names FROM objects",
      "FROM objects |> AGGREGATE STRING_AGG(DISTINCT @`LABEL`, '|' ORDER BY (@label)) AS names",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..aggregate_property_order_context(),
        parameter_declarations: Some(
          parameter_reference_declarations(declarations),
        ),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}
