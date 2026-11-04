///|
// This SAME Request has only its initial six borrower slots before its one
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
    guard @publication_host.client_model_read_scopes_construction_inventory(
        model_count,
      )
      is Some(group) &&
      @execution.preparation_array_representation(
        2L,
        2L * model_count.to_int64(),
        true,
      )
      is Some(partitions) &&
      @execution.compose_preparation_representation([group, partitions])
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
