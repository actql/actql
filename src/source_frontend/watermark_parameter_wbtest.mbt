///|
fn watermark_parameter_cursor(text : String) -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(text, {
      max_input_bytes: 4096,
      max_nodes: 256,
      max_depth: 16,
    }).unwrap(),
    {
      max_nodes: 256,
      max_depth: 16,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
  ).unwrap()
}

///|
fn watermark_parameter_context(declaration_text : String) -> @query.Context {
  let declaration = watermark_parameter_cursor(declaration_text)
  let values = watermark_parameter_cursor(
    (
      #|{"values":{"schema":{"item_id":{"type":"number","nullable":false},"occurred_ms":{"type":"number","nullable":false}},"rows":[{"item_id":1,"occurred_ms":0}]} ,"as":"records"}
    ),
  )
  {
    program_id: "frontend.watermark_parameter",
    stage_id: "main",
    stage_result: "rows",
    result_name: "answer",
    captured_stage: None,
    parameter_declarations: Some(
      @parameters.read_declarations(Some(declaration), {
        max_parameters: 1,
        max_nodes: 256,
        max_depth: 16,
        max_text_bytes: 4096,
      }).unwrap(),
    ),
    input_schemas: [],
    source_catalog: None,
    model_tasks: None,
    calendar_profile: None,
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: @query.GeneratedValues(values),
        visible_fields: ["item_id", "occurred_ms"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "watermark numeric Parameters lower before binding for mark and drop" {
  for policy in ["mark", "drop"] {
    let result = lower(
      "FROM records |> to_events(id: item_id, time: occurred_ms) |> watermark_events(watermark_ms: @threshold, policy: '" +
      policy +
      "') |> events() |> SELECT item_id, late",
      Text,
      Some(
        watermark_parameter_context(
          "{\"threshold\":{\"type\":\"number\",\"nullable\":false}}",
        ),
      ),
    ).unwrap()
    assert_true(
      result.document.contains("\"watermark_ms\":{\"$param\":\"threshold\"}"),
    )
  }
}

///|
test "watermark Parameters reject undeclared nonnumeric and nullable declarations" {
  for
    declaration in [
      "{\"other\":{\"type\":\"number\",\"nullable\":false}}", "{\"threshold\":{\"type\":\"string\",\"nullable\":false}}",
      "{\"threshold\":{\"type\":\"number\",\"nullable\":true}}",
    ] {
    assert_true(
      lower(
        "FROM records |> to_events(id: item_id, time: occurred_ms) |> watermark_events(watermark_ms: @threshold, policy: 'mark') |> events() |> SELECT item_id, late",
        Text,
        Some(watermark_parameter_context(declaration)),
      )
      is Err(_),
    )
  }
}

///|
test "literal watermark control accepts signed fractional and zero thresholds" {
  for threshold in ["-2.5", "0", "1.5"] {
    assert_true(
      lower(
        "FROM records |> to_events(id: item_id, time: occurred_ms) |> watermark_events(watermark_ms: " +
        threshold +
        ", policy: 'mark') |> events() |> SELECT item_id, late",
        Text,
        Some(
          watermark_parameter_context(
            "{\"threshold\":{\"type\":\"number\",\"nullable\":false}}",
          ),
        ),
      )
      is Ok(_),
    )
  }
}
