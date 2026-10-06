///|
#borrow(parent, children, completed, current, position, pending, used, cancelled, terminal, reclaimed, cleanup_index, sequence, inputs, execution, measurement, numeric, family)
extern "C" fn parent_control_probe(
  parent : ManagedProviderExecution,
  children : Ref[Array[ManagedProviderExecution]],
  completed : Ref[Array[@execution.CompletedOutput?]],
  current : Ref[ManagedProviderExecution?],
  position : Ref[Int],
  pending : Ref[Bool],
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
) -> String = "actql_proof_parent_control"

///|
#borrow(parent)
extern "C" fn parent_core_phase_probe(
  parent : ManagedProviderExecution,
  phase : Int,
) -> String = "actql_proof_parent_phase"

///|
#borrow(candidates, execution, measurement)
extern "C" fn provider_construction_probe(
  candidates : Array[ManagedProvider],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> String = "actql_proof_provider_construction"
