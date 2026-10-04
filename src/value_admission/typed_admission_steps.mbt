///|
priv struct TypedObjectAdmission {
  source : @decode.Cursor
  fields : @contract.Fields
  children : Map[String, @decode.Cursor]
  depth : Int
}

///|
priv enum TypedAdmissionFrame {
  ReadTyped(@decode.Cursor, @contract.Contract, Int, Bool)
  TypedArrayNext(@decode.Cursor, @contract.Contract, ArrayBuilder, Int, Int)
  TypedObjectInput(TypedObjectAdmission, Int)
  TypedObjectFind(TypedObjectAdmission, Int, String, @decode.Cursor, Int, Int)
  TypedObjectNames(TypedObjectAdmission, Int)
  TypedObjectNext(TypedObjectAdmission, ObjectBuilder, Int)
  TypedVectorNext(@decode.Cursor, VectorBuilder, Int)
  TypedJson(JsonAdmission, @decode.Cursor)
  TypedArrayAppend(ArrayBuilder)
  TypedObjectAppend(ObjectBuilder, String)
}

///|
/// Resumed typed data admission in the existing Value owner. A checked result
/// is exposed only after all fields, children and budgets are admitted. Like
/// ordinary admit_usage, this entry has no reference issuance authority.
struct TypedAdmission {
  contract : @contract.Contract
  limits : Limits
  budget : Budget
  mut root : @decode.Cursor?
  frames : Array[TypedAdmissionFrame]
  mut value : Value?
  mut terminal : Bool
}

///|
pub enum TypedAdmissionPoll {
  TypedAdmissionContinue
  TypedAdmissionComplete(CheckedValue, Int, Int)
  TypedAdmissionFailed(Issue)
  TypedAdmissionTerminal
}

///|
pub fn start_typed_admission(
  contract : @contract.Contract,
  root : @decode.Cursor,
  limits : Limits,
) -> Result[TypedAdmission, Issue] {
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
    contract,
    limits,
    budget: {
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      max_depth: limits.max_depth,
    },
    root: Some(root),
    frames: [ReadTyped(root, contract, 0, false)],
    value: None,
    terminal: false,
  })
}

///|
fn typed_object_issue(
  cursor : @decode.Cursor,
  kind : @decode.IssueKind,
  name? : String,
) -> Unit raise Abort {
  let path = @decode.cursor_path(cursor)
  if name is Some(name) {
    path.push(Key(name))
  }
  let span = if kind == @decode.UnknownField || kind == @decode.DuplicateField {
    @decode.cursor_key_span(cursor).unwrap_or(@decode.cursor_span(cursor))
  } else {
    @decode.cursor_span(cursor)
  }
  raise Abort(Decode({ kind, path, span, }))
}

///|
fn TypedAdmission::step(admission : TypedAdmission) -> Unit raise Abort {
  let budget = admission.budget
  let root = admission.root.unwrap()
  guard admission.frames.pop() is Some(frame) else { fail(root, WrongType) }
  match frame {
    ReadTyped(cursor, contract, parent_depth, reserved) => {
      if !reserved {
        reserve(cursor, 1, budget)
      }
      if @decode.is_null(cursor) {
        if !contract.nullable {
          fail(cursor, UnexpectedNull)
        }
        admission.value = Some(Null)
        return
      }
      let container = @decode.array_length(cursor) is Some(_) ||
        @decode.object_length(cursor) is Some(_)
      if container && parent_depth >= budget.max_depth {
        fail(cursor, BudgetExceeded)
      }
      let depth = parent_depth + (if container { 1 } else { 0 })
      match contract.shape {
        @contract.Array(item, max_items~) => {
          guard @decode.array_length(cursor) is Some(count) else {
            typed_object_issue(cursor, @decode.WrongType)
          }
          if max_items is Some(limit) && count.to_int64() > limit {
            fail(cursor, ArrayConstraint)
          }
          reserve(cursor, count, budget)
          guard prepare_array_value(count) is Some(builder) else {
            fail(cursor, BudgetExceeded)
          }
          admission.value = None
          admission.frames.push(TypedArrayNext(cursor, item, builder, 0, depth))
        }
        @contract.Object(fields) => {
          if @decode.object_length(cursor) is None {
            typed_object_issue(cursor, @decode.WrongType)
          }
          let object : TypedObjectAdmission = {
            source: cursor,
            fields,
            children: Map([]),
            depth,
          }
          admission.value = None
          admission.frames.push(TypedObjectInput(object, 0))
        }
        @contract.Vector(dimensions~) => {
          guard @decode.array_length(cursor) is Some(count) else {
            typed_object_issue(cursor, @decode.WrongType)
          }
          if count.to_double() != dimensions {
            fail(cursor, VectorDimension)
          }
          reserve(cursor, count, budget)
          guard prepare_vector_value(count) is Some(builder) else {
            fail(cursor, VectorDimension)
          }
          admission.value = None
          admission.frames.push(TypedVectorNext(cursor, builder, 0))
        }
        @contract.Json => {
          // The root was charged by this typed read; the shared JSON owner
          // consumes that same node rather than reserving it a second time.
          let json = match
            start_json_admission(cursor, {
              max_nodes: budget.nodes + 1,
              max_depth: budget.max_depth - parent_depth,
              max_text_bytes: budget.text,
            }) {
            Ok(json) => json
            Err(issue) => raise Abort(issue)
          }
          admission.value = None
          admission.frames.push(TypedJson(json, cursor))
        }
        @contract.ResourceRef(_) | @contract.ArtifactRef(_) =>
          fail(cursor, UnsupportedReference)
        shape => admission.value = Some(read_scalar(cursor, shape, budget))
      }
    }
    TypedArrayNext(cursor, item, builder, index, depth) =>
      if @decode.element_at(cursor, index) is Some(child) {
        admission.frames.push(
          TypedArrayNext(cursor, item, builder, index + 1, depth),
        )
        admission.frames.push(TypedArrayAppend(builder))
        admission.frames.push(ReadTyped(child, item, depth, true))
      } else {
        admission.value = finish_array_value(builder)
        if admission.value is None {
          fail(cursor, BudgetExceeded)
        }
      }
    TypedObjectInput(object, index) =>
      if @decode.field_at(object.source, index) is Some((name, child)) {
        // Contracts already keep fields in canonical name order. Resume a
        // binary lookup instead of copying the entire admitted schema into a
        // second name map before the value's child-node budget is checked.
        admission.frames.push(
          TypedObjectFind(
            object,
            index,
            name,
            child,
            0,
            @contract.field_count(object.fields),
          ),
        )
      } else {
        reserve(object.source, @contract.field_count(object.fields), budget)
        admission.frames.push(TypedObjectNames(object, 0))
      }
    TypedObjectFind(object, index, name, child, low, high) => {
      if low >= high {
        typed_object_issue(child, @decode.UnknownField)
      }
      let middle = low + (high - low) / 2
      let field = @contract.field_at(object.fields, middle).unwrap()
      let order = @canonical.compare_utf16(name, field.name)
      if order < 0 {
        admission.frames.push(
          TypedObjectFind(object, index, name, child, low, middle),
        )
      } else if order > 0 {
        admission.frames.push(
          TypedObjectFind(object, index, name, child, middle + 1, high),
        )
      } else {
        if object.children.contains(name) {
          typed_object_issue(child, @decode.DuplicateField)
        }
        object.children[name] = child
        admission.frames.push(TypedObjectInput(object, index + 1))
      }
    }
    TypedObjectNames(object, index) =>
      if @contract.field_at(object.fields, index) is Some(field) {
        guard object.children.get(field.name) is Some(child) else {
          typed_object_issue(
            object.source,
            @decode.MissingField,
            name=field.name,
          )
        }
        cursor_key_text(field.name, child, budget)
        admission.frames.push(TypedObjectNames(object, index + 1))
      } else {
        guard prepare_object_value(@contract.field_count(object.fields))
          is Some(builder) else {
          fail(object.source, BudgetExceeded)
        }
        admission.frames.push(TypedObjectNext(object, builder, 0))
      }
    TypedObjectNext(object, builder, index) =>
      if @contract.field_at(object.fields, index) is Some(field) {
        let child = object.children.get(field.name).unwrap()
        admission.frames.push(TypedObjectNext(object, builder, index + 1))
        admission.frames.push(TypedObjectAppend(builder, field.name))
        admission.frames.push(
          ReadTyped(child, field.contract, object.depth, true),
        )
      } else {
        admission.value = finish_object_value(builder)
        if admission.value is None {
          fail(object.source, BudgetExceeded)
        }
        object.children.clear()
      }
    TypedVectorNext(cursor, builder, index) =>
      if @decode.element_at(cursor, index) is Some(child) {
        if !append_vector_component(builder, number(child)) {
          fail(child, InvalidNumber)
        }
        admission.frames.push(TypedVectorNext(cursor, builder, index + 1))
      } else {
        admission.value = finish_vector_value(builder)
        if admission.value is None {
          fail(cursor, VectorDimension)
        }
      }
    TypedJson(json, cursor) =>
      match advance_json_admission(json) {
        JsonAdmissionContinue => admission.frames.push(TypedJson(json, cursor))
        JsonAdmissionComplete(checked, nodes, text) => {
          if nodes < 1 || nodes - 1 > budget.nodes || text > budget.text {
            fail(cursor, BudgetExceeded)
          }
          budget.nodes -= nodes - 1
          budget.text -= text
          admission.value = Some(checked.value)
        }
        JsonAdmissionFailed(issue) => raise Abort(issue)
        JsonAdmissionTerminal => fail(cursor, WrongType)
      }
    TypedArrayAppend(builder) => {
      guard admission.value is Some(value) && append_array_item(builder, value) else {
        fail(root, BudgetExceeded)
      }
      admission.value = None
    }
    TypedObjectAppend(builder, name) => {
      guard admission.value is Some(value) &&
        append_object_field(builder, name, value) else {
        fail(root, BudgetExceeded)
      }
      admission.value = None
    }
  }
}

///|
/// One typed read, indexed name lookup, name check, shared JSON step, append or
/// container completion. Complete usage counts value nodes and UTF-8 text, not
/// the number of resumed transitions; callers account each transition as work.
pub fn advance_typed_admission(
  admission : TypedAdmission,
) -> TypedAdmissionPoll {
  if admission.terminal {
    return TypedAdmissionTerminal
  }
  admission.step() catch {
    Abort(issue) => {
      cancel_typed_admission(admission)
      return TypedAdmissionFailed(issue)
    }
  }
  if admission.frames.is_empty() {
    guard admission.value is Some(value) else {
      let root = admission.root.unwrap()
      let issue = ValueIssue(
        WrongType,
        path=@decode.cursor_path(root),
        span=@decode.cursor_span(root),
      )
      cancel_typed_admission(admission)
      return TypedAdmissionFailed(issue)
    }
    admission.root = None
    admission.value = None
    admission.terminal = true
    TypedAdmissionComplete(
      { contract: admission.contract, value, },
      admission.limits.max_nodes - admission.budget.nodes,
      admission.limits.max_text_bytes - admission.budget.text,
    )
  } else {
    TypedAdmissionContinue
  }
}

///|
pub fn cancel_typed_admission(admission : TypedAdmission) -> Unit {
  for frame in admission.frames {
    match frame {
      TypedArrayNext(_, _, builder, _, _) | TypedArrayAppend(builder) =>
        cancel_array_value(builder) |> ignore
      TypedObjectNext(object, builder, _) => {
        object.children.clear()
        cancel_object_value(builder) |> ignore
      }
      TypedObjectInput(object, _)
      | TypedObjectFind(object, _, _, _, _, _)
      | TypedObjectNames(object, _) => object.children.clear()
      TypedObjectAppend(builder, _) => cancel_object_value(builder) |> ignore
      TypedVectorNext(_, builder, _) => cancel_vector_value(builder) |> ignore
      TypedJson(json, _) => cancel_json_admission(json)
      ReadTyped(_, _, _, _) => ()
    }
  }
  admission.frames.clear()
  admission.root = None
  admission.value = None
  admission.terminal = true
}
