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
  let graph = @strategy.captured_dag_graph(run)
  if !physical_equal(graph, selection.owner.graph) || selection.result != result {
    return Err(ForeignSelection)
  }
  guard @strategy.graph_result_task(graph, result) is Some(task) &&
    @strategy.graph_result_occurrence(graph, result) is Some(occurrence) else {
    return Err(ForeignSelection)
  }
  let ceiling = if max_pins == 0 {
    @strategy.graph_result_count(graph) + 1
  } else {
    max_pins
  }
  let borrow = match
    @strategy.borrow_captured_result_completion(run, task, occurrence, ceiling) {
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
  match start_client_result_transformation(selection, output, limits) {
    Ok(preparation) => Ok({ preparation, borrow: Some(Cells(borrow)), })
    Err(issue) => {
      @strategy.release_captured_result_borrow(borrow) |> ignore
      Err(Transform(issue))
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
  let graph = @strategy.captured_dag_graph(run)
  if !physical_equal(graph, selection.owner.graph) || selection.result != result {
    return Err(ForeignSelection)
  }
  guard @strategy.graph_result_task(graph, result) is Some(task) else {
    return Err(ForeignSelection)
  }
  let ceiling = if max_pins == 0 {
    @strategy.graph_result_count(graph) + 1
  } else {
    max_pins
  }
  let borrow = match
    @strategy.borrow_captured_any_result_output(
      run,
      task,
      selection.occurrence,
      ceiling,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Retain(issue))
  }
  if !@strategy.captured_any_result_borrow_matches_managed(borrow, managed) {
    @strategy.release_captured_any_result_borrow(borrow) |> ignore
    return Err(ForeignSelection)
  }
  let preparation = match
    start_client_result_transformation(selection, output, limits) {
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
      selection.occurrence,
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
