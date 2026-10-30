///|
/// Owned initial census representation: headers/reference slots/scalar words,
/// not byte prices or an allocation grant. Resource owns these record/array
/// shapes; its fixed consumer applies the existing common tariff once.
/// Arrays reserve the supplied finite slot backing before use. Every live
/// slot includes its Some, reference backing and scalar issuance-order slot.
/// The returned DATA may be retained in the installed baseline before entry.
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
  // Inventory1H6R8W (including original attempt offset), identity1H2R,
  // three slot records3H6R,
  // six array headers6H, ledger Some and returned identity Ok2H2R2W.
  // Each possible live entry adds Some1H1R1W + backing1R + order1W.
  Some((13L + slots, 16L + 2L * slots, 10L + 2L * slots))
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
  owner.ledger.original_inventory = None
  Ok(())
}
