///|
// The same ordinary selection used by execution. These are finite bounds DATA,
// not numerical physical coefficients, an operational issuer or a byte loan.
fn select_infer_execution_limits(
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph?,
  limits : Limits,
  physical : Bool,
) -> Result[Limits, Issue] {
  let (ceiling, request_ceiling) = match
    @publication_host.client_infer_occurrence_host_ceilings(occurrence) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  if limits.model.max_items < 0 || limits.model.max_request_bytes < 0L {
    return Err(Model(@model.InvalidLimits))
  }
  let limits = {
    ..limits,
    model: {
      ..limits.model,
      max_items: Int64::min(ceiling, limits.model.max_items.to_int64()).to_int(),
      max_request_bytes: Int64::min(
        request_ceiling,
        limits.model.max_request_bytes,
      ),
    },
  }
  Ok(
    if physical && plan is Some(graph) {
      {
        ..limits,
        model: {
          ..limits.model,
          ledger: original_model_ledger_limits(graph, limits.model),
        },
      }
    } else {
      limits
    },
  )
}

///|
/// Read the selected consumer's input/Model/output bounds before a Run exists.
/// These are the same checked occurrence/Plan DATA used by execution, not a
/// resource grant or an authorization. The caller funds this selection and
/// retains its original result before allocating the complete physical frame.
pub fn prepared_composed_bounds(
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
) -> Result[Limits, Issue] {
  if !@publication_host.client_infer_occurrence_matches_plan(occurrence, plan) {
    return Err(OriginalCapacity(@publication_host.ForeignInput))
  }
  select_infer_execution_limits(occurrence, Some(plan), standard_limits(), true)
}

///|
/// Bind that same prepared occurrence/Plan to the actual original Run later.
/// No bounds selection, Ledger/Scope, provider, current callback or resource
/// quote is repeated here. Current authority remains at its existing owner.
pub fn check_original_composed_preparation(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
) -> Result[Unit, Issue] {
  if !@publication_host.client_infer_occurrence_matches_compiled_run(
      occurrence, compiled,
    ) ||
    !@publication_host.client_infer_occurrence_matches_plan(occurrence, plan) {
    return Err(OriginalCapacity(@publication_host.ForeignInput))
  }
  match
    @publication_host.check_client_compiled_run_definition(compiled, definition) {
    Err(_) =>
      return Err(
        OriginalCapacity(@publication_host.Read(@publication_host.ForeignRun)),
      )
    Ok(_) => ()
  }
  Ok(())
}
