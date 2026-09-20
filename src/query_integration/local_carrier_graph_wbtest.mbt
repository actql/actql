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
fn local_carrier_graph_program(variant? : String = "projection") -> String {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"src\":{\"type\":\"number\",\"nullable\":false}," +
    "\"dst\":{\"type\":\"number\",\"nullable\":false}," +
    "\"node_name\":{\"type\":\"string\",\"nullable\":false}," +
    "\"weight\":{\"type\":\"number\",\"nullable\":false}}"
  let rows = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"first\",\"weight\":10},{\"id\":2," +
    "\"src\":2,\"dst\":1,\"node_name\":\"second\"," +
    "\"weight\":20}]"
  let projection = if variant == "match_nodes" {
    "\"from\":\"g\",\"match_nodes\":{\"ids\":[2,1,2]," +
    "\"fields\":[\"id\",\"node_name\"]},\"as\":\"out\""
  } else if variant == "match_nodes_literal" {
    "\"from\":\"g\",\"match_nodes\":{\"where\":\"true\"," +
    "\"fields\":[\"id\",\"node_name\"]},\"as\":\"out\""
  } else if variant == "match_edges" {
    "\"from\":\"g\",\"match_edges\":{\"fields\":[\"src\",\"dst\"," +
    "\"weight\"]},\"as\":\"out\""
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
  } else {
    "\"node_rows\":true,\"as\":\"out\""
  }
  let result_fields = if variant == "match_edges" {
    "\"src\",\"dst\",\"weight\""
  } else if variant == "graph_bounds" {
    "\"kind\",\"node_id\",\"actual\",\"max\""
  } else if variant.has_prefix("degree_") {
    "\"node\",\"degree\""
  } else if variant.has_prefix("components_") {
    "\"node_id\",\"component_id\",\"component_size\""
  } else {
    "\"id\",\"node_name\""
  }
  let first_fields = result_fields
  let second_fields = if variant == "match_edges" {
    "\"weight\",\"src\""
  } else if variant == "graph_bounds" {
    "\"kind\",\"node_id\""
  } else if variant.has_prefix("degree_") {
    "\"degree\""
  } else if variant.has_prefix("components_") {
    "\"component_id\",\"component_size\""
  } else {
    "\"node_name\""
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
  "\"src\",\"dst\",\"node_name\",\"weight\"]}}},{" +
  "\"id\":\"graph\"," +
  "\"inputs\":{\"rows\":{\"result\":{\"stage\":\"values\"," +
  "\"result\":\"r\"}}},\"steps\":[{\"graph\":{\"nodes\":{" +
  "\"from\":\"rows\",\"id\":\"id\",\"fields\":[\"node_name\"]}," +
  "\"edges\":{\"from\":\"rows\",\"source\":\"src\"," +
  "\"target\":\"dst\",\"fields\":[\"weight\"]}},\"as\":\"g\"},{" +
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
fn literal_match_nodes_output(
  source_owner : @lower.BoundPrepared,
  predicate : String,
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
    8,
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
  let selected = literal_match_nodes_output(source_owner, "true")
  assert_eq(@execution.completed_row_count(selected), 2)
  assert_true(@execution.completed_cell(selected, 0, 0) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(selected, 1, 1) is Some(Text("second")))

  let empty = literal_match_nodes_output(source_owner, "false")
  assert_eq(@execution.completed_row_count(empty), 0)
  assert_true(@execution.completed_output_available(empty))
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
  if variant == "graph_bounds" {
    "sha256:17d576d1679a19ebaa39babfe25c6922f65888c29781f7ea73b3f2af674b13c7"
  } else if variant == "match_edges" {
    "sha256:c60b5715592edabcbe32bd818f14c8d413b3717806662aa06c9e4eae57420932"
  } else if variant == "degree_both" {
    "sha256:3a537f671c5f32a7a9e97bb2e1a0edd04aeec3df32a5403bef7801958022deb0"
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
    @local_sga_provider.provider(
      carrier_graph_storage_limits(),
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
  let graph_live = Ref(true)
  let graph_obligations = graph_publication_obligations(run, publication)
  let (graph_ops, graph) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [values_rows],
    2,
    graph_live,
    obligations?=graph_obligations,
  )
  let graph_rows = local_managed_test_rows(graph_ops)
  let expected_rows = if variant == "graph_bounds" { 4 } else { 2 }
  assert_eq(graph_rows.length(), expected_rows)
  if variant == "match_edges" {
    assert_true(graph_rows[0].contains("\"src\":1"))
    assert_true(graph_rows[1].contains("\"weight\":20"))
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
    3,
    [graph],
    [graph_rows],
    3,
    first_live,
    obligations?=graph_publication_obligations(run, publication),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [graph],
    [graph_rows],
    4,
    second_live,
    obligations?=graph_publication_obligations(run, publication),
  )
  assert_eq(local_managed_test_rows(first_ops).length(), expected_rows)
  assert_eq(local_managed_test_rows(second_ops).length(), expected_rows)

  first_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(graph))

  second_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  graph_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (graph_ops.close)()
  assert_false((graph_ops.cleanup_refresh)())
  assert_true((graph_ops.cleanup_refresh)())
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

///|
test "standard Host runs bounded Graph relation paths with two consumers" {
  run_standard_host_graph_relation_path("projection")
  run_standard_host_graph_relation_path("match_nodes", publication=true)
  run_standard_host_graph_relation_path("match_nodes_literal")
  run_standard_host_graph_relation_path("match_edges", publication=true)
  run_standard_host_graph_relation_path("graph_bounds", publication=true)
  run_standard_host_graph_relation_path("degree_in")
  run_standard_host_graph_relation_path("degree_out")
  run_standard_host_graph_relation_path("degree_both", publication=true)
  run_standard_host_graph_relation_path("components_weak")
  run_standard_host_graph_relation_path("components_strong")
}
