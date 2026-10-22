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
/// Read the selected fixed consumer's complete input/Model/output bounds from
/// its same checked occurrence, graph and admitted Run definition. The actual
/// Host still supplies currentness and the entire before-work physical overlap;
/// no read/Model/publication byte projection or permission is inferred here.
pub fn original_composed_bounds(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
) -> Result[Limits, Issue] {
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
  select_infer_execution_limits(occurrence, Some(plan), standard_limits(), true)
}
