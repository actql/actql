///|
fn carrier_graph_source_owner_with_rows(
  rows : String,
  wide? : Bool = false,
  text_id? : Bool = false,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"" +
      (if text_id { "string" } else { "number" }) +
      "\",\"nullable\":false}," +
      "\"src\":{\"type\":\"" +
      (if text_id { "string" } else { "number" }) +
      "\",\"nullable\":false}," +
      "\"dst\":{\"type\":\"" +
      (if text_id { "string" } else { "number" }) +
      "\",\"nullable\":false}," +
      "\"node_name\":{\"type\":\"string\",\"nullable\":false}," +
      (if wide {
        "\"node_label\":{\"type\":\"string\",\"nullable\":false}," +
        "\"node_tag\":{\"type\":\"string\",\"nullable\":false}," +
        "\"edge_note\":{\"type\":\"string\",\"nullable\":false},"
      } else {
        ""
      }) +
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
fn carrier_graph_selector_source_owner(
  rows : String,
  nullable? : Bool = false,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"key\":{\"type\":\"number\"," +
      "\"nullable\":" +
      nullable.to_string() +
      "}},\"rows\":" +
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
fn local_carrier_graph_apply_program() -> String {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"src\":{\"type\":\"number\",\"nullable\":false}," +
    "\"dst\":{\"type\":\"number\",\"nullable\":false}," +
    "\"node_name\":{\"type\":\"string\",\"nullable\":false}," +
    "\"weight\":{\"type\":\"number\",\"nullable\":false}}"
  let graph = "{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":[\"weight\"]}}"
  let right_graph = "{\"nodes\":{\"from\":\"other\",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"other\"," +
    "\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":[\"weight\"]}}"
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{" +
  "\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"values\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":[{" +
  "\"id\":1,\"src\":1,\"dst\":2,\"node_name\":\"first\"," +
  "\"weight\":10},{\"id\":2,\"src\":2,\"dst\":1," +
  "\"node_name\":\"second\",\"weight\":20}]},\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"," +
  "\"src\",\"dst\",\"node_name\",\"weight\"]}}},{" +
  "\"id\":\"other_values\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":[{\"id\":1,\"src\":1," +
  "\"dst\":3,\"node_name\":\"changed\",\"weight\":11},{" +
  "\"id\":3,\"src\":3,\"dst\":1,\"node_name\":\"third\"," +
  "\"weight\":30}]},\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":[\"id\",\"src\",\"dst\"," +
  "\"node_name\",\"weight\"]}}},{\"id\":\"diff\",\"inputs\":{" +
  "\"rows\":{\"result\":{\"stage\":\"values\",\"result\":\"r\"}}," +
  "\"other\":{\"result\":{\"stage\":\"other_values\"," +
  "\"result\":\"r\"}}},\"steps\":[{\"graph\":" +
  graph +
  ",\"as\":\"g\"},{\"graph\":" +
  right_graph +
  ",\"as\":\"right\"},{\"from\":\"g\",\"graph_diff\":{" +
  "\"with\":\"right\"},\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":[\"delta\"]}}},{" +
  "\"id\":\"apply\",\"inputs\":{\"rows\":{\"result\":{" +
  "\"stage\":\"values\",\"result\":\"r\"}},\"changes\":{" +
  "\"result\":{\"stage\":\"diff\",\"result\":\"r\"}}}," +
  "\"steps\":[{\"graph\":" +
  graph +
  ",\"as\":\"base\"},{" +
  "\"from\":\"base\",\"apply_graph_delta\":{\"with\":\"changes\"," +
  "\"field\":\"delta\"},\"as\":\"applied\"},{\"from\":\"applied\"," +
  "\"node_rows\":true,\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":[\"id\",\"node_name\"]}}},{" +
  "\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"apply\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"id\",\"node_name\"],\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"," +
  "\"node_name\"]}}},{\"id\":\"consumer_b\",\"inputs\":{\"x\":{" +
  "\"result\":{\"stage\":\"apply\",\"result\":\"r\"}}}," +
  "\"steps\":[{\"select\":[\"node_name\"],\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[" +
  "\"node_name\"]}}}],\"results\":{\"source\":{\"from\":{" +
  "\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn local_carrier_graph_program(variant? : String = "projection") -> String {
  if variant == "graph_apply_changes" {
    return local_carrier_graph_apply_program()
  }
  let concise = variant == "concise_projection"
  let split = variant == "split_projection"
  let subtract = variant.has_prefix("subtract")
  let subtract_exact = variant == "subtract_exact"
  let subtract_numeric = variant == "subtract_numeric"
  let subtract_properties = subtract_exact || subtract_numeric
  let union_set = variant == "union_set"
  let patterned_multi = variant == "traverse_pattern_multi" ||
    variant.has_prefix("traverse_pattern_multi_paths")
  let typed_traverse = variant.has_prefix("traverse_type") ||
    variant.has_prefix("shortest_type") ||
    patterned_multi
  let subgraph_relation_selector = variant.has_prefix(
    "subgraph_relation_selector",
  )
  let traverse_relation_selector = variant == "traverse_relation_selector" ||
    variant == "traverse_relation_paths"
  let traverse_paths = variant == "traverse_paths" ||
    variant == "traverse_relation_paths" ||
    variant == "traverse_predicate_paths" ||
    variant.has_prefix("traverse_pattern_multi_paths") ||
    variant == "traverse_in_paths" ||
    variant == "traverse_both_paths" ||
    variant == "traverse_zero_paths" ||
    variant == "traverse_type_empty_paths"
  let shortest_relation_selector = variant == "shortest_relation_selector"
  let relation_selector = subgraph_relation_selector ||
    traverse_relation_selector ||
    shortest_relation_selector
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"src\":{\"type\":\"number\",\"nullable\":false}," +
    "\"dst\":{\"type\":\"number\",\"nullable\":false}," +
    (if typed_traverse {
      "\"edge_type\":{\"type\":\"string\",\"nullable\":false},"
    } else {
      ""
    }) +
    (if union_set {
      "\"tags\":{\"type\":\"array\",\"nullable\":false," +
      "\"items\":{\"type\":\"string\",\"nullable\":true}," +
      "\"max_items\":10}}"
    } else if subtract && !subtract_properties {
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
  let rows = if union_set {
    "[{\"id\":1,\"src\":1,\"dst\":1," + "\"tags\":[\"b\",\"a\"]}]"
  } else if patterned_multi {
    "[{\"id\":1,\"src\":1,\"dst\":2,\"edge_type\":\"owns\"," +
    "\"node_name\":\"first\",\"weight\":10},{\"id\":2," +
    "\"src\":2,\"dst\":3,\"edge_type\":\"blocks\"," +
    "\"node_name\":\"second\",\"weight\":20},{\"id\":3," +
    "\"src\":3,\"dst\":3,\"edge_type\":\"other\"," +
    "\"node_name\":\"third\",\"weight\":30}]"
  } else if typed_traverse {
    "[{\"id\":1,\"src\":1,\"dst\":2,\"edge_type\":\"owns\"," +
    "\"node_name\":\"first\",\"weight\":10},{\"id\":2," +
    "\"src\":2,\"dst\":1,\"edge_type\":\"blocks\"," +
    "\"node_name\":\"second\",\"weight\":20}]"
  } else if subtract && !subtract_properties {
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
  let graph_diff = variant == "graph_diff" || variant == "graph_diff_changes"
  let graph_diff_changes = variant == "graph_diff_changes"
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
  } else if shortest_relation_selector {
    "\"from\":\"g\",\"shortest_path\":{\"source\":{\"from\":" +
    "\"selected\",\"id\":\"key\"},\"target\":{\"from\":" +
    "\"selected\",\"id\":\"key\"},\"selection\":\"each_pair\"," +
    "\"direction\":\"out\",\"max_hops\":2},\"as\":\"out\""
  } else if variant == "shortest_predicate" {
    "\"from\":\"g\",\"shortest_path\":{\"source\":{\"where\":" +
    "\"true\"},\"target\":{\"where\":\"node_name = 'second'\"}," +
    "\"selection\":\"each_pair\",\"direction\":\"out\"," +
    "\"max_hops\":2},\"as\":\"out\""
  } else if variant == "shortest_ids" {
    "\"from\":\"g\",\"shortest_path\":{\"source\":{\"ids\":[2,1,2]}," +
    "\"target\":{\"ids\":[2,1]},\"selection\":\"each_pair\"," +
    "\"direction\":\"out\",\"max_hops\":2},\"as\":\"out\""
  } else if variant == "shortest_nearest_per_source" {
    "\"from\":\"g\",\"shortest_path\":{\"source\":{\"ids\":[2,1]}," +
    "\"target\":{\"ids\":[2]},\"selection\":\"nearest_per_source\"," +
    "\"direction\":\"out\",\"max_hops\":2},\"as\":\"out\""
  } else if variant == "shortest_nearest_pair" {
    "\"from\":\"g\",\"shortest_path\":{\"source\":{\"ids\":[2,1]}," +
    "\"target\":{\"ids\":[2,1]},\"selection\":\"nearest_pair\"," +
    "\"direction\":\"out\",\"max_hops\":2},\"as\":\"out\""
  } else if variant.has_prefix("shortest_") {
    "\"from\":\"g\",\"shortest_path\":{\"source\":1," +
    "\"target\":" +
    (if variant == "shortest_zero" { "1" } else { "2" }) +
    ",\"direction\":\"" +
    (if variant == "shortest_in" {
      "in"
    } else if variant == "shortest_both" {
      "both"
    } else {
      "out"
    }) +
    "\",\"max_hops\":2" +
    (if variant == "shortest_weighted" { ",\"weight\":\"weight\"" } else { "" }) +
    (if variant == "shortest_type_empty" {
      ",\"edge_types\":[]"
    } else if variant == "shortest_types_match" {
      ",\"edge_types\":[\"missing\",\"owns\"]"
    } else if variant == "shortest_type_miss" {
      ",\"edge_types\":[\"blocks\"]"
    } else if variant == "shortest_type_match" {
      ",\"edge_types\":[\"owns\"]"
    } else {
      ""
    }) +
    "}," +
    "\"as\":\"out\""
  } else if variant.has_prefix("traverse_") {
    "\"from\":\"g\",\"traverse\":{\"start\":{" +
    (if variant == "traverse_predicate" ||
      variant == "traverse_predicate_paths" ||
      variant == "traverse_pattern_all_predicates" {
      "\"where\":" +
      (if variant == "traverse_pattern_all_predicates" {
        "\"node_name = 'second'\""
      } else {
        "\"true\""
      })
    } else if traverse_relation_selector {
      "\"from\":\"selected\",\"id\":\"key\""
    } else {
      "\"ids\":[" +
      (if variant == "traverse_ids" {
        "2,1,2"
      } else if variant.has_prefix("traverse_pattern_") &&
        !patterned_multi &&
        variant != "traverse_pattern_one" {
        "2"
      } else {
        "1"
      }) +
      "]"
    }) +
    "}," +
    (if variant.has_prefix("traverse_pattern_") {
      if patterned_multi {
        "\"hops\":[{\"direction\":\"out\"," +
        "\"edge_types\":[\"owns\"]," +
        "\"edge_where\":\"weight > " +
        (if variant == "traverse_pattern_multi_paths_empty" {
          "100"
        } else {
          "5"
        }) +
        "\"," +
        "\"node_where\":\"node_name = 'second'\"" +
        "},{\"direction\":\"out\"," +
        "\"edge_types\":[\"blocks\"]," +
        "\"edge_where\":\"weight > 15\"," +
        "\"node_where\":\"node_name = 'third'\"" +
        "}],"
      } else {
        "\"hops\":[{\"direction\":\"out\"" +
        (if variant == "traverse_pattern_predicate" ||
          variant == "traverse_pattern_all_predicates" ||
          variant == "traverse_pattern_edge_predicate" {
          ",\"edge_where\":\"weight > 10\""
        } else if variant == "traverse_pattern_predicate_empty" {
          ",\"edge_where\":\"weight > 100\""
        } else {
          ""
        }) +
        (if variant == "traverse_pattern_predicate" ||
          variant == "traverse_pattern_all_predicates" ||
          variant == "traverse_pattern_node_predicate" {
          ",\"node_where\":\"node_name = 'first'\""
        } else {
          ""
        }) +
        "}],"
      }
    } else {
      "\"direction\":\"" +
      (if variant == "traverse_in" || variant == "traverse_in_paths" {
        "in"
      } else if variant == "traverse_both" || variant == "traverse_both_paths" {
        "both"
      } else {
        "out"
      }) +
      "\"," +
      (if typed_traverse {
        if variant == "traverse_type_empty" ||
          variant == "traverse_type_empty_paths" {
          "\"edge_types\":[],"
        } else if variant.has_prefix("traverse_types_") {
          "\"edge_types\":[\"missing\",\"" +
          (if variant == "traverse_types_match" { "owns" } else { "other" }) +
          "\"],"
        } else {
          "\"edge_types\":[\"" +
          (if variant == "traverse_type_miss" { "blocks" } else { "owns" }) +
          "\"],"
        }
      } else {
        ""
      }) +
      "\"min_hops\":" +
      (if variant == "traverse_zero_paths" { "0" } else { "1" }) +
      ",\"max_hops\":" +
      (if variant == "traverse_zero_paths" { "1" } else { "2" }) +
      ","
    }) +
    (if traverse_paths {
      "\"max_output_rows\":" +
      (if traverse_relation_selector { "4" } else { "2" }) +
      ","
    } else {
      ""
    }) +
    "\"emit\":\"" +
    (if traverse_paths { "paths" } else { "nodes" }) +
    "\"},\"as\":\"out\""
  } else if variant == "normalize_shared" {
    "\"from\":\"g\",\"normalize_graph\":true,\"as\":\"normalized\"},{" +
    "\"from\":\"normalized\",\"normalize_graph\":true," +
    "\"as\":\"same_carrier\"},{" +
    "\"from\":\"normalized\",\"node_rows\":true,\"as\":\"out\""
  } else if variant == "normalize_filter" ||
    variant == "normalize_filter_false" ||
    variant == "normalize_select" ||
    variant == "normalize_derive" ||
    variant == "normalize_take" ||
    variant == "normalize_sort" ||
    variant == "normalize_assert" ||
    variant == "normalize_unique" {
    "\"from\":\"g\",\"normalize_graph\":true,\"as\":\"normalized\"},{" +
    "\"from\":\"normalized\",\"node_rows\":true," +
    "\"as\":\"projected\"},{" +
    "\"from\":\"projected\"," +
    (if variant == "normalize_select" {
      "\"select\":[\"id\",\"node_name\"]"
    } else if variant == "normalize_derive" {
      "\"derive\":{\"copy\":\"id\"}"
    } else if variant == "normalize_take" {
      "\"take\":1"
    } else if variant == "normalize_sort" {
      "\"sort\":[{\"id\":\"desc\"}]"
    } else if variant == "normalize_assert" {
      "\"assert_rows\":{\"where\":\"id > 0\"}"
    } else if variant == "normalize_unique" {
      "\"assert_rows\":{\"unique_by\":[\"id\"]}"
    } else if variant == "normalize_filter_false" {
      "\"filter\":\"false\""
    } else {
      "\"filter\":\"true\""
    }) +
    ",\"as\":\"out\""
  } else if variant == "edge_projection_filter" {
    "\"from\":\"g\",\"normalize_graph\":true,\"as\":\"normalized\"},{" +
    "\"from\":\"normalized\",\"edge_rows\":true," +
    "\"as\":\"projected\"},{" +
    "\"from\":\"projected\",\"filter\":\"true\",\"as\":\"out\""
  } else if variant == "normalize" {
    "\"from\":\"g\",\"normalize_graph\":true,\"as\":\"normalized\"},{" +
    "\"from\":\"normalized\",\"node_rows\":true,\"as\":\"out\""
  } else if variant == "subgraph_ids" ||
    variant == "subgraph_shared" ||
    variant == "subgraph_filter" {
    "\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[2]}}," +
    "\"as\":\"selected\"},{" +
    (if variant == "subgraph_shared" {
      "\"from\":\"selected\",\"normalize_graph\":true," +
      "\"as\":\"same_carrier\"},{"
    } else {
      ""
    }) +
    "\"from\":\"selected\"," +
    "\"node_rows\":true,\"as\":" +
    (if variant == "subgraph_filter" {
      "\"projected\"},{\"from\":\"projected\"," +
      "\"filter\":\"true\",\"as\":\"out\""
    } else {
      "\"out\""
    })
  } else if variant == "subgraph_edges_false" {
    "\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[1,2]}," +
    "\"edges\":\"false\"},\"as\":\"selected\"},{" +
    "\"from\":\"selected\",\"edge_rows\":true,\"as\":\"out\""
  } else if variant == "subgraph_node_predicate" {
    "\"from\":\"g\",\"subgraph\":{\"nodes\":{\"where\":" +
    "\"node_name = 'second'\"}},\"as\":\"selected\"},{" +
    "\"from\":\"selected\",\"node_rows\":true,\"as\":\"out\""
  } else if subgraph_relation_selector {
    "\"from\":\"g\",\"subgraph\":{\"nodes\":{\"from\":" +
    "\"selected\",\"id\":\"key\"}},\"as\":\"selected_graph\"},{" +
    "\"from\":\"selected_graph\",\"node_rows\":true,\"as\":\"out\""
  } else if variant == "subgraph_edge_predicate" {
    "\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[1,2]}," +
    "\"edges\":\"weight > 10\"},\"as\":\"selected\"},{" +
    "\"from\":\"selected\",\"edge_rows\":true,\"as\":\"out\""
  } else if variant == "graft" {
    "\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":" +
    "\"rows\",\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":[\"weight\"]}},\"as\":\"right_graph\"},{" +
    "\"from\":\"g\",\"graft_graph\":{\"with\":\"right_graph\"}," +
    "\"as\":\"grafted\"},{\"from\":\"grafted\"," +
    "\"node_rows\":true,\"as\":\"out\""
  } else if variant == "mean" {
    "\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":" +
    "\"rows\",\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":[\"weight\"]}},\"as\":\"right_graph\"},{" +
    "\"mean_graphs\":{\"with\":[\"right_graph\",\"g\"," +
    "\"right_graph\"],\"weights\":[1,2,3]," +
    "\"support\":{\"nodes\":1,\"edges\":1}," +
    "\"properties\":{\"nodes\":{\"node_name\":\"exact_equal\"}," +
    "\"edges\":{\"weight\":{\"mean\":{" +
    "\"missing\":\"exclude\",\"nulls\":\"fail\"}}}}}," +
    "\"as\":\"averaged\"},{\"from\":\"averaged\"," +
    "\"node_rows\":true,\"as\":\"out\""
  } else if variant == "union" ||
    variant == "union_singleton" ||
    variant == "union_numeric" ||
    union_set {
    "\"graph\":{\"nodes\":{\"from\":" +
    (if union_set { "\"other\"" } else { "\"rows\"" }) +
    ",\"id\":\"id\"," +
    "\"fields\":" +
    (if union_set { "[\"tags\"]" } else { "[\"node_name\"]" }) +
    "},\"edges\":{\"from\":" +
    (if union_set { "\"other\"" } else { "\"rows\"" }) +
    "," +
    "\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":" +
    (if union_set { "[]" } else { "[\"weight\"]" }) +
    "}},\"as\":\"right_graph\"},{" +
    "\"from\":\"g\",\"union_graphs\":{\"with\":" +
    (if variant == "union_singleton" || variant == "union_numeric" || union_set {
      "\"right_graph\""
    } else {
      "[\"right_graph\",\"g\",\"right_graph\"]"
    }) +
    (if variant == "union_numeric" {
      ",\"merge\":{\"edge_properties\":{\"weight\":" + "\"number_sum\"}}"
    } else if union_set {
      ",\"merge\":{\"node_properties\":{\"tags\":\"set_union\"}}"
    } else {
      ""
    }) +
    "}," +
    "\"as\":\"united\"},{\"from\":\"united\"," +
    (if variant == "union_numeric" {
      "\"edge_rows\":true,\"as\":\"out\""
    } else {
      "\"node_rows\":true,\"as\":\"out\""
    })
  } else if subtract {
    "\"graph\":{\"nodes\":{\"from\":\"other\",\"id\":\"id\"," +
    "\"fields\":" +
    (if subtract_properties { "[\"node_name\"]" } else { "[]" }) +
    "},\"edges\":{\"from\":\"other\"," +
    "\"source\":\"src\",\"target\":\"dst\",\"fields\":" +
    (if subtract_properties { "[\"weight\"]" } else { "[]" }) +
    "}}," +
    "\"as\":\"right_graph\"},{" +
    "\"from\":\"g\",\"subtract_graphs\":{\"with\":\"right_graph\"" +
    (if subtract_exact {
      ",\"merge\":{\"node_properties\":{\"node_name\":\"exact_equal\"}," +
      "\"edge_properties\":{\"weight\":\"exact_equal\"}}"
    } else if subtract_numeric {
      ",\"merge\":{\"node_properties\":{\"node_name\":\"exact_equal\"}," +
      "\"edge_properties\":{\"weight\":\"number_sum\"}}"
    } else {
      ""
    }) +
    "}," +
    "\"as\":\"subtracted\"},{\"from\":\"subtracted\"," +
    (if subtract_numeric {
      "\"edge_rows\":true,\"as\":\"out\""
    } else {
      "\"node_rows\":true,\"as\":\"out\""
    })
  } else if graph_diff {
    "\"graph\":{\"nodes\":{\"from\":" +
    (if graph_diff_changes { "\"other\"" } else { "\"rows\"" }) +
    ",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":" +
    (if graph_diff_changes { "\"other\"" } else { "\"rows\"" }) +
    "," +
    "\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":[\"weight\"]}},\"as\":\"right_graph\"},{" +
    "\"from\":\"g\",\"graph_diff\":{\"with\":\"right_graph\"}," +
    "\"as\":\"out\""
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
  } else if variant == "edge_projection" || variant == "edge_projection_filter" {
    "\"from\":\"g\",\"edge_rows\":true,\"as\":\"out\""
  } else {
    "\"node_rows\":true,\"as\":\"out\""
  }
  let result_fields = if union_set {
    "\"id\",\"tags\""
  } else if subtract && !subtract_properties {
    "\"id\""
  } else if subtract_numeric {
    "\"src\",\"dst\",\"weight\""
  } else if variant == "normalize_derive" {
    "\"id\",\"node_name\",\"copy\""
  } else if concise {
    "\"src\",\"dst\",\"id\",\"weight\""
  } else if variant.has_prefix("match_edges") ||
    variant == "edge_projection" ||
    variant == "edge_projection_filter" ||
    variant == "union_numeric" ||
    variant == "subgraph_edges_false" ||
    variant == "subgraph_edge_predicate" {
    "\"src\",\"dst\",\"weight\""
  } else if variant == "graph_bounds" {
    "\"kind\",\"node_id\",\"actual\",\"max\""
  } else if variant.has_prefix("degree_") {
    "\"node\",\"degree\""
  } else if variant.has_prefix("components_") {
    "\"node_id\",\"component_id\",\"component_size\""
  } else if variant.has_prefix("shortest_") {
    "\"source_id\",\"target_id\",\"total_cost\",\"hop_count\"," +
    "\"node_ids\",\"edge_ids\""
  } else if traverse_paths {
    "\"start_id\",\"end_id\",\"hop_count\",\"node_ids\",\"edge_ids\""
  } else if variant.has_prefix("reach_") || variant.has_prefix("traverse_") {
    "\"start_id\",\"node_id\",\"depth\""
  } else if graph_diff {
    "\"delta\""
  } else if graph_equality {
    "\"equal\""
  } else {
    "\"id\",\"node_name\""
  }
  let first_fields = result_fields
  let second_fields = if union_set {
    "\"tags\""
  } else if subtract && !subtract_properties {
    "\"id\""
  } else if subtract_numeric {
    "\"weight\",\"src\""
  } else if variant == "normalize_derive" {
    "\"copy\",\"id\""
  } else if concise {
    "\"weight\",\"src\""
  } else if variant.has_prefix("match_edges") ||
    variant == "edge_projection" ||
    variant == "edge_projection_filter" ||
    variant == "union_numeric" ||
    variant == "subgraph_edges_false" ||
    variant == "subgraph_edge_predicate" {
    "\"weight\",\"src\""
  } else if variant == "graph_bounds" {
    "\"kind\",\"node_id\""
  } else if variant.has_prefix("degree_") {
    "\"degree\""
  } else if variant.has_prefix("components_") {
    "\"component_id\",\"component_size\""
  } else if variant.has_prefix("shortest_") {
    "\"source_id\",\"target_id\",\"hop_count\""
  } else if traverse_paths {
    "\"start_id\",\"end_id\",\"hop_count\""
  } else if variant.has_prefix("reach_") || variant.has_prefix("traverse_") {
    "\"node_id\",\"depth\""
  } else if graph_diff {
    "\"delta\""
  } else if graph_equality {
    "\"equal\""
  } else {
    "\"node_name\""
  }
  let other_stage = if graph_diff_changes {
    "{\"id\":\"other_values\",\"inputs\":{},\"steps\":[{" +
    "\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"id\":1,\"src\":1,\"dst\":3," +
    "\"node_name\":\"changed\",\"weight\":11},{\"id\":3," +
    "\"src\":3,\"dst\":1,\"node_name\":\"third\"," +
    "\"weight\":30}]},\"as\":\"out\"}],\"results\":{\"r\":{" +
    "\"from\":\"out\",\"fields\":[\"id\",\"src\",\"dst\"," +
    "\"node_name\",\"weight\"]}}},"
  } else if subtract || union_set {
    "{\"id\":\"other_values\",\"inputs\":{},\"steps\":[{" +
    "\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    (if union_set {
      "[{\"id\":1,\"src\":1,\"dst\":1," + "\"tags\":[\"c\",null,\"b\"]}]"
    } else if subtract_numeric {
      "[{\"id\":1,\"src\":1,\"dst\":2," +
      "\"node_name\":\"first\",\"weight\":1},{\"id\":2," +
      "\"src\":2,\"dst\":1,\"node_name\":\"second\"," +
      "\"weight\":5}]"
    } else {
      "[{\"id\":2,\"src\":2,\"dst\":2," +
      (if subtract_properties {
        "\"node_name\":\"second\",\"weight\":20"
      } else {
        "\"marker\":0"
      }) +
      "}]"
    }) +
    "},\"as\":\"out\"}],\"results\":{\"r\":{" +
    "\"from\":\"out\",\"fields\":[\"id\",\"src\",\"dst\"," +
    (if union_set {
      "\"tags\""
    } else if subtract_properties {
      "\"node_name\",\"weight\""
    } else {
      "\"marker\""
    }) +
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
  let selector_stage = if relation_selector {
    "{\"id\":\"selector_values\",\"inputs\":{},\"steps\":[{" +
    "\"values\":{\"schema\":{\"key\":{\"type\":\"number\"," +
    "\"nullable\":" +
    (if variant == "subgraph_relation_selector_nullable" {
      "true"
    } else {
      "false"
    }) +
    "}},\"rows\":" +
    (if traverse_relation_selector || shortest_relation_selector {
      "[{\"key\":2},{\"key\":1},{\"key\":2}]"
    } else {
      "[{\"key\":2},{\"key\":2}]"
    }) +
    "}" +
    ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
    "\"fields\":[\"key\"]}}},"
  } else {
    ""
  }
  let graph_inputs = if graph_diff_changes {
    "\"rows\":{\"result\":{\"stage\":\"values\",\"result\":\"r\"}}," +
    "\"other\":{\"result\":{\"stage\":\"other_values\"," +
    "\"result\":\"r\"}}"
  } else if subtract || union_set {
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
  } else if relation_selector {
    "\"rows\":{\"result\":{\"stage\":\"values\",\"result\":\"r\"}}," +
    "\"selected\":{\"result\":{\"stage\":\"selector_values\"," +
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
  (if union_set {
    "\"tags\""
  } else if subtract && !subtract_properties {
    "\"marker\""
  } else if typed_traverse {
    "\"edge_type\",\"node_name\",\"weight\""
  } else {
    "\"node_name\",\"weight\""
  }) +
  "]}}}," +
  other_stage +
  selector_stage +
  "{\"id\":\"graph\",\"inputs\":{" +
  graph_inputs +
  "},\"steps\":[{" +
  (if concise {
    "\"from\":\"rows\",\"graph\":{\"source\":\"src\"," +
    "\"target\":\"dst\"},\"as\":\"g\"},{"
  } else if subtract {
    "\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":" +
    (if subtract_properties { "[\"node_name\"]" } else { "[]" }) +
    "},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\",\"fields\":" +
    (if subtract_properties { "[\"weight\"]" } else { "[]" }) +
    "}}," +
    "\"as\":\"g\"},{"
  } else if union_set {
    "\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[\"tags\"]},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\",\"fields\":[]}}," +
    "\"as\":\"g\"},{"
  } else if typed_traverse {
    "\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\"," +
    "\"label\":\"edge_type\",\"fields\":[\"weight\"]}}," +
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
fn carrier_selected_match_owner(
  graph_owner : @lower.BoundPrepared,
  nodes : Bool,
) -> @lower.BoundPrepared {
  let match_step = if nodes {
    "{\"from\":\"g\",\"match_nodes\":{\"ids\":[1]," +
    "\"fields\":[\"id\",\"node_name\"]},\"as\":\"matched\"}"
  } else {
    "{\"from\":\"g\",\"match_edges\":{\"types\":[\"missing\"]," +
    "\"fields\":[\"src\",\"dst\",\"rel\",\"weight\"]},\"as\":\"matched\"}"
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[" +
      match_step +
      "," +
      "{\"from\":\"matched\",\"filter\":\"true\",\"as\":\"out\"}]",
    ),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(graph_owner)),
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
fn carrier_match_graph_material(
  graph_owner : @lower.BoundPrepared,
  source_owner : @lower.BoundPrepared,
) -> @carrier_runtime.Material raise {
  let source = carrier_events_source_output(source_owner)
  let external = @execution.prepare_producer_read(
    graph_owner,
    @execution.bind_completed_input(graph_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  @graphs.completed_material(graph).unwrap()
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
fn carrier_graph_labeled_source_owner_with_rows(
  rows : String,
  text_id? : Bool = false,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"" +
      (if text_id { "string" } else { "number" }) +
      "\",\"nullable\":false},\"src\":{\"type\":\"" +
      (if text_id { "string" } else { "number" }) +
      "\",\"nullable\":false},\"dst\":{\"type\":\"" +
      (if text_id { "string" } else { "number" }) +
      "\",\"nullable\":false},\"rel\":{\"type\":\"string\"," +
      "\"nullable\":false},\"weight\":{\"type\":\"number\"," +
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
fn carrier_graph_labeled_source_owner() -> @lower.BoundPrepared {
  carrier_graph_labeled_source_owner_with_rows(
    "[{\"id\":2,\"src\":2,\"dst\":1,\"rel\":\"controls\"," +
    "\"weight\":20},{\"id\":1,\"src\":1,\"dst\":3," +
    "\"rel\":\"owns\",\"weight\":30},{\"id\":3,\"src\":1," +
    "\"dst\":2,\"rel\":\"owns\",\"weight\":10}]",
  )
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
fn carrier_graph_traverse_owner(
  source : @lower.BoundPrepared,
  minimum : Int,
  maximum : Int,
  emission? : String = "nodes",
  starts? : String = "1",
  predicate? : String = "",
  max_output_rows? : Int = 4,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"traverse\":{\"start\":{" +
      (if predicate == "" {
        "\"ids\":[" + starts + "]"
      } else {
        "\"where\":\"" + predicate + "\""
      }) +
      "}," +
      "\"direction\":\"out\",\"min_hops\":" +
      minimum.to_string() +
      ",\"max_hops\":" +
      maximum.to_string() +
      ",\"emit\":\"" +
      emission +
      "\",\"max_output_rows\":" +
      max_output_rows.to_string() +
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
fn carrier_graph_two_path_traversals_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"}," +
      "{\"from\":\"graph\",\"traverse\":{\"start\":{\"ids\":[1]}," +
      "\"direction\":\"out\",\"min_hops\":1,\"max_hops\":2," +
      "\"emit\":\"paths\",\"max_output_rows\":4},\"as\":\"first\"}," +
      "{\"from\":\"graph\",\"traverse\":{\"start\":{\"ids\":[1]}," +
      "\"direction\":\"out\",\"min_hops\":1,\"max_hops\":2," +
      "\"emit\":\"paths\",\"max_output_rows\":4}}]",
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
fn carrier_graph_predicate_pattern_owner(
  source : @lower.BoundPrepared,
  emission? : String = "nodes",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"traverse\":{\"start\":{\"where\":" +
      "\"node_name = 'second'\"},\"hops\":[{\"direction\":\"out\"," +
      "\"edge_where\":\"weight > 10\",\"node_where\":" +
      "\"node_name = 'first'\"}],\"emit\":\"" +
      emission +
      "\"," +
      "\"max_output_rows\":4}}]",
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
fn carrier_graph_relation_traverse_owner(
  source : @lower.BoundPrepared,
  selector : @lower.BoundPrepared,
  emission? : String = "nodes",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"traverse\":{\"start\":{" +
      "\"from\":\"selected\",\"id\":\"key\"}," +
      "\"direction\":\"out\",\"min_hops\":1,\"max_hops\":2," +
      "\"emit\":\"" +
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
      (
        "selected",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(selector)),
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
          @local_bridge.GraphControlWorkLimit => abort("graph control work")
          @local_bridge.GraphRelationOutput(_) => abort("graph relation output")
          @local_bridge.GraphCompletion(_) => abort("graph completion")
          @local_bridge.GraphExecution(_) => abort("graph execution")
          @local_bridge.GraphSnapshot(_) => abort("graph snapshot")
          @local_bridge.GraphSnapshotOutput(_) => abort("graph snapshot output")
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
fn finish_traverse(
  execution : @local_sga.TraverseExecution,
  quantum? : Int = 1,
  spent_work? : Ref[Int64]? = None,
) -> Result[@execution.CompletedOutput, @local_sga.TraverseIssue] {
  while true {
    let poll = match @local_sga.advance_traverse(execution, quantum) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      @local_sga.TraverseContinue(..) => ()
      @local_sga.TraverseComplete(output, work~, ..) => {
        if spent_work is Some(value) {
          value.val = work
        }
        return Ok(output)
      }
      @local_sga.TraverseFailed(issue, work~, ..) => {
        if spent_work is Some(value) {
          value.val = work
        }
        return Err(issue)
      }
      @local_sga.TraverseStopped(_, ..) =>
        return Err(
          @local_sga.TraversePathIssue(
            @local_sga.TraversePathsExecutionIssue(@bounded.Terminal),
          ),
        )
    }
  }
  Err(
    @local_sga.TraversePathIssue(
      @local_sga.TraversePathsExecutionIssue(@bounded.Terminal),
    ),
  )
}

///|
fn match_nodes_predicate_output(
  source_owner : @lower.BoundPrepared,
  predicate : String,
  workspace? : Int = 8,
  check_workspace_boundary? : Bool = false,
  check_work_boundary? : Bool = false,
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
  if check_work_boundary {
    let start = fn(work) raise {
      @local_sga.start_match_nodes(
        @bounded.control(),
        task_test_completion(owner),
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
        control_work_limit=Some(work),
      ).unwrap()
    }
    // Two scratch cells, four predicate bindings, twelve predicate steps,
    // two output fields, one row commit, and one completion cost 22 units.
    let exact = start(22)
    let mut done = false
    for _ in 0..<23 {
      if !done {
        match @local_sga.advance_match_nodes(exact, 1).unwrap() {
          @local_sga.MatchNodesComplete(_, work~, ..) => {
            assert_eq(work, 22L)
            done = true
          }
          @local_sga.MatchNodesContinue(..) => ()
          _ => fail("exact predicate node work failed")
        }
      }
    }
    assert_true(done)
    assert_eq(@local_sga.cleanup_match_nodes(exact), Ok(true))
    let short = start(21)
    let mut failed = false
    for _ in 0..<23 {
      if !failed {
        match @local_sga.advance_match_nodes(short, 1).unwrap() {
          @local_sga.MatchNodesContinue(..) => ()
          @local_sga.MatchNodesFailed(@local_sga.MatchNodesWorkLimit, ..) =>
            failed = true
          _ => fail("one-short predicate node work accepted")
        }
      }
    }
    assert_true(failed)
    assert_true(@local_sga.match_nodes_cleanup_pending(short))
    assert_eq(@local_sga.cleanup_match_nodes(short), Ok(true))
  }
  if check_workspace_boundary {
    let short = @local_sga.start_match_nodes(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      input,
      2,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace - 1,
      1000,
      1000,
      [external],
    ).unwrap()
    assert_true(
      finish_match_nodes(short)
      is Err(@local_sga.MatchNodesPredicate(@execution.WorkspaceLimit)),
    )
    assert_eq(@local_sga.cleanup_match_nodes(short), Ok(true))
    assert_true(@graphs.producer_read_available(input))
  }
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
    check_workspace_boundary=true,
    check_work_boundary=true,
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
test "node identity sort yields during a long text comparison" {
  let prefix = "x".repeat(160)
  let first = prefix + "a"
  let second = prefix + "b"
  let rows = "[{\"id\":\"" +
    second +
    "\",\"src\":\"" +
    second +
    "\",\"dst\":\"" +
    second +
    "\",\"node_name\":\"second\"," +
    "\"weight\":1},{\"id\":\"" +
    first +
    "\",\"src\":\"" +
    first +
    "\",\"dst\":\"" +
    first +
    "\",\"node_name\":\"first\"," +
    "\"weight\":2}]"
  let source_owner = carrier_graph_source_owner_with_rows(rows, text_id=true)
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_match_owner(
    source_owner,
    "[\"" + second + "\",\"" + first + "\"]",
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
  let control = @bounded.control()
  let execution = @local_sga.start_match_nodes(
    control,
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
  for _ in 0..<60 {
    assert_true(
      @local_sga.advance_match_nodes(execution, 1).unwrap()
      is @local_sga.MatchNodesContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_match_nodes(execution, 1).unwrap()
    is @local_sga.MatchNodesStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_match_nodes(execution), Ok(true))
  assert_true(@graphs.producer_read_available(input))
  let completed = @local_sga.start_match_nodes(
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
  let output = finish_match_nodes(completed).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Text(id)) && id == first,
  )
  assert_true(
    @execution.completed_cell(output, 1, 0) is Some(Text(id)) && id == second,
  )
  assert_eq(@local_sga.cleanup_match_nodes(completed), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(source))
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
  assert_eq(@local_sga.match_nodes_scratch_slots(execution), 0)
  assert_true(
    @local_sga.advance_match_nodes(execution, 1).unwrap()
    is @local_sga.MatchNodesContinue(progress=1L, work=1L),
  )
  assert_eq(@local_sga.match_nodes_scratch_slots(execution), 1)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_match_nodes(execution, 1).unwrap()
    is @local_sga.MatchNodesStopped(_, progress=1L, work=1L),
  )
  assert_true(@local_sga.match_nodes_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_match_nodes(execution), Ok(true))
  assert_eq(@local_sga.match_nodes_scratch_slots(execution), 0)
  assert_false(@local_sga.match_nodes_cleanup_pending(execution))
  assert_true(@execution.producer_read_available(external))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "node identity match admits exact work and workspace and rejects one short" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_match_owner(source_owner, "[1]")
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
  let start = fn(work, workspace) raise {
    @local_sga.start_match_nodes(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      input,
      1,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [external],
      control_work_limit=Some(work),
    )
  }
  // One identity needs two sort slots and two output-name slots. Work adds
  // scratch, identity, two fields, commit, and finish: four slots, six steps.
  assert_true(start(6, 3) is Err(@local_sga.MatchNodesWorkspaceLimit))
  let exact = start(6, 4).unwrap()
  let mut complete = false
  for _ in 0..<7 {
    if !complete {
      match @local_sga.advance_match_nodes(exact, 1).unwrap() {
        @local_sga.MatchNodesContinue(work~, ..) => assert_true(work <= 6L)
        @local_sga.MatchNodesComplete(output, work~, ..) => {
          assert_eq(work, 6L)
          assert_eq(@execution.completed_row_count(output), 1)
          complete = true
        }
        _ => fail("exact node match control work failed")
      }
    }
  }
  assert_true(complete)
  assert_eq(@local_sga.cleanup_match_nodes(exact), Ok(true))
  let short = start(5, 4).unwrap()
  let mut failed = false
  for _ in 0..<7 {
    if !failed {
      match @local_sga.advance_match_nodes(short, 1).unwrap() {
        @local_sga.MatchNodesContinue(..) => ()
        @local_sga.MatchNodesFailed(@local_sga.MatchNodesWorkLimit, ..) =>
          failed = true
        _ => fail("one-short node match control work accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(@local_sga.match_nodes_cleanup_pending(short))
  assert_eq(@local_sga.cleanup_match_nodes(short), Ok(true))
  assert_true(@graphs.producer_read_available(input))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "selected node match view admits exact limits and cleans cancellation" {
  let source_owner = carrier_graph_source_owner()
  let graph_owner = carrier_graph_match_owner(source_owner, "[1]")
  let owner = carrier_selected_match_owner(graph_owner, true)
  let material = carrier_match_graph_material(graph_owner, source_owner)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let sequence = @execution.generated_prepared_sequence(generated)
  let control = @bounded.control()
  let start = fn(work, workspace) {
    let view = @carrier_runtime.material_prepare_view(
      material, owner, 0, graph_owner,
    ).unwrap()
    @local_sga.start_match_nodes_view(
      control,
      @execution.generated_completion_preparation(generated),
      sequence,
      0,
      view,
      1,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [],
      control_work_limit=Some(work),
    )
  }
  assert_true(start(6, 3) is Err(@local_sga.MatchNodesWorkspaceLimit))
  let exact = start(6, 4).unwrap()
  let mut complete = false
  for _ in 0..<7 {
    if !complete {
      match @local_sga.advance_match_nodes(exact, 1).unwrap() {
        @local_sga.MatchNodesContinue(work~, ..) => assert_true(work <= 6L)
        @local_sga.MatchNodesComplete(output, work~, ..) => {
          assert_eq(work, 6L)
          assert_eq(@execution.completed_row_count(output), 1)
          complete = true
        }
        _ => fail("selected node match exact limit failed")
      }
    }
  }
  assert_true(complete)
  assert_eq(@local_sga.cleanup_match_nodes(exact), Ok(true))
  let short = start(5, 4).unwrap()
  let mut failed = false
  for _ in 0..<7 {
    if !failed {
      match @local_sga.advance_match_nodes(short, 1).unwrap() {
        @local_sga.MatchNodesContinue(..) => ()
        @local_sga.MatchNodesFailed(@local_sga.MatchNodesWorkLimit, ..) =>
          failed = true
        _ => fail("selected node match one-short limit accepted")
      }
    }
  }
  assert_true(failed)
  assert_eq(@local_sga.cleanup_match_nodes(short), Ok(true))
  let cancelled = start(6, 4).unwrap()
  match @local_sga.advance_match_nodes(cancelled, 1).unwrap() {
    @local_sga.MatchNodesContinue(work~, ..) => assert_true(work > 0L)
    _ => fail("selected node match did not advance before cancellation")
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_match_nodes(cancelled, 1).unwrap()
    is @local_sga.MatchNodesStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_match_nodes(cancelled), Ok(true))
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
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
    12,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_match_edges(execution).unwrap()
  assert_eq(@local_sga.match_edges_type_probes(execution), 3)
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
test "edge identity sort yields during a long text comparison" {
  let prefix = "y".repeat(160)
  let first = prefix + "a"
  let second = prefix + "b"
  let rows = "[{\"id\":\"" +
    second +
    "\",\"src\":\"" +
    second +
    "\",\"dst\":\"" +
    second +
    "\",\"rel\":\"owns\"," +
    "\"weight\":2},{\"id\":\"" +
    first +
    "\",\"src\":\"" +
    first +
    "\",\"dst\":\"" +
    first +
    "\",\"rel\":\"owns\"," +
    "\"weight\":1}]"
  let source_owner = carrier_graph_labeled_source_owner_with_rows(
    rows,
    text_id=true,
  )
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_edge_match_owner(source_owner, "[\"owns\"]")
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
  let control = @bounded.control()
  let execution = @local_sga.start_match_edges(
    control,
    task_test_completion(owner),
    sequence,
    1,
    input,
    2,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    12,
    1000,
    1000,
    [external],
  ).unwrap()
  for _ in 0..<60 {
    assert_true(
      @local_sga.advance_match_edges(execution, 1).unwrap()
      is @local_sga.MatchEdgesContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_match_edges(execution, 1).unwrap()
    is @local_sga.MatchEdgesStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_match_edges(execution), Ok(true))
  assert_true(@graphs.producer_read_available(input))
  let completed = @local_sga.start_match_edges(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    2,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    12,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_match_edges(completed).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Text(id)) && id == first,
  )
  assert_true(
    @execution.completed_cell(output, 1, 0) is Some(Text(id)) && id == second,
  )
  assert_eq(@local_sga.cleanup_match_edges(completed), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(source))
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
  let start = fn(workspace, work) raise {
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
      control_work_limit=Some(work),
    )
  }
  let insufficient = start(15, 100).unwrap()
  assert_true(
    finish_match_edges(insufficient)
    is Err(@local_sga.MatchEdgesPredicate(@execution.WorkspaceLimit)),
  )
  assert_eq(@local_sga.cleanup_match_edges(insufficient), Ok(true))
  // One type entry, two scratch cells, two edge probes, eight bindings,
  // predicate evaluation, four fields, a row commit, and finalization
  // have a fixed 33-unit control-work envelope for this two-edge input.
  let execution = start(16, 33).unwrap()
  let mut completed : @execution.CompletedOutput? = None
  for _ in 0..<34 {
    if completed is None {
      match @local_sga.advance_match_edges(execution, 1).unwrap() {
        @local_sga.MatchEdgesContinue(..) => ()
        @local_sga.MatchEdgesComplete(output, work~, ..) => {
          assert_eq(work, 33L)
          completed = Some(output)
        }
        _ => fail("exact predicate edge work failed")
      }
    }
  }
  let output = completed.unwrap()
  assert_eq(@local_sga.cleanup_match_edges(execution), Ok(true))
  let short = start(16, 32).unwrap()
  let mut failed = false
  for _ in 0..<34 {
    if !failed {
      match @local_sga.advance_match_edges(short, 1).unwrap() {
        @local_sga.MatchEdgesContinue(..) => ()
        @local_sga.MatchEdgesFailed(@local_sga.MatchEdgesWorkLimit, ..) =>
          failed = true
        _ => fail("one-short predicate edge work accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(@local_sga.match_edges_cleanup_pending(short))
  assert_eq(@local_sga.cleanup_match_edges(short), Ok(true))
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
  assert_eq(@local_sga.match_edges_scratch_slots(execution), 0)
  assert_true(
    @local_sga.advance_match_edges(execution, 1).unwrap()
    is @local_sga.MatchEdgesContinue(progress=1L, work=1L),
  )
  assert_eq(@local_sga.match_edges_scratch_slots(execution), 1)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_match_edges(execution, 1).unwrap()
    is @local_sga.MatchEdgesStopped(_, progress=1L, work=1L),
  )
  assert_true(@local_sga.match_edges_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_match_edges(execution), Ok(true))
  assert_eq(@local_sga.match_edges_scratch_slots(execution), 0)
  assert_false(@local_sga.match_edges_cleanup_pending(execution))
  assert_true(@execution.producer_read_available(external))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "edge type index builds within quantum and releases on cancellation" {
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
  let start = fn(control, workspace) raise {
    @local_sga.start_match_edges(
      control,
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
  assert_true(
    start(@bounded.control(), 11) is Err(@local_sga.MatchEdgesWorkspaceLimit),
  )
  let control = @bounded.control()
  let execution = start(control, 12).unwrap()
  assert_eq(@local_sga.match_edges_scratch_slots(execution), 0)
  assert_eq(@local_sga.match_edges_type_probes(execution), 0)
  assert_true(
    @local_sga.advance_match_edges(execution, 1).unwrap()
    is @local_sga.MatchEdgesContinue(progress=1L, work=1L),
  )
  assert_eq(@local_sga.match_edges_scratch_slots(execution), 0)
  assert_eq(@local_sga.match_edges_type_probes(execution), 0)
  assert_true(
    @local_sga.advance_match_edges(execution, 1).unwrap()
    is @local_sga.MatchEdgesContinue(progress=2L, work=2L),
  )
  assert_eq(@local_sga.match_edges_scratch_slots(execution), 0)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_match_edges(execution, 1).unwrap()
    is @local_sga.MatchEdgesStopped(_, progress=2L, work=2L),
  )
  assert_eq(@local_sga.cleanup_match_edges(execution), Ok(true))
  assert_true(@graphs.producer_read_available(input))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "edge identity match admits exact work and workspace and rejects one short" {
  let source_owner = carrier_graph_labeled_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_edge_match_owner(source_owner, "[\"missing\"]")
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
  let start = fn(work, workspace) raise {
    @local_sga.start_match_edges(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      input,
      0,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [external],
      control_work_limit=Some(work),
    )
  }
  // Three edges need six sort slots, four output-name slots, and one type
  // index slot. Work adds the index, scratch, checks, and finish.
  assert_true(start(8, 10) is Err(@local_sga.MatchEdgesWorkspaceLimit))
  let exact = start(8, 11).unwrap()
  let mut complete = false
  for _ in 0..<9 {
    if !complete {
      match @local_sga.advance_match_edges(exact, 1).unwrap() {
        @local_sga.MatchEdgesContinue(..) => ()
        @local_sga.MatchEdgesComplete(output, work~, ..) => {
          assert_eq(work, 8L)
          assert_eq(@execution.completed_row_count(output), 0)
          complete = true
        }
        @local_sga.MatchEdgesFailed(@local_sga.MatchEdgesWorkLimit, work~, ..) =>
          fail("exact edge match exhausted work at " + work.to_string())
        _ => fail("exact edge match control work failed")
      }
    }
  }
  assert_true(complete)
  assert_eq(@local_sga.cleanup_match_edges(exact), Ok(true))
  let short = start(7, 11).unwrap()
  let mut failed = false
  for _ in 0..<9 {
    if !failed {
      match @local_sga.advance_match_edges(short, 1).unwrap() {
        @local_sga.MatchEdgesContinue(..) => ()
        @local_sga.MatchEdgesFailed(@local_sga.MatchEdgesWorkLimit, ..) =>
          failed = true
        _ => fail("one-short edge match control work accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(@local_sga.match_edges_cleanup_pending(short))
  assert_eq(@local_sga.cleanup_match_edges(short), Ok(true))
  assert_true(@graphs.producer_read_available(input))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "selected edge match view admits exact limits and cleans cancellation" {
  let source_owner = carrier_graph_labeled_source_owner()
  let graph_owner = carrier_graph_edge_match_owner(
    source_owner, "[\"missing\"]",
  )
  let owner = carrier_selected_match_owner(graph_owner, false)
  let material = carrier_match_graph_material(graph_owner, source_owner)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let sequence = @execution.generated_prepared_sequence(generated)
  let control = @bounded.control()
  let start = fn(work, workspace) {
    let view = @carrier_runtime.material_prepare_view(
      material, owner, 0, graph_owner,
    ).unwrap()
    @local_sga.start_match_edges_view(
      control,
      @execution.generated_completion_preparation(generated),
      sequence,
      0,
      view,
      0,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [],
      control_work_limit=Some(work),
    )
  }
  assert_true(start(8, 10) is Err(@local_sga.MatchEdgesWorkspaceLimit))
  let exact = start(8, 11).unwrap()
  let mut complete = false
  for _ in 0..<9 {
    if !complete {
      match @local_sga.advance_match_edges(exact, 1).unwrap() {
        @local_sga.MatchEdgesContinue(..) => ()
        @local_sga.MatchEdgesComplete(output, work~, ..) => {
          assert_eq(work, 8L)
          assert_eq(@execution.completed_row_count(output), 0)
          complete = true
        }
        _ => fail("selected edge match exact limit failed")
      }
    }
  }
  assert_true(complete)
  assert_eq(@local_sga.cleanup_match_edges(exact), Ok(true))
  let short = start(7, 11).unwrap()
  let mut failed = false
  for _ in 0..<9 {
    if !failed {
      match @local_sga.advance_match_edges(short, 1).unwrap() {
        @local_sga.MatchEdgesContinue(..) => ()
        @local_sga.MatchEdgesFailed(@local_sga.MatchEdgesWorkLimit, ..) =>
          failed = true
        _ => fail("selected edge match one-short limit accepted")
      }
    }
  }
  assert_true(failed)
  assert_eq(@local_sga.cleanup_match_edges(short), Ok(true))
  let cancelled = start(8, 11).unwrap()
  match @local_sga.advance_match_edges(cancelled, 1).unwrap() {
    @local_sga.MatchEdgesContinue(work~, ..) => assert_true(work > 0L)
    _ => fail("selected edge match did not advance before cancellation")
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_match_edges(cancelled, 1).unwrap()
    is @local_sga.MatchEdgesStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_match_edges(cancelled), Ok(true))
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "homogeneous traversal reads a Relation start selector" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let selector_owner = carrier_graph_selector_source_owner(
    "[{\"key\":2},{\"key\":1},{\"key\":2}]",
    nullable=true,
  )
  let selector = carrier_events_source_output(selector_owner)
  let owner = carrier_graph_relation_traverse_owner(
    source_owner, selector_owner,
  )
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
  let sequence = prepared_sequence(owner)
  let source_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let selector_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, selector_owner, selector).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [source_read, source_read],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let execution = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    65,
    1000,
    1000,
    [source_read, selector_read],
  ).unwrap()
  let output = finish_traverse(execution).unwrap()
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 4)
  let rows = []
  for row in 0..<4 {
    rows.push(
      @execution.completed_output_row_wire(output, row, 1000, 100, 10).unwrap(),
    )
  }
  assert_eq(rows, [
    "{\"depth\":1,\"node_id\":2,\"start_id\":1}", "{\"depth\":2,\"node_id\":3,\"start_id\":1}",
    "{\"depth\":1,\"node_id\":1,\"start_id\":2}", "{\"depth\":1,\"node_id\":3,\"start_id\":2}",
  ])
  assert_true(
    @execution.completed_output_matches_inputs(output, [
      source_read, selector_read,
    ]),
  )
  let control = @bounded.control()
  let cancelled = @local_sga.start_traverse(
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
    [source_read, selector_read],
  ).unwrap()
  match @local_sga.advance_traverse(cancelled, 1).unwrap() {
    @local_sga.TraverseContinue(..) => ()
    _ => fail("Relation start traversal must remain resumable")
  }
  assert_true(@bounded.request_cancel(control))
  match @local_sga.advance_traverse(cancelled, 1).unwrap() {
    @local_sga.TraverseStopped(_, ..) => ()
    _ => fail("Relation start traversal must stop after cancellation")
  }
  assert_true(@local_sga.traverse_stopped(cancelled))
  assert_eq(@local_sga.cleanup_traverse(cancelled), Ok(true))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "path traversal reads a Relation start selector" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let selector_owner = carrier_graph_selector_source_owner(
    "[{\"key\":2},{\"key\":1},{\"key\":2}]",
    nullable=true,
  )
  let selector = carrier_events_source_output(selector_owner)
  let owner = carrier_graph_relation_traverse_owner(
    source_owner,
    selector_owner,
    emission="paths",
  )
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
  let sequence = prepared_sequence(owner)
  let source_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let selector_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, selector_owner, selector).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [source_read, source_read],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let execution = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [source_read, selector_read],
  ).unwrap()
  let output = finish_traverse(execution).unwrap()
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 4)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap(),
    "{\"edge_ids\":[{\"dst\":2,\"rel\":null,\"src\":1}]," +
    "\"end_id\":2,\"hop_count\":1,\"node_ids\":[1,2],\"start_id\":1}",
  )
  assert_true(
    @execution.completed_output_matches_inputs(output, [
      source_read, selector_read,
    ]),
  )
  let control = @bounded.control()
  let cancelled = @local_sga.start_traverse(
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
    [source_read, selector_read],
  ).unwrap()
  match @local_sga.advance_traverse(cancelled, 1).unwrap() {
    @local_sga.TraverseContinue(..) => ()
    _ => fail("Relation path traversal must remain resumable")
  }
  assert_true(@bounded.request_cancel(control))
  match @local_sga.advance_traverse(cancelled, 1).unwrap() {
    @local_sga.TraverseStopped(_, ..) => ()
    _ => fail("Relation path traversal must stop after cancellation")
  }
  assert_true(@local_sga.traverse_stopped(cancelled))
  assert_eq(@local_sga.cleanup_traverse(cancelled), Ok(true))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "homogeneous traversal evaluates a typed start predicate" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_traverse_owner(
    source_owner,
    1,
    2,
    predicate="node_name = 'two'",
  )
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
  let execution = @local_sga.start_traverse(
    @bounded.control(),
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
  let output = finish_traverse(execution).unwrap()
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap(),
    "{\"depth\":1,\"node_id\":1,\"start_id\":2}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 1000, 100, 10).unwrap(),
    "{\"depth\":1,\"node_id\":3,\"start_id\":2}",
  )
  assert_true(@graphs.discard_completed(graph))
}

///|
test "path traversal evaluates a typed start predicate" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_traverse_owner(
    source_owner,
    1,
    2,
    emission="paths",
    predicate="node_name = 'two'",
  )
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
  assert_true(
    @local_sga.start_traverse(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      5,
      1000,
      1000,
      [external],
    )
    is Err(@local_sga.TraversePathIssue(@local_sga.TraversePathsWorkspaceLimit)),
  )
  let admission_control = @bounded.control()
  let admitted = @local_sga.start_traverse(
    admission_control,
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    6,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(@bounded.request_cancel(admission_control))
  match @local_sga.advance_traverse(admitted, 1).unwrap() {
    @local_sga.TraverseStopped(_, ..) => ()
    _ => fail("Predicate path traversal must stop after cancellation")
  }
  assert_eq(@local_sga.cleanup_traverse(admitted), Ok(true))
  let execution = @local_sga.start_traverse(
    @bounded.control(),
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
  let output = finish_traverse(execution).unwrap()
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap(),
    "{\"edge_ids\":[{\"dst\":1,\"rel\":null,\"src\":2}]," +
    "\"end_id\":1,\"hop_count\":1,\"node_ids\":[2,1],\"start_id\":2}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 1000, 100, 10).unwrap(),
    "{\"edge_ids\":[{\"dst\":3,\"rel\":null,\"src\":2}]," +
    "\"end_id\":3,\"hop_count\":1,\"node_ids\":[2,3],\"start_id\":2}",
  )
  assert_true(@graphs.discard_completed(graph))
}

///|
test "path traversal admits hop predicate bindings before allocation" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_predicate_pattern_owner(
    source_owner,
    emission="paths",
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
  assert_true(
    @local_sga.start_traverse(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      4,
      1000,
      1000,
      [external],
    )
    is Err(@local_sga.TraversePathIssue(@local_sga.TraversePathsWorkspaceLimit)),
  )
  let control = @bounded.control()
  let admitted = @local_sga.start_traverse(
    control,
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    5,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_traverse(admitted, 1).unwrap()
    is @local_sga.TraverseStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_traverse(admitted), Ok(true))
  let execution = @local_sga.start_traverse(
    @bounded.control(),
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
  let output = finish_traverse(execution).unwrap()
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap(),
    "{\"edge_ids\":[{\"dst\":1,\"rel\":null,\"src\":2}]," +
    "\"end_id\":1,\"hop_count\":1,\"node_ids\":[2,1],\"start_id\":2}",
  )
  assert_true(@graphs.discard_completed(graph))
}

///|
fn traverse_paths_result_for_source(
  source_owner : @lower.BoundPrepared,
  max_output_rows : Int,
  workspace : Int,
  minimum? : Int = 1,
  maximum? : Int = 2,
  starts? : String = "1",
  predicate? : String = "",
  max_value_nodes? : Int = 1000,
  attempts? : Ref[Int]? = None,
  quantum? : Int = 1,
  workspace_peak? : Ref[Int]? = None,
  max_work? : Int = 10000,
  spent_work? : Ref[Int64]? = None,
) -> Result[@execution.CompletedOutput, @local_sga.TraverseIssue] raise {
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_traverse_owner(
    source_owner,
    minimum,
    maximum,
    emission="paths",
    starts~,
    predicate~,
    max_output_rows~,
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
  let execution = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    4,
    {
      max_nodes: max_value_nodes,
      max_text_bytes: 1000,
      max_depth: 10,
      max_work,
    },
    workspace,
    1000,
    1000,
    [external],
  ).unwrap()
  let result = finish_traverse(execution, quantum~, spent_work~)
  if attempts is Some(attempts) {
    attempts.val = @local_sga.traverse_value_item_attempts(execution)
  }
  if workspace_peak is Some(peak) {
    peak.val = @local_sga.traverse_private_workspace_usage(execution).1
  }
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  result
}

///|
fn homogeneous_traverse_paths_result(
  max_output_rows : Int,
  workspace : Int,
  minimum? : Int = 1,
  maximum? : Int = 2,
  starts? : String = "1",
  predicate? : String = "",
  max_value_nodes? : Int = 1000,
  attempts? : Ref[Int]? = None,
  quantum? : Int = 1,
  workspace_peak? : Ref[Int]? = None,
) -> Result[@execution.CompletedOutput, @local_sga.TraverseIssue] raise {
  traverse_paths_result_for_source(
    carrier_graph_components_source_owner(),
    max_output_rows,
    workspace,
    minimum~,
    maximum~,
    starts~,
    predicate~,
    max_value_nodes~,
    attempts~,
    quantum~,
    workspace_peak~,
  )
}

///|
fn traverse_nodes_result_for_source(
  source_owner : @lower.BoundPrepared,
  minimum : Int,
  maximum : Int,
  max_rows? : Int = 4,
  workspace? : Int = 100,
  peak? : Ref[Int]? = None,
  max_work? : Int = 10000,
  spent_work? : Ref[Int64]? = None,
) -> Result[@execution.CompletedOutput, @local_sga.TraverseIssue] raise {
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_traverse_owner(
    source_owner,
    minimum,
    maximum,
    emission="nodes",
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
  let execution = match
    @local_sga.start_traverse(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
      max_rows,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work, },
      workspace,
      1000,
      1000,
      [external],
    ) {
    Ok(value) => value
    Err(issue) => {
      assert_true(@graphs.discard_completed(graph))
      return Err(issue)
    }
  }
  let result = finish_traverse(execution, spent_work~)
  if peak is Some(value) {
    value.val = @local_sga.traverse_private_workspace_usage(execution).1
  }
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  result
}

///|
test "node traversal sorts endpoints and retains minimum eligible depth" {
  let source_owner = carrier_graph_source_owner_with_rows(
    "[{\"id\":1,\"src\":1,\"dst\":3,\"node_name\":\"one\",\"weight\":1}," +
    "{\"id\":2,\"src\":1,\"dst\":2,\"node_name\":\"two\",\"weight\":1}," +
    "{\"id\":3,\"src\":2,\"dst\":4,\"node_name\":\"three\",\"weight\":1}," +
    "{\"id\":4,\"src\":3,\"dst\":5,\"node_name\":\"four\",\"weight\":1}," +
    "{\"id\":5,\"src\":5,\"dst\":4,\"node_name\":\"five\",\"weight\":1}]",
  )
  let peak = Ref(0)
  let output = traverse_nodes_result_for_source(
    source_owner,
    2,
    3,
    peak=Some(peak),
  ).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 20).unwrap(),
    "{\"depth\":2,\"node_id\":4,\"start_id\":1}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 10000, 1000, 20).unwrap(),
    "{\"depth\":2,\"node_id\":5,\"start_id\":1}",
  )
  assert_true(peak.val > 0)
  assert_true(
    traverse_nodes_result_for_source(source_owner, 2, 3, max_rows=1)
    is Err(@local_sga.TraversePathIssue(@local_sga.TraversePathsOutputLimit)),
  )
  assert_true(
    traverse_nodes_result_for_source(source_owner, 2, 3, workspace=peak.val - 1)
    is Err(@local_sga.TraversePathIssue(@local_sga.TraversePathsWorkspaceLimit)),
  )
}

///|
test "node traversal cancellation reclaims the unpublished path state" {
  let source_owner = carrier_graph_source_owner_with_rows(
    "[{\"id\":1,\"src\":1,\"dst\":3,\"node_name\":\"one\",\"weight\":1}," +
    "{\"id\":2,\"src\":1,\"dst\":2,\"node_name\":\"two\",\"weight\":1}," +
    "{\"id\":3,\"src\":2,\"dst\":3,\"node_name\":\"three\",\"weight\":1}]",
  )
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_traverse_owner(source_owner, 2, 2, emission="nodes")
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
  let control = @bounded.control()
  let execution = @local_sga.start_traverse(
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
  let mut reached = false
  for _ in 0..<1000 {
    match @local_sga.advance_traverse(execution, 1).unwrap() {
      @local_sga.TraverseContinue(..) =>
        if @local_sga.traverse_private_entry_count(execution) > 3 {
          reached = true
          break
        }
      _ => abort("node traversal completed before cancellation")
    }
  }
  assert_true(reached)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_traverse(execution, 1).unwrap()
    is @local_sga.TraverseStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_eq(@local_sga.traverse_private_entry_count(execution), 0)
  assert_eq(@local_sga.traverse_private_workspace_usage(execution).0, 0)
  assert_true(@graphs.discard_completed(graph))
}

///|
fn relation_traverse_result(
  rows : String,
  emission : String,
  nullable? : Bool = false,
) -> Result[@execution.CompletedOutput, @local_sga.TraverseIssue] raise {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let selector_owner = carrier_graph_selector_source_owner(rows, nullable~)
  let selector = carrier_events_source_output(selector_owner)
  let owner = carrier_graph_relation_traverse_owner(
    source_owner,
    selector_owner,
    emission~,
  )
  let sequence = prepared_sequence(owner)
  let source_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let selector_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, selector_owner, selector).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [source_read, source_read],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let execution = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [source_read, selector_read],
  ).unwrap()
  let result = finish_traverse(execution)
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  result
}

///|
fn relation_traverse_paths_result(
  rows : String,
  nullable? : Bool = false,
) -> Result[@execution.CompletedOutput, @local_sga.TraverseIssue] raise {
  relation_traverse_result(rows, "paths", nullable~)
}

///|
test "homogeneous traversal emits canonical simple paths" {
  let output = homogeneous_traverse_paths_result(4, 100).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 20).unwrap(),
    "{\"edge_ids\":[{\"dst\":2,\"rel\":null,\"src\":1}]," +
    "\"end_id\":2,\"hop_count\":1,\"node_ids\":[1,2],\"start_id\":1}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 10000, 1000, 20).unwrap(),
    "{\"edge_ids\":[{\"dst\":2,\"rel\":null,\"src\":1}," +
    "{\"dst\":3,\"rel\":null,\"src\":2}],\"end_id\":3," +
    "\"hop_count\":2,\"node_ids\":[1,2,3],\"start_id\":1}",
  )
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
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
}

///|
test "path traversal admits output and workspace before expansion" {
  assert_true(
    homogeneous_traverse_paths_result(1, 100)
    is Err(@local_sga.TraversePathIssue(@local_sga.TraversePathsOutputLimit)),
  )
  assert_true(
    homogeneous_traverse_paths_result(4, 19)
    is Err(@local_sga.TraversePathIssue(@local_sga.TraversePathsWorkspaceLimit)),
  )
  let peak = Ref(0)
  assert_true(
    homogeneous_traverse_paths_result(4, 20, workspace_peak=Some(peak)) is Ok(_),
  )
  assert_eq(peak.val, 20)
}

///|
test "path traversal charges overlapping start selector and indices" {
  for workspace in [7, 8] {
    let source_owner = carrier_graph_components_source_owner()
    let source = carrier_events_source_output(source_owner)
    let owner = carrier_graph_traverse_owner(
      source_owner,
      0,
      1,
      emission="paths",
      starts="1,2,3,4",
      max_output_rows=20,
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
    let control = @bounded.control()
    let execution = @local_sga.start_traverse(
      control,
      task_test_completion(owner),
      sequence,
      1,
      @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
      20,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [external],
    ).unwrap()
    let mut terminal = false
    let mut polls = 0
    while !terminal {
      polls += 1
      assert_true(polls < 1000)
      match @local_sga.advance_traverse(execution, 1).unwrap() {
        @local_sga.TraverseContinue(..) => {
          let (live, peak) = @local_sga.traverse_private_workspace_usage(
            execution,
          )
          if workspace == 8 && peak == 8 && live == 8 {
            assert_eq(@local_sga.traverse_private_entry_count(execution), 8)
            assert_true(@bounded.request_cancel(control))
            assert_true(
              @local_sga.advance_traverse(execution, 1).unwrap()
              is @local_sga.TraverseStopped(_, ..),
            )
            terminal = true
          }
        }
        @local_sga.TraverseFailed(
          @local_sga.TraversePathIssue(@local_sga.TraversePathsWorkspaceLimit),
          ..
        ) => {
          assert_eq(workspace, 7)
          assert_eq(@local_sga.traverse_private_workspace_usage(execution).1, 7)
          terminal = true
        }
        _ => abort("unexpected traversal outcome")
      }
    }
    assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
    assert_eq(@local_sga.traverse_private_entry_count(execution), 0)
    assert_eq(@local_sga.traverse_private_workspace_usage(execution).0, 0)
    if workspace == 8 {
      for ceiling in [0, 1] {
        let limited = @local_sga.start_traverse(
          @bounded.control(),
          task_test_completion(owner),
          sequence,
          1,
          @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
          20,
          {
            max_nodes: 1000,
            max_text_bytes: 1000,
            max_depth: 10,
            max_work: ceiling,
          },
          workspace,
          1000,
          1000,
          [external],
        ).unwrap()
        match @local_sga.advance_traverse(limited, 100).unwrap() {
          @local_sga.TraverseFailed(
            @local_sga.TraversePathIssue(@local_sga.TraversePathsWorkLimit),
            progress=0L,
            work~
          ) => assert_eq(work, ceiling.to_int64())
          _ => fail("path traversal escaped its work ceiling")
        }
        assert_eq(@local_sga.cleanup_traverse(limited), Ok(true))
        assert_eq(@local_sga.traverse_private_entry_count(limited), 0)
      }
    }
    assert_true(@graphs.discard_completed(graph))
  }
}

///|
test "sparse and zero-hop path selectors are independent of resume quantum" {
  let empty_one_peak = Ref(0)
  let empty_seven_peak = Ref(0)
  let empty_one = homogeneous_traverse_paths_result(
    10,
    100,
    minimum=0,
    maximum=1,
    predicate="false",
    quantum=1,
    workspace_peak=Some(empty_one_peak),
  ).unwrap()
  let empty_seven = homogeneous_traverse_paths_result(
    10,
    100,
    minimum=0,
    maximum=1,
    predicate="false",
    quantum=7,
    workspace_peak=Some(empty_seven_peak),
  ).unwrap()
  assert_eq(@execution.completed_row_count(empty_one), 0)
  assert_eq(@execution.completed_row_count(empty_seven), 0)
  assert_eq(empty_one_peak.val, empty_seven_peak.val)
  let one_peak = Ref(0)
  let seven_peak = Ref(0)
  let one = homogeneous_traverse_paths_result(
    10,
    100,
    minimum=0,
    maximum=1,
    starts="1,4",
    quantum=1,
    workspace_peak=Some(one_peak),
  ).unwrap()
  let seven = homogeneous_traverse_paths_result(
    10,
    100,
    minimum=0,
    maximum=1,
    starts="1,4",
    quantum=7,
    workspace_peak=Some(seven_peak),
  ).unwrap()
  assert_eq(one_peak.val, seven_peak.val)
  assert_true(one_peak.val >= 6)
  assert_eq(
    @execution.completed_row_count(one),
    @execution.completed_row_count(seven),
  )
  for row in 0..<@execution.completed_row_count(one) {
    assert_eq(
      @execution.completed_output_row_wire(one, row, 10000, 1000, 20).unwrap(),
      @execution.completed_output_row_wire(seven, row, 10000, 1000, 20).unwrap(),
    )
  }
}

///|
test "path traversal rejects oversized arrays before building all items" {
  let attempts = Ref(0)
  assert_true(
    homogeneous_traverse_paths_result(
      1,
      100,
      minimum=2,
      maximum=2,
      max_value_nodes=16,
      attempts=Some(attempts),
    )
    is Err(@local_sga.TraversePathIssue(@local_sga.TraversePathsOutputLimit)),
  )
  assert_eq(attempts.val, 0)
  assert_true(
    homogeneous_traverse_paths_result(
      1,
      100,
      minimum=2,
      maximum=2,
      max_value_nodes=17,
    )
    is Ok(_),
  )
}

///|
test "path traversal orders all depths within each canonical start" {
  let expected = [
    "{\"edge_ids\":[{\"dst\":2,\"rel\":null,\"src\":1}]," +
    "\"end_id\":2,\"hop_count\":1,\"node_ids\":[1,2],\"start_id\":1}",
    "{\"edge_ids\":[{\"dst\":2,\"rel\":null,\"src\":1}," +
    "{\"dst\":3,\"rel\":null,\"src\":2}],\"end_id\":3," +
    "\"hop_count\":2,\"node_ids\":[1,2,3],\"start_id\":1}",
    "{\"edge_ids\":[{\"dst\":1,\"rel\":null,\"src\":2}]," +
    "\"end_id\":1,\"hop_count\":1,\"node_ids\":[2,1],\"start_id\":2}",
    "{\"edge_ids\":[{\"dst\":3,\"rel\":null,\"src\":2}]," +
    "\"end_id\":3,\"hop_count\":1,\"node_ids\":[2,3],\"start_id\":2}",
  ]
  for quantum in [1, 2, 32, 256] {
    let output = homogeneous_traverse_paths_result(
      4,
      100,
      starts="2,1,2",
      quantum~,
    ).unwrap()
    assert_eq(@execution.completed_row_count(output), 4)
    let rows = Array::makei(4, row => {
      @execution.completed_output_row_wire(output, row, 10000, 1000, 20).unwrap()
    })
    assert_eq(rows, expected)
  }
}

///|
test "path traversal is start-major across physical edge permutations" {
  let a = "{\"id\":1,\"src\":1,\"dst\":3," +
    "\"node_name\":\"one\",\"weight\":10}"
  let b = "{\"id\":3,\"src\":3,\"dst\":4," +
    "\"node_name\":\"three\",\"weight\":30}"
  let c = "{\"id\":2,\"src\":2,\"dst\":4," +
    "\"node_name\":\"two\",\"weight\":20}"
  let d = "{\"id\":4,\"src\":4,\"dst\":4," +
    "\"node_name\":\"four\",\"weight\":40}"
  let expected = [
    "{\"edge_ids\":[{\"dst\":3,\"rel\":null,\"src\":1}]," +
    "\"end_id\":3,\"hop_count\":1,\"node_ids\":[1,3],\"start_id\":1}",
    "{\"edge_ids\":[{\"dst\":3,\"rel\":null,\"src\":1}," +
    "{\"dst\":4,\"rel\":null,\"src\":3}],\"end_id\":4," +
    "\"hop_count\":2,\"node_ids\":[1,3,4],\"start_id\":1}",
    "{\"edge_ids\":[{\"dst\":4,\"rel\":null,\"src\":2}]," +
    "\"end_id\":4,\"hop_count\":1,\"node_ids\":[2,4],\"start_id\":2}",
  ]
  for
    rows in [
      [a, b, c, d],
      [a, c, b, d],
      [b, a, c, d],
      [b, c, a, d],
      [c, a, b, d],
      [c, b, a, d],
    ] {
    let source_owner = carrier_graph_source_owner_with_rows(
      "[" + rows.join(",") + "]",
    )
    let output = traverse_paths_result_for_source(
      source_owner,
      3,
      120,
      starts="2,1",
    ).unwrap()
    let actual = Array::makei(3, row => {
      @execution.completed_output_row_wire(output, row, 10000, 1000, 20).unwrap()
    })
    assert_eq(actual, expected)
  }
}

///|
test "path traversal revalidates nullable Relation start identities" {
  let required = relation_traverse_paths_result("[{\"key\":1}]").unwrap()
  let nullable = relation_traverse_paths_result("[{\"key\":1}]", nullable=true).unwrap()
  assert_eq(
    @execution.completed_output_row_wire(required, 0, 10000, 1000, 20).unwrap(),
    @execution.completed_output_row_wire(nullable, 0, 10000, 1000, 20).unwrap(),
  )
  assert_true(
    relation_traverse_paths_result("[{\"key\":null}]", nullable=true)
    is Err(
      @local_sga.TraversePathIssue(
        @local_sga.TraversePathsKeyOrder(@admitted.InvalidKey)
      )
    ),
  )
  assert_true(
    relation_traverse_paths_result("[{\"key\":999}]", nullable=true)
    is Err(@local_sga.TraversePathIssue(@local_sga.TraversePathsStartMissing)),
  )
  assert_eq(
    @execution.completed_row_count(
      relation_traverse_paths_result("[]", nullable=true).unwrap(),
    ),
    0,
  )
}

///|
test "path traversal rejects a Graph read bound to another step" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_two_path_traversals_owner(source_owner)
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
  let wrong_step = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  assert_true(
    @local_sga.start_traverse(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      2,
      wrong_step,
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      100,
      1000,
      1000,
      [external],
    )
    is Err(@local_sga.UnsupportedTraverseKernel),
  )
  assert_true(@graphs.producer_read_available(wrong_step))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "path traversal emits a zero-hop path at minimum zero" {
  let output = homogeneous_traverse_paths_result(4, 100, minimum=0).unwrap()
  assert_eq(@execution.completed_row_count(output), 3)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 20).unwrap(),
    "{\"edge_ids\":[],\"end_id\":1,\"hop_count\":0," +
    "\"node_ids\":[1],\"start_id\":1}",
  )
}

///|
test "path traversal observes cancellation before completion" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_traverse_owner(source_owner, 1, 2, emission="paths")
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
  let control = @bounded.control()
  let execution = @local_sga.start_traverse(
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
  assert_true(
    @local_sga.advance_traverse(execution, 1).unwrap()
    is @local_sga.TraverseContinue(progress=0L, work=1L),
  )
  assert_true(@local_sga.traverse_private_entry_count(execution) > 0)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_traverse(execution, 1).unwrap()
    is @local_sga.TraverseStopped(_, ..),
  )
  assert_true(@local_sga.traverse_stopped(execution))
  assert_true(@local_sga.traverse_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_false(@local_sga.traverse_cleanup_pending(execution))
  assert_eq(@local_sga.traverse_private_entry_count(execution), 0)
  assert_true(@graphs.discard_completed(graph))
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
test "rows to Graph Bridge admits exact control work and workspace" {
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
  // Two declared nodes each take identity, property, and commit work. Two
  // edges each take source, target, property, two endpoint checks, and commit.
  // Finalizing the Graph is one further step: 2 * 3 + 2 * 6 + 1 = 19.
  // The two property indices and eight fixed scratch slots overlap at start.
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
      control_work_limit=Some(19),
    )
    is Err(@local_bridge.GraphWorkspaceLimit),
  )
  for (work, accepted) in [(19, true), (18, false)] {
    let execution = @local_bridge.start_rows_to_graph(
      @bounded.control(),
      sequence,
      0,
      [external, external],
      carrier_graph_storage_limits(),
      4096L,
      10,
      fn() { true },
      control_work_limit=Some(work),
    ).unwrap()
    let mut finished = false
    for _ in 0..<30 {
      if !finished {
        match @local_bridge.advance_rows_to_graph(execution, 1).unwrap() {
          @local_bridge.Continue(..) => ()
          @local_bridge.Complete(output, work=charged, ..) => {
            assert_true(accepted)
            assert_eq(charged, 19L)
            let storage = @graphs.completed_storage(output).unwrap()
            assert_eq(@graph_storage.node_count(storage), 2)
            assert_eq(@graph_storage.edge_count(storage), 2)
            assert_true(@graphs.discard_completed(output))
            finished = true
          }
          @local_bridge.Failed(@local_bridge.GraphControlWorkLimit, ..) => {
            assert_false(accepted)
            assert_true(@local_bridge.rows_to_graph_cleanup_pending(execution))
            finished = true
          }
          _ => fail("rows-to-Graph control boundary had another outcome")
        }
      }
    }
    assert_true(finished)
    assert_eq(@local_bridge.cleanup_rows_to_graph(execution), Ok(true))
    assert_false(@local_bridge.rows_to_graph_cleanup_pending(execution))
    assert_true(@execution.producer_read_available(external))
  }
  let control = @bounded.control()
  let cancelled = @local_bridge.start_rows_to_graph(
    control,
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    10,
    fn() { true },
    control_work_limit=Some(19),
  ).unwrap()
  assert_true(
    @local_bridge.advance_rows_to_graph(cancelled, 1).unwrap()
    is @local_bridge.Continue(work=1L, ..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_bridge.advance_rows_to_graph(cancelled, 1).unwrap()
    is @local_bridge.Stopped(@bounded.Cancelled, ..),
  )
  assert_true(@local_bridge.rows_to_graph_cleanup_pending(cancelled))
  assert_eq(@local_bridge.cleanup_rows_to_graph(cancelled), Ok(true))
  assert_false(@local_bridge.rows_to_graph_cleanup_pending(cancelled))
  assert_true(@execution.producer_read_available(external))
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
fn graph_rows_projection_workspace_and_cancel(
  projection : String,
  width : Int,
  exact_work : Int,
) -> Unit raise {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner, projection~)
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
  let values : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 1000,
    max_depth: 10,
    max_work: 10000,
  }
  assert_true(
    @local_bridge.start_graph_to_rows(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      input,
      10,
      values,
      width - 1,
      1000,
      1000,
      [external],
    )
    is Err(@local_bridge.GraphWorkspaceLimit),
  )
  let short_work : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 1000,
    max_depth: 10,
    max_work: exact_work - 1,
  }
  let rejected = @local_bridge.start_graph_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    10,
    short_work,
    width,
    1000,
    1000,
    [external],
  ).unwrap()
  let mut saw_work_limit = false
  for _ in 0..<100 {
    match @local_bridge.advance_graph_to_rows(rejected, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Failed(
        @local_bridge.GraphRelationOutput(@execution.CaptureLimit),
        ..
      ) => {
        saw_work_limit = true
        break
      }
      _ => fail("Graph projection did not reject one-short value work")
    }
  }
  assert_true(saw_work_limit)
  assert_true(@local_bridge.graph_to_rows_cleanup_pending(rejected))
  assert_eq(@local_bridge.cleanup_graph_to_rows(rejected), Ok(true))
  assert_true(@graphs.producer_read_available(input))
  let exact : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 1000,
    max_depth: 10,
    max_work: exact_work,
  }
  let accepted = @local_bridge.start_graph_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    10,
    exact,
    width,
    1000,
    1000,
    [external],
    control_work_limit=Some(2 * (width + 1)),
  ).unwrap()
  let rows = finish_graph_to_rows(accepted)
  assert_eq(@execution.completed_row_count(rows), 2)
  assert_eq(@local_bridge.cleanup_graph_to_rows(accepted), Ok(true))
  let one_short_control = @local_bridge.start_graph_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    10,
    values,
    width,
    1000,
    1000,
    [external],
    control_work_limit=Some(2 * (width + 1) - 1),
  ).unwrap()
  let mut control_failed = false
  for _ in 0..<100 {
    match @local_bridge.advance_graph_to_rows(one_short_control, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Failed(@local_bridge.GraphControlWorkLimit, ..) => {
        control_failed = true
        break
      }
      _ => fail("Graph projection did not reject one-short control work")
    }
  }
  assert_true(control_failed)
  assert_eq(@local_bridge.cleanup_graph_to_rows(one_short_control), Ok(true))
  let control = @bounded.control()
  let execution = @local_bridge.start_graph_to_rows(
    control,
    task_test_completion(owner),
    sequence,
    1,
    input,
    10,
    values,
    width,
    1000,
    1000,
    [external],
  ).unwrap()
  match @local_bridge.advance_graph_to_rows(execution, 1).unwrap() {
    @local_bridge.Continue(progress~, work~) => {
      assert_eq(progress, 0L)
      assert_eq(work, 1L)
    }
    _ => fail("Graph projection did not report bounded field work")
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_bridge.advance_graph_to_rows(execution, 1).unwrap()
    is @local_bridge.Stopped(_, ..),
  )
  assert_true(@local_bridge.graph_to_rows_cleanup_pending(execution))
  assert_eq(@local_bridge.cleanup_graph_to_rows(execution), Ok(true))
  assert_false(@local_bridge.graph_to_rows_cleanup_pending(execution))
  assert_true(@graphs.producer_read_available(input))
  assert_true(@execution.producer_read_available(external))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Graph node rows admit exact work and workspace and stop after field work" {
  // Two rows: one row node, two value nodes, 11 field-name bytes,
  // and five/six text bytes respectively.
  graph_rows_projection_workspace_and_cancel("node_rows", 2, 39)
}

///|
test "Graph edge rows admit exact work and workspace and stop after field work" {
  // Each row has one row node, four value nodes, and 15 field-name bytes.
  graph_rows_projection_workspace_and_cancel("edge_rows", 4, 40)
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
  if variant == "graph_diff_changes" {
    "sha256:de8347c32fb9edf7f0bddd3ab5bcd9b986ba90aeff296e55f02e52f067067ef9"
  } else if variant == "concise_projection" {
    // A nullable edge label is not a Result candidate key. Projected-field
    // completion orders by src before dst, so the src=1 row comes first.
    // Independent CID preimage: {"sort":"relation","value":[
    // {"dst":2,"id":1,"src":1,"weight":10},
    // {"dst":1,"id":2,"src":2,"weight":20}]}.
    "sha256:4dc1796ed34dc82b34758a1fca828ec1a34ef068e231fd5637d51841529bdb97"
  } else if variant == "subtract_exact" {
    "sha256:61658ff21fd18cc3b110c965c92422c813ef6e76d1aef0415841101c72e8f576"
  } else if variant == "subtract" {
    "sha256:581c1ad7ac48237df5c669e328275ed013a700f7308143a32557810117210089"
  } else if variant == "graph_bounds" {
    // The bounds kernel emits the whole-Graph rows before per-node rows.
    // Independent CID preimage: {"sort":"relation","value":[
    // {"actual":2,"kind":"nodes","max":1,"node_id":null},
    // {"actual":2,"kind":"edges","max":1,"node_id":null},
    // {"actual":2,"kind":"degree","max":1,"node_id":1},
    // {"actual":2,"kind":"degree","max":1,"node_id":2}]}.
    "sha256:ef020b0f84c290dff499e09e66f810128a9a64ec49b5f579f034c58fb2b22eaa"
  } else if variant == "match_edges" ||
    variant == "edge_projection" ||
    variant == "union_numeric" {
    "sha256:c60b5715592edabcbe32bd818f14c8d413b3717806662aa06c9e4eae57420932"
  } else if variant == "match_edges_predicate" {
    "sha256:2565b440f95c1ee69574099652dde59d535c5a390fe62c29de3b147d3ce32304"
  } else if variant == "match_nodes_predicate" {
    "sha256:a2151218d0638a59beb6b366fa8f2d0803e643139fd8c19cae1f9c8d6044f78f"
  } else if variant == "subgraph_ids" || variant == "subgraph_shared" {
    "sha256:a2151218d0638a59beb6b366fa8f2d0803e643139fd8c19cae1f9c8d6044f78f"
  } else if variant == "subgraph_edges_false" {
    "sha256:d2889f6d3b43fe20f75149d13eb0585918c94cf3a5b0520f5f9e1525b0846f3d"
  } else if variant == "subgraph_node_predicate" {
    "sha256:a2151218d0638a59beb6b366fa8f2d0803e643139fd8c19cae1f9c8d6044f78f"
  } else if variant.has_prefix("subgraph_relation_selector") {
    "sha256:a2151218d0638a59beb6b366fa8f2d0803e643139fd8c19cae1f9c8d6044f78f"
  } else if variant == "subgraph_edge_predicate" {
    "sha256:2565b440f95c1ee69574099652dde59d535c5a390fe62c29de3b147d3ce32304"
  } else if variant == "degree_both" {
    "sha256:3a537f671c5f32a7a9e97bb2e1a0edd04aeec3df32a5403bef7801958022deb0"
  } else if variant == "reach_out" {
    "sha256:821ce11feb97033bed3e665dd44185973dab504b4d5f85ee72b24ae212b765e4"
  } else if variant == "shortest_in" {
    "sha256:2415a7a8c26f36220fb0ab8b39e12b5a875638e7c7f12c77d33cff7beb3bf3f2"
  } else if variant == "shortest_ids" || variant == "shortest_relation_selector" {
    "sha256:7de829b7221d828eb4205ffbb82988aedafea600a2454a84203e4d966ff03b3c"
  } else if variant == "shortest_predicate" ||
    variant == "shortest_nearest_per_source" {
    "sha256:9734654c29bb6c6adc042fa640e65d87f7bd2eec43261acc3d0ae56209d7fde1"
  } else if variant == "shortest_weighted" {
    "sha256:3cfb1e511489aff333aa50b95bcdf7ccc857315196ef6ba1857d48bc1a7dc823"
  } else if variant.has_prefix("shortest_") {
    "sha256:831394d8299fafff2a67b830d12bd9ed6f22028d51be29d4c3cd04f81d7511b1"
  } else if variant == "traverse_paths" {
    "sha256:cfc576a9585dd7c2b6fabb259d8c20b6f56faa99fd09803f85d83805f8fd6174"
  } else if variant == "traverse_relation_paths" {
    "sha256:1c0cbd7fcb1f8c732eadd4214ccb94132fe77ebc043af653a0327d329adfafa7"
  } else if variant == "traverse_predicate_paths" {
    "sha256:1c0cbd7fcb1f8c732eadd4214ccb94132fe77ebc043af653a0327d329adfafa7"
  } else if variant == "traverse_pattern_multi_paths" {
    "sha256:dddbfc637cf2cf3754dd3bf39af12cd54006d26f38e09736d8f0fb1a922ed332"
  } else if variant.has_prefix("traverse_") {
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

///|
fn run_standard_host_graph_relation_path(
  variant : String,
  publication? : Bool = false,
) -> Unit raise {
  let graph_diff_changes = variant == "graph_diff_changes"
  let relation_selector = variant.has_prefix("subgraph_relation_selector") ||
    variant == "traverse_relation_selector" ||
    variant == "traverse_relation_paths" ||
    variant == "shortest_relation_selector"
  let traverse_relation_selector = variant == "traverse_relation_selector" ||
    variant == "traverse_relation_paths"
  let traverse_paths = variant == "traverse_paths" ||
    variant == "traverse_relation_paths" ||
    variant == "traverse_predicate_paths" ||
    variant == "traverse_pattern_multi_paths" ||
    variant == "traverse_in_paths" ||
    variant == "traverse_both_paths" ||
    variant == "traverse_zero_paths" ||
    variant == "traverse_type_empty_paths"
  let (run, issuer) = captured_graph_fixture(
    local_carrier_graph_chain=true,
    local_carrier_graph_variant=variant,
    managed_publication=publication,
    ledger_limits=if variant.has_suffix("unequal") ||
      variant == "split_projection" ||
      variant.has_prefix("subtract") ||
      variant == "union_set" ||
      graph_diff_changes ||
      relation_selector {
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
  let selected_path_query = variant.has_prefix("reach_") ||
    variant.has_prefix("shortest_")
  let separate_graph_task = variant == "projection" || selected_path_query
  let graph_task = if selected_path_query {
    if relation_selector {
      4
    } else {
      3
    }
  } else if separate_graph_task {
    3
  } else if variant.has_suffix("unequal") ||
    variant == "split_projection" ||
    variant.has_prefix("subtract") ||
    variant == "union_set" ||
    graph_diff_changes ||
    relation_selector {
    3
  } else {
    2
  }
  let cleanup_attempts = Ref(0)
  let base_provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      sequences[graph_task - 1],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let provider = if separate_graph_task {
    base_provider
  } else {
    delayed_cleanup_provider(base_provider, cleanup_attempts)
  }
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
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
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
  if relation_selector {
    let selector_live = Ref(true)
    let (selector_ops, selector) = run_local_managed_test_task(
      installed,
      run,
      2,
      [],
      [],
      2,
      selector_live,
      obligations?=graph_publication_obligations(run, publication),
    )
    graph_inputs.push(selector)
    graph_input_rows.push(local_managed_test_rows(selector_ops))
    other_cleanup.val = Some(fn() {
      selector_live.val = false
      @strategy.close_captured_task_output(run, 2)
      (selector_ops.close)()
      (selector_ops.cleanup_refresh)() |> ignore
    })
  } else if variant.has_suffix("unequal") ||
    variant == "split_projection" ||
    variant.has_prefix("subtract") ||
    variant == "union_set" ||
    graph_diff_changes {
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
  let initial_graph_obligations = graph_publication_obligations(
    run, publication,
  )
  let physical_cleanup : Ref[(() -> Unit)?] = Ref(None)
  let (graph_ops, graph, graph_obligations) = if separate_graph_task {
    let construction_task = graph_task - 1
    let producer_count = @strategy.captured_next_managed_producers(run).length()
    let construction_inputs = Array::makei(producer_count, _ => {
      @local_driver.local_managed_relation_output(values)
    })
    let construction_rows = Array::makei(producer_count, _ => values_rows)
    let (carrier_ops, carrier, material) = run_local_managed_carrier_test_task(
      installed,
      run,
      construction_task,
      construction_inputs,
      construction_rows,
      obligations?=graph_publication_obligations(run, publication),
    )
    physical_cleanup.val = Some(fn() {
      @strategy.close_captured_task_output(run, construction_task)
      (carrier_ops.close)()
      (carrier_ops.cleanup_refresh)() |> ignore
    })
    let output_obligations = graph_publication_obligations(run, publication)
    let ordered_outputs = if selected_path_query && relation_selector {
      [
        @local_driver.local_managed_carrier_output(carrier, material),
        @local_driver.local_managed_relation_output(graph_inputs[1]),
        @local_driver.local_managed_relation_output(graph_inputs[1]),
      ]
    } else {
      [@local_driver.local_managed_carrier_output(carrier, material)]
    }
    let output_input_rows = if selected_path_query && relation_selector {
      [graph_input_rows[1], graph_input_rows[1]]
    } else {
      []
    }
    let (output_ops, output) = run_local_managed_test_task(
      installed,
      run,
      graph_task,
      [],
      output_input_rows,
      graph_task,
      graph_live,
      obligations?=output_obligations,
      ordered_outputs=Some(ordered_outputs),
    )
    (output_ops, output, output_obligations)
  } else {
    let (output_ops, output) = run_local_managed_test_task(
      installed,
      run,
      graph_task,
      graph_inputs,
      graph_input_rows,
      graph_task,
      graph_live,
      obligations?=initial_graph_obligations,
    )
    (output_ops, output, initial_graph_obligations)
  }
  let graph_rows = local_managed_test_rows(graph_ops)
  let expected_rows = if variant == "traverse_type_miss" ||
    variant == "traverse_type_empty" ||
    variant == "traverse_type_empty_paths" ||
    variant == "traverse_types_miss" ||
    variant == "traverse_pattern_predicate_empty" ||
    variant == "traverse_pattern_multi_paths_empty" ||
    variant == "shortest_type_miss" ||
    variant == "shortest_type_empty" ||
    variant == "subgraph_edges_false" {
    0
  } else if variant == "graph_bounds" {
    4
  } else if variant == "traverse_both_paths" {
    2
  } else if variant == "traverse_zero_paths" {
    2
  } else if variant == "traverse_relation_paths" {
    2
  } else if variant == "traverse_ids" || traverse_relation_selector {
    2
  } else if variant == "shortest_ids" || variant == "shortest_relation_selector" {
    4
  } else if variant == "shortest_nearest_per_source" {
    2
  } else if variant == "shortest_nearest_pair" {
    1
  } else if variant == "shortest_predicate" {
    2
  } else if variant.has_prefix("shortest_") {
    1
  } else if variant == "traverse_predicate" ||
    variant == "traverse_predicate_paths" {
    2
  } else if variant == "union_set" {
    1
  } else if variant.has_prefix("traverse_") ||
    variant == "subtract" ||
    variant.has_prefix("subgraph_") {
    1
  } else if variant == "match_edges_predicate" ||
    variant == "match_nodes_predicate" {
    1
  } else if is_graph_equality_variant(variant) ||
    variant.has_prefix("graph_diff") {
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
  } else if variant == "subtract_numeric" {
    assert_true(graph_rows[0].contains("\"weight\":11"))
    assert_true(graph_rows[1].contains("\"weight\":25"))
  } else if variant == "union_set" {
    assert_true(graph_rows[0].contains("\"id\":1"))
    assert_true(graph_rows[0].contains("\"tags\":[null,\"a\",\"b\",\"c\"]"))
  } else if variant == "match_edges" ||
    variant == "edge_projection" ||
    variant == "union_numeric" {
    assert_true(graph_rows[0].contains("\"src\":1"))
    assert_true(
      graph_rows[1].contains(
        if variant == "union_numeric" {
          "\"weight\":40"
        } else {
          "\"weight\":20"
        },
      ),
    )
    if variant == "union_numeric" {
      assert_true(graph_rows[0].contains("\"weight\":20"))
    }
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
  } else if variant == "shortest_ids" || variant == "shortest_relation_selector" {
    assert_true(graph_rows[0].contains("\"source_id\":1"))
    assert_true(graph_rows[0].contains("\"target_id\":1"))
    assert_true(graph_rows[1].contains("\"source_id\":1"))
    assert_true(graph_rows[1].contains("\"target_id\":2"))
    assert_true(graph_rows[2].contains("\"source_id\":2"))
    assert_true(graph_rows[2].contains("\"target_id\":1"))
    assert_true(graph_rows[3].contains("\"source_id\":2"))
    assert_true(graph_rows[3].contains("\"target_id\":2"))
  } else if variant == "shortest_nearest_per_source" {
    assert_true(graph_rows[0].contains("\"source_id\":1"))
    assert_true(graph_rows[0].contains("\"target_id\":2"))
    assert_true(graph_rows[0].contains("\"hop_count\":1"))
    assert_true(graph_rows[1].contains("\"source_id\":2"))
    assert_true(graph_rows[1].contains("\"target_id\":2"))
    assert_true(graph_rows[1].contains("\"hop_count\":0"))
  } else if variant == "shortest_nearest_pair" {
    assert_true(graph_rows[0].contains("\"source_id\":1"))
    assert_true(graph_rows[0].contains("\"target_id\":1"))
    assert_true(graph_rows[0].contains("\"hop_count\":0"))
  } else if variant == "shortest_predicate" {
    assert_true(graph_rows[0].contains("\"source_id\":1"))
    assert_true(graph_rows[0].contains("\"target_id\":2"))
    assert_true(graph_rows[1].contains("\"source_id\":2"))
    assert_true(graph_rows[1].contains("\"target_id\":2"))
  } else if variant.has_prefix("shortest_") && expected_rows > 0 {
    assert_true(graph_rows[0].contains("\"source_id\":1"))
    if variant == "shortest_zero" {
      assert_true(graph_rows[0].contains("\"target_id\":1"))
      assert_true(graph_rows[0].contains("\"total_cost\":0"))
      assert_true(graph_rows[0].contains("\"hop_count\":0"))
      assert_true(graph_rows[0].contains("\"node_ids\":[1]"))
    } else {
      assert_true(graph_rows[0].contains("\"target_id\":2"))
      assert_true(
        graph_rows[0].contains(
          if variant == "shortest_weighted" {
            "\"total_cost\":10"
          } else {
            "\"total_cost\":1"
          },
        ),
      )
      assert_true(graph_rows[0].contains("\"hop_count\":1"))
      assert_true(graph_rows[0].contains("\"node_ids\":[1,2]"))
    }
  } else if variant == "traverse_type_miss" ||
    variant == "traverse_type_empty" ||
    variant == "traverse_types_miss" ||
    variant == "shortest_type_miss" ||
    variant == "shortest_type_empty" ||
    variant == "traverse_pattern_predicate_empty" ||
    variant == "traverse_pattern_multi_paths_empty" ||
    variant == "traverse_type_empty_paths" {
    ()
  } else if traverse_paths {
    if variant == "traverse_zero_paths" {
      assert_true(graph_rows[0].contains("\"start_id\":1"))
      assert_true(graph_rows[0].contains("\"end_id\":1"))
      assert_true(graph_rows[0].contains("\"hop_count\":0"))
      assert_true(graph_rows[0].contains("\"node_ids\":[1]"))
      assert_true(graph_rows[0].contains("\"edge_ids\":[]"))
    } else if variant == "traverse_in_paths" {
      assert_true(graph_rows[0].contains("\"start_id\":1"))
      assert_true(graph_rows[0].contains("\"end_id\":2"))
      assert_true(graph_rows[0].contains("\"hop_count\":1"))
      assert_true(graph_rows[0].contains("\"node_ids\":[1,2]"))
      assert_true(
        graph_rows[0].contains(
          "\"edge_ids\":[{\"dst\":1,\"rel\":null,\"src\":2}]",
        ),
      )
    } else if variant == "traverse_both_paths" {
      assert_true(graph_rows[0].contains("\"start_id\":1"))
      assert_true(graph_rows[0].contains("\"end_id\":2"))
      assert_true(graph_rows[1].contains("\"start_id\":1"))
      assert_true(graph_rows[1].contains("\"end_id\":2"))
      assert_true(graph_rows[0].contains("\"hop_count\":1"))
      assert_true(graph_rows[1].contains("\"hop_count\":1"))
    } else if variant == "traverse_pattern_multi_paths" {
      assert_true(graph_rows[0].contains("\"start_id\":1"))
      assert_true(graph_rows[0].contains("\"end_id\":3"))
      assert_true(graph_rows[0].contains("\"hop_count\":2"))
      assert_true(graph_rows[0].contains("\"node_ids\":[1,2,3]"))
      assert_true(
        graph_rows[0].contains(
          "\"edge_ids\":[{\"dst\":2,\"rel\":\"owns\",\"src\":1}," +
          "{\"dst\":3,\"rel\":\"blocks\",\"src\":2}]",
        ),
      )
    } else {
      assert_true(graph_rows[0].contains("\"start_id\":1"))
      assert_true(graph_rows[0].contains("\"end_id\":2"))
      assert_true(graph_rows[0].contains("\"hop_count\":1"))
      assert_true(graph_rows[0].contains("\"node_ids\":[1,2]"))
      assert_true(
        graph_rows[0].contains(
          "\"edge_ids\":[{\"dst\":2,\"rel\":null,\"src\":1}]",
        ),
      )
    }
  } else if variant.has_prefix("traverse_") {
    if variant == "traverse_ids" || traverse_relation_selector {
      assert_true(graph_rows[0].contains("\"start_id\":1"))
      assert_true(graph_rows[0].contains("\"node_id\":2"))
      assert_true(graph_rows[1].contains("\"start_id\":2"))
      assert_true(graph_rows[1].contains("\"node_id\":1"))
    } else if variant == "traverse_predicate" {
      assert_true(graph_rows[0].contains("\"start_id\":1"))
      assert_true(graph_rows[0].contains("\"node_id\":2"))
      assert_true(graph_rows[0].contains("\"depth\":1"))
      assert_true(graph_rows[1].contains("\"start_id\":2"))
      assert_true(graph_rows[1].contains("\"node_id\":1"))
    } else if variant == "traverse_pattern_multi" {
      assert_true(graph_rows[0].contains("\"start_id\":1"))
      assert_true(graph_rows[0].contains("\"node_id\":3"))
      assert_true(graph_rows[0].contains("\"depth\":2"))
    } else if variant.has_prefix("traverse_pattern_") &&
      variant != "traverse_pattern_one" {
      assert_true(graph_rows[0].contains("\"start_id\":2"))
      assert_true(graph_rows[0].contains("\"node_id\":1"))
      assert_true(graph_rows[0].contains("\"depth\":1"))
    } else {
      assert_true(graph_rows[0].contains("\"start_id\":1"))
      assert_true(graph_rows[0].contains("\"node_id\":2"))
      assert_true(graph_rows[0].contains("\"depth\":1"))
    }
  } else if variant == "match_nodes_predicate" {
    assert_true(graph_rows[0].contains("\"id\":2"))
    assert_true(graph_rows[0].contains("\"node_name\":\"second\""))
  } else if variant == "subgraph_edges_false" {
    ()
  } else if variant == "subgraph_edge_predicate" {
    assert_true(graph_rows[0].contains("\"src\":2"))
    assert_true(graph_rows[0].contains("\"weight\":20"))
  } else if variant.has_prefix("subgraph_") {
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
  } else if variant == "graph_diff" {
    assert_true(graph_rows[0].contains("\"version\":\"actql-graph-delta/0.1\""))
    assert_true(graph_rows[0].contains("\"add\":[]"))
    assert_true(graph_rows[0].contains("\"remove\":[]"))
    assert_true(graph_rows[0].contains("\"update\":[]"))
  } else if graph_diff_changes {
    assert_true(graph_rows[0].contains("\"version\":\"actql-graph-delta/0.1\""))
    assert_true(graph_rows[0].contains("\"node_name\":\"changed\""))
    assert_true(graph_rows[0].contains("\"node_name\":\"third\""))
    assert_true(graph_rows[0].contains("\"id\":2"))
    assert_true(graph_rows[0].contains("\"weight\":11"))
    assert_true(graph_rows[0].contains("\"weight\":30"))
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
  if separate_graph_task {
    (graph_ops.cleanup_refresh)() |> ignore
  } else {
    assert_false((graph_ops.cleanup_refresh)())
    assert_true((graph_ops.cleanup_refresh)())
    assert_eq(cleanup_attempts.val, 2)
  }
  match physical_cleanup.val {
    Some(cleanup) => cleanup()
    None => ()
  }
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
fn run_standard_host_mixed_graph_relation_path(
  variant? : String = "normalize_filter",
  execution_quantum? : Int = 0,
  cancel_take_after? : Int = 0,
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_graph_chain=true,
    local_carrier_graph_variant=variant,
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 30000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 800000L,
      retained_bytes: 96000000L,
      execution_bytes: 402653184L,
    }),
  )
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  if variant == "normalize_take" {
    let mut keyed_take = false
    for position in 0..<@execution.generated_sequence_step_count(sequences[4]) {
      if @execution.generated_sequence_step_at(sequences[4], position)
        is Some(@lower.RowStep(candidate)) &&
        @lower.kernel_take(candidate) is Some(_) &&
        @lower.node_at(
          @lower.bound_preparation(
            @execution.generated_sequence_owner(sequences[4]),
          ),
          position,
        )
        is Some(node) {
        keyed_take = @lower.order_node_id(node) is Some(_)
      }
    }
    assert_true(keyed_take)
  }
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
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
        ..retained_attempt_wire_limits(),
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
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
    obligations?=graph_publication_obligations(run, true),
  )
  let values_rows = local_managed_test_rows(values_ops)
  let construction_inputs = Array::makei(2, _ => {
    @local_driver.local_managed_relation_output(values)
  })
  let construction_rows = Array::makei(2, _ => values_rows)
  let (construction_ops, construction, construction_material) = run_local_managed_carrier_test_task(
    installed,
    run,
    2,
    construction_inputs,
    construction_rows,
    obligations?=graph_publication_obligations(run, true),
  )
  let (normalize_ops, normalized, normalized_material) = run_local_managed_carrier_test_task(
    installed,
    run,
    3,
    [
      @local_driver.local_managed_carrier_output(
        construction, construction_material,
      ),
    ],
    [],
    obligations?=graph_publication_obligations(run, true),
  )
  let projected_live = Ref(true)
  let (projected_ops, projected) = run_local_managed_test_task(
    installed,
    run,
    4,
    [],
    [],
    4,
    projected_live,
    carrier_inputs=[(normalized, normalized_material)],
    obligations?=graph_publication_obligations(run, true),
  )
  let projected_rows = local_managed_test_rows(projected_ops)
  if cancel_take_after > 0 {
    let cancelled_ops = start_local_managed_test_task_operations(
      installed,
      run,
      5,
      [projected],
      [projected_rows],
      obligations?=graph_publication_obligations(run, true),
    )
    for _ in 0..<cancel_take_after {
      let observation = (cancelled_ops.advance)(1).unwrap()
      assert_false(observation.complete)
      assert_true(observation.work <= 1L)
    }
    assert_true((cancelled_ops.request_cancel)())
    assert_true((cancelled_ops.advance)(1) is Err(_))
    assert_true((cancelled_ops.execution_stopped)())
    assert_true((cancelled_ops.material)() is None)
    (cancelled_ops.settle)().unwrap()
    @strategy.close_captured_task_output(run, 5)
    (cancelled_ops.close)()
    (cancelled_ops.cleanup_refresh)() |> ignore
    projected_live.val = false
    @strategy.close_captured_task_output(run, 4)
    (projected_ops.close)()
    (projected_ops.cleanup_refresh)() |> ignore
    @strategy.close_captured_task_output(run, 3)
    (normalize_ops.close)()
    (normalize_ops.cleanup_refresh)() |> ignore
    @strategy.close_captured_task_output(run, 2)
    (construction_ops.close)()
    (construction_ops.cleanup_refresh)() |> ignore
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
    return
  }
  let filtered_live = Ref(true)
  let execution_advances = Ref(0)
  let filtered_obligations = graph_publication_obligations(run, true).unwrap()
  let (filtered_ops, filtered) = run_local_managed_test_task(
    installed,
    run,
    5,
    [projected],
    [projected_rows],
    5,
    filtered_live,
    obligations=filtered_obligations,
    execution_quantum~,
    execution_advances=Some(execution_advances),
  )
  if execution_quantum == 1 {
    assert_true(execution_advances.val > 1)
  }
  let filtered_rows = local_managed_test_rows(filtered_ops)
  let expected_rows = if variant == "normalize_take" ||
    variant == "subgraph_filter" {
    1
  } else if variant == "normalize_filter_false" {
    0
  } else {
    2
  }
  assert_eq(filtered_rows.length(), expected_rows)
  if variant == "normalize_filter_false" {
    assert_true(filtered_rows.is_empty())
  } else if variant == "normalize_filter" {
    assert_eq(filtered_rows, projected_rows)
    assert_true(filtered_rows[0].contains("\"id\":1"))
    assert_true(filtered_rows[1].contains("\"id\":2"))
  } else if variant == "normalize_select" {
    assert_true(filtered_rows[0].contains("\"id\":1"))
    assert_true(filtered_rows[1].contains("\"id\":2"))
  } else if variant == "normalize_derive" {
    assert_true(filtered_rows[0].contains("\"copy\":1"))
    assert_true(filtered_rows[1].contains("\"copy\":2"))
  } else if variant == "normalize_take" {
    assert_true(filtered_rows[0].contains("\"id\":1"))
  } else if variant == "normalize_sort" {
    assert_true(filtered_rows[0].contains("\"id\":2"))
    assert_true(filtered_rows[1].contains("\"id\":1"))
  } else if variant == "normalize_assert" {
    assert_eq(filtered_rows, projected_rows)
  } else if variant == "normalize_unique" {
    assert_eq(filtered_rows, projected_rows)
  } else if variant == "subgraph_filter" {
    assert_eq(filtered_rows, projected_rows)
    assert_true(filtered_rows[0].contains("\"id\":2"))
  } else {
    assert_true(filtered_rows[0].contains("\"src\":1"))
    assert_true(filtered_rows[1].contains("\"src\":2"))
  }
  if variant == "subgraph_filter" {
    let publication = @execution.managed_obligations_identities(
      filtered_obligations,
    ).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    })
    assert_eq(publication.length(), 1)
    match
      @execution.managed_completed_identity_requirement_status(
        filtered,
        publication[0],
      ) {
      Some(@execution.EstablishedSourceRetained(contract, cid)) => {
        assert_eq(
          contract,
          @execution.logical_relation_canonical_contract_cid(),
        )
        assert_eq(
          cid, "sha256:a2151218d0638a59beb6b366fa8f2d0803e643139fd8c19cae1f9c8d6044f78f",
        )
      }
      _ => fail("selected subgraph lost its named Relation identity")
    }
  }
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    6,
    [filtered],
    [filtered_rows],
    6,
    first_live,
    obligations?=graph_publication_obligations(run, true),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    7,
    [filtered],
    [filtered_rows],
    7,
    second_live,
    obligations?=graph_publication_obligations(run, true),
  )
  assert_eq(local_managed_test_rows(first_ops).length(), expected_rows)
  assert_eq(local_managed_test_rows(second_ops).length(), expected_rows)
  first_live.val = false
  @strategy.close_captured_task_output(run, 6)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(filtered))
  second_live.val = false
  @strategy.close_captured_task_output(run, 7)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  filtered_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (filtered_ops.close)()
  (filtered_ops.cleanup_refresh)() |> ignore
  projected_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (projected_ops.close)()
  (projected_ops.cleanup_refresh)() |> ignore
  @strategy.close_captured_task_output(run, 3)
  (normalize_ops.close)()
  (normalize_ops.cleanup_refresh)() |> ignore
  @strategy.close_captured_task_output(run, 2)
  (construction_ops.close)()
  (construction_ops.cleanup_refresh)() |> ignore
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
test "standard Host composes Graph projection and Relation filter" {
  run_standard_host_mixed_graph_relation_path()
}

///|
test "standard Host suppresses rows after a Graph projection and false filter" {
  run_standard_host_mixed_graph_relation_path(variant="normalize_filter_false")
}

///|
test "standard Host composes Graph edge projection and Relation filter" {
  run_standard_host_mixed_graph_relation_path(variant="edge_projection_filter")
}

///|
test "standard Host composes Graph projection and Relation select" {
  run_standard_host_mixed_graph_relation_path(variant="normalize_select")
}

///|
test "standard Host composes Graph projection and Relation derive" {
  run_standard_host_mixed_graph_relation_path(variant="normalize_derive")
}

///|
test "standard Host composes Graph projection and Relation take" {
  for quantum in [1, 2, 7, 1024] {
    run_standard_host_mixed_graph_relation_path(
      variant="normalize_take",
      execution_quantum=quantum,
    )
  }
}

///|
test "standard Host composes Graph projection and bounded Relation sort" {
  for quantum in [1, 7, 1024] {
    run_standard_host_mixed_graph_relation_path(
      variant="normalize_sort",
      execution_quantum=quantum,
    )
  }
}

///|
test "standard Host composes Graph projection and bounded Relation assertion" {
  for quantum in [1, 7, 1024] {
    run_standard_host_mixed_graph_relation_path(
      variant="normalize_assert",
      execution_quantum=quantum,
    )
  }
}

///|
test "standard Host composes Graph projection and bounded unique assertion" {
  for quantum in [1, 7, 1024] {
    run_standard_host_mixed_graph_relation_path(
      variant="normalize_unique",
      execution_quantum=quantum,
    )
  }
}

///|
test "standard Host cancels ordered Graph projection take before completion" {
  run_standard_host_mixed_graph_relation_path(
    variant="normalize_take",
    cancel_take_after=18,
  )
}

///|
test "standard Host runs bounded Graph relation paths with two consumers" {
  run_standard_host_graph_relation_path("concise_projection", publication=true)
  run_standard_host_graph_relation_path("split_projection", publication=true)
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
  run_standard_host_graph_relation_path("graph_diff")
  run_standard_host_graph_relation_path("graph_diff_changes", publication=true)
}

///|
test "standard Host retains Graph across physical task boundaries" {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_graph_chain=true,
    local_carrier_graph_variant="projection",
    managed_publication=true,
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  assert_eq(sequences.length(), 5)
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
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
        ..retained_attempt_wire_limits(),
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
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
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let values_rows = local_managed_test_rows(values_ops)
  assert_eq(@strategy.captured_next_managed_producers(run), [1, 1])
  assert_eq(
    @strategy.captured_next_managed_operation_input(run, 0),
    Some((0, 0)),
  )
  assert_eq(
    @strategy.captured_next_managed_operation_input(run, 1),
    Some((0, 1)),
  )
  let (graph_ops, graph, graph_material) = run_local_managed_carrier_test_task(
    installed,
    run,
    2,
    [
      @local_driver.local_managed_relation_output(values),
      @local_driver.local_managed_relation_output(values),
    ],
    [values_rows, values_rows],
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let output_live = Ref(true)
  let output_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (output_ops, output) = run_local_managed_test_task(
    installed,
    run,
    3,
    [],
    [],
    3,
    output_live,
    obligations=output_obligations,
    carrier_inputs=[(graph, graph_material)],
  )
  let rows = local_managed_test_rows(output_ops)
  assert_eq(rows.length(), 2)
  assert_true(rows[0].contains("\"id\":1"))
  assert_true(rows[1].contains("\"node_name\":\"second\""))
  let requirements = @execution.managed_obligations_identities(
    output_obligations,
  )
  let published = requirements.filter(requirement => {
    requirement.domain == @execution.LogicalRelation &&
    requirement.subject == @execution.NamedResult
  })
  assert_eq(published.length(), 1)
  match
    @execution.managed_completed_identity_requirement_status(
      output,
      published[0],
    ) {
    Some(@execution.EstablishedSourceRetained(contract, cid)) => {
      assert_eq(contract, @execution.logical_relation_canonical_contract_cid())
      assert_eq(cid, graph_relation_publication_cid("projection"))
    }
    _ => fail("Graph output did not establish publication identity")
  }

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [output],
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
    [output],
    [rows],
    5,
    second_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  assert_eq(local_managed_test_rows(first_ops).length(), 2)
  assert_eq(local_managed_test_rows(second_ops).length(), 2)

  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(output))

  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  output_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (output_ops.close)()
  (output_ops.cleanup_refresh)() |> ignore
  @strategy.close_captured_task_output(run, 2)
  (graph_ops.close)()
  (graph_ops.cleanup_refresh)() |> ignore
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
test "standard Host traverses a Graph for two consumers" {
  run_standard_host_graph_relation_path("traverse_out", publication=true)
}

///|
test "standard Host emits traversal paths for two consumers" {
  run_standard_host_graph_relation_path("traverse_paths", publication=true)
}

///|
test "standard Host emits paths from a Relation start selector" {
  run_standard_host_graph_relation_path(
    "traverse_relation_paths",
    publication=true,
  )
}

///|
test "standard Host emits paths from a predicate start selector" {
  run_standard_host_graph_relation_path(
    "traverse_predicate_paths",
    publication=true,
  )
}

///|
test "standard Host traverses sorted unique literal starts" {
  run_standard_host_graph_relation_path("traverse_ids")
}

///|
test "standard Host traverses predicate-selected starts" {
  run_standard_host_graph_relation_path("traverse_predicate")
}

///|
test "standard Host traverses Relation-selected starts" {
  run_standard_host_graph_relation_path("traverse_relation_selector")
}

///|
test "standard Host traverses one authored hop" {
  run_standard_host_graph_relation_path("traverse_pattern_one")
}

///|
test "standard Host evaluates authored hop predicates" {
  run_standard_host_graph_relation_path("traverse_pattern_predicate")
  run_standard_host_graph_relation_path("traverse_pattern_all_predicates")
  run_standard_host_graph_relation_path("traverse_pattern_edge_predicate")
  run_standard_host_graph_relation_path("traverse_pattern_node_predicate")
  run_standard_host_graph_relation_path("traverse_pattern_predicate_empty")
}

///|
test "standard Host traverses ordered authored hops" {
  run_standard_host_graph_relation_path("traverse_pattern_multi")
}

///|
test "standard Host emits paths from ordered authored hops" {
  run_standard_host_graph_relation_path(
    "traverse_pattern_multi_paths",
    publication=true,
  )
  run_standard_host_graph_relation_path("traverse_pattern_multi_paths_empty")
}

///|
test "standard Host emits inbound traversal paths" {
  run_standard_host_graph_relation_path("traverse_in_paths")
}

///|
test "standard Host emits bidirectional traversal paths" {
  run_standard_host_graph_relation_path("traverse_both_paths")
}

///|
test "standard Host emits zero-hop traversal paths" {
  run_standard_host_graph_relation_path("traverse_zero_paths")
}

///|
test "standard Host preserves empty path edge types" {
  run_standard_host_graph_relation_path("traverse_type_empty_paths")
}

///|
test "standard Host preserves inbound Graph traversal" {
  run_standard_host_graph_relation_path("traverse_in", publication=true)
}

///|
test "standard Host preserves bidirectional Graph traversal" {
  run_standard_host_graph_relation_path("traverse_both", publication=true)
}

///|
test "standard Host filters Graph traversal by edge type" {
  run_standard_host_graph_relation_path("traverse_type", publication=true)
  run_standard_host_graph_relation_path("traverse_type_miss")
  run_standard_host_graph_relation_path("traverse_type_empty")
  run_standard_host_graph_relation_path("traverse_types_match")
  run_standard_host_graph_relation_path("traverse_types_miss")
}

///|
test "standard Host grafts two Graphs before the Relation bridge" {
  run_standard_host_graph_relation_path("graft", publication=true)
}

///|
test "standard Host unions a repeated Graph list before the Relation bridge" {
  run_standard_host_graph_relation_path("union", publication=true)
  run_standard_host_graph_relation_path("union_singleton")
  run_standard_host_graph_relation_path("union_numeric")
  run_standard_host_graph_relation_path("union_set")
}

///|
test "standard Host averages a repeated Graph list before projection" {
  run_standard_host_graph_relation_path("mean", publication=true)
}

///|
test "standard Host subtracts a property-free Graph before projection" {
  run_standard_host_graph_relation_path("subtract", publication=true)
  run_standard_host_graph_relation_path("subtract_exact", publication=true)
  run_standard_host_graph_relation_path("subtract_numeric")
}
