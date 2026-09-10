///|
/// Transfers annotations on unchanged fields of a checked Calendar bucket.
/// A generator or an independently constructed input cannot authorize transfer.
pub fn transfer_ranking_calendar(
  previous : RankingInput,
  operation : @calendar.CheckedCalendar,
  limits : Limits,
) -> Result[RankingTransfer, Issue] {
  try {
    let source = @calendar.source(operation)
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard @calendar.input(operation) is Some(@carrier.Relation(input)) &&
      previous.carrier is @carrier.Relation(records) else {
      fail(source, RankingInputMismatch)
    }
    let same = if physical_equal(input, records) {
      true
    } else {
      match
        (@carrier.complete_schema(input), @carrier.complete_schema(records)) {
        (Some(a), Some(b)) => physical_equal(a, b)
        _ => false
      }
    }
    if !same {
      fail(source, RankingInputMismatch)
    }
    if limits.max_work < 1 {
      fail(source, BudgetExceeded)
    }
    Ok({
      input: { ..previous, carrier: @calendar.output(operation), },
      usage: { work: 1, nodes: 0, text_bytes: 0, },
    })
  } catch {
    Stop(e) => Err(e)
  }
}
