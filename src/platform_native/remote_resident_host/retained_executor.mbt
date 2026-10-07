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
  let output_storage = configuration.source.retained_output_root.map(root => {
    () => {
      @retained_file.begin_native_retained_task_file(
        root,
        @remote.dispatch_request_identity(dispatch)[7:].to_owned(),
        output_limits.max_retained_bytes,
      ).map_err(_ => "retained-output-storage")
    }
  })
  let factory = match
    @output.register_native_remote_standard_dispatch_run_factory(
      dispatch,
      binding,
      () => {
        let consumer = match
          open_resident_retained_compute(
            prepared, configuration, input, material, dispatch, codec, input_limits,
            current,
          ) {
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
        // The in-memory profile retains its original output lifetime.
        Ok(
          @output.prepare_native_remote_standard_captured_run_owner(
            consumer.compute,
            () => {
              consumer.close() &&
              (match (output_storage, release_retired_input) {
                (Some(_), Some(release)) => release()
                _ => true
              })
            },
            () => true,
            output_storage~,
            retire_run_after_file_handoff=output_storage is Some(_),
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
