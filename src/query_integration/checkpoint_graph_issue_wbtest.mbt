///|
fn checkpoint_graph_issue(
  result : Result[@strategy.CheckedDAG, @strategy.GraphIssue],
) -> @strategy.CheckedDAG raise {
  match result {
    Ok(graph) => graph
    Err(cause) =>
      fail("original checkpoint rejected: " + @debug.to_string(cause))
  }
}
