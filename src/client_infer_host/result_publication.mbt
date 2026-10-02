///|
pub(all) enum ResultPublicationIssue {
  Binding(InvocationBindingIssue)
  Transformation(@publication_host.ClientResultTransformationIssue)
  InvalidState
}

///|
/// One checked Result export retains its own Invocation and output custody.
/// It uses the existing Result transform and publication exporter; it neither
/// creates a task completion nor grants permission to commit a public Result.
pub struct ResultPublication {
  binding : InvocationBinding
  selection : @publication_host.ClientResultTransformation
  preparation : @publication_host.ClientResultTransformationPreparation
  mut exported : @publication_host.PublicationOutputExport?
  mut ready : Bool
  mut cancelled : Bool
  mut released : Bool
}

///|
/// Select only from the execution's original checked Program after common
/// observation issuance. Retain independently of the caller's binding so a
/// consumer release cannot invalidate an in-flight Store export.
pub fn start_result_publication(
  binding : InvocationBinding,
  result : Int,
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[ResultPublication, ResultPublicationIssue] {
  guard !binding.output_use.released &&
    binding.issuance is Some(issued) &&
    !issued.reclaimed &&
    invocation_binding_output(binding) is Some(completed) else {
    return Err(InvalidState)
  }
  let selection = match
    @publication_host.prepare_client_result_transformation(
      binding.output_use.owner.prepared,
      result,
      limits.schema.max_bytes,
      limits.schema.max_nodes,
      limits.schema.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Transformation(issue))
  }
  let retained = match
    bind_issued_invocation(
      binding.output_use.owner,
      issued.state.compiled,
      issued.state.definition,
      issued,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  let preparation = match
    @publication_host.start_client_result_transformation(
      selection, completed, limits,
    ) {
    Ok(value) => value
    Err(issue) => {
      release_invocation_binding(retained) |> ignore
      return Err(Transformation(issue))
    }
  }
  Ok({
    binding: retained,
    selection,
    preparation,
    exported: None,
    ready: false,
    cancelled: false,
    released: false,
  })
}

///|
pub fn result_publication_selection(
  value : ResultPublication,
) -> @publication_host.ClientResultTransformation? {
  if value.released {
    None
  } else {
    Some(value.selection)
  }
}

///|
pub fn advance_result_publication(
  value : ResultPublication,
  quantum : Int,
) -> Result[(Bool, Int), ResultPublicationIssue] {
  if value.released || value.cancelled || value.ready {
    return Err(InvalidState)
  }
  value.preparation
  .advance(quantum)
  .map(pair => {
    value.ready = pair.0
    pair
  })
  .map_err(issue => Transformation(issue))
}

///|
/// Return the existing opaque publication exporter, never raw result rows or a
/// JS-authored occurrence. Custody remains here until explicit release.
pub fn finish_result_publication(
  value : ResultPublication,
) -> Result[@publication_host.PublicationOutputExport, ResultPublicationIssue] {
  if value.released || value.cancelled || !value.ready {
    return Err(InvalidState)
  }
  if value.exported is Some(exported) {
    return Ok(exported)
  }
  value.preparation
  .finish()
  .map(exported => {
    value.exported = Some(exported)
    exported
  })
  .map_err(issue => Transformation(issue))
}

///|
/// Cancellation closes this export, not the already completed model operation
/// or another consumer. The adapter must first stop its Store reader/writer;
/// requesting cancellation alone is not permission to release shared custody.
pub fn cancel_result_publication(value : ResultPublication) -> Bool {
  if value.released || value.cancelled {
    return false
  }
  value.cancelled = true
  if value.exported is Some(exported) {
    exported.cancel()
  } else {
    value.preparation.cancel() |> ignore
  }
  true
}

///|
/// Release only after the installing owner has settled physical Store use.
/// This cleanup never re-enters preparation or invokes the model provider.
pub fn release_result_publication(value : ResultPublication) -> Bool {
  if value.released {
    return false
  }
  cancel_result_publication(value) |> ignore
  value.released = true
  value.exported = None
  release_invocation_binding(value.binding)
}
