///|
// These are the public Slack predicate's original logical contracts. The
// literal is authored numeric syntax, never a re-labelled Text/Decimal value.
test "public Slack reply-count predicate admits its exact integer zero" {
  assert_type(
    "{\"and\":[{\"is_null\":{\"field\":\"thread_ts\"}},{\"eq\":[{\"field\":\"reply_count\"},{\"literal\":0}]}]}",
    "{\"thread_ts\":{\"type\":\"string\",\"nullable\":true},\"reply_count\":{\"type\":\"int64\",\"nullable\":true}}",
    "null", "{\"type\":\"boolean\",\"nullable\":true}",
  )
}

///|
test "existing int64 contracts use their exact author-orderable comparison" {
  assert_type(
    "{\"lt\":[{\"field\":\"a\"},{\"field\":\"b\"}]}", "{\"a\":{\"type\":\"int64\",\"nullable\":false},\"b\":{\"type\":\"int64\",\"nullable\":false}}",
    "null", "{\"type\":\"boolean\",\"nullable\":false}",
  )
}

///|
fn int64_fields() -> String {
  "{\"i\":{\"type\":\"int64\",\"nullable\":false},\"n\":{\"type\":\"number\",\"nullable\":false},\"xs\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"int64\",\"nullable\":true}}}"
}

///|
test "int64 comparison context is independent of operand order and predicate family" {
  for tag in ["eq", "neq", "lt", "lte", "gt", "gte", "is_distinct_from"] {
    for
      pair in [
        "{\"field\":\"i\"},{\"literal\":0}", "{\"literal\":0},{\"field\":\"i\"}",
      ] {
      assert_type(
        "{\"" + tag + "\":[" + pair + "]}",
        int64_fields(),
        "null",
        "{\"type\":\"boolean\",\"nullable\":false}",
      )
    }
  }
  for
    args in [
      "{\"field\":\"i\"},{\"literal\":-1},{\"literal\":1}", "{\"literal\":0},{\"field\":\"i\"},{\"literal\":1}",
      "{\"literal\":0},{\"literal\":-1},{\"field\":\"i\"}",
    ] {
    assert_type(
      "{\"between\":[" + args + "]}",
      int64_fields(),
      "null",
      "{\"type\":\"boolean\",\"nullable\":false}",
    )
  }
}

///|
test "int64 comparison literals use the admitted Number value and exclusive upper bound" {
  for
    literal in [
      "-9223372036854775808", "9223372036854774784", "9007199254740992", "9007199254740993",
      "1e3",
    ] {
    assert_type(
      "{\"eq\":[{\"field\":\"i\"},{\"literal\":" + literal + "}]}",
      int64_fields(),
      "null",
      "{\"type\":\"boolean\",\"nullable\":false}",
    )
  }
  for
    literal in [
      "9223372036854775808", "9223372036854775807", "-9223372036854777856", "0.5",
      "1e100",
    ] {
    assert_rejected(
      "{\"eq\":[{\"literal\":" + literal + "},{\"field\":\"i\"}]}",
      int64_fields(),
      "null",
      "TypeMismatch",
    )
  }
}

///|
test "membership int64 context covers original arrays and immediate lists with Parameters" {
  for tag in ["in", "not_in"] {
    for
      expression in [
        "{\"field\":\"i\"},{\"literal\":[0,1,null]}", "{\"literal\":0},{\"field\":\"xs\"}",
        "{\"literal\":0},{\"literal\":[{\"$param\":\"p\"},1,null]}",
      ] {
      assert_type(
        "{\"" + tag + "\":[" + expression + "]}",
        int64_fields(),
        "{\"p\":{\"type\":\"int64\",\"nullable\":false}}",
        "{\"type\":\"boolean\",\"nullable\":true}",
      )
    }
    assert_type(
      "{\"" + tag + "\":[{\"field\":\"i\"},{\"literal\":[]}]}",
      int64_fields(),
      "null",
      "{\"type\":\"boolean\",\"nullable\":false}",
    )
    assert_rejected(
      "{\"" + tag + "\":[{\"field\":\"i\"},{\"literal\":[0,0.5]}]}",
      int64_fields(),
      "null",
      "TypeMismatch",
    )
  }
}

///|
test "comparison context never promotes nonliteral or conflicting Number domains" {
  for
    other in [
      "{\"field\":\"n\"}", "{\"$param\":\"p\"}", "{\"add\":[{\"literal\":0},{\"literal\":0}]}",
      "{\"literal\":\"0\"}",
    ] {
    assert_rejected(
      "{\"eq\":[{\"field\":\"i\"}," + other + "]}",
      int64_fields(),
      "{\"p\":{\"type\":\"number\",\"nullable\":false}}",
      "TypeMismatch",
    )
  }
  assert_rejected(
    "{\"between\":[{\"field\":\"i\"},{\"literal\":0},{\"field\":\"n\"}]}",
    int64_fields(),
    "null",
    "TypeMismatch",
  )
  assert_rejected(
    "{\"add\":[{\"field\":\"i\"},{\"literal\":0}]}",
    int64_fields(),
    "null",
    "TypeMismatch",
  )
  assert_rejected(
    "{\"nullif\":[{\"field\":\"i\"},{\"literal\":0}]}",
    int64_fields(),
    "null",
    "TypeMismatch",
  )
}

///|
test "comparison NULL annotations and ordinary Number literal identity stay unchanged" {
  assert_type(
    "{\"eq\":[{\"field\":\"i\"},{\"literal\":0}]}", "{\"i\":{\"type\":\"int64\",\"nullable\":true}}",
    "null", "{\"type\":\"boolean\",\"nullable\":true}",
  )
  // The independently typed peer supplies literal NULL's comparable domain.
  assert_type(
    "{\"eq\":[{\"field\":\"i\"},{\"literal\":null}]}",
    int64_fields(),
    "null",
    "{\"type\":\"boolean\",\"nullable\":true}",
  )
  assert_rejected(
    "{\"eq\":[{\"literal\":null},{\"literal\":null}]}",
    int64_fields(),
    "null",
    "NullTypeUnresolved",
  )
  // Negative zero never supplies an admitted Number value in the first place.
  assert_true(
    @source.parse_json("{\"literal\":-0}", {
      max_input_bytes: 100,
      max_nodes: 10,
      max_depth: 10,
    })
    is Err(_),
  )
  assert_type(
    "{\"is_distinct_from\":[{\"literal\":null},{\"field\":\"i\"}]}",
    int64_fields(),
    "null",
    "{\"type\":\"boolean\",\"nullable\":false}",
  )
  let source = syntax(
    "{\"eq\":[{\"literal\":9007199254740993},{\"field\":\"i\"}]}",
  )
  let before_writer = @encode.writer(10000, 1000, 100)
  @syntax.emit_source(source, before_writer)
  let before = @encode.finish(before_writer)
  let typed = @expression_typing.check(
    source,
    env(fields=int64_fields()),
    test_limits(),
  ).unwrap()
  let after_writer = @encode.writer(10000, 1000, 100)
  @syntax.emit_source(@expression_typing.expression(typed), after_writer)
  assert_eq(@encode.finish(after_writer), before)
  assert_eq(
    before, "{\"eq\":[{\"literal\":9007199254740992},{\"field\":\"i\"}]}",
  )
  let cold = @expression_typing.check(
    syntax(before),
    env(fields=int64_fields()),
    test_limits(),
  ).unwrap()
  assert_true(
    @contract.type_equal(
      @expression_typing.node_at(typed, 1).unwrap().contract,
      @expression_typing.node_at(cold, 1).unwrap().contract,
      100,
    ),
  )
  assert_type(
    "{\"eq\":[{\"literal\":0},{\"field\":\"n\"}]}",
    int64_fields(),
    "null",
    "{\"type\":\"boolean\",\"nullable\":false}",
  )
}
