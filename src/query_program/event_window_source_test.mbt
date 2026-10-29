///|
// These machine controls are authored from the existing window/watermark
// contracts. No arguments or expected Program fragments come from compilation.
fn event_window_control(
  event : Bool,
  body : String,
  watermark? : String? = None,
  parameters? : Bool = false,
) -> @program.Program {
  let boundaries = if event {
    "\"window_start_ms\",\"window_end_ms\""
  } else {
    "\"window_start\",\"window_end\""
  }
  let selected = "\"event_id\",\"occurred_ms\"," +
    boundaries +
    (if watermark is Some(_) {
      ",\"watermark_ms\",\"late\",\"watermark_decision\""
    } else {
      ""
    })
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.event_window\"," +
    (if parameters { "\"params\":{\"p\":{\"type\":\"number\"}}," } else { "" }) +
    "\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    "{\"values\":{\"schema\":{\"event_id\":{\"type\":\"number\",\"nullable\":false},\"occurred_ms\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"event_id\":1,\"occurred_ms\":0},{\"event_id\":2,\"occurred_ms\":10}]},\"as\":\"source_rows\"}," +
    (if event {
      "{\"from\":\"source_rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_ms\"},\"as\":\"ev\"},"
    } else {
      ""
    }) +
    "{\"from\":\"" +
    (if event { "ev" } else { "source_rows" }) +
    "\",\"" +
    (if event { "window_events" } else { "row_window" }) +
    "\":" +
    body +
    ",\"as\":\"windowed\"}," +
    (match watermark {
      Some(body) =>
        "{\"from\":\"windowed\",\"watermark_events\":" +
        body +
        ",\"as\":\"marked\"},"
      None => ""
    }) +
    (if event {
      "{\"from\":\"" +
      (if watermark is Some(_) { "marked" } else { "windowed" }) +
      "\",\"events\":true},"
    } else {
      ""
    }) +
    "{\"sort\":[{\"field\":\"event_id\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"" +
    (if event { "window_start_ms" } else { "window_start" }) +
    "\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[" +
    selected +
    "],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[" +
    selected +
    "]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn event_window_common_checked(program : @program.Program) -> Unit raise {
  let source = @stage_parameters.prepare(program, {
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
    msg="independent existing window/Events contract must check",
  )
}

///|
fn event_window_source(
  event : Bool,
  call : String,
  watermark? : String? = None,
) -> String {
  "WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms UNION ALL SELECT 2, 10), " +
  (if event {
    "ev AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms)), "
  } else {
    ""
  }) +
  "windowed AS (FROM " +
  (if event { "ev" } else { "source_rows AS r" }) +
  " |> " +
  call +
  "), " +
  (match watermark {
    Some(call) => "marked AS (FROM windowed |> " + call + "), "
    None => ""
  }) +
  "result_rows AS (FROM " +
  (if watermark is Some(_) { "marked" } else { "windowed" }) +
  (if event { " |> events()" } else { "" }) +
  ") SELECT event_id, occurred_ms, " +
  (if event {
    "window_start_ms, window_end_ms"
  } else {
    "window_start, window_end"
  }) +
  (if watermark is Some(_) {
    ", watermark_ms, late, watermark_decision"
  } else {
    ""
  }) +
  " FROM result_rows ORDER BY event_id, " +
  (if event { "window_start_ms" } else { "window_start" })
}

///|
fn event_window_issue(text : String) -> @pipeline.IssueKind raise {
  match
    with_carrier_program(text, {
      ..pair_context(),
      inputs: [],
      parameter_declarations: Some(number_parameter_declarations()),
    }) {
    Err(BindingPreparation(LocalProgram(Pipeline(0, issue)))) => issue.kind
    Err(_) => fail("Unexpected window refusal boundary")
    Ok(_) => fail("Invalid window must not be admitted")
  }
}

///|
test "P2 window source retains common invalid body duration and Carrier refusals" {
  let prefix = "WITH `rows` AS (SELECT 1 AS event_id, 0 AS occurred_ms), ev AS (FROM rows |> to_events(id: event_id, time: occurred_ms)) "
  let cases : Array[(String, @pipeline.IssueKind)] = [
    (
      "FROM rows |> row_window(time: occurred_ms, kind: 'FIXED', size: 10)",
      Window(InvalidBody),
    ),
    (
      "FROM rows |> row_window(time: occurred_ms, kind: 'sliding', size: 10)",
      Window(InvalidBody),
    ),
    (
      "FROM rows |> row_window(time: occurred_ms, kind: 'fixed', size: 10, step: 0)",
      Window(InvalidMilliseconds),
    ),
    (
      "FROM rows |> row_window(time: occurred_ms, kind: 'fixed', size: 10, offset: 0.5)",
      Window(InvalidMilliseconds),
    ),
    (
      "FROM rows |> window_events(kind: 'fixed', size: 10)",
      WrongCarrier(RelationKind),
    ),
    (
      "FROM ev |> row_window(time: occurred_ms, kind: 'fixed', size: 10)",
      WrongCarrier(EventsKind),
    ),
    (
      "FROM ev |> watermark_events(watermark_ms: 0, policy: 'MARK')",
      Event(InvalidBody),
    ),
    (
      "FROM rows |> watermark_events(watermark_ms: 0, policy: 'mark')",
      Event(WrongCarrier(RelationKind)),
    ),
  ]
  for (call, expected) in cases {
    assert_eq(event_window_issue(prefix + call), expected)
  }
  assert_true(
    with_carrier_program(
      prefix + "FROM rows |> row_window(time: missing, kind: 'fixed', size: 10)",
      { ..pair_context(), inputs: [], },
    )
    is Err(UnknownColumn),
  )
  assert_true(
    with_carrier_program(
      prefix +
      "FROM rows |> row_window(time: occurred_ms, kind: 'fixed', size: 10, max_output_rows: 1)",
      { ..pair_context(), inputs: [], },
    )
    is Err(InvalidQuery),
  )
}

///|
test "P2 window omission does not synthesize step or offset into authored Program" {
  for event in [false, true] {
    let operation = if event { "window_events" } else { "row_window" }
    let body = "{\"kind\":\"fixed\",\"size\":\"10ms\"" +
      (if event { "" } else { ",\"time\":\"occurred_ms\"" }) +
      "}"
    let actual = with_carrier_program(
      event_window_source(
        event,
        operation +
        "(kind: 'fixed', size: '10ms'" +
        (if event { "" } else { ", time: r.occurred_ms" }) +
        ")",
      ),
      { ..pair_context(), inputs: [], },
    ).unwrap()
    assert_eq(
      with_carrier_argument(actual, operation),
      with_carrier_argument(event_window_control(event, body), operation),
    )
    event_window_common_checked(actual)
  }
}

///|
test "P2 independent windows retain fixed step offset and whole Parameters" {
  for event in [false, true] {
    for
      body in [
        "{\"kind\":\"fixed\",\"size\":10,\"step\":3,\"offset\":-2}", "{\"kind\":\"sliding\",\"size\":10,\"step\":3,\"offset\":2}",
        "{\"kind\":\"fixed\",\"size\":{\"$param\":\"p\"},\"step\":{\"$param\":\"p\"},\"offset\":{\"$param\":\"p\"}}",
      ] {
      let body = if event {
        body
      } else {
        body.replace(
          old="{\"kind\":",
          new="{\"time\":\"occurred_ms\",\"kind\":",
        )
      }
      event_window_common_checked(
        event_window_control(event, body, parameters=body.contains("$param")),
      )
    }
  }
  for policy in ["mark", "drop"] {
    event_window_common_checked(
      event_window_control(
        true,
        "{\"kind\":\"fixed\",\"size\":10,\"offset\":-2}",
        watermark=Some("{\"watermark_ms\":-0.5,\"policy\":\"" + policy + "\"}"),
      ),
    )
  }
}

///|
test "P2 window source preserves closed arguments against independent Programs" {
  for event in [false, true] {
    for kind in ["fixed", "sliding"] {
      let body = "{\"kind\":\"" +
        kind +
        "\",\"size\":10,\"step\":3,\"offset\":-2" +
        (if event { "" } else { ",\"time\":\"occurred_ms\"" }) +
        "}"
      let operation = if event { "window_events" } else { "row_window" }
      let text = event_window_source(
        event,
        operation +
        "(kind: '" +
        kind +
        "', size: 10, step: 3, offset: -2" +
        (if event { "" } else { ", time: r.OCCURRED_MS" }) +
        ")",
      )
      let actual = with_carrier_program(text, { ..pair_context(), inputs: [], }).unwrap()
      let control = event_window_control(event, body)
      assert_eq(
        with_carrier_argument(actual, operation),
        with_carrier_argument(control, operation),
      )
      event_window_common_checked(actual)
    }
  }
}

///|
test "P2 event watermark source preserves fractional threshold and exact policies" {
  for policy in ["mark", "drop"] {
    let body = "{\"kind\":\"fixed\",\"size\":10,\"offset\":-2}"
    let mark = "{\"watermark_ms\":-0.5,\"policy\":\"" + policy + "\"}"
    let actual = with_carrier_program(
      event_window_source(
        true,
        "window_events(kind: 'fixed', size: 10, offset: -2)",
        watermark=Some(
          "watermark_events(watermark_ms: -0.5, policy: '" + policy + "')",
        ),
      ),
      { ..pair_context(), inputs: [], },
    ).unwrap()
    let control = event_window_control(true, body, watermark=Some(mark))
    for operation in ["window_events", "watermark_events", "events"] {
      assert_eq(
        with_carrier_argument(actual, operation),
        with_carrier_argument(control, operation),
      )
    }
    event_window_common_checked(actual)
  }
}

///|
test "P2 window Parameters keep their declarations and references before binding" {
  for event in [false, true] {
    let operation = if event { "window_events" } else { "row_window" }
    let text = event_window_source(
      event,
      operation +
      "(kind: 'fixed', size: @p, step: @p, offset: @p" +
      (if event { "" } else { ", time: r.occurred_ms" }) +
      ")",
    )
    let actual = with_carrier_program(text, {
      ..pair_context(),
      inputs: [],
      parameter_declarations: Some(number_parameter_declarations()),
    }).unwrap()
    let body = "{\"kind\":\"fixed\",\"size\":{\"$param\":\"p\"},\"step\":{\"$param\":\"p\"},\"offset\":{\"$param\":\"p\"}" +
      (if event { "" } else { ",\"time\":\"occurred_ms\"" }) +
      "}"
    let control = event_window_control(event, body, parameters=true)
    assert_eq(
      with_carrier_argument(actual, operation),
      with_carrier_argument(control, operation),
    )
    event_window_common_checked(actual)
  }
}

///|
test "watermark whole numeric Parameter source agrees with its independent machine control" {
  let actual = with_carrier_program(
    event_window_source(
      true,
      "window_events(kind: 'fixed', size: 10)",
      watermark=Some("watermark_events(watermark_ms: @p, policy: 'mark')"),
    ),
    {
      ..pair_context(),
      inputs: [],
      parameter_declarations: Some(number_parameter_declarations()),
    },
  ).unwrap()
  let control = event_window_control(
    true,
    "{\"kind\":\"fixed\",\"size\":10}",
    watermark=Some("{\"watermark_ms\":{\"$param\":\"p\"},\"policy\":\"mark\"}"),
    parameters=true,
  )
  assert_eq(
    with_carrier_argument(actual, "watermark_events"),
    with_carrier_argument(control, "watermark_events"),
  )
  event_window_common_checked(actual)
  event_window_common_checked(control)
}

///|
test "watermark whole Parameter support retains undeclared parameter refusal" {
  let control = event_window_control(
    true,
    "{\"kind\":\"fixed\",\"size\":10}",
    watermark=Some(
      "{\"watermark_ms\":{\"$param\":\"missing\"},\"policy\":\"mark\"}",
    ),
    parameters=true,
  )
  let source = @stage_parameters.prepare(control, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  match
    @stage_results.check_local_program(source, {
      max_stages: 10,
      max_steps: 100,
      max_results: 100,
      max_work: 1000000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    }) {
    Err(Pipeline(stage, issue)) => {
      assert_eq(stage, 0)
      assert_true(issue.kind is Event(UnknownParameter("missing")))
    }
    _ => fail("whole Parameter support does not invent a declaration")
  }
}
