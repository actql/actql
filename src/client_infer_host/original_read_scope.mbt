///|
// Use the same admitted ceilings before read as before ordinary Model startup.
// These are existing contract bounds, not another physical byte profile.
fn original_model_ledger_limits(
  plan : @publication_host.ClientInferPlanGraph,
  limits : @model.ModelExecutionLimits,
) -> @resources.LedgerLimits {
  let execution = @publication_host.client_infer_plan_graph_execution_contract(
    plan,
  )
  let ledger = limits.ledger
  {
    ..ledger,
    attempts: Int64::min(
      ledger.attempts.to_int64(),
      @environment.model_execution_ceiling(
        execution,
        @environment.TotalAttempts,
      ),
    ).to_int(),
    transfer_bytes: Int64::min(
      ledger.transfer_bytes,
      @environment.model_execution_ceiling(
        execution,
        @environment.TotalWireBytes,
      ),
    ),
  }
}

///|
/// Move the original Model Ledger initialization before its read children.
/// Return only the existing opaque checked-Run scope, never a Ledger/token.
/// The trusted installation must already cover initialization and supply the
/// reviewed bootstrap/control envelope. Positive numbers alone do not justify
/// a physical layout, public installation, authority or a Model send.
pub fn begin_original_model_read_scope(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  limits : @model.ModelExecutionLimits,
  quantity_capacity : @model.ModelQuantityCapacity?,
  bootstrap_retained_bytes : Int64,
  bootstrap_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[@publication_host.ClientModelReadScope, Issue] {
  let quantities = match quantity_capacity {
    None => None
    Some(installed) =>
      match original_model_quantity_capacity(plan, installed) {
        Ok(capacity) => Some(capacity)
        Err(issue) => return Err(issue)
      }
  }
  let ledger = match
    @resources.create_ledger(original_model_ledger_limits(plan, limits)) {
    Ok(value) => value
    Err(issue) => return Err(Model(@model.Ledger(issue)))
  }
  // Configure once, before even the bootstrap reservation advances its serial.
  // start_original_model_execution later compares this exact configuration;
  // it cannot refill, reset or infer quantities from the byte envelope.
  if quantities is Some(capacity) {
    match @resources.configure_quantities(ledger, capacity.limits) {
      Ok(_) => ()
      Err(issue) => return Err(Model(@model.Ledger(issue)))
    }
  }
  let bootstrap = match
    @resources.reserve_capacity(
      ledger, bootstrap_retained_bytes, bootstrap_execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Model(@model.Ledger(issue)))
  }
  match
    @publication_host.begin_client_model_read_scope(
      compiled, definition, plan, ledger, bootstrap, max_reservations, max_holdings,
      max_delegations,
    ) {
    Ok(scope) => Ok(scope)
    Err(issue) =>
      // This synchronous refusal has issued no scope, descriptor, child or IO.
      // The exact local reservation cannot escape or be mutated by callbacks.
      match @resources.settle_capacity(ledger, bootstrap) {
        Ok(_) => Err(OriginalCapacity(@publication_host.Read(issue)))
        Err(cleanup_issue) => Err(Model(@model.Ledger(cleanup_issue)))
      }
  }
}
