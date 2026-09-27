///|
fn generated_source(
  text : String,
  syntax_limits : Limits,
  yaml? : Bool = false,
) -> @builder.Source {
  let document = @origin.document(
    text,
    syntax_limits.source.max_input_bytes,
    source_path="program.aql",
  ).unwrap()
  let b = @builder.create(document, {
    source: syntax_limits.source,
    tree: syntax_limits.tree,
    max_origin_entries: 100000,
    max_output_bytes: 1000000,
  }).unwrap()
  let parsed = if yaml {
    @source.parse_yaml_measured(
      text,
      syntax_limits.source,
      source_path="program.aql",
    ).unwrap()
  } else {
    @source.parse_json_measured(
      text,
      syntax_limits.source,
      source_path="program.aql",
    ).unwrap()
  }
  @builder.finish(b, @builder.import_parsed(b, parsed).unwrap()).unwrap()
}

///|
fn same_tree(a : @wire.Cursor, b : @wire.Cursor) -> Unit raise {
  let work = [(a, b)]
  while work.pop() is Some((a, b)) {
    assert_eq(@wire.cursor_path(a), @wire.cursor_path(b))
    assert_eq(@wire.cursor_span(a), @wire.cursor_span(b))
    assert_eq(@wire.cursor_key_span(a), @wire.cursor_key_span(b))
    match (@wire.view(a), @wire.view(b)) {
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
        let a_names = @wire.object_field_names(a).unwrap()
        assert_eq(a_names, @wire.object_field_names(b).unwrap())
        for key in a_names {
          work.push(
            (
              @wire.required(a_view, key).unwrap(),
              @wire.required(b_view, key).unwrap(),
            ),
          )
        }
      }
      _ => fail("different source structures")
    }
  }
}

///|
test "generated admission preserves structured fields origins and retained usage" {
  let text =
    #|{"version":"actql/0.1","id":"p","meta":{"note":"é"},"params":{"n":{"type":"number","default":2}},"stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1}]},"as":"rows","meta":{"tag":"step"}}],"effects":{},"results":{"r":{"from":"rows","meta":{"note":"result"}}}}],"results":{"out":{"from":{"stage":"s","result":"r"}}}}
  let parsed = parse(text, limits(), format=Json, source_path="program.aql").unwrap()
  let input = generated_source(text, limits())
  let generated = admit_generated_source(input, limits()).unwrap()
  same_tree(program_body(parsed), program_body(generated))
  assert_eq(program_usage(parsed), program_usage(generated))
  assert_true(@builder.origin(input, program_body(generated)) is Some(_))
  assert_true(@builder.origin(input, program_body(parsed)) is None)
  // YAML metadata, Stage imports, peer Effects and accepted/completed gating
  // retain exactly the existing stage structure and source diagnostics.
  let text = source()
  let parsed = parse(text, limits(), format=Yaml, source_path="program.aql").unwrap()
  let input = generated_source(text, limits(), yaml=true)
  let generated = admit_generated_source(input, limits()).unwrap()
  same_tree(program_body(parsed), program_body(generated))
  assert_eq(program_usage(parsed), program_usage(generated))
}

///|
test "generated Program applies every current reuse limit before envelope decoding" {
  let text = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{\"from\":\"generated\"}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
  let exact = limits(
    bytes=text.length(),
    nodes=16,
    depth=5,
    tree_nodes=16,
    tree_depth=5,
    string_bytes=9,
    total_bytes=85,
    stage_count=1,
  )
  let input = generated_source(text, exact)
  let a = admit_generated_source(input, exact).unwrap()
  assert_eq(
    program_usage(a),
    program_usage(parse(text, exact, format=Json).unwrap()),
  )
  for
    small in [
      limits(bytes=text.length() - 1),
      limits(nodes=15),
      limits(depth=4),
      limits(tree_nodes=15),
      limits(tree_depth=4),
      limits(string_bytes=8),
      limits(total_bytes=84),
      limits(stage_count=0),
      limits(bytes=-1),
    ] {
    assert_true(admit_generated_source(input, small) is Err(_))
    assert_true(parse(text, small, format=Json) is Err(_))
  }
}

///|
test "generated input cannot bypass the ordinary closed Program envelope" {
  for
    text in [
      "{\"version\":\"actql/0.1\",\"id\":\"x\",\"stages\":[],\"results\":{}}", "{\"version\":\"actql/0.1\",\"id\":\"x\",\"inputs\":{},\"stages\":[],\"results\":{}}",
      "{\"version\":\"wrong\",\"id\":\"x\",\"stages\":[],\"results\":{}}",
    ] {
    let input = generated_source(text, limits())
    match
      (
        admit_generated_source(input, limits()),
        parse(text, limits(), format=Json, source_path="program.aql"),
      ) {
      (Err(a), Err(b)) => assert_eq(a, b)
      _ => fail("both entries must reject with the same diagnostic subject")
    }
  }
}
