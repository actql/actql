///|
/// One pending unit of a resumable runtime recheck: a node still to check, or
/// the next child of a container whose own node was already checked.
priv enum RecheckFrame {
  CheckNode(Value, @contract.Contract, Int)
  ArrayItems(Array[Value], @contract.Contract, Int, Int)
  ObjectFields(Array[(String, Value)], @contract.Contract, Int, Int)
  JsonNode(Value, Int)
  JsonItems(Array[Value], Int, Int)
  JsonFields(Array[(String, Value)], Int, Int)
}

///|
/// Resumable form of `recheck_runtime_value`: the same structural checks,
/// budgets and result, one node or one container child per advance, so a
/// caller can stop between nodes of a large composite value.
struct RecheckCursor {
  value : Value
  contract : @contract.Contract
  limits : Limits
  budget : RecheckBudget
  stack : Array[RecheckFrame]
  mut finished : Bool
}

///|
pub enum RecheckPoll {
  RecheckContinue
  RecheckComplete(CheckedValue, Int, Int)
  RecheckFailed
}

///|
pub fn start_recheck_runtime_value(
  value : Value,
  contract : @contract.Contract,
  limits : Limits,
) -> RecheckCursor? {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return None
  }
  Some({
    value,
    contract,
    limits,
    budget: {
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      max_depth: limits.max_depth,
    },
    stack: [CheckNode(value, contract, 0)],
    finished: false,
  })
}

///|
/// Drop every pending frame. A cancelled cursor retains no child references.
pub fn cancel_recheck_runtime_value(cursor : RecheckCursor) -> Unit {
  cursor.stack.clear()
  cursor.finished = true
}

///|
fn recheck_step_fail(cursor : RecheckCursor) -> RecheckPoll {
  cancel_recheck_runtime_value(cursor)
  RecheckFailed
}

///|
pub fn advance_recheck_runtime_value(cursor : RecheckCursor) -> RecheckPoll {
  if cursor.finished {
    return RecheckFailed
  }
  let budget = cursor.budget
  guard cursor.stack.pop() is Some(frame) else {
    cursor.finished = true
    return RecheckComplete(
      { contract: cursor.contract, value: cursor.value, },
      cursor.limits.max_nodes - budget.nodes,
      cursor.limits.max_text_bytes - budget.text,
    )
  }
  match frame {
    CheckNode(value, contract, depth) =>
      if !recheck_node_step(cursor, value, contract, depth) {
        return recheck_step_fail(cursor)
      }
    ArrayItems(values, item, index, depth) =>
      if index < values.length() {
        cursor.stack.push(ArrayItems(values, item, index + 1, depth))
        cursor.stack.push(CheckNode(values[index], item, depth + 1))
      }
    ObjectFields(values, contract, index, depth) =>
      if index < values.length() {
        guard contract.shape is @contract.Object(fields) &&
          @contract.field_at(fields, index) is Some(field) else {
          return recheck_step_fail(cursor)
        }
        let (name, child) = values[index]
        if name != field.name || recheck_text(name, budget) is None {
          return recheck_step_fail(cursor)
        }
        cursor.stack.push(ObjectFields(values, contract, index + 1, depth))
        cursor.stack.push(CheckNode(child, field.contract, depth + 1))
      }
    JsonNode(value, depth) =>
      if !recheck_json_step(cursor, value, depth) {
        return recheck_step_fail(cursor)
      }
    JsonItems(values, index, depth) =>
      if index < values.length() {
        cursor.stack.push(JsonItems(values, index + 1, depth))
        cursor.stack.push(JsonNode(values[index], depth + 1))
      }
    JsonFields(values, index, depth) =>
      if index < values.length() {
        let (name, child) = values[index]
        if recheck_text(name, budget) is None {
          return recheck_step_fail(cursor)
        }
        cursor.stack.push(JsonFields(values, index + 1, depth))
        cursor.stack.push(JsonNode(child, depth + 1))
      }
  }
  RecheckContinue
}

///|
/// One node of `recheck_value`; containers defer their children.
fn recheck_node_step(
  cursor : RecheckCursor,
  value : Value,
  contract : @contract.Contract,
  depth : Int,
) -> Bool {
  let budget = cursor.budget
  if budget.nodes == 0 {
    return false
  }
  budget.nodes -= 1
  if value is Null {
    return contract.nullable
  }
  match (value, contract.shape) {
    (Array(values), @contract.Array(item, max_items~)) => {
      let count = values.values.length()
      if depth >= budget.max_depth ||
        (max_items is Some(limit) && count.to_int64() > limit) {
        return false
      }
      cursor.stack.push(ArrayItems(values.values, item, 0, depth))
      true
    }
    (Object(values), @contract.Object(fields)) => {
      if depth >= budget.max_depth ||
        values.values.length() != @contract.field_count(fields) {
        return false
      }
      cursor.stack.push(ObjectFields(values.values, contract, 0, depth))
      true
    }
    (_, @contract.Json) => {
      budget.nodes += 1
      recheck_json_step(cursor, value, depth)
    }
    // Scalars, vectors and references have no deferred children.
    _ => {
      budget.nodes += 1
      recheck_value(value, contract, budget, depth)
    }
  }
}

///|
/// One node of `recheck_json`; containers defer their children.
fn recheck_json_step(
  cursor : RecheckCursor,
  value : Value,
  depth : Int,
) -> Bool {
  let budget = cursor.budget
  match value {
    Array(values) => {
      if budget.nodes == 0 {
        return false
      }
      budget.nodes -= 1
      if depth >= budget.max_depth {
        return false
      }
      cursor.stack.push(JsonItems(values.values, 0, depth))
      true
    }
    Object(values) => {
      if budget.nodes == 0 {
        return false
      }
      budget.nodes -= 1
      if depth >= budget.max_depth {
        return false
      }
      cursor.stack.push(JsonFields(values.values, 0, depth))
      true
    }
    _ => recheck_json(value, budget, depth)
  }
}
