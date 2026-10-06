///|
/// Select the first incomplete task whose checked data and control predecessors
/// are complete. Completion is supplied by the execution owner, never inferred
/// from equal payload bytes. This projection grants no execution or input read.
pub fn next_dependency_ready_task(
  graph : CheckedDAG,
  completed : (Int) -> Bool,
  first_task? : Int = 0,
) -> Int? {
  if first_task < 0 || first_task >= graph.owners.length() {
    return None
  }
  for index in first_task..<graph.owners.length() {
    if completed(index) {
      continue
    }
    let mut ready = true
    for edge in graph.data {
      if edge.consumer == index && !completed(edge.producer) {
        ready = false
      }
    }
    for edge in graph.control {
      if edge.consumer == index && !completed(edge.predecessor) {
        ready = false
      }
    }
    if ready {
      return Some(index)
    }
  }
  None
}
