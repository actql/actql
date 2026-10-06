///|
/// One pending unit of a resumable runtime recheck: a node still to check, or
/// the next child of a container whose own node was already checked.
priv enum RecheckFrame {
  CheckNode(Value, @contract.Contract, Int)
  ArrayItems(Array[Value], @contract.Contract, Int, Int)
  ObjectFields(Array[(String, Value)], @contract.Contract, Int, Int)
  ObjectName(Array[(String, Value)], @contract.Contract, Int, Int, Int)
  JsonNode(Value, Int)
  JsonItems(Array[Value], Int, Int)
  JsonFields(Array[(String, Value)], Int, Int)
  JsonName(Array[(String, Value)], Int, Int, Int)
  VectorItems(Array[Double], Int)
  TextUnits(String, @contract.TextLimits, Int, Int64, Int64)
}

///|
/// Resumable form of `recheck_runtime_value`: the same structural checks,
/// budgets and result, one node, one container child, or at most 64 UTF-16
/// text units per advance. A caller can stop inside large composite values
/// and Text scalars, including declared Object names. Opaque JSON member
/// names remain data, separate from the declared Object identifier domain.
struct RecheckCursor {
  value : Value
  contract : @contract.Contract
  limits : Limits
  budget : RecheckBudget
  stack : Array[RecheckFrame]
  mut text_counts : (Int64, Int64)?
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
    text_counts: None,
    finished: false,
  })
}

///|
/// Stage raw runtime Text without validating it synchronously. Only a
/// completed recheck yields a checked value for downstream publication.
pub fn start_recheck_runtime_text(
  value : String,
  contract : @contract.Contract,
  limits : Limits,
) -> RecheckCursor? {
  start_recheck_runtime_value(Text(value), contract, limits)
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
        if name.length() > 64 {
          if name.length() != field.name.length() || name.length() > budget.text {
            return recheck_step_fail(cursor)
          }
          cursor.stack.push(ObjectName(values, contract, index, depth, 0))
        } else {
          if name != field.name || recheck_text(name, budget) is None {
            return recheck_step_fail(cursor)
          }
          cursor.stack.push(ObjectFields(values, contract, index + 1, depth))
          cursor.stack.push(CheckNode(child, field.contract, depth + 1))
        }
      }
    ObjectName(values, contract, field_index, depth, offset) => {
      guard contract.shape is @contract.Object(fields) &&
        @contract.field_at(fields, field_index) is Some(field) else {
        return recheck_step_fail(cursor)
      }
      let (name, child) = values[field_index]
      let mut index = offset
      let end = offset + Int::min(64, name.length() - offset)
      // Fields is opaque: every contract constructor/admitter checks NFC/LF.
      // Exact equality therefore reuses that name evidence without applying
      // identifier normalization to any child data String. Delay both child
      // and sibling continuations until the name is completely checked, so
      // the existing depth-stack custody suffices.
      while index < end {
        let unit = name[index].to_int()
        if name[index] != field.name[index] {
          return recheck_step_fail(cursor)
        }
        let mut units = 1
        let bytes = if unit < 0x80 {
          1
        } else if unit < 0x800 {
          2
        } else if unit >= 0xd800 && unit <= 0xdbff {
          if index + 1 >= name.length() ||
            name[index + 1] != field.name[index + 1] ||
            name[index + 1].to_int() < 0xdc00 ||
            name[index + 1].to_int() > 0xdfff {
            return recheck_step_fail(cursor)
          }
          units = 2
          4
        } else if unit >= 0xdc00 && unit <= 0xdfff {
          return recheck_step_fail(cursor)
        } else {
          3
        }
        if bytes > budget.text {
          return recheck_step_fail(cursor)
        }
        budget.text -= bytes
        index += units
      }
      if index < name.length() {
        cursor.stack.push(
          ObjectName(values, contract, field_index, depth, index),
        )
      } else {
        cursor.stack.push(
          ObjectFields(values, contract, field_index + 1, depth),
        )
        cursor.stack.push(CheckNode(child, field.contract, depth + 1))
      }
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
        if name.length() > 64 {
          cursor.stack.push(JsonName(values, index, depth, 0))
        } else {
          if recheck_text(name, budget) is None {
            return recheck_step_fail(cursor)
          }
          cursor.stack.push(JsonFields(values, index + 1, depth))
          cursor.stack.push(JsonNode(child, depth + 1))
        }
      }
    JsonName(values, field_index, depth, offset) => {
      let (name, child) = values[field_index]
      guard recheck_text_fragment(budget, name, offset) is Some((next, _, _)) else {
        return recheck_step_fail(cursor)
      }
      if next < name.length() {
        cursor.stack.push(JsonName(values, field_index, depth, next))
      } else {
        cursor.stack.push(JsonFields(values, field_index + 1, depth))
        cursor.stack.push(JsonNode(child, depth + 1))
      }
    }
    VectorItems(values, index) =>
      if index < values.length() {
        let component = values[index]
        if component.is_nan() ||
          component.is_inf() ||
          (component == 0.0 && 1.0 / component < 0.0) {
          return recheck_step_fail(cursor)
        }
        cursor.stack.push(VectorItems(values, index + 1))
      }
    TextUnits(value, bounds, offset, characters, bytes) =>
      if !recheck_text_units(cursor, value, bounds, offset, characters, bytes) {
        return recheck_step_fail(cursor)
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
    (Text(text), @contract.Text(bounds)) => {
      // The UTF-16 lower bound is cheap, but the scalar scan must remain
      // interruptible even for a single large runtime Text value.
      if text.length() > budget.text {
        return false
      }
      cursor.stack.push(TextUnits(text, bounds, 0, 0L, 0L))
      true
    }
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
    (Vector(values), @contract.Vector(dimensions~)) => {
      let count = values.values.length()
      if depth >= budget.max_depth ||
        count.to_double() != dimensions ||
        count > budget.nodes {
        return false
      }
      // Preserve the original node accounting, but inspect one component
      // between caller-controlled stop/yield boundaries.
      budget.nodes -= count
      cursor.stack.push(VectorItems(values.values, 0))
      true
    }
    (JsonData(value), @contract.Json) => {
      budget.nodes += 1
      recheck_json_step(cursor, value, depth)
    }
    // Fixed-size typed scalars and references have no deferred children.
    _ => {
      budget.nodes += 1
      recheck_value(value, contract, budget, depth)
    }
  }
}

///|
/// Validate at most 64 UTF-16 units per poll, including a trailing surrogate
/// pair that starts at the boundary. Text usage is charged exactly once.
fn recheck_text_units(
  cursor : RecheckCursor,
  value : String,
  bounds : @contract.TextLimits,
  offset : Int,
  characters : Int64,
  bytes : Int64,
) -> Bool {
  guard recheck_text_fragment(cursor.budget, value, offset)
    is Some((index, added_characters, added_bytes)) else {
    return false
  }
  let count = characters + added_characters
  let byte_count = bytes + added_bytes
  if index < value.length() {
    cursor.stack.push(TextUnits(value, bounds, index, count, byte_count))
    true
  } else {
    cursor.text_counts = Some((count, byte_count))
    (bounds.min_length is None || count >= bounds.min_length.unwrap()) &&
    (bounds.max_codepoints is None || count <= bounds.max_codepoints.unwrap()) &&
    (
      bounds.max_utf8_bytes is None ||
      byte_count <= bounds.max_utf8_bytes.unwrap()
    )
  }
}

///|
/// Data Text and opaque JSON names share scalar-safe byte admission. Names
/// retain their exact data spelling; only their UTF-8 bytes are charged here.
fn recheck_text_fragment(
  budget : RecheckBudget,
  value : String,
  offset : Int,
) -> (Int, Int64, Int64)? {
  let mut index = offset
  let mut count = 0L
  let mut byte_count = 0L
  let end = offset + Int::min(64, value.length() - offset)
  while index < end {
    let unit = value[index].to_int()
    let mut units = 1
    let width = if unit < 0x80 {
      1
    } else if unit < 0x800 {
      2
    } else if unit >= 0xd800 && unit <= 0xdbff {
      if index + 1 >= value.length() {
        return None
      }
      let trailing = value[index + 1].to_int()
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
    if width > budget.text {
      return None
    }
    budget.text -= width
    byte_count += width.to_int64()
    count += 1L
    index += units
  }
  Some((index, count, byte_count))
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
    Text(text) => {
      if budget.nodes == 0 || text.length() > budget.text {
        return false
      }
      budget.nodes -= 1
      // JSON Text is data: preserve original scalars and line endings,
      // using the same chunked walk without identifier normalization.
      guard @contract.primitive(@contract.StringType, nullable=false).shape
        is @contract.Text(bounds) else {
        return false
      }
      cursor.stack.push(TextUnits(text, bounds, 0, 0L, 0L))
      true
    }
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
