///|
test "Parameter diagnostics distinguish default and supplied origins with identical file labels" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let supplied = @decode.admit(
    @source.parse_json(
      "{\"n\":\"bad\"}",
      { max_input_bytes: 100, max_nodes: 10, max_depth: 10, },
      source_path="same.label",
    ).unwrap(),
    {
      max_nodes: 10,
      max_depth: 10,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    },
  ).unwrap()
  for from_default in [false, true] {
    let document = if from_default {
      text.replace(old="\"default\":1", new="\"default\":\"bad\"")
    } else {
      text
    }
    let diagnostic = public_rejected(
      @program_check.check_document(
        document,
        environment,
        if from_default {
          None
        } else {
          Some(supplied)
        },
        limits,
        format=Json,
        source_path="same.label",
      ),
    )
    assert_eq(
      @program_check.diagnostic_origin(diagnostic),
      Some(
        if from_default {
          @program_check.ProgramDocument
        } else {
          @program_check.SuppliedValues
        },
      ),
    )
    let location = @program_check.diagnostic_location(diagnostic).unwrap()
    assert_eq(
      @program_check.diagnostic_location_source_path(location),
      "same.label",
    )
    assert_eq(
      @program_check.diagnostic_location_path(location),
      Some(
        if from_default {
          [@source.Key("params"), @source.Key("n"), @source.Key("default")]
        } else {
          [@source.Key("n")]
        },
      ),
    )
  }
}
