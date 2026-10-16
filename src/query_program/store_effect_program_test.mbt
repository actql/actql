///|
// A nominal captured input declaration, not a Values substitute for ContentRef
// acquisition. Installed availability, issuer/current and apply remain Host-owned.
fn store_capture_context() -> Context {
  let declaration = @wire.admit(
    @source.parse_json(
      "{\"carrier\":\"relation\",\"schema\":{\"path\":{\"type\":\"string\",\"nullable\":false},\"content\":{\"type\":\"content_ref\",\"nullable\":false}},\"primary_key\":[]}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let input : Input = {
    relation: [{ value: "files", quoted: false, }],
    name: "files",
    source: Captured(declaration),
    visible_fields: ["path", "content"],
    graph_bindings: [],
  }
  { ..fixture_context(), program_id: "fixture.store_private", inputs: [input], }
}

///|
fn store_capture_publication() -> StoreTargetPublication {
  let environment = store_source_environment("collection")
  @source_publication.published_store_targets(
    environment,
    store_source_publication(environment),
  )
  .unwrap()
  .unwrap()
}

///|
fn store_capture_program(source : String) -> @program.Program raise {
  let query = @query.parse_query(source, syntax_limits()).unwrap()
  match
    compile(
      query,
      store_capture_context(),
      construction_limits(),
      store_targets=Some(store_capture_publication()),
    ) {
    Ok(program) => program
    Err(issue) =>
      fail("STORE lowerer refused: " + private_update_issue_label(issue))
  }
}

///|
fn store_capture_field(cursor : @wire.Cursor, name : String) -> @wire.Cursor {
  @wire.required(@wire.open_object(cursor).unwrap(), name).unwrap()
}

///|
fn store_capture_private(program : @program.Program) -> @wire.Cursor {
  store_capture_field(
    store_capture_field(
      @program.stage_body(@program.stages(program).last().unwrap()),
      "results",
    ),
    "aql_private_store",
  )
}

///|
fn store_capture_steps(program : @program.Program) -> Array[@wire.Cursor] {
  let steps : Array[@wire.Cursor] = []
  for stage in @program.stages(program) {
    steps.append(
      @wire.elements(store_capture_field(@program.stage_body(stage), "steps")).unwrap(),
    )
  }
  steps
}

///|
fn store_capture_header(
  program : @program.Program,
) -> @program.EffectHeader raise {
  let headers = @program.collect_effect_headers(program, 10, 10000).unwrap()
  assert_eq(@program.effect_header_count(headers), 1)
  @program.effect_header_at(headers, 0).unwrap()
}

///|
test "STORE collection uses its original Command pair and one private input" {
  for
    source in [
      "FROM files |> EFFECT STORE storage.archive", "SELECT path, content FROM files |> EFFECT STORE storage.archive",
      "WITH original AS (FROM files) FROM original |> EFFECT STORE storage.archive SET (path = path, content = content)",
    ] {
    let program = store_capture_program(source)
    assert_eq(@program.export_count(program), 0)
    let header = store_capture_header(program)
    assert_eq(@program.effect_header_kind(header), "command")
    assert_eq(@program.effect_header_id(header), "aql_store_effect")
    assert_eq(
      @program.effect_header_contract_ref(header),
      "command:fixture.upload.v1",
    )
    assert_eq(
      @program.effect_header_published_store_target(header),
      Some(("connector://storage/archive", "mapping:fixture.archive.v1")),
    )
    assert_eq(
      @program.effect_header_source_result(header),
      Some("aql_private_store"),
    )
    let fields = @wire.elements(
        store_capture_field(store_capture_private(program), "fields"),
      )
      .unwrap()
      .map(field => @wire.text(field).unwrap())
    assert_eq(fields, ["path", "content"])
    let input = store_capture_field(
      @program.effect_header_body(header),
      "input",
    )
    assert_eq(@wire.object_field_names(input).unwrap(), ["path", "content"])
    for name in fields {
      assert_eq(
        @wire.text(
          store_capture_field(store_capture_field(input, name), "field"),
        ).unwrap(),
        name,
      )
    }
  }
}

///|
test "STORE SET evaluates one existing Relation expression and retains ContentRef" {
  let program = store_capture_program(
    "FROM files |> EFFECT upload STORE storage.archive SET (path = CONCAT(path, '.csv'), content = content)",
  )
  assert_eq(@program.effect_header_id(store_capture_header(program)), "upload")
  let derives = store_capture_steps(program).filter(step => {
    @wire.lookup(@wire.open_object(step).unwrap(), "derive") is Some(_)
  })
  assert_eq(derives.length(), 1)
  let derivation = store_capture_field(derives[0], "derive")
  assert_eq(@wire.object_length(derivation), Some(1))
  let expression = @wire.field_at(derivation, 0).unwrap().1
  let args = @wire.elements(store_capture_field(expression, "concat")).unwrap()
  assert_eq(args.length(), 2)
  assert_eq(@wire.text(store_capture_field(args[0], "field")).unwrap(), "path")
  assert_eq(
    @wire.text(store_capture_field(args[1], "literal")).unwrap(),
    ".csv",
  )
  let capture = store_capture_private(program)
  let capture_name = @wire.text(store_capture_field(capture, "from")).unwrap()
  let step = store_capture_steps(program).filter(step => {
      @wire.lookup(@wire.open_object(step).unwrap(), "as").map(value => {
        @wire.text(value).unwrap()
      }) ==
      Some(capture_name)
    })[0]
  let selected = @wire.elements(store_capture_field(step, "select")).unwrap()
  assert_eq(@wire.text(selected[1]).unwrap(), "content")
}

///|
test "STORE retains authored public Result independently from its private SET" {
  let program = store_capture_program(
    "FROM files |> RESULT before_write |> EFFECT STORE storage.archive SET (path = path, content = content)",
  )
  assert_eq(@program.exports(program), [("before_write", "main", "rows")])
  assert_eq(@program.result_names(@program.stages(program).last().unwrap()), [
    "rows", "aql_private_store",
  ])
}

///|
test "STORE target admission precedes SET binding and never guesses from rows" {
  let query = @query.parse_query(
    "FROM files |> EFFECT STORE storage.archive SET (path = absent, content = content)",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, store_capture_context(), construction_limits())
    is Err(StoreTargetBinding(UnresolvedTarget)),
  )
  assert_true(
    compile(
      query,
      store_capture_context(),
      construction_limits(),
      store_targets=Some(store_target_publication("ambiguous")),
    )
    is Err(StoreTargetBinding(AmbiguousTarget)),
  )
  assert_true(
    compile(
      query,
      store_capture_context(),
      construction_limits(),
      store_targets=Some(store_capture_publication()),
    )
    is Err(_),
  )
}
