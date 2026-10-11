///|
/// Physical output conversion from the original retained Compute owner into
/// the existing all-Named-Results publication owner. No Source or task is
/// reopened. Current Run/publication authority belongs to the calling Host.
pub fn ResidentSourceCompute::prepare_result_publication(
  self : ResidentSourceCompute,
  service : @native_publication.NativeRunPublicationService,
  context : @native_publication.NativeEffectFreeRunContext,
  results : Array[@native_publication.NativeCapturedResultPublicationContext],
  intent : @native_publication.NativeRunPublicationIntent,
  occurrence : @native_publication.NativeRunPublicationOccurrence,
  limits : @host.PublicationOutputExportLimits,
) -> Result[
  @native_publication.NativePreparedCapturedRunPublication,
  ResidentSourceResultPublicationIssue,
] {
  // Effect Runs keep their own capture/receipt owner; never publish them by
  // omitting their Effect obligations from an Effect-free receipt.
  if self.stopping || self.effect_run is Some(_) {
    return Err(Unavailable)
  }
  let graph = @strategy.captured_dag_graph(self.run)
  let converted : Array[@execution.CompletedOutput?] = []
  for result in 0..<@strategy.graph_result_count(graph) {
    guard @strategy.graph_result_task(graph, result) is Some(task) else {
      return Err(Unavailable)
    }
    match
      @duckdb_native.read_native_standard_task_output(
        self.compute,
        task,
        limits.max_rows,
        limits.values,
        limits.payload_wire,
        limits.max_batch_bytes,
      ) {
      Ok(output) => converted.push(Some(output))
      Err(issue) => return Err(Output(issue))
    }
  }
  @native_publication.prepare_captured_effect_free_run_publication_native(
    service,
    self.run,
    context,
    results,
    intent,
    occurrence,
    limits,
    converted_outputs=converted,
  ).map_err(issue => Publication(issue))
}

///|
pub(all) enum ResidentSourceResultPublicationIssue {
  Unavailable
  Output(@duckdb_native.NativeStandardRunPublicationIssue)
  Publication(@native_publication.NativeCapturedRunPublicationPreparationIssue)
}
