///|
fn identity_ready(
  declarations : String,
  supplied : String,
) -> @parameter_binding.BoundValues {
  let result = bind(declarations, supplied).unwrap()
  guard! result is @parameter_binding.Ready(values)
  values
}

///|
fn identity_text(
  values : @parameter_binding.BoundValues,
) -> String raise @encode.EncodeFailure {
  @parameter_binding.stringify_values(values, 8000000, 300000, 30000)
}

///|
fn identity_cid(
  values : @parameter_binding.BoundValues,
) -> String raise @encode.EncodeFailure {
  @parameter_binding.parameter_values_cid(values, 8000000, 300000, 30000)
}

///|
test "identity emits large text and wide collections without a projected tree" {
  let text = "é😀\"\\".repeat(100000)
  let supplied = "{\"x\":" + encode_json_string(text) + "}"
  let values = identity_ready("{\"x\":{\"type\":\"string\"}}", supplied)
  let rendered = identity_text(values)
  assert_eq(
    identity_cid(values),
    "sha256:" + @sha256.text_hex(rendered).unwrap(),
  )
  let wide = identity_ready(
    "{\"x\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"format\":\"duration\"}}}",
    "{\"x\":[" + Array::make(10000, "\"01S\"").join(",") + "]}",
  )
  assert_eq(
    identity_cid(wide),
    "sha256:" + @sha256.text_hex(identity_text(wide)).unwrap(),
  )
}

///|
fn encode_json_string(text : String) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(8000000, 1, 0)
  @encode.string_value(writer, text)
  @encode.finish(writer)
}

///|
test "read-only indexed access is bounded and detached arrays cannot mutate values" {
  let values = identity_ready(
    "{\"x\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}}", "{\"x\":[1,2]}",
  )
  let original = identity_cid(values)
  let bindings = @parameter_binding.bound_values(values)
  guard! bindings[0].value.value is @value.Array(items)
  assert_eq(@value.element_count(items), 2)
  assert_true(@value.element_at(items, -1) is None)
  assert_true(@value.element_at(items, 2) is None)
  let copy = @value.elements(items)
  copy.clear()
  assert_eq(@value.element_count(items), 2)
  assert_eq(identity_cid(values), original)
  let syntax = @contract.read_parameter_syntax(
    cursor(
      "{\"type\":\"object\",\"fields\":{\"b\":{\"type\":\"number\"},\"a\":{\"type\":\"string\"}}}",
    ),
    { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  guard! syntax.parameter_type.rule is @contract.Properties(fields)
  assert_eq(@contract.parameter_field_at(fields, 0).unwrap().0, "a")
  assert_true(@contract.parameter_field_at(fields, -1) is None)
  assert_true(@contract.parameter_field_at(fields, 2) is None)
}

///|
test "identity keeps ordinary values and excludes constraints metadata and origin" {
  let plain = identity_ready("{\"n\":{\"type\":\"number\"}}", "{\"n\":2}")
  let bounded = identity_ready(
    "{\"n\":{\"type\":\"number\",\"integer\":true,\"minimum\":1,\"maximum\":5,\"nullable\":true,\"default\":2,\"meta\":{\"purpose\":\"note\"}}}",
    "{}",
  )
  let expected = "{\"values\":{\"n\":2},\"version\":\"actql-parameter-values/0.1\"}"
  assert_eq(identity_text(plain), expected)
  assert_eq(identity_cid(plain), identity_cid(bounded))
  assert_eq(
    identity_cid(plain),
    "sha256:" + @sha256.text_hex(expected).unwrap(),
  )
  for kind in ["string", "number", "date", "timestamp"] {
    let null_value = identity_ready(
      "{\"n\":{\"type\":\"" + kind + "\",\"nullable\":true}}",
      "{\"n\":null}",
    )
    assert_eq(
      identity_text(null_value),
      "{\"values\":{\"n\":null},\"version\":\"actql-parameter-values/0.1\"}",
    )
  }
}

///|
test "duration projection is recursive exact and different from ordinary text and numbers" {
  let declaration = "{\"t\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"1s\"}}"
  let baseline = identity_ready(declaration, "{}")
  for text in ["1s", "1S", "01s", "1000ms", "01000MS"] {
    let supplied = identity_ready(declaration, "{\"t\":\"" + text + "\"}")
    assert_eq(identity_cid(supplied), identity_cid(baseline))
  }
  assert_eq(
    identity_text(baseline),
    "{\"values\":{\"t\":{\"$actql_value\":[\"duration\",1000]}},\"version\":\"actql-parameter-values/0.1\"}",
  )
  assert_not_eq(
    identity_cid(baseline),
    identity_cid(identity_ready(declaration, "{\"t\":\"1001ms\"}")),
  )
  assert_not_eq(
    identity_cid(baseline),
    identity_cid(
      identity_ready("{\"t\":{\"type\":\"string\"}}", "{\"t\":\"1s\"}"),
    ),
  )
  assert_not_eq(
    identity_cid(baseline),
    identity_cid(
      identity_ready("{\"t\":{\"type\":\"number\"}}", "{\"t\":1000}"),
    ),
  )
  let nested = "{\"x\":{\"type\":\"object\",\"fields\":{\"a\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"format\":\"duration\",\"nullable\":true}}}}}"
  assert_eq(
    identity_cid(identity_ready(nested, "{\"x\":{\"a\":[\"1S\",null]}}")),
    identity_cid(identity_ready(nested, "{\"x\":{\"a\":[\"1000ms\",null]}}")),
  )
  let max = identity_ready(declaration, "{\"t\":\"9007199254740991ms\"}")
  assert_true(identity_text(max).contains("9007199254740991"))
}

///|
test "decimal projection binds version precision scale and exact coefficient" {
  let d = "{\"d\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2}}"
  let value = identity_ready(d, "{\"d\":\"19.90\"}")
  assert_eq(
    identity_text(value),
    "{\"values\":{\"d\":{\"$actql_value\":[\"decimal\",{\"coefficient\":\"1990\",\"precision\":4,\"scale\":2,\"version\":\"aoa-decimal-value/0.1\"}]}},\"version\":\"actql-parameter-values/0.1\"}",
  )
  let more_precision = identity_ready(
    "{\"d\":{\"type\":\"decimal\",\"precision\":5,\"scale\":2}}", "{\"d\":\"19.90\"}",
  )
  let more_scale = identity_ready(
    "{\"d\":{\"type\":\"decimal\",\"precision\":5,\"scale\":3}}", "{\"d\":\"19.900\"}",
  )
  assert_not_eq(identity_cid(value), identity_cid(more_precision))
  assert_not_eq(identity_cid(value), identity_cid(more_scale))
  assert_not_eq(
    identity_cid(value),
    identity_cid(
      identity_ready("{\"d\":{\"type\":\"string\"}}", "{\"d\":\"19.90\"}"),
    ),
  )
}

///|
test "reserved marker is escaped as ordinary object data and cannot impersonate a tag" {
  // A two-string business array can exactly mimic the special object tag prefix.
  let d = "{\"x\":{\"type\":\"object\",\"fields\":{\"$actql_value\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"other\":{\"type\":\"number\"}}}}"
  let v = identity_ready(
    d, "{\"x\":{\"other\":123,\"$actql_value\":[\"duration\",\"1000\"]}}",
  )
  assert_eq(
    identity_text(v),
    "{\"values\":{\"x\":{\"$actql_value\":[\"object\",[[\"$actql_value\",[\"duration\",\"1000\"]],[\"other\",123]]]}},\"version\":\"actql-parameter-values/0.1\"}",
  )
  let nested = "{\"x\":{\"type\":\"object\",\"fields\":{\"$actql_value\":{\"type\":\"object\",\"fields\":{\"$actql_value\":{\"type\":\"string\",\"format\":\"duration\"}}}}}}"
  let a = identity_ready(
    nested, "{\"x\":{\"$actql_value\":{\"$actql_value\":\"1S\"}}}",
  )
  let b = identity_ready(
    nested, "{\"x\":{\"$actql_value\":{\"$actql_value\":\"1000ms\"}}}",
  )
  assert_eq(identity_cid(a), identity_cid(b))
  assert_true(
    identity_text(a).contains(
      "[\"object\",[[\"$actql_value\",{\"$actql_value\":[\"object\"",
    ),
  )
}

///|
test "identity output budgets include envelope tags and escaped key pairs" {
  let fixtures = [
    identity_ready(
      "{\"x\":{\"type\":\"string\",\"format\":\"duration\"}}", "{\"x\":\"1s\"}",
    ),
    identity_ready(
      "{\"x\":{\"type\":\"object\",\"fields\":{\"$actql_value\":{\"type\":\"string\"}}}}",
      "{\"x\":{\"$actql_value\":\"é😀\"}}",
    ),
  ]
  for fixture in fixtures {
    let rendered = identity_text(fixture)
    let size = @scalar.admit_utf8_length(rendered, 10000).unwrap()
    assert_eq(@parameter_binding.measure_values(fixture, size, 100, 100), size)
    for bytes in [size - 1, size, size + 1] {
      for nodes = 0; nodes <= 15; nodes = nodes + 1 {
        for depth = 0; depth <= 8; depth = depth + 1 {
          let text = Some(
            @parameter_binding.stringify_values(fixture, bytes, nodes, depth),
          ) catch {
            _ => None
          }
          let hash = Some(
            @parameter_binding.parameter_values_cid(
              fixture, bytes, nodes, depth,
            ),
          ) catch {
            _ => None
          }
          let measured = Some(
            @parameter_binding.measure_values(fixture, bytes, nodes, depth),
          ) catch {
            _ => None
          }
          match text {
            Some(text) => {
              assert_eq(hash, Some("sha256:" + @sha256.text_hex(text).unwrap()))
              assert_eq(measured, Some(size))
            }
            None => {
              assert_eq(hash, None)
              assert_eq(measured, None)
            }
          }
        }
      }
    }
    let out = @encode.hashing_writer(size - 1, 100, 100)
    assert_true(
      try {
        @parameter_binding.emit_values(fixture, out)
        false
      } catch {
        @encode.OutputLimit => true
        _ => false
      },
    )
    assert_true(
      try {
        ignore(@encode.finish_hash(out))
        false
      } catch {
        @encode.ClosedWriter => true
        _ => false
      },
    )
  }
  let empty = @parameter_binding.bind(
    @parameter_binding.read_declarations(None, limits()).unwrap(),
    None,
    values_limit(),
  ).unwrap()
  guard! empty is @parameter_binding.Ready(values)
  let expected = "{\"values\":{},\"version\":\"actql-parameter-values/0.1\"}"
  assert_eq(
    @parameter_binding.stringify_values(values, expected.length(), 3, 2),
    expected,
  )
  for
    (bytes, nodes, depth) in [
      (-1, 3, 2),
      (100, -1, 2),
      (100, 3, -1),
      (100, 2, 2),
      (100, 3, 1),
    ] {
    assert_true(
      try {
        ignore(
          @parameter_binding.parameter_values_cid(values, bytes, nodes, depth),
        )
        false
      } catch {
        @encode.OutputLimit => true
        _ => false
      },
    )
  }
}

///|
test "identity traversal is nonrecursive and detached public views cannot replace trusted types" {
  let depth = 3000
  let declaration = "{\"x\":" +
    "{\"type\":\"array\",\"items\":".repeat(depth) +
    "{\"type\":\"string\",\"format\":\"duration\"}" +
    "}".repeat(depth) +
    "}"
  let supplied = "{\"x\":" +
    "[".repeat(depth) +
    "\"01S\"" +
    "]".repeat(depth) +
    "}"
  let values = identity_ready(declaration, supplied)
  let expected = "{\"values\":{\"x\":" +
    "[".repeat(depth) +
    "{\"$actql_value\":[\"duration\",1000]}" +
    "]".repeat(depth) +
    "},\"version\":\"actql-parameter-values/0.1\"}"
  assert_eq(identity_text(values), expected)
  let copy = @parameter_binding.bound_values(values)
  copy.clear()
  assert_eq(
    identity_cid(values),
    "sha256:" + @sha256.text_hex(expected).unwrap(),
  )
}
