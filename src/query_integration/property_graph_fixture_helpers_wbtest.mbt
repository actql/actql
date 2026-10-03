///|
// Current keyed Graph fixtures only. Retired tuple fixtures are retained in Git.
fn local_carrier_graph_program(variant? : String = "current_filter") -> String {
  current_graph_relation_program(variant)
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
