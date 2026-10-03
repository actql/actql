///|
#borrow(parent, children, previous, current, position, pending, used, cancelled, terminal, reclaimed, cleanup_index, sequence, inputs, execution, measurement, numeric, family)
extern "C" fn parent_control_probe(
  parent : ManagedProviderExecution,
  children : Ref[Array[ManagedProviderExecution]],
  previous : Ref[@execution.CompletedOutput?],
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
