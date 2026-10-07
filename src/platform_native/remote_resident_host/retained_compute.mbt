///|
/// Rebuild the existing checked consumer from an independently held Transfer
/// destination. The caller already owns its exact consumer reader occurrence;
/// pre-admission refusal leaves that reader with the caller. On successful
/// capture the returned Owner assumes its borrow cleanup. Neither holding nor
/// Named Result retention transfers to this constructor.
pub fn open_resident_retained_compute(
  prepared : @host.PreparedClientProgram,
  configuration : ResidentSourceComputeConfiguration,
  input : @output.NativeRemoteRetainedTaskInput,
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  dispatch : @remote.DispatchRequest,
  codec : @output.NativeRemoteStandardRowCodec,
  input_limits : @output.NativeRemoteStandardTransferSourceLimits,
  current : @output.NativeRemoteRetainedInputCurrent,
  observe? : (ResidentSourceComputeEvent) -> Bool,
) -> Result[
  ResidentSourceCompute,
  (ResidentSourceComputeIssue, @output.NativeRemoteStandardInputFailure),
] {
  let reject = fn(issue : ResidentSourceComputeIssue, cleanup : () -> Bool) {
    Err(
      (
        issue,
        @output.prepare_native_remote_standard_input_failure(
          "retained-compute-preparation", cleanup,
        ).unwrap(),
      ),
    )
  }
  let graph = @host.prepared_client_graph(prepared)
  let (_, task_key) = @remote.dispatch_request_task_scope(dispatch)
  guard resident_linear_graph(graph) &&
    @host.prepared_client_acquisition_count(prepared) == 1 &&
    @host.prepared_client_result_count(prepared) == 1 &&
    resident_prepared_task_index(prepared, task_key) is Some(consumer) &&
    consumer > 0 else {
    return reject(UnsupportedGraph, () => true)
  }
  let projection = match
    @strategy.prepare_retained_task_projection(graph, consumer) {
    Ok(value) => value
    Err(_) => return reject(UnsupportedGraph, () => true)
  }
  let producer = @strategy.retained_task_projection_producer(projection)
  let source = configuration.source
  let requirement = match
    @local.prepare_local_query_requirement(
      prepared,
      0,
      0,
      configuration.registry_body,
      configuration.values_body,
      Some(source.fragment_contract_body),
      None,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Source(Query(issue)), () => true)
  }
  match
    require_resident_source_identity(
      requirement,
      source.source_ref,
      source.source_contract_cid,
    ) {
    Ok(_) => ()
    Err(issue) => return reject(Source(issue), () => true)
  }
  // Reserve the actual Transfer decoder. Source acquisition (including its
  // Native/Broad scan budgets) is neither prepared nor executed by a consumer.
  guard @output.native_remote_standard_transfer_source_capacity(input_limits)
    is Some(capacity) else {
    return reject(Capacity(@resources.InvalidCharge), () => true)
  }
  guard @local.prepare_client_local_sequences(
      prepared,
      configuration.registry_body,
      configuration.values_body,
      Some(source.fragment_contract_body),
      None,
    )
    is Some(generated) &&
    generated.length() == @strategy.graph_task_count(graph) else {
    return reject(UnsupportedGraph, () => true)
  }
  // Use the original physical producer's selected operation or fused prefix,
  // exactly as the existing Local driver does before deriving completion.
  let producer_sequence = match
    @strategy.graph_task_selected_step(graph, producer) {
    Some(step) =>
      @execution.select_generated_sequence_step(generated[producer], step)
    None =>
      match @strategy.graph_task_prefix_end(graph, producer) {
        Some(last) =>
          @execution.select_generated_sequence_prefix(generated[producer], last)
        None => Some(generated[producer])
      }
  }
  guard producer_sequence is Some(producer_sequence) else {
    return reject(UnsupportedGraph, () => true)
  }
  let ledger = match @resources.create_ledger(source.ledger) {
    Ok(value) => value
    Err(issue) => return reject(Capacity(issue), () => true)
  }
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      0L,
      capacity.retained_bytes,
      capacity.execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Capacity(issue), () => true)
  }
  let return_reservation = () => {
    !@resources.reservation_open(reservation) ||
    @resources.settle_reservation(ledger, reservation) is Ok(_)
  }
  let captured = match
    @output.acquire_native_remote_retained_task_output(
      input,
      material,
      dispatch,
      codec,
      producer_sequence,
      @planning.query_requirement_program(requirement),
      input_limits,
      current,
    ) {
    Ok(value) => value
    Err(issue) => {
      let cleanup = match issue {
        @output.Source(failure) =>
          () => {
            @output.retry_native_remote_standard_input_failure_cleanup(failure) &&
            return_reservation()
          }
        _ => return_reservation
      }
      return reject(RetainedInput(issue), cleanup)
    }
  }
  let close_borrow = () => {
    @output.finish_native_remote_retained_task_output(captured) &&
    return_reservation()
  }
  let holding = match
    @resources.retain_allocation(ledger, reservation, capacity.retained_bytes) {
    Ok(value) => value
    Err(issue) => return reject(Capacity(issue), close_borrow)
  }
  open_resident_captured_compute(
    prepared,
    configuration,
    None,
    ledger,
    holding,
    generated,
    close_borrow,
    observe,
    retained_input=Some(
      (
        projection,
        @output.native_remote_retained_task_output(captured),
        @output.native_remote_retained_task_output_wire_bytes(captured),
      ),
    ),
  )
}
