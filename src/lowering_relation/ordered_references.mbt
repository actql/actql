///|
/// Bound occurrence evidence, not a caller-supplied reference table.
struct OrderedReferences {
  kernel : PreparedKernel
  entries : Array[OrderedReference]
}

///|
pub struct OrderedReference {
  at : String
  target : @relation.ReferenceTarget
}

///|
pub(all) struct OrderedReferenceLimits {
  max_references : Int
  max_pointer_bytes : Int
  max_work : Int
  max_frames : Int
}

///|
pub(all) enum OrderedReferenceIssue {
  NotOrderedKernel
  InvalidReferenceLimits
  ReferenceLimit
}

///|
priv enum ReferenceFrame {
  Visit(Expression, String)
  Children(Array[Expression], Int, String)
  Clauses(Array[(Expression, Expression)], Int, String)
  ObjectFields(Array[(String, Expression)], Int, String)
}

///|
pub fn ordered_reference_kernel(index : OrderedReferences) -> PreparedKernel {
  index.kernel
}

///|
pub fn ordered_reference_count(index : OrderedReferences) -> Int {
  index.entries.length()
}

///|
pub fn ordered_reference_at(
  index : OrderedReferences,
  i : Int,
) -> OrderedReference? {
  index.entries.get(i)
}

///|
/// Traverses the typed machine expression in semantic preorder, not emitter
/// object-key order. Literal values are opaque. Work includes every constructed
/// pointer byte; continuations keep wide expressions from filling the stack.
pub fn prepare_ordered_references(
  kernel : PreparedKernel,
  limits : OrderedReferenceLimits,
) -> Result[OrderedReferences, OrderedReferenceIssue] {
  if limits.max_references < 0 ||
    limits.max_pointer_bytes < 0 ||
    limits.max_work < 0 ||
    limits.max_frames < 0 {
    return Err(InvalidReferenceLimits)
  }
  guard kernel.body is OrderedBindings(bindings) else {
    return Err(NotOrderedKernel)
  }
  let entries : Array[OrderedReference] = []
  let pending : Array[ReferenceFrame] = []
  let mut work = limits.max_work
  let mut bytes = limits.max_pointer_bytes
  // Object field segments may be Unicode; charge actual UTF-8 pointer bytes.
  fn append_path(base : String, suffix : String) -> String? {
    guard @scalar.admit_utf8_length(base, work) is Ok(base_bytes) &&
      @scalar.admit_utf8_length(suffix, work - base_bytes) is Ok(suffix_bytes) else {
      return None
    }
    work -= base_bytes + suffix_bytes
    Some(base + suffix)
  }
  fn field_segment(name : String) -> String? {
    guard @scalar.admit_utf8_length(name, work / 2) is Ok(size) else {
      return None
    }
    work -= size * 2
    let builder = StringBuilder()
    for ch in name.to_array() {
      if ch == '~' {
        builder.write_string("~0")
      } else if ch == '/' {
        builder.write_string("~1")
      } else {
        builder.write_char(ch)
      }
    }
    Some(builder.to_string())
  }
  fn push(frame : ReferenceFrame) -> Bool {
    if pending.length() >= limits.max_frames {
      return false
    }
    pending.push(frame)
    true
  }
  for binding_index = 0
      binding_index < bindings.length()
      binding_index = binding_index + 1 {
    guard append_path("/bindings/", binding_index.to_string() + "/expr")
      is Some(pointer) else {
      return Err(ReferenceLimit)
    }
    if !push(Visit(bindings[binding_index].1, pointer)) {
      return Err(ReferenceLimit)
    }
    while pending.pop() is Some(frame) {
      if work == 0 {
        return Err(ReferenceLimit)
      }
      work -= 1
      match frame {
        Visit(expr, path) =>
          match expr.body {
            Field(_, target) => {
              if entries.length() == limits.max_references ||
                @scalar.admit_utf8_length(path, bytes) is Err(_) {
                return Err(ReferenceLimit)
              }
              bytes -= @scalar.admit_utf8_length(path, bytes).unwrap()
              entries.push({ at: path, target, })
            }
            Literal(_) | TypedNull => ()
            Property(child, _, _) | Cast(child) => {
              guard append_path(path, "/body/value") is Some(child_path) else {
                return Err(ReferenceLimit)
              }
              if !push(Visit(child, child_path)) {
                return Err(ReferenceLimit)
              }
            }
            Object(fields) => {
              guard append_path(path, "/body") is Some(body) else {
                return Err(ReferenceLimit)
              }
              if !push(ObjectFields(fields, 0, body)) {
                return Err(ReferenceLimit)
              }
            }
            Unary(_, child) => {
              guard append_path(path, "/body") is Some(child_path) else {
                return Err(ReferenceLimit)
              }
              if !push(Visit(child, child_path)) {
                return Err(ReferenceLimit)
              }
            }
            Binary(_, left, right) => {
              guard append_path(path, "/body") is Some(body) else {
                return Err(ReferenceLimit)
              }
              if !push(Children([left, right], 0, body)) {
                return Err(ReferenceLimit)
              }
            }
            VectorScore(_, left, right) => {
              guard append_path(path, "/body/right") is Some(right_path) &&
                append_path(path, "/body/left") is Some(left_path) else {
                return Err(ReferenceLimit)
              }
              if !push(Visit(right, right_path)) ||
                !push(Visit(left, left_path)) {
                return Err(ReferenceLimit)
              }
            }
            VectorConcat(children) => {
              guard append_path(path, "/body") is Some(body) else {
                return Err(ReferenceLimit)
              }
              if !push(Children(children, 0, body)) {
                return Err(ReferenceLimit)
              }
            }
            Many(_, children) => {
              guard append_path(path, "/body") is Some(body) else {
                return Err(ReferenceLimit)
              }
              if !push(Children(children, 0, body)) {
                return Err(ReferenceLimit)
              }
            }
            Conditional(condition, yes, no) => {
              guard append_path(path, "/body") is Some(body) else {
                return Err(ReferenceLimit)
              }
              if !push(Children([condition, yes, no], 0, body)) {
                return Err(ReferenceLimit)
              }
            }
            Case(clauses, otherwise) => {
              guard append_path(path, "/body/else") is Some(else_path) else {
                return Err(ReferenceLimit)
              }
              guard append_path(path, "/body/when") is Some(when_path) else {
                return Err(ReferenceLimit)
              }
              if !push(Visit(otherwise, else_path)) ||
                !push(Clauses(clauses, 0, when_path)) {
                return Err(ReferenceLimit)
              }
            }
          }
        Children(children, i, path) =>
          if children.get(i) is Some(child) {
            guard append_path(path, "/" + i.to_string()) is Some(child_path) else {
              return Err(ReferenceLimit)
            }
            if !push(Children(children, i + 1, path)) ||
              !push(Visit(child, child_path)) {
              return Err(ReferenceLimit)
            }
          }
        ObjectFields(fields, i, path) =>
          if fields.get(i) is Some((name, child)) {
            guard field_segment(name) is Some(segment) &&
              append_path(path, "/" + segment) is Some(child_path) else {
              return Err(ReferenceLimit)
            }
            if !push(ObjectFields(fields, i + 1, path)) ||
              !push(Visit(child, child_path)) {
              return Err(ReferenceLimit)
            }
          }
        Clauses(clauses, i, path) =>
          if clauses.get(i) is Some((condition, then_)) {
            guard append_path(path, "/" + i.to_string()) is Some(clause_path) else {
              return Err(ReferenceLimit)
            }
            guard append_path(clause_path, "/then") is Some(then_path) else {
              return Err(ReferenceLimit)
            }
            guard append_path(clause_path, "/when") is Some(when_path) else {
              return Err(ReferenceLimit)
            }
            if !push(Clauses(clauses, i + 1, path)) ||
              !push(Visit(then_, then_path)) ||
              !push(Visit(condition, when_path)) {
              return Err(ReferenceLimit)
            }
          }
      }
    }
  }
  Ok({ kernel, entries, })
}

///|
/// Emits only the occurrence array; this does not establish evidence closure.
pub fn emit_ordered_references(
  index : OrderedReferences,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(out)
  for entry in index.entries {
    @encode.begin_object(out)
    @encode.key(out, "at")
    @encode.string_value(out, entry.at)
    @encode.key(out, "target")
    @encode.begin_object(out)
    match entry.target {
      @relation.InputField(name) => {
        @encode.key(out, "input_field")
        @encode.string_value(out, @schema.reference_name(name))
      }
      @relation.PriorSlot(i) => {
        @encode.key(out, "prior_slot")
        @encode.number_value(out, i.to_double())
      }
    }
    @encode.end_object(out)
    @encode.end_object(out)
  }
  @encode.end_array(out)
}
