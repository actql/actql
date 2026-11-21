///|
/// Count an inclusive signed64 progression without overflowing the distance
/// between opposite endpoints or negating the minimum signed64 step.
/// The count must fit the existing ArrayBuilder length representation.
pub fn signed64_progression_count(
  start : Int64,
  end : Int64,
  step : Int64,
) -> Int? {
  if step == 0L {
    return None
  }
  if (step > 0L && start > end) || (step < 0L && start < end) {
    return Some(0)
  }
  let first = start.reinterpret_as_uint64()
  let last = end.reinterpret_as_uint64()
  let unsigned_step = step.reinterpret_as_uint64()
  let advances = if step > 0L {
    (last - first) / unsigned_step
  } else {
    (first - last) / (0UL - unsigned_step)
  }
  if advances >= 2147483647UL {
    None
  } else {
    Some(advances.to_int() + 1)
  }
}
