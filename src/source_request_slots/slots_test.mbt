///|
fn owners(
  request : String,
  next? : String = "",
) -> (@stages.Source, @binding.Declarations) {
  let p = @stage.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{\"n\":{\"type\":\"number\"}},\"bindings\":{\"n\":{\"type\":\"resource_ref\",\"resource_kind\":\"drive.file\"}},\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":\"drive/main\",\"resource\":\"file\",\"request\":" +
    request +
    "},\"rows\":\"relation\"},\"steps\":[],\"results\":{\"r\":{}}}" +
    next +
    "],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
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
  (
    @stages.prepare(p, {
      max_parameters: 10,
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap(),
    @binding.prepare(p, { max_bindings: 10, max_work: 10000, }).unwrap(),
  )
}

///|
fn caps() -> Limits {
  { max_work: 1000000, max_slots: 100, }
}

///|
test "request slots cover all stages with one budget and skip actual Result imports" {
  let next =
    #|,{"id":"b","inputs":{"imported":{"result":{"stage":"a","result":"r"}},"remote2":{"connector":"drive/main","resource":"file","request":{"x":{"$param":"n"},"y":{"$binding":"n"}}}},"steps":[],"results":{"r":{}}}
  let (owner, declared) = owners("{\"x\":1}", next~)
  let slots = collect(owner, declared, caps()).unwrap()
  assert_eq(count(slots), 3)
  assert_eq(at(slots, 0).unwrap().stage_index, 0)
  assert_eq(at(slots, 1).unwrap().stage_index, 1)
  assert_eq(at(slots, 2).unwrap().input_name, "remote2")
  assert_true(
    collect(owner, declared, { ..caps(), max_slots: 2, }) is Err(SlotLimit),
  )
  assert_true(
    collect(owner, declared, { ..caps(), max_work: work(slots), }) is Ok(_),
  )
  assert_true(
    collect(owner, declared, { ..caps(), max_work: work(slots) - 1, })
    is Err(WorkLimit),
  )
}

///|
test "request slots retain exact declarations and distinguish Parameter from Binding names" {
  let (owner, declared) = owners(
    (
      #|{"limit":{"$param":"n"},"file":{"$binding":"n"},"plain":null}
    ),
  )
  let slots = collect(owner, declared, caps()).unwrap()
  assert_true(physical_equal(source(slots), owner))
  assert_true(physical_equal(bindings(slots), declared))
  assert_eq(count(slots), 3)
  let limit = at(slots, 0).unwrap()
  let file = at(slots, 1).unwrap()
  assert_eq(limit.stage_index, 0)
  assert_eq(limit.input_name, "remote")
  assert_eq(limit.field_name, "limit")
  assert_true(limit.value is Parameter(d) && d.name == "n")
  assert_true(
    file.value is Binding(d) && d.constraint == @binding.Resource("drive.file"),
  )
  assert_eq(@decode.cursor_path(file.source), [
    Key("stages"),
    Index(0),
    Key("inputs"),
    Key("remote"),
    Key("request"),
    Key("file"),
  ])
  assert_true(at(slots, 2).unwrap().value is Literal(c) && @decode.is_null(c))
  assert_true(at(slots, -1) is None)
  let (_, foreign) = owners("{}")
  assert_true(collect(owner, foreign, caps()) is Err(ForeignBindings))
  assert_true(
    collect(owner, declared, { ..caps(), max_slots: 2, }) is Err(SlotLimit),
  )
  assert_true(
    collect(owner, declared, { ..caps(), max_work: work(slots), }) is Ok(_),
  )
  assert_true(
    collect(owner, declared, { ..caps(), max_work: work(slots) - 1, })
    is Err(WorkLimit),
  )
}

///|
test "request literals do not become recursive binding templates" {
  let (owner, declared) = owners(
    (
      #|{"nested":{"x":{"$param":"unknown"},"y":{"$binding":"unknown"}},"array":[{"$binding":"unknown"}],"literal":{"literal":{"$param":"unknown"}},"extra":{"$binding":"unknown","other":true}}
    ),
  )
  let slots = collect(owner, declared, caps()).unwrap()
  assert_eq(count(slots), 4)
  for i in 0..<count(slots) {
    assert_true(at(slots, i).unwrap().value is Literal(_))
  }
  let deep = "[".repeat(10000) +
    "{\"$binding\":\"unknown\"}" +
    "]".repeat(10000)
  let (deep_owner, deep_declared) = owners("{\"data\":" + deep + "}")
  let result = collect(deep_owner, deep_declared, caps()).unwrap()
  assert_true(at(result, 0).unwrap().value is Literal(_))
  assert_true(
    collect(deep_owner, deep_declared, { ..caps(), max_work: work(result) - 1, })
    is Err(WorkLimit),
  )
}

///|
test "unknown and malformed immediate holes fail atomically at the original slot" {
  for tag in ["$param", "$binding"] {
    let (owner, declared) = owners(
      "{\"good\":{\"$param\":\"n\"},\"bad\":{\"" + tag + "\":\"unknown\"}}",
    )
    match collect(owner, declared, caps()) {
      Err(UnknownParameter(name, c)) | Err(UnknownBinding(name, c)) => {
        assert_eq(name, "unknown")
        assert_eq(@decode.cursor_path(c), [
          Key("stages"),
          Index(0),
          Key("inputs"),
          Key("remote"),
          Key("request"),
          Key("bad"),
        ])
      }
      _ => fail("unknown request reference accepted")
    }
    let (owner, declared) = owners("{\"bad\":{\"" + tag + "\":null}}")
    assert_true(collect(owner, declared, caps()) is Err(Decode(_)))
  }
  let (owner, declared) = owners("null")
  assert_true(collect(owner, declared, caps()) is Err(Decode(_)))
  let (owner, declared) = owners("{}")
  assert_eq(count(collect(owner, declared, caps()).unwrap()), 0)
  assert_true(
    collect(owner, declared, { ..caps(), max_work: -1, }) is Err(InvalidLimits),
  )
}
