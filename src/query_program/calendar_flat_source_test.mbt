///|
// These are ordinary typed UTC rows, not sampled Calendar output. The full
// machine Program is independently authored and uses the existing profile.
fn calendar_flat_rows() -> @wire.Cursor {
  from_unpivot_public_cursor(
    (
      #|{"values":{"schema":{"start":{"type":"timestamp","nullable":false},"end":{"type":"timestamp","nullable":false}},"rows":[{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-02T00:00:00.000Z"},{"start":"2000-01-02T00:00:00.000Z","end":"2000-01-03T00:00:00.000Z"}]},"as":"raw"}
    ),
  )
}

///|
fn calendar_flat_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.calendar_flat","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"start":{"type":"timestamp","nullable":false},"end":{"type":"timestamp","nullable":false}},"rows":[{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-02T00:00:00.000Z"},{"start":"2000-01-02T00:00:00.000Z","end":"2000-01-03T00:00:00.000Z"}]},"as":"raw"},{"from":"raw","calendar_bucket":{"time":"start","unit":"month","timezone":"UTC","into":"month"},"as":"bucketed"},{"from":"bucketed","sort":[{"field":"start","dir":"asc","nulls":"first"}]},{"select":["start","end","month"],"as":"out"}],"results":{"rows":{"from":"out","fields":["start","end","month"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Calendar flat Carrier dispatch and WITH preserve the same ordinary bucket input" {
  let selected = calendar_source_selected()
  let expected = calendar_flat_control()
  calendar_source_checked(expected, selected) |> ignore
  let context = {
    ..pair_context(),
    program_id: "fixture.calendar_flat",
    calendar_profile: Some(selected),
    inputs: [
      {
        relation: [{ value: "raw", quoted: false, }],
        name: "raw",
        source: GeneratedValues(calendar_flat_rows()),
        visible_fields: ["start", "end"],
        graph_bindings: [],
      },
    ],
  }
  let pipe = "FROM raw AS r |> calendar_bucket(time:r.start,unit:'month',timezone:'UTC',into:month) |> SELECT start,`end`,month |> ORDER BY start"
  for
    text in [
      pipe,
      "WITH bucketed AS (" +
      pipe +
      ") SELECT start,`end`,month FROM bucketed ORDER BY start",
    ] {
    let actual = @frontend.lower(text, Text, Some(context)).unwrap().program.unwrap()
    let checked = calendar_source_checked(actual, selected)
    assert_eq(
      @json.parse(with_carrier_argument(actual, "calendar_bucket")),
      @json.parse(with_carrier_argument(expected, "calendar_bucket")),
    )
    assert_eq(
      @json.parse(with_carrier_argument(actual, "values")),
      @json.parse(with_carrier_argument(expected, "values")),
    )
    assert_eq(semantic(actual).split("\"values\":").length(), 2)
    assert_eq(semantic(actual).split("\"calendar_bucket\":").length(), 2)
    let stage = @stage_results.stage_at(
      @check.checked_stage_results(checked),
      0,
    ).unwrap()
    let result = @relation_results.lookup(stage, "rows").unwrap()
    assert_eq(@relation_results.fields(result), ["start", "end", "month"])
    let independent_schema = @schema.from_object(
      @contract.read_checked(
        from_unpivot_public_cursor(
          (
            #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"start":{"type":"timestamp","nullable":false},"end":{"type":"timestamp","nullable":false},"month":{"type":"object","nullable":false,"additional_properties":false,"fields":{"start":{"type":"timestamp","nullable":false},"end":{"type":"timestamp","nullable":false}}}}}
          ),
        ),
        { max_nodes: 128, max_depth: 16, max_text_bytes: 4096, },
      ).unwrap(),
    ).unwrap()
    let fields = @schema.fields(@relation_results.output_schema(result))
    let required = @schema.fields(independent_schema)
    assert_eq(
      fields.map(@schema.field_reference_name),
      required.map(@schema.field_reference_name),
    )
    for index in 0..<fields.length() {
      assert_true(fields[index].presence == required[index].presence)
      assert_true(
        @contract.type_equal(
          fields[index].contract,
          required[index].contract,
          10000,
        ),
      )
    }
  }
}
