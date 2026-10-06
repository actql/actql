///|
fn effect_key_source(effects : String, format : Format) -> String {
  if format == Json {
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}},\"effects\":" +
    effects +
    "}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
  } else {
    "version: actql/0.1\nid: p\nstages:\n- id: s\n  inputs: {}\n  steps: []\n  results: {r: {}}\n  effects: " +
    effects +
    "\nresults: {out: {from: {stage: s, result: r}}}"
  }
}

///|
fn effect_key_declaration(
  kind : String,
  slot : String,
  payload : String,
) -> String {
  "{\"e\\u0301\":{\"" +
  kind +
  "\":{\"" +
  slot +
  "\":{\"n\\u0301\":{\"literal\":" +
  payload +
  "}}}}}"
}

///|
fn effect_key_member(cursor : @wire.Cursor, name : String) -> @wire.Cursor {
  @wire.lookup(@wire.open_object(cursor).unwrap(), name).unwrap()
}

///|
fn effect_key_payload(
  program : Program,
  kind : String,
  slot : String,
) -> @wire.Cursor raise {
  let effects = effect_key_member(stage_body(stages(program)[0]), "effects")
  assert_eq(@wire.field_at(effects, 0).unwrap().0, "é")
  let fields = effect_key_member(
    effect_key_member(effect_key_member(effects, "é"), kind),
    slot,
  )
  assert_eq(@wire.field_at(fields, 0).unwrap().0, "ń")
  effect_key_member(effect_key_member(fields, "ń"), "literal")
}

///|
test "Program Effect literal payload keys retain exact Unicode and line endings in JSON and YAML" {
  let payload =
    #|{"e\u0301":1,"é":2,"line\r":3,"line\n":4,"line\r\n":5,"nested":[{"e\u0301":6,"é":7}],"$json":{"$param":"data","literal":"business"}}
  let keys = [
    "e\u0301", "é", "line\r", "line\n", "line\r\n", "nested", "$json",
  ]
  for
    (kind, slot) in [("update", "set"), ("upsert", "set"), ("command", "input")] {
    for format in [Format::Json, Format::Yaml] {
      let text = effect_key_source(
        effect_key_declaration(kind, slot, payload),
        format,
      )
      for
        program in [
          parse(text, limits(), format~, source_path="effect.aql").unwrap(),
          parse_bytes(
            @utf8.encode(text),
            limits(),
            format~,
            source_path="effect.aql",
          ).unwrap(),
        ] {
        let actual = effect_key_payload(program, kind, slot)
        assert_eq(@wire.object_field_names(actual).unwrap(), keys)
        let nested = @wire.element_at(effect_key_member(actual, "nested"), 0).unwrap()
        assert_eq(@wire.object_field_names(nested).unwrap(), ["e\u0301", "é"])
        let writer = @encode.writer(10000, 1000, 30)
        emit_program_source(program, writer)
        let roundtrip = parse(@encode.finish(writer), limits(), format=Json).unwrap()
        assert_eq(
          @wire.object_field_names(effect_key_payload(roundtrip, kind, slot)).unwrap(),
          keys,
        )
      }
    }
  }
}

///|
test "Program Effect payload retention leaves structural name collisions rejected" {
  for
    effects in [
      "{\"é\":{\"update\":{}},\"e\\u0301\":{\"update\":{}}}", "{\"e\":{\"update\":{\"set\":{\"é\":{\"literal\":1},\"e\\u0301\":{\"literal\":2}}}}}",
      "{\"e\":{\"command\":{\"input\":{\"line\\r\":{\"literal\":1},\"line\\n\":{\"literal\":2}}}}}",
    ] {
    for format in [Format::Json, Format::Yaml] {
      let text = effect_key_source(effects, format)
      assert_true(
        parse(text, limits(), format~)
        is Err(Parse({ issue: DuplicateKey(_), .. })),
      )
      assert_true(
        parse_bytes(@utf8.encode(text), limits(), format~)
        is Err(Parse({ issue: DuplicateKey(_), .. })),
      )
    }
  }
}

///|
test "Program Effect retention is anchored to exact set and input literal positions" {
  let collision = "{\"é\":1,\"e\\u0301\":2}"
  for
    effects in [
      "{\"e\":{\"create\":{\"payload\":{\"literal\":" + collision + "}}}}",
      effect_key_declaration("update", "input", collision),
      effect_key_declaration("command", "set", collision),
      "{\"e\":{\"update\":{\"set\":{\"x\":{\"typed_literal\":" +
      collision +
      "}}}}}",
      "{\"e\":{\"meta\":{\"stages\":[{\"effects\":" +
      effect_key_declaration("update", "set", collision) +
      "}]}}}",
    ] {
    for format in [Format::Json, Format::Yaml] {
      assert_true(
        parse(effect_key_source(effects, format), limits(), format~)
        is Err(Parse({ issue: DuplicateKey("é"), .. })),
      )
    }
  }
  let values = minimal().replace(
    old="\"steps\":[]",
    new="\"steps\":[{\"values\":{\"rows\":[{\"x\":{\"literal\":" +
      collision +
      "}}]}}]",
  )
  let expression = minimal().replace(
    old="\"steps\":[]",
    new="\"steps\":[{\"derive\":{\"x\":{\"literal\":" + collision + "}}}]",
  )
  for text in [values, expression] {
    for format in [Format::Json, Format::Yaml] {
      assert_true(
        parse(text, limits(), format~)
        is Err(Parse({ issue: DuplicateKey("é"), .. })),
      )
    }
  }
}

///|
test "Program Effect exact duplicate rejection keeps decoded paths and original key spans" {
  for format in [Format::Json, Format::Yaml] {
    let text = effect_key_source(
      effect_key_declaration("update", "set", "{\"e\\u0301\":1,\"é\":2}"),
      format,
    )
    let error = parse(text, limits(), format~, source_path="effect.aql").unwrap_err()
    guard error is Parse(error) else { fail("expected parse error") }
    assert_eq(error.issue, @source.DuplicateKey("e\u0301"))
    assert_eq(
      error.path,
      Some([
        @source.Key("stages"),
        @source.Index(0),
        @source.Key("effects"),
        @source.Key("é"),
        @source.Key("update"),
        @source.Key("set"),
        @source.Key("ń"),
        @source.Key("literal"),
        @source.Key("e\u0301"),
      ]),
    )
    guard error.location is @source.Source(span) else {
      fail("expected key span")
    }
    assert_eq(span.source_path, "effect.aql")
    assert_eq(
      @utf8.decode(@utf8.encode(text)[span.start_byte:span.end_byte]),
      "\"é\"",
    )
    assert_eq(
      parse_bytes(
        @utf8.encode(text),
        limits(),
        format~,
        source_path="effect.aql",
      ).unwrap_err(),
      Parse(error),
    )
  }
}

///|
test "Program Effect retained payload keys use ordinary bounded admission" {
  for format in [Format::Json, Format::Yaml] {
    let text = effect_key_source(
      effect_key_declaration("update", "set", "{\"e\\u0301\":1,\"é\":2}"),
      format,
    )
    let program = parse(text, limits(), format~).unwrap()
    let usage = program_usage(program)
    let exact = limits(
      bytes=usage.source.input_bytes,
      nodes=usage.source.nodes,
      depth=usage.source.depth,
      tree_nodes=usage.tree.nodes,
      tree_depth=usage.tree.depth,
      string_bytes=usage.tree.largest_string_bytes,
      total_bytes=usage.tree.total_string_bytes,
    )
    assert_true(parse(text, exact, format~) is Ok(_))
    assert_true(parse_bytes(@utf8.encode(text), exact, format~) is Ok(_))
    assert_true(
      parse(
        text,
        {
          ..exact,
          source: {
            ..exact.source,
            max_input_bytes: usage.source.input_bytes - 1,
          },
        },
        format~,
      )
      is Err(_),
    )
    assert_true(
      parse(
        text,
        {
          ..exact,
          source: { ..exact.source, max_nodes: usage.source.nodes - 1, },
        },
        format~,
      )
      is Err(_),
    )
    assert_true(
      parse(
        text,
        {
          ..exact,
          source: { ..exact.source, max_depth: usage.source.depth - 1, },
        },
        format~,
      )
      is Err(_),
    )
    assert_true(
      parse(
        text,
        {
          ..exact,
          tree: {
            ..exact.tree,
            max_total_string_bytes: usage.tree.total_string_bytes - 1,
          },
        },
        format~,
      )
      is Err(_),
    )
    for payload in ["{\"\\ud800\":1}", "{\"\\udc00\":1}"] {
      let malformed = effect_key_source(
        effect_key_declaration("update", "set", payload),
        format,
      )
      assert_true(parse(malformed, limits(), format~) is Err(_))
      assert_true(
        parse_bytes(@utf8.encode(malformed), limits(), format~) is Err(_),
      )
    }
  }
}
