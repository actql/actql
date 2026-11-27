///|
/// Size only the source-free VM Model census on its retained Local module.
/// Physical reservations are bounded by the original combined attempt limits.
/// A settled reservation may still be indexed by a live holding. Count that
/// separately, then the synchronous byte-only owners: the existing Request
/// slots, Run setup/publication, and each Model Read, startup, proof and output
/// projection. Raw and outcome publication may overlap on each selected Call.
/// This VM route has no process delegations. The ordinary default caller's
/// selected inventory and all original execution ceilings remain independent.
pub fn portable_model_scope_inventory(
  original : ClientInstalledManagedSourceFreePreparation,
  model_attempts : Int64,
  model_holdings : Int64,
) -> (Int, Int, Int)? {
  guard original.owner is Pure(_) &&
    original.configuration is Some(_) &&
    original.compilation is Some(@publication_host.Tasks(compilation)) &&
    !compilation.infers.is_empty() else {
    return None
  }
  portable_model_scope_inventory_from_limits(
    original.limits,
    compilation.infers.length(),
    model_attempts,
    model_holdings,
  )
}

///|
/// The same Portable physical recipe for a module that owns a Whole Source.
pub fn portable_file_model_scope_inventory(
  original : ClientInstalledManagedCapturePlan,
  model_attempts : Int64,
  model_holdings : Int64,
) -> (Int, Int, Int)? {
  guard original.whole_sources.length() == 1 &&
    original.compilation is Some(@publication_host.Tasks(compilation)) &&
    compilation.infers.length() == 1 else {
    return None
  }
  portable_model_scope_inventory_from_limits(
    original.limits,
    1,
    model_attempts,
    model_holdings,
  )
}

///|
fn portable_model_scope_inventory_from_limits(
  limits : @resources.LedgerLimits,
  model_count : Int,
  model_attempts : Int64,
  model_holdings : Int64,
) -> (Int, Int, Int)? {
  let max = 2147483647L
  guard model_attempts >= 0L &&
    model_attempts <= max &&
    model_holdings >= 0L &&
    model_holdings <= max else {
    return None
  }
  let holdings = limits.holdings.to_int64() + model_holdings
  let attempts = limits.attempts.to_int64() + model_attempts
  let request = request_preparation_borrow_limit.to_int64()
  let run = 2L
  let component = 4L * model_count.to_int64()
  let call = 2L * model_attempts
  let reservations = request + run + component + call + attempts + holdings
  if reservations > max || holdings > max - reservations {
    None
  } else {
    Some((reservations.to_int(), holdings.to_int(), 0))
  }
}

///|
// This SAME Request retains its original admission census before its one
// Model binding. Pure/Effect are closed, exclusive body choices. Resource owns
// slot shapes; the Model Owner supplies its actual retained-record inventory.
// Runtime body/operation allowances are not construction costs or spare credit.
fn[I, P] request_model_scope_construction_quote(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  model_count? : Int = 1,
  retain_model_limits? : Bool = false,
) -> Result[(Int64, Int64), ClientInstalledManagedRunIssue] {
  let selected = match
    @resources.preparation_inventory_initial_control_slots(
      Int::max(request_preparation_borrow_limit, max_reservations),
      max_holdings,
      max_delegations,
    ) {
    None => return Err(InsufficientCapacity)
    Some(value) => value
  }
  let initial = request_preparation_inventory_slots
  let scope = if model_count == 1 {
    @publication_host.client_model_read_scope_construction_inventory()
  } else {
    // Pure group binding projects the original per-Graph Model limits as a
    // third array. Each read origin retains its own optional limits reference.
    let arrays = if retain_model_limits { 3L } else { 2L }
    let options = if retain_model_limits {
      model_count.to_int64() + 1L
    } else {
      0L
    }
    guard @publication_host.client_model_read_scopes_construction_inventory(
        model_count,
      )
      is Some(group) &&
      @execution.preparation_array_representation(
        arrays,
        arrays * model_count.to_int64(),
        true,
      )
      is Some(partitions) &&
      @execution.compose_preparation_representation([
        group,
        partitions,
        {
          record_headers: options,
          reference_slots: options,
          scalar_words: options,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        },
      ])
      is Some(units) else {
      return Err(InsufficientCapacity)
    }
    units
  }
  let bytes = match
    @execution.preparation_representation_cost({
      record_headers: scope.record_headers + selected.0 - initial.0,
      reference_slots: scope.reference_slots + selected.1 - initial.1,
      scalar_words: scope.scalar_words + selected.2 - initial.2,
      owned_utf16_units: scope.owned_utf16_units,
      owned_wire_bytes: scope.owned_wire_bytes,
    }) {
    None => return Err(InsufficientCapacity)
    Some(value) => value
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(InsufficientCapacity)
  }
  Ok((r, e))
}
