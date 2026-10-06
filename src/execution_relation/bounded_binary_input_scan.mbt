///|
/// Each input position is a separate logical occurrence, even when both
/// positions borrow the same completed producer storage.
priv struct BoundedBinaryInputScan {
  left : BoundedBindingInput
  right : BoundedBindingInput
  budget : ValueBudget
  control : ControlBudget
  workspace : RowWorkspace
  mut port : Int
  mut row : Int
  mut column : Int
  mut row_open : Bool
  frames : Array[BinaryInputFrame]
}

///|
priv enum BinaryInputFrame {
  ScanValue(@admitted.Value, Int)
  ScanArray(@admitted.FrozenArray[@admitted.Value], Int, Int)
  ScanObject(@admitted.FrozenArray[(String, @admitted.Value)], Int, Int)
  ScanVector(@admitted.FrozenArray[Double], Int, Int)
  ScanText(String, Int)
}

///|
priv enum BinaryInputScanIssue {
  ValueLimit
  ControlLimit
  WorkspaceLimit
  InputUnavailable
}

///|
fn binary_input_scan(
  left : ProducerRead,
  right : ProducerRead,
  limits : ValueLimits,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> BoundedBinaryInputScan? {
  binary_binding_input_scan(
    CompletedBindingInput(left),
    CompletedBindingInput(right),
    limits,
    control,
    workspace,
  )
}

///|
fn binary_binding_input_scan(
  left : BoundedBindingInput,
  right : BoundedBindingInput,
  limits : ValueLimits,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> BoundedBinaryInputScan? {
  match value_budget(limits) {
    Err(_) => None
    Ok(budget) =>
      Some({
        left,
        right,
        budget,
        control,
        workspace,
        port: 0,
        row: 0,
        column: 0,
        row_open: false,
        frames: [],
      })
  }
}

///|
fn binary_input_push(
  scan : BoundedBinaryInputScan,
  frame : BinaryInputFrame,
) -> Bool {
  if !reserve_slots(scan.workspace, 1) {
    false
  } else {
    scan.frames.push(frame)
    true
  }
}

///|
/// Drop scan-owned frames before releasing the remaining kernel workspace.
/// Producer reads are borrowed and remain available to their own owners.
fn cleanup_binary_input_scan(scan : BoundedBinaryInputScan) -> Unit {
  let count = scan.frames.length()
  scan.frames.clear()
  release_slots(scan.workspace, count)
}

///|
fn binary_input_push_text(
  scan : BoundedBinaryInputScan,
  text : String,
) -> Result[Unit, BinaryInputScanIssue] {
  let available = Int::min(
    scan.budget.limits.max_text_bytes - scan.budget.text,
    scan.budget.limits.max_work - scan.budget.work,
  )
  if text.length() > available {
    return Err(ValueLimit)
  }
  if text.length() > 0 && !binary_input_push(scan, ScanText(text, 0)) {
    return Err(WorkspaceLimit)
  }
  Ok(())
}

///|
fn binary_input_scan_text(
  scan : BoundedBinaryInputScan,
  text : String,
  index : Int,
) -> Result[Unit, BinaryInputScanIssue] {
  if index >= text.length() {
    return Err(InputUnavailable)
  }
  let unit = text[index].to_int()
  let width = if unit < 0x80 {
    1
  } else if unit < 0x800 {
    2
  } else if unit >= 0xd800 && unit <= 0xdbff {
    if index + 1 >= text.length() {
      return Err(ValueLimit)
    }
    let trailing = text[index + 1].to_int()
    if trailing < 0xdc00 || trailing > 0xdfff {
      return Err(ValueLimit)
    }
    4
  } else if unit >= 0xdc00 && unit <= 0xdfff {
    return Err(ValueLimit)
  } else {
    3
  }
  if width > scan.budget.limits.max_text_bytes - scan.budget.text ||
    width > scan.budget.limits.max_work - scan.budget.work {
    return Err(ValueLimit)
  }
  scan.budget.text += width
  scan.budget.work += width
  let next = index + (if width == 4 { 2 } else { 1 })
  if next < text.length() && !binary_input_push(scan, ScanText(text, next)) {
    return Err(WorkspaceLimit)
  }
  Ok(())
}

///|
fn binary_input_scan_frame(
  scan : BoundedBinaryInputScan,
  frame : BinaryInputFrame,
) -> Result[Unit, BinaryInputScanIssue] {
  match frame {
    ScanValue(value, depth) => {
      if !charge_node(scan.budget, depth) {
        return Err(ValueLimit)
      }
      match value {
        @admitted.JsonData(payload) => {
          scan.budget.nodes -= 1
          if !binary_input_push(scan, ScanValue(payload, depth)) {
            return Err(WorkspaceLimit)
          }
        }
        @admitted.Null | @admitted.Boolean(_) | @admitted.Number(_) => ()
        @admitted.Text(text)
        | @admitted.Date(text)
        | @admitted.Timestamp(text) =>
          match binary_input_push_text(scan, text) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
        @admitted.Decimal(decimal) =>
          match binary_input_push_text(scan, decimal.coefficient) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
        @admitted.Array(items) => {
          let count = @admitted.element_count(items)
          if count > scan.budget.limits.max_nodes - scan.budget.nodes ||
            (count > 0 && depth >= scan.budget.limits.max_depth) {
            return Err(ValueLimit)
          }
          if count > 0 &&
            !binary_input_push(scan, ScanArray(items, 0, depth + 1)) {
            return Err(WorkspaceLimit)
          }
        }
        @admitted.Object(items) => {
          let count = @admitted.element_count(items)
          if count > scan.budget.limits.max_nodes - scan.budget.nodes ||
            (count > 0 && depth >= scan.budget.limits.max_depth) {
            return Err(ValueLimit)
          }
          if count > 0 &&
            !binary_input_push(scan, ScanObject(items, 0, depth + 1)) {
            return Err(WorkspaceLimit)
          }
        }
        @admitted.Vector(items) => {
          let count = @admitted.element_count(items)
          if count > scan.budget.limits.max_nodes - scan.budget.nodes ||
            count > scan.budget.limits.max_work - scan.budget.work ||
            (count > 0 && depth >= scan.budget.limits.max_depth) {
            return Err(ValueLimit)
          }
          if count > 0 &&
            !binary_input_push(scan, ScanVector(items, 0, depth + 1)) {
            return Err(WorkspaceLimit)
          }
        }
        @admitted.Reference(reference) =>
          if !@admitted.reference_available(reference) {
            return Err(ValueLimit)
          } else {
            match
              binary_input_push_text(scan, @admitted.reference_wire(reference)) {
              Err(issue) => return Err(issue)
              Ok(_) => ()
            }
          }
      }
    }
    ScanArray(items, index, depth) => {
      guard @admitted.element_at(items, index) is Some(child) else {
        return Err(InputUnavailable)
      }
      if index + 1 < @admitted.element_count(items) &&
        !binary_input_push(scan, ScanArray(items, index + 1, depth)) {
        return Err(WorkspaceLimit)
      }
      if !binary_input_push(scan, ScanValue(child, depth)) {
        return Err(WorkspaceLimit)
      }
    }
    ScanObject(items, index, depth) => {
      guard @admitted.element_at(items, index) is Some((name, child)) else {
        return Err(InputUnavailable)
      }
      if index + 1 < @admitted.element_count(items) &&
        !binary_input_push(scan, ScanObject(items, index + 1, depth)) {
        return Err(WorkspaceLimit)
      }
      if !binary_input_push(scan, ScanValue(child, depth)) {
        return Err(WorkspaceLimit)
      }
      match binary_input_push_text(scan, name) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    ScanVector(items, index, depth) => {
      if !charge_node(scan.budget, depth) {
        return Err(ValueLimit)
      }
      if index + 1 < @admitted.element_count(items) &&
        !binary_input_push(scan, ScanVector(items, index + 1, depth)) {
        return Err(WorkspaceLimit)
      }
    }
    ScanText(text, index) =>
      match binary_input_scan_text(scan, text, index) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
  }
  Ok(())
}

///|
/// One call performs at most one row, field, or nested-value transition.
/// The caller counts each call against its resume quantum.
fn advance_binary_input_scan(
  scan : BoundedBinaryInputScan,
) -> Result[Bool, BinaryInputScanIssue] {
  if scan.port == 2 {
    return Ok(true)
  }
  if !spend_control(scan.control, 1) {
    return Err(ControlLimit)
  }
  if scan.frames.pop() is Some(frame) {
    release_slots(scan.workspace, 1)
    match binary_input_scan_frame(scan, frame) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    return Ok(false)
  }
  let input = if scan.port == 0 { scan.left } else { scan.right }
  if !bounded_binding_input_available(input) {
    return Err(InputUnavailable)
  }
  if scan.row == bounded_binding_input_row_count(input) {
    scan.port += 1
    scan.row = 0
    scan.column = 0
    scan.row_open = false
    return Ok(scan.port == 2)
  }
  if !scan.row_open {
    if !charge_node(scan.budget, 1) {
      return Err(ValueLimit)
    }
    scan.row_open = true
    return Ok(false)
  }
  let schema = bounded_binding_input_schema(input)
  if scan.column == @schema.field_count(schema) {
    scan.row += 1
    scan.column = 0
    scan.row_open = false
    return Ok(false)
  }
  guard @schema.field_at(schema, scan.column) is Some(field) &&
    bounded_binding_input_cell(input, scan.row, scan.column) is Some(value) else {
    return Err(InputUnavailable)
  }
  match value {
    Captured(nested) =>
      if !binary_input_push(scan, ScanValue(nested, 2)) {
        return Err(WorkspaceLimit)
      }
    Text(text) =>
      if !charge_node(scan.budget, 2) {
        return Err(ValueLimit)
      } else {
        match binary_input_push_text(scan, text) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      }
    Null | Boolean(_) | Number(_) =>
      if !charge_node(scan.budget, 2) {
        return Err(ValueLimit)
      }
  }
  match binary_input_push_text(scan, @schema.reference_name(field.name)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  scan.column += 1
  Ok(false)
}
