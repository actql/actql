///|
fn limits(
  nodes? : Int = 100000,
  depth? : Int = 20000,
  text? : Int = 8000000,
) -> @value_admission.Limits {
  { max_nodes: nodes, max_depth: depth, max_text_bytes: text, }
}

///|
fn parsed(text : String) -> @source.Node {
  @source.parse_json(
    text,
    { max_input_bytes: 8000000, max_nodes: 300000, max_depth: 30000, },
    source_path="value.json",
  ).unwrap()
}

///|
fn owned(node : @source.Node) -> @decode.Cursor {
  @decode.admit(node, {
    max_nodes: 300000,
    max_depth: 30000,
    max_string_bytes: 8000000,
    max_total_string_bytes: 8000000,
  }).unwrap()
}

///|
fn contract(text : String) -> @contract.Contract {
  @contract.read_author(owned(parsed(text)), {
    max_nodes: 100000,
    max_depth: 20000,
    max_text_bytes: 8000000,
  }).unwrap()
}

///|
fn simple(name : String, nullable? : Bool = false) -> @contract.Contract {
  contract(
    "{\"type\":\"" + name + "\",\"nullable\":" + nullable.to_string() + "}",
  )
}

///|
fn accept(
  contract : @contract.Contract,
  text : String,
) -> @value_admission.CheckedValue {
  @value_admission.admit(contract, owned(parsed(text)), limits()).unwrap()
}

///|
fn outcome(
  result : Result[@value_admission.CheckedValue, @value_admission.Issue],
) -> String {
  match result {
    Ok(_) => "accepted"
    Err(@value_admission.Decode(issue)) =>
      match issue.kind {
        @decode.MissingField => "MissingField"
        @decode.UnknownField => "UnknownField"
        @decode.WrongType => "WrongType"
        _ => "DecodeError"
      }
    Err(@value_admission.ValueIssue(kind, ..)) =>
      match kind {
        @value_admission.InvalidLimits => "InvalidLimits"
        @value_admission.WrongType => "WrongType"
        @value_admission.UnexpectedNull => "UnexpectedNull"
        @value_admission.InvalidNumber => "InvalidNumber"
        @value_admission.InvalidUnicode => "InvalidUnicode"
        @value_admission.NonCanonicalText => "NonCanonicalText"
        @value_admission.InvalidDecimal => "InvalidDecimal"
        @value_admission.InvalidDate => "InvalidDate"
        @value_admission.InvalidTimestamp => "InvalidTimestamp"
        @value_admission.StringConstraint => "StringConstraint"
        @value_admission.ArrayConstraint => "ArrayConstraint"
        @value_admission.VectorDimension => "VectorDimension"
        @value_admission.UnsupportedReference => "UnsupportedReference"
        @value_admission.BudgetExceeded => "BudgetExceeded"
      }
  }
}

///|
fn raw(value : @source.Value) -> @decode.Cursor {
  owned({ value, span: parsed("null").span, })
}

///|
test "field byte limits identify the key span and unknown fields retain decode diagnostics" {
  let cursor = owned(parsed("{\"long\":0}"))
  match @value_admission.admit(simple("json"), cursor, limits(text=3)) {
    Err(
      @value_admission.ValueIssue(@value_admission.BudgetExceeded, path~, span~)
    ) => {
      assert_eq(path, [@source.Key("long")])
      assert_eq(span.start_byte, 1)
      assert_eq(span.end_byte, 7)
    }
    _ => assert_true(false)
  }
  let c = contract("{\"type\":\"object\",\"nullable\":false,\"fields\":{}}")
  match @value_admission.admit(c, cursor, limits()) {
    Err(@value_admission.Decode(issue)) => {
      assert_eq(issue.kind, @decode.UnknownField)
      assert_eq(issue.path, [@source.Key("long")])
      assert_eq(issue.span.start_byte, 1)
      assert_eq(issue.span.end_byte, 7)
    }
    _ => assert_true(false)
  }
}

///|
test "wide closed objects use shared declaration views and preserve UTF16 ordering" {
  let fields = StringBuilder()
  let input = StringBuilder()
  for index = 0; index < 5000; index = index + 1 {
    if index > 0 {
      fields.write_string(",")
      input.write_string(",")
    }
    let key = "\"f" + index.to_string() + "\":"
    fields.write_string(key + "{\"type\":\"number\",\"nullable\":false}")
    input.write_string(key + index.to_string())
  }
  let c = contract(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{" +
    fields.to_string() +
    "}}",
  )
  let cursor = owned(parsed("{" + input.to_string() + "}"))
  let value = @value_admission.admit(c, cursor, limits(nodes=5001, depth=1)).unwrap()
  match value.value {
    @value_admission.Object(fields) =>
      assert_eq(@value_admission.elements(fields).length(), 5000)
    _ => assert_true(false)
  }
  assert_eq(
    outcome(@value_admission.admit(c, cursor, limits(nodes=5000))),
    "BudgetExceeded",
  )
  match accept(simple("json"), "{\"\\ue000\":1,\"😀\":2}").value {
    @value_admission.Object(fields) =>
      assert_eq(@value_admission.elements(fields).map(e => e.0), [
        "😀", "\ue000",
      ])
    _ => assert_true(false)
  }
}

///|
test "shared subtrees and nested references do not bypass traversal" {
  let child = parsed("\"é\"")
  let cursor = raw(@source.Array([child, child]))
  assert_eq(
    outcome(
      @value_admission.admit(
        simple("json"),
        cursor,
        limits(nodes=3, depth=1, text=4),
      ),
    ),
    "accepted",
  )
  assert_eq(
    outcome(@value_admission.admit(simple("json"), cursor, limits(text=3))),
    "BudgetExceeded",
  )
  let c = contract(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"artifact_ref\",\"nullable\":true}}",
  )
  match @value_admission.admit(c, owned(parsed("[null]")), limits()) {
    Err(
      @value_admission.ValueIssue(
        @value_admission.UnsupportedReference,
        path~,
        ..
      )
    ) => assert_eq(path, [@source.Index(0)])
    _ => assert_true(false)
  }
  // An empty array visits no reference value and conveys no reference authority.
  assert_eq(
    outcome(@value_admission.admit(c, owned(parsed("[]")), limits())),
    "accepted",
  )
}

///|
test "nullable values preserve their root contract" {
  let c = simple("string", nullable=true)
  let value = accept(c, "null")
  assert_true(value.value is @value_admission.Null)
  assert_true(@contract.type_equal(value.contract, c, 1))
  assert_eq(
    outcome(
      @value_admission.admit(simple("string"), owned(parsed("null")), limits()),
    ),
    "UnexpectedNull",
  )
  assert_eq(
    outcome(
      @value_admission.admit(simple("number"), owned(parsed("\"1\"")), limits()),
    ),
    "WrongType",
  )
}

///|
test "source normalization is separate from raw cursor rejection" {
  let c = simple("string")
  assert_true(
    accept(c, "\"e\\u0301\\r\\n\"").value is @value_admission.Text("é\n"),
  )
  for text in ["e\u0301", "a\r\nb", "\u0344"] {
    assert_eq(
      outcome(@value_admission.admit(c, raw(@source.String(text)), limits())),
      "NonCanonicalText",
    )
  }
  assert_true(
    accept(c, "\"\\u0085\\u2028\\u2029\"").value
    is @value_admission.Text("\u0085\u2028\u2029"),
  )
}

///|
test "finite numbers and generic JSON reject noncanonical numeric values" {
  for c in [simple("number"), simple("json")] {
    for n in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0, -0.0] {
      assert_eq(
        outcome(@value_admission.admit(c, raw(@source.Number(n)), limits())),
        "InvalidNumber",
      )
    }
    for n in [0.0, 5.0e-324, 1.7976931348623157e308] {
      match
        @value_admission.admit(c, raw(@source.Number(n)), limits()).unwrap().value {
        @value_admission.Number(actual) =>
          assert_eq(actual.reinterpret_as_uint64(), n.reinterpret_as_uint64())
        _ => assert_true(false)
      }
    }
  }
}

///|
test "decimal coefficients retain precision scale and all significant digits" {
  for
    (p, s, input, coefficient) in [
      (4, 2, "19.90", "1990"),
      (3, 3, "0.001", "1"),
      (3, 2, "-0.01", "-1"),
      (1, 0, "0", "0"),
      (
        38, 0, "99999999999999999999999999999999999999", "99999999999999999999999999999999999999",
      ),
      (38, 38, "0.00000000000000000000000000000000000001", "1"),
    ] {
    let c = contract(
      "{\"type\":\"decimal\",\"nullable\":false,\"precision\":" +
      p.to_string() +
      ",\"scale\":" +
      s.to_string() +
      "}",
    )
    match accept(c, "\"" + input + "\"").value {
      @value_admission.Decimal(value) => {
        assert_eq(value.coefficient, coefficient)
        assert_eq(value.precision, p)
        assert_eq(value.scale, s)
      }
      _ => assert_true(false)
    }
  }
}

///|
test "decimal wire rejects alternate spellings without repair or rounding" {
  let c = contract(
    "{\"type\":\"decimal\",\"nullable\":false,\"precision\":4,\"scale\":2}",
  )
  for
    input in [
      "-0.00", "+1.00", "01.00", "1", "1.0", "1.000", "1e0", ".01", "1.", "100.00",
      " 1.00", "１.00", "1.0x",
    ] {
    assert_eq(
      outcome(@value_admission.admit(c, raw(@source.String(input)), limits())),
      "InvalidDecimal",
    )
  }
  for
    input in [
      "1", "{\"$decimal\":{\"coefficient\":\"100\",\"precision\":4,\"scale\":2}}",
    ] {
    assert_eq(
      outcome(@value_admission.admit(c, owned(parsed(input)), limits())),
      "WrongType",
    )
  }
}

///|
test "calendar validation includes year zero and Gregorian century boundaries" {
  for
    value in [
      "0000-02-29", "2000-02-29", "2400-02-29", "9999-12-31", "1900-02-28",
    ] {
    assert_true(
      accept(simple("date"), "\"" + value + "\"").value
      is @value_admission.Date(_),
    )
  }
  for
    value in [
      "1900-02-29", "2100-02-29", "2024-04-31", "2024-00-01", "2024-13-01", "2024-01-00",
      "2024-1-01", "10000-01-01", "-001-01-01", "2024-01-01Z",
    ] {
    assert_eq(
      outcome(
        @value_admission.admit(
          simple("date"),
          raw(@source.String(value)),
          limits(),
        ),
      ),
      "InvalidDate",
    )
  }
  assert_true(
    accept(simple("timestamp"), "\"0000-02-29T23:59:59.999Z\"").value
    is @value_admission.Timestamp("0000-02-29T23:59:59.999Z"),
  )
  for
    value in [
      "2024-02-30T00:00:00.000Z", "2024-01-01T24:00:00.000Z", "2024-01-01T00:60:00.000Z",
      "2024-01-01T00:00:60.000Z", "2024-01-01T00:00:00Z", "2024-01-01T00:00:00.00Z",
      "2024-01-01T00:00:00.0000Z", "2024-01-01T00:00:00.000+00:00", "2024-01-01t00:00:00.000z",
    ] {
    assert_eq(
      outcome(
        @value_admission.admit(
          simple("timestamp"),
          raw(@source.String(value)),
          limits(),
        ),
      ),
      "InvalidTimestamp",
    )
  }
}

///|
test "checked string constraints count normalized scalars and UTF8 bytes" {
  let c = @contract.read_checked(
    owned(
      parsed(
        "{\"type\":\"string\",\"nullable\":false,\"min_length\":1,\"max_codepoints\":1,\"max_utf8_bytes\":4}",
      ),
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  assert_true(accept(c, "\"😀\"").value is @value_admission.Text("😀"))
  for input in ["\"\"", "\"ab\"", "\"\\u0344\""] {
    assert_eq(
      outcome(@value_admission.admit(c, owned(parsed(input)), limits())),
      "StringConstraint",
    )
  }
  let bytes = @contract.read_checked(
    owned(
      parsed("{\"type\":\"string\",\"nullable\":false,\"max_utf8_bytes\":3}"),
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  assert_eq(
    outcome(@value_admission.admit(bytes, owned(parsed("\"😀\"")), limits())),
    "StringConstraint",
  )
  assert_eq(
    outcome(
      @value_admission.admit(bytes, owned(parsed("\"\\u0344\"")), limits()),
    ),
    "StringConstraint",
  )
}

///|
test "closed objects distinguish required nullable fields from missing fields" {
  let c = contract(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"a\":{\"type\":\"string\",\"nullable\":true},\"b\":{\"type\":\"number\",\"nullable\":false}}}",
  )
  let result = accept(c, "{\"b\":1,\"a\":null}")
  match result.value {
    @value_admission.Object(entries) => {
      let entries = @value_admission.elements(entries)
      assert_eq(entries.map(e => e.0), ["a", "b"])
      assert_true(entries[0].1 is @value_admission.Null)
    }
    _ => assert_true(false)
  }
  for
    (input, expected) in [
      ("{\"b\":1}", "MissingField"),
      ("{\"a\":null,\"b\":null}", "UnexpectedNull"),
      ("{\"a\":null,\"b\":1,\"c\":2}", "UnknownField"),
    ] {
    assert_eq(
      outcome(@value_admission.admit(c, owned(parsed(input)), limits())),
      expected,
    )
  }
}

///|
test "empty objects and arrays remain constrained" {
  let object = contract(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{}}",
  )
  assert_true(accept(object, "{}").value is @value_admission.Object(_))
  assert_eq(
    outcome(
      @value_admission.admit(object, owned(parsed("{\"x\":1}")), limits()),
    ),
    "UnknownField",
  )
  let array = contract(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"boolean\",\"nullable\":false},\"max_items\":0}",
  )
  assert_true(accept(array, "[]").value is @value_admission.Array(_))
  assert_eq(
    outcome(@value_admission.admit(array, owned(parsed("[true]")), limits())),
    "ArrayConstraint",
  )
}

///|
test "vector shape admission preserves binary64 rather than scoring quantization" {
  let c = contract("{\"type\":\"vector\",\"nullable\":false,\"dimensions\":3}")
  match accept(c, "[0.1,1e300,-1e-300]").value {
    @value_admission.Vector(items) =>
      assert_eq(@value_admission.elements(items), [0.1, 1.0e300, -1.0e-300])
    _ => assert_true(false)
  }
  assert_eq(
    outcome(@value_admission.admit(c, owned(parsed("[1,2]")), limits())),
    "VectorDimension",
  )
  assert_eq(
    outcome(@value_admission.admit(c, owned(parsed("[1,2,\"3\"]")), limits())),
    "WrongType",
  )
  let span = parsed("0").span
  for invalid in [-0.0, 0.0 / 0.0, 1.0 / 0.0] {
    let cursor = raw(
      @source.Array(
        [0.0, 1.0, invalid].map(n => { value: @source.Number(n), span, }),
      ),
    )
    match @value_admission.admit(c, cursor, limits()) {
      Err(
        @value_admission.ValueIssue(@value_admission.InvalidNumber, path~, ..)
      ) => assert_eq(path, [@source.Index(2)])
      _ => assert_true(false)
    }
  }
}

///|
test "reference values are unsupported even when nullable or structurally plausible" {
  for
    spec in [
      "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"record\"}",
      "{\"type\":\"artifact_ref\",\"nullable\":true}",
    ] {
    for input in ["null", "{}", "{\"identity_cid\":\"sha256:abc\"}"] {
      assert_eq(
        outcome(
          @value_admission.admit(contract(spec), owned(parsed(input)), limits()),
        ),
        "UnsupportedReference",
      )
    }
  }
}

///|
test "whole-value budgets include JSON descendants keys and vector elements" {
  let c = simple("json")
  let cursor = owned(parsed("{\"é\":[\"😀\",null]}"))
  assert_eq(
    outcome(@value_admission.admit(c, cursor, limits(nodes=4, depth=2, text=6))),
    "accepted",
  )
  for
    limit in [
      limits(nodes=3, depth=2, text=6),
      limits(nodes=4, depth=1, text=6),
      limits(nodes=4, depth=2, text=5),
    ] {
    assert_eq(
      outcome(@value_admission.admit(c, cursor, limit)),
      "BudgetExceeded",
    )
  }
  assert_eq(
    outcome(
      @value_admission.admit(
        c,
        owned(parsed("0")),
        limits(nodes=1, depth=0, text=0),
      ),
    ),
    "accepted",
  )
  assert_eq(
    outcome(
      @value_admission.admit(
        c,
        owned(parsed("[]")),
        limits(nodes=1, depth=0, text=0),
      ),
    ),
    "BudgetExceeded",
  )
  for limit in [limits(nodes=-1), limits(depth=-1), limits(text=-1)] {
    assert_eq(
      outcome(@value_admission.admit(c, cursor, limit)),
      "InvalidLimits",
    )
  }
  let vector = contract(
    "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":2}",
  )
  assert_eq(
    outcome(
      @value_admission.admit(
        vector,
        owned(parsed("[1,2]")),
        limits(nodes=3, depth=1, text=0),
      ),
    ),
    "accepted",
  )
  assert_eq(
    outcome(
      @value_admission.admit(
        vector,
        owned(parsed("[1,2]")),
        limits(nodes=2, depth=1, text=0),
      ),
    ),
    "BudgetExceeded",
  )
}

///|
test "errors keep original nested source spans and separate calls have fresh budgets" {
  let c = contract(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"date\",\"nullable\":false}}",
  )
  let cursor = owned(parsed("[\"2000-02-29\",\"1900-02-29\"]"))
  match @value_admission.admit(c, cursor, limits()) {
    Err(@value_admission.ValueIssue(@value_admission.InvalidDate, path~, span~)) => {
      assert_eq(path, [@source.Index(1)])
      assert_eq(span.start_byte, 14)
      assert_eq(span.end_byte, 26)
      assert_eq(span.source_path, "value.json")
      path.push(@source.Index(99))
    }
    _ => assert_true(false)
  }
  assert_eq(
    outcome(@value_admission.admit(c, owned(parsed("[]")), limits())),
    "accepted",
  )
  assert_eq(outcome(@value_admission.admit(c, cursor, limits())), "InvalidDate")
}

///|
test "returned arrays and source mutations cannot modify checked values" {
  let node = parsed("{\"a\":[1,2]}")
  let cursor = owned(node)
  let value = @value_admission.admit(simple("json"), cursor, limits()).unwrap()
  match node.value {
    @source.Object(fields) => fields.clear()
    _ => assert_true(false)
  }
  match value.value {
    @value_admission.Object(fields) => {
      let copy = @value_admission.elements(fields)
      match copy[0].1 {
        @value_admission.Array(items) => {
          let copy = @value_admission.elements(items)
          copy.clear()
          assert_eq(@value_admission.elements(items).length(), 2)
        }
        _ => assert_true(false)
      }
      copy.clear()
      assert_eq(@value_admission.elements(fields).length(), 1)
    }
    _ => assert_true(false)
  }
}

///|
test "generic JSON validates every descendant without treating business tags as Ref" {
  let c = simple("json")
  assert_true(
    accept(c, "{\"identity_cid\":\"business data\",\"$decimal\":\"text\"}").value
    is @value_admission.Object(_),
  )
  let span = parsed("null").span
  for value in [@source.Number(-0.0), @source.String("e\u0301")] {
    let cursor = raw(@source.Array([{ value, span, }]))
    assert_true(@value_admission.admit(c, cursor, limits()) is Err(_))
  }
  let fields : Array[@source.Field] = [
    { key: "e\u0301", key_span: span, value: { value: @source.Null, span, }, },
  ]
  assert_eq(
    outcome(@value_admission.admit(c, raw(@source.Object(fields)), limits())),
    "NonCanonicalText",
  )
}

///|
test "deep values and type-directed trees are traversed without recursion" {
  let depth = 10000
  let input = "[".repeat(depth) + "0" + "]".repeat(depth)
  let cursor = owned(parsed(input))
  assert_eq(
    outcome(
      @value_admission.admit(
        simple("json"),
        cursor,
        limits(nodes=depth + 1, depth~, text=0),
      ),
    ),
    "accepted",
  )
  let prefix = "{\"type\":\"array\",\"nullable\":false,\"items\":"
  let c = contract(
    prefix.repeat(depth) +
    "{\"type\":\"number\",\"nullable\":false}" +
    "}".repeat(depth),
  )
  let value = @value_admission.admit(
    c,
    cursor,
    limits(nodes=depth + 1, depth~, text=0),
  ).unwrap()
  let mut node = value.value
  let mut visited = 0
  while node is @value_admission.Array(items) {
    node = @value_admission.elements(items)[0]
    visited += 1
  }
  assert_eq(visited, depth)
  assert_true(node is @value_admission.Number(0.0))
}
