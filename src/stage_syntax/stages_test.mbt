///|
fn source() -> String {
  let value =
    #|version: actql/0.1
    #|id: example
    #|stages:
    #|- id: parent
    #|  inputs: {}
    #|  steps: []
    #|  results:
    #|    rows: {from: generated}
    #|  effects:
    #|    create: {create: {}}
    #|- id: child
    #|  after: accepted
    #|  inputs:
    #|    parents: {receipt: {stage: parent, effect: create}}
    #|    data: {result: {stage: parent, result: rows}}
    #|  from: parents
    #|  steps: []
    #|  results:
    #|    children: {from: parents}
    #|- id: notify
    #|  inputs: {}
    #|  steps: []
    #|  results:
    #|    messages: {from: generated}
    #|results:
    #|  final: {from: {stage: notify, result: messages}}
  value
}

///|
fn limits(
  bytes? : Int = 1000000,
  nodes? : Int = 100000,
  depth? : Int = 20000,
  stage_count? : Int = 10000,
  tree_nodes? : Int = 100000,
  tree_depth? : Int = 20000,
  string_bytes? : Int = 1000000,
  total_bytes? : Int = 1000000,
) -> Limits {
  {
    source: { max_input_bytes: bytes, max_nodes: nodes, max_depth: depth, },
    tree: {
      max_nodes: tree_nodes,
      max_depth: tree_depth,
      max_string_bytes: string_bytes,
      max_total_string_bytes: total_bytes,
    },
    max_stages: stage_count,
  }
}

///|
fn parsed(text : String, format? : Format = Auto) -> Program raise {
  match parse(text, limits(), format~, source_path="program.aql") {
    Ok(value) => value
    Err(error) => {
      debug_inspect(error, content="no error")
      fail("unexpected rejection")
    }
  }
}

///|
fn rejected(text : String, format? : Format = Auto) -> SyntaxError raise {
  match parse(text, limits(), format~, source_path="program.aql") {
    Err(error) => error
    Ok(_) => fail("expected rejection")
  }
}

///|
fn minimal() -> String {
  (
    #|{"version":"actql/0.1","id":"p","stages":[{"id":"s","inputs":{},"steps":[],"results":{"r":{}}}],"results":{"out":{"from":{"stage":"s","result":"r"}}}}
  )
}

///|
test "stage connections preserve ordered control and named data ports" {
  let p = parsed(source())
  assert_eq(p.id, "example")
  let all = stages(p)
  assert_eq(all.length(), 3)
  assert_eq(all[0].predecessor, Initial)
  assert_eq(all[1].predecessor, Accepted("parent"))
  assert_eq(all[2].predecessor, Completed("child"))
  assert_eq(imports(all[1]), [
    ("parents", Receipt(producer="parent", effect="create")),
    ("data", Result(producer="parent", result="rows")),
  ])
  assert_eq(imports(all[2]).length(), 0)
  assert_eq(exports(p), [("final", "notify", "messages")])
  let defaults = parsed(source().replace(old="  after: accepted\n", new=""))
  assert_eq(stages(defaults)[1].predecessor, Completed("parent"))
  assert_eq(stages(parsed(source(), format=Yaml))[2].id, "notify")
}

///|
test "stage topology rejects invalid predecessor and port references" {
  let cases : Array[(String, String, StructuralIssue)] = [
    ("- id: parent", "- id: parent\n  after: completed", InitialAfter),
    ("- id: child", "- id: parent", DuplicateStage("parent")),
    ("stage: parent, effect", "stage: child, effect", UnknownProducer("child")),
    (
      "stage: parent, effect",
      "stage: notify, effect",
      UnknownProducer("notify"),
    ),
    (
      "stage: parent, effect",
      "stage: absent, effect",
      UnknownProducer("absent"),
    ),
    ("effect: create", "effect: absent", UnknownEffect("absent")),
    (
      "stage: parent, result: rows",
      "stage: parent, result: tmp",
      UnknownResult("tmp"),
    ),
    ("after: accepted", "after: unknown", InvalidAfter),
    (
      "stage: notify, result: messages",
      "stage: notify, result: absent",
      UnknownResult("absent"),
    ),
    (
      "stage: notify, result: messages",
      "stage: absent, result: messages",
      UnknownProducer("absent"),
    ),
    ("from: parents", "from: elsewhere", UnknownInput("elsewhere")),
  ]
  for (old, new, expected) in cases {
    guard rejected(source().replace(old~, new~))
      is Structure(issue, path~, span~) else {
      fail("expected structural rejection")
    }
    assert_eq(issue, expected)
    assert_true(!path.is_empty())
    assert_eq(span.source_path, "program.aql")
  }
}

///|
test "root and stage envelopes require closed fields and nonempty declarations" {
  let cases : Array[(String, String, @wire.IssueKind)] = [
    ("\"version\":\"actql/0.1\",", "", MissingField),
    ("\"id\":\"p\",", "", MissingField),
    ("\"stages\":", "\"inputs\":{},\"stages\":", UnknownField),
    ("\"inputs\":{}", "\"inputs\":{},\"output\":{}", UnknownField),
    ("\"inputs\":{},", "", MissingField),
    ("\"steps\":[],", "", MissingField),
    ("\"steps\":[]", "\"steps\":{}", WrongType),
    ("\"inputs\":{}", "\"inputs\":[]", WrongType),
    ("\"steps\":[]", "\"steps\":null", UnexpectedNull),
    ("\"id\":\"s\"", "\"id\":false", WrongType),
    ("\"results\":{\"r\":{}}", "\"results\":null", UnexpectedNull),
  ]
  for (old, new, expected) in cases {
    guard rejected(minimal().replace(old~, new~)) is Decode(issue) else {
      fail("expected shape rejection")
    }
    assert_eq(issue.kind, expected)
  }
  let semantic : Array[(String, String, StructuralIssue)] = [
    ("actql/0.1", "actql/9.0", WrongVersion),
    ("\"id\":\"p\"", "\"id\":\"\"", EmptyName),
    ("\"id\":\"s\"", "\"id\":\"\"", EmptyName),
    ("\"r\":{}", "\"\":{}", EmptyName),
    ("\"results\":{\"r\":{}}", "\"results\":{}", EmptyDeclarations),
    ("\"id\":\"p\"", "\"id\":\"p\",\"params\":{}", EmptyDeclarations),
    ("\"id\":\"p\"", "\"id\":\"p\",\"bindings\":{}", EmptyDeclarations),
    ("\"id\":\"p\"", "\"id\":\"p\",\"meta\":{}", EmptyDeclarations),
    ("\"id\":\"s\"", "\"id\":\"s\",\"meta\":{}", EmptyDeclarations),
  ]
  for (old, new, expected) in semantic {
    guard rejected(minimal().replace(old~, new~)) is Structure(issue, ..) else {
      fail("expected structural rejection")
    }
    assert_eq(issue, expected)
  }
  assert_true(
    rejected(
      "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[],\"results\":{}}",
    )
    is Structure(EmptyStages, ..),
  )
}

///|
test "imports and exports have closed reference envelopes" {
  for
    (old, new) in [
      (
        "{receipt: {stage: parent, effect: create}}", "{receipt: {stage: parent, effect: create}, carrier: relation}",
      ),
      (
        "{stage: parent, effect: create}", "{stage: parent, effect: create, extra: true}",
      ),
      ("{stage: parent, effect: create}", "{stage: parent}"),
      ("{stage: parent, effect: create}", "{stage: null, effect: create}"),
      (
        "{from: {stage: notify, result: messages}}", "{from: {stage: notify, result: messages}, fields: [x]}",
      ),
      (
        "{stage: notify, result: messages}", "{stage: notify, result: messages, extra: true}",
      ),
      ("{stage: notify, result: messages}", "{result: messages}"),
    ] {
    assert_true(rejected(source().replace(old~, new~)) is Decode(_))
  }
}

///|
test "auto detects syntax only and retains both failed parser diagnostics" {
  assert_eq(parsed(minimal()).id, parsed(minimal(), format=Json).id)
  assert_true(rejected(source(), format=Json) is Parse(_))
  assert_eq(parsed(minimal(), format=Yaml).id, "p")
  // A syntactically complete JSON scalar must not be reconsidered as YAML.
  assert_true(rejected("true") is Decode(_))
  assert_true(
    rejected("{\"version\":\"other\"}") is Structure(WrongVersion, ..),
  )
  guard rejected("@bad") is Alternatives(json~, yaml~) else {
    fail("expected both syntax diagnostics")
  }
  assert_eq(json.issue, @source.UnexpectedToken)
  assert_eq(yaml.issue, @source.InvalidYamlScalar)
  assert_eq(json.source_path, "program.aql")
  assert_eq(yaml.source_path, "program.aql")
  for
    (text, expected) in [
      ("-0", @source.NegativeZero),
      ("1e400", @source.NumberOutOfRange),
      ("\"\\ud800\"", @source.InvalidUnicodeEscape),
      ("{\"é\":1,\"e\\u0301\":2}", @source.DuplicateKey("é")),
    ] {
    guard rejected(text) is Parse(error) else { fail("must not retry YAML") }
    assert_eq(error.issue, expected)
  }
}

///|
test "source and admission budgets remain independent with exact boundaries" {
  let text = minimal()
  // 15 value nodes, deepest container at depth 5; keys are not nodes.
  assert_true(
    parse(
      text,
      limits(
        bytes=text.length(),
        nodes=15,
        depth=5,
        tree_nodes=15,
        tree_depth=5,
        stage_count=1,
      ),
    )
    is Ok(_),
  )
  for
    (budget, expected) in [
      (limits(bytes=text.length() - 1), @source.InputLimit),
      (limits(nodes=14), @source.NodeLimit),
      (limits(depth=4), @source.DepthLimit),
    ] {
    guard parse(text, budget) is Err(Parse(error)) else {
      fail("expected source limit")
    }
    assert_eq(error.issue, expected)
  }
  for
    budget in [
      limits(tree_nodes=14),
      limits(tree_depth=4),
      limits(string_bytes=4),
      limits(total_bytes=1),
    ] {
    guard parse(text, budget) is Err(Decode(issue)) else {
      fail("expected admission limit")
    }
    assert_eq(issue.kind, @wire.BudgetExceeded)
  }
  assert_true(
    parse(text, limits(stage_count=0)) is Err(Structure(StageLimit, ..)),
  )
  assert_true(
    parse(source(), limits(stage_count=2)) is Err(Structure(StageLimit, ..)),
  )
  for
    budget in [
      limits(bytes=-1),
      limits(nodes=-1),
      limits(depth=-1),
      limits(tree_nodes=-1),
      limits(tree_depth=-1),
      limits(string_bytes=-1),
      limits(total_bytes=-1),
      limits(stage_count=-1),
    ] {
    assert_true(parse("@bad", budget) is Err(InvalidLimits))
  }
  // YAML fallback still applies its own source caps and reports terminal limits.
  assert_true(
    parse(source(), limits(nodes=1))
    is Err(Parse({ issue: @source.NodeLimit, .. })),
  )
}

///|
test "byte input and explicit formats preserve normalization and source spans" {
  let text = source().replace(old="id: example", new="id: e\u0301")
  for format in [Format::Auto, Format::Yaml] {
    let a = parsed(text, format~)
    let b = parse_bytes(
      @utf8.encode(text),
      limits(),
      format~,
      source_path="program.aql",
    ).unwrap()
    assert_eq(a.id, "é")
    assert_eq(b.id, a.id)
    assert_eq(exports(a), exports(b))
    assert_eq(
      @wire.cursor_span(program_body(a)),
      @wire.cursor_span(program_body(b)),
    )
  }
  let malformed = String::from_array([(0xd800).unsafe_to_char()])
  assert_true(rejected(malformed) is Parse({ issue: @source.InvalidUtf16, .. }))
  assert_true(
    parse_bytes(b"\xff", limits())
    is Err(Parse({ issue: @source.InvalidUtf8, .. })),
  )
  let e = rejected(
    source().replace(old="stage: parent, effect", new="stage: missing, effect"),
  )
  guard e is Structure(UnknownProducer("missing"), path~, span~) else {
    fail("expected reference issue")
  }
  assert_eq(path, [
    @source.Key("stages"),
    @source.Index(1),
    @source.Key("inputs"),
    @source.Key("parents"),
    @source.Key("receipt"),
    @source.Key("stage"),
  ])
  assert_eq(span.source_path, "program.aql")
  assert_eq(span.start_line, 14)
  assert_eq(span.end_byte - span.start_byte, 7)
}

///|
test "program bodies and accessor arrays are isolated owned views" {
  let p = parsed(source())
  let all = stages(p)
  let child = all[1]
  all.clear()
  imports(child).clear()
  result_names(child).clear()
  effect_names(stages(p)[0]).clear()
  exports(p).clear()
  assert_eq(stages(p).length(), 3)
  assert_eq(imports(child).length(), 2)
  assert_eq(result_names(child), ["children"])
  assert_eq(effect_names(stages(p)[0]), ["create"])
  assert_eq(exports(p), [("final", "notify", "messages")])
  let root = @wire.open_object(program_body(p)).unwrap()
  let body = @wire.elements(@wire.required(root, "stages").unwrap()).unwrap()
  body.clear()
  assert_eq(stages(p).length(), 3)
  let view = @wire.open_object(stage_body(child)).unwrap()
  assert_eq(@wire.text(@wire.required(view, "id").unwrap()).unwrap(), "child")
}

///|
test "local bodies remain explicitly unchecked syntax without fabricated execution" {
  let text = minimal()
    .replace(old="\"steps\":[]", new="\"steps\":[{\"unknown_operation\":true}]")
    .replace(
      old="\"id\":\"p\"",
      new="\"id\":\"p\",\"params\":{\"x\":{\"type\":\"not_a_type\"}}",
    )
  let p = parsed(text)
  let stage = stages(p)[0]
  let view = @wire.open_object(stage_body(stage)).unwrap()
  assert_eq(
    @wire.elements(@wire.required(view, "steps").unwrap()).unwrap().length(),
    1,
  )
  let deep = minimal().replace(
    old="\"r\":{}",
    new="\"r\":" + "[".repeat(1000) + "true" + "]".repeat(1000),
  )
  assert_true(parse(deep, limits()) is Ok(_))
}

///|
test "normalized stage names connect consistently and collide before execution" {
  let text = source()
    .replace(old="id: parent", new="id: e\u0301")
    .replace(old="stage: parent", new="stage: é")
    .replace(old="stage: parent", new="stage: é")
  assert_eq(stages(parsed(text))[0].id, "é")
  assert_eq(
    imports(stages(parsed(text))[1])[0].1,
    Receipt(producer="é", effect="create"),
  )
  assert_true(
    rejected(text.replace(old="id: child", new="id: é"))
    is Structure(DuplicateStage("é"), ..),
  )
  let exports_empty = minimal().replace(
    old="\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}",
    new="\"results\":{}",
  )
  assert_true(
    rejected(exports_empty)
    is Structure(EmptyDeclarations, path=[@source.Key("results")], ..),
  )
}

///|
test "automatic YAML selection supports Core values inside deferred bodies" {
  let text = minimal().replace(old="\"r\":{}", new="\"r\":{\"n\":01}")
  assert_true(
    rejected(text, format=Json) is Parse({ issue: @source.InvalidNumber, .. }),
  )
  let p = parsed(text)
  let root = @wire.open_object(stage_body(stages(p)[0])).unwrap()
  let results = @wire.open_object(@wire.required(root, "results").unwrap()).unwrap()
  let body = @wire.open_object(@wire.required(results, "r").unwrap()).unwrap()
  assert_eq(
    @wire.finite_number(@wire.required(body, "n").unwrap()).unwrap(),
    1.0,
  )
  assert_eq(parse_bytes(@utf8.encode(text), limits()).unwrap().id, p.id)
  // A complete JSON parse must never retry after a stricter owned-tree budget.
  assert_true(
    parse(minimal(), limits(tree_nodes=0))
    is Err(Decode({ kind: @wire.BudgetExceeded, .. })),
  )
}

///|
test "wide stage chains preserve immediate predecessors without recursion" {
  let count = 1000
  let chunks : Array[String] = []
  for i = 0; i < count; i = i + 1 {
    chunks.push(
      "{\"id\":\"s" +
      i.to_string() +
      "\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}",
    )
  }
  let text = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[" +
    chunks.join(",") +
    "],\"results\":{\"out\":{\"from\":{\"stage\":\"s999\",\"result\":\"r\"}}}}"
  let p = parse(text, limits(stage_count=count)).unwrap()
  assert_eq(stages(p).length(), count)
  assert_eq(stages(p)[999].predecessor, Completed("s998"))
  assert_true(
    parse(text, limits(stage_count=count - 1)) is Err(Structure(StageLimit, ..)),
  )
}

///|
test "short-form local inputs remain available to the domain checker" {
  let text = minimal().replace(
    old="\"inputs\":{}",
    new="\"inputs\":{\"rows\":\"relation\",\"g\":\"graph\",\"e\":\"events\",\"v\":\"vectors\"},\"from\":\"rows\"",
  )
  let p = parsed(text)
  assert_eq(imports(stages(p)[0]), [])
  let stage = @wire.open_object(stage_body(stages(p)[0])).unwrap()
  let inputs = @wire.open_object(@wire.required(stage, "inputs").unwrap()).unwrap()
  assert_eq(
    @wire.text(@wire.required(inputs, "rows").unwrap()).unwrap(),
    "relation",
  )
  assert_eq(parsed(text, format=Yaml).id, "p")
}

///|
test "wide declaration maps reuse lookup indexes without changing order" {
  let count = 8000
  let inputs : Array[String] = []
  let results : Array[String] = []
  let effects : Array[String] = []
  let ports : Array[String] = []
  let exposed : Array[String] = []
  for i = 0; i < count; i = i + 1 {
    let suffix = i.to_string()
    inputs.push("\"i" + suffix + "\":{}")
    results.push("\"r" + suffix + "\":{}")
    effects.push("\"e" + suffix + "\":{}")
    ports.push(
      "\"p" +
      suffix +
      "\":{\"result\":{\"stage\":\"producer\",\"result\":\"r" +
      suffix +
      "\"}}",
    )
    ports.push(
      "\"q" +
      suffix +
      "\":{\"receipt\":{\"stage\":\"producer\",\"effect\":\"e" +
      suffix +
      "\"}}",
    )
    exposed.push(
      "\"x" +
      suffix +
      "\":{\"from\":{\"stage\":\"producer\",\"result\":\"r" +
      suffix +
      "\"}}",
    )
  }
  let text = "{\"version\":\"actql/0.1\",\"id\":\"wide\",\"stages\":[" +
    "{\"id\":\"producer\",\"inputs\":{" +
    inputs.join(",") +
    "},\"steps\":[],\"results\":{" +
    results.join(",") +
    "},\"effects\":{" +
    effects.join(",") +
    "}},{\"id\":\"consumer\",\"inputs\":{" +
    ports.join(",") +
    "},\"steps\":[],\"results\":{\"done\":{}}}],\"results\":{" +
    exposed.join(",") +
    "}}"
  let p = parse(
    text,
    limits(bytes=10000000, nodes=300000, tree_nodes=300000, total_bytes=5000000),
  ).unwrap()
  let all = stages(p)
  assert_eq(result_names(all[0]).length(), count)
  assert_eq(effect_names(all[0]).length(), count)
  let imported = imports(all[1])
  assert_eq(imported.length(), count * 2)
  assert_eq(imported[0], ("p0", Result(producer="producer", result="r0")))
  assert_eq(
    imported[count * 2 - 1],
    ("q7999", Receipt(producer="producer", effect="e7999")),
  )
  let exported = exports(p)
  assert_eq(exported.length(), count)
  assert_eq(exported[0], ("x0", "producer", "r0"))
  assert_eq(exported[count - 1], ("x7999", "producer", "r7999"))
}

///|
test "import annotations preserve arbitrary JSON without changing port connections" {
  let text = source()
    .replace(
      old="parents: {receipt: {stage: parent, effect: create}}",
      new="parents: {receipt: {stage: parent, effect: create}, meta: {description: 42, custom: [null, true], nested: {actql_note: ok}}}",
    )
    .replace(
      old="data: {result: {stage: parent, result: rows}}",
      new="data: {result: {stage: parent, result: rows}, meta: {anything: false}}",
    )
  let before = parsed(source())
  let after = parsed(text)
  assert_eq(imports(stages(before)[1]), imports(stages(after)[1]))
  assert_eq(exports(before), exports(after))
  let stage = @wire.open_object(stage_body(stages(after)[1])).unwrap()
  let inputs = @wire.open_object(@wire.required(stage, "inputs").unwrap()).unwrap()
  let input = @wire.open_object(@wire.required(inputs, "parents").unwrap()).unwrap()
  let meta = @wire.open_object(@wire.required(input, "meta").unwrap()).unwrap()
  assert_eq(
    @wire.finite_number(@wire.required(meta, "description").unwrap()).unwrap(),
    42.0,
  )
  for suffix in ["{}", "null", "[]"] {
    let invalid = source().replace(
      old="parents: {receipt: {stage: parent, effect: create}}",
      new="parents: {receipt: {stage: parent, effect: create}, meta: " +
        suffix +
        "}",
    )
    assert_true(parse(invalid, limits()) is Err(_))
  }
  for value in ["true", "null", "[]", "{}"] {
    let invalid = source().replace(
      old="parents: {receipt: {stage: parent, effect: create}}",
      new="parents: {receipt: {stage: parent, effect: create}, meta: {actql_reserved: " +
        value +
        "}}",
    )
    guard rejected(invalid) is Structure(ReservedMetadataKey(key), path~, span~) else {
      fail("expected reserved metadata key classification")
    }
    assert_eq(key, "actql_reserved")
    assert_eq(path, [
      @source.Key("stages"),
      @source.Index(1),
      @source.Key("inputs"),
      @source.Key("parents"),
      @source.Key("meta"),
      @source.Key("actql_reserved"),
    ])
    assert_eq(span.source_path, "program.aql")
  }
  assert_true(
    rejected(
      source().replace(
        old="effect: create",
        new="effect: create, meta: {note: wrong_place}",
      ),
    )
    is Decode(_),
  )
}
