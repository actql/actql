///|
/// Select the first incomplete task whose checked data and control predecessors
/// are complete. Completion is supplied by the execution owner, never inferred
/// from equal payload bytes. This projection grants no execution or input read.
pub fn next_dependency_ready_task(
  graph : CheckedDAG,
  completed : (Int) -> Bool,
  first_task? : Int = 0,
) -> Int? {
  if first_task < 0 || first_task >= graph.owners_count() {
    return None
  }
  for index in first_task..<graph.owners_count() {
    if !completed(index) && dependency_task_ready(graph, completed, index) {
      return Some(index)
    }
  }
  None
}

///|
// Shared by scheduling and pre-work control. The caller owns completion.
fn dependency_task_ready(
  graph : CheckedDAG,
  completed : (Int) -> Bool,
  task : Int,
) -> Bool {
  let mut ready = true
  for edge in graph.data_iter() {
    if edge.consumer == task && !completed(edge.producer) {
      ready = false
    }
  }
  for edge in graph.control_iter() {
    if edge.consumer == task && !completed(edge.predecessor) {
      ready = false
    }
  }
  ready
}
