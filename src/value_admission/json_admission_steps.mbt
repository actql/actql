///|
priv enum JsonAdmissionFrame {
  ReadJson(@decode.Cursor, Int, Bool)
  ArrayNext(@decode.Cursor, ArrayBuilder, Int, Int)
  ObjectKeys(@decode.Cursor, Array[Array[String]], Int, Int)
  ObjectSort(@decode.Cursor, @sort.Sort, Int)
  ObjectNext(@decode.Cursor, @sort.Sort, ObjectBuilder, Int, Int)
  ArrayAppend(ArrayBuilder)
  ObjectAppend(ObjectBuilder, String)
}

///|
/// Ordinary JSON data admission in the existing Value owner. No reference
/// issuer is accepted: wire identity data never acquires live authority.
struct JsonAdmission {
  mut root : @decode.Cursor?
  limits : Limits
  budget : Budget
  frames : Array[JsonAdmissionFrame]
  mut value : Value?
  mut terminal : Bool
}

///|
pub enum JsonAdmissionPoll {
  JsonAdmissionContinue
  JsonAdmissionComplete(CheckedValue, Int, Int)
  JsonAdmissionFailed(Issue)
  JsonAdmissionTerminal
}

///|
pub fn start_json_admission(
  root : @decode.Cursor,
  limits : Limits,
) -> Result[JsonAdmission, Issue] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(
      ValueIssue(
        InvalidLimits,
        path=@decode.cursor_path(root),
        span=@decode.cursor_span(root),
      ),
    )
  }
  Ok({
    root: Some(root),
    limits,
    budget: {
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      max_depth: limits.max_depth,
    },
    frames: [ReadJson(root, 0, true)],
    value: None,
    terminal: false,
  })
}

///|
fn JsonAdmission::step(admission : JsonAdmission) -> Unit raise Abort {
  let budget = admission.budget
  let root = admission.root.unwrap()
  guard admission.frames.pop() is Some(frame) else { fail(root, WrongType) }
  match frame {
    ReadJson(cursor, depth, root) => {
      reserve(cursor, 1, budget)
      if @decode.is_null(cursor) {
        if root {
          fail(cursor, UnexpectedNull)
        }
        admission.value = Some(Null)
      } else if @decode.array_length(cursor) is Some(count) {
        if depth >= budget.max_depth || count > budget.nodes {
          fail(cursor, BudgetExceeded)
        }
        guard prepare_array_value(count) is Some(builder) else {
          fail(cursor, BudgetExceeded)
        }
        admission.value = None
        admission.frames.push(ArrayNext(cursor, builder, 0, depth + 1))
      } else if @decode.object_length(cursor) is Some(count) {
        if depth >= budget.max_depth || count > budget.nodes {
          fail(cursor, BudgetExceeded)
        }
        admission.value = None
        admission.frames.push(ObjectKeys(cursor, [], 0, depth + 1))
      } else {
        admission.value = Some(
          match @decode.view(cursor) {
            @decode.BoolValue(value) => Boolean(value)
            @decode.NumberValue(_) => Number(number(cursor))
            @decode.TextValue(text) => {
              ignore(text_size(text, cursor, budget))
              Text(text)
            }
            _ => fail(cursor, WrongType)
          },
        )
      }
    }
    ArrayNext(cursor, builder, index, depth) =>
      if @decode.element_at(cursor, index) is Some(child) {
        admission.frames.push(ArrayNext(cursor, builder, index + 1, depth))
        admission.frames.push(ArrayAppend(builder))
        admission.frames.push(ReadJson(child, depth, false))
      } else {
        admission.value = finish_array_value(builder)
        if admission.value is None {
          fail(cursor, BudgetExceeded)
        }
      }
    ObjectKeys(cursor, keys, index, depth) =>
      if @decode.field_at(cursor, index) is Some((name, child)) {
        ignore(text_size(name, child, budget, identifier=true)) catch {
          Abort(ValueIssue(kind, ..)) =>
            raise Abort(
              ValueIssue(
                kind,
                path=@decode.cursor_path(child),
                span=@decode.cursor_key_span(child).unwrap_or(
                  @decode.cursor_span(child),
                ),
              ),
            )
          error => raise error
        }
        keys.push([name])
        admission.frames.push(ObjectKeys(cursor, keys, index + 1, depth))
      } else {
        if keys.length() > 1073741823 {
          fail(cursor, BudgetExceeded)
        }
        let sort = match @sort.prepare_deferred(keys, keys.length() * 2) {
          Ok(sort) => sort
          Err(_) => fail(cursor, BudgetExceeded)
        }
        admission.frames.push(ObjectSort(cursor, sort, depth))
      }
    ObjectSort(cursor, sort, depth) =>
      match @sort.advance(sort, 1) {
        Ok(@sort.Continue(..)) =>
          admission.frames.push(ObjectSort(cursor, sort, depth))
        Ok(@sort.Complete(..)) => {
          guard @decode.object_length(cursor) is Some(count) &&
            prepare_object_value(count) is Some(builder) else {
            fail(cursor, BudgetExceeded)
          }
          admission.frames.push(ObjectNext(cursor, sort, builder, 0, depth))
        }
        Err(_) => fail(cursor, BudgetExceeded)
      }
    ObjectNext(cursor, sort, builder, index, depth) =>
      if @sort.index_at(sort, index) is Some(source_index) {
        guard @decode.field_at(cursor, source_index) is Some((name, child)) else {
          fail(cursor, WrongType)
        }
        admission.frames.push(
          ObjectNext(cursor, sort, builder, index + 1, depth),
        )
        admission.frames.push(ObjectAppend(builder, name))
        admission.frames.push(ReadJson(child, depth, false))
      } else {
        @sort.cleanup(sort) |> ignore
        admission.value = finish_object_value(builder)
        if admission.value is None {
          fail(cursor, BudgetExceeded)
        }
      }
    ArrayAppend(builder) => {
      guard admission.value is Some(value) && append_array_item(builder, value) else {
        fail(root, BudgetExceeded)
      }
      admission.value = None
    }
    ObjectAppend(builder, name) => {
      guard admission.value is Some(value) &&
        append_object_field(builder, name, value) else {
        fail(root, BudgetExceeded)
      }
      admission.value = None
    }
  }
}

///|
/// One value node, field, bounded sort step, append or container completion.
pub fn advance_json_admission(admission : JsonAdmission) -> JsonAdmissionPoll {
  if admission.terminal {
    return JsonAdmissionTerminal
  }
  admission.step() catch {
    Abort(issue) => {
      cancel_json_admission(admission)
      return JsonAdmissionFailed(issue)
    }
  }
  if admission.frames.is_empty() {
    let root = admission.root.unwrap()
    guard admission.value is Some(value) else {
      cancel_json_admission(admission)
      return JsonAdmissionFailed(
        ValueIssue(
          WrongType,
          path=@decode.cursor_path(root),
          span=@decode.cursor_span(root),
        ),
      )
    }
    admission.value = None
    admission.root = None
    admission.terminal = true
    JsonAdmissionComplete(
      { value, contract: @contract.primitive(JsonType, nullable=false), },
      admission.limits.max_nodes - admission.budget.nodes,
      admission.limits.max_text_bytes - admission.budget.text,
    )
  } else {
    JsonAdmissionContinue
  }
}

///|
pub fn cancel_json_admission(admission : JsonAdmission) -> Unit {
  for frame in admission.frames {
    match frame {
      ArrayNext(_, builder, _, _) | ArrayAppend(builder) =>
        cancel_array_value(builder) |> ignore
      ObjectNext(_, sort, builder, _, _) => {
        @sort.cleanup(sort) |> ignore
        cancel_object_value(builder) |> ignore
      }
      ObjectAppend(builder, _) => cancel_object_value(builder) |> ignore
      ObjectSort(_, sort, _) => @sort.cleanup(sort) |> ignore
      ObjectKeys(_, keys, _, _) => keys.clear()
      ReadJson(_, _, _) => ()
    }
  }
  admission.frames.clear()
  admission.value = None
  admission.root = None
  admission.terminal = true
}
