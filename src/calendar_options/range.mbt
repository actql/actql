///|
/// Shared Calendar domain/range validation for originally admitted timestamp
/// values. This does not bind Parameters, select a profile or issue a Plan.
pub fn validate_range(start : String, end : String) -> Result[Unit, IssueKind] {
  if @value.timestamp_epoch_milliseconds(start) is None ||
    @value.timestamp_epoch_milliseconds(end) is None ||
    start.has_prefix("0000-") ||
    end.has_prefix("0000-") {
    return Err(InvalidTimestamp)
  }
  if @canonical.compare_utf16(start, end) > 0 {
    Err(ReversedRange)
  } else {
    Ok(())
  }
}
