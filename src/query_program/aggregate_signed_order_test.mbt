///|
fn aggregate_signed_order_expected(positive : Bool) -> @program.Program {
  let receiver = "{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}"
  let key = if positive {
    "{\"negate\":{\"negate\":" + receiver + "}}"
  } else {
    "{\"negate\":" + receiver + "}"
  }
  aggregate_signed_order_key_expected(key, "")
}

///|
fn aggregate_signed_order_key_expected(
  key : String,
  declarations : String,
) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\"," +
    declarations +
    "\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    ", {\"from\":\"objects\",\"derive\":{\"aql_aggregate_sort_5\":" +
    key +
    "}},{\"group\":{\"by\":[],\"aggregates\":{\"names\":{\"fn\":\"string_agg\",\"field\":\"name\",\"max_bytes\":10000,\"order_by\":[{\"field\":\"aql_aggregate_sort_5\",\"dir\":\"asc\",\"nulls\":\"last\"},{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"delimiter\":\"|\"}}}},{\"select\":[\"names\"],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"names\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "signed direct and nested keys preserve complete ordinary expressions" {
  for
    (key, expression) in [
      ("-id", "{\"negate\":{\"field\":\"id\"}}"),
      ("+objects.id", "{\"negate\":{\"negate\":{\"field\":\"id\"}}}"),
      (
        "-(-payload.score)", "{\"negate\":{\"negate\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}}}",
      ),
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY " +
        key +
        " NULLS LAST, id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(
      semantic(actual),
      semantic(aggregate_signed_order_key_expected(expression, "")),
    )
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "signed parameter key preserves admitted NULL and typed parameter identity" {
  let declarations = "{\"key\":{\"type\":\"number\",\"nullable\":true}}"
  let actual = compile(
    @query.parse_query(
      "FROM objects |> AGGREGATE STRING_AGG(name, '|' ORDER BY -@KEY NULLS LAST, id) AS names",
      syntax_limits(),
    ).unwrap(),
    {
      ..aggregate_property_order_context(),
      parameter_declarations: Some(
        parameter_reference_declarations(declarations),
      ),
    },
    construction_limits(),
  ).unwrap()
  assert_eq(
    semantic(actual),
    semantic(
      aggregate_signed_order_key_expected(
        "{\"negate\":{\"$param\":\"key\"}}",
        "\"params\":" + declarations + ",",
      ),
    ),
  )
  for values in ["{\"key\":7}", "{\"key\":null}"] {
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(aggregate_order_parameter_values(values)),
        check_limits(),
      )
      is Checked(_),
    )
  }
}

///|
test "signed keys leave invalid operand contracts to the ordinary checker" {
  for key in ["-name", "+payload", "-payload.missing"] {
    let actual = compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY " +
        key +
        ", id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(_),
      msg=key,
    )
  }
}

///|
test "signed aggregate keys preserve unavailable scope and demand restrictions" {
  assert_true(
    compile(
      @query.parse_query(
        "FROM objects AS old |> AS `current` |> AGGREGATE STRING_AGG(name, '|' ORDER BY -old.payload.score, id) AS names",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  for key in ["-(id + 1)", "-1", "-(id / (id - id))"] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT STRING_AGG(name, '|' WHERE FALSE ORDER BY " +
          key +
          ") AS names FROM objects",
          syntax_limits(),
        ).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedAggregate),
      msg=key,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY -id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedAggregate),
  )
}

///|
test "signed aggregate keys have independent checked ordinary Programs" {
  for positive in [false, true] {
    assert_true(
      @check.check_parsed(
        aggregate_signed_order_expected(positive),
        check_environment(),
        None,
        check_limits(),
      )
      is Checked(_),
    )
  }
}

///|
test "signed aggregate source preserves the operand and requested order" {
  for (sign, positive) in [("-", false), ("+", true)] {
    for
      source in [
        "SELECT STRING_AGG(name, '|' ORDER BY " +
        sign +
        "payload.score NULLS LAST, id) AS names FROM objects",
        "FROM objects |> AGGREGATE STRING_AGG(name, '|' ORDER BY " +
        sign +
        "((objects.payload).score) NULLS LAST, id) AS names",
      ] {
      let actual = compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      ).unwrap()
      assert_eq(
        semantic(actual),
        semantic(aggregate_signed_order_expected(positive)),
      )
    }
  }
}
