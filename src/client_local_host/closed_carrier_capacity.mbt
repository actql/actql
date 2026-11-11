///|
// A bounded borrowed traversal of original checked targets. No Carrier value,
// schema, graph or permission is constructed. Input edges must resolve to the
// same original producer/target in every physical task view of this owner.
fn client_local_closed_item_bound(
  graph : @strategy.CheckedDAG,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  work : Ref[Int],
  depth : Int,
) -> Int? {
  if work.val < 1 || depth < 0 {
    return None
  }
  work.val -= 1
  let prepared = @lower.bound_preparation(owner)
  match target {
    @pipeline.Step(index) => {
      guard @lower.node_at(prepared, index) is Some(node) else { return None }
      let inputs : Array[Int] = []
      for port in 0..<@lower.node_input_count(node) {
        guard @lower.node_input_target(node, port) is Some(input) &&
          client_local_closed_item_bound(graph, owner, input, work, depth - 1)
          is Some(count) else {
          return None
        }
        inputs.push(count)
      }
      @lower.node_closed_item_count_bound(node, inputs)
    }
    @pipeline.Input(input) => {
      let mut producer : (@lower.BoundPrepared, @pipeline.Target)? = None
      for index in 0..<@strategy.graph_data_count(graph) {
        if work.val < 1 {
          return None
        }
        work.val -= 1
        guard @strategy.graph_data_at(graph, index) is Some(edge) else {
          return None
        }
        guard edge.source_input is Some(source) && source == input else {
          continue
        }
        guard @strategy.graph_task_owner(
            graph,
            @strategy.data_edge_consumer(edge),
          )
          is Some(consumer) &&
          physical_equal(consumer, owner) else {
          continue
        }
        guard @strategy.graph_task_owner(
            graph,
            @strategy.data_edge_producer(edge),
          )
          is Some(original) else {
          return None
        }
        let selected = @strategy.data_edge_target(edge)
        match producer {
          None => producer = Some((original, selected))
          Some((previous, previous_target)) =>
            if !physical_equal(previous, original) ||
              previous_target != selected {
              return None
            }
        }
      }
      guard producer is Some((original, selected)) else { return None }
      client_local_closed_item_bound(graph, original, selected, work, depth - 1)
    }
  }
}

///|
// This optional demand fact visits every original node, including intermediate
// Carrier constructors, rather than proving only selected Result endpoints.
// Unknown, expanding, open-input or exhausted paths retain the general profile.
fn client_local_closed_carrier_bound(
  sequences : Array[@execution.GeneratedSequence],
  graph : @strategy.CheckedDAG,
  work : Ref[Int],
) -> Int? {
  if sequences.length() != @strategy.graph_task_count(graph) {
    return None
  }
  let mut maximum = 0
  let mut carrier = false
  for task, sequence in sequences {
    let owner = @execution.generated_sequence_owner(sequence)
    guard @strategy.graph_task_owner(graph, task) is Some(original) &&
      physical_equal(owner, original) else {
      return None
    }
    let prepared = @lower.bound_preparation(owner)
    for index in 0..<@lower.node_count(prepared) {
      guard @lower.node_at(prepared, index) is Some(node) &&
        client_local_closed_item_bound(
          graph,
          owner,
          @pipeline.Step(index),
          work,
          client_local_value_node_proof_depth(),
        )
        is Some(count) else {
        return None
      }
      carrier = carrier || @lower.node_relation_schema(node) is None
      maximum = Int::max(maximum, count)
    }
  }
  if carrier {
    Some(maximum)
  } else {
    None
  }
}

///|
// At most one item slot can be allocated per spent proof-work unit, including
// arrays held by ancestor calls. Recursion uses the existing compilation depth.
// Price those actual temporary representations before entering Plan creation;
// no new resource limit, returned certificate or retained cache is introduced.
fn client_local_closed_carrier_proof_scratch_bytes() -> Int64? {
  let levels = client_local_value_node_proof_depth().to_int64() + 2L
  @execution.preparation_representation_cost({
    record_headers: 6L * levels + 2L,
    reference_slots: 12L * levels +
    2L * client_local_schema_proof_work().to_int64(),
    scalar_words: 12L * levels,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
