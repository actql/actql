///|
/// Read-only canonical tree. Only admission can construct values.
pub enum CanonicalValue {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(FrozenArray[CanonicalValue])
  Object(FrozenArray[(String, CanonicalValue)])
}

///|
struct FrozenArray[T] {
  values : Array[T]
}

///|
/// Return a detached collection, never the canonical tree's backing array.
pub fn[T] array_values(value : FrozenArray[T]) -> Array[T] {
  value.values.copy()
}

///|
pub(all) suberror CanonicalFailure {
  InvalidNumber
  InvalidUnicode(Int)
  DuplicateKey(String)
  InputLimit
} derive(Debug)

///|
priv struct InputBudget {
  mut nodes : Int
  mut units : Int
  depth : Int
}

///|
fn normalize(
  text : String,
  budget : InputBudget,
) -> String raise CanonicalFailure {
  if text.length() > budget.units {
    raise InputLimit
  }
  budget.units -= text.length()
  match @value.normalize_nfc_lf(text) {
    Ok(value) => value
    Err(UnpairedSurrogate(offset)) => raise InvalidUnicode(offset)
  }
}

///|
priv enum BuildFrame {
  Visit(Json, Int)
  ArrayNext(Array[Json], Int, Array[CanonicalValue], Int)
  ArrayAppend(Array[CanonicalValue])
  ObjectNext(
    Iter[(String, Json)],
    Array[(String, CanonicalValue)],
    Map[String, Unit],
    Int
  )
  ObjectAppend(Array[(String, CanonicalValue)], String)
}

///|
/// Normalize an in-memory JSON value into an owned immutable tree.
/// Input units count raw UTF-16 units in every visited key and string value.
/// Nodes include containers; root scalar depth is zero, root container depth one.
/// This is not JSON parsing or strict canonical-artifact admission.
pub fn from_json(
  json : Json,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> CanonicalValue raise CanonicalFailure {
  if max_nodes < 1 || max_depth < 0 || max_utf16_units < 0 {
    raise InputLimit
  }
  let budget = { nodes: max_nodes, units: max_utf16_units, depth: max_depth, }
  let pending : Array[BuildFrame] = [Visit(json, 0)]
  let mut result : CanonicalValue = Null
  while pending.pop() is Some(frame) {
    match frame {
      Visit(value, depth) => {
        if budget.nodes == 0 {
          raise InputLimit
        }
        budget.nodes -= 1
        match value {
          Null => result = Null
          True => result = Bool(true)
          False => result = Bool(false)
          Number(number, ..) => {
            if number.is_nan() ||
              number.is_inf() ||
              number.reinterpret_as_uint64() == 0x8000000000000000UL {
              raise InvalidNumber
            }
            result = Number(number)
          }
          String(text) => result = String(normalize(text, budget))
          Array(items) => {
            if depth >= budget.depth {
              raise InputLimit
            }
            // Check minimum child cost before retaining an output collection.
            if items.length() > budget.nodes {
              raise InputLimit
            }
            pending.push(ArrayNext(items, 0, [], depth + 1))
          }
          Object(fields) => {
            if depth >= budget.depth {
              raise InputLimit
            }
            if fields.length() > budget.nodes {
              raise InputLimit
            }
            pending.push(ObjectNext(fields.iter(), [], Map([]), depth + 1))
          }
        }
      }
      ArrayNext(items, index, output, depth) =>
        if index < items.length() {
          pending.push(ArrayNext(items, index + 1, output, depth))
          pending.push(ArrayAppend(output))
          pending.push(Visit(items[index], depth))
        } else {
          result = Array({ values: output, })
        }
      ArrayAppend(output) => output.push(result)
      ObjectNext(entries, output, seen, depth) =>
        match entries.next() {
          Some((original_key, item)) => {
            // A key belongs to a value node; reject exhausted nodes before
            // spending the separate text budget on that key.
            if budget.nodes == 0 {
              raise InputLimit
            }
            let key = normalize(original_key, budget)
            if seen.contains(key) {
              raise DuplicateKey(key)
            }
            seen[key] = ()
            pending.push(ObjectNext(entries, output, seen, depth))
            pending.push(ObjectAppend(output, key))
            pending.push(Visit(item, depth))
          }
          None => {
            output.sort_by((a, b) => @value.compare_utf16(a.0, b.0))
            result = Object({ values: output, })
          }
        }
      ObjectAppend(output, key) => output.push((key, result))
    }
  }
  result
}
