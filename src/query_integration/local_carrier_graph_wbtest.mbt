///|
fn carrier_graph_source_owner_with_rows(rows : String) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
      "\"src\":{\"type\":\"number\",\"nullable\":false}," +
      "\"dst\":{\"type\":\"number\",\"nullable\":false}," +
      "\"node_name\":{\"type\":\"string\",\"nullable\":false}," +
      "\"weight\":{\"type\":\"number\",\"nullable\":false}}," +
      "\"rows\":" +
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
fn carrier_graph_source_owner() -> @lower.BoundPrepared {
  carrier_graph_source_owner_with_rows(
    "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"first\",\"weight\":10},{\"id\":2," +
    "\"src\":2,\"dst\":1,\"node_name\":\"second\"," +
    "\"weight\":20}]",
  )
}

///|
fn carrier_graph_self_loop_source_owner() -> @lower.BoundPrepared {
  carrier_graph_source_owner_with_rows(
    "[{\"id\":1,\"src\":1,\"dst\":1," + "\"node_name\":\"self\",\"weight\":10}]",
  )
}

///|
fn carrier_graph_components_source_owner() -> @lower.BoundPrepared {
  carrier_graph_source_owner_with_rows(
    "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"one\",\"weight\":10},{\"id\":2," +
    "\"src\":2,\"dst\":1,\"node_name\":\"two\",\"weight\":20}," +
    "{\"id\":3,\"src\":2,\"dst\":3,\"node_name\":\"three\"," +
    "\"weight\":30},{\"id\":4,\"src\":4,\"dst\":4," +
    "\"node_name\":\"four\",\"weight\":40}]",
  )
}

///|
fn carrier_graph_open_endpoint_source_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\"," +
      "\"nullable\":false},\"src\":{\"type\":\"number\"," +
      "\"nullable\":false},\"dst\":{\"type\":\"number\"," +
      "\"nullable\":false},\"node_name\":{\"type\":\"string\"," +
      "\"nullable\":false},\"weight\":{\"type\":\"number\"," +
      "\"nullable\":false}},\"rows\":[{\"id\":1,\"src\":1," +
      "\"dst\":2,\"node_name\":\"first\",\"weight\":10}]}," +
      "\"as\":\"source\"}]",
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
fn is_graph_equality_variant(variant : String) -> Bool {
  variant == "graphs_equal" ||
  variant == "graphs_equal_reverse" ||
  variant == "graphs_equal_self" ||
  variant == "graphs_nullable_equal" ||
  variant == "graphs_nullable_null_equal" ||
  variant.has_suffix("unequal")
}

///|
fn local_carrier_graph_program(variant? : String = "projection") -> String {
  let concise = variant == "concise_projection"
  let split = variant == "split_projection"
  let subtract = variant.has_prefix("subtract")
  let subtract_exact = variant == "subtract_exact"
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"src\":{\"type\":\"number\",\"nullable\":false}," +
    "\"dst\":{\"type\":\"number\",\"nullable\":false}," +
    (if subtract && !subtract_exact {
      "\"marker\":{\"type\":\"number\",\"nullable\":false}}"
    } else {
      "\"node_name\":{\"type\":\"string\",\"nullable\":" +
      (if variant.has_prefix("graphs_nullable") { "true" } else { "false" }) +
      "}," +
      "\"weight\":{\"type\":\"number\",\"nullable\":" +
      (if variant.has_prefix("graphs_nullable") { "true" } else { "false" }) +
      "}}"
    })
  let first_name = if variant == "graphs_nullable_null_equal" {
    "null"
  } else if variant == "graphs_nullable_equal" {
    "\"x\""
  } else {
    "\"first\""
  }
  let rows = if subtract && !subtract_exact {
    "[{\"id\":1,\"src\":1,\"dst\":2,\"marker\":0}," +
    "{\"id\":2,\"src\":2,\"dst\":1,\"marker\":0}]"
  } else {
    "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":" +
    first_name +
    ",\"weight\":" +
    (if variant == "graphs_nullable_null_equal" { "null" } else { "10" }) +
    "},{\"id\":2," +
    "\"src\":2,\"dst\":1,\"node_name\":\"second\"," +
    "\"weight\":20}]"
  }
  let graph_equality = is_graph_equality_variant(variant)
  let projection = if concise {
    "\"from\":\"g\",\"edge_rows\":true,\"as\":\"out\""
  } else if variant == "match_nodes" {
    "\"from\":\"g\",\"match_nodes\":{\"ids\":[2,1,2]," +
    "\"fields\":[\"id\",\"node_name\"]},\"as\":\"out\""
  } else if variant == "match_nodes_literal" {
    "\"from\":\"g\",\"match_nodes\":{\"where\":\"true\"," +
    "\"fields\":[\"id\",\"node_name\"]},\"as\":\"out\""
  } else if variant == "match_nodes_predicate" {
    "\"from\":\"g\",\"match_nodes\":{\"where\":" +
    "\"node_name = 'second'\",\"fields\":[\"id\",\"node_name\"]}," +
    "\"as\":\"out\""
  } else if variant == "match_edges" || variant == "edge_projection" {
    "\"from\":\"g\",\"match_edges\":{\"fields\":[\"src\",\"dst\"," +
    "\"weight\"]},\"as\":\"out\""
  } else if variant == "match_edges_predicate" {
    "\"from\":\"g\",\"match_edges\":{\"where\":\"weight > 10\"," +
    "\"fields\":[\"src\",\"dst\",\"weight\"]},\"as\":\"out\""
  } else if variant == "graph_bounds" {
    "\"from\":\"g\",\"graph_bounds\":{\"max_nodes\":1," +
    "\"max_edges\":1,\"max_degree\":1},\"as\":\"out\""
  } else if variant == "degree_in" {
    "\"from\":\"g\",\"degree\":{\"direction\":\"in\"}," + "\"as\":\"out\""
  } else if variant == "degree_out" {
    "\"from\":\"g\",\"degree\":{\"direction\":\"out\"}," + "\"as\":\"out\""
  } else if variant == "degree_both" {
    "\"from\":\"g\",\"degree\":{\"direction\":\"both\"}," + "\"as\":\"out\""
  } else if variant == "components_weak" {
    "\"from\":\"g\",\"components\":{\"kind\":\"weak\"}," + "\"as\":\"out\""
  } else if variant == "components_strong" {
    "\"from\":\"g\",\"components\":{\"kind\":\"strong\"}," + "\"as\":\"out\""
  } else if variant == "reach_out" {
    "\"from\":\"g\",\"reach\":{\"start\":1,\"direction\":\"out\"," +
    "\"max_depth\":2},\"as\":\"out\""
  } else if variant == "traverse_out" {
    "\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[1]}," +
    "\"direction\":\"out\",\"min_hops\":1,\"max_hops\":2," +
    "\"emit\":\"nodes\"},\"as\":\"out\""
  } else if variant == "normalize_shared" {
    "\"from\":\"g\",\"normalize_graph\":true,\"as\":\"normalized\"},{" +
    "\"from\":\"normalized\",\"normalize_graph\":true," +
    "\"as\":\"same_carrier\"},{" +
    "\"from\":\"normalized\",\"node_rows\":true,\"as\":\"out\""
  } else if variant == "normalize" {
    "\"from\":\"g\",\"normalize_graph\":true,\"as\":\"normalized\"},{" +
    "\"from\":\"normalized\",\"node_rows\":true,\"as\":\"out\""
  } else if variant == "graft" {
    "\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":[\"weight\"]}},\"as\":\"right_graph\"},{" +
    "\"from\":\"g\",\"graft_graph\":{\"with\":\"right_graph\"}," +
    "\"as\":\"grafted\"},{\"from\":\"grafted\"," +
    "\"node_rows\":true,\"as\":\"out\""
  } else if variant == "union" || variant == "union_singleton" {
    "\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":[\"weight\"]}},\"as\":\"right_graph\"},{" +
    "\"from\":\"g\",\"union_graphs\":{\"with\":" +
    (if variant == "union_singleton" {
      "\"right_graph\""
    } else {
      "[\"right_graph\",\"g\",\"right_graph\"]"
    }) +
    "}," +
    "\"as\":\"united\"},{\"from\":\"united\"," +
    "\"node_rows\":true,\"as\":\"out\""
  } else if subtract {
    "\"graph\":{\"nodes\":{\"from\":\"other\",\"id\":\"id\"," +
    "\"fields\":" +
    (if subtract_exact { "[\"node_name\"]" } else { "[]" }) +
    "},\"edges\":{\"from\":\"other\"," +
    "\"source\":\"src\",\"target\":\"dst\",\"fields\":" +
    (if subtract_exact { "[\"weight\"]" } else { "[]" }) +
    "}}," +
    "\"as\":\"right_graph\"},{" +
    "\"from\":\"g\",\"subtract_graphs\":{\"with\":\"right_graph\"" +
    (if subtract_exact {
      ",\"merge\":{\"node_properties\":{\"node_name\":\"exact_equal\"}," +
      "\"edge_properties\":{\"weight\":\"exact_equal\"}}"
    } else {
      ""
    }) +
    "}," +
    "\"as\":\"subtracted\"},{\"from\":\"subtracted\"," +
    "\"node_rows\":true,\"as\":\"out\""
  } else if graph_equality {
    let right = if variant == "graphs_equal_self" {
      ""
    } else {
      "\"graph\":{\"nodes\":{\"from\":" +
      (if variant == "graphs_payload_unequal" {
        "\"other\""
      } else {
        "\"rows\""
      }) +
      ",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":" +
      (if variant.has_suffix("unequal") { "\"other\"" } else { "\"rows\"" }) +
      "," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"right_graph\"},{"
    }
    let left_name = if variant == "graphs_equal_reverse" {
      "right_graph"
    } else {
      "g"
    }
    let right_name = if variant == "graphs_equal_reverse" ||
      variant == "graphs_equal_self" {
      "g"
    } else {
      "right_graph"
    }
    right +
    "\"from\":\"" +
    left_name +
    "\",\"graphs_equal\":{\"with\":\"" +
    right_name +
    "\"},\"as\":\"out\""
  } else if variant == "edge_projection" {
    "\"from\":\"g\",\"edge_rows\":true,\"as\":\"out\""
  } else {
    "\"node_rows\":true,\"as\":\"out\""
  }
  let result_fields = if subtract && !subtract_exact {
    "\"id\""
  } else if concise {
    "\"src\",\"dst\",\"id\",\"weight\""
  } else if variant.has_prefix("match_edges") || variant == "edge_projection" {
    "\"src\",\"dst\",\"weight\""
  } else if variant == "graph_bounds" {
    "\"kind\",\"node_id\",\"actual\",\"max\""
  } else if variant.has_prefix("degree_") {
    "\"node\",\"degree\""
  } else if variant.has_prefix("components_") {
    "\"node_id\",\"component_id\",\"component_size\""
  } else if variant.has_prefix("reach_") || variant.has_prefix("traverse_") {
    "\"start_id\",\"node_id\",\"depth\""
  } else if graph_equality {
    "\"equal\""
  } else {
    "\"id\",\"node_name\""
  }
  let first_fields = result_fields
  let second_fields = if subtract && !subtract_exact {
    "\"id\""
  } else if concise {
    "\"weight\",\"src\""
  } else if variant.has_prefix("match_edges") || variant == "edge_projection" {
    "\"weight\",\"src\""
  } else if variant == "graph_bounds" {
    "\"kind\",\"node_id\""
  } else if variant.has_prefix("degree_") {
    "\"degree\""
  } else if variant.has_prefix("components_") {
    "\"component_id\",\"component_size\""
  } else if variant.has_prefix("reach_") || variant.has_prefix("traverse_") {
    "\"node_id\",\"depth\""
  } else if graph_equality {
    "\"equal\""
  } else {
    "\"node_name\""
  }
  let other_stage = if subtract {
    "{\"id\":\"other_values\",\"inputs\":{},\"steps\":[{" +
    "\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"id\":2,\"src\":2,\"dst\":2," +
    (if subtract_exact {
      "\"node_name\":\"second\",\"weight\":20"
    } else {
      "\"marker\":0"
    }) +
    "}]},\"as\":\"out\"}],\"results\":{\"r\":{" +
    "\"from\":\"out\",\"fields\":[\"id\",\"src\",\"dst\"," +
    (if subtract_exact { "\"node_name\",\"weight\"" } else { "\"marker\"" }) +
    "]}}},"
  } else if split {
    "{\"id\":\"node_values\",\"inputs\":{},\"steps\":[{" +
    "\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"id\":1,\"src\":1,\"dst\":1," +
    "\"node_name\":\"first\",\"weight\":0},{\"id\":2," +
    "\"src\":2,\"dst\":2,\"node_name\":\"second\"," +
    "\"weight\":0}]},\"as\":\"out\"}],\"results\":{\"r\":{" +
    "\"from\":\"out\",\"fields\":[\"id\",\"src\",\"dst\"," +
    "\"node_name\",\"weight\"]}}},"
  } else if variant.has_suffix("unequal") {
    "{\"id\":\"other_values\",\"inputs\":{},\"steps\":[{" +
    "\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    (if variant == "graphs_payload_unequal" {
      "[{\"id\":1,\"src\":1,\"dst\":2," +
      "\"node_name\":\"different\",\"weight\":10},{\"id\":2," +
      "\"src\":2,\"dst\":1,\"node_name\":\"second\"," +
      "\"weight\":20}]"
    } else {
      "[]"
    }) +
    "}," +
    "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
    "\"fields\":[\"id\",\"src\",\"dst\",\"node_name\"," +
    "\"weight\"]}}},"
  } else {
    ""
  }
  let graph_inputs = if subtract {
    "\"rows\":{\"result\":{\"stage\":\"values\",\"result\":\"r\"}}," +
    "\"other\":{\"result\":{\"stage\":\"other_values\"," +
    "\"result\":\"r\"}}"
  } else if split {
    "\"nodes\":{\"result\":{\"stage\":\"node_values\"," +
    "\"result\":\"r\"}},\"rows\":{\"result\":{" +
    "\"stage\":\"values\",\"result\":\"r\"}}"
  } else if variant.has_suffix("unequal") {
    "\"rows\":{\"result\":{\"stage\":\"values\",\"result\":\"r\"}}," +
    "\"other\":{\"result\":{\"stage\":\"other_values\"," +
    "\"result\":\"r\"}}"
  } else {
    "\"rows\":{\"result\":{\"stage\":\"values\",\"result\":\"r\"}}"
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"values\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":" +
  rows +
  "},\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"," +
  "\"src\",\"dst\"," +
  (if subtract && !subtract_exact {
    "\"marker\""
  } else {
    "\"node_name\",\"weight\""
  }) +
  "]}}}," +
  other_stage +
  "{\"id\":\"graph\",\"inputs\":{" +
  graph_inputs +
  "},\"steps\":[{" +
  (if concise {
    "\"from\":\"rows\",\"graph\":{\"source\":\"src\"," +
    "\"target\":\"dst\"},\"as\":\"g\"},{"
  } else if subtract {
    "\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":" +
    (if subtract_exact { "[\"node_name\"]" } else { "[]" }) +
    "},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\",\"fields\":" +
    (if subtract_exact { "[\"weight\"]" } else { "[]" }) +
    "}}," +
    "\"as\":\"g\"},{"
  } else {
    "\"graph\":{\"nodes\":{\"from\":" +
    (if split { "\"nodes\"" } else { "\"rows\"" }) +
    ",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":[\"weight\"]}},\"as\":\"g\"},{"
  }) +
  projection +
  "}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":[" +
  result_fields +
  "]}}},{" +
  "\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"graph\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[" +
  first_fields +
  "],\"as\":\"out\"}],\"results\":{" +
  "\"r\":{\"from\":\"out\",\"fields\":[" +
  first_fields +
  "]}}},{" +
  "\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"graph\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[" +
  second_fields +
  "],\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":[" +
  second_fields +
  "]}}}],\"results\":{" +
  "\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn local_carrier_graph_environment(
  original : @environment.WireEnvironment,
) -> @environment.WireEnvironment raise {
  let writer = @encode.writer(1000000, 100000, 100)
  @environment.emit(original, writer)
  let body = @encode.finish(writer)
    .replace(
      old="\"evidence_bundle_cid\":\"" + @environment.cid(original) + "\",",
      new="",
    )
    .replace(
      old="\"max_graph_input_edges\":",
      new="\"max_graph_construction_edges\":10000," +
        "\"max_graph_construction_input_rows\":10000," +
        "\"max_graph_construction_nodes\":10000," +
        "\"max_graph_input_edges\":",
    )
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  @environment.read(
    @utf8.encode(
      body.replace(
        old="\"host_policy_profile\":",
        new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
      ),
    ),
    cid,
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_members: 1000,
    },
  ).unwrap()
}

///|
fn carrier_graph_owner(
  source : @lower.BoundPrepared,
  projection? : String = "node_rows",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"}," +
      "{\"" +
      projection +
      "\":true}]",
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
fn carrier_graph_material_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"}]",
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
fn carrier_graph_projection_owner(
  source : @lower.BoundPrepared,
  projection : String,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"g\",\"" + projection + "\":true}]"),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
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
fn carrier_graph_match_owner(
  source : @lower.BoundPrepared,
  ids : String,
) -> @lower.BoundPrepared {
  carrier_graph_match_body_owner(
    source,
    "{\"ids\":" + ids + ",\"fields\":[\"id\",\"node_name\"]}",
  )
}

///|
fn carrier_graph_match_body_owner(
  source : @lower.BoundPrepared,
  body : String,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"}," +
      "{\"from\":\"graph\",\"match_nodes\":" +
      body +
      "}]",
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
fn carrier_graph_labeled_source_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\"," +
      "\"nullable\":false},\"src\":{\"type\":\"number\"," +
      "\"nullable\":false},\"dst\":{\"type\":\"number\"," +
      "\"nullable\":false},\"rel\":{\"type\":\"string\"," +
      "\"nullable\":false},\"weight\":{\"type\":\"number\"," +
      "\"nullable\":false}},\"rows\":[{\"id\":2,\"src\":2," +
      "\"dst\":1,\"rel\":\"controls\",\"weight\":20},{\"id\":1," +
      "\"src\":1,\"dst\":3,\"rel\":\"owns\",\"weight\":30},{" +
      "\"id\":3,\"src\":1,\"dst\":2,\"rel\":\"owns\"," +
      "\"weight\":10}]},\"as\":\"source\"}]",
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
fn carrier_graph_edge_match_owner(
  source : @lower.BoundPrepared,
  types : String,
  predicate? : String = "\"true\"",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"}," +
      "\"edges\":{\"from\":\"rows\",\"source\":\"src\"," +
      "\"target\":\"dst\",\"label\":\"rel\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"match_edges\":{\"types\":" +
      types +
      ",\"where\":" +
      predicate +
      ",\"fields\":[\"src\",\"dst\",\"rel\",\"weight\"]}}]",
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
fn carrier_graph_bounds_owner(
  source : @lower.BoundPrepared,
  body : String,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"graph_bounds\":" +
      body +
      "}]",
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
fn carrier_graph_degree_owner(
  source : @lower.BoundPrepared,
  direction : String,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"degree\":{\"direction\":\"" +
      direction +
      "\"}}]",
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
fn carrier_graph_components_owner(
  source : @lower.BoundPrepared,
  kind : String,
  max_guard? : String = "",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"components\":{\"kind\":\"" +
      kind +
      "\"" +
      max_guard +
      "}}]",
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
fn carrier_graph_reach_owner(
  source : @lower.BoundPrepared,
  start : Int,
  direction : String,
  depth : Int,
) -> @lower.BoundPrepared {
  carrier_graph_reach_owner_with_depth(
    source,
    start,
    direction,
    depth.to_string(),
  )
}

///|
fn carrier_graph_reach_owner_with_depth(
  source : @lower.BoundPrepared,
  start : Int,
  direction : String,
  depth : String,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"reach\":{\"start\":" +
      start.to_string() +
      ",\"direction\":\"" +
      direction +
      "\",\"max_depth\":" +
      depth +
      "}}]",
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
fn carrier_graph_traverse_owner(
  source : @lower.BoundPrepared,
  minimum : Int,
  maximum : Int,
  emission? : String = "nodes",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"traverse\":{\"start\":{\"ids\":[1]}," +
      "\"direction\":\"out\",\"min_hops\":" +
      minimum.to_string() +
      ",\"max_hops\":" +
      maximum.to_string() +
      ",\"emit\":\"" +
      emission +
      "\",\"max_output_rows\":4}}]",
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
fn carrier_graph_storage_limits() -> @graph_storage.Limits {
  {
    max_input_rows: 20,
    max_nodes: 10,
    max_edges: 10,
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
fn finish_rows_to_graph(
  execution : @local_bridge.RowsToGraphExecution,
) -> @graphs.Completed {
  while true {
    match @local_bridge.advance_rows_to_graph(execution, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => return output
      @local_bridge.Failed(_, ..) => abort("rows-to-graph failed")
      @local_bridge.Stopped(_, ..) => abort("rows-to-graph stopped")
    }
  }
  abort("unreachable")
}

///|
fn finish_graph_to_rows(
  execution : @local_bridge.GraphRowsExecution,
) -> @execution.CompletedOutput {
  while true {
    match @local_bridge.advance_graph_to_rows(execution, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => return output
      @local_bridge.Failed(issue, ..) =>
        match issue {
          @local_bridge.InvalidGraphKernel => abort("invalid graph kernel")
          @local_bridge.GraphInputUnavailable => abort("graph unavailable")
          @local_bridge.InvalidGraphRecord(_) => abort("invalid graph record")
          @local_bridge.GraphWorkspaceLimit => abort("graph workspace")
          @local_bridge.GraphRelationOutput(_) => abort("graph relation output")
          @local_bridge.GraphCompletion(_) => abort("graph completion")
          @local_bridge.GraphExecution(_) => abort("graph execution")
        }
      @local_bridge.Stopped(_, ..) => abort("graph-to-rows stopped")
    }
  }
  abort("unreachable")
}

///|
fn finish_match_nodes(
  execution : @local_sga.MatchNodesExecution,
) -> Result[@execution.CompletedOutput, @local_sga.MatchNodesIssue] {
  while true {
    let poll = match @local_sga.advance_match_nodes(execution, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      @local_sga.MatchNodesContinue(..) => ()
      @local_sga.MatchNodesComplete(output, ..) => return Ok(output)
      @local_sga.MatchNodesFailed(issue, ..) => return Err(issue)
      @local_sga.MatchNodesStopped(_, ..) =>
        return Err(@local_sga.MatchNodesExecutionIssue(@bounded.Terminal))
    }
  }
  abort("unreachable")
}

///|
fn finish_match_edges(
  execution : @local_sga.MatchEdgesExecution,
) -> Result[@execution.CompletedOutput, @local_sga.MatchEdgesIssue] {
  while true {
    let poll = match @local_sga.advance_match_edges(execution, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      @local_sga.MatchEdgesContinue(..) => ()
      @local_sga.MatchEdgesComplete(output, ..) => return Ok(output)
      @local_sga.MatchEdgesFailed(issue, ..) => return Err(issue)
      @local_sga.MatchEdgesStopped(_, ..) =>
        return Err(@local_sga.MatchEdgesExecutionIssue(@bounded.Terminal))
    }
  }
  abort("unreachable")
}

///|
fn finish_graph_bounds(
  execution : @local_sga.GraphBoundsExecution,
) -> Result[@execution.CompletedOutput, @local_sga.GraphBoundsIssue] {
  while true {
    let poll = match @local_sga.advance_graph_bounds(execution, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      @local_sga.GraphBoundsContinue(..) => ()
      @local_sga.GraphBoundsComplete(output, ..) => return Ok(output)
      @local_sga.GraphBoundsFailed(issue, ..) => return Err(issue)
      @local_sga.GraphBoundsStopped(_, ..) =>
        return Err(@local_sga.GraphBoundsExecutionIssue(@bounded.Terminal))
    }
  }
  abort("unreachable")
}

///|
fn finish_graph_degree(
  execution : @local_sga.GraphDegreeExecution,
) -> Result[@execution.CompletedOutput, @local_sga.GraphBoundsIssue] {
  while true {
    let poll = match @local_sga.advance_graph_degree(execution, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      @local_sga.GraphDegreeContinue(..) => ()
      @local_sga.GraphDegreeComplete(output, ..) => return Ok(output)
      @local_sga.GraphDegreeFailed(issue, ..) => return Err(issue)
      @local_sga.GraphDegreeStopped(_, ..) =>
        return Err(@local_sga.GraphBoundsExecutionIssue(@bounded.Terminal))
    }
  }
  Err(@local_sga.GraphBoundsExecutionIssue(@bounded.Terminal))
}

///|
fn finish_components(
  execution : @local_sga.ComponentsExecution,
) -> Result[@execution.CompletedOutput, @local_sga.ComponentsIssue] {
  while true {
    let poll = match @local_sga.advance_components(execution, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      @local_sga.ComponentsContinue(..) => ()
      @local_sga.ComponentsComplete(output, ..) => return Ok(output)
      @local_sga.ComponentsFailed(issue, ..) => return Err(issue)
      @local_sga.ComponentsStopped(_, ..) =>
        return Err(@local_sga.ComponentsExecutionIssue(@bounded.Terminal))
    }
  }
  Err(@local_sga.ComponentsExecutionIssue(@bounded.Terminal))
}

///|
fn finish_reach(
  execution : @local_sga.ReachExecution,
) -> Result[@execution.CompletedOutput, @local_sga.ReachIssue] {
  while true {
    let poll = match @local_sga.advance_reach(execution, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      @local_sga.ReachContinue(..) => ()
      @local_sga.ReachComplete(output, ..) => return Ok(output)
      @local_sga.ReachFailed(issue, ..) => return Err(issue)
      @local_sga.ReachStopped(_, ..) =>
        return Err(@local_sga.ReachExecutionIssue(@bounded.Terminal))
    }
  }
  Err(@local_sga.ReachExecutionIssue(@bounded.Terminal))
}

///|
fn finish_traverse(
  execution : @local_sga.TraverseExecution,
) -> Result[@execution.CompletedOutput, @local_sga.TraverseIssue] {
  while true {
    let poll = match @local_sga.advance_traverse(execution, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      @local_sga.TraverseContinue(..) => ()
      @local_sga.TraverseComplete(output, ..) => return Ok(output)
      @local_sga.TraverseFailed(issue, ..) => return Err(issue)
      @local_sga.TraverseStopped(_, ..) =>
        return Err(
          @local_sga.TraverseReachIssue(
            @local_sga.ReachExecutionIssue(@bounded.Terminal),
          ),
        )
    }
  }
  Err(
    @local_sga.TraverseReachIssue(
      @local_sga.ReachExecutionIssue(@bounded.Terminal),
    ),
  )
}

///|
fn match_nodes_predicate_output(
  source_owner : @lower.BoundPrepared,
  predicate : String,
  workspace? : Int = 8,
) -> @execution.CompletedOutput raise {
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_match_body_owner(
    source_owner,
    "{\"where\":\"" + predicate + "\",\"fields\":[\"id\",\"node_name\"]}",
  )
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let execution = @local_sga.start_match_nodes(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    2,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    workspace,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_match_nodes(execution).unwrap()
  assert_eq(@local_sga.cleanup_match_nodes(execution), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  output
}

///|
test "bounded node literal predicates select all or no entities" {
  let source_owner = carrier_graph_source_owner()
  let selected = match_nodes_predicate_output(source_owner, "true")
  assert_eq(@execution.completed_row_count(selected), 2)
  assert_true(@execution.completed_cell(selected, 0, 0) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(selected, 1, 1) is Some(Text("second")))

  let empty = match_nodes_predicate_output(source_owner, "false")
  assert_eq(@execution.completed_row_count(empty), 0)
  assert_true(@execution.completed_output_available(empty))
}

///|
test "bounded node match evaluates a checked property predicate" {
  let source_owner = carrier_graph_source_owner()
  let selected = match_nodes_predicate_output(
    source_owner,
    "node_name = 'second'",
    workspace=9,
  )
  assert_eq(@execution.completed_row_count(selected), 1)
  assert_true(@execution.completed_cell(selected, 0, 0) is Some(Number(2.0)))
  assert_true(@execution.completed_cell(selected, 0, 1) is Some(Text("second")))
  assert_true(@execution.completed_output_available(selected))
}

///|
test "bounded node identity match sorts deduplicates and completes atomically" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_match_owner(source_owner, "[2,1,2]")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let execution = @local_sga.start_match_nodes(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    2,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    8,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_match_nodes(execution).unwrap()
  assert_eq(@local_sga.cleanup_match_nodes(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Text("first")))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2.0)))
  assert_true(@execution.completed_cell(output, 1, 1) is Some(Text("second")))
  assert_true(@execution.completed_output_matches_inputs(output, [external]))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
}

///|
test "bounded node identity match rejects a missing identity before output" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_match_owner(source_owner, "[1,3]")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let execution = @local_sga.start_match_nodes(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    2,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    6,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(
    finish_match_nodes(execution) is Err(@local_sga.MissingMatchNodeIdentity(1)),
  )
  assert_eq(@local_sga.cleanup_match_nodes(execution), Ok(true))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "node identity match admits workspace before execution and cleans cancel" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_match_owner(source_owner, "[2,1,2]")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let completion = task_test_completion(owner)
  let start = fn(control, workspace) {
    @local_sga.start_match_nodes(
      control,
      completion,
      sequence,
      1,
      input,
      3,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [external],
    )
  }
  assert_true(
    start(@bounded.control(), 7) is Err(@local_sga.MatchNodesWorkspaceLimit),
  )
  let control = @bounded.control()
  let execution = start(control, 8).unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_match_nodes(execution, 1).unwrap()
    is @local_sga.MatchNodesStopped(_, progress=0L, work=0L),
  )
  assert_true(@local_sga.match_nodes_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_match_nodes(execution), Ok(true))
  assert_false(@local_sga.match_nodes_cleanup_pending(execution))
  assert_true(@execution.producer_read_available(external))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "bounded edge match filters repeated types and sorts canonically" {
  let source_owner = carrier_graph_labeled_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_edge_match_owner(
    source_owner, "[\"owns\",\"owns\"]",
  )
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let execution = @local_sga.start_match_edges(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    2,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    10,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_match_edges(execution).unwrap()
  assert_eq(@local_sga.cleanup_match_edges(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Text("owns")))
  assert_true(@execution.completed_cell(output, 0, 2) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(output, 0, 3) is Some(Number(10.0)))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(3.0)))
  assert_true(@execution.completed_cell(output, 1, 3) is Some(Number(30.0)))
  assert_true(@execution.completed_output_matches_inputs(output, [external]))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
}

///|
test "bounded edge match evaluates a checked property predicate" {
  let source_owner = carrier_graph_labeled_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_edge_match_owner(
    source_owner,
    "[\"owns\"]",
    predicate="\"weight > 10\"",
  )
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let start = fn(workspace) raise {
    @local_sga.start_match_edges(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      input,
      2,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [external],
    )
  }
  let insufficient = start(14).unwrap()
  assert_true(
    finish_match_edges(insufficient)
    is Err(@local_sga.MatchEdgesPredicate(@execution.WorkspaceLimit)),
  )
  assert_eq(@local_sga.cleanup_match_edges(insufficient), Ok(true))
  let execution = start(15).unwrap()
  let output = finish_match_edges(execution).unwrap()
  assert_eq(@local_sga.cleanup_match_edges(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3.0)))
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Text("owns")))
  assert_true(@execution.completed_cell(output, 0, 2) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(output, 0, 3) is Some(Number(30.0)))
  assert_true(@execution.completed_output_matches_inputs(output, [external]))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
}

///|
test "bounded edge match admits workspace and cleans cancellation" {
  let source_owner = carrier_graph_labeled_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_edge_match_owner(source_owner, "[]")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let completion = task_test_completion(owner)
  let start = fn(control, workspace) {
    @local_sga.start_match_edges(
      control,
      completion,
      sequence,
      1,
      input,
      2,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [external],
    )
  }
  assert_true(
    start(@bounded.control(), 9) is Err(@local_sga.MatchEdgesWorkspaceLimit),
  )
  let control = @bounded.control()
  let execution = start(control, 10).unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_match_edges(execution, 1).unwrap()
    is @local_sga.MatchEdgesStopped(_, progress=0L, work=0L),
  )
  assert_true(@local_sga.match_edges_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_match_edges(execution), Ok(true))
  assert_false(@local_sga.match_edges_cleanup_pending(execution))
  assert_true(@execution.producer_read_available(external))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "bounded graph diagnostics preserve row and identity order" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_bounds_owner(
    source_owner, "{\"max_nodes\":1,\"max_edges\":1,\"max_degree\":1}",
  )
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let execution = @local_sga.start_graph_bounds(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    10,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_graph_bounds(execution).unwrap()
  assert_eq(@local_sga.cleanup_graph_bounds(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 4)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Text("nodes")))
  assert_true(@execution.completed_cell(output, 0, 3) is Some(Null))
  assert_true(@execution.completed_cell(output, 1, 1) is Some(Text("edges")))
  assert_true(@execution.completed_cell(output, 2, 1) is Some(Text("degree")))
  assert_true(@execution.completed_cell(output, 2, 3) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(output, 3, 3) is Some(Number(2.0)))
  assert_true(@execution.completed_output_matches_inputs(output, [external]))
  let limited_input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let limited = @local_sga.start_graph_bounds(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    limited_input,
    3,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    10,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(
    finish_graph_bounds(limited)
    is Err(@local_sga.GraphBoundsOutput(@execution.CaptureLimit)),
  )
  assert_eq(@local_sga.cleanup_graph_bounds(limited), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
}

///|
test "graph diagnostics admit workspace before execution and clean cancel" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_bounds_owner(source_owner, "{\"max_degree\":1}")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let completion = task_test_completion(owner)
  let start = fn(control, workspace) {
    @local_sga.start_graph_bounds(
      control,
      completion,
      sequence,
      1,
      input,
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [external],
    )
  }
  assert_true(
    start(@bounded.control(), 9) is Err(@local_sga.GraphBoundsWorkspaceLimit),
  )
  let control = @bounded.control()
  let execution = start(control, 10).unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_graph_bounds(execution, 1).unwrap()
    is @local_sga.GraphBoundsStopped(_, progress=0L, work=0L),
  )
  assert_true(@local_sga.graph_bounds_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_graph_bounds(execution), Ok(true))
  assert_false(@local_sga.graph_bounds_cleanup_pending(execution))
  assert_true(@execution.producer_read_available(external))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "degree metrics preserve directions and admitted execution" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  for direction in ["in", "out", "both"] {
    let owner = carrier_graph_degree_owner(source_owner, direction)
    let sequence = prepared_sequence(owner)
    let external = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
      100,
      1000,
    ).unwrap()
    let construction = @local_bridge.start_rows_to_graph(
      @bounded.control(),
      sequence,
      0,
      [external, external],
      carrier_graph_storage_limits(),
      4096L,
      100,
      fn() { true },
    ).unwrap()
    let graph = finish_rows_to_graph(construction)
    assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
    let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
    let completion = task_test_completion(owner)
    let start = fn(workspace) {
      @local_sga.start_graph_degree(
        @bounded.control(),
        completion,
        sequence,
        1,
        input,
        2,
        {
          max_nodes: 1000,
          max_text_bytes: 1000,
          max_depth: 10,
          max_work: 10000,
        },
        workspace,
        1000,
        1000,
        [external],
      )
    }
    assert_true(start(7) is Err(@local_sga.GraphBoundsWorkspaceLimit))
    let execution = start(8).unwrap()
    let output = finish_graph_degree(execution).unwrap()
    assert_eq(@local_sga.cleanup_graph_degree(execution), Ok(true))
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 1) is Some(Number(1.0)))
    let expected = if direction == "both" { 2.0 } else { 1.0 }
    guard @execution.completed_cell(output, 0, 0) is Some(Number(first)) &&
      @execution.completed_cell(output, 1, 0) is Some(Number(second)) else {
      fail("degree output must contain numeric metrics")
    }
    assert_eq(first, expected)
    assert_eq(second, expected)
    assert_true(@graphs.discard_completed(graph))
    assert_true(@execution.completed_output_available(output))
  }
}

///|
test "total degree counts both self-loop incidences" {
  let source_owner = carrier_graph_self_loop_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_degree_owner(source_owner, "both")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let execution = @local_sga.start_graph_degree(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    1,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    5,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_graph_degree(execution).unwrap()
  assert_eq(@local_sga.cleanup_graph_degree(execution), Ok(true))
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Number(1.0)))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "weak and strong components preserve canonical identities and bounds" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  for kind in ["weak", "strong"] {
    let owner = carrier_graph_components_owner(source_owner, kind)
    let sequence = prepared_sequence(owner)
    let external = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
      100,
      1000,
    ).unwrap()
    let construction = @local_bridge.start_rows_to_graph(
      @bounded.control(),
      sequence,
      0,
      [external, external],
      carrier_graph_storage_limits(),
      4096L,
      100,
      fn() { true },
    ).unwrap()
    let graph = finish_rows_to_graph(construction)
    assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
    let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
    let completion = task_test_completion(owner)
    let start = fn(workspace) {
      @local_sga.start_components(
        @bounded.control(),
        completion,
        sequence,
        1,
        input,
        4,
        {
          max_nodes: 1000,
          max_text_bytes: 1000,
          max_depth: 10,
          max_work: 10000,
        },
        workspace,
        1000,
        1000,
        [external],
      )
    }
    assert_true(start(72) is Err(@local_sga.ComponentsWorkspaceLimit))
    let execution = start(73).unwrap()
    let output = finish_components(execution).unwrap()
    assert_eq(@local_sga.cleanup_components(execution), Ok(true))
    assert_eq(@execution.completed_row_count(output), 4)
    let expected_components = if kind == "weak" {
      [1.0, 1.0, 1.0, 4.0]
    } else {
      [1.0, 1.0, 3.0, 4.0]
    }
    let expected_sizes = if kind == "weak" {
      [3.0, 3.0, 3.0, 1.0]
    } else {
      [2.0, 2.0, 1.0, 1.0]
    }
    for row in 0..<4 {
      let expected_component = expected_components[row]
      let expected_size = expected_sizes[row]
      let expected_node = (row + 1).to_double()
      assert_true(
        @execution.completed_cell(output, row, 0) is Some(Number(value)) &&
        value == expected_component,
      )
      assert_true(
        @execution.completed_cell(output, row, 1) is Some(Number(value)) &&
        value == expected_size,
      )
      assert_true(
        @execution.completed_cell(output, row, 2) is Some(Number(value)) &&
        value == expected_node,
      )
    }
    assert_true(@execution.completed_output_matches_inputs(output, [external]))
    let cancel_control = @bounded.control()
    let cancelled = @local_sga.start_components(
      cancel_control,
      completion,
      sequence,
      1,
      @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      73,
      1000,
      1000,
      [external],
    ).unwrap()
    assert_true(@bounded.request_cancel(cancel_control))
    assert_true(
      @local_sga.advance_components(cancelled, 1).unwrap()
      is @local_sga.ComponentsStopped(_, progress=0L, work=0L),
    )
    assert_true(@local_sga.components_cleanup_pending(cancelled))
    assert_eq(@local_sga.cleanup_components(cancelled), Ok(true))
    assert_false(@local_sga.components_cleanup_pending(cancelled))
    assert_true(@graphs.discard_completed(graph))
    assert_true(@execution.completed_output_available(output))
  }

  let guarded_owner = carrier_graph_components_owner(
    source_owner,
    "weak",
    max_guard=",\"max_output_rows\":3",
  )
  let guarded_sequence = prepared_sequence(guarded_owner)
  let guarded_external = @execution.prepare_producer_read(
    guarded_owner,
    @execution.bind_completed_input(guarded_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let guarded_construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    guarded_sequence,
    0,
    [guarded_external, guarded_external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let guarded_graph = finish_rows_to_graph(guarded_construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(guarded_construction), Ok(true))
  assert_true(
    @local_sga.start_components(
      @bounded.control(),
      task_test_completion(guarded_owner),
      guarded_sequence,
      1,
      @graphs.prepare_step_read(guarded_owner, 1, 0, guarded_graph).unwrap(),
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      73,
      1000,
      1000,
      [guarded_external],
    )
    is Err(@local_sga.ComponentsOutputLimit),
  )
  assert_true(@graphs.discard_completed(guarded_graph))
}

///|
test "reach preserves direction depth bounds and cancellation" {
  for
    (direction, depth, rows, expected_nodes) in [
      (
        "out",
        "2",
        "[{\"id\":1,\"src\":1,\"dst\":2," +
        "\"node_name\":\"one\",\"weight\":10},{\"id\":2," +
        "\"src\":2,\"dst\":1,\"node_name\":\"two\",\"weight\":20}," +
        "{\"id\":3,\"src\":2,\"dst\":3,\"node_name\":\"three\"," +
        "\"weight\":30},{\"id\":4,\"src\":4,\"dst\":4," +
        "\"node_name\":\"four\",\"weight\":40}]",
        [1.0, 2.0, 3.0],
      ),
      (
        "in",
        "2",
        "[{\"id\":1,\"src\":1,\"dst\":2," +
        "\"node_name\":\"one\",\"weight\":10},{\"id\":2," +
        "\"src\":2,\"dst\":1,\"node_name\":\"two\",\"weight\":20}," +
        "{\"id\":3,\"src\":2,\"dst\":3,\"node_name\":\"three\"," +
        "\"weight\":30},{\"id\":4,\"src\":4,\"dst\":4," +
        "\"node_name\":\"four\",\"weight\":40}]",
        [1.0, 2.0],
      ),
      (
        "both",
        "2",
        "[{\"id\":1,\"src\":1,\"dst\":2," +
        "\"node_name\":\"one\",\"weight\":10},{\"id\":2," +
        "\"src\":2,\"dst\":1,\"node_name\":\"two\",\"weight\":20}," +
        "{\"id\":3,\"src\":2,\"dst\":3,\"node_name\":\"three\"," +
        "\"weight\":30},{\"id\":4,\"src\":4,\"dst\":4," +
        "\"node_name\":\"four\",\"weight\":40}]",
        [1.0, 2.0, 3.0],
      ),
      (
        "out",
        "9007199254740991",
        "[{\"id\":1,\"src\":1,\"dst\":1," +
        "\"node_name\":\"self\",\"weight\":10}]",
        [1.0],
      ),
    ] {
    let source_owner = carrier_graph_source_owner_with_rows(rows)
    let source = carrier_events_source_output(source_owner)
    let owner = carrier_graph_reach_owner_with_depth(
      source_owner, 1, direction, depth,
    )
    let sequence = prepared_sequence(owner)
    let external = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
      100,
      1000,
    ).unwrap()
    let construction = @local_bridge.start_rows_to_graph(
      @bounded.control(),
      sequence,
      0,
      [external, external],
      carrier_graph_storage_limits(),
      4096L,
      100,
      fn() { true },
    ).unwrap()
    let graph = finish_rows_to_graph(construction)
    assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
    let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
    let completion = task_test_completion(owner)
    assert_true(
      @local_sga.start_reach(
        @bounded.control(),
        completion,
        sequence,
        1,
        input,
        4,
        {
          max_nodes: 1000,
          max_text_bytes: 1000,
          max_depth: 10,
          max_work: 10000,
        },
        0,
        1000,
        1000,
        [external],
      )
      is Err(@local_sga.ReachWorkspaceLimit),
    )
    let execution = @local_sga.start_reach(
      @bounded.control(),
      completion,
      sequence,
      1,
      input,
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      100,
      1000,
      1000,
      [external],
    ).unwrap()
    let output = finish_reach(execution).unwrap()
    assert_eq(@local_sga.cleanup_reach(execution), Ok(true))
    assert_eq(@execution.completed_row_count(output), expected_nodes.length())
    for row, expected in expected_nodes {
      assert_true(
        @execution.completed_cell(output, row, 3) is Some(Number(value)) &&
        value == 1.0,
      )
      assert_true(
        @execution.completed_cell(output, row, 2) is Some(Number(value)) &&
        value == expected,
      )
      let depth = if expected == 1.0 {
        0.0
      } else if expected == 2.0 {
        1.0
      } else {
        2.0
      }
      assert_true(
        @execution.completed_cell(output, row, 0) is Some(Number(value)) &&
        value == depth,
      )
    }
    assert_true(@execution.completed_output_matches_inputs(output, [external]))
    assert_true(@graphs.discard_completed(graph))
    assert_true(@execution.completed_output_available(output))
  }

  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_reach_owner(source_owner, 1, "out", 2)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  let control = @bounded.control()
  let cancelled = @local_sga.start_reach(
    control,
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_reach(cancelled, 1).unwrap()
    is @local_sga.ReachStopped(_, progress=0L, work=0L),
  )
  assert_true(@local_sga.reach_cleanup_pending(cancelled))
  assert_eq(@local_sga.cleanup_reach(cancelled), Ok(true))
  assert_false(@local_sga.reach_cleanup_pending(cancelled))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "homogeneous traversal enforces minimum depth and cancellation" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_traverse_owner(source_owner, 1, 2)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let execution = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_traverse(execution).unwrap()
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Number(1.0)) &&
    @execution.completed_cell(output, 0, 1) is Some(Number(2.0)) &&
    @execution.completed_cell(output, 0, 2) is Some(Number(1.0)),
  )
  assert_true(@execution.completed_cell(output, 1, 1) is Some(Number(3.0)))
  assert_true(
    @execution.completed_cell(output, 1, 0) is Some(Number(2.0)) &&
    @execution.completed_cell(output, 1, 2) is Some(Number(1.0)),
  )
  assert_true(@execution.completed_output_matches_inputs(output, [external]))

  let control = @bounded.control()
  let cancelled = @local_sga.start_traverse(
    control,
    task_test_completion(owner),
    sequence,
    1,
    input,
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_traverse(cancelled, 1).unwrap()
    is @local_sga.TraverseStopped(_, progress=0L, work=0L),
  )
  assert_true(@local_sga.traverse_stopped(cancelled))
  assert_true(@local_sga.traverse_cleanup_pending(cancelled))
  assert_eq(@local_sga.cleanup_traverse(cancelled), Ok(true))
  assert_false(@local_sga.traverse_cleanup_pending(cancelled))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
}

///|
test "Graph provider rejects unsupported traversal before execution" {
  let source_owner = carrier_graph_components_source_owner()
  let owner = carrier_graph_traverse_owner(source_owner, 1, 2, emission="paths")
  let generated = task_test_generated(owner)
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_false(@local_connector.managed_provider_accepts(provider, generated))
}

///|
fn carrier_graph_consumer_output(
  producer : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
  projection : String,
) -> @execution.CompletedOutput raise {
  let consumer = typed_receiver(producer, projection, target=@pipeline.Step(1))
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
test "bounded Graph bridge preserves repeated positions and two consumers" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  assert_true(
    @local_bridge.start_rows_to_graph(
      @bounded.control(),
      sequence,
      0,
      [external, external],
      carrier_graph_storage_limits(),
      4096L,
      9,
      fn() { true },
    )
    is Err(@local_bridge.GraphWorkspaceLimit),
  )
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let projection_input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let projection = @local_bridge.start_graph_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let rows = finish_graph_to_rows(projection)
  assert_eq(@local_bridge.cleanup_graph_to_rows(projection), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_eq(@execution.completed_row_count(rows), 2)
  assert_true(@execution.completed_output_matches_inputs(rows, [external]))
  let first = carrier_graph_consumer_output(
    owner, rows, "[{\"select\":[\"id\",\"node_name\"]}]",
  )
  let second = carrier_graph_consumer_output(
    owner, rows, "[{\"select\":[\"node_name\"]}]",
  )
  assert_true(@execution.completed_cell(first, 0, 0) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(first, 1, 1) is Some(Text("second")))
  assert_true(@execution.completed_cell(second, 0, 0) is Some(Text("first")))
  assert_true(@execution.completed_output_available(rows))
}

///|
test "bounded Graph edge projection survives Graph reclamation" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner, projection="edge_rows")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    10,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let projection_input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let projection = @local_bridge.start_graph_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let rows = finish_graph_to_rows(projection)
  assert_eq(@local_bridge.cleanup_graph_to_rows(projection), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_eq(@execution.completed_row_count(rows), 2)
  let first = carrier_graph_consumer_output(
    owner, rows, "[{\"select\":[\"src\",\"dst\",\"weight\"]}]",
  )
  let second = carrier_graph_consumer_output(
    owner, rows, "[{\"select\":[\"weight\",\"src\"]}]",
  )
  assert_true(@execution.completed_cell(first, 0, 0) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(first, 0, 1) is Some(Number(2.0)))
  assert_true(@execution.completed_cell(first, 1, 2) is Some(Number(20.0)))
  assert_true(@execution.completed_cell(second, 0, 0) is Some(Number(10.0)))
  assert_true(@execution.completed_output_available(rows))
}

///|
test "explicit Graph construction closes absent edge endpoints" {
  let source_owner = carrier_graph_open_endpoint_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner, projection="edge_rows")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let projection_input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let projection = @local_bridge.start_graph_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let rows = finish_graph_to_rows(projection)
  assert_eq(@local_bridge.cleanup_graph_to_rows(projection), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_eq(@execution.completed_row_count(rows), 0)
}

///|
test "Graph bridge cancellation stops before cleanup and preserves inputs" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let control = @bounded.control()
  let construction = @local_bridge.start_rows_to_graph(
    control,
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    10,
    fn() { true },
  ).unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_bridge.advance_rows_to_graph(construction, 1).unwrap()
    is @local_bridge.Stopped(_, ..),
  )
  assert_true(@local_bridge.rows_to_graph_cleanup_pending(construction))
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  assert_false(@local_bridge.rows_to_graph_cleanup_pending(construction))
  assert_true(@execution.producer_read_available(external))
}

///|
test "registered Graph provider expands repeated semantic input positions" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner)
  let generated = task_test_generated(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
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
        fail("Graph provider returned a Carrier output")
      @local_connector.Failed(_, ..) => fail("Graph provider failed")
      @local_connector.Stopped(..) => fail("Graph provider stopped")
    }
  }
  let completed = output.unwrap()
  assert_eq(@execution.completed_row_count(completed), 2)
  assert_true(@execution.completed_output_matches_inputs(completed, [external]))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@execution.completed_output_available(completed))
  assert_true(@execution.producer_read_available(external))
}

///|
test "registered Graph provider executes node identity match for two consumers" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_match_owner(source_owner, "[2,1,2]")
  let generated = task_test_generated(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
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
    2,
    1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("Graph provider returned a Carrier output")
      @local_connector.Failed(_, ..) => fail("Graph match provider failed")
      @local_connector.Stopped(..) => fail("Graph match provider stopped")
    }
  }
  let completed = output.unwrap()
  assert_eq(@execution.completed_row_count(completed), 2)
  assert_true(@execution.completed_cell(completed, 0, 0) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(completed, 1, 0) is Some(Number(2.0)))
  assert_true(@execution.completed_output_matches_inputs(completed, [external]))
  let first = carrier_graph_consumer_output(
    owner, completed, "[{\"select\":[\"id\",\"node_name\"]}]",
  )
  let second = carrier_graph_consumer_output(
    owner, completed, "[{\"select\":[\"node_name\"]}]",
  )
  assert_eq(@execution.completed_row_count(first), 2)
  assert_eq(@execution.completed_row_count(second), 2)
  assert_true(@execution.completed_cell(first, 1, 1) is Some(Text("second")))
  assert_true(@execution.completed_cell(second, 0, 0) is Some(Text("first")))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@execution.completed_output_available(completed))
  assert_true(@execution.producer_read_available(external))
}

///|
fn carrier_graft_contract() -> @carrier_contract.Carrier {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  let node = @carrier_contract.rows(
    [
      (
        @schema.Unqualified("name"),
        Some(
          @value_contract.primitive(@value_contract.StringType, nullable=false),
        ),
      ),
    ],
    field_set=@carrier_contract.Closed,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  let edge = @carrier_contract.rows(
    [],
    field_set=@carrier_contract.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  @carrier_contract.graph(
    number,
    node,
    edge,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
}

///|
fn carrier_graft_source_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check_carriers(
    input_cursor("[{\"from\":\"g\",\"normalize_graph\":true}]"),
    [("g", carrier_graft_contract())],
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
fn carrier_graft_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"left\",\"graft_graph\":{\"with\":\"right\"}," +
      "\"as\":\"g\"},{\"from\":\"g\",\"node_rows\":true," +
      "\"as\":\"out\"}]",
    ),
    [
      (
        "left",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(left)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
      (
        "right",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(right)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
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
fn carrier_union_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"left\",\"union_graphs\":{" +
      "\"with\":[\"right\",\"left\",\"right\"]}," +
      "\"as\":\"g\"},{\"from\":\"g\",\"node_rows\":true," +
      "\"as\":\"out\"}]",
    ),
    [
      (
        "left",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(left)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
      (
        "right",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(right)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
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
fn carrier_union_merge_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"left\",\"union_graphs\":{" +
      "\"with\":\"right\",\"merge\":{" +
      "\"node_properties\":{\"name\":\"exact_equal\"}}}," +
      "\"as\":\"g\"},{\"from\":\"g\",\"node_rows\":true}]",
    ),
    [
      (
        "left",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(left)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
      (
        "right",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(right)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
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
fn carrier_graft_graph(
  owner : @lower.BoundPrepared,
  identity : Double,
  name : String,
) -> @graphs.Completed {
  let output = @graphs.prepare_output(
    owner,
    @pipeline.Step(0),
    @graph_storage.DeclaredNodes,
    carrier_graph_storage_limits(),
    2048L,
    fn() { true },
  ).unwrap()
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  let text = @value_contract.primitive(
    @value_contract.StringType,
    nullable=false,
  )
  @graphs.append_node(
    output,
    @admitted.checked_number_value(identity, number).unwrap(),
    [@admitted.checked_text_value(name, text).unwrap()],
  ).unwrap()
  @graphs.finish_output(output).unwrap()
}

///|
test "registered Graph provider grafts exact Carrier inputs into rows" {
  let left_owner = carrier_graft_source_owner()
  let right_owner = carrier_graft_source_owner()
  let owner = carrier_graft_owner(left_owner, right_owner)
  let generated = task_test_generated(owner)
  let left = carrier_graft_graph(left_owner, 1.0, "left")
  let right = carrier_graft_graph(right_owner, 2.0, "right")
  let left_material = @graphs.completed_material(left).unwrap()
  let right_material = @graphs.completed_material(right).unwrap()
  let left_view = @carrier_runtime.material_prepare_view(
    left_material, owner, 0, left_owner,
  ).unwrap()
  let right_view = @carrier_runtime.material_prepare_view(
    right_material, owner, 1, right_owner,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(left_view),
      @local_connector.managed_provider_carrier_input(right_view),
    ],
    10,
    1000,
  ).unwrap()
  let mut completed = None
  while completed is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(output, ..) => completed = Some(output)
      @local_connector.CarrierComplete(_, ..) =>
        fail("graft projection returned a Carrier")
      @local_connector.Failed(_, ..) => fail("graft provider failed")
      @local_connector.Stopped(..) => fail("graft provider stopped")
    }
  }
  let output = completed.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Text("left")))
  assert_true(@execution.completed_cell(output, 1, 1) is Some(Text("right")))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(left_material))
  assert_true(@carrier_runtime.material_available(right_material))
}

///|
test "registered Graph provider unions an ordered repeated Carrier list" {
  let left_owner = carrier_graft_source_owner()
  let right_owner = carrier_graft_source_owner()
  let owner = carrier_union_owner(left_owner, right_owner)
  let generated = task_test_generated(owner)
  let left = carrier_graft_graph(left_owner, 1.0, "left")
  let right = carrier_graft_graph(right_owner, 2.0, "right")
  let left_material = @graphs.completed_material(left).unwrap()
  let right_material = @graphs.completed_material(right).unwrap()
  let inputs = [
    @carrier_runtime.material_prepare_view(left_material, owner, 0, left_owner).unwrap(),
    @carrier_runtime.material_prepare_view(
      right_material, owner, 1, right_owner,
    ).unwrap(),
  ]
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    inputs.map(@local_connector.managed_provider_carrier_input),
    10,
    1000,
  ).unwrap()
  let mut completed = None
  while completed is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(output, ..) => completed = Some(output)
      @local_connector.CarrierComplete(_, ..) =>
        fail("union projection returned a Carrier")
      @local_connector.Failed(_, ..) => fail("union provider failed")
      @local_connector.Stopped(..) => fail("union provider stopped")
    }
  }
  let output = completed.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Text("left")))
  assert_true(@execution.completed_cell(output, 1, 1) is Some(Text("right")))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(left_material))
  assert_true(@carrier_runtime.material_available(right_material))
}

///|
test "registered Graph provider admits explicit exact union properties" {
  let left_owner = carrier_graft_source_owner()
  let right_owner = carrier_graft_source_owner()
  let owner = carrier_union_merge_owner(left_owner, right_owner)
  let generated = task_test_generated(owner)
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
}

///|
test "Graph union rejects conflicting repeated identities atomically" {
  let left_owner = carrier_graft_source_owner()
  let right_owner = carrier_graft_source_owner()
  let owner = carrier_union_owner(left_owner, right_owner)
  let generated = task_test_generated(owner)
  let left = carrier_graft_graph(left_owner, 1.0, "left")
  let right = carrier_graft_graph(right_owner, 1.0, "different")
  let left_material = @graphs.completed_material(left).unwrap()
  let right_material = @graphs.completed_material(right).unwrap()
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(
        @carrier_runtime.material_prepare_view(
          left_material, owner, 0, left_owner,
        ).unwrap(),
      ),
      @local_connector.managed_provider_carrier_input(
        @carrier_runtime.material_prepare_view(
          right_material, owner, 1, right_owner,
        ).unwrap(),
      ),
    ],
    10,
    1000,
  ).unwrap()
  let mut failed = false
  while !failed {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.Failed(_, ..) => failed = true
      @local_connector.Complete(_, ..)
      | @local_connector.CarrierComplete(_, ..) =>
        fail("conflicting union completed")
      @local_connector.Stopped(..) => fail("conflicting union stopped")
    }
  }
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(left_material))
  assert_true(@carrier_runtime.material_available(right_material))
}

///|
test "registered Graph material crosses tasks to Graph and Bridge consumers" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let graph_owner = carrier_graph_material_owner(source_owner)
  let graph_generated = task_test_generated(graph_owner)
  let external = @execution.prepare_producer_read(
    graph_owner,
    @execution.bind_completed_input(graph_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let limits = carrier_graph_storage_limits()
  let graph_provider = @local_sga_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      graph_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(
    @local_connector.managed_provider_accepts(graph_provider, graph_generated),
  )
  let graph_execution = @local_connector.start_managed_provider(
    graph_provider,
    graph_generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut material = None
  while material is None {
    match
      @local_connector.advance_managed_provider(graph_execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) => material = Some(value)
      @local_connector.Complete(_, ..) => fail("Graph producer returned rows")
      @local_connector.Failed(_, ..) => fail("Graph producer failed")
      @local_connector.Stopped(..) => fail("Graph producer stopped")
    }
  }
  assert_true(
    @local_connector.cleanup_managed_provider(graph_execution).unwrap_or(false),
  )
  let material = material.unwrap()
  assert_eq(
    @carrier_runtime.material_kind(material),
    @carrier_contract.GraphKind,
  )

  let graph_consumer = carrier_graft_owner(graph_owner, graph_owner)
  let bridge_consumer = carrier_graph_projection_owner(graph_owner, "edge_rows")
  let graph_first = @carrier_runtime.material_prepare_view(
    material, graph_consumer, 0, graph_owner,
  ).unwrap()
  let graph_second = @carrier_runtime.material_prepare_view(
    material, graph_consumer, 1, graph_owner,
  ).unwrap()
  let bridge_input = @carrier_runtime.material_prepare_view(
    material, bridge_consumer, 0, graph_owner,
  ).unwrap()
  let graph_consumer_generated = task_test_generated(graph_consumer)
  let bridge_consumer_generated = task_test_generated(bridge_consumer)
  let graph_consumer_provider = @local_sga_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      graph_consumer_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let bridge_consumer_provider = @local_sga_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      bridge_consumer_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let graph_run = @local_connector.start_managed_provider_with_inputs(
    graph_consumer_provider,
    graph_consumer_generated,
    [
      @local_connector.managed_provider_carrier_input(graph_first),
      @local_connector.managed_provider_carrier_input(graph_second),
    ],
    10,
    1000,
  ).unwrap()
  let bridge_run = @local_connector.start_managed_provider_with_inputs(
    bridge_consumer_provider,
    bridge_consumer_generated,
    [@local_connector.managed_provider_carrier_input(bridge_input)],
    10,
    1000,
  ).unwrap()
  let mut graph_rows = None
  while graph_rows is None {
    match @local_connector.advance_managed_provider(graph_run, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => graph_rows = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("Graph consumer returned a Carrier")
      @local_connector.Failed(_, ..) => fail("Graph consumer failed")
      @local_connector.Stopped(..) => fail("Graph consumer stopped")
    }
  }
  assert_true(
    @local_connector.cleanup_managed_provider(graph_run).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(material))
  let mut bridge_rows = None
  while bridge_rows is None {
    match @local_connector.advance_managed_provider(bridge_run, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => bridge_rows = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("Graph Bridge returned a Carrier")
      @local_connector.Failed(_, ..) => fail("Graph Bridge failed")
      @local_connector.Stopped(..) => fail("Graph Bridge stopped")
    }
  }
  assert_eq(@execution.completed_row_count(graph_rows.unwrap()), 2)
  assert_eq(@execution.completed_row_count(bridge_rows.unwrap()), 2)
  assert_true(
    @local_connector.cleanup_managed_provider(bridge_run).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(material))

  let cancel_owner = carrier_graph_projection_owner(graph_owner, "node_rows")
  let cancel_generated = task_test_generated(cancel_owner)
  let cancel_view = @carrier_runtime.material_prepare_view(
    material, cancel_owner, 0, graph_owner,
  ).unwrap()
  let cancel_provider = @local_sga_provider.provider(
    limits,
    4096L,
    @execution.generated_sequence_capacity(
      cancel_generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let cancel_run = @local_connector.start_managed_provider_with_inputs(
    cancel_provider,
    cancel_generated,
    [@local_connector.managed_provider_carrier_input(cancel_view)],
    10,
    1000,
  ).unwrap()
  assert_true(@local_connector.cancel_managed_provider(cancel_run))
  assert_true(
    @local_connector.advance_managed_provider(cancel_run, 1).unwrap()
    is @local_connector.Stopped(..),
  )
  assert_true(
    @local_connector.cleanup_managed_provider(cancel_run).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
  assert_false(@carrier_runtime.material_available(material))
}

///|
fn graph_publication_obligations(
  run : @strategy.CapturedDAG,
  publication : Bool,
) -> @execution.ManagedObligations? {
  if publication {
    Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
  } else {
    None
  }
}

///|
fn graph_relation_publication_cid(variant : String) -> String {
  if variant == "subtract_exact" {
    "sha256:61658ff21fd18cc3b110c965c92422c813ef6e76d1aef0415841101c72e8f576"
  } else if variant == "subtract" {
    "sha256:581c1ad7ac48237df5c669e328275ed013a700f7308143a32557810117210089"
  } else if variant == "graph_bounds" {
    "sha256:17d576d1679a19ebaa39babfe25c6922f65888c29781f7ea73b3f2af674b13c7"
  } else if variant == "match_edges" || variant == "edge_projection" {
    "sha256:c60b5715592edabcbe32bd818f14c8d413b3717806662aa06c9e4eae57420932"
  } else if variant == "match_edges_predicate" {
    "sha256:2565b440f95c1ee69574099652dde59d535c5a390fe62c29de3b147d3ce32304"
  } else if variant == "match_nodes_predicate" {
    "sha256:a2151218d0638a59beb6b366fa8f2d0803e643139fd8c19cae1f9c8d6044f78f"
  } else if variant == "degree_both" {
    "sha256:3a537f671c5f32a7a9e97bb2e1a0edd04aeec3df32a5403bef7801958022deb0"
  } else if variant == "reach_out" {
    "sha256:821ce11feb97033bed3e665dd44185973dab504b4d5f85ee72b24ae212b765e4"
  } else if variant == "traverse_out" {
    "sha256:92400debf0eecbf465589ca37f212e8480db77c26ce2279ae4c00993121bd2e1"
  } else if variant == "graphs_equal" ||
    variant == "graphs_nullable_equal" ||
    variant == "graphs_nullable_null_equal" {
    "sha256:e9f87b3bf1a837c8ac5b37d1c231c25071935f3dc3c202b3ace9c4d55acddc37"
  } else {
    "sha256:61658ff21fd18cc3b110c965c92422c813ef6e76d1aef0415841101c72e8f576"
  }
}

///|
fn run_standard_host_graph_relation_path(
  variant : String,
  publication? : Bool = false,
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_graph_chain=true,
    local_carrier_graph_variant=variant,
    managed_publication=publication,
    ledger_limits=if variant.has_suffix("unequal") ||
      variant == "split_projection" ||
      variant.has_prefix("subtract") {
      Some({
        planning_work: 20000,
        attempts: 20,
        holdings: 20,
        transfer_bytes: 600000L,
        retained_bytes: 64000000L,
        execution_bytes: 268435456L,
      })
    } else {
      None
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
  let graph_task = if variant.has_suffix("unequal") ||
    variant == "split_projection" ||
    variant.has_prefix("subtract") {
    3
  } else {
    2
  }
  let cleanup_attempts = Ref(0)
  let provider = delayed_cleanup_provider(
    @local_sga_provider.provider(
      carrier_graph_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        sequences[graph_task - 1],
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
        ..retained_attempt_wire_limits(),
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 10,
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
    obligations?=graph_publication_obligations(run, publication),
  )
  let values_rows = local_managed_test_rows(values_ops)
  let graph_inputs = if variant == "split_projection" { [] } else { [values] }
  let graph_input_rows = if variant == "split_projection" {
    []
  } else {
    [values_rows]
  }
  let other_cleanup : Ref[(() -> Unit)?] = Ref(None)
  if variant.has_suffix("unequal") ||
    variant == "split_projection" ||
    variant.has_prefix("subtract") {
    let other_live = Ref(true)
    let (other_ops, other) = run_local_managed_test_task(
      installed,
      run,
      2,
      [],
      [],
      2,
      other_live,
      obligations?=graph_publication_obligations(run, publication),
    )
    if variant == "split_projection" {
      graph_inputs.push(other)
      graph_input_rows.push(local_managed_test_rows(other_ops))
      graph_inputs.push(values)
      graph_input_rows.push(values_rows)
    } else {
      graph_inputs.push(other)
      graph_input_rows.push(local_managed_test_rows(other_ops))
    }
    other_cleanup.val = Some(fn() {
      other_live.val = false
      @strategy.close_captured_task_output(run, 2)
      (other_ops.close)()
      (other_ops.cleanup_refresh)() |> ignore
    })
  }
  let graph_live = Ref(true)
  let graph_obligations = graph_publication_obligations(run, publication)
  let (graph_ops, graph) = run_local_managed_test_task(
    installed,
    run,
    graph_task,
    graph_inputs,
    graph_input_rows,
    graph_task,
    graph_live,
    obligations?=graph_obligations,
  )
  let graph_rows = local_managed_test_rows(graph_ops)
  let expected_rows = if variant == "graph_bounds" {
    4
  } else if variant == "traverse_out" || variant == "subtract" {
    1
  } else if variant == "match_edges_predicate" ||
    variant == "match_nodes_predicate" {
    1
  } else if is_graph_equality_variant(variant) {
    1
  } else {
    2
  }
  assert_eq(graph_rows.length(), expected_rows)
  if variant == "subtract" {
    assert_true(graph_rows[0].contains("\"id\":1"))
  } else if variant == "subtract_exact" {
    assert_true(graph_rows[0].contains("\"id\":1"))
    assert_true(graph_rows[1].contains("\"id\":2"))
    assert_true(graph_rows[1].contains("\"node_name\":\"second\""))
  } else if variant == "match_edges" || variant == "edge_projection" {
    assert_true(graph_rows[0].contains("\"src\":1"))
    assert_true(graph_rows[1].contains("\"weight\":20"))
  } else if variant == "match_edges_predicate" {
    assert_true(graph_rows[0].contains("\"src\":2"))
    assert_true(graph_rows[0].contains("\"weight\":20"))
  } else if variant == "graph_bounds" {
    assert_true(graph_rows[0].contains("\"kind\":\"nodes\""))
    assert_true(graph_rows[1].contains("\"kind\":\"edges\""))
    assert_true(graph_rows[2].contains("\"node_id\":1"))
    assert_true(graph_rows[3].contains("\"node_id\":2"))
  } else if variant.has_prefix("degree_") {
    assert_true(graph_rows[0].contains("\"node\":1"))
    assert_true(graph_rows[1].contains("\"node\":2"))
    let expected_degree = if variant == "degree_both" { 2 } else { 1 }
    assert_true(
      graph_rows[0].contains(
        "\"degree\":" + expected_degree.to_double().to_string(),
      ),
    )
    assert_true(
      graph_rows[1].contains(
        "\"degree\":" + expected_degree.to_double().to_string(),
      ),
    )
  } else if variant.has_prefix("components_") {
    assert_true(graph_rows[0].contains("\"component_id\":1"))
    assert_true(graph_rows[0].contains("\"component_size\":2"))
    assert_true(graph_rows[0].contains("\"node_id\":1"))
    assert_true(graph_rows[1].contains("\"node_id\":2"))
  } else if variant.has_prefix("reach_") {
    assert_true(graph_rows[0].contains("\"start_id\":1"))
    assert_true(graph_rows[0].contains("\"node_id\":1"))
    assert_true(graph_rows[0].contains("\"depth\":0"))
    assert_true(graph_rows[1].contains("\"node_id\":2"))
    assert_true(graph_rows[1].contains("\"depth\":1"))
  } else if variant.has_prefix("traverse_") {
    assert_true(graph_rows[0].contains("\"start_id\":1"))
    assert_true(graph_rows[0].contains("\"node_id\":2"))
    assert_true(graph_rows[0].contains("\"depth\":1"))
  } else if variant == "match_nodes_predicate" {
    assert_true(graph_rows[0].contains("\"id\":2"))
    assert_true(graph_rows[0].contains("\"node_name\":\"second\""))
  } else if variant == "graphs_equal" ||
    variant == "graphs_equal_reverse" ||
    variant == "graphs_equal_self" ||
    variant == "graphs_nullable_equal" ||
    variant == "graphs_nullable_null_equal" {
    assert_true(graph_rows[0].contains("\"equal\":true"))
  } else if variant.has_suffix("unequal") {
    assert_true(graph_rows[0].contains("\"equal\":false"))
  } else if variant == "concise_projection" {
    assert_true(graph_rows[0].contains("\"src\":1"))
    assert_true(graph_rows[0].contains("\"dst\":2"))
    assert_true(graph_rows[0].contains("\"id\":1"))
    assert_true(graph_rows[1].contains("\"weight\":20"))
  } else {
    assert_true(graph_rows[0].contains("\"id\":1"))
    assert_true(graph_rows[1].contains("\"node_name\":\"second\""))
  }
  if graph_obligations is Some(obligations) {
    let requirements = @execution.managed_obligations_identities(obligations)
    let published = requirements.filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    })
    assert_eq(published.length(), 1)
    match
      @execution.managed_completed_identity_requirement_status(
        graph,
        published[0],
      ) {
      Some(@execution.EstablishedSourceRetained(contract, cid)) => {
        assert_eq(
          contract,
          @execution.logical_relation_canonical_contract_cid(),
        )
        assert_eq(cid, graph_relation_publication_cid(variant))
      }
      _ => fail("Graph match output did not establish publication identity")
    }
    assert_true(
      @execution.managed_completed_deadline_satisfied(
        graph,
        @execution.BeforePublication,
      ),
    )
  }

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    graph_task + 1,
    [graph],
    [graph_rows],
    graph_task + 1,
    first_live,
    obligations?=graph_publication_obligations(run, publication),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    graph_task + 2,
    [graph],
    [graph_rows],
    graph_task + 2,
    second_live,
    obligations?=graph_publication_obligations(run, publication),
  )
  assert_eq(local_managed_test_rows(first_ops).length(), expected_rows)
  assert_eq(local_managed_test_rows(second_ops).length(), expected_rows)

  first_live.val = false
  @strategy.close_captured_task_output(run, graph_task + 1)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(graph))

  second_live.val = false
  @strategy.close_captured_task_output(run, graph_task + 2)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  graph_live.val = false
  @strategy.close_captured_task_output(run, graph_task)
  (graph_ops.close)()
  assert_false((graph_ops.cleanup_refresh)())
  assert_true((graph_ops.cleanup_refresh)())
  assert_eq(cleanup_attempts.val, 2)
  match other_cleanup.val {
    Some(cleanup) => cleanup()
    None => ()
  }
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

///|
test "standard Host runs bounded Graph relation paths with two consumers" {
  run_standard_host_graph_relation_path("concise_projection")
  run_standard_host_graph_relation_path("split_projection")
  run_standard_host_graph_relation_path("projection", publication=true)
  run_standard_host_graph_relation_path("edge_projection", publication=true)
  run_standard_host_graph_relation_path("normalize")
  run_standard_host_graph_relation_path("normalize_shared", publication=true)
  run_standard_host_graph_relation_path("match_nodes", publication=true)
  run_standard_host_graph_relation_path("match_nodes_literal")
  run_standard_host_graph_relation_path(
    "match_nodes_predicate",
    publication=true,
  )
  run_standard_host_graph_relation_path("match_edges", publication=true)
  run_standard_host_graph_relation_path(
    "match_edges_predicate",
    publication=true,
  )
  run_standard_host_graph_relation_path("graph_bounds", publication=true)
  run_standard_host_graph_relation_path("degree_in")
  run_standard_host_graph_relation_path("degree_out")
  run_standard_host_graph_relation_path("degree_both", publication=true)
  run_standard_host_graph_relation_path("components_weak")
  run_standard_host_graph_relation_path("components_strong")
  run_standard_host_graph_relation_path("reach_out", publication=true)
  run_standard_host_graph_relation_path("graphs_equal", publication=true)
  run_standard_host_graph_relation_path("graphs_equal_reverse")
  run_standard_host_graph_relation_path("graphs_equal_self")
  run_standard_host_graph_relation_path("graphs_nullable_equal")
  run_standard_host_graph_relation_path("graphs_nullable_null_equal")
  run_standard_host_graph_relation_path("graphs_unequal")
  run_standard_host_graph_relation_path("graphs_payload_unequal")
}

///|
test "standard Host traverses a Graph for two consumers" {
  run_standard_host_graph_relation_path("traverse_out", publication=true)
}

///|
test "Graph equality retains a property comparison across bounded resumes" {
  run_standard_host_graph_relation_path(
    "graphs_nullable_equal",
    publication=true,
  )
  run_standard_host_graph_relation_path("graphs_nullable_null_equal")
}

///|
test "standard Host grafts two Graphs before the Relation bridge" {
  run_standard_host_graph_relation_path("graft", publication=true)
}

///|
test "standard Host unions a repeated Graph list before the Relation bridge" {
  run_standard_host_graph_relation_path("union", publication=true)
  run_standard_host_graph_relation_path("union_singleton")
}

///|
test "standard Host subtracts a property-free Graph before projection" {
  run_standard_host_graph_relation_path("subtract", publication=true)
  run_standard_host_graph_relation_path("subtract_exact", publication=true)
}
