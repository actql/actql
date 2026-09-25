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
fn carrier_graph_binary_relation_owner(
  source : @lower.BoundPrepared,
  operation : String,
) -> @lower.BoundPrepared {
  let graph = "{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":[\"weight\"]}}"
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":" +
      graph +
      ",\"as\":\"left\"},{\"graph\":" +
      graph +
      ",\"as\":\"right\"},{\"from\":\"left\"," +
      "\"" +
      operation +
      "\":{\"with\":\"right\"}}]",
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
fn carrier_graph_diff_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  carrier_graph_binary_relation_owner(source, "graph_diff")
}

///|
fn carrier_graph_delta_owner(
  left_source : @lower.BoundPrepared,
  right_source : @lower.BoundPrepared,
  wide? : Bool = false,
) -> @lower.BoundPrepared {
  let graph = fn(rows : String) {
    "{\"nodes\":{\"from\":\"" +
    rows +
    "\",\"id\":\"id\",\"fields\":" +
    (if wide {
      "[\"node_name\",\"node_label\",\"node_tag\"]"
    } else {
      "[\"node_name\"]"
    }) +
    "}," +
    "\"edges\":{\"from\":\"" +
    rows +
    "\",\"source\":\"src\",\"target\":\"dst\"," +
    "\"fields\":" +
    (if wide { "[\"weight\",\"edge_note\"]" } else { "[\"weight\"]" }) +
    "}}"
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":" +
      graph("left_rows") +
      ",\"as\":\"left\"},{\"graph\":" +
      graph("right_rows") +
      ",\"as\":\"right\"},{\"from\":\"left\"," +
      "\"graph_diff\":{\"with\":\"right\"}}]",
    ),
    [
      (
        "left_rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(left_source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
      (
        "right_rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(right_source)),
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
fn carrier_graph_apply_owner(
  graph_owner : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let producer = @lower.pipeline(@lower.bound_preparation(graph_owner))
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"g\",\"apply_graph_delta\":{\"with\":\"d\",\"field\":\"delta\"}," +
      "\"as\":\"restored\"},{\"from\":\"restored\",\"node_rows\":true}]",
    ),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(producer, @pipeline.Step(0)).unwrap(),
        ),
      ),
      (
        "d",
        @pipeline.ProducedInput(
          @pipeline.produced_input(producer, @pipeline.Step(2)).unwrap(),
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
  start_json? : String = "",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"reach\":{\"start\":" +
      (if start_json == "" { start.to_string() } else { start_json }) +
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
fn carrier_graph_shortest_owner_with_endpoints(
  source : @lower.BoundPrepared,
  source_endpoint : String,
  target_endpoint : String,
  maximum : Int,
  labeled? : Bool = false,
  edge_types? : String = "",
  weight? : String = "",
  selection? : String = "",
  max_output_rows? : Int = 1,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":" +
      (if labeled { "[]" } else { "[\"node_name\"]" }) +
      "},\"edges\":{\"from\":\"rows\",\"source\":\"src\"," +
      "\"target\":\"dst\"," +
      (if labeled { "\"label\":\"rel\"," } else { "" }) +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"shortest_path\":{\"source\":" +
      source_endpoint +
      ",\"target\":" +
      target_endpoint +
      selection +
      ",\"direction\":\"out\",\"max_hops\":" +
      maximum.to_string() +
      edge_types +
      weight +
      ",\"max_output_rows\":" +
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
fn carrier_graph_shortest_owner(
  source : @lower.BoundPrepared,
  source_id : Int,
  target_id : Int,
  maximum : Int,
  labeled? : Bool = false,
  edge_types? : String = "",
  weight? : String = "",
) -> @lower.BoundPrepared {
  carrier_graph_shortest_owner_with_endpoints(
    source,
    source_id.to_string(),
    target_id.to_string(),
    maximum,
    labeled~,
    edge_types~,
    weight~,
  )
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
fn carrier_graph_storage_limits_for_scratch(
  workspace : Int,
  bytes : Int,
) -> @graph_storage.Limits {
  let limits = carrier_graph_storage_limits()
  {
    max_input_rows: limits.max_input_rows,
    max_nodes: limits.max_nodes,
    max_edges: limits.max_edges,
    max_value_bytes: limits.max_value_bytes,
    max_total_value_bytes: bytes,
    max_retained_value_bytes: limits.max_retained_value_bytes,
    max_value_nodes: limits.max_value_nodes,
    max_value_depth: limits.max_value_depth,
    max_contract_work: limits.max_contract_work,
    max_work: limits.max_work,
    max_workspace_slots: workspace,
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
        }
      @local_bridge.Stopped(_, ..) => abort("graph-to-rows stopped")
    }
  }
  abort("unreachable")
}

///|
fn finish_graph_diff(
  execution : @local_sga.GraphDiffExecution,
) -> @execution.CompletedOutput {
  while true {
    match @local_sga.advance_graph_diff(execution, 1).unwrap() {
      @local_sga.GraphDiffContinue(..) => ()
      @local_sga.GraphDiffComplete(output, ..) => return output
      @local_sga.GraphDiffFailed(_, ..) => abort("graph diff failed")
      @local_sga.GraphDiffStopped(_, ..) => abort("graph diff stopped")
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
  quantum? : Int = 1,
) -> Result[@execution.CompletedOutput, @local_sga.TraverseIssue] {
  while true {
    let poll = match @local_sga.advance_traverse(execution, quantum) {
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
fn finish_shortest(
  execution : @local_sga.ShortestExecution,
) -> Result[@execution.CompletedOutput, @local_sga.ShortestIssue] {
  while true {
    let poll = match @local_sga.advance_shortest(execution, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      @local_sga.ShortestContinue(..) => ()
      @local_sga.ShortestComplete(output, ..) => return Ok(output)
      @local_sga.ShortestFailed(issue, ..) => return Err(issue)
      @local_sga.ShortestStopped(_, ..) =>
        return Err(@local_sga.ShortestExecutionIssue(@bounded.Terminal))
    }
  }
  Err(@local_sga.ShortestExecutionIssue(@bounded.Terminal))
}

///|
fn weighted_shortest_result(
  rows : String,
  source_id : Int,
  target_id : Int,
  max_hops : Int,
  workspace? : Int = 1000,
) -> Result[@execution.CompletedOutput, @local_sga.ShortestIssue] raise {
  weighted_shortest_endpoint_result(
    rows,
    source_id.to_string(),
    target_id.to_string(),
    max_hops,
    workspace~,
  )
}

///|
fn weighted_shortest_endpoint_result(
  rows : String,
  source_endpoint : String,
  target_endpoint : String,
  max_hops : Int,
  workspace? : Int = 1000,
  selection? : String = "",
  max_rows? : Int = 1,
) -> Result[@execution.CompletedOutput, @local_sga.ShortestIssue] raise {
  let source_owner = carrier_graph_source_owner_with_rows(rows)
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_shortest_owner_with_endpoints(
    source_owner,
    source_endpoint,
    target_endpoint,
    max_hops,
    weight=",\"weight\":\"weight\"",
    selection~,
    max_output_rows=max_rows,
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
  let execution = match
    @local_sga.start_shortest(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      input,
      max_rows,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
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
  let result = finish_shortest(execution)
  assert_eq(@local_sga.cleanup_shortest(execution), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  result
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
test "graph diagnostics yield during long identity ordering" {
  let prefix = "z".repeat(160)
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
  let owner = carrier_graph_bounds_owner(source_owner, "{\"max_degree\":0}")
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
  let start = fn(control, work_limit) raise {
    @local_sga.start_graph_bounds(
      control,
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
      control_work_limit=Some(work_limit),
    )
  }
  // Two node and two edge scans cost four steps. Merge preparation costs two
  // steps, the first differing UTF-16 unit costs 161, and copying costs two.
  // Four candidate checks, two four-field rows, and finish cost fifteen more.
  // The independent total is 4 + 2 + 161 + 2 + 4 + 10 + 1 = 184.
  let control = @bounded.control()
  let execution = start(control, 184).unwrap()
  for _ in 0..<60 {
    assert_true(
      @local_sga.advance_graph_bounds(execution, 1).unwrap()
      is @local_sga.GraphBoundsContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_graph_bounds(execution, 1).unwrap()
    is @local_sga.GraphBoundsStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_graph_bounds(execution), Ok(true))
  assert_true(@graphs.producer_read_available(input))
  let completed = start(@bounded.control(), 184).unwrap()
  let output = finish_graph_bounds(completed).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(
    @execution.completed_cell(output, 0, 3) is Some(Text(id)) && id == first,
  )
  assert_true(
    @execution.completed_cell(output, 1, 3) is Some(Text(id)) && id == second,
  )
  assert_eq(@local_sga.cleanup_graph_bounds(completed), Ok(true))
  let one_short = start(@bounded.control(), 183).unwrap()
  assert_true(
    finish_graph_bounds(one_short) is Err(@local_sga.GraphBoundsWorkLimit),
  )
  assert_eq(@local_sga.cleanup_graph_bounds(one_short), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(source))
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
  assert_true(
    @local_sga.advance_graph_bounds(execution, 1).unwrap()
    is @local_sga.GraphBoundsContinue(progress=0L, work=1L),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_graph_bounds(execution, 1).unwrap()
    is @local_sga.GraphBoundsStopped(_, progress=0L, work=1L),
  )
  assert_true(@local_sga.graph_bounds_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_graph_bounds(execution), Ok(true))
  assert_false(@local_sga.graph_bounds_cleanup_pending(execution))
  assert_true(@execution.producer_read_available(external))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "graph bounds admits exact value and control work" {
  let source_owner = carrier_graph_source_owner_with_rows(
    "[{\"id\":1,\"src\":1,\"dst\":1," + "\"node_name\":\"only\",\"weight\":10}]",
  )
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_bounds_owner(source_owner, "{\"max_nodes\":0}")
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
  let start = fn(max_work, workspace, control_work_limit) {
    @local_sga.start_graph_bounds(
      @bounded.control(),
      completion,
      sequence,
      1,
      input,
      1,
      { max_nodes: 5, max_text_bytes: 25, max_depth: 10, max_work, },
      workspace,
      1000,
      1000,
      [external],
      control_work_limit=Some(control_work_limit),
    )
  }
  // One node needs 3 index slots; four result fields need four more.
  assert_true(start(30, 6, 11) is Err(@local_sga.GraphBoundsWorkspaceLimit))
  let exact = start(30, 7, 11).unwrap()
  let output = finish_graph_bounds(exact).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Text("nodes")))
  assert_eq(@local_sga.cleanup_graph_bounds(exact), Ok(true))
  // The row object and four scalar values cost five nodes. Four field names
  // cost 4+7+6+3 bytes, and the only text value, "nodes", costs five more.
  // Thus the independent value-work bound is 5 + 20 + 5 = 30.
  let short = start(29, 7, 11).unwrap()
  assert_true(
    finish_graph_bounds(short)
    is Err(@local_sga.GraphBoundsOutput(@execution.CaptureLimit)),
  )
  assert_eq(@local_sga.cleanup_graph_bounds(short), Ok(true))
  // With one node and one edge, the bounded phases spend: initialize 1,
  // scan 1, inspect three candidates, build four fields, commit 1, finish 1.
  // The cumulative control-work requirement is exactly 11, independent of
  // the output-value work budget of 30.
  let control_short = start(30, 7, 10).unwrap()
  assert_true(
    finish_graph_bounds(control_short) is Err(@local_sga.GraphBoundsWorkLimit),
  )
  assert_eq(@local_sga.cleanup_graph_bounds(control_short), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
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
    let start = fn(workspace, control_work_limit, value_work_limit) {
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
          max_work: value_work_limit,
        },
        workspace,
        1000,
        1000,
        [external],
        control_work_limit=Some(control_work_limit),
      )
    }
    assert_true(
      start(7, 18, 10000) is Err(@local_sga.GraphBoundsWorkspaceLimit),
    )
    let execution = start(8, 18, 10000).unwrap()
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
    // Two nodes and two edges cost four steps. Sorting the two nodes takes
    // three merge steps and two copy steps. The two selected rows cost two
    // candidate steps, four field reads, two commits, and one finish: 18.
    let one_short = start(8, 17, 10000).unwrap()
    assert_true(
      finish_graph_degree(one_short) is Err(@local_sga.GraphBoundsWorkLimit),
    )
    assert_eq(@local_sga.cleanup_graph_degree(one_short), Ok(true))
    // Each of two rows has an object and two scalar values: six nodes.
    // The "node" and "degree" field names cost 4 + 6 bytes per row.
    // The independently calculated value-work requirement is 6 + 20 = 26.
    let value_exact = start(8, 18, 26).unwrap()
    let value_output = finish_graph_degree(value_exact).unwrap()
    assert_eq(@execution.completed_row_count(value_output), 2)
    assert_eq(@local_sga.cleanup_graph_degree(value_exact), Ok(true))
    let value_short = start(8, 18, 25).unwrap()
    assert_true(
      finish_graph_degree(value_short)
      is Err(@local_sga.GraphBoundsOutput(@execution.CaptureLimit)),
    )
    assert_eq(@local_sga.cleanup_graph_degree(value_short), Ok(true))
    assert_true(@graphs.discard_completed(graph))
    assert_true(@execution.completed_output_available(output))
  }
}

///|
test "degree diagnostics enforce output capacity before publishing" {
  let source_owner = carrier_graph_source_owner()
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
  let start = fn(max_rows, completion) {
    let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
    @local_sga.start_graph_degree(
      @bounded.control(),
      completion,
      sequence,
      1,
      input,
      max_rows,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      8,
      1000,
      1000,
      [external],
    ).unwrap()
  }
  let exact = start(2, task_test_completion(owner))
  let output = finish_graph_degree(exact).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(@local_sga.cleanup_graph_degree(exact), Ok(true))
  let one_short = start(1, task_test_completion(owner))
  assert_true(
    finish_graph_degree(one_short)
    is Err(@local_sga.GraphBoundsOutput(@execution.CaptureLimit)),
  )
  assert_eq(@local_sga.cleanup_graph_degree(one_short), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
}

///|
test "degree diagnostics stop in flight and reclaim private output" {
  let source_owner = carrier_graph_source_owner()
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
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let control = @bounded.control()
  let execution = @local_sga.start_graph_degree(
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
  assert_true(
    @local_sga.advance_graph_degree(execution, 1).unwrap()
    is @local_sga.GraphDegreeContinue(progress=0L, work=1L),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_graph_degree(execution, 1).unwrap()
    is @local_sga.GraphDegreeStopped(_, progress=0L, work=1L),
  )
  assert_true(@local_sga.graph_degree_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_graph_degree(execution), Ok(true))
  assert_false(@local_sga.graph_degree_cleanup_pending(execution))
  assert_true(@execution.producer_read_available(external))
  assert_true(@graphs.discard_completed(graph))
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
test "empty components admit exact work and workspace and reclaim cancellation" {
  let source_owner = carrier_graph_source_owner_with_rows("[]")
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
    let start = fn(control, workspace, work) raise {
      @local_sga.start_components(
        control,
        task_test_completion(owner),
        sequence,
        1,
        input,
        0,
        {
          max_nodes: 1000,
          max_text_bytes: 1000,
          max_depth: 10,
          max_work: 1000,
        },
        workspace,
        1000,
        1000,
        [external],
        control_work_limit=Some(work),
      )
    }
    // Fifteen slots per node, two per edge, three fields, two fixed slots.
    assert_true(
      start(@bounded.control(), 4, 2)
      is Err(@local_sga.ComponentsWorkspaceLimit),
    )
    let exact = start(@bounded.control(), 5, 2).unwrap()
    assert_true(
      @local_sga.advance_components(exact, 1).unwrap()
      is @local_sga.ComponentsContinue(progress=0L, work=1L),
    )
    let output = match @local_sga.advance_components(exact, 1).unwrap() {
      @local_sga.ComponentsComplete(output, progress=0L, work=2L) => output
      _ => abort("exact empty components did not complete")
    }
    assert_eq(@execution.completed_row_count(output), 0)
    assert_eq(@local_sga.cleanup_components(exact), Ok(true))
    assert_true(@execution.completed_output_available(output))
    let short = start(@bounded.control(), 5, 1).unwrap()
    assert_true(
      @local_sga.advance_components(short, 1).unwrap()
      is @local_sga.ComponentsContinue(progress=0L, work=1L),
    )
    assert_true(
      @local_sga.advance_components(short, 1).unwrap()
      is @local_sga.ComponentsFailed(@local_sga.ComponentsWorkLimit, ..),
    )
    assert_eq(@local_sga.cleanup_components(short), Ok(true))
    let control = @bounded.control()
    let cancelled = start(control, 5, 2).unwrap()
    assert_true(
      @local_sga.advance_components(cancelled, 1).unwrap()
      is @local_sga.ComponentsContinue(progress=0L, work=1L),
    )
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @local_sga.advance_components(cancelled, 1).unwrap()
      is @local_sga.ComponentsStopped(_, progress=0L, work=1L),
    )
    assert_eq(@local_sga.cleanup_components(cancelled), Ok(true))
    assert_true(@graphs.producer_read_available(input))
    assert_true(@graphs.discard_completed(graph))
  }
  assert_true(@execution.completed_output_available(source))
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
    let limited = @local_sga.start_components(
      @bounded.control(),
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
      control_work_limit=Some(1),
    ).unwrap()
    assert_true(
      @local_sga.advance_components(limited, 100).unwrap()
      is @local_sga.ComponentsFailed(
        @local_sga.ComponentsWorkLimit,
        progress=0L,
        work=1L
      ),
    )
    assert_eq(@local_sga.cleanup_components(limited), Ok(true))
    let active_control = @bounded.control()
    let active = @local_sga.start_components(
      active_control,
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
    assert_true(
      @local_sga.advance_components(active, 1).unwrap()
      is @local_sga.ComponentsContinue(progress=0L, work=1L),
    )
    assert_true(@bounded.request_cancel(active_control))
    assert_true(
      @local_sga.advance_components(active, 1).unwrap()
      is @local_sga.ComponentsStopped(_, progress=0L, work=1L),
    )
    assert_eq(@local_sga.cleanup_components(active), Ok(true))
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
test "weak and strong components yield during long minimum comparisons" {
  let prefix = "m".repeat(160)
  let first = prefix + "a"
  let second = prefix + "b"
  let rows = "[{\"id\":\"" +
    second +
    "\",\"src\":\"" +
    second +
    "\",\"dst\":\"" +
    first +
    "\",\"node_name\":\"second\"," +
    "\"weight\":1},{\"id\":\"" +
    first +
    "\",\"src\":\"" +
    first +
    "\",\"dst\":\"" +
    second +
    "\",\"node_name\":\"first\"," +
    "\"weight\":2}]"
  let source_owner = carrier_graph_source_owner_with_rows(rows, text_id=true)
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
    let start = fn(control) raise {
      @local_sga.start_components(
        control,
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
        39,
        1000,
        1000,
        [external],
      )
    }
    let control = @bounded.control()
    let cancelled = start(control).unwrap()
    for _ in 0..<90 {
      assert_true(
        @local_sga.advance_components(cancelled, 1).unwrap()
        is @local_sga.ComponentsContinue(..),
      )
    }
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @local_sga.advance_components(cancelled, 1).unwrap()
      is @local_sga.ComponentsStopped(_, ..),
    )
    assert_eq(@local_sga.cleanup_components(cancelled), Ok(true))
    assert_true(@graphs.producer_read_available(input))
    let completed = start(@bounded.control()).unwrap()
    let output = finish_components(completed).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(
      @execution.completed_cell(output, 0, 0) is Some(Text(id)) && id == first,
    )
    assert_true(
      @execution.completed_cell(output, 1, 0) is Some(Text(id)) && id == first,
    )
    assert_true(
      @execution.completed_cell(output, 0, 2) is Some(Text(id)) && id == first,
    )
    assert_true(
      @execution.completed_cell(output, 1, 2) is Some(Text(id)) && id == second,
    )
    assert_eq(@local_sga.cleanup_components(completed), Ok(true))
    assert_true(@graphs.discard_completed(graph))
  }
  assert_true(@execution.completed_output_available(source))
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
  // Four nodes, four edges, and four output fields admit 66 slots.
  let start = fn(control, workspace, work) raise {
    @local_sga.start_reach(
      control,
      task_test_completion(owner),
      sequence,
      1,
      @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      workspace,
      1000,
      1000,
      [external],
      control_work_limit=Some(work),
    )
  }
  assert_true(
    start(@bounded.control(), 65, 1) is Err(@local_sga.ReachWorkspaceLimit),
  )
  let limited = start(@bounded.control(), 66, 1).unwrap()
  assert_true(
    @local_sga.advance_reach(limited, 100).unwrap()
    is @local_sga.ReachFailed(@local_sga.ReachWorkLimit, progress=0L, work=1L),
  )
  assert_eq(@local_sga.cleanup_reach(limited), Ok(true))
  let active_control = @bounded.control()
  let active = start(active_control, 66, 10000).unwrap()
  assert_true(
    @local_sga.advance_reach(active, 1).unwrap()
    is @local_sga.ReachContinue(progress=0L, work=1L),
  )
  assert_true(@bounded.request_cancel(active_control))
  assert_true(
    @local_sga.advance_reach(active, 1).unwrap()
    is @local_sga.ReachStopped(_, progress=0L, work=1L),
  )
  assert_eq(@local_sga.cleanup_reach(active), Ok(true))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "reach yields during long typed identity sorting" {
  let prefix = "m".repeat(160)
  let first = prefix + "a"
  let second = prefix + "b"
  let third = prefix + "c"
  let rows = "[{\"id\":\"" +
    third +
    "\",\"src\":\"" +
    first +
    "\",\"dst\":\"" +
    third +
    "\",\"node_name\":\"third\",\"weight\":1},{\"id\":\"" +
    second +
    "\",\"src\":\"" +
    first +
    "\",\"dst\":\"" +
    second +
    "\",\"node_name\":\"second\",\"weight\":2},{\"id\":\"" +
    first +
    "\",\"src\":\"" +
    first +
    "\",\"dst\":\"" +
    first +
    "\",\"node_name\":\"first\",\"weight\":3}]"
  let source_owner = carrier_graph_source_owner_with_rows(rows, text_id=true)
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_reach_owner_with_depth(
    source_owner,
    0,
    "out",
    "1",
    start_json="\"" + first + "\"",
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
  let start = fn(control) raise {
    @local_sga.start_reach(
      control,
      task_test_completion(owner),
      sequence,
      1,
      input,
      3,
      {
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 10,
        max_work: 10000,
      },
      100,
      1000,
      10000,
      [external],
    )
  }
  let control = @bounded.control()
  let cancelled = start(control).unwrap()
  for _ in 0..<90 {
    assert_true(
      @local_sga.advance_reach(cancelled, 1).unwrap()
      is @local_sga.ReachContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_reach(cancelled, 1).unwrap()
    is @local_sga.ReachStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_reach(cancelled), Ok(true))
  assert_true(@graphs.producer_read_available(input))
  let completed = start(@bounded.control()).unwrap()
  let output = finish_reach(completed).unwrap()
  assert_eq(@execution.completed_row_count(output), 3)
  let expected = [first, second, third]
  for index in 0..<expected.length() {
    assert_true(
      @execution.completed_cell(output, index, 2) is Some(Text(id)) &&
      id == expected[index],
    )
  }
  assert_eq(@local_sga.cleanup_reach(completed), Ok(true))
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
  match @local_sga.advance_traverse(cancelled, 1).unwrap() {
    @local_sga.TraverseStopped(_, ..) => ()
    _ => fail("Traversal must stop after cancellation")
  }
  assert_true(@local_sga.traverse_stopped(cancelled))
  assert_true(@local_sga.traverse_cleanup_pending(cancelled))
  assert_eq(@local_sga.cleanup_traverse(cancelled), Ok(true))
  assert_false(@local_sga.traverse_cleanup_pending(cancelled))
  let limited = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 1, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(
    @local_sga.advance_traverse(limited, 100).unwrap()
    is @local_sga.TraverseFailed(
      @local_sga.TraverseReachIssue(@local_sga.ReachWorkLimit),
      progress=0L,
      work=1L
    ),
  )
  assert_eq(@local_sga.cleanup_traverse(limited), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
}

///|
test "scalar shortest path admits workspace before allocation and cancels" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_shortest_owner(source_owner, 1, 3, 2)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    89,
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
    @local_sga.start_shortest(
      @bounded.control(),
      completion,
      sequence,
      1,
      input,
      1,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      88,
      1000,
      1000,
      [external],
    )
    is Err(@local_sga.ShortestWorkspaceLimit),
  )
  let execution = @local_sga.start_shortest(
    @bounded.control(),
    completion,
    sequence,
    1,
    input,
    1,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    89,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_shortest(execution).unwrap()
  assert_eq(@local_sga.cleanup_shortest(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_output_matches_inputs(output, [external]))

  let limited = @local_sga.start_shortest(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    1,
    { max_nodes: 3, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let mut limited_terminal = false
  while !limited_terminal {
    match @local_sga.advance_shortest(limited, 1).unwrap() {
      @local_sga.ShortestContinue(..) => ()
      @local_sga.ShortestFailed(@local_sga.ShortestOutputLimit, ..) =>
        limited_terminal = true
      _ => fail("expected bounded path value rejection")
    }
  }
  assert_eq(@local_sga.shortest_value_item_attempts(limited), 0)
  assert_eq(@local_sga.cleanup_shortest(limited), Ok(true))

  let control = @bounded.control()
  let cancelled = @local_sga.start_shortest(
    control,
    task_test_completion(owner),
    sequence,
    1,
    input,
    1,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    89,
    1000,
    1000,
    [external],
  ).unwrap()
  let mut polls = 0
  let mut attempts = 0
  while attempts == 0 {
    let before = @local_sga.shortest_value_item_attempts(cancelled)
    assert_true(
      @local_sga.advance_shortest(cancelled, 1).unwrap()
      is @local_sga.ShortestContinue(..),
    )
    attempts = @local_sga.shortest_value_item_attempts(cancelled)
    assert_true(attempts - before <= 1)
    polls += 1
    assert_true(polls < 1000)
  }
  assert_true(@bounded.request_cancel(control))
  let attempts_before_stop = @local_sga.shortest_value_item_attempts(cancelled)
  assert_true(
    @local_sga.advance_shortest(cancelled, 1).unwrap()
    is @local_sga.ShortestStopped(_, progress=_, work=_),
  )
  assert_eq(
    @local_sga.shortest_value_item_attempts(cancelled),
    attempts_before_stop,
  )
  assert_true(@local_sga.shortest_stopped(cancelled))
  assert_true(@local_sga.shortest_cleanup_pending(cancelled))
  assert_eq(@local_sga.cleanup_shortest(cancelled), Ok(true))
  assert_false(@local_sga.shortest_cleanup_pending(cancelled))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
}

///|
test "scalar shortest path uses canonical identity ties" {
  let source_owner = carrier_graph_source_owner_with_rows(
    "[{\"id\":4,\"src\":1,\"dst\":4," +
    "\"node_name\":\"four\",\"weight\":10},{\"id\":3," +
    "\"src\":4,\"dst\":3,\"node_name\":\"three\"," +
    "\"weight\":20},{\"id\":2,\"src\":1,\"dst\":2," +
    "\"node_name\":\"two\",\"weight\":30},{\"id\":1," +
    "\"src\":2,\"dst\":3,\"node_name\":\"one\"," +
    "\"weight\":40}]",
  )
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_shortest_owner(source_owner, 1, 3, 2)
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
  let execution = @local_sga.start_shortest(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    1,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    89,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_shortest(execution).unwrap()
  assert_eq(@local_sga.cleanup_shortest(execution), Ok(true))
  let row = @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap()
  assert_true(
    row.contains("\"node_ids\":[1,2,3]") && row.contains("\"hop_count\":2"),
  )
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
}

///|
test "shortest endpoint ordering yields across long typed identities" {
  let prefix = "s".repeat(160)
  let first = prefix + "a"
  let second = prefix + "b"
  let rows = "[{\"id\":\"" +
    second +
    "\",\"src\":\"" +
    second +
    "\",\"dst\":\"" +
    second +
    "\",\"node_name\":\"second\",\"weight\":1}," +
    "{\"id\":\"" +
    first +
    "\",\"src\":\"" +
    first +
    "\",\"dst\":\"" +
    first +
    "\",\"node_name\":\"first\",\"weight\":2}]"
  let source_owner = carrier_graph_source_owner_with_rows(rows, text_id=true)
  let source = carrier_events_source_output(source_owner)
  let endpoints = "{\"ids\":[\"" + second + "\",\"" + first + "\"]}"
  let owner = carrier_graph_shortest_owner_with_endpoints(
    source_owner,
    endpoints,
    endpoints,
    1,
    selection=",\"selection\":\"each_pair\"",
    max_output_rows=4,
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
  let limits : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 10,
    max_work: 20000,
  }
  let control = @bounded.control()
  let cancelled = @local_sga.start_shortest(
    control,
    task_test_completion(owner),
    sequence,
    1,
    input,
    4,
    limits,
    200,
    1000,
    1000,
    [external],
  ).unwrap()
  for _ in 0..<200 {
    assert_true(
      @local_sga.advance_shortest(cancelled, 1).unwrap()
      is @local_sga.ShortestContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_shortest(cancelled, 1).unwrap()
    is @local_sga.ShortestStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_shortest(cancelled), Ok(true))
  assert_true(@graphs.completed_available(graph))
  let completed = @local_sga.start_shortest(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    4,
    limits,
    200,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_shortest(completed).unwrap()
  assert_eq(@local_sga.cleanup_shortest(completed), Ok(true))
  assert_eq(@execution.completed_row_count(output), 2)
  let first_row = @execution.completed_output_row_wire(output, 0, 2000, 100, 10).unwrap()
  let second_row = @execution.completed_output_row_wire(
    output, 1, 2000, 100, 10,
  ).unwrap()
  assert_true(first_row.contains("\"source_id\":\"" + first + "\""))
  assert_true(second_row.contains("\"source_id\":\"" + second + "\""))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "weighted shortest path preserves cost hop and identity order" {
  let cheaper = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"one\",\"weight\":10},{\"id\":2," +
    "\"src\":1,\"dst\":3,\"node_name\":\"two\",\"weight\":1}," +
    "{\"id\":3,\"src\":3,\"dst\":2," +
    "\"node_name\":\"three\",\"weight\":1}]"
  let output = weighted_shortest_result(cheaper, 1, 2, 2).unwrap()
  let row = @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap()
  assert_true(
    row.contains("\"total_cost\":2") &&
    row.contains("\"node_ids\":[1,3,2]") &&
    row.contains("\"hop_count\":2"),
  )
  let one_hop = weighted_shortest_result(cheaper, 1, 2, 1).unwrap()
  let one_hop_row = @execution.completed_output_row_wire(
    one_hop, 0, 1000, 100, 10,
  ).unwrap()
  assert_true(
    one_hop_row.contains("\"total_cost\":10") &&
    one_hop_row.contains("\"node_ids\":[1,2]") &&
    one_hop_row.contains("\"hop_count\":1"),
  )

  let fewer_hops = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"one\",\"weight\":2},{\"id\":2," +
    "\"src\":1,\"dst\":3,\"node_name\":\"two\",\"weight\":1}," +
    "{\"id\":3,\"src\":3,\"dst\":2," +
    "\"node_name\":\"three\",\"weight\":1}]"
  let fewer = weighted_shortest_result(fewer_hops, 1, 2, 2).unwrap()
  let fewer_row = @execution.completed_output_row_wire(fewer, 0, 1000, 100, 10).unwrap()
  assert_true(
    fewer_row.contains("\"total_cost\":2") &&
    fewer_row.contains("\"node_ids\":[1,2]") &&
    fewer_row.contains("\"hop_count\":1"),
  )

  let tied = "[{\"id\":1,\"src\":1,\"dst\":4," +
    "\"node_name\":\"one\",\"weight\":1},{\"id\":4," +
    "\"src\":4,\"dst\":3,\"node_name\":\"four\",\"weight\":1}," +
    "{\"id\":2,\"src\":1,\"dst\":2," +
    "\"node_name\":\"two\",\"weight\":1},{\"id\":3," +
    "\"src\":2,\"dst\":3,\"node_name\":\"three\",\"weight\":1}]"
  let canonical = weighted_shortest_result(tied, 1, 3, 2).unwrap()
  let canonical_row = @execution.completed_output_row_wire(
    canonical, 0, 1000, 100, 10,
  ).unwrap()
  assert_true(canonical_row.contains("\"node_ids\":[1,2,3]"))

  let zero = weighted_shortest_result(cheaper, 1, 1, 2).unwrap()
  let zero_row = @execution.completed_output_row_wire(zero, 0, 1000, 100, 10).unwrap()
  assert_true(
    zero_row.contains("\"total_cost\":0") &&
    zero_row.contains("\"node_ids\":[1]") &&
    zero_row.contains("\"hop_count\":0"),
  )

  let nearest_source = weighted_shortest_endpoint_result(
    cheaper,
    "{\"ids\":[1]}",
    "{\"ids\":[2,3]}",
    2,
    selection=",\"selection\":\"nearest_per_source\"",
  ).unwrap()
  let nearest_source_row = @execution.completed_output_row_wire(
    nearest_source, 0, 1000, 100, 10,
  ).unwrap()
  assert_true(
    nearest_source_row.contains("\"target_id\":3") &&
    nearest_source_row.contains("\"total_cost\":1"),
  )
  let nearest_pair = weighted_shortest_endpoint_result(
    cheaper,
    "{\"ids\":[1,3]}",
    "{\"ids\":[2]}",
    2,
    selection=",\"selection\":\"nearest_pair\"",
  ).unwrap()
  let nearest_pair_row = @execution.completed_output_row_wire(
    nearest_pair, 0, 1000, 100, 10,
  ).unwrap()
  assert_true(
    nearest_pair_row.contains("\"source_id\":3") &&
    nearest_pair_row.contains("\"total_cost\":1"),
  )
}

///|
test "weighted shortest path validates every edge and cost overrange" {
  let invalid = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"one\",\"weight\":1},{\"id\":2," +
    "\"src\":2,\"dst\":2,\"node_name\":\"two\",\"weight\":-1}]"
  assert_true(
    weighted_shortest_result(invalid, 1, 2, 1)
    is Err(@local_sga.ShortestInvalidWeight),
  )

  let overrange = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"one\",\"weight\":1.7976931348623157e308}," +
    "{\"id\":2,\"src\":2,\"dst\":3," +
    "\"node_name\":\"two\",\"weight\":1.7976931348623157e308}," +
    "{\"id\":3,\"src\":3,\"dst\":3," +
    "\"node_name\":\"three\",\"weight\":0}]"
  assert_true(
    weighted_shortest_result(overrange, 1, 3, 2)
    is Err(@local_sga.ShortestCostOverrange),
  )
  assert_true(
    weighted_shortest_endpoint_result(
      overrange,
      "{\"ids\":[1]}",
      "{\"ids\":[2,3]}",
      2,
      selection=",\"selection\":\"each_pair\"",
      max_rows=2,
    )
    is Err(@local_sga.ShortestCostOverrange),
  )

  let finite_alternative = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"one\",\"weight\":1.7976931348623157e308}," +
    "{\"id\":2,\"src\":2,\"dst\":4," +
    "\"node_name\":\"two\",\"weight\":1.7976931348623157e308}," +
    "{\"id\":3,\"src\":1,\"dst\":3," +
    "\"node_name\":\"three\",\"weight\":1},{\"id\":4," +
    "\"src\":3,\"dst\":4,\"node_name\":\"four\",\"weight\":1}]"
  let output = weighted_shortest_result(finite_alternative, 1, 4, 2).unwrap()
  let row = @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap()
  assert_true(
    row.contains("\"total_cost\":2") && row.contains("\"node_ids\":[1,3,4]"),
  )
}

///|
test "weighted shortest path admits workspace before allocation" {
  let rows = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"one\",\"weight\":10},{\"id\":2," +
    "\"src\":1,\"dst\":3,\"node_name\":\"two\",\"weight\":1}," +
    "{\"id\":3,\"src\":3,\"dst\":2," +
    "\"node_name\":\"three\",\"weight\":1}]"
  assert_true(
    weighted_shortest_result(rows, 1, 2, 2, workspace=87)
    is Err(@local_sga.ShortestWorkspaceLimit),
  )
  assert_true(weighted_shortest_result(rows, 1, 2, 2, workspace=88) is Ok(_))

  let source_owner = carrier_graph_source_owner_with_rows(rows)
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_shortest_owner(
    source_owner,
    1,
    2,
    2,
    weight=",\"weight\":\"weight\"",
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
  let cancelled = @local_sga.start_shortest(
    control,
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    1,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    88,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(
    @local_sga.advance_shortest(cancelled, 1).unwrap()
    is @local_sga.ShortestContinue(..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_shortest(cancelled, 1).unwrap()
    is @local_sga.ShortestStopped(_, ..),
  )
  assert_true(@local_sga.shortest_cleanup_pending(cancelled))
  assert_eq(@local_sga.cleanup_shortest(cancelled), Ok(true))
  assert_false(@local_sga.shortest_cleanup_pending(cancelled))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(source))
}

///|
test "scalar shortest path preserves edge type filters" {
  let source_owner = carrier_graph_labeled_source_owner()
  let source = carrier_events_source_output(source_owner)
  for
    (edge_types, expected_rows) in [
      (",\"edge_types\":[\"missing\",\"owns\"]", 1),
      (",\"edge_types\":[\"controls\"]", 0),
      (",\"edge_types\":[]", 0),
    ] {
    let owner = carrier_graph_shortest_owner(
      source_owner,
      1,
      2,
      2,
      labeled=true,
      edge_types~,
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
    let execution = @local_sga.start_shortest(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      input,
      1,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      67,
      1000,
      1000,
      [external],
    ).unwrap()
    let output = finish_shortest(execution).unwrap()
    assert_eq(@local_sga.cleanup_shortest(execution), Ok(true))
    assert_eq(@execution.completed_row_count(output), expected_rows)
    if expected_rows == 1 {
      let row = @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap()
      assert_true(row.contains("\"node_ids\":[1,2]"))
    }
    assert_true(@graphs.discard_completed(graph))
    assert_true(@execution.completed_output_available(output))
  }
}

///|
test "shortest path executes explicit endpoint identity sets" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_shortest_owner_with_endpoints(
    source_owner,
    "{\"ids\":[2,1,2]}",
    "{\"ids\":[4,3,3]}",
    2,
    selection=",\"selection\":\"each_pair\"",
    max_output_rows=4,
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
  let execution = @local_sga.start_shortest(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    89,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_shortest(execution).unwrap()
  assert_eq(@local_sga.cleanup_shortest(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 2)
  let first = @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap()
  let second = @execution.completed_output_row_wire(output, 1, 1000, 100, 10).unwrap()
  assert_true(
    first.contains("\"source_id\":1") &&
    first.contains("\"target_id\":3") &&
    first.contains("\"node_ids\":[1,2,3]"),
  )
  assert_true(
    second.contains("\"source_id\":2") &&
    second.contains("\"target_id\":3") &&
    second.contains("\"node_ids\":[2,3]"),
  )
  let nearest_owner = carrier_graph_shortest_owner_with_endpoints(
    source_owner,
    "{\"ids\":[2,1]}",
    "{\"ids\":[4,3]}",
    2,
    selection=",\"selection\":\"nearest_per_source\"",
    max_output_rows=2,
  )
  let nearest_sequence = prepared_sequence(nearest_owner)
  let nearest_external = @execution.prepare_producer_read(
    nearest_owner,
    @execution.bind_completed_input(nearest_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let nearest_construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    nearest_sequence,
    0,
    [nearest_external, nearest_external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let nearest_graph = finish_rows_to_graph(nearest_construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(nearest_construction), Ok(true))
  let nearest_input = @graphs.prepare_step_read(
    nearest_owner, 1, 0, nearest_graph,
  ).unwrap()
  assert_true(
    @local_sga.start_shortest(
      @bounded.control(),
      task_test_completion(nearest_owner),
      nearest_sequence,
      1,
      nearest_input,
      2,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      96,
      1000,
      1000,
      [nearest_external],
    )
    is Err(@local_sga.ShortestWorkspaceLimit),
  )
  let nearest = @local_sga.start_shortest(
    @bounded.control(),
    task_test_completion(nearest_owner),
    nearest_sequence,
    1,
    nearest_input,
    2,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    97,
    1000,
    1000,
    [nearest_external],
  ).unwrap()
  let nearest_output = finish_shortest(nearest).unwrap()
  assert_eq(@local_sga.cleanup_shortest(nearest), Ok(true))
  assert_eq(@execution.completed_row_count(nearest_output), 2)
  assert_true(@graphs.discard_completed(nearest_graph))
  let empty_owner = carrier_graph_shortest_owner_with_endpoints(
    source_owner,
    "{\"where\":\"false\"}",
    "{\"where\":\"true\"}",
    2,
    selection=",\"selection\":\"each_pair\"",
    max_output_rows=1,
  )
  let empty_sequence = prepared_sequence(empty_owner)
  let empty_external = @execution.prepare_producer_read(
    empty_owner,
    @execution.bind_completed_input(empty_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let empty_construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    empty_sequence,
    0,
    [empty_external, empty_external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let empty_graph = finish_rows_to_graph(empty_construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(empty_construction), Ok(true))
  let empty_input = @graphs.prepare_step_read(empty_owner, 1, 0, empty_graph).unwrap()
  let empty = @local_sga.start_shortest(
    @bounded.control(),
    task_test_completion(empty_owner),
    empty_sequence,
    1,
    empty_input,
    0,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [empty_external],
  ).unwrap()
  let empty_output = finish_shortest(empty).unwrap()
  assert_eq(@local_sga.cleanup_shortest(empty), Ok(true))
  assert_eq(@execution.completed_row_count(empty_output), 0)
  assert_true(@graphs.discard_completed(empty_graph))
  let missing_owner = carrier_graph_shortest_owner_with_endpoints(
    source_owner,
    "{\"ids\":[1]}",
    "{\"ids\":[9]}",
    2,
    selection=",\"selection\":\"each_pair\"",
  )
  let missing_sequence = prepared_sequence(missing_owner)
  let missing_external = @execution.prepare_producer_read(
    missing_owner,
    @execution.bind_completed_input(missing_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let missing_construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    missing_sequence,
    0,
    [missing_external, missing_external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let missing_graph = finish_rows_to_graph(missing_construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(missing_construction), Ok(true))
  let missing_input = @graphs.prepare_step_read(
    missing_owner, 1, 0, missing_graph,
  ).unwrap()
  let missing = @local_sga.start_shortest(
    @bounded.control(),
    task_test_completion(missing_owner),
    missing_sequence,
    1,
    missing_input,
    1,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    89,
    1000,
    1000,
    [missing_external],
  ).unwrap()
  assert_true(
    finish_shortest(missing) is Err(@local_sga.ShortestEndpointMissing),
  )
  assert_eq(@local_sga.cleanup_shortest(missing), Ok(true))
  assert_true(@graphs.discard_completed(missing_graph))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.completed_output_available(output))
  assert_true(@execution.completed_output_available(source))
}

///|
test "traversal applies output ceilings only to emitted rows" {
  for
    (minimum, maximum, starts, expected) in [
      (0, 1, "3", Some(1)),
      (1, 1, "3", Some(0)),
      (1, 1, "1,2", None),
    ] {
    let source_owner = carrier_graph_components_source_owner()
    let source = carrier_events_source_output(source_owner)
    let owner = carrier_graph_traverse_owner(
      source_owner,
      minimum,
      maximum,
      starts~,
      max_output_rows=1,
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
      100,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      100,
      1000,
      1000,
      [external],
    ).unwrap()
    match expected {
      Some(rows) => {
        let output = finish_traverse(execution).unwrap()
        assert_eq(@execution.completed_row_count(output), rows)
        assert_true(@execution.completed_output_available(output))
      }
      None =>
        assert_true(
          finish_traverse(execution)
          is Err(@local_sga.TraverseReachIssue(@local_sga.ReachOutput(_))),
        )
    }
    assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
    assert_true(@graphs.discard_completed(graph))
  }
}

///|
test "homogeneous traversal sorts and deduplicates literal starts" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_traverse_owner(source_owner, 1, 2, starts="2,1,2")
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
    65,
    1000,
    1000,
    [external],
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
    @local_sga.start_traverse(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      64,
      1000,
      1000,
      [external],
    )
    is Err(@local_sga.TraverseReachIssue(@local_sga.ReachWorkspaceLimit)),
  )
  assert_true(@graphs.discard_completed(graph))
}

///|
test "homogeneous traversal reads a Relation start selector" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let selector_owner = carrier_graph_selector_source_owner(
    "[{\"key\":2},{\"key\":1},{\"key\":2}]",
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
test "traversal separates predicate widths at exact workspace" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_predicate_pattern_owner(source_owner)
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
  assert_true(
    @local_sga.start_traverse(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      input,
      4,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      37,
      1000,
      1000,
      [external],
    )
    is Err(@local_sga.TraverseReachIssue(@local_sga.ReachWorkspaceLimit)),
  )
  let short = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    38,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(
    finish_traverse(short)
    is Err(@local_sga.TraverseReachIssue(@local_sga.ReachPredicate(_))),
  )
  assert_eq(@local_sga.cleanup_traverse(short), Ok(true))
  let execution = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    4,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    39,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_traverse(execution).unwrap()
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 1000, 100, 10).unwrap(),
    "{\"depth\":1,\"node_id\":1,\"start_id\":2}",
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
test "homogeneous traversal rejects a missing literal start atomically" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_traverse_owner(source_owner, 1, 2, starts="1,9")
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
    65,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(
    finish_traverse(execution)
    is Err(@local_sga.TraverseReachIssue(@local_sga.ReachStartMissing)),
  )
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
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
      max_work: 10000,
    },
    workspace,
    1000,
    1000,
    [external],
  ).unwrap()
  let result = finish_traverse(execution, quantum~)
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
  let execution = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    max_rows,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    workspace,
    1000,
    1000,
    [external],
  ).unwrap()
  let result = finish_traverse(execution)
  if peak is Some(value) {
    value.val = @local_sga.traverse_private_workspace_usage(execution).1
  }
  assert_eq(@local_sga.cleanup_traverse(execution), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  result
}

///|
test "node traversal finds the shortest eligible simple path" {
  let source_owner = carrier_graph_source_owner_with_rows(
    "[{\"id\":1,\"src\":1,\"dst\":3,\"node_name\":\"one\",\"weight\":1}," +
    "{\"id\":2,\"src\":1,\"dst\":2,\"node_name\":\"two\",\"weight\":1}," +
    "{\"id\":3,\"src\":2,\"dst\":3,\"node_name\":\"three\",\"weight\":1}]",
  )
  let output = traverse_nodes_result_for_source(source_owner, 2, 2).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 20).unwrap(),
    "{\"depth\":2,\"node_id\":3,\"start_id\":1}",
  )
  let paths = traverse_paths_result_for_source(
    source_owner,
    4,
    100,
    minimum=2,
    maximum=2,
  ).unwrap()
  assert_eq(@execution.completed_row_count(paths), 1)
  assert_true(
    @execution.completed_output_row_wire(paths, 0, 10000, 1000, 20)
    .unwrap()
    .contains("\"node_ids\":[1,2,3]"),
  )
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
fn relation_traverse_paths_result(
  rows : String,
  nullable? : Bool = false,
) -> Result[@execution.CompletedOutput, @local_sga.TraverseIssue] raise {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let selector_owner = carrier_graph_selector_source_owner(rows, nullable~)
  let selector = carrier_events_source_output(selector_owner)
  let owner = carrier_graph_relation_traverse_owner(
    source_owner,
    selector_owner,
    emission="paths",
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
fn carrier_numeric_graph_contract() -> @carrier_contract.Carrier {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  let node = @carrier_contract.rows(
    [(@schema.Unqualified("score"), Some(number))],
    field_set=@carrier_contract.Closed,
    max_fields=1,
    max_name_bytes=5,
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
fn carrier_numeric_graph_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check_carriers(
    input_cursor("[{\"from\":\"g\",\"normalize_graph\":true}]"),
    [("g", carrier_numeric_graph_contract())],
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
fn carrier_numeric_union_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"left\",\"union_graphs\":{" +
      "\"with\":\"right\",\"merge\":{" +
      "\"node_properties\":{\"score\":\"number_sum\"}}}," +
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
fn carrier_numeric_mean_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked_result = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"mean_graphs\":{" +
      "\"with\":[\"left\",\"right\"],\"weights\":[1,3]," +
      "\"support\":{\"nodes\":1,\"edges\":1}," +
      "\"properties\":{\"nodes\":{\"score\":{" +
      "\"mean\":{\"missing\":\"exclude\",\"nulls\":\"fail\"}}}," +
      "\"edges\":{}}},\"as\":\"g\"}," +
      "{\"from\":\"g\",\"node_rows\":true}]",
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
  )
  let checked = checked_result.unwrap()
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
fn carrier_numeric_graph(
  owner : @lower.BoundPrepared,
  identity : Double,
  score : Double,
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
  @graphs.append_node(
    output,
    @admitted.checked_number_value(identity, number).unwrap(),
    [@admitted.checked_number_value(score, number).unwrap()],
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
test "registered Graph provider merges numeric Carrier properties" {
  let left_owner = carrier_numeric_graph_owner()
  let right_owner = carrier_numeric_graph_owner()
  let owner = carrier_numeric_union_owner(left_owner, right_owner)
  let generated = task_test_generated(owner)
  let left = carrier_numeric_graph(left_owner, 1.0, 2.0)
  let right = carrier_numeric_graph(right_owner, 1.0, 4.0)
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
        fail("numeric union projection returned a Carrier")
      @local_connector.Failed(_, ..) => fail("numeric union provider failed")
      @local_connector.Stopped(..) => fail("numeric union provider stopped")
    }
  }
  let output = completed.unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Number(6.0)))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(left_material))
  assert_true(@carrier_runtime.material_available(right_material))
}

///|
test "registered Graph provider computes an exact weighted mean" {
  let left_owner = carrier_numeric_graph_owner()
  let right_owner = carrier_numeric_graph_owner()
  let owner = carrier_numeric_mean_owner(left_owner, right_owner)
  let generated = task_test_generated(owner)
  let left = carrier_numeric_graph(left_owner, 1.0, 2.0)
  let right = carrier_numeric_graph(right_owner, 1.0, 4.0)
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
        fail("mean projection returned a Carrier")
      @local_connector.Failed(_, ..) => fail("mean provider failed")
      @local_connector.Stopped(..) => fail("mean provider stopped")
    }
  }
  let output = completed.unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Number(3.5)))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(left_material))
  assert_true(@carrier_runtime.material_available(right_material))
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
  if variant == "graph_diff_changes" {
    "sha256:de8347c32fb9edf7f0bddd3ab5bcd9b986ba90aeff296e55f02e52f067067ef9"
  } else if variant == "concise_projection" {
    "sha256:4dc1796ed34dc82b34758a1fca828ec1a34ef068e231fd5637d51841529bdb97"
  } else if variant == "subtract_exact" {
    "sha256:61658ff21fd18cc3b110c965c92422c813ef6e76d1aef0415841101c72e8f576"
  } else if variant == "subtract" {
    "sha256:581c1ad7ac48237df5c669e328275ed013a700f7308143a32557810117210089"
  } else if variant == "graph_bounds" {
    "sha256:17d576d1679a19ebaa39babfe25c6922f65888c29781f7ea73b3f2af674b13c7"
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
test "Graph equality enforces exact control work and cleans cancellation" {
  let source_owner = carrier_graph_source_owner_with_rows("[]")
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_binary_relation_owner(source_owner, "graphs_equal")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let left_builder = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let left = finish_rows_to_graph(left_builder)
  assert_eq(@local_bridge.cleanup_rows_to_graph(left_builder), Ok(true))
  let right_builder = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    1,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let right = finish_rows_to_graph(right_builder)
  assert_eq(@local_bridge.cleanup_rows_to_graph(right_builder), Ok(true))
  let left_read = @graphs.prepare_step_read(owner, 2, 0, left).unwrap()
  let right_read = @graphs.prepare_step_read(owner, 2, 1, right).unwrap()
  let start = fn(control, work, entries) raise {
    @local_sga.start_graphs_equal(
      control,
      task_test_completion(owner),
      sequence,
      2,
      left_read,
      right_read,
      1,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      entries,
      1000,
      [external],
      control_work_limit=Some(work),
    ).unwrap()
  }
  // The one receiving input and one Boolean output each require one
  // structural port entry. The same entry is reused across both checks.
  assert_true(
    @local_sga.start_graphs_equal(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      2,
      left_read,
      right_read,
      1,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      0,
      1000,
      [external],
      control_work_limit=Some(3),
    )
    is Err(@local_sga.GraphsEqualCompletion(@execution.Limit)),
  )
  // Empty Graphs require count comparison, one output, and completion.
  let exact = start(@bounded.control(), 3, 1)
  assert_true(
    @local_sga.advance_graphs_equal(exact, 1).unwrap()
    is @local_sga.GraphsEqualContinue(progress=0L, work=1L),
  )
  match @local_sga.advance_graphs_equal(exact, 1).unwrap() {
    @local_sga.GraphsEqualContinue(progress=1L, work=2L) => ()
    @local_sga.GraphsEqualContinue(progress~, work~) =>
      fail("equality progress " + progress.to_string() + "/" + work.to_string())
    @local_sga.GraphsEqualFailed(@local_sga.GraphsEqualWorkLimit, ..) =>
      fail("equality work limit fired before output")
    @local_sga.GraphsEqualFailed(@local_sga.GraphsEqualOutput(_), ..) =>
      fail("equality output failed")
    @local_sga.GraphsEqualFailed(@local_sga.GraphsEqualCompletion(_), ..) =>
      fail("equality completion failed")
    @local_sga.GraphsEqualFailed(@local_sga.InvalidGraphsEqualKernel, ..) =>
      fail("equality kernel rejected output")
    @local_sga.GraphsEqualFailed(_, ..) => fail("equality failed before output")
    _ => fail("equality second step did not continue")
  }
  let output = match @local_sga.advance_graphs_equal(exact, 1).unwrap() {
    @local_sga.GraphsEqualComplete(output, progress=1L, work=3L) => output
    _ => abort("exact Graph equality did not complete")
  }
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Boolean(true)))
  assert_eq(@local_sga.cleanup_graphs_equal(exact), Ok(true))
  assert_true(@execution.completed_output_available(output))
  let short = start(@bounded.control(), 2, 1)
  assert_true(
    @local_sga.advance_graphs_equal(short, 1).unwrap()
    is @local_sga.GraphsEqualContinue(progress=0L, work=1L),
  )
  assert_true(
    @local_sga.advance_graphs_equal(short, 1).unwrap()
    is @local_sga.GraphsEqualContinue(progress=1L, work=2L),
  )
  assert_true(
    @local_sga.advance_graphs_equal(short, 1).unwrap()
    is @local_sga.GraphsEqualFailed(@local_sga.GraphsEqualWorkLimit, ..),
  )
  assert_true(@local_sga.graphs_equal_cleanup_pending(short))
  assert_eq(@local_sga.cleanup_graphs_equal(short), Ok(true))
  let control = @bounded.control()
  let cancelled = start(control, 3, 1)
  assert_true(
    @local_sga.advance_graphs_equal(cancelled, 1).unwrap()
    is @local_sga.GraphsEqualContinue(progress=0L, work=1L),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_graphs_equal(cancelled, 1).unwrap()
    is @local_sga.GraphsEqualStopped(_, progress=0L, work=1L),
  )
  assert_eq(@local_sga.cleanup_graphs_equal(cancelled), Ok(true))
  assert_true(@graphs.producer_read_available(left_read))
  assert_true(@graphs.producer_read_available(right_read))
  assert_true(@graphs.discard_completed(left))
  assert_true(@graphs.discard_completed(right))
  assert_true(@execution.completed_output_available(source))
}

///|
test "Graph equality stops during a long property comparison" {
  let rows = "[{\"id\":1,\"src\":1,\"dst\":1," +
    "\"node_name\":\"" +
    "x".repeat(512) +
    "\",\"weight\":1}]"
  let source_owner = carrier_graph_source_owner_with_rows(rows)
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_binary_relation_owner(source_owner, "graphs_equal")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let left_builder = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let left = finish_rows_to_graph(left_builder)
  assert_eq(@local_bridge.cleanup_rows_to_graph(left_builder), Ok(true))
  let right_builder = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    1,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let right = finish_rows_to_graph(right_builder)
  assert_eq(@local_bridge.cleanup_rows_to_graph(right_builder), Ok(true))
  let left_read = @graphs.prepare_step_read(owner, 2, 0, left).unwrap()
  let right_read = @graphs.prepare_step_read(owner, 2, 1, right).unwrap()
  let control = @bounded.control()
  let active = @local_sga.start_graphs_equal(
    control,
    task_test_completion(owner),
    sequence,
    2,
    left_read,
    right_read,
    1,
    { max_nodes: 1000, max_text_bytes: 2048, max_depth: 10, max_work: 10000, },
    1000,
    1000,
    [external],
  ).unwrap()
  for index in 0..<50 {
    match @local_sga.advance_graphs_equal(active, 1).unwrap() {
      @local_sga.GraphsEqualContinue(progress~, work~) => {
        assert_eq(progress, 0L)
        assert_eq(work, (index + 1).to_int64())
      }
      _ => fail("Graph equality did not yield during long text comparison")
    }
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_graphs_equal(active, 1).unwrap()
    is @local_sga.GraphsEqualStopped(_, progress=0L, work=50L),
  )
  assert_eq(@local_sga.cleanup_graphs_equal(active), Ok(true))
  assert_true(@graphs.producer_read_available(left_read))
  assert_true(@graphs.producer_read_available(right_read))
  assert_true(@graphs.discard_completed(left))
  assert_true(@graphs.discard_completed(right))
  assert_true(@execution.completed_output_available(source))
}

///|
test "Graph equality bounds nested value comparison work" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_binary_relation_owner(source_owner, "graphs_equal")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let left_builder = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let left = finish_rows_to_graph(left_builder)
  assert_eq(@local_bridge.cleanup_rows_to_graph(left_builder), Ok(true))
  let right_builder = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    1,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let right = finish_rows_to_graph(right_builder)
  assert_eq(@local_bridge.cleanup_rows_to_graph(right_builder), Ok(true))
  let left_read = @graphs.prepare_step_read(owner, 2, 0, left).unwrap()
  let right_read = @graphs.prepare_step_read(owner, 2, 1, right).unwrap()
  let execution = @local_sga.start_graphs_equal(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    2,
    left_read,
    right_read,
    1,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    1000,
    1000,
    [external],
    control_work_limit=Some(3),
  ).unwrap()
  assert_true(
    @local_sga.advance_graphs_equal(execution, 100).unwrap()
    is @local_sga.GraphsEqualFailed(
      @local_sga.GraphsEqualWorkLimit,
      progress=0L,
      work=3L
    ),
  )
  assert_eq(@local_sga.cleanup_graphs_equal(execution), Ok(true))
  assert_true(@graphs.producer_read_available(left_read))
  assert_true(@graphs.producer_read_available(right_read))
  assert_true(@graphs.discard_completed(left))
  assert_true(@graphs.discard_completed(right))
}

///|
test "Graph diff cancellation stops partial snapshots before cleanup" {
  let mut source_rows = "["
  for id in 1..<=10 {
    if id > 1 {
      source_rows += ","
    }
    source_rows += "{\"id\":" +
      id.to_string() +
      ",\"src\":" +
      id.to_string() +
      ",\"dst\":" +
      id.to_string() +
      ",\"node_name\":\"same\",\"weight\":1}"
  }
  source_rows += "]"
  let source_owner = carrier_graph_source_owner_with_rows(source_rows)
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_diff_owner(source_owner)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let left_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let left = finish_rows_to_graph(left_execution)
  assert_eq(@local_bridge.cleanup_rows_to_graph(left_execution), Ok(true))
  let right_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    1,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let right = finish_rows_to_graph(right_execution)
  assert_eq(@local_bridge.cleanup_rows_to_graph(right_execution), Ok(true))
  let control = @bounded.control()
  let execution = @local_sga.start_graph_diff(
    control,
    task_test_completion(owner),
    sequence,
    2,
    @graphs.prepare_step_read(owner, 2, 0, left).unwrap(),
    @graphs.prepare_step_read(owner, 2, 1, right).unwrap(),
    1,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    1000,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(
    @local_sga.advance_graph_diff(execution, 1).unwrap()
    is @local_sga.GraphDiffContinue(progress=1L, work=1L),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_graph_diff(execution, 1).unwrap()
    is @local_sga.GraphDiffStopped(_, ..),
  )
  assert_true(@local_sga.graph_diff_stopped(execution))
  assert_true(@local_sga.graph_diff_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_graph_diff(execution), Ok(true))
  assert_false(@local_sga.graph_diff_cleanup_pending(execution))
  let reference = @local_sga.start_graph_diff(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    2,
    @graphs.prepare_step_read(owner, 2, 0, left).unwrap(),
    @graphs.prepare_step_read(owner, 2, 1, right).unwrap(),
    1,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    1000,
    1000,
    1000,
    [external],
  ).unwrap()
  let mut charged = 0
  let mut finished = false
  while !finished {
    match @local_sga.advance_graph_diff(reference, 1).unwrap() {
      @local_sga.GraphDiffContinue(work~, ..) => charged = work.to_int()
      @local_sga.GraphDiffComplete(output, work~, ..) => {
        charged = work.to_int()
        assert_true(@execution.completed_output_available(output))
        finished = true
      }
      _ => fail("reference graph diff failed")
    }
  }
  assert_eq(@local_sga.cleanup_graph_diff(reference), Ok(true))
  assert_true(charged > 2)
  // The paired ceilings guard the emit/finalize tail, not an independent
  // full-route work formula for every graph shape.
  for ceiling in [charged - 1, charged] {
    let limited = @local_sga.start_graph_diff(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      2,
      @graphs.prepare_step_read(owner, 2, 0, left).unwrap(),
      @graphs.prepare_step_read(owner, 2, 1, right).unwrap(),
      1,
      {
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: ceiling,
      },
      1000,
      1000,
      1000,
      [external],
    ).unwrap()
    let mut terminal = false
    let mut reported = 0
    while !terminal {
      match @local_sga.advance_graph_diff(limited, 1).unwrap() {
        @local_sga.GraphDiffContinue(work~, ..) => reported = work.to_int()
        @local_sga.GraphDiffComplete(output, work~, ..) => {
          reported = work.to_int()
          assert_eq(ceiling, charged)
          assert_true(@execution.completed_output_available(output))
          terminal = true
        }
        @local_sga.GraphDiffFailed(@local_sga.GraphDiffWorkLimit, work~, ..) => {
          reported = work.to_int()
          assert_eq(ceiling, charged - 1)
          terminal = true
        }
        _ => fail("graph diff ignored its total work ceiling")
      }
    }
    assert_eq(reported, ceiling)
    assert_eq(@local_sga.cleanup_graph_diff(limited), Ok(true))
  }
  assert_true(@graphs.discard_completed(left))
  assert_true(@graphs.discard_completed(right))
  assert_true(@execution.completed_output_available(source))
}

///|
test "Graph delta applies an empty exact diff with quantum one" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let diff_owner = carrier_graph_diff_owner(source_owner)
  let diff_sequence = prepared_sequence(diff_owner)
  let external = @execution.prepare_producer_read(
    diff_owner,
    @execution.bind_completed_input(diff_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let left_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    diff_sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let left = finish_rows_to_graph(left_execution)
  let right_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    diff_sequence,
    1,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let right = finish_rows_to_graph(right_execution)
  let diff_execution = @local_sga.start_graph_diff(
    @bounded.control(),
    task_test_completion(diff_owner),
    diff_sequence,
    2,
    @graphs.prepare_step_read(diff_owner, 2, 0, left).unwrap(),
    @graphs.prepare_step_read(diff_owner, 2, 1, right).unwrap(),
    1,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let delta = finish_graph_diff(diff_execution)
  let apply_owner = carrier_graph_apply_owner(diff_owner)
  let apply_sequence = prepared_sequence(apply_owner)
  let base = @graphs.prepare_producer_read(apply_owner, 0, diff_owner, left).unwrap()
  let delta = @execution.prepare_producer_read(
    apply_owner,
    @execution.bind_completed_input(apply_owner, 1, diff_owner, delta).unwrap(),
    100,
    1000,
  ).unwrap()
  let apply = @local_sga.start_graph_apply(
    @bounded.control(),
    apply_sequence,
    0,
    base,
    delta,
    carrier_graph_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut completed = None
  let mut polls = 0
  while completed is None {
    polls += 1
    assert_true(polls < 1000)
    match @local_sga.advance_graph_apply(apply, 1).unwrap() {
      @local_sga.GraphApplyContinue(..) => ()
      @local_sga.GraphApplyComplete(output, ..) => completed = Some(output)
      @local_sga.GraphApplyFailed(_, ..) => abort("graph apply failed")
      @local_sga.GraphApplyStopped(_, ..) => abort("graph apply stopped")
    }
  }
  let output = completed.unwrap()
  let storage = @graphs.completed_storage(output).unwrap()
  assert_eq(@graph_storage.node_count(storage), 2)
  assert_eq(@graph_storage.edge_count(storage), 2)
  let cancel_control = @bounded.control()
  let cancelled = @local_sga.start_graph_apply(
    cancel_control,
    apply_sequence,
    0,
    base,
    delta,
    carrier_graph_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(@bounded.request_cancel(cancel_control))
  assert_true(
    @local_sga.advance_graph_apply(cancelled, 1).unwrap()
    is @local_sga.GraphApplyStopped(_, progress=0L, work=0L),
  )
  assert_true(@local_sga.graph_apply_stopped(cancelled))
  assert_true(@local_sga.graph_apply_cleanup_pending(cancelled))
  assert_eq(@local_sga.cleanup_graph_apply(cancelled), Ok(true))
  assert_false(@local_sga.graph_apply_cleanup_pending(cancelled))
  assert_true(@local_sga.cleanup_graph_apply(apply).unwrap_or(false))
  assert_true(@graphs.discard_completed(output))
  assert_true(@local_sga.cleanup_graph_diff(diff_execution).unwrap_or(false))
  assert_true(
    @local_bridge.cleanup_rows_to_graph(left_execution).unwrap_or(false),
  )
  assert_true(
    @local_bridge.cleanup_rows_to_graph(right_execution).unwrap_or(false),
  )
  assert_true(@graphs.discard_completed(left))
  assert_true(@graphs.discard_completed(right))
  assert_true(@execution.completed_output_available(source))
}

///|
test "Graph delta atomically applies node edge and property changes" {
  let left_owner = carrier_graph_source_owner()
  let right_owner = carrier_graph_source_owner_with_rows(
    "[{\"id\":1,\"src\":1,\"dst\":3," +
    "\"node_name\":\"changed\",\"weight\":11},{\"id\":3," +
    "\"src\":3,\"dst\":1,\"node_name\":\"third\",\"weight\":30}]",
  )
  let left_rows = carrier_events_source_output(left_owner)
  let right_rows = carrier_events_source_output(right_owner)
  let diff_owner = carrier_graph_delta_owner(left_owner, right_owner)
  let sequence = prepared_sequence(diff_owner)
  let left_input = @execution.prepare_producer_read(
    diff_owner,
    @execution.bind_completed_input(diff_owner, 0, left_owner, left_rows).unwrap(),
    100,
    1000,
  ).unwrap()
  let right_input = @execution.prepare_producer_read(
    diff_owner,
    @execution.bind_completed_input(diff_owner, 1, right_owner, right_rows).unwrap(),
    100,
    1000,
  ).unwrap()
  let inputs = [left_input, right_input]
  let left_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [left_input, left_input],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let left = finish_rows_to_graph(left_execution)
  let right_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    1,
    [right_input, right_input],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let right = finish_rows_to_graph(right_execution)
  let diff_execution = @local_sga.start_graph_diff(
    @bounded.control(),
    task_test_completion(diff_owner),
    sequence,
    2,
    @graphs.prepare_step_read(diff_owner, 2, 0, left).unwrap(),
    @graphs.prepare_step_read(diff_owner, 2, 1, right).unwrap(),
    1,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    100,
    1000,
    1000,
    inputs,
  ).unwrap()
  let delta = finish_graph_diff(diff_execution)
  let apply_owner = carrier_graph_apply_owner(diff_owner)
  let apply = @local_sga.start_graph_apply(
    @bounded.control(),
    prepared_sequence(apply_owner),
    0,
    @graphs.prepare_producer_read(apply_owner, 0, diff_owner, left).unwrap(),
    @execution.prepare_producer_read(
      apply_owner,
      @execution.bind_completed_input(apply_owner, 1, diff_owner, delta).unwrap(),
      100,
      1000,
    ).unwrap(),
    carrier_graph_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut applied = None
  let mut polls = 0
  while applied is None {
    polls += 1
    assert_true(polls < 1000)
    match @local_sga.advance_graph_apply(apply, 1).unwrap() {
      @local_sga.GraphApplyContinue(..) => ()
      @local_sga.GraphApplyComplete(output, ..) => applied = Some(output)
      @local_sga.GraphApplyFailed(_, ..) => abort("graph apply failed")
      @local_sga.GraphApplyStopped(_, ..) => abort("graph apply stopped")
    }
  }
  let output = applied.unwrap()
  assert_true(@local_sga.graph_apply_private_entry_count(apply) > 0)
  let (scratch_slots, scratch_bytes, peak_slots, peak_bytes) = @local_sga.graph_apply_private_scratch_usage(
    apply,
  )
  assert_eq(
    (scratch_slots, scratch_bytes, peak_slots, peak_bytes),
    (38, 776, 44, 922),
  )
  let storage = @graphs.completed_storage(output).unwrap()
  assert_eq(@graph_storage.node_count(storage), 2)
  assert_eq(@graph_storage.edge_count(storage), 2)
  assert_true(
    @graph_storage.node_identity(storage, 1).unwrap().value
    is @admitted.Number(3.0),
  )
  assert_true(
    @graph_storage.node_property(storage, 0, 0).unwrap().value
    is @admitted.Text("changed"),
  )
  let generated = task_test_generated(apply_owner)
  let material = @graphs.completed_material(left).unwrap()
  let view = @carrier_runtime.material_prepare_view(
    material, apply_owner, 0, diff_owner,
  ).unwrap()
  let viewed = @local_sga.start_graph_apply_view(
    @bounded.control(),
    prepared_sequence(apply_owner),
    0,
    view,
    @execution.prepare_producer_read(
      apply_owner,
      @execution.bind_completed_input(apply_owner, 1, diff_owner, delta).unwrap(),
      100,
      1000,
    ).unwrap(),
    carrier_graph_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut viewed_output = None
  while viewed_output is None {
    match @local_sga.advance_graph_apply(viewed, 7).unwrap() {
      @local_sga.GraphApplyContinue(..) => ()
      @local_sga.GraphApplyComplete(result, ..) => viewed_output = Some(result)
      _ => abort("viewed graph apply failed")
    }
  }
  assert_eq(@local_sga.graph_apply_private_scratch_usage(viewed).2, 44)
  assert_eq(@local_sga.graph_apply_private_scratch_usage(viewed).3, 922)
  assert_eq(
    @graph_storage.node_count(
      @graphs.completed_storage(viewed_output.unwrap()).unwrap(),
    ),
    2,
  )
  assert_eq(@local_sga.cleanup_graph_apply(viewed), Ok(true))
  assert_eq(@local_sga.graph_apply_private_entry_count(viewed), 0)
  assert_true(@graphs.discard_completed(viewed_output.unwrap()))
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
  let provider_run = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(view),
      @local_connector.managed_provider_relation_input(
        @execution.prepare_producer_read(
          apply_owner,
          @execution.bind_completed_input(apply_owner, 1, diff_owner, delta).unwrap(),
          100,
          1000,
        ).unwrap(),
      ),
    ],
    10,
    1000,
  ).unwrap()
  let mut rows = None
  while rows is None {
    match @local_connector.advance_managed_provider(provider_run, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(output, ..) => rows = Some(output)
      @local_connector.CarrierComplete(_, ..) =>
        abort("graph apply projection returned a Carrier")
      @local_connector.Failed(_, ..) => abort("graph apply provider failed")
      @local_connector.Stopped(..) => abort("graph apply provider stopped")
    }
  }
  assert_eq(@execution.completed_row_count(rows.unwrap()), 2)
  assert_true(
    @local_connector.cleanup_managed_provider(provider_run).unwrap_or(false),
  )
  let partial_control = @bounded.control()
  let partial = @local_sga.start_graph_apply(
    partial_control,
    prepared_sequence(apply_owner),
    0,
    @graphs.prepare_producer_read(apply_owner, 0, diff_owner, left).unwrap(),
    @execution.prepare_producer_read(
      apply_owner,
      @execution.bind_completed_input(apply_owner, 1, diff_owner, delta).unwrap(),
      100,
      1000,
    ).unwrap(),
    carrier_graph_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let mut partial_polls = 0
  while @local_sga.graph_apply_private_entry_count(partial) == 0 {
    partial_polls += 1
    assert_true(partial_polls < 1000)
    assert_true(
      @local_sga.advance_graph_apply(partial, 1).unwrap()
      is @local_sga.GraphApplyContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(partial_control))
  assert_true(
    @local_sga.advance_graph_apply(partial, 1).unwrap()
    is @local_sga.GraphApplyStopped(_, ..),
  )
  assert_eq(@local_sga.cleanup_graph_apply(partial), Ok(true))
  assert_eq(@local_sga.graph_apply_private_entry_count(partial), 0)
  assert_eq(@local_sga.cleanup_graph_apply(partial), Ok(false))
  for
    (workspace, bytes, expected) in [
      (64, 10000, "scratch"),
      (109, 10000, "scratch"),
      (110, 10000, "complete"),
      (1000, 921, "bytes"),
      (1000, 922, "complete"),
    ] {
    let capped = @local_sga.start_graph_apply(
      @bounded.control(),
      prepared_sequence(apply_owner),
      0,
      @graphs.prepare_producer_read(apply_owner, 0, diff_owner, left).unwrap(),
      @execution.prepare_producer_read(
        apply_owner,
        @execution.bind_completed_input(apply_owner, 1, diff_owner, delta).unwrap(),
        100,
        1000,
      ).unwrap(),
      carrier_graph_storage_limits_for_scratch(workspace, bytes),
      4096L,
      fn() { true },
    ).unwrap()
    let mut status = ""
    let mut attempts = 0
    while status == "" {
      attempts += 1
      assert_true(attempts < 1000)
      match @local_sga.advance_graph_apply(capped, 1).unwrap() {
        @local_sga.GraphApplyContinue(..) => ()
        @local_sga.GraphApplyFailed(@local_sga.GraphApplyWorkspaceLimit, ..) =>
          status = "scratch"
        @local_sga.GraphApplyFailed(@local_sga.GraphApplyScratchBytesLimit, ..) =>
          status = "bytes"
        @local_sga.GraphApplyFailed(_, ..) => status = "other"
        @local_sga.GraphApplyComplete(result, ..) => {
          assert_true(@graphs.discard_completed(result))
          status = "complete"
        }
        _ => abort("unexpected capped apply outcome")
      }
    }
    assert_eq(status, expected)
    if workspace == 64 {
      assert_true(@local_sga.graph_apply_private_scratch_usage(capped).2 < 44)
      assert_true(@local_sga.graph_apply_private_entry_count(capped) < 20)
    }
    if bytes == 921 {
      assert_true(@local_sga.graph_apply_private_scratch_usage(capped).3 < 922)
    }
    if expected == "complete" {
      assert_eq(@local_sga.graph_apply_private_scratch_usage(capped).2, 44)
      assert_eq(@local_sga.graph_apply_private_scratch_usage(capped).3, 922)
    }
    assert_eq(@local_sga.cleanup_graph_apply(capped), Ok(true))
    assert_eq(@local_sga.graph_apply_private_entry_count(capped), 0)
    assert_eq(@local_sga.graph_apply_private_scratch_usage(capped).0, 0)
    assert_eq(@local_sga.graph_apply_private_scratch_usage(capped).1, 0)
  }
  assert_true(@local_sga.cleanup_graph_apply(apply).unwrap_or(false))
  assert_eq(@local_sga.graph_apply_private_entry_count(apply), 0)
  assert_true(@graphs.discard_completed(output))
  assert_true(@local_sga.cleanup_graph_diff(diff_execution).unwrap_or(false))
  assert_true(
    @local_bridge.cleanup_rows_to_graph(left_execution).unwrap_or(false),
  )
  assert_true(
    @local_bridge.cleanup_rows_to_graph(right_execution).unwrap_or(false),
  )
  assert_true(@graphs.discard_completed(left))
  assert_true(@graphs.discard_completed(right))
  assert_true(@execution.completed_output_available(left_rows))
  assert_true(@execution.completed_output_available(right_rows))
}

///|
fn graph_apply_population_case(
  left_data : String,
  right_data : String,
  workspace : Int,
  quantum : Int,
  wide? : Bool = false,
  text_id? : Bool = false,
  scratch_bytes? : Int = 10000,
) -> (String, Int, Int, Int, Int, Int) raise {
  let left_owner = carrier_graph_source_owner_with_rows(
    left_data,
    wide~,
    text_id~,
  )
  let right_owner = carrier_graph_source_owner_with_rows(
    right_data,
    wide~,
    text_id~,
  )
  let left_rows = carrier_events_source_output(left_owner)
  let right_rows = carrier_events_source_output(right_owner)
  let diff_owner = carrier_graph_delta_owner(left_owner, right_owner, wide~)
  let sequence = prepared_sequence(diff_owner)
  let left_input = @execution.prepare_producer_read(
    diff_owner,
    @execution.bind_completed_input(diff_owner, 0, left_owner, left_rows).unwrap(),
    100,
    1000,
  ).unwrap()
  let right_input = @execution.prepare_producer_read(
    diff_owner,
    @execution.bind_completed_input(diff_owner, 1, right_owner, right_rows).unwrap(),
    100,
    1000,
  ).unwrap()
  let inputs = [left_input, right_input]
  let left_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [left_input, left_input],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let left = finish_rows_to_graph(left_execution)
  let right_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    1,
    [right_input, right_input],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let right = finish_rows_to_graph(right_execution)
  let diff_execution = @local_sga.start_graph_diff(
    @bounded.control(),
    task_test_completion(diff_owner),
    sequence,
    2,
    @graphs.prepare_step_read(diff_owner, 2, 0, left).unwrap(),
    @graphs.prepare_step_read(diff_owner, 2, 1, right).unwrap(),
    1,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    100,
    1000,
    1000,
    inputs,
  ).unwrap()
  let delta = finish_graph_diff(diff_execution)
  let apply_owner = carrier_graph_apply_owner(diff_owner)
  let execution = @local_sga.start_graph_apply(
    @bounded.control(),
    prepared_sequence(apply_owner),
    0,
    @graphs.prepare_producer_read(apply_owner, 0, diff_owner, left).unwrap(),
    @execution.prepare_producer_read(
      apply_owner,
      @execution.bind_completed_input(apply_owner, 1, diff_owner, delta).unwrap(),
      100,
      1000,
    ).unwrap(),
    carrier_graph_storage_limits_for_scratch(workspace, scratch_bytes),
    4096L,
    fn() { true },
  ).unwrap()
  let mut status = ""
  let mut output = None
  let mut polls = 0
  while status == "" {
    polls += 1
    assert_true(polls < 1000)
    match @local_sga.advance_graph_apply(execution, quantum).unwrap() {
      @local_sga.GraphApplyContinue(..) => ()
      @local_sga.GraphApplyFailed(@local_sga.GraphApplyWorkspaceLimit, ..) =>
        status = "workspace"
      @local_sga.GraphApplyFailed(@local_sga.GraphApplyScratchBytesLimit, ..) =>
        status = "bytes"
      @local_sga.GraphApplyFailed(_, ..) => status = "other"
      @local_sga.GraphApplyComplete(completed, ..) => {
        output = Some(completed)
        status = "complete"
      }
      _ => abort("unexpected Graph delta population result")
    }
  }
  let entries = @local_sga.graph_apply_private_entry_count(execution)
  let (live_slots, _, peak_slots, peak_bytes) = @local_sga.graph_apply_private_scratch_usage(
    execution,
  )
  if output is Some(completed) {
    assert_eq(
      @graph_storage.node_count(@graphs.completed_storage(completed).unwrap()),
      @graph_storage.node_count(@graphs.completed_storage(right).unwrap()),
    )
  }
  assert_eq(@local_sga.cleanup_graph_apply(execution), Ok(true))
  assert_eq(@local_sga.graph_apply_private_entry_count(execution), 0)
  assert_eq(@local_sga.graph_apply_private_scratch_usage(execution).0, 0)
  if output is Some(completed) {
    assert_true(@graphs.discard_completed(completed))
  }
  assert_eq(@local_sga.cleanup_graph_diff(diff_execution), Ok(true))
  assert_eq(@local_bridge.cleanup_rows_to_graph(left_execution), Ok(true))
  assert_eq(@local_bridge.cleanup_rows_to_graph(right_execution), Ok(true))
  assert_true(@graphs.discard_completed(left))
  assert_true(@graphs.discard_completed(right))
  assert_true(@execution.completed_output_available(left_rows))
  assert_true(@execution.completed_output_available(right_rows))
  (status, entries, live_slots, peak_slots, peak_bytes, polls)
}

///|
test "Graph delta admits many additions and removals before scratch allocation" {
  let three = "[{\"id\":1,\"src\":1,\"dst\":2,\"node_name\":\"a\",\"weight\":10}," +
    "{\"id\":2,\"src\":2,\"dst\":3,\"node_name\":\"b\",\"weight\":20}," +
    "{\"id\":3,\"src\":3,\"dst\":1,\"node_name\":\"c\",\"weight\":30}]"
  let add_zero = graph_apply_population_case("[]", three, 0, 1)
  assert_eq(add_zero.0, "workspace")
  assert_eq(add_zero.1, 0)
  assert_eq(add_zero.2, 0)
  let add_one = graph_apply_population_case("[]", three, 5, 7)
  assert_eq(add_one.0, "workspace")
  assert_eq(add_one.1, 0)
  let added = graph_apply_population_case("[]", three, 1000, 1)
  assert_eq(added.0, "complete")
  assert_true(added.1 > 6)
  assert_true(added.2 > 0)
  let added_wide = graph_apply_population_case("[]", three, 1000, 7)
  assert_eq(added.3, added_wide.3)
  let removed = graph_apply_population_case(three, "[]", 1000, 1)
  assert_eq(removed.0, "complete")
  assert_true(removed.1 > 6)
  let removed_wide = graph_apply_population_case(three, "[]", 1000, 7)
  assert_eq(removed.3, removed_wide.3)
}

///|
test "Graph delta reserves wide property reference containers before action storage" {
  let wide = "[{\"id\":1,\"src\":1,\"dst\":1," +
    "\"node_name\":\"name\",\"node_label\":\"label\"," +
    "\"node_tag\":\"tag\",\"weight\":10," +
    "\"edge_note\":\"note\"}]"
  let rejected = graph_apply_population_case("[]", wide, 7, 1, wide=true)
  assert_eq(rejected.0, "workspace")
  assert_eq(rejected.1, 0)
  let first_action_only = graph_apply_population_case(
    "[]",
    wide,
    8,
    1,
    wide=true,
  )
  assert_eq(first_action_only.0, "workspace")
  assert_true(first_action_only.1 > 0)
  let accepted = graph_apply_population_case("[]", wide, 1000, 1, wide=true)
  assert_eq(accepted.0, "complete")
  assert_true(accepted.1 >= 8)
  let alternate = graph_apply_population_case("[]", wide, 1000, 7, wide=true)
  assert_eq(accepted.3, alternate.3)
}

///|
test "Graph delta accounts UTF-8 action keys apart from structural entries" {
  let unicode = "[{\"id\":\"😀\",\"src\":\"😀\",\"dst\":\"😀\"," +
    "\"node_name\":\"x\",\"weight\":1}]"
  let accepted = graph_apply_population_case(
    "[]",
    unicode,
    1000,
    1,
    text_id=true,
  )
  assert_eq(accepted.0, "complete")
  assert_true(accepted.4 > accepted.3)
  let one_short = graph_apply_population_case(
    "[]",
    unicode,
    1000,
    7,
    text_id=true,
    scratch_bytes=accepted.4 - 1,
  )
  assert_eq(one_short.0, "bytes")
  assert_true(one_short.4 < accepted.4)
  assert_true(one_short.1 < accepted.1)
  let exact = graph_apply_population_case(
    "[]",
    unicode,
    1000,
    7,
    text_id=true,
    scratch_bytes=accepted.4,
  )
  assert_eq(exact.0, "complete")
  assert_eq(exact.4, accepted.4)
}

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
  let physical_graph_bridge = variant == "projection"
  let graph_task = if physical_graph_bridge {
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
  let provider = if physical_graph_bridge {
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
  let (graph_ops, graph, graph_obligations) = if physical_graph_bridge {
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
    let (output_ops, output) = run_local_managed_test_task(
      installed,
      run,
      graph_task,
      [],
      [],
      graph_task,
      graph_live,
      obligations?=output_obligations,
      carrier_inputs=[(carrier, material)],
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
  if physical_graph_bridge {
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
  let (filtered_ops, filtered) = run_local_managed_test_task(
    installed,
    run,
    5,
    [projected],
    [projected_rows],
    5,
    filtered_live,
    obligations?=graph_publication_obligations(run, true),
    execution_quantum~,
    execution_advances=Some(execution_advances),
  )
  if execution_quantum == 1 {
    assert_true(execution_advances.val > 1)
  }
  let filtered_rows = local_managed_test_rows(filtered_ops)
  let expected_rows = if variant == "normalize_take" {
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
  } else {
    assert_true(filtered_rows[0].contains("\"src\":1"))
    assert_true(filtered_rows[1].contains("\"src\":2"))
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
test "standard Host runs a fused Graph prefix before Relation filter and two consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_graph_chain=true,
    local_carrier_graph_variant="subgraph_filter",
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
  assert_eq(@strategy.graph_task_count(graph), 6)
  assert_eq(@strategy.graph_task_prefix_end(graph, 2), Some(2))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
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
  let prefix_live = Ref(true)
  let (prefix_ops, prefix) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [values_rows],
    2,
    prefix_live,
    obligations?=graph_publication_obligations(run, true),
  )
  let prefix_rows = local_managed_test_rows(prefix_ops)
  assert_eq(prefix_rows.length(), 1)
  assert_true(prefix_rows[0].contains("\"id\":2"))
  let filtered_live = Ref(true)
  let filtered_obligations = graph_publication_obligations(run, true).unwrap()
  let (filtered_ops, filtered) = run_local_managed_test_task(
    installed,
    run,
    3,
    [prefix],
    [prefix_rows],
    3,
    filtered_live,
    obligations=filtered_obligations,
  )
  assert_eq(local_managed_test_rows(filtered_ops), prefix_rows)
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
      assert_eq(contract, @execution.logical_relation_canonical_contract_cid())
      assert_eq(
        cid, "sha256:a2151218d0638a59beb6b366fa8f2d0803e643139fd8c19cae1f9c8d6044f78f",
      )
    }
    _ => fail("fused Graph prefix lost the named Relation identity")
  }
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [filtered],
    [prefix_rows],
    4,
    first_live,
    obligations?=graph_publication_obligations(run, true),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [filtered],
    [prefix_rows],
    5,
    second_live,
    obligations?=graph_publication_obligations(run, true),
  )
  assert_eq(local_managed_test_rows(first_ops).length(), 1)
  assert_eq(local_managed_test_rows(second_ops).length(), 1)
  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  filtered_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (filtered_ops.close)()
  (filtered_ops.cleanup_refresh)() |> ignore
  prefix_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (prefix_ops.close)()
  (prefix_ops.cleanup_refresh)() |> ignore
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
fn run_standard_host_graph_apply_path() -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_graph_chain=true,
    local_carrier_graph_variant="graph_apply_changes",
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 30000,
      attempts: 30,
      holdings: 30,
      transfer_bytes: 800000L,
      retained_bytes: 96000000L,
      execution_bytes: 402653184L,
    }),
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let cleanup_attempts = Ref(0)
  let provider = delayed_cleanup_provider(
    @local_sga_provider.provider(
      carrier_graph_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        sequences[3],
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
  let other_live = Ref(true)
  let (other_ops, other) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    other_live,
    obligations?=graph_publication_obligations(run, true),
  )
  let other_rows = local_managed_test_rows(other_ops)
  let diff_live = Ref(true)
  let (diff_ops, diff) = run_local_managed_test_task(
    installed,
    run,
    3,
    [values, other],
    [values_rows, other_rows],
    3,
    diff_live,
    obligations?=graph_publication_obligations(run, true),
  )
  let diff_rows = local_managed_test_rows(diff_ops)
  assert_eq(diff_rows.length(), 1)
  assert_true(diff_rows[0].contains("\"version\":\"actql-graph-delta/0.1\""))

  let apply_live = Ref(true)
  let apply_obligations = graph_publication_obligations(run, true)
  let (apply_ops, applied) = run_local_managed_test_task(
    installed,
    run,
    4,
    [values, diff],
    [values_rows, diff_rows],
    4,
    apply_live,
    obligations?=apply_obligations,
  )
  let applied_rows = local_managed_test_rows(apply_ops)
  assert_eq(applied_rows.length(), 2)
  assert_true(applied_rows[0].contains("\"id\":1"))
  assert_true(applied_rows[0].contains("\"node_name\":\"changed\""))
  assert_true(applied_rows[1].contains("\"id\":3"))
  assert_true(applied_rows[1].contains("\"node_name\":\"third\""))
  guard apply_obligations is Some(obligations) else {
    fail("missing graph apply publication obligations")
  }
  let requirements = @execution.managed_obligations_identities(obligations)
  let published = requirements.filter(requirement => {
    requirement.domain == @execution.LogicalRelation &&
    requirement.subject == @execution.NamedResult
  })
  assert_eq(published.length(), 1)
  match
    @execution.managed_completed_identity_requirement_status(
      applied,
      published[0],
    ) {
    Some(@execution.EstablishedSourceRetained(contract, cid)) => {
      assert_eq(contract, @execution.logical_relation_canonical_contract_cid())
      assert_eq(
        cid, "sha256:52381836c0f9c56d7d1fd56a8d84dd49031c7eaf602b458b604b2d649c27d7ef",
      )
    }
    _ => fail("Graph apply output did not establish publication identity")
  }

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    5,
    [applied],
    [applied_rows],
    5,
    first_live,
    obligations?=graph_publication_obligations(run, true),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    6,
    [applied],
    [applied_rows],
    6,
    second_live,
    obligations?=graph_publication_obligations(run, true),
  )
  assert_eq(local_managed_test_rows(first_ops).length(), 2)
  assert_eq(local_managed_test_rows(second_ops).length(), 2)

  first_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(applied))

  second_live.val = false
  @strategy.close_captured_task_output(run, 6)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  apply_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (apply_ops.close)()
  assert_false((apply_ops.cleanup_refresh)())
  assert_true((apply_ops.cleanup_refresh)())
  diff_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (diff_ops.close)()
  assert_true((diff_ops.cleanup_refresh)())
  assert_eq(cleanup_attempts.val, 3)
  other_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (other_ops.close)()
  (other_ops.cleanup_refresh)() |> ignore
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
test "standard Host applies an exact Graph delta for two consumers" {
  run_standard_host_graph_apply_path()
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
test "standard Host selects a literal Graph subgraph" {
  run_standard_host_graph_relation_path("subgraph_ids", publication=true)
  run_standard_host_graph_relation_path("subgraph_shared", publication=true)
  run_standard_host_graph_relation_path(
    "subgraph_edges_false",
    publication=true,
  )
  run_standard_host_graph_relation_path(
    "subgraph_node_predicate",
    publication=true,
  )
  run_standard_host_graph_relation_path(
    "subgraph_edge_predicate",
    publication=true,
  )
}

///|
test "standard Host selects a Graph subgraph from a Relation" {
  run_standard_host_graph_relation_path(
    "subgraph_relation_selector",
    publication=true,
  )
  run_standard_host_graph_relation_path(
    "subgraph_relation_selector_nullable",
    publication=true,
  )
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
  run_standard_host_graph_relation_path("union_numeric")
  run_standard_host_graph_relation_path("union_set")
}

///|
test "standard Host averages a repeated Graph list before projection" {
  run_standard_host_graph_relation_path("mean", publication=true)
}

///|
test "standard Host runs a bounded scalar shortest path" {
  run_standard_host_graph_relation_path("shortest_scalar")
  run_standard_host_graph_relation_path("shortest_weighted", publication=true)
  run_standard_host_graph_relation_path("shortest_in", publication=true)
  run_standard_host_graph_relation_path("shortest_both")
  run_standard_host_graph_relation_path("shortest_zero")
}

///|
test "standard Host runs explicit shortest endpoint identity sets" {
  run_standard_host_graph_relation_path("shortest_ids", publication=true)
}

///|
test "standard Host runs Relation-selected shortest endpoint sets" {
  run_standard_host_graph_relation_path(
    "shortest_relation_selector",
    publication=true,
  )
}

///|
test "standard Host runs predicate-selected shortest endpoint sets" {
  run_standard_host_graph_relation_path("shortest_predicate", publication=true)
}

///|
test "standard Host runs nearest shortest selection policies" {
  run_standard_host_graph_relation_path(
    "shortest_nearest_per_source",
    publication=true,
  )
  run_standard_host_graph_relation_path("shortest_nearest_pair")
}

///|
test "standard Host filters scalar shortest paths by edge type" {
  run_standard_host_graph_relation_path("shortest_type_match", publication=true)
  run_standard_host_graph_relation_path("shortest_types_match")
  run_standard_host_graph_relation_path("shortest_type_miss")
  run_standard_host_graph_relation_path("shortest_type_empty")
}

///|
test "standard Host subtracts a property-free Graph before projection" {
  run_standard_host_graph_relation_path("subtract", publication=true)
  run_standard_host_graph_relation_path("subtract_exact", publication=true)
  run_standard_host_graph_relation_path("subtract_numeric")
}
