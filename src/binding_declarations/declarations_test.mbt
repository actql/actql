///|
fn parsed(bindings : String) -> @stage.Program {
  @stage.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\"" +
    bindings +
    ",\"stages\":[{\"id\":\"a\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
    {
      source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 20000, },
      tree: {
        max_nodes: 100000,
        max_depth: 20000,
        max_string_bytes: 1000000,
        max_total_string_bytes: 1000000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
}

///|
fn caps() -> Limits {
  { max_bindings: 100, max_work: 1000000, }
}

///|
fn rendered(value : Declaration) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(10000, 100, 10)
  emit_declaration(value, writer)
  @encode.finish(writer)
}

///|
test "opaque declarations keep the source Program and distinct reference constraints" {
  let p = parsed(
    (
      #|,"bindings":{"z":{"type":"artifact_ref"},"a":{"type":"resource_ref","resource_kind":"drive.file","meta":{"note":"keep for diagnostics"}},"b":{"type":"artifact_ref","media_type":"application/pdf"}}
    ),
  )
  let ds = prepare(p, caps()).unwrap()
  assert_true(physical_equal(program(ds), p))
  assert_eq(count(ds), 3)
  assert_eq(at(ds, 0).unwrap().name, "a")
  assert_eq(at(ds, 1).unwrap().name, "b")
  assert_eq(at(ds, 2).unwrap().name, "z")
  assert_eq(find(ds, "a").unwrap().constraint, Resource("drive.file"))
  assert_eq(
    find(ds, "b").unwrap().constraint,
    Artifact(Some("application/pdf")),
  )
  assert_eq(find(ds, "z").unwrap().constraint, Artifact(None))
  assert_true(find(ds, "missing") is None)
  assert_true(find(ds, "A") is None)
  assert_true(at(ds, -1) is None)
  assert_true(at(ds, 3) is None)
  assert_eq(@decode.cursor_path(source(find(ds, "a").unwrap())), [
    Key("bindings"),
    Key("a"),
  ])
  assert_true(
    @decode.lookup(
      @decode.open_object(source(find(ds, "a").unwrap())).unwrap(),
      "meta",
    )
    is Some(_),
  )
  assert_eq(
    rendered(find(ds, "a").unwrap()),
    "{\"resource_kind\":\"drive.file\",\"type\":\"resource_ref\"}",
  )
  assert_eq(
    rendered(find(ds, "b").unwrap()),
    "{\"media_type\":\"application/pdf\",\"type\":\"artifact_ref\"}",
  )
  assert_eq(rendered(find(ds, "z").unwrap()), "{\"type\":\"artifact_ref\"}")
  assert_true(prepare(p, { ..caps(), max_work: work(ds), }) is Ok(_))
  assert_true(
    prepare(p, { ..caps(), max_work: work(ds) - 1, }) is Err(WorkLimit),
  )
  assert_true(prepare(p, { ..caps(), max_bindings: 2, }) is Err(BindingLimit))
}

///|
test "binding declarations are closed and cannot introduce parameter defaults or nullability" {
  for
    declaration in [
      "{\"type\":\"number\"}", "{\"type\":\"resource_ref\"}", "{\"type\":\"resource_ref\",\"resource_kind\":\"\"}",
      "{\"type\":\"resource_ref\",\"resource_kind\":null}", "{\"type\":\"artifact_ref\",\"media_type\":\"\"}",
      "{\"type\":\"artifact_ref\",\"media_type\":null}", "{\"type\":\"artifact_ref\",\"nullable\":false}",
      "{\"type\":\"artifact_ref\",\"default\":null}", "{\"type\":\"artifact_ref\",\"resource_kind\":\"x\"}",
      "null", "[]", "{}",
    ] {
    assert_true(
      prepare(parsed(",\"bindings\":{\"x\":" + declaration + "}"), caps())
      is Err(_),
    )
  }
  for name in ["1x", "x-y", "é", "x y"] {
    assert_true(
      prepare(
        parsed(",\"bindings\":{\"" + name + "\":{\"type\":\"artifact_ref\"}}"),
        caps(),
      )
      is Err(InvalidName(_)),
    )
  }
  assert_true(
    prepare(
      parsed(",\"bindings\":{\"_x1\":{\"type\":\"artifact_ref\"}}"),
      caps(),
    )
    is Ok(_),
  )
  let absent = prepare(parsed(""), { max_bindings: 0, max_work: 1, }).unwrap()
  assert_eq(count(absent), 0)
  assert_eq(work(absent), 1)
  assert_true(
    prepare(parsed(""), { max_bindings: -1, max_work: 1, })
    is Err(InvalidLimits),
  )
}

///|
test "binding annotation admission is bounded without recursive traversal" {
  for meta in ["{}", "null", "[]", "{\"actql_reserved\":true}"] {
    assert_true(
      prepare(
        parsed(
          ",\"bindings\":{\"x\":{\"type\":\"artifact_ref\",\"meta\":" +
          meta +
          "}}",
        ),
        caps(),
      )
      is Err(InvalidMetadata(_)),
    )
  }
  let deep = "[".repeat(10000) + "{\"actql_nested\":true}" + "]".repeat(10000)
  let p = parsed(
    ",\"bindings\":{\"x\":{\"type\":\"artifact_ref\",\"meta\":{\"data\":" +
    deep +
    "}}}",
  )
  let ds = prepare(p, caps()).unwrap()
  assert_eq(rendered(at(ds, 0).unwrap()), "{\"type\":\"artifact_ref\"}")
  assert_true(
    prepare(p, { ..caps(), max_work: work(ds) - 1, }) is Err(WorkLimit),
  )
}

///|
test "annotation-free binding output shares enclosing sink limits" {
  let ds = prepare(
    parsed(
      ",\"bindings\":{\"x\":{\"type\":\"resource_ref\",\"resource_kind\":\"é😀\"}}",
    ),
    caps(),
  ).unwrap()
  let declaration = at(ds, 0).unwrap()
  for bytes in 0..<80 {
    for nodes in 0..<6 {
      for depth in 0..<4 {
        let outcomes = []
        for kind in 0..<3 {
          let ok = try {
            let writer = if kind == 0 {
              @encode.writer(bytes, nodes, depth)
            } else if kind == 1 {
              @encode.measuring_writer(bytes, nodes, depth)
            } else {
              @encode.hashing_writer(bytes, nodes, depth)
            }
            @encode.begin_array(writer)
            emit_declaration(declaration, writer)
            @encode.end_array(writer)
            if kind == 0 {
              ignore(@encode.finish(writer))
            } else if kind == 1 {
              ignore(@encode.finish_measurement(writer))
            } else {
              ignore(@encode.finish_hash(writer))
            }
            true
          } catch {
            _ => false
          }
          outcomes.push(ok)
        }
        assert_eq(outcomes[0], outcomes[1])
        assert_eq(outcomes[1], outcomes[2])
      }
    }
  }
}
