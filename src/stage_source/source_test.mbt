///|
fn collected(
  effects : String,
  input? : String = "{\"carrier\":\"relation\"}",
  result? : String = "{\"from\":\"rows\",\"fields\":[\"amount\"]}",
  step_text? : String = "[]",
  initial? : String = "",
  source_text? : String? = None,
  stage_index? : Int = 0,
) -> @stages.CollectedStage {
  let text = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{\"n\":{\"type\":\"number\"}},\"stages\":[{\"id\":\"a\",\"meta\":{\"note\":\"stage\"},\"inputs\":{\"rows\":" +
    input +
    "},\"steps\":" +
    step_text +
    ",\"results\":{\"r\":" +
    result +
    "}" +
    initial +
    effects +
    "}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
  let program = @syntax.parse(
    source_text.unwrap_or(text),
    {
      source: { max_input_bytes: 2000000, max_nodes: 100000, max_depth: 20000, },
      tree: {
        max_nodes: 100000,
        max_depth: 20000,
        max_string_bytes: 2000000,
        max_total_string_bytes: 2000000,
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
  let object = @decode.open_object(
    @syntax.stage_body(@stages.stage_at(source, stage_index).unwrap()),
  ).unwrap()
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("amount"),
        @contract.primitive(@contract.NumberType, nullable=false),
      ),
    ],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let pipeline = @pipeline.check(
    @decode.required(object, "steps").unwrap(),
    [("rows", schema)],
    Some(@stages.declarations(source)),
    @decode.lookup(object, "from"),
    {
      max_steps: 100,
      max_work: 1000000,
      max_nodes: 100000,
      max_depth: 20000,
      max_text_bytes: 2000000,
      max_tokens: 10000,
    },
  ).unwrap()
  @stages.collect(source, stage_index, pipeline, {
    max_work: 1000000,
    max_slots: 1000,
    max_references: 1000,
    max_pointer_units: 100000,
    max_direct_text_bytes: 100000,
  }).unwrap()
}

///|
fn caps() -> Limits {
  {
    max_work: 2000000,
    selectors: {
      max_nodes: 100000,
      max_depth: 20000,
      max_text_bytes: 2000000,
      max_tokens: 100000,
      tree: {
        max_nodes: 100000,
        max_depth: 20000,
        max_string_bytes: 2000000,
        max_total_string_bytes: 2000000,
      },
    },
  }
}

///|
fn rendered(body : Body) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(2000000, 100000, 20000)
  emit(body, writer)
  @encode.finish(writer)
}

///|
test "local stage body omits annotations only at their owned declaration slots" {
  let owner = collected(
    (
      #|,"effects":{"e":{"meta":{"note":"omit"},"create":{"payload":{"meta":{"note":"keep"},"literal":{"$param":"data"}},"target":{"literal":"business"}}}}
    ),
    input="{\"carrier\":\"relation\",\"meta\":{\"note\":\"omit\"},\"schema\":{\"meta\":{\"type\":\"string\"}}}",
    result="{\"from\":\"rows\",\"fields\":[\"amount\"],\"meta\":{\"note\":\"omit\"}}",
    step_text="[{\"filter\":\"amount > $n\",\"meta\":{\"note\":\"omit\"}}]",
    initial=",\"from\":\"rows\"",
  )
  let body = prepare(owner, caps()).unwrap()
  assert_true(physical_equal(stage(body), owner))
  assert_true(
    physical_equal(@steps.collection(steps(body)), @stages.collection(owner)),
  )
  assert_eq(
    rendered(body),
    (
      #|{"effects":{"e":{"create":{"payload":{"literal":{"$param":"data"},"meta":{"note":"keep"}},"target":{"literal":"business"}}}},"from":"rows","inputs":{"rows":{"carrier":"relation","schema":{"meta":{"type":"string"}}}},"results":{"r":{"fields":["amount"],"from":"rows"}},"steps":[{"filter":{"gt":[{"field":"amount"},{"$param":"n"}]}}]}
    ),
  )
  assert_eq(selector_count(body), 0)
  assert_true(selector_at(body, -1) is None)
  let exact = work(body)
  assert_true(prepare(owner, { ..caps(), max_work: exact, }) is Ok(_))
  assert_true(prepare(owner, { ..caps(), max_work: exact - 1, }) is Err(_))
  assert_true(prepare(owner, { ..caps(), max_work: -1, }) is Err(InvalidLimits))
}

///|
test "omitted effects becomes an empty map without synthesizing from or Input defaults" {
  let absent = prepare(collected("", input="\"relation\""), caps()).unwrap()
  let explicit = prepare(
    collected(",\"effects\":{}", input="\"relation\""),
    caps(),
  ).unwrap()
  assert_eq(rendered(absent), rendered(explicit))
  assert_eq(
    rendered(absent),
    (
      #|{"effects":{},"inputs":{"rows":"relation"},"results":{"r":{"fields":["amount"],"from":"rows"}},"steps":[]}
    ),
  )
  assert_true(
    prepare(collected(""), {
      ..caps(),
      selectors: { ..caps().selectors, max_tokens: -1, },
    })
    is Err(InvalidLimits),
  )
}

///|
test "Effect selectors share syntax budgets and retain their actual source origins" {
  let owner = collected(
    (
      #|,"effects":{"u":{"update":{"where":["amount > $n",{"eq":[{"field":"amount"},{"literal":2}]}],"set":{"x":{"literal":{"meta":true,"$param":"data"}}}}}}
    ),
  )
  let body = prepare(owner, caps()).unwrap()
  assert_eq(selector_count(body), 2)
  let first = @selector.expression(selector_at(body, 0).unwrap())
  let second = @selector.expression(selector_at(body, 1).unwrap())
  assert_eq(
    @expression.location_path(
      @expression.origin(first, @expression.tree(first)).unwrap(),
    ),
    [
      Key("stages"),
      Index(0),
      Key("effects"),
      Key("u"),
      Key("update"),
      Key("where"),
      Index(0),
    ],
  )
  assert_eq(@expression.parameter_references(first).length(), 1)
  assert_eq(
    rendered(body),
    (
      #|{"effects":{"u":{"update":{"set":{"x":{"literal":{"$param":"data","meta":true}}},"where":[{"gt":[{"field":"amount"},{"$param":"n"}]},{"eq":[{"field":"amount"},{"literal":2}]}]}}},"inputs":{"rows":{"carrier":"relation"}},"results":{"r":{"fields":["amount"],"from":"rows"}},"steps":[]}
    ),
  )
  let n = @expression.usage(first).nodes + @expression.usage(second).nodes
  assert_true(
    prepare(owner, {
      ..caps(),
      selectors: { ..caps().selectors, max_nodes: n, },
    })
    is Ok(_),
  )
  assert_true(
    prepare(owner, {
      ..caps(),
      selectors: { ..caps().selectors, max_nodes: n - 1, },
    })
    is Err(_),
  )
  let bad = collected(
    ",\"effects\":{\"e\":{\"delete\":{\"where\":[\"amount + 1 > 0\"]}}}",
  )
  assert_true(prepare(bad, caps()) is Err(Selector(_)))
}

///|
test "invalid annotations and ambiguous selector envelopes cannot disappear during projection" {
  for metadata in ["{}", "null", "[]", "{\"actql_reserved\":true}"] {
    assert_true(
      prepare(
        collected(
          "",
          input="{\"carrier\":\"relation\",\"meta\":" + metadata + "}",
        ),
        caps(),
      )
      is Err(InvalidMetadata(_)),
    )
    assert_true(
      prepare(
        collected(
          "",
          result="{\"from\":\"rows\",\"fields\":[\"amount\"],\"meta\":" +
            metadata +
            "}",
        ),
        caps(),
      )
      is Err(InvalidMetadata(_)),
    )
    assert_true(
      prepare(
        collected(
          ",\"effects\":{\"e\":{\"delete\":{},\"meta\":" + metadata + "}}",
        ),
        caps(),
      )
      is Err(InvalidMetadata(_)),
    )
  }
  assert_true(
    prepare(
      collected(
        ",\"effects\":{\"e\":{\"delete\":{},\"meta\":{\"nested\":{\"actql_note\":true}}}}",
      ),
      caps(),
    )
    is Ok(_),
  )
  for
    effect in [
      "{}", "null", "{\"delete\":{},\"update\":{}}", "{\"unknown\":{}}", "{\"delete\":{\"where\":[]}}",
      "{\"delete\":{\"where\":null}}",
    ] {
    assert_true(
      prepare(collected(",\"effects\":{\"e\":" + effect + "}"), caps())
      is Err(InvalidEffect(_)),
    )
  }
}

///|
test "raw Effect data uses an iterative emitter and the same bounded sinks" {
  let depth = 10000
  let data = "[".repeat(depth) + "0" + "]".repeat(depth)
  let body = prepare(
    collected(
      ",\"effects\":{\"e\":{\"create\":{\"payload\":{\"x\":" + data + "}}}}",
    ),
    caps(),
  ).unwrap()
  let output = rendered(body)
  let measure = @encode.measuring_writer(output.length(), 100000, 20000)
  emit(body, measure)
  assert_eq(@encode.finish_measurement(measure), output.length())
  let small = prepare(collected(""), caps()).unwrap()
  let size = rendered(small).length()
  assert_eq(size, 118)
  let hash = @encode.hashing_writer(118, 100, 100)
  emit(small, hash)
  // Independent Node crypto digest of the fixed canonical source fixture.
  assert_eq(
    @encode.finish_hash(hash),
    "fa6aa274507e29e1b1ffaac36e3bdebf55410427af9a830ee94c82fcd1fdd58a",
  )
  for bytes in [size - 1, size, size + 1] {
    for nodes in 0..<20 {
      for depth in 0..<6 {
        let accepted = []
        for kind in 0..<3 {
          let ok = try {
            let writer = if kind == 0 {
              @encode.writer(bytes, nodes, depth)
            } else if kind == 1 {
              @encode.measuring_writer(bytes, nodes, depth)
            } else {
              @encode.hashing_writer(bytes, nodes, depth)
            }
            emit(small, writer)
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
          accepted.push(ok)
        }
        assert_eq(accepted[0], accepted[1])
        assert_eq(accepted[1], accepted[2])
      }
    }
  }
}

///|
test "import source references survive without Stage identity or predecessor fields" {
  let text =
    #|{"version":"actql/0.1","id":"p","stages":[{"id":"a","inputs":{"rows":"relation"},"steps":[],"results":{"r":{}}},{"id":"b","after":"accepted","inputs":{"rows":{"result":{"stage":"a","result":"r"},"meta":{"note":"omit"}}},"steps":[],"results":{"r":{"from":"rows","fields":["amount"]}}}],"results":{"out":{"from":{"stage":"b","result":"r"}}}}
  let body = prepare(
    collected("", source_text=Some(text), stage_index=1),
    caps(),
  ).unwrap()
  assert_eq(@stages.stage_index(stage(body)), 1)
  assert_eq(
    rendered(body),
    (
      #|{"effects":{},"inputs":{"rows":{"result":{"result":"r","stage":"a"}}},"results":{"r":{"fields":["amount"],"from":"rows"}},"steps":[]}
    ),
  )
  let other = prepare(
    collected(
      "",
      source_text=Some(text.replace(old="accepted", new="completed")),
      stage_index=1,
    ),
    caps(),
  ).unwrap()
  assert_eq(rendered(body), rendered(other))
  assert_true(!physical_equal(stage(body), stage(other)))
}
