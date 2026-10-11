///|
// Installed physical grants only, not a numerical profile or a new Owner.
// The installing Run funds this four-field record and Execution's reference
// before binding. Normal public installation remains unavailable until the
// complete original Ledger overlap envelope is adopted.
struct OriginalModelPreparation {
  read : @publication_host.ClientModelReadPreparation
  retained_bytes : Int64
  execution_bytes : Int64
  mut startup : @model.OriginalModelStartup?
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
  active.original_preparation = Some({read, retained_bytes, execution_bytes, startup: None})
  Ok(())
}
