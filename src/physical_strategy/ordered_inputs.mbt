///|
fn ordered_data_inputs_complete(
  input_counts : Array[Int],
  data : Array[DataEdge],
  supplied_slots? : Array[LocalInputSlot] = [],
  captured_prefix? : Int = 1,
) -> Bool {
  if input_counts.is_empty() ||
    captured_prefix < 0 ||
    captured_prefix > input_counts.length() {
    return false
  }
  let seen : Array[Array[Bool]] = Array::makei(input_counts.length(), task => {
    let count = input_counts[task]
    if count < 0 {
      []
    } else {
      Array::make(count, false)
    }
  })
  for edge in data {
    if edge.consumer < captured_prefix || edge.consumer >= input_counts.length() {
      return false
    }
    let inputs = seen[edge.consumer]
    if edge.input < 0 || edge.input >= inputs.length() || inputs[edge.input] {
      return false
    }
    inputs[edge.input] = true
  }
  for input in supplied_slots {
    if input.consumer < captured_prefix ||
      input.consumer >= input_counts.length() {
      return false
    }
    let inputs = seen[input.consumer]
    if input.input < 0 || input.input >= inputs.length() || inputs[input.input] {
      return false
    }
    inputs[input.input] = true
  }
  for task in captured_prefix..<input_counts.length() {
    if input_counts[task] < 0 {
      return false
    }
    for present in seen[task] {
      if !present {
        return false
      }
    }
  }
  true
}

///|
pub fn graph_ordered_inputs_complete(graph : CheckedDAG) -> Bool {
  ordered_data_inputs_complete(
    graph.input_counts,
    graph.data,
    supplied_slots=graph.supplied_slots,
    captured_prefix=graph.captured_prefix,
  )
}
