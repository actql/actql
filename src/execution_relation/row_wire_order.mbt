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
  let cursor = match start_row_wire_order(names, max_columns, max_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  while !cursor.done {
    match advance_row_wire_order(cursor, 64) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  finish_row_wire_order(cursor)
}

///|
/// Serialization metadata only. The caller keeps borrowed input names stable
/// until transfer or cancellation; the finished order owns its column entries.
struct RowWireOrderPreparation {
  mut names : Array[String]?
  width : Int
  control : ControlBudget
  maximum_work : Int
  comparison : BoundedCompleteValueComparison
  mut columns : Array[(String, Int)]
  mut item : (String, Int)?
  mut index : Int
  mut position : Int
  mut shift : Int
  mut phase : Int
  mut done : Bool
  mut closed : Bool
  mut advancing : Bool
  mut poll_work : Int
}

///|
pub fn start_row_wire_order(
  names : Array[String],
  max_columns : Int,
  max_work : Int,
) -> Result[RowWireOrderPreparation, RowWireIssue] {
  if max_columns < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let width = names.length()
  if width > max_columns || width > max_work {
    return Err(OrderLimit)
  }
  Ok({
    names: Some(names),
    width,
    control: { remaining: max_work - width, max_frames: 0, },
    maximum_work: max_work,
    comparison: bounded_complete_value_comparison(),
    columns: [],
    item: None,
    index: 0,
    position: 0,
    shift: 0,
    phase: 0,
    done: false,
    closed: false,
    advancing: false,
    poll_work: 0,
  })
}

///|
pub fn cancel_row_wire_order(value : RowWireOrderPreparation) -> Bool {
  if value.closed {
    return false
  }
  value.closed = true
  value.names = None
  value.item = None
  value.columns = []
  true
}

///|
fn advance_row_wire_order_frame(
  value : RowWireOrderPreparation,
  names : Array[String],
) -> Result[Unit, RowWireIssue] {
  match value.phase {
    0 =>
      if value.index == value.width {
        value.done = true
      } else {
        value.item = Some((names[value.index], value.index))
        value.position = value.columns.length()
        value.phase = 1
      }
    1 =>
      if value.position == 0 {
        value.phase = 2
      } else {
        let comparison = match
          bounded_complete_value_comparison_step(
            value.comparison,
            Text(value.item.unwrap().0),
            Text(value.columns[value.position - 1].0),
            value.control,
          ) {
          Ok(value) => value
          Err(_) => return Err(OrderLimit)
        }
        if comparison is Some(order) {
          if order == 0 {
            return Err(InvalidLayout)
          }
          if order > 0 {
            value.phase = 2
          } else {
            value.position -= 1
          }
        }
      }
    2 => {
      // Width admission precedes every incrementally allocated column entry.
      value.columns.push(value.item.unwrap())
      value.shift = value.columns.length() - 1
      value.phase = 3
    }
    3 =>
      if value.shift > value.position {
        value.columns[value.shift] = value.columns[value.shift - 1]
        value.shift -= 1
      } else {
        value.phase = 4
      }
    4 => {
      value.columns[value.position] = value.item.unwrap()
      value.item = None
      value.index += 1
      value.phase = 0
    }
    _ => return Err(InvalidLayout)
  }
  Ok(())
}

///|
pub fn advance_row_wire_order(
  value : RowWireOrderPreparation,
  quantum : Int,
) -> Result[(Bool, Int), RowWireIssue] {
  if value.closed || value.advancing || quantum <= 0 {
    return Err(InvalidLayout)
  }
  value.poll_work = 0
  guard value.names is Some(names) && names.length() == value.width else {
    cancel_row_wire_order(value) |> ignore
    return Err(InvalidLayout)
  }
  if value.done {
    return Ok((true, 0))
  }
  value.advancing = true
  let result = (fn() -> Result[(Bool, Int), RowWireIssue] {
    for step in 0..<quantum {
      value.poll_work = step + 1
      match advance_row_wire_order_frame(value, names) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      if value.done {
        return Ok((true, step + 1))
      }
    }
    Ok((false, quantum))
  })()
  value.advancing = false
  if result is Err(_) {
    cancel_row_wire_order(value) |> ignore
  }
  result
}

///|
pub fn finish_row_wire_order(
  value : RowWireOrderPreparation,
) -> Result[RowWireOrder, RowWireIssue] {
  if value.closed || value.advancing || !value.done {
    return Err(InvalidLayout)
  }
  let columns = value.columns
  value.columns = []
  value.names = None
  value.closed = true
  Ok({ columns, work: value.maximum_work - value.control.remaining, })
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
