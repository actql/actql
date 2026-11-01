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
  open_resident_retained_compute_owned(
    Pure(prepared),
    projection,
    configuration,
    input,
    material,
    dispatch,
    codec,
    input_limits,
    current,
    observe,
  )
}

///|
/// The original Effect materials bind this consumer before the independent
/// Transfer holding is borrowed. No Source is reacquired or Effect approved.
/// As with the ordinary entry, the caller owns pre-admission cleanup and must
/// hold the existing exclusive start claim/current authority before execution.
pub fn open_resident_effect_retained_compute(
  materials : @host.ClientEffectRunMaterials,
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
  let bound = match
    @host.bind_client_effect_compiled_run(
      materials.prepared,
      materials.allowed,
      materials.run_definition,
    ) {
    Ok(value) => value
    Err(issue) => return reject(EffectRun(issue), () => true)
  }
  let edge = match
    @host.prepare_client_effect_retained_input_edge(
      materials.allowed,
      materials.run_definition,
    ) {
    Ok(value) => value
    Err(issue) => return reject(EffectInput(issue), () => true)
  }
  let expected = @host.client_retained_input_edge_projection(edge)
  if @remote.dispatch_request_task_scope(dispatch) != (expected[0], expected[5]) ||
    !@remote.remote_input_binding_matches_dispatch(
      @output.native_remote_retained_task_input_binding(input),
      dispatch,
    ) {
    return reject(Source(ForeignInput), () => true)
  }
  let projection = match
    @strategy.prepare_retained_effect_task_projection(
      @host.prepared_client_effect_run_graph(bound),
    ) {
    Ok(value) => value
    Err(_) => return reject(UnsupportedGraph, () => true)
  }
  open_resident_retained_compute_owned(
    Effect(bound),
    projection,
    configuration,
    input,
    material,
    dispatch,
    codec,
    input_limits,
    current,
    observe,
    effect_materials=Some((materials, bound)),
  )
}

///|
fn open_resident_retained_compute_owned(
  prepared : ResidentSourceOwner,
  projection : @strategy.RetainedTaskProjection,
  configuration : ResidentSourceComputeConfiguration,
  input : @output.NativeRemoteRetainedTaskInput,
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  dispatch : @remote.DispatchRequest,
  codec : @output.NativeRemoteStandardRowCodec,
  input_limits : @output.NativeRemoteStandardTransferSourceLimits,
  current : @output.NativeRemoteRetainedInputCurrent,
  observe : ((ResidentSourceComputeEvent) -> Bool)?,
  effect_materials? : (
    @host.ClientEffectRunMaterials,
    @host.PreparedClientEffectRun,
  )? = None,
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
  let graph = resident_source_owner_graph(prepared)
  let producer = @strategy.retained_task_projection_producer(projection)
  let source = configuration.source
  let requirement = match
    resident_source_owner_requirement(prepared, configuration) {
    Ok(value) => value
    Err(issue) => return reject(Source(issue), () => true)
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
  guard resident_source_owner_sequences(prepared, configuration)
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
  let (dispatch_preparation, estimates) = match
    prepare_resident_compute_dispatch(
      prepared,
      @graph.retained_task_projection_graph(projection),
      configuration,
      ledger,
      generated,
    ) {
    Ok(value) => value
    Err(issue) => return reject(issue, () => true)
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
      (ledger, reservation),
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
    dispatch_preparation,
    estimates,
    close_borrow,
    observe,
    effect_retained=match prepared {
      Effect(_) => Some({ dispatch, input, material, current, })
      Pure(_) => None
    },
    effect_materials~,
    retained_input=Some(
      (
        projection,
        @output.native_remote_retained_task_output(captured),
        @output.native_remote_retained_task_output_wire_bytes(captured),
      ),
    ),
  )
}
