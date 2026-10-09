///|
/// Install the original checked consumer in the existing remote Runtime.
/// Registration performs no acquisition, capture or physical input read. The
/// fixed factory opens its owned borrow only after Runtime admission, current
/// authorization and the exclusive start claim. Output release returns the
/// consumer borrow. After a durable independent file handoff, the optional
/// retained-input cleanup callback reclaims the existing receiver Owner.
pub fn install_resident_retained_compute_executor(
  materials : @host.ClientRunMaterials,
  configuration : ResidentSourceComputeConfiguration,
  input : @output.NativeRemoteRetainedTaskInput,
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  dispatch : @remote.DispatchRequest,
  codec : @output.NativeRemoteStandardRowCodec,
  input_limits : @output.NativeRemoteStandardTransferSourceLimits,
  current : @output.NativeRemoteRetainedInputCurrent,
  output_limits : @output.NativeRemoteStandardTaskLimits,
  observe_failure? : (ResidentSourceComputeIssue) -> Unit,
  release_retired_input? : (() -> Bool)? = None,
) -> Result[
  @output.NativeRemoteStandardTaskExecutor,
  ResidentSourceComputeIssue,
] {
  let prepared = materials.prepared
  let graph = @host.prepared_client_graph(prepared)
  guard materials.compilation is @host.Tasks(compilation) &&
    resident_linear_graph(graph) &&
    @host.prepared_client_acquisition_count(prepared) == 1 &&
    @host.prepared_client_result_count(prepared) == 1 &&
    resident_linear_task_index(materials, dispatch) is Some(consumer_task) &&
    consumer_task > 0 else {
    return Err(UnsupportedGraph)
  }
  if @host.bind_client_task_run(
      prepared,
      compilation,
      materials.admission,
      materials.run_definition,
    )
    is Err(_) {
    return Err(UnsupportedGraph)
  }
  let fragment = match
    @host.issue_prepared_client_task_fragment(
      prepared,
      consumer_task,
      @host.client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(Fragment(issue)))
  }
  let definition_cid = @publication.publication_contract_identity(
    materials.run_definition,
  )
  let task_key = @host.client_task_fragment_node_id(fragment)
  let binding = @output.native_remote_retained_task_input_binding(input)
  if @remote.dispatch_request_task_scope(dispatch) != (definition_cid, task_key) ||
    !@remote.remote_input_binding_matches_dispatch(binding, dispatch) {
    return Err(Source(ForeignInput))
  }
  install_resident_retained_executor_owned(
    configuration,
    input,
    dispatch,
    definition_cid,
    task_key,
    consumer_task,
    output_limits,
    release_retired_input,
    () => {
      open_resident_retained_compute(
        prepared, configuration, input, material, dispatch, codec, input_limits,
        current,
      )
    },
    observe_failure,
  )
}

///|
/// Register the original Effect computation consumer with the existing remote
/// Runtime. The factory borrows its independent receiver holding only after
/// admission, current authorization and the exclusive start claim. It does not
/// approve or apply an Effect; task output and cleanup stay with Runtime.
pub fn install_resident_effect_retained_compute_executor(
  materials : @host.ClientEffectRunMaterials,
  configuration : ResidentSourceComputeConfiguration,
  input : @output.NativeRemoteRetainedTaskInput,
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  dispatch : @remote.DispatchRequest,
  codec : @output.NativeRemoteStandardRowCodec,
  input_limits : @output.NativeRemoteStandardTransferSourceLimits,
  current : @output.NativeRemoteRetainedInputCurrent,
  output_limits : @output.NativeRemoteStandardTaskLimits,
  observe_failure? : (ResidentSourceComputeIssue) -> Unit,
  release_retired_input? : (() -> Bool)? = None,
) -> Result[
  @output.NativeRemoteStandardTaskExecutor,
  ResidentSourceComputeIssue,
] {
  let fragment = match @host.issue_client_effect_task_fragment(materials, 1) {
    Ok(value) => value
    Err(_) => return Err(UnsupportedGraph)
  }
  let definition_cid = @publication.publication_contract_identity(
    materials.run_definition,
  )
  let task_key = @host.client_task_fragment_node_id(fragment)
  let binding = @output.native_remote_retained_task_input_binding(input)
  if @remote.dispatch_request_task_scope(dispatch) != (definition_cid, task_key) ||
    !@remote.remote_input_binding_matches_dispatch(binding, dispatch) {
    return Err(Source(ForeignInput))
  }
  install_resident_retained_executor_owned(
    configuration,
    input,
    dispatch,
    definition_cid,
    task_key,
    1,
    output_limits,
    release_retired_input,
    () => {
      open_resident_effect_retained_compute(
        materials, configuration, input, material, dispatch, codec, input_limits,
        current,
      )
    },
    observe_failure,
  )
}

///|
// Both prepared owners enter the same physical factory and cleanup path.
fn install_resident_retained_executor_owned(
  configuration : ResidentSourceComputeConfiguration,
  input : @output.NativeRemoteRetainedTaskInput,
  dispatch : @remote.DispatchRequest,
  definition_cid : String,
  task_key : String,
  consumer_task : Int,
  output_limits : @output.NativeRemoteStandardTaskLimits,
  release_retired_input : (() -> Bool)?,
  open_consumer : () -> Result[
    ResidentSourceCompute,
    (ResidentSourceComputeIssue, @output.NativeRemoteStandardInputFailure),
  ],
  observe_failure : ((ResidentSourceComputeIssue) -> Unit)?,
) -> Result[
  @output.NativeRemoteStandardTaskExecutor,
  ResidentSourceComputeIssue,
] {
  let binding = @output.native_remote_retained_task_input_binding(input)
  // A completed consumer must retain its exact output independently of the
  // process-local Compute owner. Reuse the same physical file/custody path as
  // the producer; never reacquire input to reconstruct a lost completion.
  guard configuration.source.retained_output_root is Some(output_root) else {
    return Err(Source(UnsupportedSource))
  }
  let output_storage = () => {
    @retained_file.begin_native_retained_task_file(
      output_root,
      @remote.dispatch_request_identity(dispatch)[7:].to_owned(),
      output_limits.max_retained_bytes,
    ).map_err(_ => "consumer-output-storage")
  }
  let factory = match
    @output.register_native_remote_standard_dispatch_run_factory(
      dispatch,
      binding,
      () => {
        let consumer = match open_consumer() {
          Ok(value) => value
          Err((issue, cleanup)) => {
            match observe_failure {
              Some(observer) => observer(issue)
              None => ()
            }
            return Err(cleanup)
          }
        }
        // The independent file must be durably handed off before retiring the
        // Compute/input owner. A pending cleanup remains owned by the output.
        Ok(
          @output.prepare_native_remote_standard_captured_run_owner(
            consumer.compute,
            () => consumer.close(),
            () => true,
            output_storage=Some(output_storage),
            retire_run_after_file_handoff=release_retired_input is Some(_),
            retired_input_cleanup=release_retired_input,
          ),
        )
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(Standard(issue)))
  }
  @output.install_native_remote_standard_bound_task_executor(
    definition_cid, task_key, consumer_task, factory, output_limits,
  ).map_err(issue => Source(Standard(issue)))
}
