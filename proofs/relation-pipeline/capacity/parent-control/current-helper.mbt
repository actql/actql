///|
#borrow(parent, state, children, completed, preparation, read)
extern "C" fn current_chain_phase_probe(
  parent : ManagedProviderExecution,
  state : RelationChainExecutionState,
  children : Array[ManagedProviderExecution],
  completed : Array[@execution.CompletedOutput?],
  preparation : RelationChainInputPreparation?,
  read : @execution.ProducerReadPreparation?,
  position : Int,
  pending : Bool,
  reclaiming : Bool,
  phase : Int,
) -> String = "actql_proof_current_chain_phase"

///|
#borrow(parent, state, used, cancelled, terminal, reclaimed, cleanup_index, sequence, inputs, execution, measurement, numeric, family)
extern "C" fn current_chain_start_probe(
  parent : ManagedProviderExecution,
  state : RelationChainExecutionState,
  used : Ref[Int64],
  cancelled : Ref[Bool],
  terminal : Ref[Bool],
  reclaimed : Ref[Bool],
  cleanup_index : Ref[Int],
  sequence : @execution.GeneratedSequence,
  inputs : Array[ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  numeric : @execution.NumericAggregateExecution?,
  family : Array[ManagedProvider],
  count : Int,
  max_value_bytes : Int,
  reclaims_scratch : Bool,
) -> String = "actql_proof_current_chain_start"

///|
#warnings("-unused_value")
fn current_chain_observe(
  parent : ManagedProviderExecution,
  state : RelationChainExecutionState,
  phase : Int,
) -> Unit {
  let read = match state.input_preparation {
    Some(cursor) => cursor.read
    None => None
  }
  println(
    current_chain_phase_probe(
      parent,
      state,
      state.children,
      state.completed,
      state.input_preparation,
      read,
      state.position,
      state.pending,
      state.reclaiming,
      phase,
    ),
  )
}

///|
#borrow(candidates, execution, measurement)
extern "C" fn provider_construction_probe(
  candidates : Array[ManagedProvider],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> String = "actql_proof_provider_construction"
