///|
// A nominal captured input declaration, not a Values substitute for ContentRef
// acquisition. Installed availability, issuer/current and apply remain Host-owned.
fn store_capture_context() -> Context {
  let declaration = @wire.admit(
    @source.parse_json(
      "{\"carrier\":\"relation\",\"schema\":{\"path\":{\"type\":\"string\",\"nullable\":false},\"content\":{\"type\":\"content_ref\",\"nullable\":false}}}",
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
      fail(
        "STORE lowerer refused: " +
        store_capture_issue_label(issue) +
        " source=" +
        source,
      )
  }
}

///|
fn store_capture_issue_label(issue : Issue) -> String {
  match issue {
    BindingPreparation(LocalProgram(Pipeline(_, detail))) =>
      @debug.to_string(detail.kind)
    BindingPreparationSource(LocalProgram(Pipeline(_, detail)), _) =>
      @debug.to_string(detail.kind)
    BindingPreparation(LocalProgram(Order(_, _))) => "LocalProgram.Order"
    BindingPreparation(LocalProgram(cause)) =>
      match cause {
        InvalidLimits => "LocalProgram.InvalidLimits"
        CheckOnlyPrefix => "LocalProgram.CheckOnlyPrefix"
        BudgetExceeded => "LocalProgram.BudgetExceeded"
        ForeignEnvironmentSource => "LocalProgram.ForeignEnvironmentSource"
        ForeignModelEnvironment => "LocalProgram.ForeignModelEnvironment"
        SourceViewStageCount => "LocalProgram.SourceViewStageCount"
        MissingSourceViewRegistrations(_) =>
          "LocalProgram.MissingSourceViewRegistrations"
        InvalidSourceViewRegistration(_, _) =>
          "LocalProgram.InvalidSourceViewRegistration"
        UnsupportedReceipt(_, _) => "LocalProgram.UnsupportedReceipt"
        LocalInput(_, _) => "LocalProgram.LocalInput"
        Import(_, _) => "LocalProgram.Import"
        Pipeline(_, _) => "LocalProgram.Pipeline"
        Collection(_, _) => "LocalProgram.Collection"
        Results(_, _) => "LocalProgram.Results"
        Order(_, _) => "LocalProgram.Order"
        Ports(_, _) => "LocalProgram.Ports"
        TableInputs(_, _) => "LocalProgram.TableInputs"
        Wiring(_) => "LocalProgram.Wiring"
      }
    BindingPreparation(Demand(_)) => "Demand"
    BindingPreparation(SourceDeclarations(_)) => "SourceDeclarations"
    BindingPreparation(MissingSourceCatalog(_)) => "MissingSourceCatalog"
    BindingPreparation(Declarations(_)) => "Declarations"
    _ => private_update_issue_label(issue)
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
  let args = @wire.elements(store_capture_field(expression, "concat_strict")).unwrap()
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
    is Err(StoreTargetBinding(AmbiguousMapping)),
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

///|
test "STORE WITH control retains the same captured input before terminal lowering" {
  let source = "WITH original AS (FROM files) FROM original"
  let query = @query.parse_query(source, syntax_limits()).unwrap()
  match compile(query, store_capture_context(), construction_limits()) {
    Ok(_) => ()
    Err(issue) => fail(store_capture_issue_label(issue))
  }
}

///|
test "STORE never claims an empty primary key as input evidence" {
  let valid = match store_capture_context().inputs[0].source {
    Captured(source) => source
    _ => abort("expected the captured declaration control")
  }
  let limits : @local_input.Limits = {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }
  assert_true(@local_input.read(valid, limits) is Ok(_))
  let invalid = @wire.admit(
    @source.parse_json(
      "{\"carrier\":\"relation\",\"primary_key\":[],\"schema\":{\"path\":{\"type\":\"string\",\"nullable\":false},\"content\":{\"type\":\"content_ref\",\"nullable\":false}}}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  assert_true(@local_input.read(invalid, limits) is Err(PrimaryKey(_)))
}

///|
test "STORE set tail captures the completed UNION once" {
  let program = store_capture_program(
    "FROM files |> UNION ALL (FROM files) |> EFFECT STORE storage.archive SET (path = path, content = content)",
  )
  assert_eq(@program.export_count(program), 0)
  let steps = store_capture_steps(program)
  let union_steps = steps.filter(step => {
    @wire.lookup(@wire.open_object(step).unwrap(), "append") is Some(_)
  })
  assert_eq(union_steps.length(), 1)
  assert_eq(
    @program.effect_header_count(
      @program.collect_effect_headers(program, 10, 10000).unwrap(),
    ),
    1,
  )
  assert_eq(@program.result_names(@program.stages(program).last().unwrap()), [
    "aql_private_store",
  ])
}

///|
test "STORE consumes immutable range values before the public projection drops them" {
  let program = store_capture_program(
    "FROM files AS original |> SET path = 'replacement' |> EFFECT STORE storage.archive SET (path = original.path, content = original.content)",
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
  // The immutable range still names original slots, not the newly derived path.
  assert_eq(@wire.text(selected[0]).unwrap(), "path")
  assert_eq(@wire.text(selected[1]).unwrap(), "content")
}

///|
test "STORE relation Mapping keeps canonical relation materialization" {
  let query = @query.parse_query(
    "FROM orders |> EFFECT STORE storage.archive SET (id = id, value = status)",
    syntax_limits(),
  ).unwrap()
  let program = compile(
    query,
    fixture_context(),
    construction_limits(),
    store_targets=Some(store_target_publication("relation")),
  ).unwrap()
  let header = store_capture_header(program)
  assert_eq(@program.effect_header_kind(header), "store")
  assert_true(@program.effect_header_published_store_target(header) is None)
  assert_eq(
    @program.effect_header_source_result(header),
    Some("aql_private_store"),
  )
  let body = @program.effect_header_body(header)
  assert_eq(
    @wire.text(store_capture_field(body, "target")).unwrap(),
    "connector://storage/archive",
  )
  assert_eq(
    @wire.text(store_capture_field(body, "mapping")).unwrap(),
    "mapping:fixture.archive.v1",
  )
  assert_eq(@program.export_count(program), 0)
}

///|
test "STORE takes original typed content from SERIALIZE through the existing compiler" {
  let query = @query.parse_query(
    "FROM pair |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'pair.jsonl', max_rows = 1, max_bytes = 128) |> EFFECT STORE storage.archive SET (path = name, content = content)",
    syntax_limits(),
  ).unwrap()
  let program = match
    compile(
      query,
      pair_context(),
      construction_limits(),
      store_targets=Some(store_capture_publication()),
    ) {
    Ok(program) => program
    Err(issue) =>
      fail("SERIALIZE STORE refused: " + store_capture_issue_label(issue))
  }
  assert_eq(@program.export_count(program), 0)
  let headers = @program.collect_effect_headers(program, 10, 10000).unwrap()
  assert_eq(@program.effect_header_count(headers), 1)
  let steps = store_capture_steps(program)
  assert_eq(
    steps
    .filter(step => {
      @wire.lookup(@wire.open_object(step).unwrap(), "serialize") is Some(_)
    })
    .length(),
    1,
  )
  let environment = store_source_environment("collection")
  let candidate = match
    @check.prepare_effect_computation_candidate(
      program,
      environment,
      None,
      [],
      check_limits(),
      1,
      1000,
    ) {
    Ok(candidate) => candidate
    Err(Computation(issue)) => raise issue
    Err(_) =>
      fail(
        "original SERIALIZE computation must reach the existing Effect checker",
      )
  }
  let mappings = @environment.check_mapping_contract_shapes(
    @check.checking_environment_wire(environment),
    { max_bytes: 40000, max_nodes: 4000, max_depth: 100, max_members: 100, },
    10000,
  ).unwrap()
  let closed = @check.close_effect_computation_static(candidate, mappings, {
    max_members: 10,
    max_work: 10000,
    max_admission_nodes: 1000,
    max_admission_depth: 100,
    max_admission_text_bytes: 10000,
  }).unwrap()
  assert_eq(
    @program.effect_header_count(@check.effect_program_static_headers(closed)),
    1,
  )
}

///|
test "source Frontend preserves the original STORE publication and private output" {
  let publication = store_capture_publication()
  let lowered = @frontend.lower(
    "FROM files |> EFFECT STORE storage.archive SET (path = path, content = content)",
    @frontend.select_format("aql").unwrap(),
    Some(store_capture_context()),
    store_targets=Some(publication),
  ).unwrap()
  assert_true(physical_equal(lowered.store_targets.unwrap(), publication))
  assert_eq(@program.export_count(lowered.program.unwrap()), 0)
}
