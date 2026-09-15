///|
/// Host-fixed Local implementation configuration. Entries are private sequence
/// handles, not shared planner payloads or reconstructed checked owners.
struct LocalComputeModule {
  registry : @connector.CapabilityRegistry
  registration : @connector.CapabilityRegistration
  sequences : Array[@execution.GeneratedSequence]
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  max_work : Int
}

///|
pub(all) enum LocalModuleIssue {
  Candidate(@connector.FixedComputeIssue)
  NotSelected
  Capacity
  Execution(@connector.FixedComputeIssue)
}

///|
/// Pure bounded installation. This snapshots only the sequence-handle container;
/// it does not admit values, execute a sequence, or allocate task resources.
pub fn prepare_local_compute_module(
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  sequences : Array[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_work : Int,
  max_sequences : Int,
) -> Result[LocalComputeModule, @connector.FixedComputeIssue] {
  if max_work < 1 || max_sequences < 0 || sequences.length() > max_sequences {
    return Err(InvalidLimits)
  }
  if !@connector.capability_registration_matches(registration, registry) {
    return Err(ForeignCapability(0))
  }
  if !@connector.capability_description(registration).fixed_compute {
    return Err(ComputeUnsupported)
  }
  Ok({
    registry,
    registration,
    sequences: sequences.copy(),
    execution,
    measurement,
    max_work,
  })
}

///|
/// The slot is this module's bounded configuration index, not a semantic task
/// identity. Candidate preparation still verifies the exact request owner.
pub fn prepare_local_module_compute(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.FixedComputeRequest,
  join_output_ceiling : (Int, Int64)?,
) -> Result[@connector.SynchronousCompute, LocalModuleIssue] {
  guard installed.sequences.get(slot) is Some(sequence) else {
    return Err(Candidate(ForeignPreparation))
  }
  let candidate = match
    local_fixed_compute_candidate(
      installed.registration,
      request,
      sequence,
      [],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      installed.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let choice = match
    @connector.choose_fixed_compute_candidate(
      installed.registry,
      request,
      [@connector.prepared_compute_candidate(candidate)],
      Some([0]),
      installed.max_work,
    ) {
    Ok(Proposed(choice)) => choice
    Ok(_) => return Err(NotSelected)
    Err(issue) => return Err(Candidate(issue))
  }
  match
    prepare_local_compute_execution(
      choice,
      candidate,
      installed.execution,
      installed.measurement,
      join_output_ceiling~,
    ) {
    Ok(compute) => Ok(compute)
    Err(InvalidLimits) => Err(Capacity)
    Err(issue) => Err(Execution(issue))
  }
}

///|
/// Capacity for the module's actual fixed sequence and selected limits, not an
/// estimate derived from output cardinality or an exported mutable sequence.
pub fn local_module_capacity(
  installed : LocalComputeModule,
  slot : Int,
) -> @execution.ExecutionCapacity? {
  guard installed.sequences.get(slot) is Some(sequence) else { return None }
  @execution.generated_sequence_capacity(
    sequence,
    installed.execution,
    installed.measurement,
  )
}
