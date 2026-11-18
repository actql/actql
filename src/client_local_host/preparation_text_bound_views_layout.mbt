///|
// The erased TextBound view became one retained record (header/two references).
// A Timestamp also retains Some(original pattern), including its scalar tag.
// Price that closed maximum for every original Envelope, including the
// non-Timestamp record. Each actual
// Task may retain its complete sequence; no source walk or policy count is used.
fn installed_text_bound_views_layout(
  graph : @strategy.CheckedDAG,
) -> (Int64, Int64)? {
  let original = @strategy.graph_program(graph)
  let bounds = @checked.expression_bound_count(original).to_int64()
  let tasks = @strategy.graph_task_count(graph).to_int64()
  guard @execution.checked_preparation_add_product(0L, bounds, tasks)
    is Some(count) &&
    @execution.checked_preparation_add_product(0L, count, 2L) is Some(headers) &&
    @execution.checked_preparation_add_product(0L, count, 3L)
    is Some(references) &&
    @execution.preparation_representation_cost({
      record_headers: headers,
      reference_slots: references,
      scalar_words: count,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    // A cached old sequence remains live while a different original limit
    // selection constructs its replacement, including a failed child prefix.
    @execution.checked_preparation_add_product(0L, retained, 2L)
    is Some(execution) else {
    return None
  }
  Some((retained, execution))
}
