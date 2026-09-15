///|
fn cursor(text : String) -> @decode.Cursor {
  let node = @source.parse_json(
    text,
    { max_input_bytes: 8000000, max_nodes: 300000, max_depth: 30000, },
    source_path="params.json",
  ).unwrap()
  @decode.admit(node, {
    max_nodes: 300000,
    max_depth: 30000,
    max_string_bytes: 8000000,
    max_total_string_bytes: 8000000,
  }).unwrap()
}

///|
fn limits(
  nodes? : Int = 100000,
  depth? : Int = 20000,
  text? : Int = 8000000,
  parameters? : Int = 10000,
) -> @parameter_binding.DeclarationLimits {
  {
    max_parameters: parameters,
    max_nodes: nodes,
    max_depth: depth,
    max_text_bytes: text,
  }
}

///|
fn values_limit(
  nodes? : Int = 100000,
  depth? : Int = 20000,
  text? : Int = 8000000,
) -> @value.Limits {
  { max_nodes: nodes, max_depth: depth, max_text_bytes: text, }
}

///|
fn declarations(text : String) -> @parameter_binding.Declarations {
  @parameter_binding.read_declarations(Some(cursor(text)), limits()).unwrap()
}

///|
fn bind(
  text : String,
  values : String,
) -> Result[@parameter_binding.BindingResult, @parameter_binding.Issue] {
  @parameter_binding.bind(
    declarations(text),
    Some(cursor(values)),
    values_limit(),
  )
}

///|
fn ready(
  value : @parameter_binding.BindingResult,
) -> Array[@parameter_binding.BoundParameter] raise {
  match value {
    @parameter_binding.Ready(values) => @parameter_binding.bound_values(values)
    _ => {
      assert_true(false)
      []
    }
  }
}

///|
fn decode_outcome(kind : @decode.IssueKind) -> String {
  match kind {
    @decode.UnknownField => "UnknownField"
    @decode.MissingField => "MissingField"
    @decode.WrongType => "WrongType"
    _ => "DecodeError"
  }
}

///|
fn outcome(
  result : Result[@parameter_binding.BindingResult, @parameter_binding.Issue],
) -> String {
  match result {
    Err(@parameter_binding.BindingInput(_, issue)) => outcome(Err(issue))
    Ok(@parameter_binding.Ready(_)) => "Ready"
    Ok(@parameter_binding.NeedsBindings(_)) => "NeedsBindings"
    Err(@parameter_binding.Decode(e)) => decode_outcome(e.kind)
    Err(@parameter_binding.Contract(@contract.Decode(e))) =>
      decode_outcome(e.kind)
    Err(
      @parameter_binding.Contract(
        @contract.ContractIssue(@contract.UnknownType(_), ..)
      )
    ) => "UnknownType"
    Err(@parameter_binding.Value(@value.Decode(e))) => decode_outcome(e.kind)
    Err(@parameter_binding.Value(@value.ValueIssue(@value.UnexpectedNull, ..))) =>
      "UnexpectedNull"
    Err(@parameter_binding.Value(@value.ValueIssue(@value.WrongType, ..))) =>
      "WrongType"
    Err(@parameter_binding.Value(@value.ValueIssue(@value.ArrayConstraint, ..))) =>
      "ArrayConstraint"
    Err(
      @parameter_binding.ParameterIssue(
        @parameter_binding.NumericConstraint,
        ..
      )
    ) => "NumericConstraint"
    Err(
      @parameter_binding.ParameterIssue(
        @parameter_binding.DurationConstraint,
        ..
      )
    ) => "DurationConstraint"
    Err(
      @parameter_binding.ParameterIssue(@parameter_binding.LengthConstraint, ..)
    ) => "LengthConstraint"
    Err(
      @parameter_binding.ParameterIssue(
        @parameter_binding.ReservedMetadataKey,
        ..
      )
    ) => "ReservedMetadataKey"
    Err(_) => "OtherError"
  }
}

///|
test "binding defaults apply only to missing values and origin stays separate" {
  let d = declarations(
    "{\"x\":{\"type\":\"number\",\"default\":3},\"n\":{\"type\":\"string\",\"nullable\":true,\"default\":\"fallback\"}}",
  )
  let omitted = ready(@parameter_binding.bind(d, None, values_limit()).unwrap())
  let explicit = ready(
    @parameter_binding.bind(
      d,
      Some(cursor("{\"x\":3,\"n\":null}")),
      values_limit(),
    ).unwrap(),
  )
  assert_eq(omitted.map(e => e.name), ["n", "x"])
  assert_true(omitted[0].value.value is @value.Text("fallback"))
  assert_true(explicit[0].value.value is @value.Null)
  assert_true(omitted[1].origin is @parameter_binding.Default)
  assert_true(explicit[1].origin is @parameter_binding.Supplied)
  assert_true(omitted[1].value.value is @value.Number(3.0))
  assert_true(explicit[1].value.value is @value.Number(3.0))
  let info = @parameter_binding.declarations(d)
  assert_true(@parameter_binding.has_default(info[0]))
  info.clear()
  assert_eq(@parameter_binding.declarations(d).length(), 2)
}

///|
test "all missing names are reported without exposing a partially ready set" {
  let d = declarations(
    "{\"z\":{\"type\":\"number\"},\"a\":{\"type\":\"string\",\"nullable\":true}}",
  )
  match @parameter_binding.bind(d, None, values_limit()).unwrap() {
    @parameter_binding.NeedsBindings(missing) => {
      let names = @parameter_binding.missing_names(missing)
      assert_eq(names, ["a", "z"])
      names.clear()
      assert_eq(@parameter_binding.missing_names(missing), ["a", "z"])
      assert_eq(@parameter_binding.missing_count(missing), 2)
      assert_true(
        physical_equal(@parameter_binding.missing_declaration_owner(missing), d),
      )
      for index in 0..<2 {
        let original = @parameter_binding.declaration_at(d, index).unwrap()
        let retained = @parameter_binding.missing_at(missing, index).unwrap()
        assert_true(physical_equal(original, retained))
        assert_eq(
          @decode.cursor_path(@parameter_binding.declaration_source(retained)),
          [@source.Key(retained.name)],
        )
        assert_eq(
          @decode.cursor_span(@parameter_binding.declaration_source(retained)).source_path,
          "params.json",
        )
      }
      assert_true(@parameter_binding.missing_at(missing, -1) is None)
      assert_true(@parameter_binding.missing_at(missing, 2) is None)
    }
    _ => assert_true(false)
  }
  assert_true(
    @parameter_binding.bind(d, Some(cursor("{\"z\":\"bad\"}")), values_limit())
    is Err(_),
  )
  assert_true(
    @parameter_binding.bind(d, Some(cursor("{\"extra\":1}")), values_limit())
    is Err(
      @parameter_binding.BindingInput(Supplied, @parameter_binding.Decode(_))
    ),
  )
}

///|
test "recursive nullable defaults and constraints are parameter-only" {
  let text = "{\"options\":{\"type\":\"object\",\"fields\":{\"retries\":{\"type\":\"number\",\"integer\":true,\"minimum\":0},\"waits\":{\"type\":\"array\",\"length\":2,\"items\":{\"type\":\"string\",\"format\":\"duration\"}}}}}"
  assert_true(
    bind(text, "{\"options\":{\"retries\":2,\"waits\":[\"01S\",\"1ms\"]}}")
    is Ok(@parameter_binding.Ready(_)),
  )
  for
    input in [
      "{\"options\":null}", "{\"options\":{\"retries\":null,\"waits\":[\"1s\",\"2s\"]}}",
      "{\"options\":{\"retries\":1.5,\"waits\":[\"1s\",\"2s\"]}}", "{\"options\":{\"retries\":1,\"waits\":[\"1s\"]}}",
      "{\"options\":{\"retries\":1,\"waits\":[\"1s\",null]}}", "{\"options\":{\"retries\":1,\"waits\":[\"1s\",\"0s\"]}}",
    ] {
    assert_true(bind(text, input) is Err(_))
  }
  assert_true(
    @contract.read_author(
      cursor(
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\"}}",
      ),
      { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
    )
    is Err(_),
  )
  assert_true(
    bind(
      "{\"a\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"nullable\":true}}}",
      "{\"a\":[null]}",
    )
    is Ok(@parameter_binding.Ready(_)),
  )
}

///|
test "integer and bounds impose no unintended safe integer ceiling" {
  let text = "{\"x\":{\"type\":\"number\",\"integer\":true,\"minimum\":-1,\"maximum\":1e100}}"
  for n in ["-1", "0", "9007199254740992", "1e100"] {
    assert_true(bind(text, "{\"x\":" + n + "}") is Ok(_))
  }
  for n in ["-2", "0.5", "1e101"] {
    assert_true(
      bind(text, "{\"x\":" + n + "}")
      is Err(
        @parameter_binding.BindingInput(
          Supplied,
          @parameter_binding.ParameterIssue(
            @parameter_binding.NumericConstraint,
            ..
          )
        )
      ),
    )
  }
  assert_true(
    bind("{\"x\":{\"type\":\"number\",\"integer\":false}}", "{\"x\":0.5}")
    is Ok(_),
  )
}

///|
test "duration constraints follow ASCII token and positive safe millisecond rules" {
  let d = declarations("{\"t\":{\"type\":\"string\",\"format\":\"duration\"}}")
  for
    text in [
      "1ms", "01MS", "1S", "1m", "1H", "1d", "9007199254740991ms", "9007199254740s",
      "000000000000000000000000001mS",
    ] {
    let v = ready(
      @parameter_binding.bind(
        d,
        Some(cursor("{\"t\":\"" + text + "\"}")),
        values_limit(),
      ).unwrap(),
    )
    match v[0].value.value {
      @value.Text(actual) => assert_eq(actual, text)
      _ => assert_true(false)
    }
  }
  for
    text in [
      "0s", "000ms", "-0ms", "+1s", "1.5s", "1e3ms", "1w", "1 s", "1", "ms", "9007199254740992ms",
      "9007199254741s", "999999999999999999999999999999d", "１s",
    ] {
    assert_true(
      @parameter_binding.bind(
        d,
        Some(cursor("{\"t\":\"" + text + "\"}")),
        values_limit(),
      )
      is Err(
        @parameter_binding.BindingInput(
          Supplied,
          @parameter_binding.ParameterIssue(
            @parameter_binding.DurationConstraint,
            ..
          )
        )
      ),
    )
  }
}

///|
test "defaults are complete canonical literals validated before any override" {
  for
    text in [
      "{\"x\":{\"type\":\"number\",\"default\":null}}", "{\"x\":{\"type\":\"number\",\"minimum\":1,\"default\":0}}",
      "{\"x\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"0ms\"}}",
      "{\"x\":{\"type\":\"object\",\"fields\":{\"a\":{\"type\":\"string\",\"nullable\":true}},\"default\":{}}}",
    ] {
    assert_true(
      @parameter_binding.read_declarations(Some(cursor(text)), limits())
      is Err(_),
    )
  }
  let text = "{\"x\":{\"type\":\"object\",\"fields\":{\"a\":{\"type\":\"number\"}},\"default\":{\"a\":1}}}"
  assert_true(bind(text, "{\"x\":{}}") is Err(_))
  let decimal = "{\"x\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"default\":\"19.90\"}}"
  let v = ready(bind(decimal, "{}").unwrap())
  match v[0].value.value {
    @value.Decimal(d) => assert_eq(d.coefficient, "1990")
    _ => assert_true(false)
  }
  assert_true(bind(decimal, "{\"x\":19.9}") is Err(_))
}

///|
test "default and metadata are root annotations not recursive type fields" {
  let d = declarations(
    "{\"p\":{\"type\":\"object\",\"meta\":{\"service\":{\"actql_note\":1}},\"fields\":{\"meta\":{\"type\":\"string\"}}}}",
  )
  assert_true(@parameter_binding.declarations(d)[0].metadata is Some(_))
  assert_true(
    @parameter_binding.bind(
      d,
      Some(cursor("{\"p\":{\"meta\":\"data\"}}")),
      values_limit(),
    )
    is Ok(_),
  )
  for extra in ["\"meta\":{\"x\":1}", "\"default\":1"] {
    assert_true(
      @parameter_binding.read_declarations(
        Some(
          cursor(
            "{\"p\":{\"type\":\"array\",\"items\":{\"type\":\"number\"," +
            extra +
            "}}}",
          ),
        ),
        limits(),
      )
      is Err(_),
    )
  }
  for meta in ["{}", "null", "[]", "{\"actql_reserved\":true}"] {
    assert_true(
      @parameter_binding.read_declarations(
        Some(cursor("{\"p\":{\"type\":\"number\",\"meta\":" + meta + "}}")),
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "empty declarations and unsupported parameter domains fail closed" {
  let empty = @parameter_binding.read_declarations(
    None,
    limits(nodes=0, depth=0, text=0, parameters=0),
  ).unwrap()
  assert_eq(
    ready(
      @parameter_binding.bind(
        empty,
        None,
        values_limit(nodes=0, depth=0, text=0),
      ).unwrap(),
    ).length(),
    0,
  )
  assert_true(
    @parameter_binding.read_declarations(Some(cursor("{}")), limits()) is Err(_),
  )
  for name in ["1x", "$x", "a.b", "é"] {
    assert_true(
      @parameter_binding.read_declarations(
        Some(cursor("{\"" + name + "\":{\"type\":\"number\"}}")),
        limits(),
      )
      is Err(
        @parameter_binding.ParameterIssue(@parameter_binding.InvalidName, ..)
      ),
    )
  }
  for
    spec in [
      "{\"type\":\"json\"}", "{\"type\":\"vector\",\"dimensions\":1}", "{\"type\":\"artifact_ref\"}",
      "{\"type\":\"resource_ref\",\"resource_kind\":\"x\"}", "{\"type\":\"number\",\"nullable\":null}",
      "{\"type\":\"string\",\"integer\":true}", "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"length\":0}",
    ] {
    assert_true(
      @parameter_binding.read_declarations(
        Some(cursor("{\"x\":" + spec + "}")),
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "budgets cover the complete declaration tree and all effective values" {
  let text = "{\"a\":{\"type\":\"number\"},\"b\":{\"type\":\"number\"}}"
  // Root map, two declarations and two type strings; keys a,b,type,type and tags.
  let d = @parameter_binding.read_declarations(
    Some(cursor(text)),
    limits(nodes=5, depth=2, text=22, parameters=2),
  ).unwrap()
  for
    lim in [
      limits(nodes=4),
      limits(depth=1),
      limits(text=21),
      limits(parameters=1),
    ] {
    assert_true(
      @parameter_binding.read_declarations(Some(cursor(text)), lim) is Err(_),
    )
  }
  assert_true(
    @parameter_binding.bind(
      d,
      Some(cursor("{\"a\":1,\"b\":2}")),
      values_limit(nodes=2, depth=0, text=2),
    )
    is Ok(_),
  )
  for lim in [values_limit(nodes=1), values_limit(text=1)] {
    assert_true(
      @parameter_binding.bind(d, Some(cursor("{\"a\":1,\"b\":2}")), lim)
      is Err(_),
    )
  }
  let defaults = declarations(
    "{\"a\":{\"type\":\"string\",\"default\":\"é\"},\"b\":{\"type\":\"string\",\"default\":\"é\"}}",
  )
  assert_true(
    @parameter_binding.bind(defaults, None, values_limit(nodes=2, text=6))
    is Ok(_),
  )
  assert_true(
    @parameter_binding.bind(defaults, None, values_limit(text=5)) is Err(_),
  )
  for
    lim in [
      values_limit(nodes=-1),
      values_limit(depth=-1),
      values_limit(text=-1),
    ] {
    assert_true(
      @parameter_binding.bind(d, None, lim)
      is Err(@parameter_binding.InvalidLimits),
    )
  }
}

///|
test "diagnostics preserve original paths and values do not depend on mutable views" {
  let d = declarations(
    "{\"p\":{\"type\":\"object\",\"fields\":{\"x\":{\"type\":\"number\",\"minimum\":0}}}}",
  )
  match
    @parameter_binding.bind(
      d,
      Some(cursor("{\"p\":{\"x\":-1}}")),
      values_limit(),
    ) {
    Err(
      @parameter_binding.BindingInput(
        Supplied,
        @parameter_binding.ParameterIssue(
          @parameter_binding.NumericConstraint,
          path~,
          span~
        )
      )
    ) => {
      assert_eq(path, [@source.Key("p"), @source.Key("x")])
      assert_eq(span.start_byte, 10)
      assert_eq(span.end_byte, 12)
    }
    _ => assert_true(false)
  }
  let result = @parameter_binding.bind(
    d,
    Some(cursor("{\"p\":{\"x\":1}}")),
    values_limit(),
  ).unwrap()
  let copy = ready(result)
  copy.clear()
  assert_eq(ready(result).length(), 1)
}

///|
test "recursive parameter types defaults and values are nonrecursive traversals" {
  let depth = 3000
  let prefix = "{\"type\":\"array\",\"items\":"
  let declaration = "{\"p\":" +
    prefix.repeat(depth) +
    "{\"type\":\"number\",\"integer\":true}" +
    "}".repeat(depth) +
    "}"
  let value = "{\"p\":" + "[".repeat(depth) + "1" + "]".repeat(depth) + "}"
  assert_true(bind(declaration, value) is Ok(@parameter_binding.Ready(_)))
}

///|
test "default failures point into declarations and literal business JSON is opaque" {
  match
    @parameter_binding.read_declarations(
      Some(
        cursor(
          "{\"p\":{\"type\":\"array\",\"items\":{\"type\":\"number\",\"integer\":true},\"default\":[1.5]}}",
        ),
      ),
      limits(),
    ) {
    Err(
      @parameter_binding.ParameterIssue(
        @parameter_binding.NumericConstraint,
        path~,
        ..
      )
    ) =>
      assert_eq(path, [
        @source.Key("p"),
        @source.Key("default"),
        @source.Index(0),
      ])
    _ => assert_true(false)
  }
  let literal = "{\"p\":{\"type\":\"object\",\"fields\":{\"$param\":{\"type\":\"string\"}},\"default\":{\"$param\":\"other_parameter\"}}}"
  let values = ready(bind(literal, "{}").unwrap())
  match values[0].value.value {
    @value.Object(fields) => {
      let fields = @value.elements(fields)
      assert_eq(fields[0].0, "$param")
      assert_true(fields[0].1 is @value.Text("other_parameter"))
    }
    _ => assert_true(false)
  }
}

///|
test "wide parameter maps are admitted once and keep case-sensitive names" {
  let defs = StringBuilder()
  let supplied = StringBuilder()
  for index = 0; index < 2000; index = index + 1 {
    if index > 0 {
      defs.write_string(",")
      supplied.write_string(",")
    }
    let key = "\"p" + index.to_string() + "\":"
    defs.write_string(key + "{\"type\":\"number\"}")
    supplied.write_string(key + index.to_string())
  }
  let result = bind(
    "{" + defs.to_string() + "}",
    "{" + supplied.to_string() + "}",
  ).unwrap()
  assert_eq(ready(result).length(), 2000)
  let c = "{\"Name\":{\"type\":\"number\"},\"name\":{\"type\":\"number\"}}"
  assert_eq(
    ready(bind(c, "{\"name\":2,\"Name\":1}").unwrap()).map(v => v.name),
    ["Name", "name"],
  )
}

///|
test "declaration preflight includes metadata defaults and raw normalization" {
  let source = cursor(
    "{\"p\":{\"type\":\"number\",\"meta\":{\"note\":\"long string\"},\"default\":1}}",
  )
  assert_true(
    @parameter_binding.read_declarations(Some(source), limits(nodes=5))
    is Err(
      @parameter_binding.ParameterIssue(@parameter_binding.BudgetExceeded, ..)
    ),
  )
  assert_true(
    @parameter_binding.read_declarations(Some(source), limits(nodes=6)) is Ok(_),
  )
  let node = @source.parse_json("{\"p\":{\"type\":\"number\",\"minimum\":0}}", {
    max_input_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  match node.value {
    @source.Object(fields) =>
      match fields[0].value.value {
        @source.Object(parts) => {
          let entry = parts[1]
          parts[1] = {
            key: entry.key,
            key_span: entry.key_span,
            value: { value: @source.Number(-0.0), span: entry.value.span, },
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
  let raw = @decode.admit(node, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }).unwrap()
  assert_true(
    @parameter_binding.read_declarations(Some(raw), limits())
    is Err(
      @parameter_binding.ParameterIssue(@parameter_binding.InvalidNumber, ..)
    ),
  )
}
