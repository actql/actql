///|
fn graph_selection_tag(selection : GraphRowSelection) -> Int {
  match selection {
    PendingSelection => 0
    SelectedRow => 1
    SkipRow => 2
  }
}

///|
test "Graph selection retains a name fragment and candidate until comparison settles" {
  let prefix = "L".repeat(512)
  let definition = @carrier.graph_node_definition(
    "D".repeat(513),
    [@contract.primitive(@contract.NumberType, nullable=false)],
    @carrier.rows([], field_set=@carrier.Closed, max_fields=0, max_name_bytes=0).unwrap(),
    [prefix + "A", prefix + "B"],
    max_fields=2,
    max_name_bytes=2000,
  ).unwrap()
  for
    (name, label, expected, polls) in [
      (Some("D".repeat(513)), None, SelectedRow, 9),
      (Some("D".repeat(512) + "X"), None, SkipRow, 9),
      (Some("d".repeat(513)), None, SkipRow, 1),
      (None, Some("l".repeat(512) + "b"), SelectedRow, 18),
      (None, Some("l".repeat(512) + "c"), SkipRow, 18),
      (None, None, SelectedRow, 1),
    ] {
    let mut index = 0
    let mut offset = 0
    let mut complete = false
    for poll in 1..<=polls {
      let (result, next_index, next_offset) = graph_definition_selected(
        definition, name, label, index, offset,
      )
      if result is PendingSelection {
        assert_true(poll < polls)
        if next_index == index {
          assert_true(next_offset > offset)
        } else {
          assert_eq(next_index, index + 1)
          assert_eq(next_offset, 0)
        }
        index = next_index
        offset = next_offset
      } else {
        assert_eq(graph_selection_tag(result), graph_selection_tag(expected))
        assert_eq(poll, polls)
        assert_eq((next_index, next_offset), (0, 0))
        complete = true
      }
    }
    assert_true(complete)
  }
  // Candidate zero must not be skipped merely because its first fragment ties.
  let (result, index, offset) = graph_definition_selected(
    definition,
    None,
    Some(prefix + "B"),
    0,
    0,
  )
  assert_eq((graph_selection_tag(result), index, offset), (0, 0, 64))
  // After settling candidate zero, candidate one starts from offset zero.
  let (result, index, offset) = graph_definition_selected(
    definition,
    None,
    Some(prefix + "B"),
    0,
    512,
  )
  assert_eq((graph_selection_tag(result), index, offset), (0, 1, 0))
}
