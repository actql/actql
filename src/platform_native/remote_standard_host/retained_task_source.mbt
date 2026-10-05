///|
pub(all) enum NativeRemoteRetainedTaskSourceIssue {
  Input(NativeRemoteRetainedTaskInputIssue)
  ForeignConsumer
  ForeignCapture
  Source(NativeRemoteStandardInputFailure)
}

///|
/// Attach an already-owned destination borrow to its checked consumer.
/// No reader or reservation is invented here. Pre-admission rejection leaves
/// that borrow with the caller; physical admission failure returns the
/// existing retryable input cleanup owner. The caller pins the reader using
/// the original consumer dispatch identity, including its exact attempt.
/// Success returns a captured source
/// whose close operation returns only this borrow, not either holding.
pub fn acquire_native_remote_retained_task_source(
  input : NativeRemoteRetainedTaskInput,
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  dispatch : @remote.DispatchRequest,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  limits : NativeRemoteStandardTransferSourceLimits,
  current : NativeRemoteRetainedInputCurrent,
) -> Result[
  NativeRemoteStandardTransferSource,
  NativeRemoteRetainedTaskSourceIssue,
] {
  match
    retained_task_source_semantics(input, dispatch, sequence, program, current) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if @transfer_client.destination_material_use_reader_id(material) !=
    @remote.dispatch_request_identity(dispatch) {
    return Err(Input(ForeignTransfer))
  }
  match
    validate_native_remote_retained_task_input_borrow(input, material, current) {
    Ok(_) => ()
    Err(issue) => return Err(Input(issue))
  }
  let physical = register_native_remote_standard_physical_source(
    input.physical,
    () => {
      validate_native_remote_retained_task_input_borrow(
        input, material, current,
      )
      is Ok(_)
    },
    (max_bytes, emit) => {
      if validate_native_remote_retained_task_input_borrow(
          input, material, current,
        )
        is Err(_) {
        return Err("retained-input-unavailable")
      }
      @transfer_client.stream_destination_material_use(
        material, max_bytes, emit,
      ).map_err(_ => "retained-input-stream")
    },
    () => @transfer_client.release_destination_material_use(material) is Ok(_),
  )
  acquire_native_remote_retained_physical_source(
    input, physical, dispatch, codec, sequence, program, limits, current,
  )
}

///|
fn retained_task_source_semantics(
  input : NativeRemoteRetainedTaskInput,
  dispatch : @remote.DispatchRequest,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  current : NativeRemoteRetainedInputCurrent,
) -> Result[Unit, NativeRemoteRetainedTaskSourceIssue] {
  let producer = @publication_host.client_retained_task_input_producer(
    input.common,
  )
  let edge = @publication_host.client_retained_input_producer_edge(producer)
  let ports = @publication_host.client_retained_input_edge_projection(edge)
  if !@remote.remote_input_binding_matches_dispatch(input.binding, dispatch) ||
    @remote.dispatch_request_task_scope(dispatch) != (ports[0], ports[5]) ||
    @remote.dispatch_request_execution_scope(dispatch) !=
    @remote.dispatch_request_execution_scope(
      @publication_host.client_retained_input_producer_dispatch(producer),
    ) ||
    @remote.dispatch_request_journal_key(dispatch)[0] !=
    @remote.dispatch_request_journal_key(
      @publication_host.client_retained_input_producer_dispatch(producer),
    )[0] {
    return Err(ForeignConsumer)
  }
  if !@publication_host.client_retained_input_capture_owner_matches(
      edge, sequence, program,
    ) {
    return Err(ForeignCapture)
  }
  native_retained_task_input_current(input, current).map_err(issue => {
    Input(issue)
  })
}

///|
/// Registered physical routes share the same checked retained-input admission.
/// The provider owns its exact borrow and physical lifetime; this owner
/// verifies the consumer edge and rechecks trusted authorization around the
/// provisional stream. It neither executes Source nor frees a holding.
fn acquire_native_remote_retained_physical_source(
  input : NativeRemoteRetainedTaskInput,
  physical : NativeRemoteStandardPhysicalSource,
  dispatch : @remote.DispatchRequest,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  limits : NativeRemoteStandardTransferSourceLimits,
  current : NativeRemoteRetainedInputCurrent,
) -> Result[
  NativeRemoteStandardTransferSource,
  NativeRemoteRetainedTaskSourceIssue,
] {
  match
    retained_task_source_semantics(input, dispatch, sequence, program, current) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let guarded = register_native_remote_standard_physical_source(
    input.physical,
    () => {
      native_retained_task_input_current(input, current) is Ok(_) &&
      (physical.available)()
    },
    physical.stream,
    physical.release,
  )
  // Preserve the registered provider's binding rather than rebinding a
  // different physical generation under this consumer's input.
  if physical.request_cid != guarded.request_cid ||
    physical.input_binding_cid != guarded.input_binding_cid {
    return Err(ForeignConsumer)
  }
  acquire_native_remote_standard_physical_source(
    input.physical,
    guarded,
    codec,
    sequence,
    program,
    limits,
  ).map_err(issue => Source(issue))
}
