///|
fn fixture(
  used_bindings? : Bool = false,
  unused_parameter? : Bool = false,
  unused_parameter_name? : String = "unknown",
  empty? : Bool = false,
  annotations? : Bool = false,
  import_mode? : Int = 0,
  accepted? : Bool = false,
  root_id? : String = "p",
  parameters? : String? = None,
) -> (@requests.Slots, Array[@body.ParameterUses]) {
  let text =
    #|{"version":"actql/0.1","id":"p","params":{"n":{"type":"number"},"m":{"type":"number"}},"bindings":{"b":{"type":"resource_ref","resource_kind":"drive.file","meta":{"note":"omit"}},"unused":{"type":"artifact_ref"}},"stages":[{"id":"a","inputs":{"rows":"relation","remote/~":{"connector":"drive/main","resource":"file","request":{"p":{"$param":"n"},"f/~":{"$binding":"b"},"again":{"$binding":"b"},"data":{"nested":{"$param":"unknown"}}}}},"from":"rows","steps":[{"take":{"$param":"m"}}],"results":{"r":{}},"effects":{"d":{"delete":{"where":["1 < $n"]}}}},{"id":"b","inputs":{"rows":"relation"},"from":"rows","steps":[{"take":{"$param":"m"}}],"results":{"r":{}}}],"results":{"out":{"from":{"stage":"b","result":"r"}}}}
  let text = if used_bindings {
    text.replace(old=",\"unused\":{\"type\":\"artifact_ref\"}", new="")
  } else {
    text
  }
  let text = if unused_parameter {
    text.replace(
      old="\"params\":{",
      new="\"params\":{\"" +
        unused_parameter_name +
        "\":{\"type\":\"number\",\"default\":7},",
    )
  } else {
    text
  }
  let text = if empty {
    (
      #|{"version":"actql/0.1","id":"empty","stages":[{"id":"a","inputs":{"rows":"relation","remote/~":"relation"},"from":"rows","steps":[],"results":{"r":{}}},{"id":"b","inputs":{"rows":"relation"},"from":"rows","steps":[],"results":{"r":{}}}],"results":{"out":{"from":{"stage":"b","result":"r"}}}}
    )
  } else {
    text
  }
  let text = if import_mode == 0 {
    text
  } else {
    text.replace(
      old="\"id\":\"b\",\"inputs\":{\"rows\":\"relation\"}",
      new="\"id\":\"b\",\"inputs\":{\"rows\":" +
        (if import_mode == 1 {
          "{\"result\":{\"stage\":\"a\",\"result\":\"r\"}}"
        } else {
          "{\"receipt\":{\"stage\":\"a\",\"effect\":\"d\"}}"
        }) +
        "}",
    )
  }
  let text = if accepted {
    text.replace(old="\"id\":\"b\"", new="\"id\":\"b\",\"after\":\"accepted\"")
  } else {
    text
  }
  let text = if annotations {
    text
    .replace(
      old="\"id\":\"a\"",
      new="\"id\":\"renamed-a\",\"meta\":{\"note\":\"different stage explanation\"}",
    )
    .replace(
      old="\"id\":\"b\"",
      new="\"id\":\"renamed-b\",\"meta\":{\"note\":\"another explanation\"}",
    )
    .replace(old="\"stage\":\"b\"", new="\"stage\":\"renamed-b\"")
    .replace(
      old="\"take\":{\"$param\":\"m\"}",
      new="\"take\":{\"$param\":\"m\"},\"meta\":{\"note\":\"step annotation\"}",
    )
  } else {
    text
  }
  let text = text.replace(old="\"id\":\"p\"", new="\"id\":\"" + root_id + "\"")
  let text = match parameters {
    Some(params) =>
      text.replace(
        old="\"params\":{\"n\":{\"type\":\"number\"},\"m\":{\"type\":\"number\"}}",
        new="\"params\":" + params,
      )
    None => text
  }
  let program = @stage.parse(
    text,
    {
      source: { max_input_bytes: 100000, max_nodes: 10000, max_depth: 100, },
      tree: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 100000,
        max_total_string_bytes: 100000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let bindings = @bindings.prepare(program, {
    max_bindings: 10,
    max_work: 10000,
  }).unwrap()
  let requests = @requests.collect(source, bindings, {
    max_work: 100000,
    max_slots: 100,
  }).unwrap()
  let stages = []
  let schema = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let collection_limits : @collection.Limits = {
    max_work: 1000000,
    max_slots: 1000,
    max_references: 1000,
    max_pointer_units: 100000,
    max_direct_text_bytes: 100000,
  }
  for i in 0..<2 {
    let root = @stage.stage_body(@stages.stage_at(source, i).unwrap())
    let view = @decode.open_object(root).unwrap()
    let inputs = [("rows", schema)]
    if i == 0 {
      inputs.push(("remote/~", schema))
    }
    let pipeline = @pipeline.check(
      @decode.required(view, "steps").unwrap(),
      inputs,
      Some(@stages.declarations(source)),
      @decode.lookup(view, "from"),
      {
        max_steps: 100,
        max_work: 100000,
        max_nodes: 10000,
        max_depth: 100,
        max_text_bytes: 100000,
        max_tokens: 1000,
      },
    ).unwrap()
    let collected = @stages.collect(source, i, pipeline, collection_limits).unwrap()
    let body = @body.prepare(collected, {
      max_work: 1000000,
      selectors: {
        max_nodes: 10000,
        max_depth: 100,
        max_text_bytes: 100000,
        max_tokens: 1000,
        tree: {
          max_nodes: 10000,
          max_depth: 100,
          max_string_bytes: 100000,
          max_total_string_bytes: 100000,
        },
      },
    }).unwrap()
    stages.push(@body.collect_parameter_uses(body, collection_limits).unwrap())
  }
  (requests, stages)
}

///|
fn caps() -> Limits {
  {
    max_work: 4000000,
    max_slots: 1000,
    max_references: 1000,
    max_pointer_units: 1000000,
    max_request_text_bytes: 100000,
  }
}

///|
fn binding_text(value : Index) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(10000, 1000, 100)
  emit_binding_references(value, writer)
  @encode.finish(writer)
}

///|
test "all-stage reference inventory separates local and Program coordinates" {
  let (request_slots, stages) = fixture()
  let inventory = prepare(request_slots, stages, caps()).unwrap()
  assert_true(physical_equal(requests(inventory), request_slots))
  let a = stage_index(inventory, 0).unwrap()
  let b = stage_index(inventory, 1).unwrap()
  let program = program_index(inventory)
  assert_eq(@parameters.reference_count(parameters(a)), 3)
  assert_eq(@parameters.reference_count(parameters(b)), 1)
  let paths = []
  for i in 0..<@parameters.reference_count(parameters(program)) {
    paths.push(@parameters.reference_at(parameters(program), i).unwrap().path)
  }
  assert_eq(paths, [
    "/stages/0/effects/d/delete/where/0/lt/1", "/stages/0/inputs/remote~1~0/request/p",
    "/stages/0/steps/0/take", "/stages/1/steps/0/take",
  ])
  assert_eq(
    @parameters.reference_at(parameters(a), 1).unwrap().path,
    "/inputs/remote~1~0/request/p",
  )
  assert_eq(
    @parameters.reference_at(parameters(b), 0).unwrap().path,
    "/steps/0/take",
  )
  assert_eq(binding_count(a), 2)
  assert_eq(binding_count(b), 0)
  assert_eq(binding_count(program), 2)
  assert_eq(binding_at(a, 0).unwrap().path, "/inputs/remote~1~0/request/again")
  assert_eq(
    binding_at(program, 1).unwrap().path,
    "/stages/0/inputs/remote~1~0/request/f~1~0",
  )
  assert_true(binding_at(program, 2) is None)
  assert_true(stage_index(inventory, 2) is None)
  assert_eq(binding_text(b), "[]")
  assert_eq(
    binding_text(a),
    (
      #|[{"name":"b","path":"/inputs/remote~1~0/request/again","type":{"resource_kind":"drive.file","type":"resource_ref"}},{"name":"b","path":"/inputs/remote~1~0/request/f~1~0","type":{"resource_kind":"drive.file","type":"resource_ref"}}]
    ),
  )
  let used = @encode.writer(10000, 100, 100)
  emit_used_bindings(program, used)
  assert_eq(
    @encode.finish(used),
    "{\"b\":{\"resource_kind\":\"drive.file\",\"type\":\"resource_ref\"}}",
  )
  let local_parameters = @encode.writer(10000, 100, 100)
  @parameters.emit_used_declarations(parameters(b), local_parameters)
  assert_eq(@encode.finish(local_parameters), "{\"m\":{\"type\":\"number\"}}")
}

///|
test "reference inventory rejects missing reordered and foreign stage owners" {
  let (slots, stages) = fixture()
  let original = stages[0]
  let inventory = prepare(slots, stages, caps()).unwrap()
  assert_true(prepare(slots, [], caps()) is Err(StageCountMismatch))
  assert_true(
    prepare(slots, [stages[1], stages[0]], caps()) is Err(ForeignStage(0)),
  )
  assert_true(
    prepare(slots, [stages[0], stages[0]], caps()) is Err(ForeignStage(1)),
  )
  let (_, foreign) = fixture()
  assert_true(prepare(slots, foreign, caps()) is Err(ForeignStage(0)))
  stages[0] = stages[1]
  assert_true(physical_equal(stage_uses(inventory, 0).unwrap(), original))
}

///|
test "whole Program reference budgets include retained and rebuilt indices" {
  let (slots, stages) = fixture()
  let inventory = prepare(slots, stages, caps()).unwrap()
  let exact = work(inventory)
  assert_true(prepare(slots, stages, { ..caps(), max_work: exact, }) is Ok(_))
  assert_true(
    prepare(slots, stages, { ..caps(), max_work: exact - 1, }) is Err(_),
  )
  assert_true(
    prepare(slots, stages, { ..caps(), max_slots: 6, max_references: 6, })
    is Ok(_),
  )
  assert_true(
    prepare(slots, stages, { ..caps(), max_slots: 5, }) is Err(SlotLimit),
  )
  assert_true(
    prepare(slots, stages, { ..caps(), max_references: 5, })
    is Err(ReferenceLimit),
  )
  assert_true(
    prepare(slots, stages, { ..caps(), max_pointer_units: 0, })
    is Err(PointerLimit),
  )
  assert_true(
    prepare(slots, stages, { ..caps(), max_request_text_bytes: 0, })
    is Err(Syntax(_)),
  )
  assert_true(
    prepare(slots, stages, { ..caps(), max_work: -1, }) is Err(InvalidLimits),
  )
  let index = program_index(inventory)
  let length = binding_text(index).length()
  for bytes in [length - 1, length, length + 1] {
    for nodes in 0..<14 {
      for depth in 0..<5 {
        let results = []
        for kind in 0..<3 {
          let ok = try {
            let writer = if kind == 0 {
              @encode.writer(bytes, nodes, depth)
            } else if kind == 1 {
              @encode.measuring_writer(bytes, nodes, depth)
            } else {
              @encode.hashing_writer(bytes, nodes, depth)
            }
            emit_binding_references(index, writer)
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
          results.push(ok)
        }
        assert_eq(results[0], results[1])
        assert_eq(results[1], results[2])
      }
    }
  }
}
