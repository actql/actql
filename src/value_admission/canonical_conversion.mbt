///|
priv enum CanonicalConversionFrame {
  Visit(@identity.CanonicalValue, Int, @contract.Contract?)
  ArrayNext(
    @identity.FrozenArray[@identity.CanonicalValue],
    ArrayBuilder,
    Int,
    Int,
    @contract.Contract?
  )
  ObjectNext(
    @identity.FrozenArray[(String, @identity.CanonicalValue)],
    ObjectBuilder,
    Int,
    Int,
    @contract.Fields?
  )
  VectorNext(
    @identity.FrozenArray[@identity.CanonicalValue],
    VectorBuilder,
    Int
  )
  ArrayAppend(ArrayBuilder)
  ObjectAppend(ObjectBuilder, String)
  JsonEnd
}

///|
/// Convert admitted canonical transport data, not a typed model result.
/// Every child is constructed separately; the normal typed recheck follows.
struct CanonicalConversion {
  pending : Array[CanonicalConversionFrame]
  limits : Limits
  mut nodes : Int
  mut text_bytes : Int
  mut value : Value?
  mut failed : Bool
  mut cancelled : Bool
  wire : Bool
}

///|
pub enum CanonicalConversionPoll {
  CanonicalConversionContinue
  CanonicalConversionComplete(Value)
  CanonicalConversionFailed
}

///|
pub fn start_canonical_conversion(
  value : @identity.CanonicalValue,
  limits : Limits,
  contract? : @contract.Contract? = None,
  wire? : Bool = false,
) -> CanonicalConversion? {
  if limits.max_nodes < 1 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return None
  }
  Some({
    pending: [Visit(value, 0, contract)],
    limits,
    nodes: 0,
    text_bytes: 0,
    value: None,
    failed: false,
    cancelled: false,
    wire,
  })
}

///|
fn conversion_text(cursor : CanonicalConversion, text : String) -> Bool {
  match
    @scalar.admit_utf8_length(
      text,
      cursor.limits.max_text_bytes - cursor.text_bytes,
    ) {
    Err(_) => false
    Ok(bytes) => {
      cursor.text_bytes += bytes
      true
    }
  }
}

///|
fn conversion_scalar(
  value : @identity.CanonicalValue,
  contract : @contract.Contract,
  limits : Limits,
) -> Value? {
  let json = match value {
    @identity.Null => Json::null()
    @identity.Bool(value) => Json::boolean(value)
    @identity.Number(value) => Json::number(value)
    @identity.String(value) => Json::string(value)
    _ => return None
  }
  let span : @span.Span = {
    start_byte: 0,
    end_byte: 0,
    start_line: 1,
    end_line: 1,
    start_column: 1,
    end_column: 1,
    source_path: "model-capture",
  }
  let decoded = match
    @decode.admit_raw_json(json, span, {
      max_nodes: 1,
      max_depth: 0,
      max_string_bytes: limits.max_text_bytes,
      max_total_string_bytes: limits.max_text_bytes,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  match admit(contract, decoded, limits) {
    Ok(value) => Some(value.value)
    Err(_) => None
  }
}

///|
fn conversion_frame(
  cursor : CanonicalConversion,
  frame : CanonicalConversionFrame,
) -> Bool {
  match frame {
    Visit(value, depth, expected) => {
      if cursor.nodes == cursor.limits.max_nodes {
        return false
      }
      cursor.nodes += 1
      if expected is Some(contract) && contract.shape is @contract.Json {
        if value is @identity.Null {
          if !contract.nullable {
            return false
          }
          cursor.value = Some(Null)
          return true
        }
        let payload = if cursor.wire {
          guard @identity.object_field_count(value) == Some(1) &&
            @identity.object_field(value, "$json") is Some(payload) else {
            return false
          }
          payload
        } else {
          value
        }
        cursor.nodes -= 1
        cursor.pending.push(JsonEnd)
        cursor.pending.push(Visit(payload, depth, None))
        return true
      }
      if !(value is @identity.Array(_)) &&
        !(value is @identity.Object(_)) &&
        expected is Some(contract) {
        let remaining = cursor.limits.max_text_bytes - cursor.text_bytes
        if value is @identity.String(text) && !conversion_text(cursor, text) {
          return false
        }
        cursor.value = conversion_scalar(value, contract, {
          ..cursor.limits,
          max_nodes: 1,
          max_text_bytes: remaining,
        })
        return cursor.value is Some(_)
      }
      match value {
        @identity.Null => cursor.value = Some(Null)
        @identity.Bool(value) => cursor.value = Some(Boolean(value))
        @identity.Number(value) => cursor.value = number_value(value)
        @identity.String(text) => {
          if !conversion_text(cursor, text) {
            return false
          }
          // Admission already validated this immutable data text.
          cursor.value = Some(Text(text))
        }
        @identity.Array(items) => {
          let count = @identity.array_count(items)
          if depth >= cursor.limits.max_depth ||
            count > cursor.limits.max_nodes - cursor.nodes {
            return false
          }
          let child_contract = match expected {
            None => None
            Some(contract) =>
              match contract.shape {
                @contract.Array(item, max_items~) => {
                  if max_items is Some(limit) && count.to_int64() > limit {
                    return false
                  }
                  Some(item)
                }
                @contract.Vector(dimensions~) => {
                  if count.to_double() != dimensions {
                    return false
                  }
                  guard prepare_vector_value(count) is Some(builder) else {
                    return false
                  }
                  cursor.value = None
                  cursor.pending.push(VectorNext(items, builder, 0))
                  return true
                }
                _ => return false
              }
          }
          guard prepare_array_value(count) is Some(builder) else {
            return false
          }
          cursor.value = None
          cursor.pending.push(
            ArrayNext(items, builder, 0, depth + 1, child_contract),
          )
        }
        @identity.Object(fields) => {
          let count = @identity.array_count(fields)
          if depth >= cursor.limits.max_depth ||
            count > cursor.limits.max_nodes - cursor.nodes {
            return false
          }
          let contracts = match expected {
            None => None
            Some(contract) =>
              match contract.shape {
                @contract.Object(contracts) => {
                  if count != @contract.field_count(contracts) {
                    return false
                  }
                  Some(contracts)
                }
                _ => return false
              }
          }
          guard prepare_object_value(count, data_keys=true) is Some(builder) else {
            return false
          }
          cursor.value = None
          cursor.pending.push(
            ObjectNext(fields, builder, 0, depth + 1, contracts),
          )
        }
      }
      true
    }
    ArrayNext(items, builder, index, depth, contract) => {
      if @identity.array_at(items, index) is Some(value) {
        cursor.pending.push(
          ArrayNext(items, builder, index + 1, depth, contract),
        )
        cursor.pending.push(ArrayAppend(builder))
        cursor.pending.push(Visit(value, depth, contract))
      } else {
        cursor.value = finish_array_value(builder)
        if cursor.value is None {
          return false
        }
      }
      true
    }
    ObjectNext(fields, builder, index, depth, contracts) => {
      if @identity.array_at(fields, index) is Some((name, value)) {
        if !conversion_text(cursor, name) {
          return false
        }
        let contract = match contracts {
          None => None
          Some(fields) => {
            guard @contract.field_at(fields, index) is Some(field) &&
              field.name == name else {
              return false
            }
            Some(field.contract)
          }
        }
        cursor.pending.push(
          ObjectNext(fields, builder, index + 1, depth, contracts),
        )
        cursor.pending.push(ObjectAppend(builder, name))
        cursor.pending.push(Visit(value, depth, contract))
      } else {
        cursor.value = finish_object_value(builder)
        if cursor.value is None {
          return false
        }
      }
      true
    }
    VectorNext(items, builder, index) => {
      if @identity.array_at(items, index) is Some(value) {
        if cursor.nodes == cursor.limits.max_nodes {
          return false
        }
        cursor.nodes += 1
        guard value is @identity.Number(component) &&
          append_vector_component(builder, component) else {
          return false
        }
        cursor.pending.push(VectorNext(items, builder, index + 1))
      } else {
        cursor.value = finish_vector_value(builder)
        if cursor.value is None {
          return false
        }
      }
      true
    }
    ArrayAppend(builder) => {
      guard cursor.value is Some(value) else { return false }
      cursor.value = None
      append_array_item(builder, value)
    }
    ObjectAppend(builder, name) => {
      guard cursor.value is Some(value) else { return false }
      cursor.value = None
      append_object_field(builder, name, value)
    }
    JsonEnd => {
      guard cursor.value is Some(payload) else { return false }
      cursor.value = Some(JsonData(payload))
      true
    }
  }
}

///|
/// One node, field, append or container end. Parent work/control owns polling.
pub fn advance_canonical_conversion(
  cursor : CanonicalConversion,
) -> CanonicalConversionPoll {
  if cursor.failed || cursor.cancelled {
    return CanonicalConversionFailed
  }
  if cursor.pending.pop() is Some(frame) && !conversion_frame(cursor, frame) {
    cursor.failed = true
    return CanonicalConversionFailed
  }
  if cursor.pending.is_empty() {
    match cursor.value {
      Some(value) => CanonicalConversionComplete(value)
      None => {
        cursor.failed = true
        CanonicalConversionFailed
      }
    }
  } else {
    CanonicalConversionContinue
  }
}

///|
pub fn cancel_canonical_conversion(cursor : CanonicalConversion) -> Unit {
  for frame in cursor.pending {
    match frame {
      ArrayNext(_, builder, _, _, _) | ArrayAppend(builder) =>
        cancel_array_value(builder) |> ignore
      ObjectNext(_, builder, _, _, _) | ObjectAppend(builder, _) =>
        cancel_object_value(builder) |> ignore
      VectorNext(_, builder, _) => cancel_vector_value(builder) |> ignore
      Visit(_, _, _) | JsonEnd => ()
    }
  }
  cursor.pending.clear()
  cursor.value = None
  cursor.cancelled = true
}
