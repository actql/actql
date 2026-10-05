///|
priv enum CursorFrame {
  CursorRead(@decode.Cursor, Int)
  CursorArrayNext(@decode.Cursor, Array[CanonicalValue], Int, Int)
  CursorArrayAppend(Array[CanonicalValue])
  CursorObjectKeys(
    @decode.Cursor,
    Array[Array[String]],
    Map[String, Unit],
    Int,
    Int
  )
  CursorObjectSort(@decode.Cursor, Array[Array[String]], @sort.Sort, Int)
  CursorObjectNext(
    @decode.Cursor,
    Array[Array[String]],
    @sort.Sort,
    Array[(String, CanonicalValue)],
    Int,
    Int
  )
  CursorObjectAppend(Array[(String, CanonicalValue)], String)
}

///|
/// Canonical data admission in the existing identity owner. This retains an
/// indexed, already admitted source, normalizes only object names, and exposes
/// no partial canonical tree or reference authority.
struct CursorAdmission {
  budget : InputBudget
  max_nodes : Int
  max_raw_text_bytes : Int
  mut raw_text_bytes : Int
  mut root : @decode.Cursor?
  pending : Array[CursorFrame]
  mut value : CanonicalValue?
  mut terminal : Bool
  data_keys : Bool
}

///|
pub enum CursorAdmissionPoll {
  CursorAdmissionContinue
  CursorAdmissionComplete(CanonicalValue, Int, Int)
  CursorAdmissionFailed(CanonicalFailure)
  CursorAdmissionTerminal
}

///|
pub fn start_cursor_admission(
  root : @decode.Cursor,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
  max_raw_text_bytes : Int,
  data_keys? : Bool = false,
) -> CursorAdmission? {
  if max_nodes < 1 ||
    max_depth < 0 ||
    max_utf16_units < 0 ||
    max_raw_text_bytes < 0 {
    return None
  }
  Some({
    budget: { nodes: max_nodes, units: max_utf16_units, depth: max_depth, },
    max_nodes,
    max_raw_text_bytes,
    raw_text_bytes: 0,
    root: Some(root),
    pending: [CursorRead(root, 0)],
    value: None,
    terminal: false,
    data_keys,
  })
}

///|
fn cursor_admission_text(
  admission : CursorAdmission,
  text : String,
  identifier~ : Bool,
) -> String raise CanonicalFailure {
  let normalized = normalize(text, admission.budget, identifier~)
  match
    @scalar.admit_utf8_length(
      text,
      admission.max_raw_text_bytes - admission.raw_text_bytes,
    ) {
    Ok(bytes) => admission.raw_text_bytes += bytes
    Err(_) => raise InputLimit
  }
  normalized
}

///|
fn CursorAdmission::step(
  admission : CursorAdmission,
) -> Unit raise CanonicalFailure {
  let budget = admission.budget
  guard admission.pending.pop() is Some(frame) else { raise InputLimit }
  match frame {
    CursorRead(cursor, depth) => {
      if budget.nodes == 0 {
        raise InputLimit
      }
      budget.nodes -= 1
      if @decode.is_null(cursor) {
        admission.value = Some(Null)
      } else if @decode.array_length(cursor) is Some(count) {
        if depth >= budget.depth || count > budget.nodes {
          raise InputLimit
        }
        admission.value = None
        admission.pending.push(CursorArrayNext(cursor, [], 0, depth + 1))
      } else if @decode.object_length(cursor) is Some(count) {
        if depth >= budget.depth || count > budget.nodes {
          raise InputLimit
        }
        admission.value = None
        admission.pending.push(
          CursorObjectKeys(cursor, [], Map([]), 0, depth + 1),
        )
      } else {
        admission.value = Some(
          match @decode.view(cursor) {
            @decode.BoolValue(value) => Bool(value)
            @decode.TextValue(text) =>
              String(cursor_admission_text(admission, text, identifier=false))
            @decode.NumberValue(number) => {
              if number.is_nan() ||
                number.is_inf() ||
                number.reinterpret_as_uint64() == 0x8000000000000000UL {
                raise InvalidNumber
              }
              Number(number)
            }
            _ => raise InputLimit
          },
        )
      }
    }
    CursorArrayNext(cursor, output, index, depth) =>
      if @decode.element_at(cursor, index) is Some(child) {
        admission.pending.push(
          CursorArrayNext(cursor, output, index + 1, depth),
        )
        admission.pending.push(CursorArrayAppend(output))
        admission.pending.push(CursorRead(child, depth))
      } else {
        admission.value = Some(Array({ values: output, }))
      }
    CursorArrayAppend(output) => {
      guard admission.value is Some(value) else { raise InputLimit }
      output.push(value)
      admission.value = None
    }
    CursorObjectKeys(cursor, keys, seen, index, depth) =>
      if @decode.field_at(cursor, index) is Some((raw_name, _)) {
        if budget.nodes == 0 {
          raise InputLimit
        }
        let name = cursor_admission_text(
          admission,
          raw_name,
          identifier=!admission.data_keys,
        )
        if seen.contains(name) {
          raise DuplicateKey(name)
        }
        seen[name] = ()
        keys.push([name])
        admission.pending.push(
          CursorObjectKeys(cursor, keys, seen, index + 1, depth),
        )
      } else {
        seen.clear()
        if keys.length() > 1073741823 {
          raise InputLimit
        }
        guard @sort.prepare_deferred(keys, keys.length() * 2) is Ok(sort) else {
          raise InputLimit
        }
        admission.pending.push(CursorObjectSort(cursor, keys, sort, depth))
      }
    CursorObjectSort(cursor, keys, sort, depth) =>
      match @sort.advance(sort, 1) {
        Ok(@sort.Continue(..)) =>
          admission.pending.push(CursorObjectSort(cursor, keys, sort, depth))
        Ok(@sort.Complete(..)) =>
          admission.pending.push(
            CursorObjectNext(cursor, keys, sort, [], 0, depth),
          )
        Err(_) => raise InputLimit
      }
    CursorObjectNext(cursor, keys, sort, output, index, depth) =>
      if @sort.index_at(sort, index) is Some(source_index) {
        guard @decode.field_at(cursor, source_index) is Some((_, child)) else {
          raise InputLimit
        }
        let name = keys[source_index][0]
        admission.pending.push(
          CursorObjectNext(cursor, keys, sort, output, index + 1, depth),
        )
        admission.pending.push(CursorObjectAppend(output, name))
        admission.pending.push(CursorRead(child, depth))
      } else {
        @sort.cleanup(sort) |> ignore
        keys.clear()
        admission.value = Some(Object({ values: output, }))
      }
    CursorObjectAppend(output, name) => {
      guard admission.value is Some(value) else { raise InputLimit }
      output.push((name, value))
      admission.value = None
    }
  }
}

///|
/// One indexed node, key, shared sort transition, append or container end.
/// The two usage counters are input nodes and raw UTF-8 text, not poll work.
pub fn advance_cursor_admission(
  admission : CursorAdmission,
) -> CursorAdmissionPoll {
  if admission.terminal || admission.root is None {
    return CursorAdmissionTerminal
  }
  admission.step() catch {
    issue => {
      cancel_cursor_admission(admission)
      return CursorAdmissionFailed(issue)
    }
  }
  if admission.pending.is_empty() {
    guard admission.value is Some(value) else {
      cancel_cursor_admission(admission)
      return CursorAdmissionFailed(InputLimit)
    }
    admission.value = None
    admission.root = None
    admission.terminal = true
    CursorAdmissionComplete(
      value,
      admission.max_nodes - admission.budget.nodes,
      admission.raw_text_bytes,
    )
  } else {
    CursorAdmissionContinue
  }
}

///|
pub fn cancel_cursor_admission(admission : CursorAdmission) -> Unit {
  for frame in admission.pending {
    match frame {
      CursorArrayNext(_, output, _, _) | CursorArrayAppend(output) =>
        output.clear()
      CursorObjectKeys(_, keys, seen, _, _) => {
        keys.clear()
        seen.clear()
      }
      CursorObjectSort(_, keys, sort, _) => {
        @sort.cleanup(sort) |> ignore
        keys.clear()
      }
      CursorObjectNext(_, keys, sort, output, _, _) => {
        @sort.cleanup(sort) |> ignore
        keys.clear()
        output.clear()
      }
      CursorObjectAppend(output, _) => output.clear()
      CursorRead(_, _) => ()
    }
  }
  admission.pending.clear()
  admission.value = None
  admission.root = None
  admission.terminal = true
}
