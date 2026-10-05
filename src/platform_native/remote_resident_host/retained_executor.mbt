///|
/// Install the original checked consumer in the existing remote Runtime.
/// Registration performs no acquisition, capture or physical input read. The
/// fixed factory opens its owned borrow only after Runtime admission, current
/// authorization and the exclusive start claim. Output release returns the
/// consumer borrow; neither Transfer holding is reclaimed by this executor.
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
) -> Result[
  @output.NativeRemoteStandardTaskExecutor,
  ResidentSourceComputeIssue,
] {
  let prepared = materials.prepared
  let graph = @host.prepared_client_graph(prepared)
  guard materials.compilation is @host.Tasks(compilation) &&
    @strategy.graph_task_count(graph) == 2 &&
    !@strategy.graph_program_has_effects(graph) &&
    @host.prepared_client_acquisition_count(prepared) == 1 &&
    @host.prepared_client_result_count(prepared) == 1 &&
    @strategy.graph_result_task(graph, 0) == Some(1) &&
    @strategy.graph_task_target(graph, 0) is None &&
    @strategy.graph_task_target(graph, 1) is Some(_) else {
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
      1,
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
          Err((_, cleanup)) => return Err(cleanup)
        }
        // The synchronous Compute stops before its output is handed to Runtime.
        // Keep input custody with that output until Runtime authorizes release;
        // its generic finish-input hook must not return the borrow prematurely.
        Ok(
          @output.prepare_native_remote_standard_captured_run_owner(
            consumer.compute,
            () => consumer.close(),
            () => true,
          ),
        )
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(Standard(issue)))
  }
  @output.install_native_remote_standard_bound_task_executor(
    definition_cid, task_key, 1, factory, output_limits,
  ).map_err(issue => Source(Standard(issue)))
}
