///|
priv enum RelationChainInputPhase {
  Port
  External
  Producer
  Read
}

///|
priv struct RelationChainInputPreparation {
  sequence : @execution.GeneratedSequence
  position : Int
  inputs : Array[ManagedProviderInput]
  completed : Array[@execution.CompletedOutput?]
  selected : Array[ManagedProviderInput]
  owner : @lower.BoundPrepared
  node : @lower.PreparedNode
  first_step : Int
  step : Int
  max_entries : Int
  max_value_bytes : Int
  mut port : Int
  mut probe : Int
  mut matched : ManagedProviderInput?
  mut read : @execution.ProducerReadPreparation?
  mut phase : RelationChainInputPhase
}

///|
fn start_relation_chain_inputs(
  sequence : @execution.GeneratedSequence,
  position : Int,
  inputs : Array[ManagedProviderInput],
  completed : Array[@execution.CompletedOutput?],
  max_entries : Int,
  max_value_bytes : Int,
) -> Result[RelationChainInputPreparation, @connector.FixedComputeIssue] {
  let owner = @execution.generated_sequence_owner(sequence)
  guard @execution.generated_sequence_step_index_at(sequence, 0)
    is Some(first_step) &&
    @execution.generated_sequence_step_index_at(sequence, position)
    is Some(step) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) else {
    return Err(@connector.Execution(@execution.InputSet))
  }
  Ok({
    sequence,
    position,
    inputs,
    completed,
    owner,
    node,
    first_step,
    step,
    max_entries,
    max_value_bytes,
    selected: [],
    port: 0,
    probe: 0,
    matched: None,
    read: None,
    phase: Port,
  })
}

///|
fn cancel_relation_chain_inputs(cursor : RelationChainInputPreparation) -> Unit {
  if cursor.read is Some(read) {
    @execution.cancel_prepare_producer_read(read)
  }
  cursor.read = None
  cursor.matched = None
  cursor.selected.clear()
}

///|
/// One checked port/probe or one common metadata cursor advance. Selection
/// never publishes a partial receiving-input array or grants start authority.
fn advance_relation_chain_inputs(
  cursor : RelationChainInputPreparation,
) -> Result[Array[ManagedProviderInput]?, @connector.FixedComputeIssue] {
  match cursor.phase {
    Port => {
      if cursor.port == @lower.node_input_count(cursor.node) {
        return Ok(Some(cursor.selected))
      }
      cursor.probe = 0
      cursor.matched = None
      cursor.phase = match @lower.node_input_target(cursor.node, cursor.port) {
        Some(@pipeline.Input(_)) => External
        Some(@pipeline.Step(producer)) =>
          if producer < cursor.first_step {
            External
          } else {
            Producer
          }
        None => return Err(@connector.Execution(@execution.InputSet))
      }
    }
    External =>
      if cursor.probe == cursor.inputs.length() {
        guard cursor.matched is Some(input) else {
          return Err(@connector.Execution(@execution.InputSet))
        }
        cursor.selected.push(input)
        cursor.matched = None
        cursor.port += 1
        cursor.phase = Port
      } else {
        let input = cursor.inputs[cursor.probe]
        cursor.probe += 1
        let exact = match input {
          RelationInput(read) =>
            @execution.producer_read_matches_operation_input(
              read,
              cursor.owner,
              cursor.step,
              cursor.port,
            )
          SuppliedRelationInput(read) =>
            @execution.supplied_relation_read_matches_operation_input(
              read,
              cursor.owner,
              cursor.step,
              cursor.port,
            )
          CarrierInput(_) => false
        }
        if exact {
          if cursor.matched is Some(_) {
            return Err(@connector.Execution(@execution.InputSet))
          }
          cursor.matched = Some(input)
        }
      }
    Producer => {
      if cursor.probe == cursor.position {
        return Err(@connector.Execution(@execution.InputSet))
      }
      let position = cursor.probe
      cursor.probe += 1
      guard @lower.node_input_target(cursor.node, cursor.port)
        is Some(@pipeline.Step(producer)) else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      if @execution.generated_sequence_step_index_at(cursor.sequence, position) ==
        Some(producer) {
        guard cursor.completed.get(position) is Some(Some(output)) else {
          return Err(@connector.Execution(@execution.InputSet))
        }
        let bound = match
          @execution.bind_completed_operation_input(
            cursor.owner,
            cursor.step,
            cursor.port,
            cursor.owner,
            output,
          ) {
          Ok(bound) => bound
          Err(_) => return Err(@connector.Execution(@execution.InputSet))
        }
        let read = match
          @execution.start_prepare_producer_read(
            cursor.owner,
            bound,
            cursor.max_entries,
            cursor.max_value_bytes,
          ) {
          Ok(read) => read
          Err(_) => return Err(@connector.Execution(@execution.InputSet))
        }
        cursor.read = Some(read)
        cursor.phase = Read
      }
    }
    Read => {
      guard cursor.read is Some(read) else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      match @execution.advance_prepare_producer_read(read) {
        Err(_) => return Err(@connector.Execution(@execution.InputSet))
        Ok(None) => ()
        Ok(Some(read)) => {
          cursor.selected.push(RelationInput(read))
          cursor.read = None
          cursor.port += 1
          cursor.phase = Port
        }
      }
    }
  }
  Ok(None)
}

///|
/// Preserve the existing fixed small lane only when every loop has a static
/// bound. No long-name measurement, projection copy or value read is involved.
fn relation_chain_inputs_are_small(
  cursor : RelationChainInputPreparation,
) -> Bool {
  if cursor.position > 8 ||
    cursor.inputs.length() > 8 ||
    @lower.node_input_count(cursor.node) > 2 {
    return false
  }
  for port in 0..<@lower.node_input_count(cursor.node) {
    match @lower.node_input_target(cursor.node, port) {
      Some(@pipeline.Input(_)) => ()
      Some(@pipeline.Step(producer)) => {
        if producer < cursor.first_step {
          continue
        }
        let mut found = false
        for index in 0..<cursor.position {
          if @execution.generated_sequence_step_index_at(cursor.sequence, index) ==
            Some(producer) {
            guard cursor.completed.get(index) is Some(Some(output)) else {
              return true
            }
            let bound = match
              @execution.bind_completed_operation_input(
                cursor.owner,
                cursor.step,
                port,
                cursor.owner,
                output,
              ) {
              Ok(bound) => bound
              Err(_) => return true
            }
            let read = match
              @execution.start_prepare_producer_read(
                cursor.owner,
                bound,
                cursor.max_entries,
                cursor.max_value_bytes,
              ) {
              Ok(read) => read
              Err(_) => return true
            }
            let small = @execution.producer_read_preparation_is_small(read)
            @execution.cancel_prepare_producer_read(read)
            if !small {
              return false
            }
            found = true
            break
          }
        }
        if !found {
          return true
        }
      }
      None => return true
    }
  }
  true
}
