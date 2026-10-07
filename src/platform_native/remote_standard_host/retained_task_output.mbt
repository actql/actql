///|
/// One decoded completed predecessor and its original destination reader.
/// Closing this Owner revokes the imported output before returning the reader;
/// neither the producer nor destination holding is released here.
struct NativeRemoteRetainedTaskOutput {
  token : NativeRemoteTransferSourceToken
  output : @execution.CompletedOutput
  wire_bytes : Int
}

///|
pub fn native_remote_retained_task_output(
  value : NativeRemoteRetainedTaskOutput,
) -> @execution.CompletedOutput {
  value.output
}

///|
/// Exact extent admitted by the existing bounded row decoder, not an estimate
/// copied from the original Source or supplied by the execution-view caller.
pub fn native_remote_retained_task_output_wire_bytes(
  value : NativeRemoteRetainedTaskOutput,
) -> Int {
  value.wire_bytes
}

///|
pub fn finish_native_remote_retained_task_output(
  value : NativeRemoteRetainedTaskOutput,
) -> Bool {
  finish_transfer_source_token(value.token)
}

///|
/// Decode a checked completed task at its own original preparation and target.
/// Source capture remains a separate API; no Source query is acquired here.
pub fn acquire_native_remote_retained_task_output(
  input : NativeRemoteRetainedTaskInput,
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  dispatch : @remote.DispatchRequest,
  codec : NativeRemoteStandardRowCodec,
  generated : @execution.GeneratedSequence,
  program : @context.ProgramSourceIdentity,
  limits : NativeRemoteStandardTransferSourceLimits,
  current : NativeRemoteRetainedInputCurrent,
) -> Result[NativeRemoteRetainedTaskOutput, NativeRemoteRetainedTaskSourceIssue] {
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
  let preparation = @execution.generated_completion_preparation(generated)
  if !@publication_host.client_retained_input_output_owner_matches(
      edge, preparation, program,
    ) {
    return Err(ForeignCapture)
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
  let admission = match
    prepare_native_remote_standard_output_admission(
      input.physical,
      physical,
      codec,
      preparation,
      @publication_host.client_retained_input_edge_target(edge),
      None,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  match stream_native_remote_standard_physical_admission(admission) {
    Ok(_) => ()
    Err(issue) => return Err(Source(issue))
  }
  finish_native_remote_standard_output_admission(admission).map_err(issue => {
    Source(issue)
  })
}
