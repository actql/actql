///|
/// Immutable column spelling and source position for canonical row emission.
/// This is serialization metadata, never ownership or execution evidence.
struct RowWireOrder {
  columns : Array[(String, Int)]
  work : Int
}

///|
pub fn prepare_row_wire_order(
  names : Array[String],
  max_columns : Int,
  max_work : Int,
) -> Result[RowWireOrder, RowWireIssue] {
  if max_columns < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let width = names.length()
  if width > max_columns || width > max_work {
    return Err(OrderLimit)
  }
  let control = { remaining: max_work - width, max_frames: 0, }
  let columns : Array[(String, Int)] = []
  for i in 0..<width {
    let name = names[i]
    let mut position = columns.length()
    while position > 0 {
      let previous = columns[position - 1].0
      if !spend_control(control, 1) ||
        !spend_control_text(control, name) ||
        !spend_control_text(control, previous) {
        return Err(OrderLimit)
      }
      let comparison = @canonical.compare_utf16(previous, name)
      if comparison == 0 {
        return Err(InvalidLayout)
      }
      if comparison < 0 {
        break
      }
      position -= 1
    }
    columns.push((name, i))
    for j = columns.length() - 1; j > position; j = j - 1 {
      columns[j] = columns[j - 1]
    }
    columns[position] = (name, i)
  }
  Ok({ columns, work: max_work - control.remaining, })
}

///|
pub fn row_wire_order_column(
  order : RowWireOrder,
  index : Int,
) -> (String, Int)? {
  order.columns.get(index)
}

///|
pub fn row_wire_order_work(order : RowWireOrder) -> Int {
  order.work
}
