///|
fn query_checked_program_fixture(
  nullable? : Bool = false,
  catalog? : @environment.SourceRequestContracts? = None,
  dag? : Bool = false,
  dag_count? : Bool = false,
  dag_collections? : Bool = false,
  dag_join? : Bool = false,
  self_join? : Bool = false,
  numeric_dag? : Bool = false,
  sort_take? : Bool = false,
  dag_values? : Bool = false,
  local_values_two_consumer_chain? : Bool = false,
  local_values_two_consumer_filter? : Bool = false,
  local_values_two_consumer_assert? : Bool = false,
  local_values_two_consumer_assert_unique? : Bool = false,
  local_values_two_consumer_sort_take? : Bool = false,
  local_values_two_consumer_relation_variant? : String = "",
  local_values_managed_variant? : String = "",
  local_values_group_chain? : Bool = false,
  local_values_group_variant? : String = "keyed",
  local_values_window_chain? : Bool = false,
  local_values_window_variant? : String = "fixed",
  local_values_window_group_chain? : Bool = false,
  local_values_window_group_variant? : String = "fixed_keyed",
  local_values_lag_chain? : Bool = false,
  local_values_lag_variant? : String = "literal",
  local_values_watermark_chain? : Bool = false,
  local_values_watermark_variant? : String = "fixed_mark",
  local_carrier_events_chain? : Bool = false,
  local_carrier_events_variant? : String = "watermark",
  local_carrier_graph_chain? : Bool = false,
  local_carrier_graph_variant? : String = "projection",
  local_time_series_chain? : Bool = false,
  local_carrier_vectors_chain? : Bool = false,
  local_carrier_vectors_variant? : String = "normalize",
  local_supplied_ranking_chain? : Bool = false,
  local_supplied_ranking_policy? : String = "\"max\"",
  local_vector_expression_chain? : Bool = false,
  local_values_analytic_chain? : Bool = false,
  local_values_analytic_variant? : String = "baseline",
  local_values_append_chain? : Bool = false,
  local_values_append_variant? : String = "local",
  local_values_cross_chain? : Bool = false,
  local_values_cross_direct? : Bool = false,
  local_values_cross_external_chain? : Bool = false,
  local_values_cross_external_filter? : Bool = false,
  local_values_cross_singleton? : Bool = false,
  local_values_cross_output_guard? : Int? = None,
  local_values_set_operation? : String = "",
  local_values_set_duplicates? : String = "all",
  local_values_join_chain? : Bool = false,
  local_values_join_kind? : String = "inner",
  local_values_join_imported_full? : Bool = false,
  local_values_interval_chain? : Bool = false,
  local_values_asof_chain? : Bool = false,
  local_values_sequence_chain? : Bool = false,
  local_values_nest_chain? : Bool = false,
  local_values_unary_chain? : String? = None,
  local_select_qualified_chain? : Bool = false,
  linear_compute_stages? : Int = 0,
  join_steps? : Array[Int] = [0],
  managed_publication? : Bool = false,
  acquisition_filter? : String = "id > $minimum",
  compute_filter? : String = "id > 2",
  parameter_json? : String = "{\"minimum\":1}",
) -> @program_check.CheckedProgram raise {
  let text =
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}}],"results":{"out":{"from":{"stage":"a","result":"r"}}}}
  let text = if dag {
    text.replace(
      old="}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
      new="},{\"id\":\"compute_a\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id > 2\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}},{\"id\":\"compute_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id > 0\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}},{\"id\":\"compute_c\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id < 9\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}}],\"results\":{\"b\":{\"from\":{\"stage\":\"compute_b\",\"result\":\"r\"}},\"c\":{\"from\":{\"stage\":\"compute_c\",\"result\":\"r\"}}}}",
    )
  } else {
    text
  }
  let text = if local_values_group_chain {
    local_values_group_program(local_values_group_variant)
  } else {
    text
  }
  let text = if local_values_window_chain {
    local_values_window_program(local_values_window_variant)
  } else {
    text
  }
  let text = if local_values_window_group_chain {
    local_values_window_group_program(local_values_window_group_variant)
  } else {
    text
  }
  let text = if local_values_lag_chain {
    local_values_lag_program(local_values_lag_variant)
  } else {
    text
  }
  let text = if local_values_watermark_chain {
    local_values_watermark_program(local_values_watermark_variant)
  } else {
    text
  }
  let text = if local_carrier_events_chain {
    local_carrier_events_program(variant=local_carrier_events_variant)
  } else {
    text
  }
  let text = if local_carrier_graph_chain {
    local_carrier_graph_program(variant=local_carrier_graph_variant)
  } else {
    text
  }
  let text = if local_time_series_chain {
    local_time_series_program()
  } else {
    text
  }
  let text = if local_values_interval_chain {
    local_values_interval_program()
  } else {
    text
  }
  let text = if local_values_asof_chain {
    local_values_asof_program()
  } else {
    text
  }
  let text = if local_values_sequence_chain {
    local_values_sequence_program()
  } else {
    text
  }
  let text = if local_carrier_vectors_chain {
    local_carrier_vectors_program(variant=local_carrier_vectors_variant)
  } else {
    text
  }
  let text = if local_supplied_ranking_chain {
    local_supplied_ranking_program(policy=local_supplied_ranking_policy)
  } else {
    text
  }
  let text = if local_vector_expression_chain {
    local_vector_expression_program()
  } else {
    text
  }
  let text = if local_values_analytic_chain {
    local_values_analytic_program(local_values_analytic_variant)
  } else {
    text
  }
  let text = if local_values_two_consumer_chain {
    let program =
      #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"values_a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":true},"label":{"type":"string","nullable":false}},"rows":[{"id":null,"label":"none"},{"id":1,"label":"one"}]} ,"as":"out"}],"results":{"r":{"from":"out","fields":["id","label"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"values_a","result":"r"}}},"steps":[{"select":["id","label"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","label"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"values_a","result":"r"}}},"steps":[{"select":["label","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["label","id"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
    if local_values_two_consumer_relation_variant == "separate_sort_take" ||
      local_values_two_consumer_relation_variant == "separate_filter_sort_take" ||
      local_values_two_consumer_relation_variant == "chained_filter_sort_take" {
      let separated = program
        .replace(
          old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
          new="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"ordered\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"values_a\",\"result\":\"r\"}}},\"steps\":[{\"from\":\"x\",\"sort\":[{\"field\":\"id\",\"dir\":\"desc\",\"nulls\":\"last\"}],\"as\":\"ordered_rows\"},{\"from\":\"ordered_rows\",\"take\":1,\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
        )
        .replace(
          old="\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"values_a\"",
          new="\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"ordered\"",
        )
        .replace(
          old="\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"values_a\"",
          new="\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"ordered\"",
        )
      if local_values_two_consumer_relation_variant ==
        "separate_filter_sort_take" {
        separated.replace(
          old="\"steps\":[{\"from\":\"x\",\"sort\"",
          new="\"steps\":[{\"from\":\"x\",\"filter\":\"true\",\"as\":\"filtered\"},{\"from\":\"filtered\",\"sort\"",
        )
      } else if local_values_two_consumer_relation_variant ==
        "chained_filter_sort_take" {
        separated.replace(
          old="\"id\":\"ordered\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"values_a\",\"result\":\"r\"}}},\"steps\":[",
          new="\"id\":\"filtered\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"values_a\",\"result\":\"r\"}}},\"steps\":[{\"from\":\"x\",\"filter\":\"true\",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"ordered\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"filtered\",\"result\":\"r\"}}},\"steps\":[",
        )
      } else {
        separated
      }
    } else if local_values_two_consumer_sort_take {
      program.replace(
        old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
        new="\"as\":\"values_rows\"},{\"from\":\"values_rows\",\"sort\":[{\"field\":\"id\",\"dir\":\"desc\",\"nulls\":\"last\"}],\"as\":\"ordered\"},{\"from\":\"ordered\",\"take\":1,\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
      )
    } else if local_values_two_consumer_assert_unique {
      program.replace(
        old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
        new="\"as\":\"values_rows\"},{\"from\":\"values_rows\",\"assert_rows\":{\"unique_by\":[\"label\"]},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
      )
    } else if local_values_two_consumer_assert {
      program.replace(
        old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
        new="\"as\":\"values_rows\"},{\"from\":\"values_rows\",\"assert_rows\":{\"where\":\"1 > 0\"},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
      )
    } else if local_values_two_consumer_filter {
      program.replace(
        old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
        new="\"as\":\"values_rows\"},{\"from\":\"values_rows\",\"filter\":\"id > 0\",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
      )
    } else if local_values_two_consumer_relation_variant == "take" {
      program.replace(
        old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
        new="\"as\":\"values_rows\"},{\"from\":\"values_rows\",\"take\":1,\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
      )
    } else if local_values_two_consumer_relation_variant == "select" {
      program.replace(
        old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
        new="\"as\":\"values_rows\"},{\"from\":\"values_rows\",\"select\":[\"id\",\"label\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
      )
    } else if local_values_two_consumer_relation_variant == "derive" {
      program.replace(
        old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
        new="\"as\":\"values_rows\"},{\"from\":\"values_rows\",\"derive\":{\"copy\":\"label\"},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\",\"copy\"]}}},{\"id\":\"consumer_a\"",
      )
    } else if local_values_two_consumer_relation_variant == "distinct" {
      program.replace(
        old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
        new="\"as\":\"values_rows\"},{\"from\":\"values_rows\",\"distinct\":true,\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"label\"]}}},{\"id\":\"consumer_a\"",
      )
    } else {
      program
    }
  } else {
    text
  }
  let text = if local_values_managed_variant != "" {
    let rows = if local_values_managed_variant == "empty" {
      "[]"
    } else if local_values_managed_variant == "thirty_one" {
      "[" +
      Array::makei(31, index => "{\"id\":" + index.to_string() + "}").join(",") +
      "]"
    } else {
      "[{\"items\":{\"literal\":[{\"name\":\"a\",\"score\":1},{\"name\":\"b\",\"score\":2}]},\"meta\":{\"literal\":{\"active\":true}}}]"
    }
    let schema = if local_values_managed_variant == "empty" ||
      local_values_managed_variant == "thirty_one" {
      "{\"id\":{\"type\":\"number\",\"nullable\":false}}"
    } else {
      "{\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"name\":{\"type\":\"string\",\"nullable\":false},\"score\":{\"type\":\"number\",\"nullable\":false}}}},\"meta\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"active\":{\"type\":\"boolean\",\"nullable\":false}}}}"
    }
    let fields = if local_values_managed_variant == "empty" ||
      local_values_managed_variant == "thirty_one" {
      "[\"id\"]"
    } else {
      "[\"items\",\"meta\"]"
    }
    let reversed = if local_values_managed_variant == "empty" ||
      local_values_managed_variant == "thirty_one" {
      fields
    } else {
      "[\"meta\",\"items\"]"
    }
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{\"minimum\":{\"type\":\"number\",\"nullable\":false}},\"stages\":[" +
    "{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}}," +
    "{\"id\":\"values_a\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    rows +
    "},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
    fields +
    "}}}," +
    "{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"values_a\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
    fields +
    ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
    fields +
    "}}}," +
    "{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"values_a\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
    reversed +
    ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
    reversed +
    "}}}],\"results\":{\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
  } else {
    text
  }
  let text = if local_values_append_chain {
    local_values_append_program(local_values_append_variant)
  } else {
    text
  }
  let text = if local_values_cross_chain {
    let cross =
      #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"crossed","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]} ,"as":"left_raw"},{"from":"left_raw","distinct":["id"],"as":"left_rows"},{"values":{"schema":{"tag":{"type":"string","nullable":false}},"rows":[{"tag":"a"}__RIGHT_EXTRA__]} ,"as":"right_raw"},{"from":"right_raw","distinct":["tag"],"as":"right_rows"},{"from":"left_rows","cross_join":{"with":"right_rows"__RIGHT_ONE____OUTPUT_GUARD__,"select":{"id":"left.id","tag":"right.tag"}},"as":"out"}],"results":{"r":{"from":"out","fields":["id","tag"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"crossed","result":"r"}}},"steps":[{"select":["id","tag"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","tag"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"crossed","result":"r"}}},"steps":[{"select":["tag","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["tag","id"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
    let cross = if local_values_cross_direct {
      cross
      .replace(
        old=",{\"from\":\"left_raw\",\"distinct\":[\"id\"],\"as\":\"left_rows\"}",
        new="",
      )
      .replace(
        old=",{\"from\":\"right_raw\",\"distinct\":[\"tag\"],\"as\":\"right_rows\"}",
        new="",
      )
      .replace(old="\"as\":\"left_raw\"", new="\"as\":\"left_rows\"")
      .replace(old="\"as\":\"right_raw\"", new="\"as\":\"right_rows\"")
    } else {
      cross
    }
    cross
    .replace(
      old="__RIGHT_EXTRA__",
      new=if local_values_cross_singleton { "" } else { ",{\"tag\":\"b\"}" },
    )
    .replace(
      old="__RIGHT_ONE__",
      new=if local_values_cross_singleton {
        ",\"right_rows\":\"one\""
      } else {
        ""
      },
    )
    .replace(
      old="__OUTPUT_GUARD__",
      new=match local_values_cross_output_guard {
        Some(value) => ",\"max_output_rows\":" + value.to_string()
        None => ""
      },
    )
  } else {
    text
  }
  let text = if local_values_cross_external_chain {
    let program = local_values_cross_external_program()
    if local_values_cross_external_filter {
      program.replace(
        old="\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"tag\"]}}},{\"id\":\"consumer_a\"",
        new="\"as\":\"crossed_rows\"},{\"from\":\"crossed_rows\",\"filter\":\"id > 0\",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"tag\"]}}},{\"id\":\"consumer_a\"",
      )
    } else {
      program
    }
  } else {
    text
  }
  let text = if local_values_set_operation != "" {
    let set_text =
      #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"set_rows","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":true},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"a"},{"id":1,"label":"a"},{"id":2,"label":"b"},{"id":null,"label":"n"}]},"as":"left_rows"},{"values":{"schema":{"label":{"type":"string","nullable":false},"id":{"type":"number","nullable":true}},"rows":[{"label":"a","id":1},{"label":"c","id":3}]},"as":"right_rows"},{"from":"left_rows","__set_operation__":{"with":"right_rows","duplicates":"__set_duplicates__"},"as":"out"}],"results":{"r":{"from":"out","fields":["id","label"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"set_rows","result":"r"}}},"steps":[{"select":["id","label"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","label"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"set_rows","result":"r"}}},"steps":[{"select":["label","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["label","id"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
    set_text
    .replace(old="__set_operation__", new=local_values_set_operation)
    .replace(old="__set_duplicates__", new=local_values_set_duplicates)
  } else {
    text
  }
  let text = if local_values_join_chain {
    (
      #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"left_values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":true},"l":{"type":"string","nullable":false}},"rows":[{"id":1,"l":"l1"},{"id":1,"l":"l2"},{"id":null,"l":"ln"},{"id":2,"l":"l3"}]} ,"as":"out"}],"results":{"r":{"from":"out","fields":["id","l"]}}},{"id":"right_values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":true},"r":{"type":"string","nullable":false}},"rows":[{"id":1,"r":"r1"},{"id":1,"r":"r2"},{"id":null,"r":"rn"},{"id":3,"r":"r3"},{"id":4,"r":"r4"}]} ,"as":"out"}],"results":{"r":{"from":"out","fields":["id","r"]}}},{"id":"joined","inputs":{"l":{"result":{"stage":"left_values","result":"r"}},"r":{"result":{"stage":"right_values","result":"r"}}},"steps":[{"from":"l","join":{"with":"r","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id","l":"left.l","r":"right.r"}},"as":"out"}],"results":{"r":{"from":"out","fields":["id","l","r"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"joined","result":"r"}}},"steps":[{"select":["id","l","r"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","l","r"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"joined","result":"r"}}},"steps":[{"select":["r","l","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["r","l","id"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
    )
  } else {
    text
  }
  let text = if local_values_join_imported_full {
    (
      #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"left_values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"l":{"type":"string","nullable":false}},"rows":[{"id":1,"l":"l1"},{"id":1,"l":"l2"},{"id":2,"l":"l3"}]} ,"as":"left_raw"},{"from":"left_raw","distinct":["id","l"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","l"]}}},{"id":"right_values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"r":{"type":"string","nullable":false}},"rows":[{"id":1,"r":"r1"},{"id":1,"r":"r2"},{"id":3,"r":"r3"},{"id":4,"r":"r4"}]} ,"as":"right_raw"},{"from":"right_raw","distinct":["id","r"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","r"]}}},{"id":"joined","inputs":{"l":{"result":{"stage":"left_values","result":"r"}},"r":{"result":{"stage":"right_values","result":"r"}}},"steps":[{"from":"l","join":{"with":"r","kind":"full","on":[{"left":"id","right":"id"}],"select":{"id":"left.id","l":"left.l","r":"right.r"}},"as":"out"}],"results":{"r":{"from":"out","fields":["id","l","r"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"joined","result":"r"}}},"steps":[{"select":["id","l","r"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","l","r"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"joined","result":"r"}}},"steps":[{"select":["r","l","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["r","l","id"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
    )
  } else {
    text
  }
  let text = if local_values_join_chain &&
    local_values_join_kind == "full" &&
    !local_values_join_imported_full {
    (
      #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"joined","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"l":{"type":"string","nullable":false}},"rows":[{"id":1,"l":"l1"},{"id":1,"l":"l2"},{"id":2,"l":"l3"}]},"as":"left_raw"},{"from":"left_raw","distinct":["id","l"],"as":"left_rows"},{"values":{"schema":{"id":{"type":"number","nullable":false},"r":{"type":"string","nullable":false}},"rows":[{"id":1,"r":"r1"},{"id":1,"r":"r2"},{"id":3,"r":"r3"},{"id":4,"r":"r4"}]},"as":"right_raw"},{"from":"right_raw","distinct":["id","r"],"as":"right_rows"},{"from":"left_rows","join":{"with":"right_rows","kind":"full","on":[{"left":"id","right":"id"}],"select":{"id":"left.id","l":"left.l","r":"right.r"}},"as":"joined_raw"},{"from":"joined_raw","distinct":true,"as":"unique"},{"from":"unique","sort":[{"id":"asc"},{"l":"asc"},{"r":"asc"}],"as":"out"}],"results":{"r":{"from":"out","fields":["id","l","r"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"joined","result":"r"}}},"steps":[{"select":["id","l","r"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","l","r"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"joined","result":"r"}}},"steps":[{"select":["r","l","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["r","l","id"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
    )
  } else {
    text
  }
  let text = if local_values_nest_chain {
    local_values_nest_program()
  } else {
    text
  }
  let text = if local_values_join_chain &&
    local_values_join_kind == "full" &&
    !local_values_join_imported_full {
    text.replace(
      old="{\"select\":[\"r\",\"l\",\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"r\",\"l\",\"id\"]}}}",
      new="{\"select\":[\"id\",\"l\",\"r\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"l\",\"r\"]}}}",
    )
  } else {
    text
  }
  let text = if local_values_join_chain && local_values_join_kind != "inner" {
    text.replace(
      old="\"kind\":\"inner\"",
      new="\"kind\":\"" + local_values_join_kind + "\"",
    )
  } else {
    text
  }
  let text = if local_values_join_chain &&
    (local_values_join_kind == "semi" || local_values_join_kind == "anti") {
    text
    .replace(
      old="\"select\":{\"id\":\"left.id\",\"l\":\"left.l\",\"r\":\"right.r\"}",
      new="\"select\":{\"id\":\"left.id\",\"l\":\"left.l\"}",
    )
    .replace_all(
      old="\"fields\":[\"id\",\"l\",\"r\"]",
      new="\"fields\":[\"id\",\"l\"]",
    )
    .replace(
      old="\"select\":[\"id\",\"l\",\"r\"]",
      new="\"select\":[\"id\",\"l\"]",
    )
    .replace(
      old="\"select\":[\"r\",\"l\",\"id\"]",
      new="\"select\":[\"l\",\"id\"]",
    )
    .replace(
      old="\"fields\":[\"r\",\"l\",\"id\"]",
      new="\"fields\":[\"l\",\"id\"]",
    )
  } else {
    text
  }
  let text = match local_values_unary_chain {
    None => text
    Some(kind) => local_values_unary_program(kind)
  }
  let text = if local_select_qualified_chain {
    local_select_qualified_program()
  } else {
    text
  }
  let text = if sort_take {
    text.replace(
      old="{\"filter\":\"id > 2\"},{\"select\":[\"id\"],\"as\":\"out\"}",
      new="{\"sort\":[{\"id\":\"desc\"}]},{\"take\":2,\"as\":\"out\"}",
    )
  } else {
    text
  }
  let text = if dag_values {
    text
    .replace(
      old="{\"id\":\"compute_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id > 0\"},{\"select\":[\"id\"],\"as\":\"out\"}]",
      new="{\"id\":\"compute_b\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":7}]},\"as\":\"out\"}]",
    )
    .replace(
      old="\"results\":{\"b\":{\"from\":{\"stage\":\"compute_b\",\"result\":\"r\"}},\"c\":{\"from\":{\"stage\":\"compute_c\",\"result\":\"r\"}}}",
      new="\"results\":{\"c\":{\"from\":{\"stage\":\"compute_c\",\"result\":\"r\"}}}",
    )
  } else {
    text
  }
  let text = if dag_count {
    text.replace(
      old="{\"filter\":\"id > 2\"},{\"select\":[\"id\"],\"as\":\"out\"}",
      new="{\"group\":{\"by\":[],\"aggregates\":{\"id\":{\"fn\":\"count\"}}},\"as\":\"out\"}",
    )
  } else {
    text
  }
  let text = if dag_collections {
    text.replace(
      old="{\"filter\":\"id > 2\"},{\"select\":[\"id\"],\"as\":\"out\"}",
      new="{\"derive\":{\"label\":\"to_string(id)\"},\"as\":\"derived\"},{\"from\":\"derived\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"unique\"},{\"from\":\"unique\",\"group\":{\"by\":[],\"aggregates\":{\"items\":{\"fn\":\"array_agg\",\"field\":\"id\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":5},\"n\":{\"fn\":\"count\"},\"text\":{\"fn\":\"string_agg\",\"field\":\"label\",\"delimiter\":\"|\",\"order_by\":[{\"id\":\"asc\"}],\"max_bytes\":17}}},\"as\":\"grouped\"},{\"from\":\"grouped\",\"select\":[{\"id\":\"n\"}],\"as\":\"out\"}",
    )
  } else {
    text
  }
  let text = if dag_join {
    let joined = text.replace(
      old="\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id < 9\"},{\"select\":[\"id\"],\"as\":\"out\"}]",
      new="\"inputs\":{\"l\":{\"result\":{\"stage\":\"compute_a\",\"result\":\"r\"}},\"r\":{\"result\":{\"stage\":\"" +
        (if self_join { "compute_a" } else { "compute_b" }) +
        "\",\"result\":\"r\"}}},\"steps\":[{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}},\"from\":\"l\",\"as\":\"out\"}]",
    )
    joined.replace(
      old="}],\"results\":{\"b\":{\"from\":{\"stage\":\"compute_b\",\"result\":\"r\"}},\"c\":{\"from\":{\"stage\":\"compute_c\",\"result\":\"r\"}}}}",
      new="},{\"id\":\"count_d\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_c\",\"result\":\"r\"}}},\"steps\":[{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"n\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"count_d\",\"result\":\"r\"}}}}",
    )
  } else {
    text
  }
  let text = if dag_join && join_steps != [0] {
    let start = "{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}},\"from\":\"l\",\"as\":\"out\"}"
    let join = "{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}}"
    text.replace(
      old=start,
      new="{\"filter\":\"id > 0\",\"from\":\"l\"}," +
        (if join_steps.length() == 2 { join + "}," } else { "" }) +
        join +
        ",\"as\":\"out\"}",
    )
  } else {
    text
  }
  let text = if numeric_dag {
    text.replace(old="id < 9", new="id > 2")
  } else {
    text
  }
  let text = if managed_publication {
    text.replace(
      old="\"results\":{\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
      new=if local_carrier_graph_chain {
        "\"results\":{\"published\":{\"from\":{\"stage\":" +
        (if local_carrier_graph_variant == "graph_apply_changes" {
          "\"apply\""
        } else {
          "\"graph\""
        }) +
        ",\"result\":\"r\"}}}}"
      } else if local_carrier_events_chain {
        "\"results\":{\"published\":{\"from\":{\"stage\":" +
        "\"events\",\"result\":\"r\"}}}}"
      } else if local_carrier_vectors_chain {
        "\"results\":{\"published\":{\"from\":{\"stage\":" +
        (if local_carrier_vectors_variant.has_prefix("nearest") {
          "\"nearest\""
        } else if local_carrier_vectors_variant.has_prefix("ranking") {
          "\"fusion\""
        } else {
          "\"vectors\""
        }) +
        ",\"result\":\"r\"}}}}"
      } else if local_time_series_chain {
        "\"results\":{\"published\":{\"from\":{\"stage\":" +
        "\"series\",\"result\":\"r\"}}}}"
      } else if local_values_interval_chain || local_values_asof_chain {
        "\"results\":{\"published\":{\"from\":{\"stage\":" +
        "\"joined\",\"result\":\"r\"}}}}"
      } else if local_values_sequence_chain {
        "\"results\":{\"published\":{\"from\":{\"stage\":" +
        "\"matched\",\"result\":\"r\"}}}}"
      } else {
        "\"results\":{\"published\":{\"from\":{\"stage\":" +
        "\"compute_b\",\"result\":\"r\"}}}}"
      },
    )
  } else {
    text
  }
  let text = if linear_compute_stages > 0 {
    linear_compute_program(linear_compute_stages)
  } else {
    text
  }
  let text = text.replace(old="id > $minimum", new=acquisition_filter)
  let text = text.replace(old="id > 2", new=compute_filter)
  let input_limits : @syntax.Limits = {
    source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    tree: {
      max_nodes: 100000,
      max_depth: 100,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
    max_stages: Int::max(10, linear_compute_stages + 1),
  }
  let program = @syntax.parse(text, input_limits, format=Json).unwrap()
  let policies = @environment.value_contract_policies(
    @environment.source_view_shape_values(
      @environment.read_mode_shapes(
        @environment.carrier_schema_modes(
          @environment.source_request_carriers(
            if catalog is Some(catalog) {
              catalog
            } else if nullable {
              query_nullable_catalog_fixture()
            } else {
              query_program_catalog_fixture(
                analytic=local_values_analytic_chain,
                schema_snapshots=if local_supplied_ranking_chain {
                  local_supplied_ranking_schema_snapshots()
                } else {
                  "[]"
                },
              )
            },
          ),
        ),
      ),
    ),
  )
  let environment = @environment.contract_registry_environment(
    @environment.catalog_registry(
      @environment.reference_contents(
        @environment.data_policy_references(policies),
      ),
    ),
  )
  let environment = if local_carrier_graph_chain {
    local_carrier_graph_environment(environment)
  } else {
    environment
  }
  let evidence = if local_carrier_graph_chain &&
    local_carrier_graph_variant.has_prefix("components_") {
    [components_capacity_material(environment, "graph")]
  } else if local_carrier_graph_chain &&
    local_carrier_graph_variant.has_prefix("reach_") {
    [traversal_capacity_material(environment, "graph", "reach")]
  } else if local_carrier_graph_chain &&
    local_carrier_graph_variant.has_prefix("traverse_") {
    [
      traversal_capacity_material(
        environment,
        "graph",
        "traverse",
        input_rows=if local_carrier_graph_variant.has_prefix(
            "traverse_pattern_multi",
          ) {
          3L
        } else {
          2L
        },
        output_rows=if local_carrier_graph_variant == "traverse_ids" ||
          local_carrier_graph_variant == "traverse_predicate" ||
          local_carrier_graph_variant == "traverse_predicate_paths" ||
          local_carrier_graph_variant == "traverse_pattern_all_predicates" ||
          local_carrier_graph_variant == "traverse_relation_selector" ||
          local_carrier_graph_variant == "traverse_relation_paths" {
          4L
        } else if local_carrier_graph_variant == "traverse_pattern_multi" {
          3L
        } else {
          2L
        },
        selector_rows=if local_carrier_graph_variant ==
          "traverse_relation_selector" ||
          local_carrier_graph_variant == "traverse_relation_paths" {
          Some(3L)
        } else {
          None
        },
        path_emission=local_carrier_graph_variant == "traverse_paths" ||
          local_carrier_graph_variant == "traverse_relation_paths" ||
          local_carrier_graph_variant == "traverse_predicate_paths" ||
          local_carrier_graph_variant.has_prefix("traverse_pattern_multi_paths") ||
          local_carrier_graph_variant == "traverse_in_paths" ||
          local_carrier_graph_variant == "traverse_both_paths" ||
          local_carrier_graph_variant == "traverse_zero_paths" ||
          local_carrier_graph_variant == "traverse_type_empty_paths",
      ),
    ]
  } else if local_carrier_graph_chain &&
    local_carrier_graph_variant.has_prefix("shortest_") {
    [
      traversal_capacity_material(
        environment,
        "graph",
        "shortest_path",
        output_rows=if local_carrier_graph_variant == "shortest_ids" {
          6L
        } else if local_carrier_graph_variant == "shortest_relation_selector" {
          9L
        } else if local_carrier_graph_variant == "shortest_predicate" {
          4L
        } else if local_carrier_graph_variant == "shortest_nearest_per_source" {
          2L
        } else {
          1L
        },
        selector_rows=if local_carrier_graph_variant ==
          "shortest_relation_selector" {
          Some(3L)
        } else {
          None
        },
        predicate_selector=local_carrier_graph_variant == "shortest_predicate",
      ),
    ]
  } else if dag_join {
    [join_graph_capacity_material(environment, "compute_c", steps=join_steps)]
  } else if local_values_cross_external_chain {
    let left = query_capacity_proof(
      "actql.bound.values",
      2L,
      "{\"op\":\"source\"}",
      step=0,
    )
    let right = query_capacity_proof(
      "actql.bound.values",
      3L,
      "{\"op\":\"source\"}",
      step=0,
    )
    let joined = query_capacity_proof(
      "actql.bound.join-output",
      6L,
      "{\"op\":\"source\"}",
      inputs=[
        @wire.cid(@wire.program_proof_witness(left)),
        @wire.cid(@wire.program_proof_witness(right)),
      ],
      step=0,
    )
    [
      join_graph_capacity_material(
        environment,
        "crossed",
        steps=[0],
        proofs=[left, right, joined],
        candidates=[joined],
      ),
    ]
  } else if local_values_cross_chain {
    let left = query_capacity_proof(
      "actql.bound.values",
      2L,
      "{\"op\":\"source\"}",
      step=0,
    )
    let right = query_capacity_proof(
      "actql.bound.values",
      if local_values_cross_singleton {
        1L
      } else {
        2L
      },
      "{\"op\":\"source\"}",
      step=if local_values_cross_direct { 1 } else { 2 },
    )
    let joined = query_capacity_proof(
      "actql.bound.join-output",
      if local_values_cross_singleton {
        2L
      } else {
        4L
      },
      "{\"op\":\"source\"}",
      inputs=[
        @wire.cid(@wire.program_proof_witness(left)),
        @wire.cid(@wire.program_proof_witness(right)),
      ],
      step=if local_values_cross_direct { 2 } else { 4 },
    )
    [
      join_graph_capacity_material(
        environment,
        "crossed",
        steps=[if local_values_cross_direct { 2 } else { 4 }],
        proofs=[left, right, joined],
        candidates=[joined],
      ),
    ]
  } else if local_select_qualified_chain {
    let left = query_capacity_proof(
      "actql.bound.values",
      2L,
      "{\"op\":\"source\"}",
      step=0,
    )
    let right = query_capacity_proof(
      "actql.bound.values",
      3L,
      "{\"op\":\"source\"}",
      step=0,
    )
    let joined = query_capacity_proof(
      "actql.bound.join-output",
      6L,
      "{\"op\":\"source\"}",
      inputs=[
        @wire.cid(@wire.program_proof_witness(left)),
        @wire.cid(@wire.program_proof_witness(right)),
      ],
      step=0,
    )
    [
      join_graph_capacity_material(
        environment,
        "selected",
        steps=[0],
        proofs=[left, right, joined],
        candidates=[joined],
      ),
    ]
  } else if local_carrier_events_chain &&
    local_carrier_events_variant == "sequence" {
    let input = query_capacity_proof(
      "actql.bound.values",
      3L,
      "{\"op\":\"source\"}",
      step=0,
    )
    [sequence_capacity_material(environment, input, stage="events", step=1)]
  } else if local_values_sequence_chain {
    let input = query_capacity_proof(
      "actql.bound.values",
      5L,
      "{\"op\":\"source\"}",
      step=0,
    )
    [sequence_capacity_material(environment, input)]
  } else if local_values_interval_chain || local_values_asof_chain {
    let left = query_capacity_proof(
      "actql.bound.values",
      if local_values_asof_chain {
        1L
      } else {
        3L
      },
      "{\"op\":\"source\"}",
      step=0,
    )
    let right = query_capacity_proof(
      "actql.bound.values",
      if local_values_asof_chain {
        3L
      } else {
        4L
      },
      "{\"op\":\"source\"}",
      step=0,
    )
    let joined = query_capacity_proof(
      if local_values_asof_chain {
        "actql.bound.asof-left"
      } else {
        "actql.bound.join-output"
      },
      if local_values_asof_chain {
        1L
      } else {
        12L
      },
      if local_values_asof_chain {
        "{\"input\":\"" +
        @wire.cid(@wire.program_proof_witness(left)) +
        "\",\"op\":\"preserve\"}"
      } else {
        "{\"op\":\"source\"}"
      },
      inputs=if local_values_asof_chain {
        [@wire.cid(@wire.program_proof_witness(left))]
      } else {
        [
          @wire.cid(@wire.program_proof_witness(left)),
          @wire.cid(@wire.program_proof_witness(right)),
        ]
      },
      step=0,
    )
    [
      join_graph_capacity_material(
        environment,
        "joined",
        steps=[0],
        proofs=[left, right, joined],
        candidates=[joined],
      ),
    ]
  } else if local_values_join_chain {
    let same_stage_full = local_values_join_kind == "full" &&
      !local_values_join_imported_full
    let imported_full = local_values_join_imported_full
    let left = query_capacity_proof(
      "actql.bound.values",
      if same_stage_full || imported_full {
        3L
      } else {
        4L
      },
      "{\"op\":\"source\"}",
      step=0,
    )
    let right = query_capacity_proof(
      "actql.bound.values",
      if same_stage_full || imported_full {
        4L
      } else {
        5L
      },
      "{\"op\":\"source\"}",
      step=if same_stage_full { 2 } else { 0 },
    )
    let left_cid = @wire.cid(@wire.program_proof_witness(left))
    let right_cid = @wire.cid(@wire.program_proof_witness(right))
    let joined = query_capacity_proof(
      "actql.bound.join-output",
      if same_stage_full || imported_full {
        12L
      } else if local_values_join_kind == "semi" ||
        local_values_join_kind == "anti" {
        4L
      } else {
        20L
      },
      "{\"op\":\"source\"}",
      inputs=[left_cid, right_cid],
      step=if same_stage_full { 4 } else { 0 },
    )
    [
      join_graph_capacity_material(
        environment,
        "joined",
        steps=if same_stage_full { [4] } else { [0] },
        proofs=[left, right, joined],
        candidates=[joined],
      ),
    ]
  } else {
    []
  }
  match
    @program_check.check_parsed_with_evidence(
      program,
      @program_check.checking_environment(
        environment,
        {
          text_time: false,
          veca: local_carrier_vectors_chain ||
          local_vector_expression_chain ||
          local_supplied_ranking_chain,
        },
        {
          rela: true,
          sga: local_carrier_graph_chain,
          tea: local_carrier_events_chain ||
          local_time_series_chain ||
          local_values_interval_chain ||
          local_values_asof_chain ||
          local_values_sequence_chain,
          calendar: false,
          text_rank: false,
        },
        numeric_profile=if (
            local_values_group_chain &&
            (
              local_values_group_variant == "numeric" ||
              local_values_group_variant == "numeric_filter" ||
              local_values_group_variant == "numeric_regroup"
            )
          ) ||
          (
            local_values_window_group_chain &&
            local_values_window_group_variant == "numeric"
          ) ||
          (
            local_values_analytic_chain &&
            (
              local_values_analytic_variant == "numeric" ||
              local_values_analytic_variant == "numeric_take"
            )
          ) ||
          local_values_unary_chain == Some("pivot_numeric") {
          Some(@numeric.builtin_profile())
        } else {
          None
        },
      ),
      Some(input_cursor(parameter_json)),
      evidence,
      {
        input: input_limits,
        compilation: query_checked_limits(
          Int::max(
            2 * (linear_compute_stages + 1),
            if local_carrier_graph_variant == "graph_apply_changes" {
              12
            } else if local_values_join_chain &&
              local_values_join_kind == "full" {
              20
            } else {
              10
            },
          ),
          parameter_count=if local_carrier_vectors_variant == "score_parameter" ||
            local_carrier_events_variant == "window_parameter" {
            2
          } else {
            1
          },
        ),
      },
    ) {
    Checked(value) => value
    NeedsInputs(_) => fail("fixture requires complete checking inputs")
    Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
  }
}

///|
fn linear_compute_program(count : Int) -> String raise {
  if count < 1 || count > 32 {
    fail("invalid linear compute fixture")
  }
  let stages = Array::makei(count, index => {
    let prior = if index == 0 {
      "a"
    } else {
      "linear_" + (index - 1).to_string()
    }
    ",{\"id\":\"linear_" +
    index.to_string() +
    "\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"" +
    prior +
    "\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id >= 0\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}}"
  }).join("")
  "{\"version\":\"actql/0.1\",\"id\":\"linear-placement\",\"params\":{\"minimum\":{\"type\":\"number\",\"nullable\":false}},\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}}" +
  stages +
  "],\"results\":{\"out\":{\"from\":{\"stage\":\"linear_" +
  (count - 1).to_string() +
  "\",\"result\":\"r\"}}}}"
}

///|
fn local_values_nest_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"parents","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"key":{"type":"number","nullable":true}},"rows":[{"id":1,"key":1},{"id":2,"key":1},{"id":3,"key":null},{"id":4,"key":2}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","key"]}}},{"id":"children","inputs":{},"steps":[{"values":{"schema":{"child_id":{"type":"number","nullable":false},"key":{"type":"number","nullable":true},"value":{"type":"number","nullable":true}},"rows":[{"child_id":2,"key":1,"value":null},{"child_id":1,"key":1,"value":10},{"child_id":3,"key":null,"value":30}]},"as":"out"}],"results":{"r":{"from":"out","fields":["child_id","key","value"]}}},{"id":"nested","inputs":{"parents":{"result":{"stage":"parents","result":"r"}},"children":{"result":{"stage":"children","result":"r"}}},"steps":[{"from":"parents","nest":{"with":"children","on":[{"left":"key","right":"key"}],"into":"items","fields":[{"amount":"value"}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","key","items"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"nested","result":"r"}}},"steps":[{"select":["id","key","items"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","key","items"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"nested","result":"r"}}},"steps":[{"select":["items","id","key"],"as":"out"}],"results":{"r":{"from":"out","fields":["items","id","key"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
fn local_json_pick_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"compute_a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"inner":{"type":"object","nullable":false,"fields":{"leaf":{"type":"number","nullable":false}}}}}},"rows":[{"id":1,"payload":{"inner":{"leaf":3}}},{"id":2,"payload":null}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","payload"]}}},{"id":"compute_b","inputs":{"x":{"result":{"stage":"compute_a","result":"r"}}},"steps":[{"json_pick":{"column":"payload","path":["inner","leaf"],"output":"picked"},"as":"out"}],"results":{"r":{"from":"out","fields":["id","payload","picked"]}}},{"id":"compute_c","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["id","payload","picked"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","payload","picked"]}}},{"id":"compute_d","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["id","payload","picked"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","payload","picked"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
fn local_ordered_set_program(kind : String) -> String {
  let operation = match kind {
    "sort" => "{\"sort\":[{\"id\":\"asc\"}],\"as\":\"out\"}"
    "sort_compound" =>
      "{\"sort\":[{\"field\":\"amount\",\"dir\":\"desc\",\"nulls\":\"first\"},{\"id\":\"asc\"}],\"as\":\"out\"}"
    "take" => "{\"take\":{\"count\":2,\"offset\":1},\"as\":\"out\"}"
    "take_parameter" =>
      "{\"take\":{\"count\":{\"$param\":\"minimum\"},\"offset\":1},\"as\":\"out\"}"
    "top_k" =>
      "{\"distinct\":[\"id\",\"amount\"],\"as\":\"unique\"},{\"from\":\"unique\",\"top_k\":{\"k\":2,\"by\":[{\"amount\":\"desc\"}]},\"as\":\"out\"}"
    "top_k_parameter" =>
      "{\"distinct\":[\"id\",\"amount\"],\"as\":\"unique\"},{\"from\":\"unique\",\"top_k\":{\"k\":{\"$param\":\"minimum\"},\"by\":[{\"amount\":\"desc\"}]},\"as\":\"out\"}"
    "top_k_compound" =>
      "{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"unique\"},{\"from\":\"unique\",\"top_k\":{\"k\":3,\"by\":[{\"field\":\"amount\",\"dir\":\"desc\",\"nulls\":\"first\"},{\"id\":\"asc\"}]},\"as\":\"out\"}"
    "top_k_by" =>
      "{\"distinct\":[\"id\",\"amount\"],\"as\":\"unique\"},{\"from\":\"unique\",\"top_k_by\":{\"partition_by\":[\"id\",\"id\"],\"k\":1,\"by\":[{\"amount\":\"desc\"}]},\"as\":\"out\"}"
    "top_k_by_parameter" =>
      "{\"distinct\":[\"id\",\"amount\"],\"as\":\"unique\"},{\"from\":\"unique\",\"top_k_by\":{\"partition_by\":[\"id\",\"id\"],\"k\":{\"$param\":\"minimum\"},\"by\":[{\"amount\":\"desc\"}]},\"as\":\"out\"}"
    "top_k_by_nullable" =>
      "{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"unique\"},{\"from\":\"unique\",\"top_k_by\":{\"partition_by\":[\"group\",\"group\"],\"k\":1,\"by\":[{\"amount\":\"desc\"}]},\"as\":\"out\"}"
    "distinct" => "{\"distinct\":true,\"as\":\"out\"}"
    "distinct_keyed_nullable" =>
      "{\"distinct\":[\"amount\",\"id\"],\"as\":\"out\"}"
    "dedupe_rows" =>
      "{\"dedupe_rows\":{\"by\":[\"id\"],\"order_by\":[{\"amount\":\"desc\"}]},\"as\":\"out\"}"
    "dedupe_compound_nullable" =>
      "{\"dedupe_rows\":{\"by\":[\"group\",\"bucket\"],\"order_by\":[{\"amount\":\"desc\"}]},\"as\":\"out\"}"
    "dedupe_tie_failure" =>
      "{\"dedupe_rows\":{\"by\":[\"id\"],\"order_by\":[{\"amount\":\"desc\"}]},\"as\":\"out\"}"
    _ => abort("unknown Local ordered/set fixture")
  }
  let prefix =
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"compute_a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":2,"amount":20},{"id":1,"amount":10},{"id":2,"amount":20},{"id":2,"amount":30}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","amount"]}}},{"id":"compute_b","inputs":{"x":{"result":{"stage":"compute_a","result":"r"}}},"steps":[
  let prefix = if kind == "sort_compound" {
    prefix
    .replace(
      old="\"amount\":{\"type\":\"number\",\"nullable\":false}",
      new="\"amount\":{\"type\":\"number\",\"nullable\":true}",
    )
    .replace(
      old="{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":10},{\"id\":2,\"amount\":20},{\"id\":2,\"amount\":30}",
      new="{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":null},{\"id\":1,\"amount\":30},{\"id\":2,\"amount\":null}",
    )
  } else if kind == "top_k_compound" {
    prefix
    .replace(
      old="\"amount\":{\"type\":\"number\",\"nullable\":false}",
      new="\"amount\":{\"type\":\"number\",\"nullable\":true}",
    )
    .replace(
      old="{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":10},{\"id\":2,\"amount\":20},{\"id\":2,\"amount\":30}",
      new="{\"id\":4,\"amount\":20},{\"id\":1,\"amount\":null},{\"id\":3,\"amount\":30},{\"id\":2,\"amount\":null}",
    )
  } else if kind == "top_k_by_nullable" {
    prefix
    .replace(
      old="\"amount\":{\"type\":\"number\",\"nullable\":false}",
      new="\"amount\":{\"type\":\"number\",\"nullable\":false},\"group\":{\"type\":\"string\",\"nullable\":true}",
    )
    .replace(
      old="{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":10},{\"id\":2,\"amount\":20},{\"id\":2,\"amount\":30}",
      new="{\"id\":1,\"amount\":20,\"group\":null},{\"id\":2,\"amount\":10,\"group\":\"a\"},{\"id\":3,\"amount\":30,\"group\":null},{\"id\":4,\"amount\":40,\"group\":\"a\"}",
    )
  } else if kind == "distinct_keyed_nullable" {
    prefix
    .replace(
      old="\"amount\":{\"type\":\"number\",\"nullable\":false}",
      new="\"amount\":{\"type\":\"number\",\"nullable\":true}",
    )
    .replace(
      old="{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":10},{\"id\":2,\"amount\":20},{\"id\":2,\"amount\":30}",
      new="{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":null}",
    )
  } else if kind == "dedupe_compound_nullable" {
    prefix
    .replace(
      old="\"amount\":{\"type\":\"number\",\"nullable\":false}",
      new="\"amount\":{\"type\":\"number\",\"nullable\":false},\"group\":{\"type\":\"string\",\"nullable\":true},\"bucket\":{\"type\":\"number\",\"nullable\":false}",
    )
    .replace(
      old="{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":10},{\"id\":2,\"amount\":20},{\"id\":2,\"amount\":30}",
      new="{\"id\":1,\"amount\":10,\"group\":null,\"bucket\":1},{\"id\":2,\"amount\":30,\"group\":null,\"bucket\":1},{\"id\":3,\"amount\":20,\"group\":\"a\",\"bucket\":2},{\"id\":4,\"amount\":40,\"group\":\"a\",\"bucket\":2}",
    )
  } else if kind == "dedupe_tie_failure" {
    prefix.replace(
      old="{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":10},{\"id\":2,\"amount\":20},{\"id\":2,\"amount\":30}",
      new="{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":10},{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":5}",
    )
  } else {
    prefix
  }
  let consumer =
    #|,"as":"out"}],"results":{"r":{"from":"out","fields":["id","amount"]}}}
  let text = prefix +
    operation +
    "],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"amount\"]}}},{\"id\":\"compute_c\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_b\",\"result\":\"r\"}}},\"steps\":[{\"select\":[\"id\",\"amount\"]" +
    consumer +
    ",{\"id\":\"compute_d\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_b\",\"result\":\"r\"}}},\"steps\":[{\"select\":[\"id\",\"amount\"]" +
    consumer +
    "],\"results\":{\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
  if kind == "top_k_by_nullable" {
    text.replace_all(
      old="[\"id\",\"amount\"]",
      new="[\"id\",\"amount\",\"group\"]",
    )
  } else if kind == "dedupe_compound_nullable" {
    text.replace_all(
      old="[\"id\",\"amount\"]",
      new="[\"id\",\"amount\",\"group\",\"bucket\"]",
    )
  } else {
    text
  }
}

///|
fn local_unnest_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"compute_a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"items":{"type":"array","nullable":true,"items":{"type":"number","nullable":true},"max_items":2}},"rows":[{"id":1,"items":[2,null]},{"id":2,"items":[]},{"id":3,"items":null}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","items"]}}},{"id":"compute_b","inputs":{"x":{"result":{"stage":"compute_a","result":"r"}}},"steps":[{"unnest":{"column":"items","as":"item","with_index":"position","outer":true},"as":"out"}],"results":{"r":{"from":"out","fields":["id","item","items","position"]}}},{"id":"compute_c","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["id","item","items","position"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","item","items","position"]}}},{"id":"compute_d","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["id","item","items","position"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","item","items","position"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
fn local_inner_unnest_program() -> String {
  local_unnest_program()
  .replace(old=",\"with_index\":\"position\",\"outer\":true", new="")
  .replace_all(
    old="[\"id\",\"item\",\"items\",\"position\"]",
    new="[\"id\",\"item\",\"items\"]",
  )
}

///|
fn local_unpivot_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"compute_a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"jan":{"type":"number","nullable":true},"feb":{"type":"number","nullable":true}},"rows":[{"id":1,"jan":10,"feb":null},{"id":2,"jan":null,"feb":20}]} ,"as":"out"}],"results":{"r":{"from":"out","fields":["id","jan","feb"]}}},{"id":"compute_b","inputs":{"x":{"result":{"stage":"compute_a","result":"r"}}},"steps":[{"unpivot":{"columns":["jan","feb","jan"],"keep":["id","jan"],"name_column":"metric","value_column":"amount"},"as":"out"}],"results":{"r":{"from":"out","fields":["amount","id","jan","metric"]}}},{"id":"compute_c","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["amount","id","jan","metric"],"as":"out"}],"results":{"r":{"from":"out","fields":["amount","id","jan","metric"]}}},{"id":"compute_d","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["amount","id","jan","metric"],"as":"out"}],"results":{"r":{"from":"out","fields":["amount","id","jan","metric"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
fn local_empty_unpivot_program() -> String {
  local_unpivot_program().replace(
    old="\"rows\":[{\"id\":1,\"jan\":10,\"feb\":null},{\"id\":2,\"jan\":null,\"feb\":20}]",
    new="\"rows\":[]",
  )
}

///|
fn local_pivot_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"compute_a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"status":{"type":"string","nullable":true},"amount":{"type":"number","nullable":true}},"rows":[{"id":2,"status":"open","amount":20},{"id":1,"status":"won","amount":10},{"id":2,"status":"open","amount":30},{"id":1,"status":"open","amount":null},{"id":1,"status":"other","amount":99},{"id":1,"status":null,"amount":5}]} ,"as":"out"}],"results":{"r":{"from":"out","fields":["amount","id","status"]}}},{"id":"compute_b","inputs":{"x":{"result":{"stage":"compute_a","result":"r"}}},"steps":[{"pivot":{"index":["id","id"],"column":"status","values":["won","open"],"value":"amount","aggregate":"count"},"as":"out"}],"results":{"r":{"from":"out","fields":["id","open","won"]}}},{"id":"compute_c","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["id","open","won"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","open","won"]}}},{"id":"compute_d","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["id","open","won"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","open","won"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
fn local_numeric_pivot_program() -> String {
  local_pivot_program().replace(
    old="\"aggregate\":\"count\"",
    new="\"aggregate\":\"sum\"",
  )
}

///|
fn local_pivot_min_fill_program() -> String {
  local_pivot_program().replace(
    old="\"aggregate\":\"count\"",
    new="\"aggregate\":\"min\",\"fill\":0",
  )
}

///|
fn local_pivot_parameter_fill_program() -> String {
  local_pivot_program().replace(
    old="\"aggregate\":\"count\"",
    new="\"aggregate\":\"min\",\"fill\":{\"$param\":\"minimum\"}",
  )
}

///|
fn local_pivot_max_program() -> String {
  local_pivot_program().replace(
    old="\"aggregate\":\"count\"",
    new="\"aggregate\":\"max\"",
  )
}

///|
fn local_pivot_first_program() -> String {
  local_pivot_program().replace(
    old="\"aggregate\":\"count\"",
    new="\"aggregate\":\"first\"",
  )
}

///|
fn local_empty_axis_pivot_program() -> String {
  local_pivot_program()
  .replace(old="\"values\":[\"won\",\"open\"]", new="\"values\":[]")
  .replace_all(old="[\"id\",\"open\",\"won\"]", new="[\"id\"]")
}

///|
fn local_decimal_pivot_sum_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"compute_a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"status":{"type":"string","nullable":true},"amount":{"type":"decimal","precision":4,"scale":2,"nullable":true}},"rows":[{"id":1,"status":"open","amount":"1.23"},{"id":1,"status":"open","amount":"-0.23"},{"id":1,"status":"won","amount":null},{"id":2,"status":"open","amount":"2.00"},{"id":2,"status":"won","amount":"3.00"}]} ,"as":"out"}],"results":{"r":{"from":"out","fields":["amount","id","status"]}}},{"id":"compute_b","inputs":{"x":{"result":{"stage":"compute_a","result":"r"}}},"steps":[{"pivot":{"index":["id"],"column":"status","values":["won","open"],"value":"amount","aggregate":"sum"},"as":"out"}],"results":{"r":{"from":"out","fields":["id","open","won"]}}},{"id":"compute_c","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["id","open","won"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","open","won"]}}},{"id":"compute_d","inputs":{"x":{"result":{"stage":"compute_b","result":"r"}}},"steps":[{"select":["id","open","won"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","open","won"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
fn local_values_unary_program(kind : String) -> String {
  if kind == "unnest" {
    return local_unnest_program()
  }
  if kind == "unnest_inner" {
    return local_inner_unnest_program()
  }
  if kind == "unpivot" {
    return local_unpivot_program()
  }
  if kind == "unpivot_empty" {
    return local_empty_unpivot_program()
  }
  if kind == "pivot" {
    return local_pivot_program()
  }
  if kind == "pivot_numeric" {
    return local_numeric_pivot_program()
  }
  if kind == "pivot_min_fill" {
    return local_pivot_min_fill_program()
  }
  if kind == "pivot_parameter_fill" {
    return local_pivot_parameter_fill_program()
  }
  if kind == "pivot_max" {
    return local_pivot_max_program()
  }
  if kind == "pivot_first" {
    return local_pivot_first_program()
  }
  if kind == "pivot_empty_axis" {
    return local_empty_axis_pivot_program()
  }
  if kind == "pivot_decimal_sum" {
    return local_decimal_pivot_sum_program()
  }
  if kind == "json_pick" {
    return local_json_pick_program()
  }
  if kind == "sort" ||
    kind == "sort_compound" ||
    kind == "take" ||
    kind == "take_parameter" ||
    kind == "top_k" ||
    kind == "top_k_parameter" ||
    kind == "top_k_compound" ||
    kind == "top_k_by" ||
    kind == "top_k_by_parameter" ||
    kind == "top_k_by_nullable" ||
    kind == "distinct" ||
    kind == "distinct_keyed_nullable" ||
    kind == "dedupe_rows" ||
    kind == "dedupe_compound_nullable" ||
    kind == "dedupe_tie_failure" {
    return local_ordered_set_program(kind)
  }
  let operation = match kind {
    "select" => "{\"select\":[{\"total\":\"amount\"},\"id\"],\"as\":\"out\"}"
    "filter_text" => "{\"filter\":\"id > $minimum\",\"as\":\"out\"}"
    "filter_structured" =>
      "{\"filter\":{\"gt\":[{\"field\":\"id\"},{\"$param\":\"minimum\"}]},\"as\":\"out\"}"
    "filter_null" => "{\"filter\":\"amount > 0\",\"as\":\"out\"}"
    "filter_failure" => "{\"filter\":\"false AND 1 / 0 > 0\",\"as\":\"out\"}"
    "derive_map" => "{\"derive\":{\"next\":\"id + $minimum\"},\"as\":\"out\"}"
    "derive_empty" => "{\"derive\":{},\"as\":\"out\"}"
    "derive_failure" => "{\"derive\":{\"unused\":\"1 / 0\"},\"as\":\"out\"}"
    "derive_ordered" =>
      "{\"derive\":[{\"saved\":\"id\"},{\"id\":\"id + $minimum\"},{\"next\":\"saved + id\"}],\"as\":\"out\"}"
    "rename" => "{\"rename\":{\"amount\":\"total\"},\"as\":\"out\"}"
    "rename_swap" =>
      "{\"rename\":{\"id\":\"amount\",\"amount\":\"id\"},\"as\":\"out\"}"
    "rename_empty" => "{\"rename\":{},\"as\":\"out\"}"
    "drop" => "{\"drop\":[\"amount\"],\"as\":\"out\"}"
    "drop_empty" => "{\"drop\":[],\"as\":\"out\"}"
    "drop_repeated" => "{\"drop\":[\"amount\",\"amount\"],\"as\":\"out\"}"
    "assert_where" => "{\"assert_rows\":{\"where\":\"id > 0\"},\"as\":\"out\"}"
    "assert_where_failure" =>
      "{\"assert_rows\":{\"where\":\"id > 1\"},\"as\":\"out\"}"
    "assert_where_eval_failure" =>
      "{\"assert_rows\":{\"where\":\"1 / 0 > 0\"},\"as\":\"out\"}"
    "assert_unique" =>
      "{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"out\"}"
    "assert_unique_null_failure" =>
      "{\"assert_rows\":{\"unique_by\":[\"amount\"]},\"as\":\"out\"}"
    _ => abort("unknown Local unary fixture")
  }
  let fields = match kind {
    "select" => "[\"total\",\"id\"]"
    "derive_map" => "[\"id\",\"amount\",\"next\"]"
    "derive_ordered" => "[\"id\",\"amount\",\"saved\",\"next\"]"
    "rename_swap" => "[\"amount\",\"id\"]"
    "rename" => "[\"id\",\"total\"]"
    "drop" | "drop_repeated" => "[\"id\"]"
    _ => "[\"id\",\"amount\"]"
  }
  let prefix =
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"compute_a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"amount":{"type":"number","nullable":true}},"rows":[{"id":1,"amount":10},{"id":2,"amount":null}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","amount"]}}},{"id":"compute_b","inputs":{"x":{"result":{"stage":"compute_a","result":"r"}}},"steps":[
  let consumer =
    #|,"as":"out"}],"results":{"r":{"from":"out","fields":
  prefix +
  operation +
  "],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  fields +
  "}}},{\"id\":\"compute_c\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_b\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
  fields +
  consumer +
  fields +
  "}}},{\"id\":\"compute_d\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_b\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
  fields +
  consumer +
  fields +
  "}}}],\"results\":{\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn local_values_cross_external_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"left_values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id"]}}},{"id":"right_values","inputs":{},"steps":[{"values":{"schema":{"tag":{"type":"string","nullable":false}},"rows":[{"tag":"a"},{"tag":"b"},{"tag":"c"}]},"as":"out"}],"results":{"r":{"from":"out","fields":["tag"]}}},{"id":"crossed","inputs":{"l":{"result":{"stage":"left_values","result":"r"}},"r":{"result":{"stage":"right_values","result":"r"}}},"steps":[{"from":"l","cross_join":{"with":"r","max_output_rows":6,"select":{"id":"left.id","tag":"right.tag"}},"as":"out"}],"results":{"r":{"from":"out","fields":["id","tag"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"crossed","result":"r"}}},"steps":[{"select":["id","tag"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","tag"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"crossed","result":"r"}}},"steps":[{"select":["tag","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["tag","id"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
fn local_select_qualified_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"left_values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"l":{"type":"string","nullable":false}},"rows":[{"id":1,"l":"l1"},{"id":2,"l":"l2"}]} ,"as":"out"}],"results":{"r":{"from":"out","fields":["id","l"]}}},{"id":"right_values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"r":{"type":"string","nullable":false}},"rows":[{"id":1,"r":"r1"},{"id":3,"r":"r3"},{"id":4,"r":"r4"}]} ,"as":"out"}],"results":{"r":{"from":"out","fields":["id","r"]}}},{"id":"selected","inputs":{"l":{"result":{"stage":"left_values","result":"r"}},"r":{"result":{"stage":"right_values","result":"r"}}},"steps":[{"from":"l","join":{"with":"r","kind":"inner","on":[{"left":"id","right":"id"}]},"as":"joined"},{"from":"joined","select":[{"right_value":"right.r"},{"left_value":"left.l"},{"id":"left.id"}],"as":"out"}],"results":{"r":{"from":"out","fields":["right_value","left_value","id"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"selected","result":"r"}}},"steps":[{"select":["id","left_value","right_value"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","left_value","right_value"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"selected","result":"r"}}},"steps":[{"select":["right_value","id","left_value"],"as":"out"}],"results":{"r":{"from":"out","fields":["right_value","id","left_value"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
fn local_values_group_program(variant : String) -> String {
  let (schema, rows, by, aggregates, input_fields, fields, reversed) = match
    variant {
    "keyed" =>
      (
        "{\"id\":{\"type\":\"number\",\"nullable\":true}}", "[{\"id\":null},{\"id\":1},{\"id\":1}]",
        "[\"id\"]", "{\"n\":{\"fn\":\"count\"}}", "[\"id\"]", "[\"id\",\"n\"]", "[\"n\",\"id\"]",
      )
    "compound" =>
      (
        "{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"string\",\"nullable\":true}}",
        "[{\"a\":1,\"b\":\"b\"},{\"a\":null,\"b\":\"a\"},{\"a\":1,\"b\":\"a\"},{\"a\":null,\"b\":\"a\"}]",
        "[\"a\",\"b\"]", "{\"n\":{\"fn\":\"count\"}}", "[\"a\",\"b\"]", "[\"a\",\"b\",\"n\"]",
        "[\"n\",\"b\",\"a\"]",
      )
    "empty_keyed" =>
      (
        "{\"id\":{\"type\":\"number\",\"nullable\":false}}", "[]", "[\"id\"]", "{\"n\":{\"fn\":\"count\"}}",
        "[\"id\"]", "[\"id\",\"n\"]", "[\"n\",\"id\"]",
      )
    "empty_global" =>
      (
        "{\"id\":{\"type\":\"number\",\"nullable\":false}}", "[]", "[]", "{\"n\":{\"fn\":\"count\"}}",
        "[\"id\"]", "[\"n\"]", "[\"n\"]",
      )
    "counts" =>
      (
        "{\"id\":{\"type\":\"number\",\"nullable\":true}}", "[{\"id\":null},{\"id\":1},{\"id\":1}]",
        "[\"id\"]", "{\"n\":{\"fn\":\"count\"},\"present\":{\"fn\":\"count\",\"field\":\"id\"}}",
        "[\"id\"]", "[\"id\",\"n\",\"present\"]", "[\"present\",\"n\",\"id\"]",
      )
    "direct" =>
      (
        "{\"k\":{\"type\":\"number\",\"nullable\":true},\"flag\":{\"type\":\"boolean\",\"nullable\":true},\"amount\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true},\"label\":{\"type\":\"string\",\"nullable\":true}}",
        "[{\"k\":2,\"flag\":true,\"amount\":\"1.25\",\"label\":\"b\"},{\"k\":null,\"flag\":true,\"amount\":\"-0.25\",\"label\":\"a\"},{\"k\":1,\"flag\":null,\"amount\":null,\"label\":null},{\"k\":2,\"flag\":false,\"amount\":\"2.00\",\"label\":\"a\"},{\"k\":null,\"flag\":false,\"amount\":\"0.50\",\"label\":\"c\"}]",
        "[\"k\"]", "{\"distinct_labels\":{\"fn\":\"count\",\"field\":\"label\",\"distinct\":true},\"hits\":{\"fn\":\"count_if\",\"field\":\"flag\"},\"highest\":{\"fn\":\"max\",\"field\":\"label\"},\"lowest\":{\"fn\":\"min\",\"field\":\"label\"},\"total\":{\"fn\":\"sum\",\"field\":\"amount\"}}",
        "[\"amount\",\"flag\",\"k\",\"label\"]", "[\"distinct_labels\",\"highest\",\"hits\",\"k\",\"lowest\",\"total\"]",
        "[\"total\",\"lowest\",\"k\",\"hits\",\"highest\",\"distinct_labels\"]",
      )
    "ordered" =>
      (
        "{\"k\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}",
        "[{\"k\":1,\"id\":1,\"label\":null},{\"k\":1,\"id\":2,\"label\":\"low\"},{\"k\":1,\"id\":3,\"label\":\"high\"},{\"k\":2,\"id\":1,\"label\":null}]",
        "[\"k\"]", "{\"first_asc\":{\"fn\":\"first\",\"field\":\"label\",\"order_by\":[{\"id\":\"asc\"}]},\"first_desc\":{\"fn\":\"first\",\"field\":\"label\",\"order_by\":[{\"id\":\"desc\"}]},\"last_asc\":{\"fn\":\"last\",\"field\":\"label\",\"order_by\":[{\"id\":\"asc\"}]},\"last_desc\":{\"fn\":\"last\",\"field\":\"label\",\"order_by\":[{\"id\":\"desc\"}]}}",
        "[\"id\",\"k\",\"label\"]", "[\"first_asc\",\"first_desc\",\"k\",\"last_asc\",\"last_desc\"]",
        "[\"last_desc\",\"last_asc\",\"k\",\"first_desc\",\"first_asc\"]",
      )
    "collections" =>
      (
        "{\"k\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}",
        "[{\"k\":1,\"id\":1,\"label\":\"a\"},{\"k\":1,\"id\":2,\"label\":null},{\"k\":1,\"id\":3,\"label\":\"b\"}]",
        "[\"k\"]", "{\"items\":{\"fn\":\"array_agg\",\"field\":\"label\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":5},\"n\":{\"fn\":\"count\"},\"text\":{\"fn\":\"string_agg\",\"field\":\"label\",\"delimiter\":\"|\",\"order_by\":[{\"id\":\"desc\"}],\"max_bytes\":17}}",
        "[\"id\",\"k\",\"label\"]", "[\"items\",\"k\",\"n\",\"text\"]", "[\"text\",\"n\",\"k\",\"items\"]",
      )
    "nested_distinct" =>
      (
        "{\"v\":{\"type\":\"array\",\"nullable\":true,\"max_items\":1,\"items\":{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":{\"type\":\"number\",\"nullable\":false}}}}}}}}",
        "[{\"v\":[[[[[[1]]]]]]},{\"v\":[[[[[[1]]]]]]},{\"v\":[[[[[[2]]]]]]},{\"v\":null}]",
        "[]", "{\"n\":{\"fn\":\"count\",\"field\":\"v\",\"distinct\":true}}", "[\"v\"]",
        "[\"n\"]", "[\"n\"]",
      )
    "filtered_expression" =>
      (
        "{\"id\":{\"type\":\"number\",\"nullable\":false},\"k\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"id\":0,\"k\":1},{\"id\":1,\"k\":1},{\"id\":2,\"k\":1},{\"id\":2,\"k\":1}]",
        "[\"k\"]", "{\"lowest\":{\"fn\":\"min\",\"expr\":\"10 / id\",\"filter\":\"id > 0\"}}",
        "[\"id\",\"k\"]", "[\"k\",\"lowest\"]", "[\"lowest\",\"k\"]",
      )
    "statistics" =>
      (
        "{\"n\":{\"type\":\"number\",\"nullable\":true}}",
        "[{\"n\":1},{\"n\":2},{\"n\":3},{\"n\":null}]",
        "[]",
        "{\"continuous\":{\"fn\":\"percentile_cont\"," +
        "\"field\":\"n\",\"fraction\":0.5}," +
        "\"discrete\":{\"fn\":\"percentile_disc\"," +
        "\"field\":\"n\",\"fraction\":0.5}," +
        "\"population\":{\"fn\":\"var_pop\",\"field\":\"n\"}," +
        "\"population_deviation\":{\"fn\":\"stddev_pop\"," +
        "\"field\":\"n\"},\"sample\":{\"fn\":\"var_samp\"," +
        "\"field\":\"n\"},\"sample_deviation\":{" +
        "\"fn\":\"stddev_samp\",\"field\":\"n\"}}",
        "[\"n\"]",
        "[\"continuous\",\"discrete\",\"population\"," +
        "\"population_deviation\",\"sample\",\"sample_deviation\"]",
        "[\"sample_deviation\",\"sample\",\"population_deviation\"," +
        "\"population\",\"discrete\",\"continuous\"]",
      )
    "numeric" | "numeric_filter" | "numeric_regroup" =>
      (
        "{\"k\":{\"type\":\"number\",\"nullable\":true},\"n\":{\"type\":\"number\",\"nullable\":true}}",
        "[{\"k\":1,\"n\":10000000000000000},{\"k\":1,\"n\":1},{\"k\":1,\"n\":-10000000000000000},{\"k\":null,\"n\":null}]",
        "[\"k\"]",
        "{\"mean\":{\"fn\":\"avg\",\"field\":\"n\"},\"total\":{\"fn\":\"sum\",\"field\":\"n\"}}",
        "[\"k\",\"n\"]",
        if variant == "numeric_regroup" {
          "[\"mean\",\"total\"]"
        } else {
          "[\"k\",\"mean\",\"total\"]"
        },
        if variant == "numeric_regroup" {
          "[\"total\",\"mean\"]"
        } else {
          "[\"total\",\"mean\",\"k\"]"
        },
      )
    _ => abort("unknown Local group fixture")
  }
  let remote =
    #|{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}}
  let consumer = fn(id : String, selected : String) {
    "{\"id\":\"" +
    id +
    "\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_b\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
    selected +
    ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
    selected +
    "}}}"
  }
  let group_alias = if variant == "numeric_filter" ||
    variant == "numeric_regroup" {
    "grouped"
  } else {
    "out"
  }
  let group_open = if variant == "collections" {
    "{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"unique\"},{\"from\":\"unique\",\"group\":{\"by\":"
  } else {
    "{\"group\":{\"by\":"
  }
  let group_tail = match variant {
    "numeric_filter" =>
      ",{\"from\":\"grouped\",\"filter\":\"total >= 0\",\"as\":\"out\"}"
    "numeric_regroup" =>
      ",{\"from\":\"grouped\",\"group\":{\"by\":[],\"aggregates\":{" +
      "\"mean\":{\"fn\":\"avg\",\"field\":\"mean\"}," +
      "\"total\":{\"fn\":\"sum\",\"field\":\"total\"}}},\"as\":\"out\"}"
    _ => ""
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{\"minimum\":{\"type\":\"number\",\"nullable\":false}},\"stages\":[" +
  remote +
  "," +
  "{\"id\":\"compute_a\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":" +
  schema +
  ",\"rows\":" +
  rows +
  "},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  input_fields +
  "}}}," +
  "{\"id\":\"compute_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_a\",\"result\":\"r\"}}},\"steps\":[" +
  group_open +
  by +
  ",\"aggregates\":" +
  aggregates +
  "},\"as\":\"" +
  group_alias +
  "\"}" +
  group_tail +
  "],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  fields +
  "}}}," +
  consumer("compute_c", fields) +
  "," +
  consumer("compute_d", reversed) +
  "],\"results\":{\"c\":{\"from\":{\"stage\":\"compute_c\",\"result\":\"r\"}}}}"
}

///|
fn local_values_append_program(variant : String) -> String {
  let remote =
    #|{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}}
  let consumer = fn(id : String, producer : String, fields : String) {
    "{\"id\":\"" +
    id +
    "\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"" +
    producer +
    "\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
    fields +
    ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
    fields +
    "}}}"
  }
  let prefix = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{\"minimum\":{\"type\":\"number\",\"nullable\":false}},\"stages\":[" +
    remote +
    ","
  let suffix = "],\"results\":{\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
  if variant == "imported" {
    return prefix +
      "{\"id\":\"append_left\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}}," +
      "{\"id\":\"append_right\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2},{\"id\":3}]},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}}," +
      "{\"id\":\"appended\",\"inputs\":{\"l\":{\"result\":{\"stage\":\"append_left\",\"result\":\"r\"}},\"r\":{\"result\":{\"stage\":\"append_right\",\"result\":\"r\"}}},\"steps\":[{\"from\":\"l\",\"append\":{\"with\":\"r\"},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}}," +
      consumer("append_consumer_a", "appended", "[\"id\"]") +
      "," +
      consumer("append_consumer_b", "appended", "[\"id\"]") +
      suffix
  }
  if variant == "aligned" {
    return prefix +
      "{\"id\":\"appended\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"id\":1,\"tag\":{\"literal\":\"left\"}}]},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"tag\":{\"type\":\"string\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"tag\":{\"literal\":\"right\"},\"id\":2}]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"append\":{\"with\":\"right_rows\"},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"tag\"]}}}," +
      consumer("append_consumer_a", "appended", "[\"id\",\"tag\"]") +
      "," +
      consumer("append_consumer_b", "appended", "[\"id\",\"tag\"]") +
      suffix
  }
  let left = if variant == "empty_left" || variant == "empty_both" {
    "[]"
  } else {
    "[{\"id\":1}]"
  }
  let right = if variant == "empty_right" || variant == "empty_both" {
    "[]"
  } else {
    "[{\"id\":2}]"
  }
  let right_name = if variant == "self" { "left_rows" } else { "right_rows" }
  if variant != "local" &&
    variant != "self" &&
    variant != "empty_left" &&
    variant != "empty_right" &&
    variant != "empty_both" {
    abort("unknown Local append fixture")
  }
  prefix +
  "{\"id\":\"appended\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
  left +
  "},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
  right +
  "},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"append\":{\"with\":\"" +
  right_name +
  "\"},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}}," +
  consumer("append_consumer_a", "appended", "[\"id\"]") +
  "," +
  consumer("append_consumer_b", "appended", "[\"id\"]") +
  suffix
}

///|
fn checked_expression_profile_admission(
  checked : @program_check.CheckedProgram,
) -> @lower.ExpressionProfileAdmission {
  let profiles = @program_check.selected_expression_profiles(checked)
  { text_time: profiles.text_time, veca: profiles.veca, }
}

///|
test "query Program reaches the public main checked entry" {
  let checked = query_checked_program_fixture()
  assert_eq(@program_check.unit_count(checked), 1)
  assert_eq(@program_check.source_execution_count(checked), 5)
  for i in 0..<5 {
    let execution = @program_check.source_execution_at(checked, i).unwrap()
    assert_true(
      physical_equal(
        @program_check.source_execution_subject(execution).owner,
        @program_check.source_identity(checked),
      ),
    )
  }
}

///|
fn query_checked_sequence(
  checked : @program_check.CheckedProgram,
) -> @query.QuerySequence raise {
  let identity = @program_check.source_identity(checked)
  let requests = @context.program_identity_stage_requests(identity, 0).unwrap()
  let query = @acquisition.derive_query_acquisition(requests, 0, 1000000).unwrap()
  assert_true(
    physical_equal(
      @program_check.unit_pipeline(checked, 0).unwrap(),
      @acquisition.query_acquisition_pipeline(query),
    ),
  )
  let prepared = @lower.prepare(
    @acquisition.query_acquisition_pipeline(query),
    {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 10000,
    },
  ).unwrap()
  let values = @acquisition.request_parameter_values(
    @acquisition.pipeline_requests_parameters(requests),
  )
  let bound = @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=100,
    max_name_bytes=10000,
    expression_profiles=checked_expression_profile_admission(checked),
  ).unwrap()
  @query.prepare_query_sequence(query, query_generated(bound), 10000).unwrap()
}

///|
test "public CheckedProgram feeds both query strategies capture and checked consumer" {
  let checked = query_checked_program_fixture()
  let identity = @program_check.source_identity(checked)
  let sequence = query_checked_sequence(checked)
  let material = @planning.prepare_query_material(
    sequence,
    query_material_limits(),
  ).unwrap()
  let requirement = @planning.prepare_query_requirement(
    material,
    identity,
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let unit_cid = @program_check.unit_definition_cid(checked, 0).unwrap()
  let requirement_cid = @planning.query_requirement_cid(requirement)
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let issuer = @mock.prepare_mock_query_issuer(
    contracts, requirement, "checked-program-test", 100,
  ).unwrap()
  let owner = @query.query_sequence_owner(sequence)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    let attempt = query_issuer_attempt(issuer, sequence, route)
    query_issuer_run(attempt)
    let records = @mock.issue_mock_query_records(
      attempt,
      query_material_limits(),
    ).unwrap()
    let observation = @mock.capture_mock_query(
      issuer,
      attempt,
      records,
      query_capture_limits(),
    ).unwrap()
    let input = @mock.bind_captured_query_input(
      issuer, attempt, observation, receiver, 0, owner,
    ).unwrap()
    let consumer = @execution.prepare_local_compute_attempt(
      compute_test_sequence(receiver),
      [input],
      3,
    ).unwrap()
    let complete = @execution.execute_local_compute_attempt(
      consumer,
      compute_test_limits(),
    ).unwrap()
    let output = @execution.completed_output(complete, Step(0)).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
    assert_eq(@program_check.unit_definition_cid(checked, 0).unwrap(), unit_cid)
    assert_eq(@planning.query_requirement_cid(requirement), requirement_cid)
  }
  let foreign = query_checked_program_fixture()
  assert_eq(
    @context.program_identity_definition_cid(
      @program_check.source_identity(foreign),
    ),
    @context.program_identity_definition_cid(identity),
  )
  assert_true(
    @planning.prepare_query_requirement(
      material,
      @program_check.source_identity(foreign),
      { max_rows: 10, max_value_bytes: 100, },
      query_material_limits(),
    )
    is Err(ForeignProgram),
  )
}
