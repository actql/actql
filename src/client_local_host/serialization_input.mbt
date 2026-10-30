///|
/// Execute the original checked pure prefix using the existing Local managed
/// provider. No replacement Program, Source observation or serialization runtime
/// is created. The original Run ledger owns its reservation until the same
/// provider confirms cleanup, including after completed input is borrowed.
struct ClientSerializationPrefix {
  child : @local.ManagedProviderExecution
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  mut child_cleaned : Bool
  mut released : Bool
}

///|
pub(all) enum ClientSerializationPrefixIssue {
  Unavailable
  Original(@publication_host.ClientModelReadPreparationIssue)
  Physical(@resources.LedgerIssue)
  Provider(@connector.FixedComputeIssue)
  Capture(@query.CapturedSourceIssue)
  ProducerRead(@execution.ProducerReadIssue)
}

///|
fn serialization_prefix_provider(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  acquired? : Bool = false,
) -> (
  @execution.GeneratedSequence,
  @local.ManagedProvider,
  @execution.ExecutionCapacity,
)? {
  if execution.max_work <= 0 ||
    execution.rows.max_rows < 0 ||
    measurement.max_bytes < 0 {
    return None
  }
  let sequence = if acquired {
    prepare_client_acquired_serialization_prefix(
      prepared, task, step, installed_contracts, values_body, fragment_body, ordered_body,
    )
  } else {
    prepare_client_serialization_prefix(
      prepared, task, step, installed_contracts, values_body, fragment_body, ordered_body,
    )
  }
  guard sequence is Some(sequence) &&
    @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) &&
    @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
    return None
  }
  Some((sequence, provider, capacity))
}

///|
/// Derive from the same selected provider, not a Host guess or row sample.
pub fn client_serialization_prefix_capacity(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> @execution.ExecutionCapacity? {
  serialization_prefix_provider(
    prepared, task, step, installed_contracts, values_body, fragment_body, ordered_body,
    execution, measurement,
  ).map(value => value.2)
}

///|
pub fn start_client_serialization_prefix(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  workspace? : @execution.ExecutionCapacity? = None,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  guard serialization_prefix_provider(
      prepared, task, step, installed_contracts, values_body, fragment_body, ordered_body,
      execution, measurement,
    )
    is Some((sequence, provider, capacity)) else {
    return Err(Unavailable)
  }
  start_serialization_prefix_provider(
    sequence,
    provider,
    capacity,
    [],
    execution,
    measurement,
    ledger,
    workspace,
  )
}

///|
pub fn client_acquired_serialization_prefix_capacity(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> @execution.ExecutionCapacity? {
  serialization_prefix_provider(
    prepared,
    task,
    step,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    execution,
    measurement,
    acquired=true,
  ).map(value => value.2)
}

///|
/// Borrow the original live capture, never replay its acquisition operators.
/// The caller retains capture custody until this prefix confirms cleanup.
pub fn start_client_acquired_serialization_prefix(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  source : @query.CapturedInputSource,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  workspace? : @execution.ExecutionCapacity? = None,
  keyed? : @publication_host.ClientKeyedLookupInput? = None,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  start_client_acquired_serialization_prefix_owned(
    prepared,
    task,
    step,
    source,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    execution,
    measurement,
    ledger,
    workspace,
    keyed,
    None,
  )
}

///|
// Original capture custody is checked again after input-binding liveness
// callbacks and immediately before the existing reservation. Ordinary callers
// retain their previous entry; this is not a generic callback or new Owner.
fn start_client_acquired_serialization_prefix_owned(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  source : @query.CapturedInputSource,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  workspace : @execution.ExecutionCapacity?,
  keyed : @publication_host.ClientKeyedLookupInput?,
  original_capture : @row_source_host.RowSourceCapture?,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  let direct = match keyed {
    Some(lookup) => {
      let acquisition = @publication_host.client_keyed_lookup_acquisition(
        lookup,
      )
      guard @publication_host.client_keyed_acquisition_reaches_serialization(
          prepared, acquisition, task, step,
        ) &&
        @publication_host.client_keyed_direct_acquisition_coordinates(
          acquisition,
        )
        is Some((_, input, direct_task)) else {
        return Err(Unavailable)
      }
      (direct_task, input)
    }
    None => (0, 0)
  }
  guard serialization_prefix_provider(
      prepared,
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      execution,
      measurement,
      acquired=true,
    )
    is Some((sequence, provider, capacity)) &&
    @publication_host.prepare_client_query_acquisition(
      prepared,
      direct.0,
      direct.1,
    )
    is Ok(query) &&
    @sourceviews.query_acquisition_capture(query) is @pipeline.Step(capture) else {
    return Err(Unavailable)
  }
  let owner = @execution.generated_sequence_owner(sequence)
  let inputs : Array[@local.ManagedProviderInput] = []
  let keyed_step = match keyed {
    None => None
    Some(lookup) => {
      let (left, right) = match
        @publication_host.prepare_client_keyed_serialization_inputs(
          prepared, lookup, source, ledger, sequence,
        ) {
        Ok(value) => value
        Err(_) => return Err(Unavailable)
      }
      guard @publication_host.client_keyed_acquisition_coordinates(
          @publication_host.client_keyed_lookup_acquisition(lookup),
        )
        is Some((_, _, join)) else {
        return Err(Unavailable)
      }
      inputs.push(@local.managed_provider_relation_input(left))
      inputs.push(@local.managed_provider_supplied_relation_input(right))
      Some(join)
    }
  }
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    guard @execution.generated_sequence_step_index_at(sequence, index)
      is Some(consumer) &&
      @lower.node_at(@lower.bound_preparation(owner), consumer) is Some(node) else {
      return Err(Unavailable)
    }
    for port in 0..<@lower.node_input_count(node) {
      if keyed_step == Some(consumer) {
        continue
      }
      guard @lower.node_input_target(node, port) is Some(target) else {
        return Err(Unavailable)
      }
      if (task == 0 || keyed is Some(_)) &&
        target is @pipeline.Step(target) &&
        target > capture {
        continue
      }
      if task == 1 && target is @pipeline.Step(_) {
        continue
      }
      let bound = match
        (if task == 1 && target is @pipeline.Input(index) {
          @query.bind_captured_source(source, owner, index)
        } else {
          @query.bind_captured_source_operation(source, owner, consumer, port)
        }) {
        Ok(bound) => bound
        Err(issue) => return Err(Capture(issue))
      }
      let read = match
        @execution.prepare_producer_read(
          owner,
          bound,
          execution.rows.operation_entries,
          measurement.max_bytes,
        ) {
        Ok(read) => read
        Err(issue) => return Err(ProducerRead(issue))
      }
      inputs.push(@local.managed_provider_relation_input(read))
    }
  }
  if original_capture is Some(capture) &&
    @row_source_host.row_capture_original_prefix_requirement(capture, ledger)
    is None {
    return Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState)),
    )
  }
  // Capacity addition and reserve_attempt below run synchronously and invoke
  // no capture/provider callback behind this final original-custody fence.
  start_serialization_prefix_provider(
    sequence, provider, capacity, inputs, execution, measurement, ledger, workspace,
  )
}

///|
fn start_serialization_prefix_provider(
  sequence : @execution.GeneratedSequence,
  provider : @local.ManagedProvider,
  capacity : @execution.ExecutionCapacity,
  inputs : Array[@local.ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  workspace : @execution.ExecutionCapacity?,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  let capacity = match workspace {
    None => capacity
    Some(workspace) =>
      match @execution.add_execution_capacity(capacity, workspace) {
        Some(combined) => combined
        None => return Err(Unavailable)
      }
  }
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      0L,
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
      quantities=@resources.quantity_neutral_amounts(ledger),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  match
    @local.start_managed_provider_with_inputs_and_execution(
      provider,
      sequence,
      inputs,
      execution.rows.max_rows,
      measurement.max_bytes,
      execution,
    ) {
    Ok(child) =>
      Ok(bind_serialization_prefix_reservation(child, ledger, reservation))
    Err(issue) =>
      // A rejected provider start supplies no allocated execution handle.
      match @resources.settle_reservation(ledger, reservation) {
        Ok(_) => Err(Provider(issue))
        Err(issue) => Err(Physical(issue))
      }
  }
}

///|
fn bind_serialization_prefix_reservation(
  child : @local.ManagedProviderExecution,
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
) -> ClientSerializationPrefix {
  { child, ledger, reservation, child_cleaned: false, released: false, }
}

///|
pub fn advance_client_serialization_prefix(
  value : ClientSerializationPrefix,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if value.child_cleaned {
    return Ok(@local.managed_provider_stopped_poll(0L, 0L))
  }
  @local.advance_managed_provider(value.child, quantum)
}

///|
/// The same child's cumulative observation remains readable after failure or
/// close. A failed advance can have consumed work even without a returned poll.
pub fn client_serialization_prefix_work(
  value : ClientSerializationPrefix,
) -> Result[Int64, @local.ManagedProviderWorkIssue] {
  @local.managed_provider_cumulative_work(value.child)
}

///|
pub fn cancel_client_serialization_prefix(
  value : ClientSerializationPrefix,
) -> Bool {
  !value.child_cleaned && @local.cancel_managed_provider(value.child)
}

///|
pub fn cleanup_client_serialization_prefix(
  value : ClientSerializationPrefix,
) -> Result[Bool, ClientSerializationPrefixIssue] {
  if value.released {
    return Ok(true)
  }
  if !value.child_cleaned {
    match @local.cleanup_managed_provider(value.child) {
      Ok(true) => value.child_cleaned = true
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Provider(issue))
    }
  }
  // Never mark this handle complete before the original ledger settles.
  match @resources.settle_reservation(value.ledger, value.reservation) {
    Ok(_) => {
      value.released = true
      Ok(true)
    }
    Err(issue) => Err(Physical(issue))
  }
}
