///|
/// Observed or explicitly estimated quantities for a future fixed-input task.
/// None is unknown, not zero. These quantities never grant execution or admission.
pub(all) struct TaskEstimateQuantities {
  rows : Int64?
  wire_bytes : Int64?
  pairs : Int64?
}

///|
/// Pure quantities available from already completed managed producer views.
/// Row counts are exact. A managed completion does not by itself establish the
/// legacy row-wire byte quantity, so that quantity remains unknown. Pair work
/// is exact for binary inputs and zero for non-join arities; overflow remains
/// unknown rather than being truncated or treated as zero.
pub fn[T] managed_task_estimate_quantities(
  inputs : Array[@execution.ManagedProducerRead[T]],
) -> TaskEstimateQuantities {
  let mut rows = 0L
  let mut rows_known = true
  for input in inputs {
    let count = @execution.managed_producer_read_row_count(input).to_int64()
    if count < 0L || count > 9223372036854775807L - rows {
      rows_known = false
    } else if rows_known {
      rows += count
    }
  }
  let pairs = if inputs.length() == 2 {
    let left = @execution.managed_producer_read_row_count(inputs[0]).to_int64()
    let right = @execution.managed_producer_read_row_count(inputs[1]).to_int64()
    if left < 0L ||
      right < 0L ||
      (right > 0L && left > 9223372036854775807L / right) {
      None
    } else {
      Some(left * right)
    }
  } else {
    Some(0L)
  }
  { rows: if rows_known { Some(rows) } else { None }, wire_bytes: None, pairs, }
}

///|
pub(all) enum InstalledOfferIssue[E] {
  InvalidLimits
  Unavailable
  OfferLimit
  ForeignOffer
  Implementation(E)
}

///|
/// A finite installation contributes offers without exposing provider payloads.
/// Exact registration and checked task ownership are rechecked after each call.
/// Callers account for bounded planning work; callbacks must not perform I/O.
pub fn[C, E] collect_installed_task_offers(
  driver : DispatchDriver,
  installed : @connector.CapabilityImplementations[
    (C, Int, TaskEstimateQuantities) -> Result[Array[@strategy.TaskOffer], E],
  ],
  context : C,
  task : Int,
  quantities : TaskEstimateQuantities,
  max_entries : Int,
  max_offers : Int,
) -> Result[Array[@strategy.TaskOffer], InstalledOfferIssue[E]] {
  if max_entries < 0 || max_offers < 0 {
    return Err(InvalidLimits)
  }
  for quantity in [quantities.rows, quantities.wire_bytes, quantities.pairs] {
    if quantity is Some(value) && value < 0L {
      return Err(InvalidLimits)
    }
  }
  guard @connector.capability_implementation_registrations(
      installed, max_entries,
    )
    is Some(registrations) else {
    return Err(InvalidLimits)
  }
  let offers : Array[@strategy.TaskOffer] = []
  for registration in registrations {
    guard @connector.capability_implementation(installed, registration)
      is Some(implementation) else {
      return Err(Unavailable)
    }
    let proposed = match implementation(context, task, quantities) {
      Ok(value) => value
      Err(issue) => return Err(Implementation(issue))
    }
    if @connector.capability_implementation(installed, registration) is None {
      return Err(Unavailable)
    }
    if proposed.length() > max_offers - offers.length() {
      return Err(OfferLimit)
    }
    for offer in proposed {
      if !@strategy.task_offer_matches(
          driver.owner.run,
          task,
          registration,
          offer,
        ) {
        return Err(ForeignOffer)
      }
      offers.push(offer)
    }
  }
  Ok(offers)
}
