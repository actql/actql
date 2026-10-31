///|
/// Owned census representation, including builtin linked Map construction and
/// growth, not byte prices or an allocation grant. The same consumer applies
/// the existing common tariff once before construction/growth. Keys only index
/// original tokens; live holding counts and scalar issuance order are DATA.
pub fn preparation_inventory_initial_control_slots(
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> (Int64, Int64, Int64)? {
  if max_reservations < 0 ||
    max_holdings < 0 ||
    max_delegations < 0 ||
    max_holdings > 2147483647 - max_reservations ||
    max_delegations > 2147483647 - max_reservations - max_holdings {
    return None
  }
  let slots = max_reservations.to_int64() +
    max_holdings.to_int64() +
    max_delegations.to_int64()
  // Inventory1H7R8W, identity1H2R, three slot records3H6R3W,
  // ledger Some and returned identity Ok2H2R2W. Three scalar order arrays;
  // three original-token Maps and one count Map with <=max_holdings entries.
  guard @shape.collection_construction_extent({
      records: 7L,
      record_references: 17L,
      record_words: 13L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 3L,
      scalar_items: slots,
      maps: 4L,
      map_entries: slots + max_holdings.to_int64(),
    })
    is Some(body) else {
    return None
  }
  // any/all holds one borrowed Map values iterator and one next result at a
  // time. The existing generic pair recipe is an upper bound for value-only
  // iteration. No iterator or ordinal cache survives an owning clear.
  let iterator = @shape.reference_map_iterator_construction_extent()
  let next = @shape.reference_map_iterator_next_construction_extent()
  Some(
    (
      body.record_headers + iterator.record_headers + next.record_headers,
      body.reference_slots + iterator.reference_slots + next.reference_slots,
      body.scalar_words + iterator.scalar_words + next.scalar_words,
    ),
  )
}

///|
/// Atomic first reservation/census entrance on the SAME already admitted
/// Ledger. The fixed caller funds these controls and the actual borrower/IO
/// slots before entry. Current is observed once, then pristine history and
/// the existing allocator are used without another external callback.
pub fn[I, P] reserve_preparation_capacity_inventory(
  ledger : Ledger,
  input : I,
  retained_peak : Int64,
  execution_peak : Int64,
  max_borrowers~ : Int,
) -> Result[PreparationCapacity[I, P], PreparationCapacityIssue] {
  if max_borrowers < 1 || retained_peak <= 0L || execution_peak < 0L {
    return Err(InvalidExtent)
  }
  match check_original_reservation_slot(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if ledger.original_inventory is Some(_) ||
    ledger.next_capacity_serial != Some(-1) ||
    ledger.next_attempt_serial != Some(0) ||
    ledger.next_holding_serial != Some(0) ||
    !original_ledger_has_no_child_usage(ledger, 0L, 0L) ||
    (ledger.imported_child is Some(origin) && origin.fixed_capacities) {
    return Err(Resource(InvalidCharge))
  }
  let reservation = match
    reserve_capacity_current(ledger, retained_peak, execution_peak) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let owner : PreparationCapacity[I, P] = make_preparation_capacity(
    ledger, input, reservation, max_borrowers,
  )
  match
    begin_preparation_capacity_inventory(owner, input, max_borrowers, 0, 0) {
    Ok(_) => Ok(owner)
    Err(issue) => {
      // All constructor checks were validated in the same callback-free cut.
      // On an initialization refusal, no physical operation or body exists.
      // Retire the actual token, without resetting its consumed serial.
      match settle_reservation_current(ledger, reservation.reservation) {
        Err(error) => return Err(Resource(error))
        Ok(_) => ()
      }
      match issue {
        Resource(error) => Err(Resource(error))
        _ => Err(Resource(InvalidCharge))
      }
    }
  }
}

///|
/// Read the SAME original census identity through its actual preparation
/// capacity, without another wrapper, current callback or mutable Ledger.
/// This DATA projection works before Model execution funding; binding and
/// read issuance retain their own actual funded/current prerequisites.
pub fn[I, P] preparation_capacity_inventory_original(
  owner : PreparationCapacity[I, P],
  input : I,
) -> Result[OriginalLedgerIdentity, PreparationCapacityIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if !(preparation_capacity_phase_is_working(owner.phase) ||
    owner.phase == Ready ||
    owner.phase == Run) {
    return Err(Retired)
  }
  guard owner.ledger.original_inventory is Some(value) &&
    physical_equal(value.bootstrap, owner.reservation) &&
    original_inventory_preparation_owned(value) &&
    !value.closing &&
    capacity_reservation_open(value.bootstrap) else {
    return Err(Retired)
  }
  Ok(value.identity)
}

///|
/// Retire only unused preparation-census metadata after the fixed consumer's
/// actual typed non-Model constructor has proved that no Scope is needed.
/// No byte/token/work/quantity is returned or reset. Absence is idempotent
/// metadata cleanup, never a successful Plan or admission. Other bootstrap
/// owners remain untouched. A bound/issued or live-child census cannot leave.
pub fn[I, P] discard_unbound_preparation_capacity_inventory(
  owner : PreparationCapacity[I, P],
  input : I,
) -> Result[Unit, PreparationCapacityIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  guard owner.ledger.original_inventory is Some(value) else { return Ok(()) }
  if !physical_equal(value.bootstrap, owner.reservation) ||
    !original_inventory_preparation_owned(value) {
    return Ok(())
  }
  if !original_inventory_preparation_unbound(value) ||
    value.closing ||
    value.descriptor_issued ||
    value.read_claimed ||
    value.park is Some(_) ||
    !value.reservations.is_empty() ||
    !value.holdings.is_empty() ||
    !value.delegations.is_empty() ||
    owner.active_phase_work is Some(_) ||
    !(owner.phase == Ready || preparation_capacity_phase_is_working(owner.phase)) {
    return Err(WorkActive)
  }
  value.reservations.clear()
  value.reservations.shrink_to_fit()
  value.holdings.clear()
  value.holdings.shrink_to_fit()
  value.delegations.clear()
  value.delegations.shrink_to_fit()
  value.holding_counts.clear()
  value.holding_counts = Map([])
  owner.ledger.original_inventory = None
  Ok(())
}
