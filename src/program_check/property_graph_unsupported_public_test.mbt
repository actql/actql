///|
test "current public Property Graph admission refuses unsupported SGA rather than reaching a legacy selection" {
  let (_, _, base, _, limits) = public_input_fixture(
    generated=true,
    graph_policy=true,
  )
  let environment = @program_check.checking_environment(
    @program_check.checking_environment_wire(base),
    { text_time: false, veca: false, },
    { rela: true, sga: true, tea: false, calendar: false, text_rank: false, },
    property_graph=true,
  )
  for
    operation in [
      "\"normalize_graph\":true", "\"components\":{\"kind\":\"weak\"}", "\"graphs_equal\":{\"other\":\"g\"}",
      "\"graph_diff\":{\"other\":\"g\"}", "\"apply_graph_delta\":{\"delta\":\"g\"}",
      "\"subgraph\":{\"nodes\":[1]}", "\"reach\":{\"start\":{\"ids\":[1]},\"max_hops\":1}",
      "\"shortest_path\":{\"start\":{\"ids\":[1]},\"end\":{\"ids\":[1]}}", "\"graft_graph\":{\"other\":\"g\"}",
      "\"union_graphs\":{\"inputs\":[\"g\"]}", "\"subtract_graphs\":{\"other\":\"g\"}",
      "\"mean_graphs\":{\"inputs\":[\"g\"]}",
    ] {
    let source = "{\"version\":\"actql/0.1\",\"id\":\"unsupported-current-graph\",\"stages\":[{\"id\":\"source\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"nodes\"},{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"nodes\",\"key\":[\"id\"],\"labels\":[{\"name\":\"Node\"}]}],\"edges\":[]},\"as\":\"g\"},{\"from\":\"g\"," +
      operation +
      ",\"as\":\"rows\"}],\"results\":{\"out\":{\"from\":\"rows\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"source\",\"result\":\"out\"}}}}"
    // The admitted current constructor and ordinary Program shape are shared
    // with the positive vertical. Refusal must occur at the unsupported
    // operation boundary, not through a legacy kernel or fabricated NULL.
    let rejected = public_rejected(
      @program_check.check_document(
        source,
        environment,
        None,
        limits,
        format=Json,
      ),
    )
    assert_true(
      @program_check.diagnostic_cause(rejected)
      is Units(UnsupportedStaticPath(_)),
    )
  }
}
