///|
fn limits() -> Limits {
  {
    frontend: {
      max_tokens: 100000,
      max_syntax_nodes: 100000,
      max_syntax_depth: 128,
      max_literal_bytes: 1000000,
      max_symbol_count: 10000,
      max_generated_steps: 10000,
      max_generated_fields: 100000,
      max_lowering_work: 10000000,
    },
    construction: {
      source: { max_input_bytes: 100000, max_nodes: 10000, max_depth: 64, },
      tree: {
        max_nodes: 10000,
        max_depth: 64,
        max_string_bytes: 10000,
        max_total_string_bytes: 100000,
      },
      max_origin_entries: 20000,
      max_output_bytes: 100000,
    },
    max_stages: 32,
  }
}

///|
fn same_values(a : @decode.Cursor, b : @decode.Cursor) -> Unit raise {
  let work = [(a, b)]
  while work.pop() is Some((a, b)) {
    match (@decode.view(a), @decode.view(b)) {
      (NullValue, NullValue) => ()
      (BoolValue(a), BoolValue(b)) => assert_eq(a, b)
      (NumberValue(a), NumberValue(b)) => assert_eq(a, b)
      (TextValue(a), TextValue(b)) => assert_eq(a, b)
      (ArrayValue(a), ArrayValue(b)) => {
        assert_eq(a.length(), b.length())
        for i in 0..<a.length() {
          work.push((a[i], b[i]))
        }
      }
      (ObjectValue(a_view), ObjectValue(b_view)) => {
        let names = @decode.object_field_names(a).unwrap()
        assert_eq(
          names.length(),
          @decode.object_field_names(b).unwrap().length(),
        )
        for name in names {
          work.push(
            (
              @decode.lookup(a_view, name).unwrap(),
              @decode.lookup(b_view, name).unwrap(),
            ),
          )
        }
      }
      _ => fail("different retained Program structure")
    }
  }
}

///|
test "structural envelope enters normal admission without dropping source structure" {
  let text =
    #|AQL '0.1';
    #|PROGRAM 'p' {
    #|  META {"note":"é😀"};
    #|  PARAMS {"n":{"type":"number","default":2}};
    #|  STAGE s {
    #|    STEP {"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1}]},"as":"rows","meta":{"tag":"step"}};
    #|    EFFECTS {};
    #|    RESULT r = {"from":"rows","meta":{"note":"result"}};
    #|  }
    #|  RESULT out = {"from":{"stage":"s","result":"r"}};
    #|}
  let expected =
    #|{"version":"actql/0.1","id":"p","meta":{"note":"é😀"},"params":{"n":{"type":"number","default":2}},"stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1}]},"as":"rows","meta":{"tag":"step"}}],"effects":{},"results":{"r":{"from":"rows","meta":{"note":"result"}}}}],"results":{"out":{"from":{"stage":"s","result":"r"}}}}
  let parsed = parse(text, limits(), source_path="program.aql").unwrap()
  let ordinary = @syntax.parse(
    expected,
    {
      source: limits().construction.source,
      tree: limits().construction.tree,
      max_stages: 32,
    },
    format=Json,
  ).unwrap()
  same_values(
    @syntax.program_body(program(parsed)),
    @syntax.program_body(ordinary),
  )
  let root = @decode.open_object(@syntax.program_body(program(parsed))).unwrap()
  let meta = @decode.required(root, "meta").unwrap()
  let note = @decode.required(@decode.open_object(meta).unwrap(), "note").unwrap()
  let o = @builder.origin(source(parsed), note).unwrap()
  assert_eq(@origin.kind(o), @origin.Authored)
  assert_eq(@origin.span(o).start_line, 3)
  assert_eq(@origin.span(o).source_path, "program.aql")
  assert_eq(@origin.end(o).utf16_offset - @origin.start(o).utf16_offset, 6)
}

///|
test "structural declarations and strict JSON fail without publishing a Program" {
  let prefix = "AQL '0.1'; PROGRAM 'p' { "
  let suffix = " STAGE s { RESULT r = {\"from\":\"x\"}; } RESULT r = {\"from\":{\"stage\":\"s\",\"result\":\"r\"}}; }"
  for
    body in [
      "META {\"a\":1,\"a\":2};", "META {\"é\":1,\"é\":2};", "META {\"a\":1}; META {\"b\":2};",
      "META {unquoted:1};", "META {/* comment */\"a\":1};", "META {\"a\":-0};", "META {\"a\":1,};",
      "PARAMS {};", "BINDINGS {};", "UNKNOWN {};",
    ] {
    assert_true(parse(prefix + body + suffix, limits()) is Err(_), msg=body)
  }
  for
    text in [
      "AQL '0.2'; PROGRAM 'p' {}", "AQL '0.1'; PROGRAM p {}", "AQL '0.1'; PROGRAM 'p' {} trailing",
      "AQL '0.1'; PROGRAM 'p' {",
    ] {
    assert_true(parse(text, limits()) is Err(_), msg=text)
  }
}

///|
test "formatter roundtrip retains explicit steps Effects metadata and stage order" {
  let expected =
    #|{"version":"actql/0.1","id":"p'😀","meta":{"control":"\u0001","nested":{"meta":null}},"bindings":{"ref":{"kind":"resource","resource_kind":"table"}},"stages":[{"id":"first","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"unused","meta":{"note":"exact"}},{"derive":{"old":"concat(null, \"x\")"}}],"results":{"r":{"from":"unused"}},"effects":{"write":{"kind":"mapping","source":{"result":"r"},"contract_ref":"mapping","failure_policy":"stop","meta":{"label":"effect"}}}},{"id":"second","after":"accepted","inputs":{"prior":{"from":{"stage":"first","result":"r"}}},"from":"prior","steps":[],"results":{"r":{"from":"prior"}},"effects":{}}],"results":{"r":{"from":{"stage":"second","result":"r"}}}}
  let ordinary = @syntax.parse(
    expected,
    {
      source: limits().construction.source,
      tree: limits().construction.tree,
      max_stages: 32,
    },
    format=Json,
  ).unwrap()
  let printed = format(ordinary, 100000).unwrap()
  let roundtrip = parse(printed, limits()).unwrap()
  same_values(
    @syntax.program_body(ordinary),
    @syntax.program_body(program(roundtrip)),
  )
  assert_eq(format(program(roundtrip), 100000).unwrap(), printed)
  let bytes = @origin.input_bytes(@origin.document(printed, 100000).unwrap())
  assert_eq(format(ordinary, bytes).unwrap(), printed)
  assert_true(format(ordinary, bytes - 1) is Err(_))
  assert_true(format(ordinary, -1) is Err(_))
}

///|
test "structural source and output limits reject rather than truncate" {
  let text = "AQL '0.1'; PROGRAM 'p' { STAGE s { RESULT r = {\"from\":\"x\"}; } RESULT r = {\"from\":{\"stage\":\"s\",\"result\":\"r\"}}; }"
  let large = limits()
  let parsed = parse(text, large).unwrap()
  let bytes = @origin.input_bytes(@origin.document(text, 100000).unwrap())
  let exact = {
    ..large,
    construction: {
      ..large.construction,
      source: { ..large.construction.source, max_input_bytes: bytes, },
      max_output_bytes: @builder.output_bytes(source(parsed)),
    },
  }
  assert_true(parse(text, exact) is Ok(_))
  assert_true(
    parse(text, {
      ..exact,
      construction: {
        ..exact.construction,
        source: { ..exact.construction.source, max_input_bytes: bytes - 1, },
      },
    })
    is Err(_),
  )
  assert_true(
    parse(text, {
      ..exact,
      construction: {
        ..exact.construction,
        max_output_bytes: exact.construction.max_output_bytes - 1,
      },
    })
    is Err(_),
  )
  assert_true(parse(text, { ..large, max_stages: 0, }) is Err(_))
  assert_true(
    parse(text, {
      ..large,
      construction: {
        ..large.construction,
        source: { ..large.construction.source, max_nodes: 2, },
      },
    })
    is Err(_),
  )
  assert_true(
    parse(text, {
      ..large,
      construction: {
        ..large.construction,
        tree: { ..large.construction.tree, max_depth: 1, },
      },
    })
    is Err(_),
  )
}

///|
test "native DATA maps generators and explicit sources into existing steps" {
  let text =
    #|AQL '0.1'; PROGRAM 'native' {
    #|  STAGE s {
    #|    DATA rows = OP values {"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":2},{"x":1}]};
    #|    DATA kept = FROM rows |> OP filter "x > 1";
    #|    RESULT r = {"from":"kept"};
    #|  }
    #|  RESULT r = {"from":{"stage":"s","result":"r"}};
    #|}
  let expected =
    #|{"version":"actql/0.1","id":"native","stages":[{"id":"s","inputs":{},"steps":[{"as":"rows","values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":2},{"x":1}]}},{"from":"rows","filter":"x > 1","as":"kept"}],"results":{"r":{"from":"kept"}}}],"results":{"r":{"from":{"stage":"s","result":"r"}}}}
  let parsed = parse(text, limits()).unwrap()
  let ordinary = @syntax.parse(
    expected,
    {
      source: limits().construction.source,
      tree: limits().construction.tree,
      max_stages: 32,
    },
    format=Json,
  ).unwrap()
  same_values(
    @syntax.program_body(program(parsed)),
    @syntax.program_body(ordinary),
  )
  let printed = format(program(parsed), 100000).unwrap()
  same_values(
    @syntax.program_body(program(parse(printed, limits()).unwrap())),
    @syntax.program_body(ordinary),
  )
  for op in ["unknown", "VALUES", "provider_command"] {
    let invalid = "AQL '0.1'; PROGRAM 'p' { STAGE s { DATA x = OP " +
      op +
      " {}; RESULT r = {\"from\":\"x\"}; } RESULT r = {\"from\":{\"stage\":\"s\",\"result\":\"r\"}}; }"
    assert_true(parse(invalid, limits()) is Err(_), msg=op)
  }
}

///|
fn ordinary_program(text : String) -> @syntax.Program {
  @syntax.parse(
    text,
    {
      source: limits().construction.source,
      tree: limits().construction.tree,
      max_stages: 32,
    },
    format=Json,
  ).unwrap()
}

///|
fn identity_projection(p : @syntax.Program) -> String raise {
  let writer = @encode.writer(100000, 10000, 128)
  @syntax.emit_metadata_stripped_program(p, writer)
  @sha.text_hex(@encode.finish(writer)).unwrap()
}

///|
test "Program IDs and Effect names retain their canonical identity significance" {
  let original =
    #|{"version":"actql/0.1","id":"identity","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1}]},"as":"x"}],"results":{"r":{"from":"x"}},"effects":{"write":{"kind":"mapping","source":{"result":"r"},"contract_ref":"mapping","failure_policy":"stop"}}}],"results":{"r":{"from":{"stage":"s","result":"r"}}}}
  let original_cid = identity_projection(ordinary_program(original))
  for
    changed in [
      original.replace(old="\"id\":\"identity\"", new="\"id\":\"different\""),
      original.replace(old="\"write\":", new="\"other\":"),
    ] {
    let expected = ordinary_program(changed)
    let actual = program(
      parse(format(expected, 100000).unwrap(), limits()).unwrap(),
    )
    assert_eq(identity_projection(actual), identity_projection(expected))
    assert_true(identity_projection(actual) != original_cid)
  }
}

///|
test "existing literal SELECT structure is preserved without a new SQL frontend" {
  let compiled = @actsql.compile_literal_select(
    "SELECT 1 AS id, -2 AS debt;",
    "literal-query-1",
    { max_source_bytes: 256, max_columns: 8, max_program_bytes: 4096, },
  ).unwrap()
  // Independent pre-existing golden from the literal SELECT regression.
  let expected =
    #|{"version":"actql/0.1","id":"literal-query-1","stages":[{"id":"sql_source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"debt":{"type":"number","nullable":false}},"rows":[{"id":1,"debt":-2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","debt"]}}}],"results":{"answer":{"from":{"stage":"sql_source","result":"rows"}}}}
  let actual = program(
    parse(
      format(ordinary_program(compiled.document), 100000).unwrap(),
      limits(),
    ).unwrap(),
  )
  same_values(
    @syntax.program_body(actual),
    @syntax.program_body(ordinary_program(expected)),
  )
  assert_eq(
    identity_projection(actual),
    identity_projection(ordinary_program(expected)),
  )
}

///|
test "legacy YAML expression trees and explicit completed gating roundtrip" {
  let yaml =
    #|version: actql/0.1
    #|id: legacy
    #|params:
    #|  threshold:
    #|    type: number
    #|    default: 2
    #|stages:
    #|  - id: first
    #|    inputs:
    #|      rows:
    #|        carrier: relation
    #|        schema:
    #|          x: {type: number, nullable: false}
    #|    steps:
    #|      - filter: {gte: [{field: x}, {$param: threshold}]}
    #|        as: selected
    #|    results:
    #|      out: {from: selected}
    #|  - id: second
    #|    after: completed
    #|    inputs:
    #|      rows: {result: {stage: first, result: out}}
    #|    steps: []
    #|    results:
    #|      out: {from: rows}
    #|results:
    #|  out: {from: {stage: second, result: out}}
  let original = @syntax.parse(
    yaml,
    {
      source: limits().construction.source,
      tree: limits().construction.tree,
      max_stages: 32,
    },
    format=Yaml,
  ).unwrap()
  let expected =
    #|{"version":"actql/0.1","id":"legacy","params":{"threshold":{"type":"number","default":2}},"stages":[{"id":"first","inputs":{"rows":{"carrier":"relation","schema":{"x":{"type":"number","nullable":false}}}},"steps":[{"filter":{"gte":[{"field":"x"},{"$param":"threshold"}]},"as":"selected"}],"results":{"out":{"from":"selected"}}},{"id":"second","after":"completed","inputs":{"rows":{"result":{"stage":"first","result":"out"}}},"steps":[],"results":{"out":{"from":"rows"}}}],"results":{"out":{"from":{"stage":"second","result":"out"}}}}
  let text = format(original, 100000).unwrap()
  same_values(
    @syntax.program_body(program(parse(text, limits()).unwrap())),
    @syntax.program_body(ordinary_program(expected)),
  )
}

///|
test "nonfinite JSON numbers and raw transport operations are not admitted" {
  for body in ["NaN", "Infinity", "-Infinity", "1e99999"] {
    let text = "AQL '0.1'; PROGRAM 'p' { STAGE s { DATA x = OP values " +
      body +
      "; RESULT r = {\"from\":\"x\"}; } RESULT r = {\"from\":{\"stage\":\"s\",\"result\":\"r\"}}; }"
    assert_true(parse(text, limits()) is Err(_))
  }
  for op in ["http", "fetch", "wasm"] {
    let text = "AQL '0.1'; PROGRAM 'p' { STAGE s { DATA x = OP " +
      op +
      " {}; RESULT r = {\"from\":\"x\"}; } RESULT r = {\"from\":{\"stage\":\"s\",\"result\":\"r\"}}; }"
    assert_true(parse(text, limits()) is Err(_))
  }
}

///|
test "native chains and aliases preserve explicit computation without identity steps" {
  let text =
    #|AQL '0.1'; PROGRAM 'chain' {
    #| STAGE s {
    #|  DATA kept = OP values {"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":2},{"x":1}]}
    #|    |> OP filter "x > 1" |> OP select ["x"];
    #|  DATA alias = FROM kept;
    #|  DATA again = FROM alias;
    #|  STEP {"from":"again","join":{"with":"alias","on":"left.x = right.x"},"as":"joined","meta":{"from":"again"}};
    #|  RESULT r = {"from":"again","meta":{"from":"alias"}};
    #| }
    #| RESULT r = {"from":{"stage":"s","result":"r"}};
    #|}
  let expected =
    #|{"version":"actql/0.1","id":"chain","stages":[{"id":"s","inputs":{},"steps":[{"as":"__aql_native_0","values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":2},{"x":1}]}},{"filter":"x > 1"},{"select":["x"],"as":"kept"},{"from":"kept","join":{"with":"kept","on":"left.x = right.x"},"as":"joined","meta":{"from":"again"}}],"results":{"r":{"from":"kept","meta":{"from":"alias"}}}}],"results":{"r":{"from":{"stage":"s","result":"r"}}}}
  let parsed = parse(text, limits()).unwrap()
  same_values(
    @syntax.program_body(program(parsed)),
    @syntax.program_body(ordinary_program(expected)),
  )
  let printed = format(program(parsed), 100000).unwrap()
  same_values(
    @syntax.program_body(program(parse(printed, limits()).unwrap())),
    @syntax.program_body(ordinary_program(expected)),
  )
}

///|
test "generated names avoid later declarations and authored reference targets" {
  let text =
    #|AQL '0.1'; PROGRAM 'p' { STAGE s {
    #| DATA out = OP values {"schema":{"x":{"type":"number","nullable":false}},"rows":[]} |> OP take 0;
    #| STEP {"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[]},"as":"__aql_native_0"};
    #| RESULT r = {"from":"__aql_native_1"};
    #| } RESULT r = {"from":{"stage":"s","result":"r"}}; }
  let parsed = parse(text, limits()).unwrap()
  let stage = @syntax.stage_body(@syntax.stages(program(parsed))[0])
  let steps = @decode.required(@decode.open_object(stage).unwrap(), "steps").unwrap()
  let first = @decode.element_at(steps, 0).unwrap()
  assert_eq(
    @decode.text(
      @decode.required(@decode.open_object(first).unwrap(), "as").unwrap(),
    ).unwrap(),
    "__aql_native_2",
  )
  // The authored missing reference remains missing for the ordinary checker.
  // It does not become bound to a frontend helper by accident.
}

///|
test "DATA rejects self forward duplicate and implicit previous-current sources" {
  let prefix = "AQL '0.1'; PROGRAM 'p' { STAGE s { "
  let suffix = " RESULT r = {\"from\":\"x\"}; } RESULT r = {\"from\":{\"stage\":\"s\",\"result\":\"r\"}}; }"
  for
    declarations in [
      "DATA x = FROM x;", "DATA x = FROM y; DATA y = OP values {};", "DATA x = OP values {}; DATA x = FROM x;",
      "DATA x = OP values {}; DATA y = OP filter true;", "DATA x = OP values {} |> OP values {};",
      "DATA x = OP graph {\"id\":\"id\"};", "INPUT x = {}; DATA x = OP values {};",
    ] {
    assert_true(
      parse(prefix + declarations + suffix, limits()) is Err(_),
      msg=declarations,
    )
  }
}

///|
test "frontend accounting applies to the whole source with exact resource boundaries" {
  let text =
    #|/* work before tokens */ AQL '0.1'; PROGRAM 'p' { STAGE s {
    #| DATA x = OP values {"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":2}]} |> OP filter "x > 0";
    #| DATA y = FROM x; DATA z = FROM y;
    #| RESULT r = {"from":"z"};
    #| } RESULT r = {"from":{"stage":"s","result":"r"}}; }
  let large = limits()
  let measured = parse(text, large).unwrap()
  let exact : FrontendLimits = {
    max_tokens: usage(measured, Tokens),
    max_syntax_nodes: usage(measured, SyntaxNodes),
    max_syntax_depth: usage(measured, SyntaxDepth),
    max_literal_bytes: usage(measured, LiteralBytes),
    max_symbol_count: usage(measured, Symbols),
    max_generated_steps: usage(measured, GeneratedSteps),
    max_generated_fields: usage(measured, GeneratedFields),
    max_lowering_work: usage(measured, LoweringWork),
  }
  assert_true(parse(text, { ..large, frontend: exact, }) is Ok(_))
  for
    small in [
      { ..exact, max_tokens: exact.max_tokens - 1, },
      { ..exact, max_syntax_nodes: exact.max_syntax_nodes - 1, },
      { ..exact, max_syntax_depth: exact.max_syntax_depth - 1, },
      { ..exact, max_literal_bytes: exact.max_literal_bytes - 1, },
      { ..exact, max_symbol_count: exact.max_symbol_count - 1, },
      { ..exact, max_generated_steps: exact.max_generated_steps - 1, },
      { ..exact, max_generated_fields: exact.max_generated_fields - 1, },
      { ..exact, max_lowering_work: exact.max_lowering_work - 1, },
    ] {
    assert_true(parse(text, { ..large, frontend: small, }) is Err(_))
  }
  assert_true(
    parse(text, { ..large, frontend: { ..exact, max_tokens: -1, }, }) is Err(_),
  )
  assert_true(
    parse("/* additional traversal */" + text, { ..large, frontend: exact, })
    is Err(_),
  )
}

///|
test "syntax admission diagnostics retain original body positions" {
  let text =
    #|AQL '0.1';
    #|PROGRAM 'p' {
    #|  META {};
    #|  STAGE s { RESULT r = {"from":"x"}; }
    #|  RESULT r = {"from":{"stage":"s","result":"r"}};
    #|}
  match parse(text, limits(), source_path="original.aql") {
    Err(diagnostic) => {
      assert_eq(diagnostic.span.unwrap().start_line, 3)
      assert_eq(diagnostic.span.unwrap().source_path, "original.aql")
    }
    _ => fail("empty metadata must retain the existing rejection")
  }
  assert_true(parse_bytes(b"\xff", limits()) is Err(_))
}

///|
test "invalid scalar input and unsupported root metadata retain admission rejection" {
  let invalid = String::from_array([(0xd800).unsafe_to_char()])
  assert_true(parse(invalid, limits()) is Err(_))
  let text =
    #|AQL '0.1'; PROGRAM 'p' { STAGE s {
    #| STEP {"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[]},"as":"x"};
    #| RESULT r = {"from":"x"};
    #| } RESULT r = {"from":{"stage":"s","result":"r"},"meta":{"note":"unsupported"}}; }
  assert_true(parse(text, limits()) is Err(_))
}

///|
test "self import and missing exported Results fail normal structural admission" {
  let self_import =
    #|AQL '0.1'; PROGRAM 'self' { STAGE s {
    #| INPUT rows = {"result":{"stage":"s","result":"r"}};
    #| RESULT r = {"from":"rows"};
    #| } RESULT r = {"from":{"stage":"s","result":"r"}}; }
  match parse(self_import, limits(), source_path="self.aql") {
    Err(diagnostic) => {
      assert_true(diagnostic.issue is Admission(_))
      let span = diagnostic.span.unwrap()
      assert_eq(span.source_path, "self.aql")
      assert_eq(span.start_line, 2)
    }
    _ => fail("a stage cannot import its own Result")
  }
  assert_true(
    parse(
      "AQL '0.1'; PROGRAM 'p' { STAGE s { RESULT r = {\"from\":\"x\"}; } }",
      limits(),
    )
    is Err(_),
  )
}

///|
test "quoted structural keywords remain ordinary names and trivia preserves structure" {
  let text =
    #|AQL '0.1'; PROGRAM 'p' { STAGE `STAGE` {
    #| STEP {"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[]},"as":"x"};
    #| RESULT `RESULT` = {"from":"x"};
    #| } RESULT `DATA` = {"from":{"stage":"STAGE","result":"RESULT"}}; }
  let expected =
    #|{"version":"actql/0.1","id":"p","stages":[{"id":"STAGE","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[]},"as":"x"}],"results":{"RESULT":{"from":"x"}}}],"results":{"DATA":{"from":{"stage":"STAGE","result":"RESULT"}}}}
  let parsed = parse(text, limits()).unwrap()
  same_values(
    @syntax.program_body(program(parsed)),
    @syntax.program_body(ordinary_program(expected)),
  )
  let decorated = "\u{feff}-- leading comment\r\n/* nonsemantic */ " +
    text +
    "\n-- trailing comment"
  same_values(
    @syntax.program_body(program(parse(decorated, limits()).unwrap())),
    @syntax.program_body(program(parsed)),
  )
  assert_true(
    parse("AQL '0.1'; PROGRAM 'p' { STAGE STAGE {} }", limits()) is Err(_),
  )
}
