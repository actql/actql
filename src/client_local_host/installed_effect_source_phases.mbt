///|
// The normal direct provider returns its E-R before exposing the captured
// Source. Keep every acquisition/evidence/scratch remainder simultaneously,
// including earlier captures while a later reader constructs its response.
// Restored captures reserve their same complete envelope during restoration
// and settle it before return; their holding survives. These bounds therefore
// also dominate that route without inventing a second physical reader.
//
// This projects already sealed acquisition/reader inventories and the SAME
// retained tail envelope. It does not check/compile a Program, prepare a Plan,
// issue resources, or infer retirement from a Promise or Source value.
fn installed_effect_provider_execution_phases(
  captures : Array[ClientInstalledCaptureCapacity],
  transport_execution : Array[Int64],
  tail_execution : Int64,
  complete_retained : Int64,
) -> (Int64, Int64)? {
  if captures.is_empty() ||
    captures.length() != transport_execution.length() ||
    tail_execution < 0L ||
    complete_retained < 0L {
    return None
  }
  let mut previous = 0L
  let mut reading = 0L
  let mut tail_retained = complete_retained
  for index, capture in captures {
    guard capture.original_input &&
      capture.acquisition is Some(acquisition) &&
      capture.provider is Some((original, provider)) &&
      physical_equal(original, acquisition) else {
      return None
    }
    let provider_execution = @execution.execution_capacity_execution_bytes(
      provider,
    )
    let provider_retained = @execution.execution_capacity_retained_bytes(
      provider,
    )
    let scratch = transport_execution[index]
    if scratch < 0L ||
      capture.retained_bytes < 0L ||
      capture.retained_bytes > tail_retained ||
      capture.execution_bytes < provider_execution ||
      provider_execution < provider_retained {
      return None
    }
    // The complete retained inventory is an additive sum of these exact
    // captured inputs and the original tail. Its immutable module may already
    // coexist with a reader; keep that tail R in the read peak too.
    tail_retained -= capture.retained_bytes
    guard @execution.checked_preparation_add_product(
        previous,
        capture.execution_bytes,
        1L,
      )
      is Some(full) &&
      @execution.checked_preparation_add_product(full, scratch, 1L)
      is Some(full) else {
      return None
    }
    reading = Int64::max(reading, full)
    // This is the same original sum used by RowRun retirement, not a
    // subtraction from Compute's maximum of different execution phases.
    let base = capture.execution_bytes - provider_execution
    guard @execution.checked_preparation_add_product(
        base, provider_retained, 1L,
      )
      is Some(remaining) &&
      @execution.checked_preparation_add_product(remaining, scratch, 1L)
      is Some(remaining) &&
      @execution.checked_preparation_add_product(previous, remaining, 1L)
      is Some(next) else {
      return None
    }
    previous = next
  }
  guard @execution.checked_preparation_add_product(reading, tail_retained, 1L)
    is Some(reading) &&
    @execution.checked_preparation_add_product(previous, tail_execution, 1L)
    is Some(completed) else {
    return None
  }
  Some((reading, completed))
}
