///|
/// Execute the original checked pure prefix using the existing Local managed
/// provider. No replacement Program, Source observation or serialization runtime
/// is created. The original Run ledger owns its reservation until the same
/// provider confirms cleanup, including after completed input is borrowed.
struct ClientSerializationPrefix {
  mut child : @local.ManagedProviderExecution?
  // Fixed controller DATA, not another owner/allowance or cleanup witness.
  // Preserve the child's actual validated total after its heavy alias retires.
  mut final_work : Result[Int64, @local.ManagedProviderWorkIssue]?
  mut cleanup_busy : Bool
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
  query_time? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )? = None,
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
      prepared,
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      query_time~,
    )
  } else {
    prepare_client_serialization_prefix(
      prepared,
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      query_time~,
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
    is Ok(query) else {
    return Err(Unavailable)
  }
  let inputs = match
    prepare_acquired_serialization_prefix_inputs(
      prepared, task, source, sequence, query, execution, measurement, ledger, keyed,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
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
// The existing input binding logic, with no prefix/provider reconstruction or
// reservation. Managed callers reserve and retain their original prefix BEFORE
// these liveness callbacks and input/row-buffer constructors can enter.
fn prepare_acquired_serialization_prefix_inputs(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  source : @query.CapturedInputSource,
  sequence : @execution.GeneratedSequence,
  original_query : @sourceviews.QueryAcquisition,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  keyed : @publication_host.ClientKeyedLookupInput?,
) -> Result[Array[@local.ManagedProviderInput], ClientSerializationPrefixIssue] {
  guard @sourceviews.query_acquisition_capture(original_query)
    is @pipeline.Step(capture) else {
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
  Ok(inputs)
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
  // Retain the original reservation BEFORE the fallible provider constructor.
  // None with child_cleaned=false remains pending if foreign code unwinds
  // without a returned child or a known no-child refusal. It is never an ACK.
  let prefix = serialization_prefix_reservation(ledger, reservation)
  start_retained_serialization_prefix_provider(
    prefix, sequence, provider, inputs, execution, measurement,
  )
}

///|
fn serialization_prefix_reservation(
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
) -> ClientSerializationPrefix {
  {
    child: None,
    final_work: None,
    cleanup_busy: false,
    ledger,
    reservation,
    child_cleaned: false,
    released: false,
  }
}

///|
// The caller retained this exact reservation before any later original fence
// or fallible constructor. It does not observe current or reserve again.
fn start_retained_serialization_prefix_provider(
  prefix : ClientSerializationPrefix,
  sequence : @execution.GeneratedSequence,
  provider : @local.ManagedProvider,
  inputs : Array[@local.ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  match
    @local.start_managed_provider_with_inputs_and_execution(
      provider,
      sequence,
      inputs,
      execution.rows.max_rows,
      measurement.max_bytes,
      execution,
    ) {
    Ok(child) => {
      prefix.child = Some(child)
      Ok(prefix)
    }
    Err(issue) => {
      // A rejected provider start supplies no allocated execution handle.
      prefix.child_cleaned = true
      match cleanup_client_serialization_prefix(prefix) {
        Ok(true) => Err(Provider(issue))
        Ok(false) => Err(Unavailable)
        Err(issue) => Err(issue)
      }
    }
  }
}

///|
pub fn advance_client_serialization_prefix(
  value : ClientSerializationPrefix,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if value.child_cleaned {
    return Ok(@local.managed_provider_stopped_poll(0L, 0L))
  }
  if value.cleanup_busy {
    return Err(@connector.Execution(@execution.InputSet))
  }
  match value.child {
    Some(child) => @local.advance_managed_provider(child, quantum)
    None => Err(@connector.Execution(@execution.InputSet))
  }
}

///|
/// The same child's cumulative observation remains readable after failure or
/// close. A failed advance can have consumed work even without a returned poll.
pub fn client_serialization_prefix_work(
  value : ClientSerializationPrefix,
) -> Result[Int64, @local.ManagedProviderWorkIssue] {
  if value.final_work is Some(original) {
    return original
  }
  match value.child {
    Some(child) => @local.managed_provider_cumulative_work(child)
    // No execution handle has returned. This is observed work only, not
    // proof of physical stop or of how much constructor CPU was consumed.
    None => Ok(0L)
  }
}

///|
pub fn cancel_client_serialization_prefix(
  value : ClientSerializationPrefix,
) -> Bool {
  !value.child_cleaned &&
  !value.cleanup_busy &&
  value.child is Some(child) &&
  @local.cancel_managed_provider(child)
}

///|
pub fn cleanup_client_serialization_prefix(
  value : ClientSerializationPrefix,
) -> Result[Bool, ClientSerializationPrefixIssue] {
  if value.released {
    return Ok(true)
  }
  if value.cleanup_busy {
    return Ok(false)
  }
  value.cleanup_busy = true
  preparation_module_call(
    () => {
      if !value.child_cleaned {
        guard value.child is Some(child) else { return Ok(false) }
        match @local.cleanup_managed_provider(child) {
          Ok(true) => {
            value.child_cleaned = true
            // This getter is the same callback-free reported_work field read,
            // not a second current/stop/probe. Keep its exact Result (including
            // invalid/overflow) before dropping provider closures and inputs.
            value.final_work = Some(
              @local.managed_provider_cumulative_work(child),
            )
            value.child = None
          }
          Ok(false) => return Ok(false)
          Err(issue) => return Err(Provider(issue))
        }
      }
      // Alias retirement follows the original child ACK, before this original
      // settlement can consume/fail. A failed return remains retryable here;
      // it never restores a child or repeats its spent cleanup duty.
      match @resources.settle_reservation(value.ledger, value.reservation) {
        Ok(_) => {
          value.released = true
          Ok(true)
        }
        Err(issue) => Err(Physical(issue))
      }
    },
    () => value.cleanup_busy = false,
  )
}
