///|
// Installed physical grants only, not a numerical profile or a new Owner.
// The installing Run funds this four-field record and Execution's reference
// before binding. Normal public installation remains unavailable until the
// complete original Ledger overlap envelope is adopted.
priv enum OriginalModelRead {
  Bound(@publication_host.ClientModelReadPreparation)
  Claimed(@publication_host.ClientModelReadConsumer)
}

///|
struct OriginalModelPreparation {
  read : OriginalModelRead
  retained_bytes : Int64
  execution_bytes : Int64
  mut startup : @model.OriginalModelStartup?
}

///|
/// Check the complete already funded read envelope, not aggregate free bytes.
/// Bootstrap funds this authentication itself. This issues no send permission
/// and supplies no physical profile coefficients.
pub fn original_model_preparation_available(
  read : @publication_host.ClientModelReadPreparation,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
) -> Bool {
  read_retained_bytes > 0L && read_execution_bytes >= 0L &&
  @publication_host.client_model_read_preparation_available(
    read, compiled, definition, plan, read_execution_bytes,
    retained_bytes=read_retained_bytes,
  )
}

///|
/// The installing original Run reserves its full read envelope before calling.
/// Check it before the existing input/Execution/preparation allocations. The
/// later Model seal has a separate envelope and transfers the same Ledger only
/// after the actual Identity/current rows scan. No new Ledger is constructed.
pub fn start_original_model_preparation(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
  limits : Limits,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  consumer : @publication_host.ClientModelReadConsumer,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[Execution, Issue] {
  if read_retained_bytes <= 0L || read_execution_bytes < 0L ||
    model_retained_bytes <= 0L || model_execution_bytes < 0L {
    return Err(Model(@model.InvalidLimits))
  }
  guard @publication_host.prepared_client_infer_execution_occurrence(prepared, step)
    is Some(occurrence) &&
    @publication_host.client_infer_occurrence_matches_compiled_run(occurrence, compiled) else {
    return Err(OriginalCapacity(@publication_host.ForeignInput))
  }
  // The Node caller claimed once before IO/closures. Enter that same opaque
  // ticket once before input/Execution allocation; aliases cannot start again.
  // A refused input start leaves responsibility with the original read owner.
  match @publication_host.enter_client_model_read_consumer(
    consumer, compiled, definition, plan, read_retained_bytes, read_execution_bytes,
  ) {
    Ok(_) => ()
    Err(issue) => return Err(OriginalCapacity(@publication_host.Read(issue)))
  }
  let active = match start(
    prepared, step, registry, values, provider,
    @publication_host.client_infer_plan_graph_request_cid(plan), limits,
    plan=Some(plan), fragment_body~, ordered_body~,
  ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // All original bindings were checked before start. Do not introduce a
  // fallible post-start bind that could drop the newly owned input on refusal.
  active.run_binding = Some({ compiled, definition, })
  active.original_preparation = Some({
    read: Claimed(consumer), retained_bytes: model_retained_bytes,
    execution_bytes: model_execution_bytes, startup: None,
  })
  Ok(active)
}

///|
/// Bind original read custody after bind_run and before any prefix progress.
/// The existing Identity path supplies actual current scope/rows to the Core
/// issuer later; this does not accept substituted rows, Ledger or token.
pub fn bind_original_model_preparation(
  active : Execution,
  read : @publication_host.ClientModelReadPreparation,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, Issue] {
  if active.reclaimed || active.cancelled || active.advancing ||
    !(active.phase is Input) || active.work != 0L ||
    !(active.source is Physical(_)) || active.original_preparation is Some(_) {
    return Err(InvalidAdvance)
  }
  if retained_bytes <= 0L || execution_bytes < 0L {
    return Err(Model(@model.InvalidLimits))
  }
  guard active.run_binding is Some(bound) && active.plan is Some(plan) &&
    @publication_host.client_model_read_available(
      read, bound.compiled, bound.definition, plan,
    ) else {
    return Err(OriginalCapacity(@publication_host.Read(@publication_host.ForeignRun)))
  }
  // This explicit existing post-bind path is not the new early-funded path.
  // No failed claim ever falls back to it.
  active.original_preparation = Some({read: Bound(read), retained_bytes, execution_bytes, startup: None})
  Ok(())
}
