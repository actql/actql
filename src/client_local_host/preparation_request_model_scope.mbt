///|
// Prepaid at the Request's fixed entrance, before reading/growing a domain.
// Working-extents tuple/Ok2H1R3W; census-shape tuple/Some2H1R4W;
// units and checked cost2H0R7W; two checked sums2H0R4W;
// cached pair/Some and original selected Plan Some3H2R4W;
// conservative returned/error alternatives6H6R6W; final pair Result1H1R1W.
// One additional resident quote reference belongs to the existing Request.
// Growing the initially six-slot reservation census can briefly retain its
// two old backing arrays:2H6R6W. Holdings/delegations start empty. Prepay this
// fixed overlap too; the exact new backing is reserved by the domain grow.
// Scope/expanded census payloads are NOT in this caller-control packet.
let request_model_scope_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 2L + 2L + 2L + 2L + 3L + 6L + 1L + 2L,
  reference_slots: 1L + 1L + 2L + 6L + 1L + 1L + 6L,
  scalar_words: 3L + 4L + 7L + 4L + 4L + 6L + 1L + 6L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

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
  let scope = @publication_host.client_model_read_scope_construction_inventory()
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
