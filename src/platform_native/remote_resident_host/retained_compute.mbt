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
  if @strategy.graph_program_has_effects(graph) ||
    @strategy.graph_task_count(graph) != 2 ||
    @host.prepared_client_acquisition_count(prepared) != 1 ||
    @host.prepared_client_result_count(prepared) != 1 ||
    @strategy.graph_result_task(graph, 0) != Some(1) ||
    @strategy.graph_task_target(graph, 0) is Some(_) ||
    @strategy.graph_task_target(graph, 1) is None {
    return reject(UnsupportedGraph, () => true)
  }
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
    generated.length() == 2 else {
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
    @output.acquire_native_remote_retained_task_source(
      input,
      material,
      dispatch,
      codec,
      @planning.query_material_owner(
        @planning.query_requirement_material(requirement),
      ),
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
    @output.finish_native_remote_standard_transfer_source(captured) &&
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
    @output.native_remote_standard_transfer_captured_source(captured),
    ledger,
    holding,
    generated,
    close_borrow,
    observe,
  )
}
