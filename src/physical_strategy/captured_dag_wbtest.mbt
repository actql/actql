///|
fn data_edge(producer : Int, consumer : Int, input : Int) -> DataEdge {
  { producer, target: @pipeline.Step(0), consumer, input, }
}

///|
fn local_input_slot(consumer : Int, input : Int) -> LocalInputSlot {
  { consumer, input, }
}

///|
test "captured DAG accepts complete ordered multi-input edges" {
  assert_true(
    ordered_data_inputs_complete([0, 3], [
      data_edge(0, 1, 0),
      data_edge(0, 1, 1),
      data_edge(0, 1, 2),
    ]),
  )
}

///|
test "captured DAG preserves repeated producers at distinct positions" {
  assert_true(
    ordered_data_inputs_complete([0, 0, 3], [
      data_edge(0, 2, 0),
      data_edge(1, 2, 1),
      data_edge(0, 2, 2),
    ]),
  )
}

///|
test "captured DAG composes produced and supplied input positions" {
  assert_true(
    ordered_data_inputs_complete([0, 3], [data_edge(0, 1, 1)], supplied_slots=[
      local_input_slot(1, 0),
      local_input_slot(1, 2),
    ]),
  )
  assert_false(
    ordered_data_inputs_complete([0, 2], [data_edge(0, 1, 0)], supplied_slots=[
      local_input_slot(1, 0),
    ]),
  )
  assert_false(
    ordered_data_inputs_complete([0, 1], [], supplied_slots=[
      local_input_slot(0, 0),
    ]),
  )
}

///|
test "captured DAG rejects missing duplicate and foreign input positions" {
  assert_false(
    ordered_data_inputs_complete([0, 3], [
      data_edge(0, 1, 0),
      data_edge(0, 1, 2),
    ]),
  )
  assert_false(
    ordered_data_inputs_complete([0, 2], [
      data_edge(0, 1, 0),
      data_edge(0, 1, 0),
    ]),
  )
  assert_false(
    ordered_data_inputs_complete([0, 2], [
      data_edge(0, 1, 0),
      data_edge(0, 1, 2),
    ]),
  )
  assert_false(ordered_data_inputs_complete([0, 1], [data_edge(0, 0, 0)]))
  assert_false(ordered_data_inputs_complete([0, 1], [data_edge(0, 2, 0)]))
}
