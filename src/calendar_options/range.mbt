///|
/// Shared Calendar domain/range validation for originally admitted timestamp
/// values. This does not bind Parameters, select a profile or issue a Plan.
pub fn validate_range(start : String, end : String) -> Result[Unit, IssueKind] {
  guard @value.compare_timestamp_text(start, end) is Some(order) &&
    !start.has_prefix("0000-") &&
    !end.has_prefix("0000-") else {
    return Err(InvalidTimestamp)
  }
  if order > 0 {
    Err(ReversedRange)
  } else {
    Ok(())
  }
}
