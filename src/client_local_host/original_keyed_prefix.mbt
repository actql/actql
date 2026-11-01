///|
// Select the checked left producer, not the acquisition's earlier completion.
// This prepares only the existing Local residual sequence; it executes neither
// the Source acquisition nor the keyed join or serialization barrier.
fn original_keyed_left_prefix_provider(
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> (
  @execution.GeneratedSequence,
  @local.ManagedProvider,
  @execution.ExecutionCapacity,
  Int,
)? {
  guard @publication_host.client_keyed_acquisition_matches_program(
      keyed, prepared,
    ) &&
    @publication_host.client_keyed_acquisition_coordinates(keyed)
    is Some((_, task, join)) &&
    @publication_host.client_keyed_direct_acquisition_coordinates(keyed)
    is Some((_, input, _)) &&
    @publication_host.prepare_client_query_acquisition(prepared, task, input)
    is Ok(query) &&
    @sourceviews.query_acquisition_capture(query) is @pipeline.Step(capture) &&
    @lower.node_at(
      @lower.bound_preparation(
        @publication_host.client_keyed_acquisition_owner(keyed),
      ),
      join,
    )
    is Some(node) &&
    @lower.node_input_target(node, 0) is Some(@pipeline.Step(left)) &&
    left > capture &&
    left < join &&
    execution.max_work > 0 &&
    measurement.max_bytes >= 0 else {
    return None
  }
  guard prepare_client_local_sequences_owned(
      Pure(prepared),
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      task_count=Some(task + 1),
      selected_task=Some(task),
      infer_prefix=Some((task, left)),
      acquisition_source=Some((task, input)),
    )
    .to_option()
    .bind(sequences => sequences.get(0))
    .bind(sequence => {
      @execution.select_generated_sequence_range(sequence, capture + 1, left)
    })
    is Some(sequence) &&
    @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) &&
    @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
    return None
  }
  Some((sequence, provider, capacity, capture))
}

///|
// This is the selected provider's existing allowance, not a physical Host
// profile or permission to borrow a different original Run's Ledger.
pub fn client_original_keyed_left_prefix_capacity(
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> @execution.ExecutionCapacity? {
  original_keyed_left_prefix_provider(
    prepared, keyed, installed_contracts, values_body, fragment_body, ordered_body,
    execution, measurement,
  ).map(value => value.2)
}

///|
// Core Local is the closed borrower of the same original captured Scope.
// Reuse ClientSerializationPrefix's provider reservation and cleanup; no new
// execution Owner, capture, Ledger, Source read or normal numeric supplier.
// Bootstrap must already fund selection/input/control overlap before this
// constructor. Keep the original Row capture until this prefix is reclaimed.
pub fn start_client_original_keyed_left_prefix(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  capture : @row_source_host.RowSourceCapture,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_entries : Int,
  max_name_bytes : Int,
  workspace? : @execution.ExecutionCapacity? = None,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  start_client_original_keyed_left_prefix_owned(
    scope, compiled, definition, plan, prepared, keyed, capture, installed_contracts,
    values_body, fragment_body, ordered_body, execution, measurement, max_entries,
    max_name_bytes, workspace,
  ).map(value => value.0)
}

///|
// The existing managed execution and the exact input it consumed. Keep this
// tuple inside Core Local; it is not a Node Ledger getter or a new Owner.
fn start_client_original_keyed_left_prefix_owned(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  capture : @row_source_host.RowSourceCapture,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_entries : Int,
  max_name_bytes : Int,
  workspace : @execution.ExecutionCapacity?,
) -> Result[
  (
    ClientSerializationPrefix,
    @query.CapturedInputSource,
    @execution.ProducerRead,
  ),
  ClientSerializationPrefixIssue,
] {
  let source = match @row_source_host.row_capture_source(capture) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let ledger = match
    @publication_host.borrow_client_original_keyed_captured_ledger(
      scope, compiled, definition, plan, prepared, keyed, source,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  guard @row_source_host.row_capture_original_prefix_requirement(
      capture, ledger,
    )
    is Some(_) else {
    return Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState)),
    )
  }
  guard original_keyed_left_prefix_provider(
      prepared, keyed, installed_contracts, values_body, fragment_body, ordered_body,
      execution, measurement,
    )
    is Some((sequence, provider, capacity, captured_step)) else {
    return Err(Unavailable)
  }
  let owner = @execution.generated_sequence_owner(sequence)
  let inputs : Array[@local.ManagedProviderInput] = []
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    guard @execution.generated_sequence_step_index_at(sequence, index)
      is Some(consumer) &&
      @lower.node_at(@lower.bound_preparation(owner), consumer) is Some(node) else {
      return Err(Unavailable)
    }
    for port in 0..<@lower.node_input_count(node) {
      guard @lower.node_input_target(node, port) is Some(target) else {
        return Err(Unavailable)
      }
      match target {
        @pipeline.Step(step) if step > captured_step => ()
        @pipeline.Step(step) if step == captured_step => {
          let bound = match
            @query.bind_captured_source_operation(source, owner, consumer, port) {
            Ok(value) => value
            Err(issue) => return Err(Capture(issue))
          }
          let read = match
            @execution.prepare_producer_read(
              owner, bound, max_entries, max_name_bytes,
            ) {
            Ok(value) => value
            Err(issue) => return Err(ProducerRead(issue))
          }
          inputs.push(@local.managed_provider_relation_input(read))
        }
        _ => return Err(Unavailable)
      }
    }
  }
  // Binding invokes Source liveness. Both the original current fence and the
  // exact capture tokens must still match AFTER every callback, before reserve.
  guard inputs.length() == 1 &&
    @publication_host.borrow_client_original_keyed_captured_ledger(
      scope, compiled, definition, plan, prepared, keyed, source,
    )
    is Ok(current) &&
    physical_equal(current, ledger) &&
    @row_source_host.row_capture_original_prefix_requirement(capture, ledger)
    is Some(_) else {
    return Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState)),
    )
  }
  start_serialization_prefix_provider(
    sequence, provider, capacity, inputs, execution, measurement, ledger, workspace,
  ).map(prefix => {
    // This constructor admitted exactly one external original capture above.
    match inputs[0] {
      @local.RelationInput(read) => (prefix, source, read)
      _ => abort("checked keyed prefix requires its original Relation input")
    }
  })
}
