///|
fn carrier_events_source_owner_with(
  time_type : String,
  rows : String,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"event_id\":{\"type\":\"number\"," +
      "\"nullable\":false},\"occurred_at\":{\"type\":\"" +
      time_type +
      "\",\"nullable\":false},\"payload\":{\"type\":\"string\"," +
      "\"nullable\":false}},\"rows\":" +
      rows +
      "},\"as\":\"source\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn carrier_events_source_owner() -> @lower.BoundPrepared {
  carrier_events_source_owner_with(
    "number",
    "[{\"event_id\":1,\"occurred_at\":11,\"payload\":\"first\"}," +
    "{\"event_id\":2,\"occurred_at\":9,\"payload\":\"late\"}]",
  )
}

///|
fn carrier_events_relation_followup(variant : String) -> Bool {
  variant == "dedupe_filter" ||
  variant == "session_filter" ||
  variant == "session_select" ||
  variant == "session_derive" ||
  variant == "session_take"
}

///|
fn local_carrier_events_program(variant? : String = "watermark") -> String {
  let dedupe = variant == "dedupe" || variant == "dedupe_filter"
  let window = variant == "window_fixed" ||
    variant == "window_sliding" ||
    variant == "window_parameter"
  let sequence = variant == "sequence"
  let session = variant.has_prefix("session")
  let session_global = variant == "session_global"
  let session_parameter = variant == "session_parameter"
  let session_relation = variant == "session_relation"
  let fields = if sequence {
    "[\"match_start_ms\",\"match_end_ms\",\"start_id\"," +
    "\"start_time_ms\",\"end_id\",\"end_time_ms\"]"
  } else if dedupe {
    "[\"event_id\",\"occurred_at\",\"payload\"]"
  } else if window {
    "[\"event_id\",\"occurred_at\",\"payload\"," +
    "\"window_start_ms\",\"window_end_ms\"]"
  } else if session {
    "[\"event_id\",\"occurred_at\",\"payload\"," +
    "\"session_start_ms\",\"session_end_ms\",\"session_id\"]"
  } else {
    "[\"event_id\",\"occurred_at\",\"payload\"," +
    "\"watermark_ms\",\"late\",\"watermark_decision\"]"
  }
  let rows = if dedupe {
    "[{\"event_id\":1,\"occurred_at\":20,\"payload\":\"a\"}," +
    "{\"event_id\":2,\"occurred_at\":10,\"payload\":\"a\"}," +
    "{\"event_id\":3,\"occurred_at\":30,\"payload\":\"b\"}," +
    "{\"event_id\":4,\"occurred_at\":5,\"payload\":\"b\"}]"
  } else if variant == "session_ties" {
    "[{\"event_id\":2,\"occurred_at\":1,\"payload\":\"a\"}," +
    "{\"event_id\":1,\"occurred_at\":1,\"payload\":\"a\"}," +
    "{\"event_id\":3,\"occurred_at\":13,\"payload\":\"a\"}]"
  } else if session_global {
    "[{\"event_id\":2,\"occurred_at\":1,\"payload\":\"a\"}," +
    "{\"event_id\":1,\"occurred_at\":3,\"payload\":\"b\"}," +
    "{\"event_id\":3,\"occurred_at\":13,\"payload\":\"a\"}]"
  } else if session {
    "[{\"event_id\":2,\"occurred_at\":1,\"payload\":\"a\"}," +
    "{\"event_id\":1,\"occurred_at\":3,\"payload\":\"a\"}," +
    "{\"event_id\":3,\"occurred_at\":13,\"payload\":\"a\"}]"
  } else {
    "[{\"event_id\":1,\"occurred_at\":3,\"payload\":\"first\"}," +
    "{\"event_id\":2,\"occurred_at\":1,\"payload\":\"late\"}," +
    "{\"event_id\":3,\"occurred_at\":2,\"payload\":\"edge\"}]"
  }
  let transform = if sequence {
    "{\"sequence\":{\"by\":[],\"id\":\"event_id\"," +
    "\"time\":\"occurred_at\",\"pattern\":[{\"as\":\"start\"," +
    "\"where\":{\"literal\":true}},{\"as\":\"end\"," +
    "\"where\":{\"literal\":true}}],\"within\":10," +
    "\"overlap\":\"allow\",\"contiguity\":\"subsequence\"}," +
    "\"as\":\"out\"}"
  } else if dedupe {
    "{\"dedupe_events\":{\"by\":[\"payload\"],\"order_by\":[{" +
    "\"field\":\"occurred_at\",\"dir\":\"asc\"," +
    "\"nulls\":\"last\"}]}}"
  } else if variant == "window_fixed" {
    "{\"window_events\":{\"kind\":\"fixed\",\"size\":10}}"
  } else if variant == "window_sliding" {
    "{\"window_events\":{\"kind\":\"sliding\",\"size\":10," + "\"step\":5}}"
  } else if variant == "window_parameter" {
    "{\"window_events\":{\"kind\":\"fixed\",\"size\":{" +
    "\"$param\":\"window_size\"}}}"
  } else if session {
    "{\"session\":{\"by\":" +
    (if session_global { "[]" } else { "[\"payload\"]" }) +
    ",\"gap\":" +
    (if session_parameter { "{\"$param\":\"minimum\"}" } else { "10" }) +
    "}}"
  } else {
    "{\"watermark_events\":{\"watermark_ms\":2," + "\"policy\":\"mark\"}}"
  }
  let second_fields = if sequence {
    "[\"end_id\",\"start_id\",\"match_start_ms\"]"
  } else if dedupe {
    "[\"payload\",\"event_id\"]"
  } else if window {
    "[\"payload\",\"window_start_ms\",\"event_id\"]"
  } else if session {
    "[\"payload\",\"session_id\",\"event_id\"]"
  } else {
    "[\"watermark_decision\",\"late\",\"event_id\"]"
  }
  let event_steps = if session_relation {
    "{\"from\":\"rows\",\"session\":{\"id\":\"event_id\"," +
    "\"time\":\"occurred_at\",\"by\":[\"payload\"],\"gap\":10}," +
    "\"as\":\"out\"}"
  } else if sequence {
    "{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\"," +
    "\"time\":\"occurred_at\"}}," +
    transform
  } else {
    "{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\"," +
    "\"time\":\"occurred_at\"}}," +
    transform +
    ",{\"events\":true,\"as\":" +
    (if carrier_events_relation_followup(variant) {
      "\"projected\"}"
    } else {
      "\"out\"}"
    }) +
    (if carrier_events_relation_followup(variant) {
      ",{" +
      "\"from\":\"projected\"," +
      (if variant == "session_select" {
        "\"select\":" + fields
      } else if variant == "session_derive" {
        "\"derive\":{\"copy\":\"event_id\"}"
      } else if variant == "session_take" {
        "\"take\":3"
      } else {
        "\"filter\":\"true\""
      }) +
      ",\"as\":\"out\"}"
    } else {
      ""
    })
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  "{\"minimum\":{\"type\":\"number\",\"nullable\":false}" +
  (if variant == "window_parameter" {
    ",\"window_size\":{\"type\":\"number\",\"nullable\":false}"
  } else {
    ""
  }) +
  "}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"values\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":{\"event_id\":{\"type\":\"number\",\"nullable\":false}," +
  "\"occurred_at\":{\"type\":\"number\",\"nullable\":false}," +
  "\"payload\":{\"type\":\"string\",\"nullable\":false}}," +
  "\"rows\":" +
  rows +
  "}," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"event_id\",\"occurred_at\",\"payload\"]}}},{" +
  "\"id\":\"events\",\"inputs\":{\"rows\":{\"result\":{" +
  "\"stage\":\"values\",\"result\":\"r\"}}},\"steps\":[" +
  event_steps +
  "],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"events\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"events\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  second_fields +
  "," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  second_fields +
  "}}}]," +
  "\"results\":{\"source\":{\"from\":{\"stage\":\"a\"," +
  "\"result\":\"r\"}}}}"
}

///|
fn carrier_events_owner(
  source : @lower.BoundPrepared,
  variant? : String = "watermark",
) -> @lower.BoundPrepared {
  let session = variant.has_prefix("session")
  let window_parameter = variant == "window_parameter"
  let session_global = variant == "session_global"
  let session_parameter = variant == "session_parameter"
  let transform = if variant == "dedupe" {
    "{\"dedupe_events\":{\"by\":[\"payload\"],\"order_by\":[{" +
    "\"field\":\"occurred_at\",\"dir\":\"asc\"," +
    "\"nulls\":\"last\"}]}}"
  } else if variant == "window_fixed" {
    "{\"window_events\":{\"kind\":\"fixed\",\"size\":10}}"
  } else if variant == "window_sliding" {
    "{\"window_events\":{\"kind\":\"sliding\",\"size\":10," + "\"step\":5}}"
  } else if window_parameter {
    "{\"window_events\":{\"kind\":\"fixed\",\"size\":{" +
    "\"$param\":\"size\"}}}"
  } else if session {
    "{\"session\":{\"by\":" +
    (if session_global { "[]" } else { "[\"payload\"]" }) +
    ",\"gap\":" +
    (if session_parameter { "{\"$param\":\"gap\"}" } else { "10" }) +
    "}}"
  } else {
    "{\"watermark_events\":{\"watermark_ms\":10," + "\"policy\":\"mark\"}}"
  }
  let declarations = if session_parameter || window_parameter {
    Some(
      @parameter.read_declarations(
        Some(
          input_cursor(
            if window_parameter {
              "{\"size\":{\"type\":\"number\",\"nullable\":false}}"
            } else {
              "{\"gap\":{\"type\":\"number\",\"nullable\":false}}"
            },
          ),
        ),
        {
          max_parameters: 1,
          max_nodes: 10,
          max_depth: 10,
          max_text_bytes: 100,
        },
      ).unwrap(),
    )
  } else {
    None
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\"," +
      "\"time\":\"occurred_at\"}}," +
      transform +
      ",{\"events\":true}]",
    ),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    declarations,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let bound = match declarations {
    Some(declarations) =>
      match
        @parameter.bind(
          declarations,
          Some(
            input_cursor(
              if window_parameter {
                "{\"size\":10}"
              } else {
                "{\"gap\":2}"
              },
            ),
          ),
          { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
        ).unwrap() {
        @parameter.Ready(value) => Some(value)
        @parameter.NeedsBindings(_) => abort("missing session gap binding")
      }
    None => None
  }
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    bound,
    max_parameters=if session_parameter || window_parameter { 1 } else { 0 },
    max_name_bytes=if window_parameter {
      4
    } else if session_parameter {
      3
    } else {
      0
    },
  ).unwrap()
}

///|
fn carrier_events_publication_cid(variant : String) -> String {
  if variant == "dedupe" {
    "sha256:058f941f294541f1b2c6a5ee64dc74b06f03433d3474a9bc0a23a4c8e5ccf00b"
  } else if variant == "window_fixed" {
    "sha256:5528c393bdc40f682c1c7271183d2c43814871a253da19ee7fa9891ee59a9007"
  } else if variant == "window_sliding" {
    "sha256:c2ba9666c6a15ecbd0374413e5a94768d7dd66767bf17a710fbecd6a165a1cf8"
  } else if variant == "window_parameter" {
    "sha256:5528c393bdc40f682c1c7271183d2c43814871a253da19ee7fa9891ee59a9007"
  } else if variant == "session" || variant == "session_relation" {
    "sha256:cdb4e95a24f02c009ed6e25c03c17311d529d7941e7f594b24e73b5bc1d23ba3"
  } else if variant == "session_global" {
    "sha256:3d11a1af6cc603d13e7ef2e61dcfa8ebcf6fab726d5ee1289dc6ed161c0e75fe"
  } else if variant == "session_parameter" {
    "sha256:8f9b470417ca8c3ad8e28ac19d246e39503c5853682b321c9085425efc8d105d"
  } else {
    "sha256:ab1d5abbd65428f1057ba688c602e34789e9b6cacfa73890c30741cba90cc11e"
  }
}

///|
fn carrier_events_output_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"rows\",\"to_events\":{" +
      "\"id\":\"event_id\",\"time\":\"occurred_at\"}}]",
    ),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn carrier_events_session_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"events\",\"session\":{" +
      "\"by\":[\"payload\"],\"gap\":10}}]",
    ),
    [
      (
        "events",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"events\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn carrier_events_sequence_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"events\",\"sequence\":{" +
      "\"by\":[],\"id\":\"event_id\",\"time\":\"occurred_at\"," +
      "\"pattern\":[{\"as\":\"start\",\"where\":{" +
      "\"literal\":true}},{\"as\":\"end\",\"where\":{" +
      "\"literal\":true}}],\"within\":10," +
      "\"overlap\":\"allow\",\"contiguity\":\"subsequence\"}}]",
    ),
    [
      (
        "events",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"events\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn carrier_events_projection_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"events\",\"events\":true}]"),
    [
      (
        "events",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"events\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn carrier_events_storage_limits() -> @record_storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn delayed_cleanup_provider(
  provider : @local_connector.ManagedProvider,
  attempts : Ref[Int],
) -> @local_connector.ManagedProvider {
  @local_connector.managed_provider(
    sequence => @local_connector.managed_provider_accepts(provider, sequence),
    sequence => @local_connector.managed_provider_capacity(provider, sequence),
    fn(sequence, inputs, max_rows, max_value_bytes, execution) {
      match
        @local_connector.start_managed_provider_with_execution(
          provider, sequence, inputs, max_rows, max_value_bytes, execution,
        ) {
        Err(issue) => Err(issue)
        Ok(active) =>
          Ok(
            @local_connector.managed_provider_execution(
              quantum => {
                @local_connector.advance_managed_provider(active, quantum)
              },
              fn() { @local_connector.cancel_managed_provider(active) },
              fn() { @local_connector.managed_provider_stopped(active) },
              fn() {
                attempts.val += 1
                if attempts.val == 1 {
                  Ok(false)
                } else {
                  @local_connector.cleanup_managed_provider(active)
                }
              },
            ),
          )
      }
    },
  )
}

///|
fn finish_rows_to_events(
  execution : @local_bridge.RowsToEventsExecution,
) -> @records.Completed {
  while true {
    match @local_bridge.advance_rows_to_events(execution, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => return output
      @local_bridge.Failed(_, ..) => abort("rows-to-events failed")
      @local_bridge.Stopped(_, ..) => abort("rows-to-events stopped")
    }
  }
  abort("unreachable")
}

///|
fn finish_event_watermark(
  execution : @local_tea.WatermarkExecution,
) -> @records.Completed {
  while true {
    match @local_tea.advance_watermark(execution, 1).unwrap() {
      @local_tea.Continue(..) => ()
      @local_tea.Complete(output, ..) => return output
      @local_tea.Failed(_, ..) => abort("event watermark failed")
      @local_tea.Stopped(_, ..) => abort("event watermark stopped")
    }
  }
  abort("unreachable")
}

///|
fn finish_events_to_rows(
  execution : @local_bridge.EventsToRowsExecution,
) -> @execution.CompletedOutput {
  while true {
    match @local_bridge.advance_events_to_rows(execution, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => return output
      @local_bridge.Failed(_, ..) => abort("events-to-rows failed")
      @local_bridge.Stopped(_, ..) => abort("events-to-rows stopped")
    }
  }
  abort("unreachable")
}

///|
fn carrier_events_source_output(
  owner : @lower.BoundPrepared,
) -> @execution.CompletedOutput raise {
  let result = @execution.execute_generated_sequence(
    compute_test_sequence(owner),
    [],
    compute_test_limits(),
  ).unwrap()
  @execution.completed_output(result, @pipeline.Step(0)).unwrap()
}

///|
fn carrier_events_relation_session_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"rows\",\"session\":{\"id\":\"event_id\"," +
      "\"time\":\"occurred_at\",\"by\":[\"payload\"],\"gap\":10}}]",
    ),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "Relation-backed session rejects duplicate IDs across groups" {
  for payload in ["a", "b"] {
    let producer = carrier_events_source_owner_with(
      "number",
      "[{\"event_id\":1,\"occurred_at\":1,\"payload\":\"a\"}," +
      "{\"event_id\":1,\"occurred_at\":2,\"payload\":\"" +
      payload +
      "\"}]",
    )
    let source = carrier_events_source_output(producer)
    let owner = carrier_events_relation_session_owner(producer)
    let input = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, producer, source).unwrap(),
      100,
      1000,
    ).unwrap()
    let execution = @local_tea.start_session_relation(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      input,
      carrier_events_storage_limits(),
      4096L,
      fn() { true },
    ).unwrap()
    let mut failed = false
    while !failed {
      match @local_tea.advance_session(execution, 1).unwrap() {
        @local_tea.SessionContinue(..) => ()
        @local_tea.SessionFailed(@local_tea.DuplicateSessionIdentity(1), ..) =>
          failed = true
        _ => fail("duplicate relation event ID was not rejected")
      }
    }
    assert_true(@local_tea.session_cleanup_pending(execution))
    assert_eq(@local_tea.cleanup_session(execution), Ok(true))
    assert_true(@execution.producer_read_available(input))
  }
}

///|
test "Relation-backed session rejects empty input before publication" {
  let producer = carrier_events_source_owner_with("number", "[]")
  let source = carrier_events_source_output(producer)
  let owner = carrier_events_relation_session_owner(producer)
  let input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, producer, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let execution = @local_tea.start_session_relation(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    input,
    carrier_events_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    @local_tea.advance_session(execution, 1).unwrap()
    is @local_tea.SessionFailed(@local_tea.EmptySessionInput, ..),
  )
  assert_true(@local_tea.session_cleanup_pending(execution))
  assert_eq(@local_tea.cleanup_session(execution), Ok(true))
  assert_true(@execution.producer_read_available(input))
}

///|
test "Relation-backed session checks combined output workspace" {
  let producer = carrier_events_source_owner_with(
    "number", "[{\"event_id\":1,\"occurred_at\":0,\"payload\":\"a\"}]",
  )
  let source = carrier_events_source_output(producer)
  let owner = carrier_events_relation_session_owner(producer)
  let input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, producer, source).unwrap(),
    100,
    1000,
  ).unwrap()
  assert_eq(@execution.producer_read_row_count(input), 1)
  assert_eq(@schema.field_count(@execution.producer_read_schema(input)), 3)
  // Three scratch cells, three indices, four metadata slots, and twelve
  // temporary emission slots require a simultaneous bound of 22.
  // The one-row session consumes 44 control units across initialization,
  // field loading, ordering, grouping, identity, and output finalization.
  for (workspace_budget, work_budget) in [(22, 44), (21, 44), (22, 43)] {
    let execution = @local_tea.start_session_relation(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      input,
      {
        ..carrier_events_storage_limits(),
        max_workspace_slots: workspace_budget,
      },
      4096L,
      fn() { true },
      control_work_limit=Some(work_budget),
    ).unwrap()
    let mut terminal = false
    for _ in 0..<64 {
      if terminal {
        break
      }
      match @local_tea.advance_session(execution, 1).unwrap() {
        @local_tea.SessionContinue(..) => ()
        @local_tea.SessionComplete(output, ..) => {
          assert_true(workspace_budget == 22 && work_budget == 44)
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        @local_tea.SessionFailed(@local_tea.SessionWorkspaceLimit, ..) => {
          assert_eq(workspace_budget, 21)
          assert_true(@local_tea.session_cleanup_pending(execution))
          terminal = true
        }
        @local_tea.SessionFailed(@local_tea.SessionControlWorkLimit, ..) => {
          assert_eq(work_budget, 43)
          assert_true(@local_tea.session_cleanup_pending(execution))
          terminal = true
        }
        _ => fail("unexpected Relation-backed session workspace result")
      }
    }
    assert_true(terminal)
    assert_true(@local_tea.cleanup_session(execution).unwrap())
    assert_true(@execution.producer_read_available(input))
  }
  let control = @bounded.control()
  let interrupted = @local_tea.start_session_relation(
    control,
    prepared_sequence(owner),
    0,
    input,
    { ..carrier_events_storage_limits(), max_workspace_slots: 22, },
    4096L,
    fn() { true },
    control_work_limit=Some(44),
  ).unwrap()
  assert_true(
    @local_tea.advance_session(interrupted, 1).unwrap()
    is @local_tea.SessionContinue(work=1L, ..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_tea.advance_session(interrupted, 1).unwrap()
    is @local_tea.SessionStopped(@bounded.Cancelled, ..),
  )
  assert_true(@local_tea.session_cleanup_pending(interrupted))
  assert_true(@local_tea.cleanup_session(interrupted).unwrap())
  assert_true(@execution.producer_read_available(input))
}

///|
test "Events-view session checks combined output workspace" {
  let source_owner = carrier_events_source_owner_with(
    "number", "[{\"event_id\":1,\"occurred_at\":0,\"payload\":\"a\"}]",
  )
  let source = carrier_events_source_output(source_owner)
  let events_owner = carrier_events_output_owner(source_owner)
  let generated = task_test_generated(events_owner)
  let external = @execution.prepare_producer_read(
    events_owner,
    @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let provider = @local_tea_provider.provider(
    carrier_events_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let producing = @local_connector.start_managed_provider(
    provider,
    generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut material = None
  while material is None {
    match @local_connector.advance_managed_provider(producing, 1).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.CarrierComplete(value, ..) => material = Some(value)
      _ => fail("expected Events material")
    }
  }
  assert_true(@local_connector.cleanup_managed_provider(producing).unwrap())
  let material = material.unwrap()
  let owner = carrier_events_session_owner(events_owner)
  for (workspace_budget, work_budget) in [(22, 44), (21, 44), (22, 43)] {
    let view = @carrier_runtime.material_prepare_view(
      material, owner, 0, events_owner,
    ).unwrap()
    assert_eq(@carrier_runtime.producer_view_record_count(view), Some(1))
    assert_eq(@carrier_runtime.producer_view_record_field_count(view, 0), Ok(3))
    let execution = @local_tea.start_session_view(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      view,
      {
        ..carrier_events_storage_limits(),
        max_workspace_slots: workspace_budget,
      },
      4096L,
      fn() { true },
      control_work_limit=Some(work_budget),
    ).unwrap()
    let mut terminal = false
    for _ in 0..<64 {
      if terminal {
        break
      }
      match @local_tea.advance_session(execution, 1).unwrap() {
        @local_tea.SessionContinue(..) => ()
        @local_tea.SessionComplete(output, ..) => {
          assert_true(workspace_budget == 22 && work_budget == 44)
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        @local_tea.SessionFailed(@local_tea.SessionWorkspaceLimit, ..) => {
          assert_eq(workspace_budget, 21)
          assert_true(@local_tea.session_cleanup_pending(execution))
          terminal = true
        }
        @local_tea.SessionFailed(@local_tea.SessionControlWorkLimit, ..) => {
          assert_eq(work_budget, 43)
          assert_true(@local_tea.session_cleanup_pending(execution))
          terminal = true
        }
        _ => fail("unexpected Events-view session workspace result")
      }
    }
    assert_true(terminal)
    assert_true(@local_tea.cleanup_session(execution).unwrap())
    assert_true(@carrier_runtime.material_available(material))
  }
  let view = @carrier_runtime.material_prepare_view(
    material, owner, 0, events_owner,
  ).unwrap()
  let control = @bounded.control()
  let interrupted = @local_tea.start_session_view(
    control,
    prepared_sequence(owner),
    0,
    view,
    { ..carrier_events_storage_limits(), max_workspace_slots: 22, },
    4096L,
    fn() { true },
    control_work_limit=Some(44),
  ).unwrap()
  assert_true(
    @local_tea.advance_session(interrupted, 1).unwrap()
    is @local_tea.SessionContinue(work=1L, ..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_tea.advance_session(interrupted, 1).unwrap()
    is @local_tea.SessionStopped(@bounded.Cancelled, ..),
  )
  assert_true(@local_tea.session_cleanup_pending(interrupted))
  assert_true(@local_tea.cleanup_session(interrupted).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
fn carrier_events_consumer_output(
  producer : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
  projection : String,
) -> @execution.CompletedOutput raise {
  let consumer = typed_receiver(producer, projection, target=@pipeline.Step(2))
  let binding = @execution.bind_completed_input(consumer, 0, producer, output).unwrap()
  let result = @execution.execute_generated_sequence(
    compute_test_sequence(consumer),
    [],
    compute_test_limits(),
    produced=[binding],
  ).unwrap()
  @execution.completed_output(result, @pipeline.Step(0)).unwrap()
}

///|
test "completed Events relation bridge rejects a foreign owner" {
  let source_owner = carrier_events_source_owner()
  let events_owner = carrier_events_output_owner(source_owner)
  let expected_owner = carrier_events_session_owner(events_owner)
  let foreign_owner = carrier_events_session_owner(events_owner)
  let builder = @records.prepare_output(
    expected_owner,
    @pipeline.Step(0),
    carrier_events_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let completed = @records.finish_output(builder).unwrap()
  assert_true(@records.completed_available(completed))

  let rejected = @local_bridge.start_completed_relation_to_rows(
    @bounded.control(),
    task_test_completion(foreign_owner),
    prepared_sequence(foreign_owner),
    0,
    completed,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    [],
  )
  assert_true(rejected is Err(@local_bridge.InvalidKernel))
  assert_true(@records.completed_available(completed))
  assert_true(@records.discard_completed(completed))
  assert_false(@records.completed_available(completed))
}

///|
test "bounded Events bridge round trip feeds two Relation consumers" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_owner(source_owner)
  let generated = task_test_generated(owner)
  assert_true(
    physical_equal(@execution.generated_sequence_owner(generated), owner),
  )
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let storage_limits = carrier_events_storage_limits()

  let rows_execution = @local_bridge.start_rows_to_events(
    @bounded.control(),
    sequence,
    0,
    external,
    storage_limits,
    4096L,
    fn() { true },
  ).unwrap()
  let events = finish_rows_to_events(rows_execution)
  assert_eq(@local_bridge.cleanup_rows_to_events(rows_execution), Ok(true))

  let watermark_input = @records.prepare_step_read(owner, 1, 0, events).unwrap()
  let watermark_execution = @local_tea.start_watermark(
    @bounded.control(),
    sequence,
    1,
    watermark_input,
    storage_limits,
    4096L,
    fn() { true },
  ).unwrap()
  let watermarked = finish_event_watermark(watermark_execution)
  assert_eq(@local_tea.cleanup_watermark(watermark_execution), Ok(true))

  let projection_input = @records.prepare_step_read(owner, 2, 0, watermarked).unwrap()
  let projection = @local_bridge.start_events_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    2,
    projection_input,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    [external],
  ).unwrap()
  let rows = finish_events_to_rows(projection)
  assert_eq(@local_bridge.cleanup_events_to_rows(projection), Ok(true))
  assert_true(@execution.completed_output_available(rows))
  assert_true(@execution.completed_output_matches_inputs(rows, [external]))
  assert_eq(@execution.completed_row_count(rows), 2)

  let first = carrier_events_consumer_output(
    owner, rows, "[{\"select\":[\"event_id\",\"late\",\"watermark_decision\"]}]",
  )
  let second = carrier_events_consumer_output(
    owner, rows, "[{\"select\":[\"payload\",\"watermark_ms\",\"late\"]}]",
  )
  assert_true(@execution.completed_cell(first, 0, 1) is Some(Boolean(false)))
  assert_true(@execution.completed_cell(first, 1, 1) is Some(Boolean(true)))
  assert_true(@execution.completed_cell(first, 1, 2) is Some(Text("mark")))
  assert_true(@execution.completed_cell(second, 0, 0) is Some(Text("first")))
  assert_true(@execution.completed_cell(second, 1, 1) is Some(Number(10.0)))
}

///|
test "Events projection production entrypoint enforces value and width limits" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_owner(source_owner)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let storage_limits = carrier_events_storage_limits()
  let encoding = @local_bridge.start_rows_to_events(
    @bounded.control(),
    sequence,
    0,
    external,
    storage_limits,
    4096L,
    fn() { true },
  ).unwrap()
  let events = finish_rows_to_events(encoding)
  assert_eq(@local_bridge.cleanup_rows_to_events(encoding), Ok(true))
  let watermark_input = @records.prepare_step_read(owner, 1, 0, events).unwrap()
  let watermark = @local_tea.start_watermark(
    @bounded.control(),
    sequence,
    1,
    watermark_input,
    storage_limits,
    4096L,
    fn() { true },
  ).unwrap()
  let watermarked = finish_event_watermark(watermark)
  assert_eq(@local_tea.cleanup_watermark(watermark), Ok(true))
  let projection_input = @records.prepare_step_read(owner, 2, 0, watermarked).unwrap()
  let exact = @local_bridge.start_events_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    2,
    projection_input,
    2,
    { max_nodes: 14, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    6,
    1000,
    [external],
    control_work_limit=Some(26),
  ).unwrap()
  let mut exact_done = false
  for _ in 0..<40 {
    if exact_done {
      break
    }
    match @local_bridge.advance_events_to_rows(exact, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, work~, ..) => {
        assert_eq(work, 26L)
        assert_eq(@execution.completed_row_count(output), 2)
        assert_true(
          @execution.completed_output_matches_inputs(output, [external]),
        )
        exact_done = true
      }
      _ => abort("exact Events projection failed")
    }
  }
  assert_true(exact_done)
  assert_eq(@local_bridge.cleanup_events_to_rows(exact), Ok(true))
  let one_short_work = @local_bridge.start_events_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    2,
    projection_input,
    2,
    { max_nodes: 14, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    6,
    1000,
    [external],
    control_work_limit=Some(25),
  ).unwrap()
  let mut work_failed = false
  for _ in 0..<40 {
    if work_failed {
      break
    }
    match @local_bridge.advance_events_to_rows(one_short_work, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Failed(@local_bridge.ControlWorkLimit, work~, ..) => {
        assert_eq(work, 25L)
        work_failed = true
      }
      _ => abort("one-short Events projection did not reject work")
    }
  }
  assert_true(work_failed)
  assert_eq(@local_bridge.cleanup_events_to_rows(one_short_work), Ok(true))
  let one_short_width = @local_bridge.start_events_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    2,
    projection_input,
    2,
    { max_nodes: 14, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    5,
    1000,
    [external],
  )
  assert_true(
    one_short_width is Err(@local_bridge.Completion(@execution.Limit)),
  )
  let one_short_value = @local_bridge.start_events_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    2,
    projection_input,
    2,
    { max_nodes: 13, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    6,
    1000,
    [external],
  ).unwrap()
  let mut value_failed = false
  for _ in 0..<40 {
    if value_failed {
      break
    }
    match @local_bridge.advance_events_to_rows(one_short_value, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Failed(
        @local_bridge.RelationOutput(@execution.CaptureLimit),
        ..
      ) => value_failed = true
      _ => abort("one-short Events projection did not reject output")
    }
  }
  assert_true(value_failed)
  assert_eq(@local_bridge.cleanup_events_to_rows(one_short_value), Ok(true))
  let control = @bounded.control()
  let cancelled = @local_bridge.start_events_to_rows(
    control,
    task_test_completion(owner),
    sequence,
    2,
    projection_input,
    2,
    { max_nodes: 14, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    6,
    1000,
    [external],
  ).unwrap()
  assert_true(
    @local_bridge.advance_events_to_rows(cancelled, 1).unwrap()
    is @local_bridge.Continue(..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_bridge.advance_events_to_rows(cancelled, 1).unwrap()
    is @local_bridge.Stopped(_, ..),
  )
  assert_eq(@local_bridge.cleanup_events_to_rows(cancelled), Ok(true))
  assert_true(@records.completed_available(watermarked))
  assert_true(@records.discard_completed(watermarked))
  assert_true(@records.discard_completed(events))
  assert_true(@execution.completed_output_available(source))
}

///|
test "Events to rows scans once and enforces projection limits" {
  let source_owner = @lower.bind_parameters(
    @lower.prepare(
      @pipeline.check(
        input_cursor(
          "[{\"values\":{\"schema\":{" +
          "\"alpha\":{\"type\":\"number\",\"nullable\":false}," +
          "\"beta\":{\"type\":\"number\",\"nullable\":false}," +
          "\"gamma\":{\"type\":\"number\",\"nullable\":false}," +
          "\"event_id\":{\"type\":\"number\",\"nullable\":false}," +
          "\"occurred_at\":{\"type\":\"number\",\"nullable\":false}," +
          "\"payload\":{\"type\":\"string\",\"nullable\":false}}," +
          "\"rows\":[{\"alpha\":1,\"beta\":2,\"gamma\":3," +
          "\"event_id\":7,\"occurred_at\":9," +
          "\"payload\":\"x\"}]},\"as\":\"source\"}]",
        ),
        [],
        None,
        None,
        {
          max_steps: 10,
          max_work: 10000,
          max_text_bytes: 10000,
          max_nodes: 1000,
          max_tokens: 1000,
          max_depth: 100,
        },
      ).unwrap(),
      {
        max_nodes: 100,
        max_references: 100,
        max_work: 1000,
        max_identifier_bytes: 1000,
      },
    ).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let source = carrier_events_source_output(source_owner)
  let events_owner = carrier_events_output_owner(source_owner)
  let source_input = @execution.prepare_producer_read(
    events_owner,
    @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let builder = @records.prepare_output(
    events_owner,
    @pipeline.Step(0),
    carrier_events_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let source_schema = @execution.producer_read_schema(source_input)
  let fields = []
  for column in 0..<6 {
    let reversed = 5 - column
    fields.push(
      (
        @schema.field_at(source_schema, reversed).unwrap().name,
        @execution.producer_read_checked_cell(source_input, 0, reversed, {
          max_nodes: 100,
          max_depth: 10,
          max_text_bytes: 1000,
        }).unwrap(),
      ),
    )
  }
  @records.append_record(builder, fields).unwrap()
  let events = @records.finish_output(builder).unwrap()
  let projection_owner = carrier_events_projection_owner(events_owner)
  let events_input = @records.prepare_producer_read(
    projection_owner, 0, events_owner, events,
  ).unwrap()
  let projection = @local_bridge.start_events_view_to_rows(
    @bounded.control(),
    task_test_completion(projection_owner),
    prepared_sequence(projection_owner),
    0,
    @records.producer_read_view(events_input).unwrap(),
    1,
    // One row container and six scalar values need seven value nodes.
    { max_nodes: 7, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    100,
    1000,
  ).unwrap()
  let mut terminal = false
  let mut polls = 0
  while !terminal {
    polls += 1
    assert_true(polls < 25)
    match @local_bridge.advance_events_to_rows(projection, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(rows, work~, ..) => {
        // Six source probes, six required-field checks, one output append.
        assert_eq(work, 13L)
        assert_eq(@execution.completed_row_count(rows), 1)
        assert_true(@execution.completed_cell(rows, 0, 0) is Some(Number(1.0)))
        assert_true(@execution.completed_cell(rows, 0, 2) is Some(Number(7.0)))
        terminal = true
      }
      _ => abort("Events projection failed")
    }
  }
  assert_eq(@local_bridge.cleanup_events_to_rows(projection), Ok(true))
  let one_short_width = @local_bridge.start_events_view_to_rows(
    @bounded.control(),
    task_test_completion(projection_owner),
    prepared_sequence(projection_owner),
    0,
    @records.producer_read_view(events_input).unwrap(),
    1,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    5,
    1000,
  )
  assert_true(
    one_short_width is Err(@local_bridge.Completion(@execution.Limit)),
  )
  let one_short_value = @local_bridge.start_events_view_to_rows(
    @bounded.control(),
    task_test_completion(projection_owner),
    prepared_sequence(projection_owner),
    0,
    @records.producer_read_view(events_input).unwrap(),
    1,
    { max_nodes: 6, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    6,
    1000,
  ).unwrap()
  let mut value_failed = false
  for _ in 0..<25 {
    if value_failed {
      break
    }
    match @local_bridge.advance_events_to_rows(one_short_value, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Failed(
        @local_bridge.RelationOutput(@execution.CaptureLimit),
        ..
      ) => value_failed = true
      _ => abort("one-short Events projection did not reject output")
    }
  }
  assert_true(value_failed)
  assert_eq(@local_bridge.cleanup_events_to_rows(one_short_value), Ok(true))
  let control = @bounded.control()
  let cancelled = @local_bridge.start_events_view_to_rows(
    control,
    task_test_completion(projection_owner),
    prepared_sequence(projection_owner),
    0,
    @records.producer_read_view(events_input).unwrap(),
    1,
    { max_nodes: 7, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    6,
    1000,
  ).unwrap()
  assert_true(
    @local_bridge.advance_events_to_rows(cancelled, 1).unwrap()
    is @local_bridge.Continue(..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_bridge.advance_events_to_rows(cancelled, 1).unwrap()
    is @local_bridge.Stopped(_, ..),
  )
  assert_eq(@local_bridge.cleanup_events_to_rows(cancelled), Ok(true))
  assert_true(@execution.completed_output_available(source))
  assert_true(@records.completed_available(events))
  assert_true(@records.discard_completed(events))
}

///|
test "rows to Events admits exact work and workspace and reclaims partial output" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_owner(source_owner)
  let input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  // Each three-field record costs one identity array plus its value (2),
  // one record array plus three field triples (10), and four copy units.
  // Each record retains five slots. The second append also overlaps its
  // three scratch fields with five retained and five newly copied slots.
  for
    (work, slots, outcome) in [
      (32, 13, "complete"),
      (31, 13, "work"),
      (32, 12, "workspace"),
    ] {
    let limits = {
      ..carrier_events_storage_limits(),
      max_work: work,
      max_workspace_slots: slots,
    }
    let execution = @local_bridge.start_rows_to_events(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      input,
      limits,
      4096L,
      fn() { true },
    ).unwrap()
    let mut terminal = false
    let mut polls = 0
    while !terminal {
      polls += 1
      assert_true(polls < 50)
      match @local_bridge.advance_rows_to_events(execution, 1).unwrap() {
        @local_bridge.Continue(..) => ()
        @local_bridge.Complete(output, ..) => {
          assert_eq(outcome, "complete")
          assert_true(
            @records.completed_storage(output) is Some(storage) &&
            @record_storage.construction_work(storage) == 32 &&
            @record_storage.retained_workspace_slots(storage) == 10,
          )
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        @local_bridge.Failed(
          @local_bridge.Output(@records.Storage(@record_storage.WorkLimit)),
          ..
        ) => {
          assert_eq(outcome, "work")
          terminal = true
        }
        @local_bridge.Failed(
          @local_bridge.Output(@records.Storage(@record_storage.WorkspaceLimit)),
          ..
        ) => {
          assert_eq(outcome, "workspace")
          terminal = true
        }
        _ => abort("unexpected rows-to-Events result")
      }
    }
    assert_eq(@local_bridge.cleanup_rows_to_events(execution), Ok(true))
    assert_eq(@local_bridge.cleanup_rows_to_events(execution), Ok(false))
    assert_true(@execution.completed_output_available(source))
  }

  let control = @bounded.control()
  let cancelled = @local_bridge.start_rows_to_events(
    control,
    prepared_sequence(owner),
    0,
    input,
    carrier_events_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut first_row = false
  let mut polls = 0
  while !first_row {
    polls += 1
    assert_true(polls < 20)
    match @local_bridge.advance_rows_to_events(cancelled, 1).unwrap() {
      @local_bridge.Continue(progress~, ..) => first_row = progress > 0L
      _ => abort("rows-to-Events did not yield after its first row")
    }
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_bridge.advance_rows_to_events(cancelled, 1).unwrap()
    is @local_bridge.Stopped(_, ..),
  )
  assert_eq(@local_bridge.cleanup_rows_to_events(cancelled), Ok(true))
  assert_true(@execution.completed_output_available(source))
}

///|
test "Events bridge preserves timestamp clocks through a typed round trip" {
  let source_owner = carrier_events_source_owner_with(
    "timestamp",
    "[{\"event_id\":1,\"occurred_at\":" +
    "\"1969-12-31T23:59:59.999Z\",\"payload\":\"before\"}," +
    "{\"event_id\":2,\"occurred_at\":" +
    "\"2000-02-29T12:30:00.000Z\",\"payload\":\"leap\"}]",
  )
  let source = carrier_events_source_output(source_owner)
  let events_owner = carrier_events_output_owner(source_owner)
  let source_input = @execution.prepare_producer_read(
    events_owner,
    @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let encoding = @local_bridge.start_rows_to_events(
    @bounded.control(),
    prepared_sequence(events_owner),
    0,
    source_input,
    carrier_events_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let events = finish_rows_to_events(encoding)
  assert_eq(@local_bridge.cleanup_rows_to_events(encoding), Ok(true))

  let projection_owner = carrier_events_projection_owner(events_owner)
  let events_input = @records.prepare_producer_read(
    projection_owner, 0, events_owner, events,
  ).unwrap()
  assert_true(
    @records.producer_read_matches_operation_input(
      events_input, projection_owner, 0, 0,
    ),
  )
  assert_true(
    @lower.sequence_step(prepared_sequence(projection_owner), 0)
    is Some(@lower.CarrierProjectionStep(_)),
  )
  let events_view = @records.producer_read_view(events_input).unwrap()
  let projection = @local_bridge.start_events_view_to_rows(
    @bounded.control(),
    task_test_completion(projection_owner),
    prepared_sequence(projection_owner),
    0,
    events_view,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
  ).unwrap()
  let rows = finish_events_to_rows(projection)
  assert_eq(@local_bridge.cleanup_events_to_rows(projection), Ok(true))
  assert_true(
    @execution.completed_cell(rows, 0, 1)
    is Some(Captured(@admitted.Timestamp("1969-12-31T23:59:59.999Z"))),
  )
  assert_true(
    @execution.completed_cell(rows, 1, 1)
    is Some(Captured(@admitted.Timestamp("2000-02-29T12:30:00.000Z"))),
  )
  assert_true(@records.completed_available(events))
  assert_true(@records.discard_completed(events))
}

///|
test "rows to Events rejects duplicate semantic identities" {
  let source_owner = carrier_events_source_owner_with(
    "number",
    "[{\"event_id\":1,\"occurred_at\":1,\"payload\":\"first\"}," +
    "{\"event_id\":1,\"occurred_at\":2,\"payload\":\"second\"}]",
  )
  let source = carrier_events_source_output(source_owner)
  let events_owner = carrier_events_output_owner(source_owner)
  let source_input = @execution.prepare_producer_read(
    events_owner,
    @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let encoding = @local_bridge.start_rows_to_events(
    @bounded.control(),
    prepared_sequence(events_owner),
    0,
    source_input,
    carrier_events_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut failed = false
  while !failed {
    match @local_bridge.advance_rows_to_events(encoding, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Failed(
        @local_bridge.Output(
          @records.Storage(@record_storage.DuplicateIdentity)
        ),
        ..
      ) => failed = true
      @local_bridge.Failed(_, ..) => abort("unexpected rows-to-events failure")
      @local_bridge.Complete(_, ..) => abort("duplicate identity was accepted")
      @local_bridge.Stopped(_, ..) => abort("rows-to-events stopped")
    }
  }
  assert_eq(@local_bridge.cleanup_rows_to_events(encoding), Ok(true))
  assert_true(@execution.completed_output_available(source))
}

///|
test "registered Events provider advances and reclaims one typed pipeline" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_owner(source_owner)
  let generated = task_test_generated(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let provider = @local_tea_provider.provider(
    carrier_events_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let execution = @local_connector.start_managed_provider(
    provider,
    generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("provider returned a Carrier output")
      @local_connector.Failed(_, ..) => fail("provider failed")
      @local_connector.Stopped(..) => fail("provider stopped")
    }
  }
  let completed = output.unwrap()
  assert_eq(@execution.completed_row_count(completed), 2)
  assert_true(@execution.completed_output_matches_inputs(completed, [external]))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@execution.completed_output_available(completed))
}

///|
test "registered Events provider returns retained Carrier material" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_output_owner(source_owner)
  let generated = task_test_generated(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let provider = @local_tea_provider.provider(
    carrier_events_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider(
    provider,
    generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut material = None
  while material is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) => material = Some(value)
      @local_connector.Complete(_, ..) => fail("provider returned rows")
      @local_connector.Failed(_, ..) => fail("provider failed")
      @local_connector.Stopped(..) => fail("provider stopped")
    }
  }
  let retained = material.unwrap()
  assert_eq(
    @carrier_runtime.material_kind(retained),
    @carrier_contract.EventsKind,
  )
  assert_eq(@carrier_runtime.material_storage_bytes(retained), Some(4096L))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(retained))
  assert_true(@carrier_runtime.reclaim_material(retained))
}

///|
test "registered sequence provider consumes exact Events Carrier" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let events_owner = carrier_events_output_owner(source_owner)
  let events_generated = task_test_generated(events_owner)
  let limits = dispatch_test_limits()
  let storage_limits = carrier_events_storage_limits()
  let external = @execution.prepare_producer_read(
    events_owner,
    @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let events_provider = @local_tea_provider.provider(
    storage_limits,
    4096L,
    @execution.generated_sequence_capacity(
      events_generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let events_execution = @local_connector.start_managed_provider(
    events_provider,
    events_generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut material = None
  while material is None {
    match
      @local_connector.advance_managed_provider(events_execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) => material = Some(value)
      @local_connector.Complete(_, ..) => fail("bridge returned rows")
      @local_connector.Failed(_, ..) => fail("bridge provider failed")
      @local_connector.Stopped(..) => fail("bridge provider stopped")
    }
  }
  assert_true(
    @local_connector.cleanup_managed_provider(events_execution).unwrap_or(false),
  )
  let material = material.unwrap()
  let owner = carrier_events_sequence_owner(events_owner)
  let generated = task_test_generated(owner)
  let first_view = @carrier_runtime.material_prepare_view(
    material, owner, 0, events_owner,
  ).unwrap()
  for work in [0, 1] {
    assert_true(
      @execution.start_bounded_sequence_match_events(
        @bounded.control(),
        generated,
        first_view,
        10,
        limits.local_execution.rows.output_values,
        work,
        limits.local_execution.max_frames,
        storage_limits.max_workspace_slots,
        1000,
      )
      is Err(@execution.Rows(@execution.RowLimit)),
    )
  }
  let second_view = @carrier_runtime.material_prepare_view(
    material, owner, 0, events_owner,
  ).unwrap()
  let provider = @local_tea_provider.sequence_match_provider(
    storage_limits,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let first = @local_connector.start_managed_provider_with_inputs_and_execution(
    provider,
    generated,
    [@local_connector.managed_provider_carrier_input(first_view)],
    10,
    1000,
    limits.local_execution,
  ).unwrap()
  let second = @local_connector.start_managed_provider_with_inputs_and_execution(
    provider,
    generated,
    [@local_connector.managed_provider_carrier_input(second_view)],
    10,
    1000,
    limits.local_execution,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(first, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("sequence returned a Carrier")
      @local_connector.Failed(_, ..) => fail("sequence provider failed")
      @local_connector.Stopped(..) => fail("sequence provider stopped")
    }
  }
  assert_eq(@execution.completed_row_count(output.unwrap()), 1)
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@local_connector.managed_provider_stopped(first))
  assert_true(@local_connector.cleanup_managed_provider(first).unwrap_or(false))
  assert_true(@carrier_runtime.material_available(material))
  let mut second_output = None
  while second_output is None {
    match @local_connector.advance_managed_provider(second, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => second_output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("sequence returned a Carrier")
      @local_connector.Failed(_, ..) => fail("sequence provider failed")
      @local_connector.Stopped(..) => fail("sequence provider stopped")
    }
  }
  assert_eq(@execution.completed_row_count(second_output.unwrap()), 1)
  assert_true(
    @local_connector.cleanup_managed_provider(second).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(material))
  let cancel_view = @carrier_runtime.material_prepare_view(
    material, owner, 0, events_owner,
  ).unwrap()
  let cancelled = @local_connector.start_managed_provider_with_inputs_and_execution(
    provider,
    generated,
    [@local_connector.managed_provider_carrier_input(cancel_view)],
    10,
    1000,
    limits.local_execution,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(cancelled, 1).unwrap()
    is @local_connector.Continue(_),
  )
  assert_true(@local_connector.cancel_managed_provider(cancelled))
  assert_true(
    @local_connector.advance_managed_provider(cancelled, 1).unwrap()
    is @local_connector.Stopped(_),
  )
  assert_true(
    @local_connector.cleanup_managed_provider(cancelled).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "registered Events provider consumes exact Carrier in two sessions" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let events_owner = carrier_events_output_owner(source_owner)
  let events_generated = task_test_generated(events_owner)
  let external = @execution.prepare_producer_read(
    events_owner,
    @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let limits = carrier_events_storage_limits()
  let events_provider = @local_tea_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      events_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let events_execution = @local_connector.start_managed_provider(
    events_provider,
    events_generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut source_material = None
  while source_material is None {
    match
      @local_connector.advance_managed_provider(events_execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) =>
        source_material = Some(value)
      @local_connector.Complete(_, ..) => fail("bridge returned rows")
      @local_connector.Failed(_, ..) => fail("bridge provider failed")
      @local_connector.Stopped(..) => fail("bridge provider stopped")
    }
  }
  assert_true(
    @local_connector.cleanup_managed_provider(events_execution).unwrap_or(false),
  )
  let source_material = source_material.unwrap()
  let first_owner = carrier_events_session_owner(events_owner)
  let second_owner = carrier_events_session_owner(events_owner)
  let first_generated = task_test_generated(first_owner)
  let second_generated = task_test_generated(second_owner)
  let first_view = @carrier_runtime.material_prepare_view(
    source_material, first_owner, 0, events_owner,
  ).unwrap()
  let second_view = @carrier_runtime.material_prepare_view(
    source_material, second_owner, 0, events_owner,
  ).unwrap()
  let first_provider = @local_tea_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      first_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let second_provider = @local_tea_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      second_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(
    @local_connector.managed_provider_accepts(first_provider, first_generated),
  )
  assert_true(
    @local_connector.managed_provider_accepts(second_provider, second_generated),
  )
  let first = @local_connector.start_managed_provider_with_inputs(
    first_provider,
    first_generated,
    [@local_connector.managed_provider_carrier_input(first_view)],
    10,
    1000,
  ).unwrap()
  let second = @local_connector.start_managed_provider_with_inputs(
    second_provider,
    second_generated,
    [@local_connector.managed_provider_carrier_input(second_view)],
    10,
    1000,
  ).unwrap()
  let mut first_output = None
  while first_output is None {
    match @local_connector.advance_managed_provider(first, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) => first_output = Some(value)
      @local_connector.Complete(_, ..) => fail("session returned rows")
      @local_connector.Failed(_, ..) => fail("first session failed")
      @local_connector.Stopped(..) => fail("first session stopped")
    }
  }
  let first_output = first_output.unwrap()
  assert_eq(
    @carrier_runtime.material_kind(first_output),
    @carrier_contract.EventsKind,
  )
  assert_true(@carrier_runtime.material_available(source_material))
  assert_true(@local_connector.cleanup_managed_provider(first).unwrap_or(false))
  assert_true(@carrier_runtime.reclaim_material(first_output))
  assert_true(@carrier_runtime.material_available(source_material))
  let mut second_output = None
  while second_output is None {
    match @local_connector.advance_managed_provider(second, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) => second_output = Some(value)
      @local_connector.Complete(_, ..) => fail("session returned rows")
      @local_connector.Failed(_, ..) => fail("second session failed")
      @local_connector.Stopped(..) => fail("second session stopped")
    }
  }
  let second_output = second_output.unwrap()
  assert_eq(
    @carrier_runtime.material_kind(second_output),
    @carrier_contract.EventsKind,
  )
  assert_true(
    @local_connector.cleanup_managed_provider(second).unwrap_or(false),
  )
  assert_true(@carrier_runtime.reclaim_material(second_output))
  assert_false(@carrier_runtime.reclaim_material(second_output))
  assert_true(@carrier_runtime.reclaim_material(source_material))
  assert_false(@carrier_runtime.reclaim_material(source_material))
}

///|
test "registered Events provider shares Carrier with Bridge consumer" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let events_owner = carrier_events_output_owner(source_owner)
  let events_generated = task_test_generated(events_owner)
  let external = @execution.prepare_producer_read(
    events_owner,
    @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let limits = carrier_events_storage_limits()
  let events_provider = @local_tea_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      events_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let events_execution = @local_connector.start_managed_provider(
    events_provider,
    events_generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut source_material = None
  while source_material is None {
    match
      @local_connector.advance_managed_provider(events_execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) =>
        source_material = Some(value)
      @local_connector.Complete(_, ..) => fail("bridge returned rows")
      @local_connector.Failed(_, ..) => fail("bridge provider failed")
      @local_connector.Stopped(..) => fail("bridge provider stopped")
    }
  }
  assert_true(
    @local_connector.cleanup_managed_provider(events_execution).unwrap_or(false),
  )
  let source_material = source_material.unwrap()
  let session_owner = carrier_events_session_owner(events_owner)
  let projection_owner = carrier_events_projection_owner(events_owner)
  let session_generated = task_test_generated(session_owner)
  let projection_generated = task_test_generated(projection_owner)
  let session_view = @carrier_runtime.material_prepare_view(
    source_material, session_owner, 0, events_owner,
  ).unwrap()
  let projection_view = @carrier_runtime.material_prepare_view(
    source_material, projection_owner, 0, events_owner,
  ).unwrap()
  let session_provider = @local_tea_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      session_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let projection_provider = @local_tea_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      projection_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let session = @local_connector.start_managed_provider_with_inputs(
    session_provider,
    session_generated,
    [@local_connector.managed_provider_carrier_input(session_view)],
    10,
    1000,
  ).unwrap()
  let projection = @local_connector.start_managed_provider_with_inputs(
    projection_provider,
    projection_generated,
    [@local_connector.managed_provider_carrier_input(projection_view)],
    10,
    1000,
  ).unwrap()
  let mut session_output = None
  while session_output is None {
    match @local_connector.advance_managed_provider(session, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) =>
        session_output = Some(value)
      @local_connector.Complete(_, ..) => fail("session returned rows")
      @local_connector.Failed(_, ..) => fail("session failed")
      @local_connector.Stopped(..) => fail("session stopped")
    }
  }
  assert_true(@carrier_runtime.material_available(source_material))
  assert_true(
    @local_connector.cleanup_managed_provider(session).unwrap_or(false),
  )
  assert_true(@carrier_runtime.reclaim_material(session_output.unwrap()))
  assert_true(@carrier_runtime.material_available(source_material))
  let mut rows = None
  while rows is None {
    match @local_connector.advance_managed_provider(projection, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => rows = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("projection returned a Carrier")
      @local_connector.Failed(_, ..) => fail("projection failed")
      @local_connector.Stopped(..) => fail("projection stopped")
    }
  }
  assert_eq(@execution.completed_row_count(rows.unwrap()), 2)
  assert_true(
    @local_connector.cleanup_managed_provider(projection).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(source_material))
  let cancel_owner = carrier_events_projection_owner(events_owner)
  let cancel_generated = task_test_generated(cancel_owner)
  let cancel_view = @carrier_runtime.material_prepare_view(
    source_material, cancel_owner, 0, events_owner,
  ).unwrap()
  let cancel_provider = @local_tea_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      cancel_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let cancel = @local_connector.start_managed_provider_with_inputs(
    cancel_provider,
    cancel_generated,
    [@local_connector.managed_provider_carrier_input(cancel_view)],
    10,
    1000,
  ).unwrap()
  assert_true(@local_connector.cancel_managed_provider(cancel))
  assert_true(
    @local_connector.advance_managed_provider(cancel, 1).unwrap()
    is @local_connector.Stopped(..),
  )
  assert_true(
    @local_connector.cleanup_managed_provider(cancel).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(source_material))
  assert_true(@carrier_runtime.reclaim_material(source_material))
  assert_false(@carrier_runtime.material_available(source_material))
}

///|
test "selected Events steps retain original checked coordinates" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_owner(source_owner, variant="session")
  let generated = task_test_generated(owner)
  let limits = carrier_events_storage_limits()
  let capacity = @execution.generated_sequence_capacity(
    generated,
    dispatch_test_limits().local_execution,
    dispatch_test_limits().guards,
  ).unwrap()
  let provider = @local_tea_provider.provider(limits, 4096L, capacity)
  let rows = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let produce = @execution.select_generated_sequence_step(generated, 0).unwrap()
  assert_true(@local_connector.managed_provider_accepts(provider, produce))
  let producing = @local_connector.start_managed_provider(
    provider,
    produce,
    [rows],
    10,
    1000,
  ).unwrap()
  let mut produced = None
  while produced is None {
    match @local_connector.advance_managed_provider(producing, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) => produced = Some(value)
      @local_connector.Complete(_, ..) => fail("producer returned rows")
      @local_connector.Failed(_, ..) => fail("producer failed")
      @local_connector.Stopped(..) => fail("producer stopped")
    }
  }
  let produced = produced.unwrap()
  assert_true(@carrier_runtime.material_available(produced))
  assert_true(
    @carrier_runtime.completion_reference_matches_port(
      @carrier_runtime.material_reference(produced),
      owner,
      @pipeline.Step(0),
    ),
  )
  assert_eq(
    @lower.node_input_target(
      @lower.node_at(@lower.bound_preparation(owner), 1).unwrap(),
      0,
    ),
    Some(@pipeline.Step(0)),
  )
  let session_view = @carrier_runtime.material_prepare_operation_view(
    produced, owner, 1, 0, owner,
  ).unwrap()
  assert_true(
    @local_connector.cleanup_managed_provider(producing).unwrap_or(false),
  )
  let session_sequence = @execution.select_generated_sequence_step(generated, 1).unwrap()
  assert_eq(
    @execution.generated_sequence_step_index_at(session_sequence, 0),
    Some(1),
  )
  assert_true(
    @local_connector.managed_provider_accepts(provider, session_sequence),
  )
  let session = @local_connector.start_managed_provider_with_inputs(
    provider,
    session_sequence,
    [@local_connector.managed_provider_carrier_input(session_view)],
    10,
    1000,
  ).unwrap()
  let mut session_output = None
  while session_output is None {
    match @local_connector.advance_managed_provider(session, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) =>
        session_output = Some(value)
      @local_connector.Complete(_, ..) => fail("session returned rows")
      @local_connector.Failed(_, ..) => fail("session failed")
      @local_connector.Stopped(..) => fail("session stopped")
    }
  }
  assert_true(
    @local_connector.cleanup_managed_provider(session).unwrap_or(false),
  )
  assert_true(@carrier_runtime.reclaim_material(produced))
  let session_output = session_output.unwrap()
  let projection_view = @carrier_runtime.material_prepare_operation_view(
    session_output, owner, 2, 0, owner,
  ).unwrap()
  let projection_sequence = @execution.select_generated_sequence_step(
    generated, 2,
  ).unwrap()
  assert_true(
    @local_connector.managed_provider_accepts(provider, projection_sequence),
  )
  let projection = @local_connector.start_managed_provider_with_inputs(
    provider,
    projection_sequence,
    [@local_connector.managed_provider_carrier_input(projection_view)],
    10,
    1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(projection, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("projection returned Carrier")
      @local_connector.Failed(_, ..) => fail("projection failed")
      @local_connector.Stopped(..) => fail("projection stopped")
    }
  }
  assert_eq(@execution.completed_row_count(output.unwrap()), 2)
  assert_true(
    @local_connector.cleanup_managed_provider(projection).unwrap_or(false),
  )
  assert_true(@carrier_runtime.reclaim_material(session_output))
}

///|
test "registered Events provider separates stop from cleanup" {
  for
    variant in [
      "watermark", "dedupe", "window_fixed", "window_sliding", "window_parameter",
      "session", "session_global", "session_parameter",
    ] {
    let source_owner = carrier_events_source_owner()
    let source = carrier_events_source_output(source_owner)
    let owner = carrier_events_owner(source_owner, variant~)
    let generated = task_test_generated(owner)
    let external = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
      100,
      1000,
    ).unwrap()
    let provider = @local_tea_provider.provider(
      carrier_events_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        generated,
        dispatch_test_limits().local_execution,
        dispatch_test_limits().guards,
      ).unwrap(),
    )
    let execution = @local_connector.start_managed_provider(
      provider,
      generated,
      [external],
      10,
      1000,
    ).unwrap()
    assert_true(@local_connector.cancel_managed_provider(execution))
    assert_true(
      @local_connector.advance_managed_provider(execution, 1).unwrap()
      is @local_connector.Stopped(..),
    )
    assert_true(@local_connector.managed_provider_stopped(execution))
    assert_true(
      @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
    )
    assert_true(@execution.producer_read_available(external))
  }
}

///|
test "standard Host runs registered bounded Events provider" {
  for
    variant in [
      "watermark", "dedupe", "window_fixed", "window_sliding", "window_parameter",
      "session", "session_global", "session_parameter", "session_ties", "session_relation",
    ] {
    let publication = variant != "session_ties"
    let (run, issuer) = captured_graph_fixture(
      local_carrier_events_chain=true,
      local_carrier_events_variant=variant,
      managed_publication=publication,
      parameter_json=if variant == "session_parameter" {
        "{\"minimum\":2}"
      } else if variant == "window_parameter" {
        "{\"minimum\":1,\"window_size\":10}"
      } else {
        "{\"minimum\":1}"
      },
    )
    if publication {
      assert_true(
        @strategy.configure_captured_managed_identity_policy(
          run, true, false, false, false,
        ),
      )
    }
    let registry = search_registry()
    let limits = dispatch_test_limits()
    let sequences = dispatch_test_generated(run)
    let cleanup_attempts = Ref(0)
    let provider = delayed_cleanup_provider(
      @local_tea_provider.provider(
        carrier_events_storage_limits(),
        4096L,
        @execution.generated_sequence_capacity(
          sequences[1],
          limits.local_execution,
          limits.guards,
        ).unwrap(),
      ),
      cleanup_attempts,
    )
    let modules = @builtin.configure_compute_modules(
      @host_driver.open_dispatch_driver(run),
      registry,
      1,
      _ => @strategy.RunIssue::ForeignCandidate,
      with_local=Some(
        (
          @connector.capability_registration_at(registry, 0).unwrap(),
          {
            sequences,
            managed_providers: [provider],
            managed_capacity: limits.capacity,
            execution: limits.local_execution,
            measurement: limits.guards,
            max_work: limits.candidate_work,
          },
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      ),
    ).unwrap()
    let installed = @builtin.configured_local_module(modules).unwrap()
    @local_driver.configure_local_retained_inputs(
      installed,
      {
        max_rows: 100,
        values: limits.local_execution.rows.input_values,
        wire: {
          max_bytes: 3000,
          max_nodes: 300,
          max_depth: 10,
          max_columns: 10,
          max_order_work: 1000,
        },
        row: {
          max_bytes: 3000,
          max_nodes: 300,
          max_depth: 10,
          max_text_bytes: 3000,
        },
        max_batch_bytes: 3000,
      },
      None,
    ).unwrap()

    let values_live = Ref(true)
    let (values_ops, values) = run_local_managed_test_task(
      installed,
      run,
      1,
      [],
      [],
      1,
      values_live,
      obligations?=if publication {
        Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
      } else {
        None
      },
    )
    let values_rows = local_managed_test_rows(values_ops)
    let events_live = Ref(true)
    let event_obligations = if publication {
      Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
    } else {
      None
    }
    let (events_ops, events) = run_local_managed_test_task(
      installed,
      run,
      2,
      [values],
      [values_rows],
      2,
      events_live,
      obligations?=event_obligations,
      require_provider=variant.has_prefix("session") &&
        variant != "session_relation",
    )
    let event_rows = local_managed_test_rows(events_ops)
    let expected_rows = if variant == "dedupe" {
      2
    } else if variant == "window_sliding" {
      6
    } else {
      3
    }
    assert_eq(event_rows.length(), expected_rows)
    if variant == "dedupe" {
      assert_true(event_rows[0].contains("\"event_id\":2"))
      assert_true(event_rows[1].contains("\"event_id\":4"))
    } else if variant == "window_fixed" ||
      variant == "window_sliding" ||
      variant == "window_parameter" {
      assert_true(event_rows[0].contains("\"window_start_ms\""))
      assert_true(event_rows[0].contains("\"window_end_ms\""))
    } else if variant.has_prefix("session") {
      if variant == "session_ties" {
        assert_true(event_rows[0].contains("\"event_id\":1"))
        assert_true(event_rows[1].contains("\"event_id\":2"))
      } else {
        assert_true(event_rows[0].contains("\"event_id\":2"))
        assert_true(event_rows[1].contains("\"event_id\":1"))
      }
      assert_true(event_rows[2].contains("\"event_id\":3"))
      assert_true(event_rows[0].contains("\"session_start_ms\":1"))
      assert_true(event_rows[0].contains("\"session_id\":\"session:"))
      assert_true(event_rows[2].contains("\"session_start_ms\":13"))
      if variant == "session_parameter" {
        assert_true(event_rows[0].contains("\"session_end_ms\":3"))
        assert_true(event_rows[1].contains("\"session_start_ms\":3"))
        assert_true(event_rows[1].contains("\"session_end_ms\":5"))
        assert_true(event_rows[2].contains("\"session_end_ms\":15"))
      } else if variant == "session_ties" {
        assert_true(event_rows[0].contains("\"session_end_ms\":11"))
        assert_true(event_rows[1].contains("\"session_end_ms\":11"))
        assert_true(event_rows[2].contains("\"session_end_ms\":23"))
      } else {
        assert_true(event_rows[0].contains("\"session_end_ms\":13"))
        assert_true(event_rows[2].contains("\"session_end_ms\":23"))
      }
    } else {
      assert_true(event_rows[0].contains("\"watermark_decision\":\"keep\""))
      assert_true(event_rows[1].contains("\"late\":true"))
    }
    if publication {
      let requirements = @execution.managed_obligations_identities(
        event_obligations.unwrap(),
      )
      let published = requirements.filter(requirement => {
        requirement.domain == @execution.LogicalRelation &&
        requirement.subject == @execution.NamedResult
      })
      assert_eq(published.length(), 1)
      match
        @execution.managed_completed_identity_requirement_status(
          events,
          published[0],
        ) {
        Some(@execution.EstablishedSourceRetained(contract, cid)) => {
          assert_eq(
            contract,
            @execution.logical_relation_canonical_contract_cid(),
          )
          assert_eq(cid, carrier_events_publication_cid(variant))
        }
        _ => fail("Events output did not establish publication identity")
      }
      assert_true(
        @execution.managed_completed_deadline_satisfied(
          events,
          @execution.BeforePublication,
        ),
      )
    }

    let first_live = Ref(true)
    let (first_ops, first) = run_local_managed_test_task(
      installed,
      run,
      3,
      [events],
      [event_rows],
      3,
      first_live,
      obligations?=if publication {
        Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
      } else {
        None
      },
    )
    let second_live = Ref(true)
    let (second_ops, second) = run_local_managed_test_task(
      installed,
      run,
      4,
      [events],
      [event_rows],
      4,
      second_live,
      obligations?=if publication {
        Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
      } else {
        None
      },
    )
    assert_eq(local_managed_test_rows(first_ops).length(), expected_rows)
    assert_eq(local_managed_test_rows(second_ops).length(), expected_rows)

    first_live.val = false
    @strategy.close_captured_task_output(run, 3)
    (first_ops.close)()
    (first_ops.cleanup_refresh)() |> ignore
    assert_false(@execution.managed_completed_output_available(first))
    assert_true(@execution.managed_completed_output_available(second))
    assert_true(@execution.managed_completed_output_available(events))

    second_live.val = false
    @strategy.close_captured_task_output(run, 4)
    (second_ops.close)()
    (second_ops.cleanup_refresh)() |> ignore
    events_live.val = false
    @strategy.close_captured_task_output(run, 2)
    (events_ops.close)()
    assert_false((events_ops.cleanup_refresh)())
    assert_true((events_ops.cleanup_refresh)())
    assert_eq(cleanup_attempts.val, 2)
    values_live.val = false
    @strategy.close_captured_task_output(run, 1)
    (values_ops.close)()
    (values_ops.cleanup_refresh)() |> ignore
    @strategy.stop_captured_dag(run)
    @strategy.close_captured_task_output(run, 0)
    @strategy.refresh_captured_retention(run)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.held_bytes, 0L)
    @mock.close_mock_query_issuer(issuer)
  }
}

///|
test "standard Host retains Events across physical task boundaries" {
  for
    (variant, execution_quantum) in [
      ("session_filter", 0),
      ("session_select", 0),
      ("session_derive", 0),
      ("session_take", 1),
      ("session_take", 2),
      ("session_take", 7),
      ("session_take", 1024),
    ] {
    let (run, issuer) = captured_graph_fixture(
      local_carrier_events_chain=true,
      local_carrier_events_variant=variant,
      managed_publication=true,
      ledger_limits=if carrier_events_relation_followup(variant) {
        Some({
          planning_work: 30000,
          attempts: 20,
          holdings: 20,
          transfer_bytes: 800000L,
          retained_bytes: 96000000L,
          execution_bytes: 402653184L,
        })
      } else {
        None
      },
      parameter_json=if variant == "session_parameter" {
        "{\"minimum\":2}"
      } else {
        "{\"minimum\":1}"
      },
    )
    assert_true(
      @strategy.configure_captured_managed_identity_policy(
        run, true, false, false, false,
      ),
    )
    let registry = search_registry()
    let limits = dispatch_test_limits()
    let sequences = dispatch_test_generated(run)
    let provider = @local_tea_provider.provider(
      carrier_events_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        sequences[1],
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    )
    let modules = @builtin.configure_compute_modules(
      @host_driver.open_dispatch_driver(run),
      registry,
      1,
      _ => @strategy.RunIssue::ForeignCandidate,
      with_local=Some(
        (
          @connector.capability_registration_at(registry, 0).unwrap(),
          {
            sequences,
            managed_providers: [provider],
            managed_capacity: limits.capacity,
            execution: limits.local_execution,
            measurement: limits.guards,
            max_work: limits.candidate_work,
          },
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      ),
    ).unwrap()
    let installed = @builtin.configured_local_module(modules).unwrap()
    @local_driver.configure_local_retained_inputs(
      installed,
      {
        max_rows: 100,
        values: limits.local_execution.rows.input_values,
        wire: {
          max_bytes: 3000,
          max_nodes: 300,
          max_depth: 10,
          max_columns: 10,
          max_order_work: 1000,
        },
        row: {
          max_bytes: 3000,
          max_nodes: 300,
          max_depth: 10,
          max_text_bytes: 3000,
        },
        max_batch_bytes: 3000,
      },
      None,
    ).unwrap()

    let values_live = Ref(true)
    let (values_ops, values) = run_local_managed_test_task(
      installed,
      run,
      1,
      [],
      [],
      1,
      values_live,
      obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
    )
    let values_rows = local_managed_test_rows(values_ops)
    let (bridge_ops, bridge, bridge_material) = run_local_managed_carrier_test_task(
      installed,
      run,
      2,
      [@local_driver.local_managed_relation_output(values)],
      [values_rows],
      obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
    )
    let (session_ops, session, session_material) = run_local_managed_carrier_test_task(
      installed,
      run,
      3,
      [@local_driver.local_managed_carrier_output(bridge, bridge_material)],
      [],
      obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
    )
    let events_live = Ref(true)
    let (events_ops, events) = run_local_managed_test_task(
      installed,
      run,
      4,
      [],
      [],
      4,
      events_live,
      obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
      carrier_inputs=[(session, session_material)],
    )
    let event_rows = local_managed_test_rows(events_ops)
    assert_eq(event_rows.length(), 3)
    assert_true(event_rows[0].contains("\"session_start_ms\":1"))
    assert_true(event_rows[2].contains("\"session_start_ms\":13"))

    let mut consumer_source = events
    let mut consumer_rows = event_rows
    let mut consumer_task = 4
    let mut close_filter : (() -> Unit)? = None
    if carrier_events_relation_followup(variant) {
      let filter_live = Ref(true)
      let (filter_ops, filtered) = run_local_managed_test_task(
        installed,
        run,
        5,
        [events],
        [event_rows],
        5,
        filter_live,
        obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
        execution_quantum~,
      )
      consumer_source = filtered
      consumer_rows = local_managed_test_rows(filter_ops)
      consumer_task = 5
      if variant == "session_derive" {
        assert_true(consumer_rows[0].contains("\"copy\":2"))
      } else if variant == "session_select" {
        assert_true(consumer_rows[0].contains("\"event_id\":2"))
        assert_true(consumer_rows[2].contains("\"event_id\":3"))
      } else {
        assert_eq(consumer_rows, event_rows)
      }
      close_filter = Some(fn() {
        filter_live.val = false
        @strategy.close_captured_task_output(run, 5)
        (filter_ops.close)()
        (filter_ops.cleanup_refresh)() |> ignore
      })
    }

    let first_live = Ref(true)
    let (first_ops, first) = run_local_managed_test_task(
      installed,
      run,
      consumer_task + 1,
      [consumer_source],
      [consumer_rows],
      consumer_task + 1,
      first_live,
      obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
    )
    let second_live = Ref(true)
    let (second_ops, second) = run_local_managed_test_task(
      installed,
      run,
      consumer_task + 2,
      [consumer_source],
      [consumer_rows],
      consumer_task + 2,
      second_live,
      obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
    )
    assert_eq(local_managed_test_rows(first_ops).length(), 3)
    assert_eq(local_managed_test_rows(second_ops).length(), 3)

    first_live.val = false
    @strategy.close_captured_task_output(run, consumer_task + 1)
    (first_ops.close)()
    (first_ops.cleanup_refresh)() |> ignore
    assert_false(@execution.managed_completed_output_available(first))
    assert_true(@execution.managed_completed_output_available(second))
    assert_true(@execution.managed_completed_output_available(consumer_source))

    second_live.val = false
    @strategy.close_captured_task_output(run, consumer_task + 2)
    (second_ops.close)()
    (second_ops.cleanup_refresh)() |> ignore
    match close_filter {
      Some(close) => close()
      None => ()
    }
    events_live.val = false
    @strategy.close_captured_task_output(run, 4)
    (events_ops.close)()
    (events_ops.cleanup_refresh)() |> ignore
    @strategy.close_captured_task_output(run, 3)
    (session_ops.close)()
    (session_ops.cleanup_refresh)() |> ignore
    @strategy.close_captured_task_output(run, 2)
    (bridge_ops.close)()
    (bridge_ops.cleanup_refresh)() |> ignore
    values_live.val = false
    @strategy.close_captured_task_output(run, 1)
    (values_ops.close)()
    (values_ops.cleanup_refresh)() |> ignore
    @strategy.stop_captured_dag(run)
    @strategy.close_captured_task_output(run, 0)
    @strategy.refresh_captured_retention(run)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.held_bytes, 0L)
    @mock.close_mock_query_issuer(issuer)
  }
}

///|
test "standard Host matches retained Events in a later physical task" {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_events_chain=true,
    local_carrier_events_variant="sequence",
    managed_publication=true,
    parameter_json="{\"minimum\":1}",
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let event_provider = @local_tea_provider.provider(
    carrier_events_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      sequences[1],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let sequence_provider = @local_tea_provider.sequence_match_provider(
    carrier_events_storage_limits(),
    @execution.generated_sequence_capacity(
      sequences[2],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [event_provider, sequence_provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 10,
        max_order_work: 1000,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()

  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let values_rows = local_managed_test_rows(values_ops)
  let (bridge_ops, bridge, bridge_material) = run_local_managed_carrier_test_task(
    installed,
    run,
    2,
    [@local_driver.local_managed_relation_output(values)],
    [values_rows],
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let matches_live = Ref(true)
  let (matches_ops, matches) = run_local_managed_test_task(
    installed,
    run,
    3,
    [],
    [],
    3,
    matches_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
    carrier_inputs=[(bridge, bridge_material)],
  )
  let rows = local_managed_test_rows(matches_ops)
  assert_eq(rows.length(), 3)
  assert_true(rows[0].contains("\"start_id\":2"))
  assert_true(rows[0].contains("\"end_id\":3"))

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [matches],
    [rows],
    4,
    first_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [matches],
    [rows],
    5,
    second_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  assert_eq(local_managed_test_rows(first_ops).length(), 3)
  assert_eq(local_managed_test_rows(second_ops).length(), 3)

  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(matches))

  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  matches_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (matches_ops.close)()
  (matches_ops.cleanup_refresh)() |> ignore
  @strategy.close_captured_task_output(run, 2)
  (bridge_ops.close)()
  (bridge_ops.cleanup_refresh)() |> ignore
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
