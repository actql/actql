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
}

///|
fn value_budget(limits : ValueLimits) -> Result[ValueBudget, CaptureIssue] {
  if limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 ||
    limits.max_work < 0 {
    Err(InvalidCaptureLimits)
  } else {
    Ok({ limits, nodes: 0, text: 0, work: 0, })
  }
}

///|
fn charge_node(b : ValueBudget, depth : Int) -> Bool {
  if depth > b.limits.max_depth ||
    b.nodes >= b.limits.max_nodes ||
    b.work >= b.limits.max_work {
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
    b.limits.max_work - b.work,
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
              count > b.limits.max_work - b.work ||
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
