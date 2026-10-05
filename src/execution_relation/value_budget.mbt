///|
pub(all) struct ValueLimits {
  max_nodes : Int
  max_text_bytes : Int
  max_depth : Int
  max_work : Int
} derive(Eq, Debug)

///|
pub(all) struct ValueUsage {
  nodes : Int
  text_bytes : Int
  work : Int
} derive(Eq, Debug)

///|
pub(all) enum CaptureIssue {
  InvalidCaptureLimits
  CaptureLimit
  NotValuesNode
  MissingParameter(String)
  InvalidCheckedRow
  NotRelationInput
  NotRelationOutput
  ScopedInputNotImplemented
  ConditionalInputRequiresPresence
  InputValue(Int, @admitted.Issue)
  ClosedCapture
  ForeignCheckedValue(Int, Int)
} derive(Eq, Debug)

///|
pub(all) enum CaptureOrigin {
  ValuesNode(Int)
  SuppliedInput(Int)
} derive(Eq, Debug)

///|
priv struct ValueBudget {
  limits : ValueLimits
  mut nodes : Int
  mut text : Int
  mut work : Int
  mut external_work : Int
}

///|
fn value_budget(limits : ValueLimits) -> Result[ValueBudget, CaptureIssue] {
  if limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 ||
    limits.max_work < 0 {
    Err(InvalidCaptureLimits)
  } else {
    Ok({ limits, nodes: 0, text: 0, work: 0, external_work: 0, })
  }
}

///|
fn remaining_value_work(b : ValueBudget) -> Int {
  b.limits.max_work - b.work - b.external_work
}

///|
fn charge_external_value_work(b : ValueBudget, units : Int) -> Bool {
  if units < 0 || units > remaining_value_work(b) {
    return false
  }
  b.external_work += units
  true
}

///|
fn charge_node(b : ValueBudget, depth : Int) -> Bool {
  if depth > b.limits.max_depth ||
    b.nodes >= b.limits.max_nodes ||
    remaining_value_work(b) < 1 {
    return false
  }
  b.nodes += 1
  b.work += 1
  true
}

///|
fn charge_text(b : ValueBudget, text : String) -> Bool {
  let available = Int::min(
    b.limits.max_text_bytes - b.text,
    remaining_value_work(b),
  )
  match @scalar.admit_utf8_length(text, available) {
    Ok(size) => {
      b.text += size
      b.work += size
      true
    }
    Err(_) => false
  }
}

///|
priv enum MeasureFrame {
  Read(@admitted.Value, Int)
  ArrayNext(@admitted.FrozenArray[@admitted.Value], Int, Int)
  ObjectNext(@admitted.FrozenArray[(String, @admitted.Value)], Int, Int)
}

///|
/// O(depth) traversal space, no elements() copies or UTF-8 output allocation.
/// Counts logical occurrences even when immutable backing values are shared.
fn measure(value : @admitted.Value, depth : Int, b : ValueBudget) -> Bool {
  let stack = [Read(value, depth)]
  while stack.pop() is Some(frame) {
    match frame {
      Read(value, depth) => {
        if !charge_node(b, depth) {
          return false
        }
        match value {
          @admitted.Null | @admitted.Boolean(_) | @admitted.Number(_) => ()
          @admitted.Text(s) | @admitted.Date(s) | @admitted.Timestamp(s) =>
            if !charge_text(b, s) {
              return false
            }
          @admitted.Decimal(d) =>
            if !charge_text(b, d.coefficient) {
              return false
            }
          @admitted.Array(items) => {
            if @admitted.element_count(items) > b.limits.max_nodes - b.nodes {
              return false
            }
            if @admitted.element_count(items) > 0 {
              if depth >= b.limits.max_depth {
                return false
              }
              stack.push(ArrayNext(items, 0, depth + 1))
            }
          }
          @admitted.Object(items) => {
            if @admitted.element_count(items) > b.limits.max_nodes - b.nodes {
              return false
            }
            if @admitted.element_count(items) > 0 {
              if depth >= b.limits.max_depth {
                return false
              }
              stack.push(ObjectNext(items, 0, depth + 1))
            }
          }
          @admitted.Vector(items) => {
            let count = @admitted.element_count(items)
            if count > b.limits.max_nodes - b.nodes ||
              count > remaining_value_work(b) ||
              (count > 0 && depth >= b.limits.max_depth) {
              return false
            }
            b.nodes += count
            b.work += count
          }
          @admitted.Reference(reference) =>
            if !@admitted.reference_available(reference) ||
              !charge_text(b, @admitted.reference_wire(reference)) {
              return false
            }
        }
      }
      ArrayNext(items, index, depth) =>
        if @admitted.element_at(items, index) is Some(child) {
          if index + 1 < @admitted.element_count(items) {
            stack.push(ArrayNext(items, index + 1, depth))
          }
          stack.push(Read(child, depth))
        }
      ObjectNext(items, index, depth) =>
        if @admitted.element_at(items, index) is Some((name, child)) {
          if !charge_text(b, name) {
            return false
          }
          if index + 1 < @admitted.element_count(items) {
            stack.push(ObjectNext(items, index + 1, depth))
          }
          stack.push(Read(child, depth))
        }
    }
  }
  true
}

///|
priv enum SteppedMeasureFrame {
  SteppedRead(@admitted.Value, Int)
  SteppedScalar
  SteppedText(String)
  SteppedTextNext(String, Int)
  SteppedArrayNext(@admitted.FrozenArray[@admitted.Value], Int, Int)
  SteppedObjectNext(@admitted.FrozenArray[(String, @admitted.Value)], Int, Int)
}

///|
priv struct SteppedValueMeasure {
  frames : Array[SteppedMeasureFrame]
  workspace : RowWorkspace
  mut workspace_failed : Bool
}

///|
priv enum SteppedMeasurePoll {
  SteppedMeasureContinue
  SteppedMeasureComplete
  SteppedMeasureLimit
  SteppedMeasureWorkspaceLimit
}

///|
fn push_stepped_measure(
  cursor : SteppedValueMeasure,
  frame : SteppedMeasureFrame,
) -> Bool {
  if !reserve_slots(cursor.workspace, 1) {
    cursor.workspace_failed = true
    return false
  }
  cursor.frames.push(frame)
  true
}

///|
fn start_stepped_measure_result(
  value : Value,
  workspace : RowWorkspace,
) -> SteppedValueMeasure? {
  if !reserve_slots(workspace, 1) {
    return None
  }
  let frame = match value {
    Captured(value) => SteppedRead(value, 2)
    Text(text) => SteppedText(text)
    Null | Boolean(_) | Number(_) => SteppedScalar
  }
  Some({ frames: [frame], workspace, workspace_failed: false, })
}

///|
fn clear_stepped_measure(cursor : SteppedValueMeasure) -> Unit {
  release_slots(cursor.workspace, cursor.frames.length())
  cursor.frames.clear()
}

///|
// Share the finite UTF-16 walk; each owner keeps its own existing charges.
fn step_bounded_text_measure(
  text : String,
  position : Int,
  charge : (Int) -> Bool,
) -> Int? {
  let mut index = position
  let end = position + Int::min(64, text.length() - position)
  while index < end {
    let unit = text[index].to_int()
    let mut units = 1
    let width = if unit < 0x80 {
      1
    } else if unit < 0x800 {
      2
    } else if unit >= 0xd800 && unit <= 0xdbff {
      if index + 1 >= text.length() {
        return None
      }
      let trailing = text[index + 1].to_int()
      if trailing < 0xdc00 || trailing > 0xdfff {
        return None
      }
      units = 2
      4
    } else if unit >= 0xdc00 && unit <= 0xdfff {
      return None
    } else {
      3
    }
    if !charge(width) {
      return None
    }
    index += units
  }
  Some(index)
}

///|
fn step_stepped_measure_text(
  cursor : SteppedValueMeasure,
  text : String,
  position : Int,
  budget : ValueBudget,
) -> Bool {
  guard step_bounded_text_measure(text, position, width => {
      if width > budget.limits.max_text_bytes - budget.text ||
        width > remaining_value_work(budget) {
        false
      } else {
        budget.text += width
        budget.work += width
        true
      }
    })
    is Some(index) else {
    return false
  }
  index == text.length() ||
  push_stepped_measure(cursor, SteppedTextNext(text, index))
}

///|
fn step_stepped_measure_text_start(
  cursor : SteppedValueMeasure,
  text : String,
  budget : ValueBudget,
) -> Bool {
  let available = Int::min(
    budget.limits.max_text_bytes - budget.text,
    remaining_value_work(budget),
  )
  if text.length() > available {
    return false
  }
  if text.length() <= 64 {
    charge_text(budget, text)
  } else {
    push_stepped_measure(cursor, SteppedTextNext(text, 0))
  }
}

///|
fn advance_stepped_measure_result(
  cursor : SteppedValueMeasure,
  budget : ValueBudget,
) -> SteppedMeasurePoll {
  guard cursor.frames.pop() is Some(frame) else {
    return SteppedMeasureComplete
  }
  release_slots(cursor.workspace, 1)
  let valid = match frame {
    SteppedScalar => charge_node(budget, 2)
    SteppedText(text) =>
      charge_node(budget, 2) &&
      step_stepped_measure_text_start(cursor, text, budget)
    SteppedTextNext(text, index) =>
      step_stepped_measure_text(cursor, text, index, budget)
    SteppedRead(value, depth) => {
      if !charge_node(budget, depth) {
        return SteppedMeasureLimit
      }
      match value {
        @admitted.Null | @admitted.Boolean(_) | @admitted.Number(_) => true
        @admitted.Text(text)
        | @admitted.Date(text)
        | @admitted.Timestamp(text) =>
          step_stepped_measure_text_start(cursor, text, budget)
        @admitted.Decimal(decimal) =>
          step_stepped_measure_text_start(cursor, decimal.coefficient, budget)
        @admitted.Array(items) => {
          let count = @admitted.element_count(items)
          count <= budget.limits.max_nodes - budget.nodes &&
          (
            count == 0 ||
            (
              depth < budget.limits.max_depth &&
              push_stepped_measure(
                cursor,
                SteppedArrayNext(items, 0, depth + 1),
              )
            )
          )
        }
        @admitted.Object(items) => {
          let count = @admitted.element_count(items)
          count <= budget.limits.max_nodes - budget.nodes &&
          (
            count == 0 ||
            (
              depth < budget.limits.max_depth &&
              push_stepped_measure(
                cursor,
                SteppedObjectNext(items, 0, depth + 1),
              )
            )
          )
        }
        @admitted.Vector(items) => {
          let count = @admitted.element_count(items)
          if count > budget.limits.max_nodes - budget.nodes ||
            count > remaining_value_work(budget) ||
            (count > 0 && depth >= budget.limits.max_depth) {
            false
          } else {
            budget.nodes += count
            budget.work += count
            true
          }
        }
        @admitted.Reference(reference) =>
          @admitted.reference_available(reference) &&
          step_stepped_measure_text_start(
            cursor,
            @admitted.reference_wire(reference),
            budget,
          )
      }
    }
    SteppedArrayNext(items, index, depth) =>
      if @admitted.element_at(items, index) is Some(child) {
        (
          index + 1 >= @admitted.element_count(items) ||
          push_stepped_measure(
            cursor,
            SteppedArrayNext(items, index + 1, depth),
          )
        ) &&
        push_stepped_measure(cursor, SteppedRead(child, depth))
      } else {
        false
      }
    SteppedObjectNext(items, index, depth) =>
      if @admitted.element_at(items, index) is Some((name, child)) {
        (
          index + 1 >= @admitted.element_count(items) ||
          push_stepped_measure(
            cursor,
            SteppedObjectNext(items, index + 1, depth),
          )
        ) &&
        push_stepped_measure(cursor, SteppedRead(child, depth)) &&
        step_stepped_measure_text_start(cursor, name, budget)
      } else {
        false
      }
  }
  if !valid {
    if cursor.workspace_failed {
      SteppedMeasureWorkspaceLimit
    } else {
      SteppedMeasureLimit
    }
  } else if cursor.frames.is_empty() {
    SteppedMeasureComplete
  } else {
    SteppedMeasureContinue
  }
}
