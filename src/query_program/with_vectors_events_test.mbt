///|
// Independently authored machine Programs. Logical producer names deliberately
// differ from generated Frontend names; only operation arguments are compared.
fn with_vector_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.vector_control","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"item_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"item_id":"b","embedding":[0,1],"label":"second"},{"item_id":"a","embedding":[1,0],"label":"first"}]},"as":"candidates"},{"from":"candidates","to_vectors":{"id":"item_id","vector":"embedding"},"as":"prepared"},{"from":"prepared","score_vectors":{"query":[1,0],"metric":"dot"},"as":"scored"},{"from":"scored","vectors":true},{"sort":[{"field":"score","dir":"desc","nulls":"last"},{"field":"item_id","dir":"asc","nulls":"first"}]},{"select":["item_id","score"],"as":"answer"}],"results":{"rows":{"from":"answer","fields":["item_id","score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn with_event_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.event_control","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"event_id":{"type":"number","nullable":false},"occurred_ms":{"type":"number","nullable":false},"customer_id":{"type":"string","nullable":false}},"rows":[{"event_id":1,"occurred_ms":0,"customer_id":"u"},{"event_id":2,"occurred_ms":299999,"customer_id":"u"},{"event_id":3,"occurred_ms":599999,"customer_id":"u"}]},"as":"source_rows"},{"from":"source_rows","to_events":{"id":"event_id","time":"occurred_ms"},"as":"ev"},{"from":"ev","session":{"by":["customer_id"],"gap":"5m"},"as":"grouped"},{"from":"grouped","events":true},{"sort":[{"field":"event_id","dir":"asc","nulls":"first"}]},{"select":["event_id","session_start_ms","session_end_ms"],"as":"answer"}],"results":{"rows":{"from":"answer","fields":["event_id","session_start_ms","session_end_ms"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn with_carrier_argument(
  program : @program.Program,
  operation : String,
) -> String raise {
  let stage = @program.stages(program)[0]
  let steps = @wire.required(
    @wire.open_object(@program.stage_body(stage)).unwrap(),
    "steps",
  ).unwrap()
  let matches = @wire.elements(steps)
    .unwrap()
    .filter_map(step => {
      @wire.lookup(@wire.open_object(step).unwrap(), operation)
    })
  assert_eq(matches.length(), 1)
  let writer = @encode.writer(100000, 10000, 100)
  @program.emit_admitted_source_value(matches[0], writer)
  @encode.finish(writer)
}

///|
fn with_carrier_program(
  text : String,
  context : Context,
) -> Result[@program.Program, Issue] {
  compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    context,
    construction_limits(),
  )
}

///|
test "WITH preserves Vectors between bindings and only vectors bridges to Relation" {
  let text = "WITH prepared AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)), scored AS (FROM prepared |> score_vectors(query: [1, 0], metric: 'dot')), ranked_rows AS (FROM scored |> vectors()) SELECT item_id, score FROM ranked_rows ORDER BY score DESC, item_id"
  let actual = with_carrier_program(text, nearest_context()).unwrap()
  let control = with_vector_control()
  for operation in ["to_vectors", "score_vectors", "vectors"] {
    assert_eq(
      with_carrier_argument(actual, operation),
      with_carrier_argument(control, operation),
    )
  }
  guard @check.check_parsed(
      control,
      check_environment(veca=true),
      None,
      check_limits(),
    )
    is Checked(_) else {
    fail("independent Vector machine control must check")
  }
  match
    @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed vector input")
  }
}

///|
test "WITH Events session keeps typed clock and explicit bridge" {
  let actual = with_carrier_program(
    "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms, 'u' AS customer_id UNION ALL SELECT 2, 299999, 'u' UNION ALL SELECT 3, 599999, 'u'), ev AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), grouped AS (FROM ev |> session(by: [customer_id], gap: '5m')), event_result AS (FROM grouped |> events()) SELECT event_id, session_start_ms, session_end_ms FROM event_result ORDER BY event_id",
    { ..pair_context(), inputs: [], },
  ).unwrap()
  let control = with_event_control()
  for operation in ["to_events", "session", "events"] {
    assert_eq(
      with_carrier_argument(actual, operation),
      with_carrier_argument(control, operation),
    )
  }
  let source = @stage_parameters.prepare(control, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  assert_true(
    @stage_results.check_local_program(source, {
      max_stages: 10,
      max_steps: 100,
      max_results: 100,
      max_work: 1000000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    })
    is Ok(_),
  )
}

///|
test "WITH typed producer cannot use a row range or skip explicit bridge" {
  let prefix = "WITH prepared AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) "
  for
    tail in [
      "FROM prepared AS p |> vectors()", "FROM prepared |> AS p |> vectors()",
    ] {
    assert_true(
      with_carrier_program(prefix + tail, nearest_context())
      is Err(RangeAliasRequiresRelation),
    )
  }
  assert_true(
    with_carrier_program(
      prefix + "SELECT item_id FROM prepared",
      nearest_context(),
    )
    is Err(UnsupportedProjection),
  )
  assert_true(
    with_carrier_program(
      prefix + "FROM prepared |> vectors() |> AS p |> SELECT p.item_id",
      nearest_context(),
    )
    is Ok(_),
  )
}

///|
test "WITH carrier prefix never discards an unlowered Graph call" {
  let queries = [
    "WITH prepared AS (FROM candidates |> to_vectors(id: item_id, vector: embedding) |> components(kind: 'weak')) FROM prepared |> vectors() |> SELECT item_id",
    "WITH prepared AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) FROM prepared |> vectors() |> components(kind: 'weak') |> SELECT item_id",
  ]
  for text in queries {
    assert_true(with_carrier_program(text, nearest_context()) is Err(UnsupportedGraph))
  }
}
