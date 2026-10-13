///|
// Necessary live-custody facts of the same Row physical Owner, not a new
// capacity grant, caller Bool, upper-bound proof or Source authorization.
// No token leaves this package. Its listing reservation is issued before
// allocation and only this Owner may settle it after actual retirement.
// A future funded receiver handoff must be checked here explicitly; a closed
// or pending source token cannot silently borrow the old execution allowance.
fn row_listing_encoding_reservation_live(physical : RowPhysical) -> Bool {
  @resources.reservation_open(physical.reservation) &&
  !@resources.reservation_pending(physical.reservation)
}
