///|
// Unit-first is the existing canonical Common expression. The original Value
// owner reads/formats exact UTC parts; no epoch-nanosecond or Host Date exists.
fn temporal_truncation(
  expression : @lower.Expression,
  unit_value : Value,
  value : Value,
) -> Result[Value, ScalarIssue] {
  if unit_value is Null || value is Null {
    return Ok(Null)
  }
  guard unit_value is Text(unit) else { return Err(InvalidOperand) }
  match value {
    Captured(@admitted.Date(text)) => {
      if unit != "d" ||
        text.length() != 10 ||
        @admitted.timestamp_instant(text + "T00:00:00.000Z") is None {
        return Err(InvalidOperand)
      }
      Ok(value)
    }
    Captured(@admitted.Timestamp(text)) => {
      guard @admitted.timestamp_instant(text) is Some(instant) else {
        return Err(InvalidOperand)
      }
      let (seconds, nanoseconds) = if unit == "ms" {
        (instant.seconds, instant.nanoseconds / 1000000 * 1000000)
      } else {
        let width = match unit {
          "s" => 1L
          "m" => 60L
          "h" => 3600L
          "d" => 86400L
          _ => return Err(InvalidOperand)
        }
        // Seconds are already floored and bounded by the four-digit calendar.
        // Correct truncating integer remainder into the containing UTC bucket.
        let remainder = instant.seconds % width
        let start = instant.seconds - remainder
        (if remainder < 0L { start - width } else { start }, 0)
      }
      guard @admitted.epoch_parts_timestamp(seconds, nanoseconds)
        is Some(result) else {
        return Err(ArithmeticFailure)
      }
      // The generated value is checked through the existing Value owner using
      // the original typed result contract's non-null refinement. The result
      // still returns through the ordinary expression/root admission path.
      guard @admitted.checked_timestamp_value(
          result,
          @contract.with_nullability(
            @lower.expression_contract(expression),
            false,
          ),
        )
        is Some(checked) else {
        return Err(InvalidOperand)
      }
      Ok(capture(checked.value))
    }
    _ => Err(InvalidOperand)
  }
}
