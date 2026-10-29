///|
pub fn[C, E] compute_host_resident_inputs(
  host : ComputeHost[C, E],
  task : Int,
) -> Array[(Int, Int64, Int, Int)]? {
  guard @strategy.captured_dag_strategy(host.driver.owner.run) is Some(revision) &&
    @strategy.strategy_resident_profile(revision, task) is Some(profile) else {
    return None
  }
  let graph = @strategy.captured_dag_graph(host.driver.owner.run)
  guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
    return None
  }
  let count = @pipeline.input_count(
    @lower.pipeline(@lower.bound_preparation(owner)),
  )
  let inputs = []
  for port in 0..<count {
    let mut found = false
    for i in 0..<@strategy.graph_data_count(graph) {
      let edge = @strategy.graph_data_at(graph, i).unwrap()
      if edge.consumer == task && edge.input == port {
        guard @strategy.resident_profile_import(profile, edge.producer)
          is Some(value) else {
          return None
        }
        inputs.push(
          (
            edge.producer,
            value.table_bytes,
            host.dispatch.max_entries,
            host.dispatch.max_name_bytes,
          ),
        )
        found = true
        break
      }
    }
    if !found {
      return None
    }
  }
  Some(inputs)
}
