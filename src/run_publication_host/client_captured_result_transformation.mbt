///|
/// The Result borrow stays with this preparation until cancellation or its
/// transfer to the finished publication export. It is not a new Run owner.
pub struct CapturedClientResultTransformation {
  preparation : ClientResultTransformationPreparation
  mut borrow : PublicationResultRetention?
}

///|
pub(all) enum CapturedClientResultTransformationIssue {
  ForeignSelection
  InvalidState
  Retain(@strategy.RunIssue)
  Transform(ClientResultTransformationIssue)
}

///|
/// A supplied Source input gives the same checked Program a physical graph
/// view. The logical Result selection follows its original occurrence; it
/// does not require that view to be the original graph allocation. The live
/// Run, completion and bridge still pass their existing export checks below.
fn captured_client_result_selection_matches(
  selection : ClientResultTransformation,
  run : @strategy.CapturedDAG,
  result : Int,
) -> Bool {
  let graph = @strategy.captured_dag_graph(run)
  guard selection.result == result &&
    physical_equal(
      @strategy.graph_program(graph),
      @strategy.graph_program(selection.owner.graph),
    ) &&
    @strategy.graph_result_occurrence(graph, result) is Some(occurrence) else {
    return false
  }
  physical_equal(occurrence, selection.occurrence)
}

///|
pub fn start_captured_client_result_transformation(
  selection : ClientResultTransformation,
  run : @strategy.CapturedDAG,
  result : Int,
  limits : PublicationOutputExportLimits,
  converted_output? : @execution.CompletedOutput,
  max_pins? : Int = 0,
) -> Result[
  CapturedClientResultTransformation,
  CapturedClientResultTransformationIssue,
] {
  if !captured_client_result_selection_matches(selection, run, result) {
    return Err(ForeignSelection)
  }
  start_captured_result_publication_export(
    run,
    result,
    limits,
    converted_output?,
    max_pins~,
  )
}

///|
fn captured_result_publication_binding(
  run : @strategy.CapturedDAG,
  result : Int,
) -> Result[
  (Int, @execution.ManagedResultOccurrence, @publication.PublicationContract),
  CapturedClientResultTransformationIssue,
] {
  let graph = @strategy.captured_dag_graph(run)
  guard @strategy.graph_result_task(graph, result) is Some(task) &&
    @strategy.graph_result_occurrence(graph, result) is Some(occurrence) &&
    @strategy.graph_result_name(graph, result) is Some(name) else {
    return Err(ForeignSelection)
  }
  match
    @publication.prepare_result_definition(
      @strategy.graph_program_definition_cid(graph),
      name,
    ) {
    Ok(value) =>
      Ok((task, occurrence, @publication.result_definition_contract(value)))
    Err(_) => Err(ForeignSelection)
  }
}

///|
/// Acquire the exact checked Result pin before starting bounded preparation.
/// Source and cell representations use their existing export owner; a retained
/// managed representation must instead provide its exact re-admission bridge.
pub fn start_captured_result_publication_export(
  run : @strategy.CapturedDAG,
  result : Int,
  limits : PublicationOutputExportLimits,
  converted_output? : @execution.CompletedOutput,
  max_pins? : Int = 0,
) -> Result[
  CapturedClientResultTransformation,
  CapturedClientResultTransformationIssue,
] {
  let (task, occurrence, definition) = match
    captured_result_publication_binding(run, result) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let graph = @strategy.captured_dag_graph(run)
  let ceiling = if max_pins == 0 {
    @strategy.graph_result_count(graph) + 1
  } else {
    max_pins
  }
  if task < @strategy.captured_compute_first_task(run) {
    if converted_output is Some(_) {
      return Err(ForeignSelection)
    }
    let borrow = match
      @strategy.borrow_captured_any_result_output(
        run, task, occurrence, ceiling,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Retain(issue))
    }
    match
      @strategy.start_captured_any_result_borrow_export(
        borrow,
        {
          max_fields: limits.max_result_fields,
          max_mapping_work: limits.max_result_mapping_work,
          max_order_work: limits.max_result_order_work,
          max_workspace_entries: limits.max_result_workspace_entries,
        },
        limits.max_rows,
        limits.values,
        limits.payload_wire,
        limits.logical_wire,
        limits.schema,
        limits.max_batch_bytes,
      ) {
      Ok(preparation) =>
        Ok({
          preparation: { occurrence, definition, preparation, limits, },
          borrow: Some(Any(borrow)),
        })
      Err(issue) => {
        @strategy.release_captured_any_result_borrow(borrow) |> ignore
        Err(Transform(Output(issue)))
      }
    }
  } else {
    let borrow = match
      @strategy.borrow_captured_result_completion(
        run, task, occurrence, ceiling,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Retain(issue))
    }
    let materialized = @strategy.captured_result_borrow_output(borrow)
    let output = match converted_output {
      None => materialized
      Some(converted) => {
        if !@execution.completed_output_same_occurrence(materialized, converted) {
          @strategy.release_captured_result_borrow(borrow) |> ignore
          return Err(ForeignSelection)
        }
        converted
      }
    }
    match
      start_result_publication_export(output, occurrence, definition, limits) {
      Ok(preparation) => Ok({ preparation, borrow: Some(Cells(borrow)), })
      Err(issue) => {
        @strategy.release_captured_result_borrow(borrow) |> ignore
        Err(Transform(issue))
      }
    }
  }
}

///|
/// Managed rows must come from this live completion's re-admission bridge.
/// Matching a schema, row CID, or checked occurrence alone is insufficient.
pub fn[T] start_captured_managed_result_transformation(
  selection : ClientResultTransformation,
  run : @strategy.CapturedDAG,
  result : Int,
  managed : @execution.ManagedCompletedOutput[T],
  bridge : @execution.ManagedPublicationBridge[T],
  output : @execution.CompletedOutput,
  limits : PublicationOutputExportLimits,
  max_pins? : Int = 0,
) -> Result[
  CapturedClientResultTransformation,
  CapturedClientResultTransformationIssue,
] {
  if !captured_client_result_selection_matches(selection, run, result) {
    return Err(ForeignSelection)
  }
  start_captured_managed_result_publication_export(
    run,
    result,
    managed,
    bridge,
    output,
    limits,
    max_pins~,
  )
}

///|
/// Without an extra Client selection, managed publication must still retain
/// this Run's exact Result and verify the live bridge's completed generation.
pub fn[T] start_captured_managed_result_publication_export(
  run : @strategy.CapturedDAG,
  result : Int,
  managed : @execution.ManagedCompletedOutput[T],
  bridge : @execution.ManagedPublicationBridge[T],
  output : @execution.CompletedOutput,
  limits : PublicationOutputExportLimits,
  max_pins? : Int = 0,
) -> Result[
  CapturedClientResultTransformation,
  CapturedClientResultTransformationIssue,
] {
  let (task, occurrence, definition) = match
    captured_result_publication_binding(run, result) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let graph = @strategy.captured_dag_graph(run)
  let ceiling = if max_pins == 0 {
    @strategy.graph_result_count(graph) + 1
  } else {
    max_pins
  }
  let borrow = match
    @strategy.borrow_captured_any_result_output(run, task, occurrence, ceiling) {
    Ok(value) => value
    Err(issue) => return Err(Retain(issue))
  }
  if !@strategy.captured_any_result_borrow_matches_managed(borrow, managed) {
    @strategy.release_captured_any_result_borrow(borrow) |> ignore
    return Err(ForeignSelection)
  }
  let preparation = match
    start_result_publication_export(output, occurrence, definition, limits) {
    Ok(value) => value
    Err(issue) => {
      @strategy.release_captured_any_result_borrow(borrow) |> ignore
      return Err(Transform(issue))
    }
  }
  if !@execution.managed_publication_bridge_matches_result_export(
      bridge,
      managed,
      preparation.preparation,
      occurrence,
    ) {
    preparation.cancel() |> ignore
    @strategy.release_captured_any_result_borrow(borrow) |> ignore
    return Err(ForeignSelection)
  }
  Ok({ preparation, borrow: Some(Any(borrow)), })
}

///|
pub fn CapturedClientResultTransformation::advance(
  self : CapturedClientResultTransformation,
  quantum : Int,
) -> Result[(Bool, Int), CapturedClientResultTransformationIssue] {
  if self.borrow is None {
    return Err(InvalidState)
  }
  self.preparation.advance(quantum).map_err(issue => Transform(issue))
}

///|
pub fn CapturedClientResultTransformation::finish(
  self : CapturedClientResultTransformation,
) -> Result[PublicationOutputExport, CapturedClientResultTransformationIssue] {
  guard self.borrow is Some(borrow) else { return Err(InvalidState) }
  match self.preparation.finish() {
    Ok(exported) => {
      exported.retained = Some(borrow)
      self.borrow = None
      Ok(exported)
    }
    Err(issue) => Err(Transform(issue))
  }
}

///|
pub fn CapturedClientResultTransformation::cancel(
  self : CapturedClientResultTransformation,
) -> Unit {
  if self.borrow is Some(borrow) {
    self.preparation.cancel() |> ignore
    match borrow {
      Cells(borrow) =>
        @strategy.release_captured_result_borrow(borrow) |> ignore
      Any(borrow) =>
        @strategy.release_captured_any_result_borrow(borrow) |> ignore
    }
    self.borrow = None
  }
}
