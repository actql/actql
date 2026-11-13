///|
// Run-owned completion DATA. Never retain an input binding, read reference,
// output, callback or physical holding here. The same checked task commits once.
priv struct CapturedTaskCompletion {
  producer : Int?
  original : @execution.CompletedOutputOccurrence?
}

///|
// Called only after the real managed output and its exact admitted inputs
// passed completion validation. This describes the consumed checked edge;
// static graph reachability alone cannot create a successful completion.
fn prepare_captured_task_completion(
  graph : CheckedDAG,
  task : Int,
  original : @execution.CompletedOutputOccurrence?,
) -> CapturedTaskCompletion? {
  // Only Effect consumers need this historical correspondence. Pure task
  // construction keeps its original path and allocates no completion record.
  if !graph_program_has_effects(graph) {
    return None
  }
  let mut producer : Int? = None
  if graph_task_input_count(graph, task) == Some(1) {
    for edge in graph.data_iter() {
      if edge.consumer == task {
        if producer is Some(_) ||
          edge.input != 0 ||
          edge.producer < 0 ||
          edge.producer >= task {
          return Some({ producer: None, original, })
        }
        producer = Some(edge.producer)
      }
    }
  }
  Some({ producer, original, })
}

///|
fn captured_completed_edge_matches(
  run : CapturedDAG,
  consumer : Int,
  producer : Int,
) -> Bool {
  match run.lifetimes[consumer].completion {
    Some(completion) => completion.producer == Some(producer)
    // Preserve the old live materialized path, never infer a missing retired
    // completion from a checked graph or a done flag alone.
    None => run.lifetimes[consumer].live && run.outputs[consumer] is Some(_)
  }
}
