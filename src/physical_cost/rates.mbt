///|
/// Linear estimates over declared quantities, not resource admission or evidence.
pub(all) struct WorkRate {
  work_slots : Array[Int]
  fixed_ms : Int64?
  per_row_ms : Int64?
  per_wire_byte_ms : Int64?
  per_pair_ms : Int64?
}

///|
struct RateSchedule {
  rates : Array[WorkRate]
  work : Int
}

///|
pub enum RateIssue {
  InvalidQuantity
  InvalidCoefficient
  Overflow
  Coverage(CostIssue)
} derive(Eq, Debug)

///|
/// The implementation supplies its work inventory. Validate before copying;
/// callers charge this bounded preparation and each evaluation to their ledger.
pub fn prepare_rate_schedule(
  required_work : Int,
  rates : Array[WorkRate],
  max_work : Int,
) -> Result[RateSchedule, RateIssue] {
  if required_work < 0 || max_work < 0 {
    return Err(Coverage(InvalidLimit))
  }
  if required_work > max_work || rates.length() > max_work - required_work {
    return Err(Coverage(PlanningLimit))
  }
  let mut work = required_work + rates.length()
  for rate in rates {
    if rate.work_slots.length() > max_work - work {
      return Err(Coverage(PlanningLimit))
    }
    work += rate.work_slots.length()
    for
      value in [
        rate.fixed_ms,
        rate.per_row_ms,
        rate.per_wire_byte_ms,
        rate.per_pair_ms,
      ] {
      if value is Some(value) && value < 0L {
        return Err(InvalidCoefficient)
      }
    }
  }
  match
    assess_serial(
      required_work,
      rates.map(rate => { work_slots: rate.work_slots, milliseconds: None, }),
      max_work,
    ) {
    Err(issue) => return Err(Coverage(issue))
    Ok(_) => ()
  }
  Ok({
    rates: rates.map(rate => { ..rate, work_slots: rate.work_slots.copy(), }),
    work,
  })
}

///|
pub fn rate_schedule_work(schedule : RateSchedule) -> Int {
  schedule.work
}

///|
pub fn evaluate_rate_schedule(
  schedule : RateSchedule,
  rows : Int64?,
  bytes : Int64?,
  pairs : Int64?,
) -> Result[Array[SerialEstimateLine], RateIssue] {
  for quantity in [rows, bytes, pairs] {
    if quantity is Some(value) && value < 0L {
      return Err(InvalidQuantity)
    }
  }
  let lines = []
  for rate in schedule.rates {
    let milliseconds = match rate_value(rate, rows, bytes, pairs) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    // Returned arrays cannot mutate the installed schedule.
    lines.push({ work_slots: rate.work_slots.copy(), milliseconds, })
  }
  Ok(lines)
}

///|
fn rate_value(
  rate : WorkRate,
  rows : Int64?,
  bytes : Int64?,
  pairs : Int64?,
) -> Result[Int64?, RateIssue] {
  guard rate.fixed_ms is Some(base) &&
    rate.per_row_ms is Some(per_row) &&
    rate.per_wire_byte_ms is Some(per_byte) &&
    rate.per_pair_ms is Some(per_pair) else {
    return Ok(None)
  }
  let mut total = base
  for
    (coefficient, quantity) in [
      (per_row, rows),
      (per_byte, bytes),
      (per_pair, pairs),
    ] {
    if coefficient == 0L {
      continue
    }
    guard quantity is Some(quantity) else { return Ok(None) }
    if quantity > (9223372036854775807L - total) / coefficient {
      return Err(Overflow)
    }
    total += quantity * coefficient
  }
  Ok(Some(total))
}
