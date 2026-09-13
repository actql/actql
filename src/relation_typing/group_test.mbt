///|
fn aggregate_checked(call : String) -> @relation_typing.CheckedOperation raise {
  checked(Group, "{\"by\":[],\"aggregates\":{\"v\":" + call + "}}")
}

///|
fn aggregate_reject(call : String) -> Unit raise {
  assert_true(
    check_row(
      Group,
      cursor("{\"by\":[],\"aggregates\":{\"v\":" + call + "}}"),
      input(),
      None,
      limits(),
    )
    is Err(_),
  )
}

///|
test "aggregate numeric parameters remain symbolic and carry bound obligations" {
  let params = @parameter.read_declarations(
    Some(
      cursor(
        "{\"n\":{\"type\":\"number\",\"nullable\":true},\"s\":{\"type\":\"string\"}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let body = cursor(
    "{\"by\":[],\"aggregates\":{\"a\":{\"fn\":\"array_agg\",\"field\":\"id\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":{\"$param\":\"n\"}},\"p\":{\"fn\":\"percentile_disc\",\"field\":\"amount\",\"fraction\":{\"$param\":\"n\"}}}}",
  )
  let value = check_row(Group, body, input(), Some(params), limits()).unwrap()
  let g = @relation_typing.group(value).unwrap()
  assert_eq(
    @relation_typing.aggregate_item_limit(
      @relation_typing.aggregate_at(g, 0).unwrap(),
    ),
    Some(Parameter("n")),
  )
  assert_eq(
    @relation_typing.aggregate_fraction(
      @relation_typing.aggregate_at(g, 1).unwrap(),
    ),
    Some(ParameterFraction("n")),
  )
  let pending = indexed_obligation_copy(
    @relation_typing.pending_validations(value),
    @relation_typing.pending_validation_count(value),
    i => @relation_typing.pending_validation_at(value, i),
    (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
  )
  assert_true(pending.any(p => p.kind is BoundInteger(name="n", minimum=1L)))
  assert_true(pending.any(p => p.kind is BoundFraction("n")))
  for i in 0..<pending.length() {
    let owner = @relation_typing.aggregate_for_validation(g, i)
    match pending[i].kind {
      GroupPartitioning => assert_true(owner is None)
      BoundInteger(..) =>
        assert_eq(@relation_typing.aggregate_name(owner.unwrap()), "a")
      BoundFraction(_) =>
        assert_eq(@relation_typing.aggregate_name(owner.unwrap()), "p")
      _ => assert_true(owner is Some(_))
    }
  }
  for
    option in [
      "{\"$param\":\"s\"}", "{\"$param\":\"unknown\"}", "\"n\"", "{\"add\":[1,2]}",
      "null",
    ] {
    assert_true(
      check_row(
        Group,
        cursor(
          "{\"by\":[],\"aggregates\":{\"p\":{\"fn\":\"percentile_disc\",\"field\":\"amount\",\"fraction\":" +
          option +
          "}}}",
        ),
        input(),
        Some(params),
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "aggregate validation owners retain exact checked calls in canonical name order" {
  let operation = checked(
    Group,
    "{\"by\":[\"id\"],\"aggregates\":{\"z\":{\"fn\":\"sum\",\"field\":\"amount\"},\"a\":{\"fn\":\"count\"}}}",
  )
  let group = @relation_typing.group(operation).unwrap()
  let count = @relation_typing.pending_validation_count(operation)
  let mut aggregate_owned = 0
  for i in 0..<count {
    let pending = @relation_typing.pending_validation_at(operation, i).unwrap()
    match pending.kind {
      GroupPartitioning =>
        assert_true(@relation_typing.aggregate_for_validation(group, i) is None)
      _ => {
        let owner = @relation_typing.aggregate_for_validation(group, i).unwrap()
        let ordinal = if @relation_typing.aggregate_name(owner) == "a" {
          0
        } else {
          1
        }
        assert_true(
          physical_equal(
            owner,
            @relation_typing.aggregate_at(group, ordinal).unwrap(),
          ),
        )
        assert_true(
          physical_equal(
            pending.source,
            @relation_typing.aggregate_source(owner),
          ),
        )
        aggregate_owned += 1
      }
    }
  }
  assert_eq(aggregate_owned, count - 1)
  assert_true(@relation_typing.aggregate_for_validation(group, -1) is None)
  assert_true(@relation_typing.aggregate_for_validation(group, count) is None)
  let empty = @relation_typing.group(
    checked(Group, "{\"by\":[],\"aggregates\":{}}"),
  ).unwrap()
  assert_true(@relation_typing.aggregate_for_validation(empty, 0) is None)
}

///|
test "group accepts empty aggregates and retains repeated grouping occurrences" {
  for
    body in [
      "{\"by\":[],\"aggregates\":{}}", "{\"by\":[\"id\",\"id\"],\"aggregates\":{}}",
    ] {
    let value = checked(Group, body)
    let details = @relation_typing.group(value).unwrap()
    assert_eq(@relation_typing.aggregate_count(details), 0)
    let keys = @relation_typing.group_keys(details)
    assert_eq(keys.length(), if body.contains("id") { 2 } else { 0 })
    keys.clear()
    assert_eq(
      @relation_typing.group_keys(details).length(),
      if body.contains("id") {
        2
      } else {
        0
      },
    )
    assert_eq(
      @schema.field_count(@relation_typing.output_schema(value)),
      if body.contains("id") {
        1
      } else {
        0
      },
    )
  }
  let empty = check_row(
    Group,
    cursor("{\"by\":[],\"aggregates\":{}}"),
    schema("{}"),
    None,
    limits(),
  ).unwrap()
  assert_eq(@schema.field_count(@relation_typing.output_schema(empty)), 0)
  rejected(
    Group,
    "{\"by\":[\"id\"],\"aggregates\":{\"id\":{\"fn\":\"count\"}}}",
    DuplicateOutput("id"),
  )
  rejected(
    Group,
    "{\"by\":[\"missing\"],\"aggregates\":{}}",
    UnknownField("missing"),
  )
}

///|
test "all aggregate signatures have fixed result domains and nullability" {
  for
    name in [
      "count", "sum", "avg", "min", "max", "percentile_disc", "percentile_cont",
      "var_pop", "var_samp", "stddev_pop", "stddev_samp",
    ] {
    let extra = if name.has_prefix("percentile") {
      ",\"fraction\":0.5"
    } else {
      ""
    }
    let v = aggregate_checked(
      "{\"fn\":\"" + name + "\",\"field\":\"amount\"" + extra + "}",
    )
    let c = field(output_row(v), "v")
    assert_true(c.shape is @contract.Number)
    assert_eq(c.nullable, name != "count")
  }
  let count_if = aggregate_checked("{\"fn\":\"count_if\",\"field\":\"flag\"}")
  assert_true(!field(output_row(count_if), "v").nullable)
  for name in ["first", "last", "array_agg", "string_agg"] {
    let extra = if name == "string_agg" { ",\"delimiter\":\",\"" } else { "" }
    let v = aggregate_checked(
      "{\"fn\":\"" +
      name +
      "\",\"field\":\"id\",\"order_by\":[{\"id\":\"asc\"}]" +
      extra +
      "}",
    )
    let c = field(output_row(v), "v")
    if name == "array_agg" {
      match c.shape {
        @contract.Array(item, max_items~) => {
          assert_true(!c.nullable && !item.nullable)
          assert_true(item.shape is @contract.Text(_))
          assert_eq(max_items, None)
        }
        _ => fail("expected array")
      }
    } else {
      assert_true(c.nullable && c.shape is @contract.Text(_))
    }
  }
}

///|
test "aggregate fixed signatures do not repair overloaded NULL arguments" {
  for name in ["avg", "count_if", "string_agg", "percentile_cont", "var_pop"] {
    let extra = if name == "string_agg" {
      ",\"delimiter\":\"\",\"order_by\":[{\"id\":\"asc\"}]"
    } else if name == "percentile_cont" {
      ",\"fraction\":0"
    } else {
      ""
    }
    ignore(
      aggregate_checked(
        "{\"fn\":\"" + name + "\",\"expr\":\"NULL\"" + extra + "}",
      ),
    )
  }
  for name in ["count", "sum", "min", "max"] {
    aggregate_reject("{\"fn\":\"" + name + "\",\"expr\":\"NULL\"}")
  }
  aggregate_reject("{\"fn\":\"avg\",\"expr\":\"coalesce(NULL,NULL)\"}")
  aggregate_reject("{\"fn\":\"sum\",\"field\":\"id\"}")
  aggregate_reject("{\"fn\":\"avg\",\"field\":\"flag\"}")
}

///|
test "aggregate modifiers are closed and preserve explicit false" {
  for
    call in [
      "\"sum\"", "{\"op\":\"count\"}", "{\"sum\":\"amount\"}", "{\"fn\":\"count_if\",\"where\":\"flag\"}",
      "{\"fn\":\"sum\"}", "{\"fn\":\"count\",\"field\":\"id\",\"expr\":\"id\"}",
      "{\"fn\":\"count\",\"distinct\":true}", "{\"fn\":\"min\",\"field\":\"id\",\"distinct\":true}",
      "{\"fn\":\"count_if\",\"field\":\"flag\",\"distinct\":false}", "{\"fn\":\"var_pop\",\"field\":\"amount\",\"distinct\":false}",
      "{\"fn\":\"sum\",\"field\":\"amount\",\"order_by\":[{\"id\":\"asc\"}]}", "{\"fn\":\"array_agg\",\"field\":\"id\",\"order_by\":[]}",
      "{\"fn\":\"percentile_cont\",\"field\":\"amount\",\"fraction\":1.1}", "{\"fn\":\"first\",\"field\":\"id\"}",
      "{\"fn\":\"count\",\"max_items\":1}",
    ] {
    aggregate_reject(call)
  }
  for
    call in [
      "{\"fn\":\"count\",\"distinct\":false}", "{\"fn\":\"min\",\"field\":\"id\",\"distinct\":false}",
      "{\"fn\":\"max\",\"field\":\"id\",\"distinct\":false}",
    ] {
    let v = aggregate_checked(call)
    let a = @relation_typing.aggregate_at(@relation_typing.group(v).unwrap(), 0).unwrap()
    assert_eq(@relation_typing.aggregate_distinct(a), Some(false))
  }
}

///|
test "aggregate filters and independently ordered arguments retain separate bindings" {
  let v = checked(
    Group,
    "{\"by\":[],\"aggregates\":{\"z\":{\"fn\":\"array_agg\",\"expr\":\"id\",\"filter\":\"flag\",\"order_by\":[{\"id\":\"desc\"}]},\"a\":{\"fn\":\"array_agg\",\"expr\":\"id\",\"filter\":\"flag\",\"order_by\":[{\"id\":\"asc\"}]}}}",
  )
  let g = @relation_typing.group(v).unwrap()
  assert_eq(@relation_typing.binding_count(v), 4)
  for i in 0..<2 {
    let a = @relation_typing.aggregate_at(g, i).unwrap()
    assert_eq(
      @relation_typing.aggregate_name(a),
      if i == 0 {
        "a"
      } else {
        "z"
      },
    )
    assert_eq(@relation_typing.aggregate_filter(a), Some(i * 2))
    assert_true(@relation_typing.aggregate_argument(a) is Expression(_))
    let order = @relation_typing.aggregate_order(a)
    order.clear()
    assert_eq(@relation_typing.aggregate_order(a).length(), 1)
  }
  aggregate_reject("{\"fn\":\"sum\",\"expr\":\"missing\",\"filter\":\"FALSE\"}")
}

///|
test "decimal sum retains scale and selected references are not constructed arrays" {
  let row = schema(
    "{\"d\":{\"type\":\"decimal\",\"precision\":5,\"scale\":2,\"nullable\":false},\"r\":{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false},\"j\":{\"type\":\"json\",\"nullable\":false}}",
  )
  let sum = check_row(
    Group,
    cursor(
      "{\"by\":[],\"aggregates\":{\"v\":{\"fn\":\"sum\",\"field\":\"d\"}}}",
    ),
    row,
    None,
    limits(),
  ).unwrap()
  assert_true(
    field(output_row(sum), "v").shape
    is @contract.Decimal(precision=38, scale=2),
  )
  for name in ["r", "j"] {
    for fn_name in ["first", "last", "array_agg"] {
      let result = check_row(
        Group,
        cursor(
          "{\"by\":[],\"aggregates\":{\"v\":{\"fn\":\"" +
          fn_name +
          "\",\"field\":\"" +
          name +
          "\",\"order_by\":[{\"id\":\"asc\"}]}}}",
        ),
        row,
        None,
        limits(),
      )
      if fn_name == "array_agg" {
        assert_true(result is Err({ kind: ForbiddenAggregateValue, .. }))
      } else {
        assert_true(result is Ok(_))
      }
    }
  }
  assert_true(
    check_row(
      Group,
      cursor(
        "{\"by\":[],\"aggregates\":{\"v\":{\"fn\":\"avg\",\"field\":\"d\"}}}",
      ),
      row,
      None,
      limits(),
    )
    is Err(_),
  )
}

///|
test "aggregate shared budgets reject at exact work and node boundaries" {
  let body = cursor(
    "{\"by\":[],\"aggregates\":{\"a\":{\"fn\":\"sum\",\"expr\":\"amount+1\"},\"b\":{\"fn\":\"avg\",\"expr\":\"amount+1\"}}}",
  )
  let v = check_row(Group, body, input(), None, limits()).unwrap()
  let tight = {
    ..limits(),
    max_work: @relation_typing.work_used(v),
    max_nodes: @relation_typing.nodes_used(v),
    max_text_bytes: @relation_typing.text_bytes_used(v),
    max_tokens: @relation_typing.tokens_used(v),
  }
  assert_true(check_row(Group, body, input(), None, tight) is Ok(_))
  for
    l in [
      { ..tight, max_work: tight.max_work - 1, },
      { ..tight, max_nodes: tight.max_nodes - 1, },
      { ..tight, max_text_bytes: tight.max_text_bytes - 1, },
      { ..tight, max_tokens: tight.max_tokens - 1, },
    ] {
    assert_true(check_row(Group, body, input(), None, l) is Err(_))
  }
}
