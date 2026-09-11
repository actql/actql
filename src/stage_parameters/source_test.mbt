///|
fn parsed() -> @stage.Program {
  @stage.parse(
    (
      #|{"version":"actql/0.1","id":"p","params":{"n":{"type":"number"}},"stages":[{"id":"a","inputs":{"rows":{}},"from":"rows","steps":[{"take":{"$param":"n"}}],"results":{"r":{}}},{"id":"b","inputs":{"rows":{}},"from":"rows","steps":[{"take":{"$param":"n"}}],"results":{"r":{}}}],"results":{"out":{"from":{"stage":"b","result":"r"}}}}
    ),
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
}

///|
fn prepared(program : @stage.Program) -> Source {
  prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn caps() -> @collection.Limits {
  {
    max_work: 10000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }
}

///|
fn checked(
  s : Source,
  index : Int,
  d : @parameter.Declarations?,
  omit_from? : Bool = false,
) -> @pipeline.CheckedPipeline {
  let object = @decode.open_object(
    @stage.stage_body(stage_at(s, index).unwrap()),
  ).unwrap()
  let schema = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  @pipeline.check(
    @decode.required(object, "steps").unwrap(),
    [("rows", schema)],
    d,
    if omit_from {
      None
    } else {
      @decode.lookup(object, "from")
    },
    {
      max_steps: 10,
      max_work: 10000,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 10000,
      max_tokens: 1000,
    },
  ).unwrap()
}

///|
test "stage collection binds declarations and exact source slots" {
  let p = parsed()
  let s = prepared(p)
  let a = checked(s, 0, Some(declarations(s)))
  let b = checked(s, 1, Some(declarations(s)))
  let result = collect(s, 0, a, caps()).unwrap()
  assert_true(physical_equal(program(source(result)), p))
  assert_eq(stage_index(result), 0)
  assert_eq(stage_count(s), 2)
  let refs = @collection.index(collection(result))
  assert_eq(@references.reference_count(refs), 1)
  assert_eq(@references.reference_at(refs, 0).unwrap().path, "/steps/0/take")
  assert_true(collect(s, 0, b, caps()) is Err(ForeignSteps))
  assert_true(collect(s, -1, a, caps()) is Err(InvalidStage))
  assert_true(collect(s, 2, a, caps()) is Err(InvalidStage))
  assert_true(
    collect(s, 0, checked(s, 0, Some(declarations(s)), omit_from=true), caps())
    is Err(ForeignInitialFrom),
  )
  let other = prepared(parsed())
  assert_true(
    collect(s, 0, checked(s, 0, Some(declarations(other))), caps())
    is Err(ForeignDeclarations),
  )
  // Even the right declaration owner cannot legitimize a separately parsed body.
  assert_true(
    collect(s, 0, checked(other, 0, Some(declarations(s))), caps())
    is Err(ForeignSteps),
  )
  assert_true(
    collect(s, 0, a, { ..caps(), max_references: 0, }) is Err(Collection(_)),
  )
}

///|
test "absent Program parameters still use an explicit shared empty owner" {
  let p = @stage.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"a\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let s = prepared(p)
  assert_eq(@parameter.declaration_count(declarations(s)), 0)
  let view = @decode.open_object(@stage.stage_body(stage_at(s, 0).unwrap())).unwrap()
  let steps = @decode.required(view, "steps").unwrap()
  let lim : @pipeline.Limits = {
    max_steps: 0,
    max_work: 100,
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 100,
    max_tokens: 0,
  }
  let a = @pipeline.check(steps, [], Some(declarations(s)), None, lim).unwrap()
  let result = collect(s, 0, a, caps()).unwrap()
  assert_eq(
    @references.reference_count(@collection.index(collection(result))),
    0,
  )
  let b = @pipeline.check(steps, [], None, None, lim).unwrap()
  assert_true(collect(s, 0, b, caps()) is Err(ForeignDeclarations))
  let other = prepared(p)
  assert_true(collect(other, 0, a, caps()) is Err(ForeignDeclarations))
}
