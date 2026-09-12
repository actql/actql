///|
test "success readiness cannot treat unadmitted Effect contracts as an empty stage" {
  for
    (suffix, expected) in [
      ("", false),
      (",\"effects\":{}", false),
      (",\"effects\":{\"send\":{}}", true),
      (",\"effects\":{\"send\":{},\"save\":{}}", true),
    ] {
    let program = @syntax.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{\"from\":\"x\"}}" +
      suffix +
      "}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}",
      {
        source: { max_input_bytes: 4096, max_nodes: 100, max_depth: 20, },
        tree: {
          max_nodes: 100,
          max_depth: 20,
          max_string_bytes: 4096,
          max_total_string_bytes: 4096,
        },
        max_stages: 1,
      },
      format=Json,
    ).unwrap()
    assert_eq(
      incoming_effects_present(@syntax.stage_body(@syntax.stages(program)[0])),
      expected,
    )
  }
}
