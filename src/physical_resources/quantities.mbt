///|
/// Physical usage units reserved by the same attempt owner as bytes and pins.
/// These are capacity, not model permission or logical computation work.
pub(all) struct QuantityAmounts {
  tokens : Int64
  cost_units : Int64
  duration_ms : Int64
} derive(Eq, Debug)

///|
pub(all) struct QuantityUsage {
  reserved : QuantityAmounts
  uncertain : QuantityAmounts
  consumed : QuantityAmounts
} derive(Eq, Debug)

///|
fn zero_quantities() -> QuantityAmounts {
  { tokens: 0L, cost_units: 0L, duration_ms: 0L, }
}

///|
fn valid_quantities(value : QuantityAmounts) -> Bool {
  value.tokens >= 0L && value.cost_units >= 0L && value.duration_ms >= 0L
}

///|
fn add_quantities(a : QuantityAmounts, b : QuantityAmounts) -> QuantityAmounts {
  {
    tokens: a.tokens + b.tokens,
    cost_units: a.cost_units + b.cost_units,
    duration_ms: a.duration_ms + b.duration_ms,
  }
}

///|
fn subtract_quantities(
  a : QuantityAmounts,
  b : QuantityAmounts,
) -> QuantityAmounts {
  {
    tokens: a.tokens - b.tokens,
    cost_units: a.cost_units - b.cost_units,
    duration_ms: a.duration_ms - b.duration_ms,
  }
}

///|
/// Install exactly once before Model/read/delegation. Standalone Ledgers keep
/// their pristine entrance. An original preparation may retain settled input
/// IO/work, proved by its early private census, never raw token history. The
/// fixed caller supplies its actual selected limits and backs the installation
/// frame before entry; byte headroom is not a quantity grant. An installed
/// budget still cannot be bypassed by a byte-only reservation.
pub fn configure_quantities(
  ledger : Ledger,
  limits : QuantityAmounts,
) -> Result[Unit, LedgerIssue] {
  match check_original_resources_mutable(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !valid_quantities(limits) {
    return Err(InvalidLimits)
  }
  if ledger.quantity_limits is Some(_) || ledger.delegated_attempts != 0 {
    return Err(InvalidCharge)
  }
  if ledger.next_attempt_serial != Some(0) ||
    ledger.next_capacity_serial != Some(-1) {
    guard ledger.original_inventory is Some(value) &&
      value.binding == PreparationUnbound &&
      original_preparation_input_closed(value) else {
      return Err(InvalidCharge)
    }
  }
  ledger.quantity_limits = Some(limits)
  Ok(())
}

///|
pub fn quantity_usage(ledger : Ledger) -> QuantityUsage {
  ledger.quantity_usage
}

///|
// Read-only installation consistency for an already configured original
// Ledger. This configures nothing and grants no remaining quantity capacity.
pub fn quantity_configuration_matches(
  ledger : Ledger,
  limits : QuantityAmounts?,
) -> Bool {
  ledger.quantity_limits == limits
}

///|
// A sealed shared owner can carry several component ceilings on this SAME
// configured Ledger. This compares immutable configuration only; every real
// reservation still checks aggregate consumed/uncertain/reserved quantities.
// It creates no allowance, issuer, reset or remaining-capacity observation.
pub fn quantity_configuration_covers(
  ledger : Ledger,
  limits : QuantityAmounts?,
) -> Bool {
  match (ledger.quantity_limits, limits) {
    (None, None) => true
    (Some(parent), Some(component)) =>
      valid_quantities(component) &&
      parent.tokens >= component.tokens &&
      parent.cost_units >= component.cost_units &&
      parent.duration_ms >= component.duration_ms
    _ => false
  }
}

///|
/// DATA for an already selected operation that consumes no Model quantities.
/// Source/input/serialization owners still reserve their actual attempts,
/// transfer and bytes on this SAME Ledger. This is not a reservation, proof
/// of non-Model work or permission to replace a Model's actual quantity quote.
/// The ordinary reservation rechecks current configuration and all limits.
pub fn quantity_neutral_amounts(ledger : Ledger) -> QuantityAmounts? {
  match ledger.quantity_limits {
    None => None
    Some(_) => no_model_quantity_amounts
  }
}

///|
// Fixed immutable module DATA, not a remembered admission. Every reservation
// already owns its optional amount reference; neutral Source children borrow
// this same value rather than allocate a new Some/amount at each constructor.
let no_model_quantity_amounts : QuantityAmounts? = Some(zero_quantities())

///|
fn check_quantity_reservation(
  ledger : Ledger,
  amount : QuantityAmounts?,
) -> Result[Unit, LedgerIssue] {
  match (ledger.quantity_limits, amount) {
    (None, None) => Ok(())
    (Some(limits), Some(amount)) => {
      if !valid_quantities(amount) {
        return Err(InvalidCharge)
      }
      let usage = ledger.quantity_usage
      // Subtraction avoids overflowing the checked aggregate. An observed
      // provider overrun leaves a negative remainder and rejects later work.
      if !quantity_fits(
          limits.tokens,
          usage.consumed.tokens,
          usage.uncertain.tokens,
          usage.reserved.tokens,
          amount.tokens,
        ) {
        return Err(TokenLimit)
      }
      if !quantity_fits(
          limits.cost_units,
          usage.consumed.cost_units,
          usage.uncertain.cost_units,
          usage.reserved.cost_units,
          amount.cost_units,
        ) {
        return Err(CostLimit)
      }
      if !quantity_fits(
          limits.duration_ms,
          usage.consumed.duration_ms,
          usage.uncertain.duration_ms,
          usage.reserved.duration_ms,
          amount.duration_ms,
        ) {
        return Err(DurationLimit)
      }
      Ok(())
    }
    _ => Err(InvalidCharge)
  }
}

///|
fn quantity_fits(
  limit : Int64,
  consumed : Int64,
  uncertain : Int64,
  reserved : Int64,
  amount : Int64,
) -> Bool {
  if consumed > limit {
    return false
  }
  let after_consumed = limit - consumed
  if uncertain > after_consumed {
    return false
  }
  let after_uncertain = after_consumed - uncertain
  if reserved > after_uncertain {
    return false
  }
  amount <= after_uncertain - reserved
}

///|
/// Crossing physical I/O retains the full unknown envelope. Cleanup releases
/// only undispatched quantities; unknown usage does not become fictitious zero.
pub fn mark_quantities_uncertain(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard reservation.quantities is Some(amount) &&
    reservation.uncertain_quantities is None else {
    return Err(InvalidCharge)
  }
  match consume_reserved_attempt_current(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let usage = ledger.quantity_usage
  ledger.quantity_usage = {
    ..usage,
    reserved: subtract_quantities(usage.reserved, amount),
    uncertain: add_quantities(usage.uncertain, amount),
  }
  reservation.quantities = None
  reservation.uncertain_quantities = Some(amount)
  Ok(())
}

///|
/// Accept one actual observation per unit. NULL leaves its dispatched envelope
/// uncertain. Even an overrun is recorded before returning the typed failure;
/// a provider cannot erase consumption by exceeding an admitted reservation.
pub fn observe_quantities(
  ledger : Ledger,
  reservation : Reservation,
  tokens? : Int64? = None,
  cost_units? : Int64? = None,
  duration_ms? : Int64? = None,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard reservation.uncertain_quantities is Some(envelope) else {
    return Err(InvalidCharge)
  }
  let (seen_tokens, seen_cost, seen_duration) = reservation.observed_quantities
  for
    (value, seen) in [
      (tokens, seen_tokens),
      (cost_units, seen_cost),
      (duration_ms, seen_duration),
    ] {
    if value is Some(value) && (value < 0L || seen) {
      return Err(InvalidCharge)
    }
  }
  let usage = ledger.quantity_usage
  let observed : QuantityAmounts = {
    tokens: tokens.unwrap_or(0L),
    cost_units: cost_units.unwrap_or(0L),
    duration_ms: duration_ms.unwrap_or(0L),
  }
  let released : QuantityAmounts = {
    tokens: if tokens is Some(_) {
      envelope.tokens
    } else {
      0L
    },
    cost_units: if cost_units is Some(_) {
      envelope.cost_units
    } else {
      0L
    },
    duration_ms: if duration_ms is Some(_) {
      envelope.duration_ms
    } else {
      0L
    },
  }
  if observed.tokens > 9223372036854775807L - usage.consumed.tokens ||
    observed.cost_units > 9223372036854775807L - usage.consumed.cost_units ||
    observed.duration_ms > 9223372036854775807L - usage.consumed.duration_ms {
    return Err(InvalidCharge)
  }
  ledger.quantity_usage = {
    ..usage,
    consumed: add_quantities(usage.consumed, observed),
    uncertain: subtract_quantities(usage.uncertain, released),
  }
  reservation.uncertain_quantities = Some(
    subtract_quantities(envelope, released),
  )
  reservation.observed_quantities = (
    seen_tokens || tokens is Some(_),
    seen_cost || cost_units is Some(_),
    seen_duration || duration_ms is Some(_),
  )
  if observed.tokens > released.tokens {
    return Err(TokenLimit)
  }
  if observed.cost_units > released.cost_units {
    return Err(CostLimit)
  }
  if observed.duration_ms > released.duration_ms {
    return Err(DurationLimit)
  }
  Ok(())
}

///|
/// Read existing original-token quantity state, including settled uncertain
/// usage. Observed amounts stay in the consuming owner's original trace.
/// This does not call current, observe usage, mutate or grant capacity. The
/// caller funds its bounded inventory scan and borrowed result frame.
pub fn reservation_quantity_state(
  ledger : Ledger,
  reservation : Reservation,
) -> Result[
  (QuantityAmounts?, QuantityAmounts?, (Bool, Bool, Bool)),
  LedgerIssue,
] {
  if !physical_equal(ledger, reservation.owner) {
    return Err(ForeignOwner)
  }
  Ok(
    (
      reservation.quantities,
      reservation.uncertain_quantities,
      reservation.observed_quantities,
    ),
  )
}
