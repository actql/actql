///|
test "raw cursor admission does not repair noncanonical contract strings" {
  let parsed = @source.parse_json(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"ok\"}",
    { max_input_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  match parsed.value {
    Object(entries) => {
      let index = entries.length() - 1
      let field = entries[index]
      entries[index] = {
        key: field.key,
        key_span: field.key_span,
        value: { value: @source.String("e\u0301"), span: field.value.span, },
      }
      let raw = @decode.admit(parsed, {
        max_nodes: 100,
        max_depth: 10,
        max_string_bytes: 1000,
        max_total_string_bytes: 1000,
      }).unwrap()
      assert_eq(
        error_name(@value_contract.read_author(raw, limits())),
        "NonCanonicalText",
      )
      assert_eq(
        error_name(@value_contract.read_checked(raw, limits())),
        "NonCanonicalText",
      )
    }
    _ => assert_true(false)
  }
}

///|
test "invalid field diagnostics identify the key rather than its value" {
  let c = cursor(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"a.b\":{\"type\":\"number\",\"nullable\":false}}}",
  )
  match @value_contract.read_author(c, limits()) {
    Err(ContractIssue(InvalidFieldName("a.b"), path~, span~)) => {
      assert_eq(path, [@source.Key("fields"), @source.Key("a.b")])
      assert_eq(span.end_byte - span.start_byte, 5)
    }
    _ => assert_true(false)
  }
}

///|
test "checked emission shares exact writer budgets and supports embedding" {
  let value = author("{\"type\":\"number\",\"nullable\":false}")
  let output = render(value)
  let size = output.length()
  assert_eq(@value_contract.stringify_checked(value, size, 3, 1), output)
  for (bytes, nodes, depth) in [(size - 1, 3, 1), (size, 2, 1), (size, 3, 0)] {
    assert_true(
      try {
        ignore(@value_contract.stringify_checked(value, bytes, nodes, depth))
        false
      } catch {
        @encode.OutputLimit => true
        _ => false
      },
    )
  }
  let measured = @encode.measuring_writer(size, 3, 1)
  @value_contract.emit_checked(value, measured)
  assert_eq(@encode.finish_measurement(measured), size)
  let embedded = @encode.writer(size + 2, 4, 2)
  @encode.begin_array(embedded)
  @value_contract.emit_checked(value, embedded)
  @encode.end_array(embedded)
  assert_eq(@encode.finish(embedded), "[" + output + "]")
}

///|
fn limits(
  nodes? : Int = 100000,
  depth? : Int = 20000,
  text? : Int = 8000000,
) -> @value_contract.Limits {
  { max_nodes: nodes, max_depth: depth, max_text_bytes: text, }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  let node = @source.parse_json(
    text,
    { max_input_bytes: 8000000, max_nodes: 300000, max_depth: 30000, },
    source_path="contract.json",
  ).unwrap()
  @decode.admit(node, {
    max_nodes: 300000,
    max_depth: 30000,
    max_string_bytes: 8000000,
    max_total_string_bytes: 8000000,
  }).unwrap()
}

///|
fn author(text : String) -> @value_contract.Contract {
  @value_contract.read_author(cursor(text), limits()).unwrap()
}

///|
fn checked(text : String) -> @value_contract.Contract {
  @value_contract.read_checked(cursor(text), limits()).unwrap()
}

///|
fn render(
  value : @value_contract.Contract,
) -> String raise @encode.EncodeFailure {
  @value_contract.stringify_checked(value, 8000000, 300000, 30000)
}

///|
fn error_name(
  result : Result[@value_contract.Contract, @value_contract.AdmissionError],
) -> String {
  match result {
    Ok(_) => "accepted"
    Err(InvalidLimits) => "InvalidLimits"
    Err(Decode(issue)) =>
      match issue.kind {
        MissingField => "MissingField"
        UnknownField => "UnknownField"
        OutOfRange => "OutOfRange"
        WrongType => "WrongType"
        UnexpectedNull => "UnexpectedNull"
        _ => "Decode"
      }
    Err(ContractIssue(issue, ..)) =>
      match issue {
        UnknownType(_) => "UnknownType"
        InvalidFieldName(_) => "InvalidFieldName"
        NonCanonicalText => "NonCanonicalText"
        InvalidUnicode => "InvalidUnicode"
        InvalidFixedField => "InvalidFixedField"
        InvalidRange => "InvalidRange"
        BudgetExceeded => "BudgetExceeded"
      }
  }
}

///|
test "author grammar does not admit checked evidence or parameter vocabulary" {
  for
    source in [
      "{\"type\":\"string\",\"nullable\":false,\"min_length\":0}", "{\"type\":\"object\",\"nullable\":false,\"fields\":{},\"additional_properties\":false}",
      "{\"type\":\"number\",\"nullable\":false,\"default\":0}", "{\"type\":\"number\",\"nullable\":false,\"integer\":true}",
      "{\"type\":\"number\",\"nullable\":false,\"meta\":{\"note\":\"x\"}}", "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false,\"max_codepoints\":3}}",
    ] {
    assert_eq(
      error_name(@value_contract.read_author(cursor(source), limits())),
      "UnknownField",
    )
  }
  let metadata_field = author(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"meta\":{\"type\":\"json\",\"nullable\":true}}}",
  )
  assert_true(render(metadata_field).contains("\"meta\""))
}

///|
test "checked fixed members required and explicit optional nulls rejected" {
  for
    (source, expected) in [
      (
        "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":1}", "MissingField",
      ),
      (
        "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":1,\"element_type\":\"f64\"}",
        "InvalidFixedField",
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{},\"additional_properties\":true}",
        "InvalidFixedField",
      ),
      (
        "{\"type\":\"string\",\"nullable\":false,\"max_codepoints\":null}", "WrongType",
      ),
      (
        "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":null}", "WrongType",
      ),
      ("{\"type\":\"alien\",\"nullable\":false}", "UnknownType"),
    ] {
    assert_eq(
      error_name(@value_contract.read_checked(cursor(source), limits())),
      expected,
    )
  }
}

///|
test "numeric contract boundaries follow each field domain" {
  for
    (source, expected) in [
      (
        "{\"type\":\"decimal\",\"nullable\":false,\"precision\":0,\"scale\":0}",
        "InvalidRange",
      ),
      (
        "{\"type\":\"decimal\",\"nullable\":false,\"precision\":39,\"scale\":0}",
        "InvalidRange",
      ),
      (
        "{\"type\":\"decimal\",\"nullable\":false,\"precision\":2.5,\"scale\":0}",
        "OutOfRange",
      ),
      (
        "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":0}", "InvalidRange",
      ),
      (
        "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":1.5}", "InvalidRange",
      ),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false},\"max_items\":9007199254740992}",
        "OutOfRange",
      ),
    ] {
    assert_eq(
      error_name(@value_contract.read_author(cursor(source), limits())),
      expected,
    )
  }
  let vector = author(
    "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":9007199254740992}",
  )
  assert_true(render(vector).contains("9007199254740992"))
  let bound = checked(
    "{\"type\":\"string\",\"nullable\":false,\"max_utf8_bytes\":9007199254740991}",
  )
  assert_true(render(bound).contains("9007199254740991"))
  // Admission preserves declared constraints; it does not infer inhabitedness.
  ignore(
    checked(
      "{\"type\":\"string\",\"nullable\":true,\"min_length\":5,\"max_codepoints\":2}",
    ),
  )
}

///|
test "field names and reference restrictions preserve non-identifier strings" {
  for
    name in [
      "a\\nb", "a\\u2028b", "__cid\\n", "a\\u0000b", "é", "😀", "meta",
    ] {
    ignore(
      author(
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"" +
        name +
        "\":{\"type\":\"number\",\"nullable\":false}}}",
      ),
    )
  }
  for name in ["", "\\uFEFF \\t", "__cid", "__actql_x", "a\\nb.c"] {
    let c = cursor(
      "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"" +
      name +
      "\":{\"type\":\"number\",\"nullable\":false}}}",
    )
    assert_eq(
      error_name(@value_contract.read_author(c, limits())),
      "InvalidFieldName",
    )
  }
  for key in ["resource_kind", "media_type"] {
    let kind = if key == "media_type" { "artifact_ref" } else { "resource_ref" }
    ignore(
      author(
        "{\"type\":\"" +
        kind +
        "\",\"nullable\":false,\"" +
        key +
        "\":\" \\n\"}",
      ),
    )
    assert_eq(
      error_name(
        @value_contract.read_author(
          cursor(
            "{\"type\":\"" +
            kind +
            "\",\"nullable\":false,\"" +
            key +
            "\":\"\"}",
          ),
          limits(),
        ),
      ),
      "InvalidRange",
    )
  }
}

///|
test "contract budgets count nodes nesting and text at exact boundaries" {
  let c = cursor(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
  assert_true(
    @value_contract.read_author(c, limits(nodes=2, depth=1, text=11)) is Ok(_),
  )
  for l in [limits(nodes=1), limits(depth=0), limits(text=10)] {
    assert_eq(error_name(@value_contract.read_author(c, l)), "BudgetExceeded")
  }
  for l in [limits(nodes=-1), limits(depth=-1), limits(text=-1)] {
    assert_eq(error_name(@value_contract.read_author(c, l)), "InvalidLimits")
  }
  let scalar = cursor("{\"type\":\"number\",\"nullable\":false}")
  assert_true(
    @value_contract.read_author(scalar, limits(nodes=1, depth=0, text=6))
    is Ok(_),
  )
  assert_eq(
    error_name(@value_contract.read_author(scalar, limits(nodes=0))),
    "BudgetExceeded",
  )
}

///|
test "recursive errors preserve source path and span" {
  let c = cursor(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"decimal\",\"nullable\":false,\"precision\":2,\"scale\":3}}",
  )
  match @value_contract.read_author(c, limits()) {
    Err(ContractIssue(InvalidRange, path~, span~)) => {
      assert_eq(path, [@source.Key("items"), @source.Key("scale")])
      assert_eq(span.source_path, "contract.json")
      assert_eq(span.end_byte - span.start_byte, 1)
    }
    _ => assert_true(false)
  }
}

///|
test "detached field arrays preserve checked contract ownership" {
  let value = author(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"z\":{\"type\":\"number\",\"nullable\":false},\"a\":{\"type\":\"string\",\"nullable\":false}}}",
  )
  let before = render(value)
  match value.shape {
    Object(f) => {
      let detached = @value_contract.fields(f)
      assert_eq(detached[0].name, "a")
      ignore(detached.pop())
      assert_eq(@value_contract.fields(f).length(), 2)
    }
    _ => assert_true(false)
  }
  assert_eq(render(value), before)
}

///|
test "deep admission comparison join and emission do not recurse" {
  let source = "{\"type\":\"array\",\"nullable\":false,\"items\":".repeat(10000) +
    "{\"type\":\"number\",\"nullable\":false}" +
    "}".repeat(10000)
  let value = author(source)
  assert_true(@value_contract.type_equal(value, value, 10001))
  assert_true(@value_contract.assignable(value, value, 10001))
  let joined = @value_contract.join_nullability(value, value, 10001).unwrap()
  assert_eq(render(joined), render(value))
  assert_true(
    try {
      ignore(@value_contract.type_equal(value, value, 10000))
      false
    } catch {
      @value_contract.RelationLimit => true
      _ => false
    },
  )
}
