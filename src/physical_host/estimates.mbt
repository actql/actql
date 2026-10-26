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
