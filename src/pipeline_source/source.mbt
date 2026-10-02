///|
pub(all) enum Issue {
  InvalidLimits
  WorkLimit
  InvalidOrigin
  NonCanonicalText
  InvalidNumber
} derive(Eq, Debug)

///|
struct Steps {
  owner : @collection.Collected
  source : @decode.Cursor
  expressions : Map[Int, @expression.Expression]
  annotations : Map[Int, Bool]
  identifiers : Map[Int, String]
  work : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
priv struct Budget {
  mut remaining : Int
}

///|
fn spend(b : Budget, n : Int) -> Unit raise Stop {
  if n > b.remaining {
    raise Stop(WorkLimit)
  }
  b.remaining -= n
}

///|
fn text(
  b : Budget,
  value : String,
  identifier? : Bool = false,
) -> Unit raise Stop {
  spend(b, value.length())
  if identifier && @canonical.normalize_nfc_lf(value) != Ok(value) {
    raise Stop(NonCanonicalText)
  }
}

///|
/// Prepare the exact collected pipeline's decoded source steps. Only whole
/// grammar-owned expression roots are replaced, and only Step.meta is omitted.
/// This is not completion, lowering or a complete stage semantic envelope.
pub fn prepare(
  owner : @collection.Collected,
  max_work~ : Int,
) -> Result[Steps, Issue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let b : Budget = { remaining: max_work, }
  let source = @pipeline.source(@collection.pipeline(owner))
  let expressions : Map[Int, @expression.Expression] = Map([])
  let annotations : Map[Int, Bool] = Map([])
  let identifiers : Map[Int, String] = Map([])
  try {
    let slots = @collection.expressions(owner)
    spend(b, @pipeline.expression_slot_count(slots))
    for i in 0..<@pipeline.expression_slot_count(slots) {
      let expression = @typing.expression(
        @pipeline.expression_slot_at(slots, i).unwrap().expression,
      )
      let location = match
        @expression.origin(expression, @expression.tree(expression)) {
        Some(v) => v
        None => raise Stop(InvalidOrigin)
      }
      let index = match @decode.tree_index(source, location.source) {
        Some(i) => i
        None => raise Stop(InvalidOrigin)
      }
      if expressions.contains(index) {
        raise Stop(InvalidOrigin)
      }
      expressions[index] = expression
    }
    let count = @decode.array_length(source).unwrap()
    spend(b, count)
    for i in 0..<count {
      let step = @decode.element_at(source, i).unwrap()
      let fields = @decode.object_length(step).unwrap()
      spend(b, fields)
      for j in 0..<fields {
        let (name, child) = @decode.field_at(step, j).unwrap()
        if name == "meta" {
          annotations[@decode.tree_index(source, child).unwrap()] = true
        } else if name == "from" || name == "as" {
          // Only grammar-owned producer names; Values rows and literal strings
          // are not identifier positions.
          if @decode.text(child) is Ok(raw) {
            match @canonical.normalize_nfc_lf(raw) {
              Ok(value) =>
                identifiers[@decode.tree_index(source, child).unwrap()] = value
              Err(_) => raise Stop(NonCanonicalText)
            }
          }
        }
      }
    }
    let pending = [source]
    let mut replaced = 0
    while pending.pop() is Some(cursor) {
      spend(b, 1)
      let index = @decode.tree_index(source, cursor).unwrap()
      if annotations.contains(index) {
        continue
      }
      if expressions.contains(index) {
        replaced += 1
        continue
      }
      if @decode.array_length(cursor) is Some(n) {
        spend(b, n)
        for i in 0..<n {
          pending.push(@decode.element_at(cursor, i).unwrap())
        }
      } else if @decode.object_length(cursor) is Some(n) {
        spend(b, n)
        for i in 0..<n {
          let (name, child) = @decode.field_at(cursor, i).unwrap()
          text(b, name, identifier=true)
          pending.push(child)
        }
      } else {
        match @decode.view(cursor) {
          @decode.TextValue(v) => text(b, v)
          @decode.NumberValue(v) =>
            if v.is_nan() || v.is_inf() || (v == 0.0 && 1.0 / v < 0.0) {
              raise Stop(InvalidNumber)
            }
          _ => ()
        }
      }
    }
    if replaced != expressions.length() {
      raise Stop(InvalidOrigin)
    }
    Ok({
      owner,
      source,
      expressions,
      annotations,
      identifiers,
      work: max_work - b.remaining,
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
priv enum Frame {
  Value(@decode.Cursor)
  ArrayRest(@decode.Cursor, Int, Int)
  ObjectRest(Array[(String, @decode.Cursor)], Int)
}

///|
pub fn emit(
  steps : Steps,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let pending : Array[Frame] = [Value(steps.source)]
  while pending.pop() is Some(frame) {
    match frame {
      Value(cursor) => {
        let index = @decode.tree_index(steps.source, cursor).unwrap()
        if steps.expressions.get(index) is Some(expression) {
          @expression.emit_source(expression, writer)
        } else if steps.identifiers.get(index) is Some(identifier) {
          @encode.string_value(writer, identifier)
        } else if @decode.array_length(cursor) is Some(n) {
          @encode.begin_array(writer)
          pending.push(ArrayRest(cursor, 0, n))
        } else if @decode.object_length(cursor) is Some(n) {
          @encode.begin_object(writer)
          let fields = []
          for i in 0..<n {
            let field = @decode.field_at(cursor, i).unwrap()
            if !steps.annotations.contains(
                @decode.tree_index(steps.source, field.1).unwrap(),
              ) {
              fields.push(field)
            }
          }
          fields.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
          pending.push(ObjectRest(fields, 0))
        } else {
          match @decode.view(cursor) {
            @decode.NullValue => @encode.null_value(writer)
            @decode.BoolValue(v) => @encode.bool_value(writer, v)
            @decode.NumberValue(v) => @encode.number_value(writer, v)
            @decode.TextValue(v) => @encode.string_value(writer, v)
            _ => raise @encode.InvalidStructure
          }
        }
      }
      ArrayRest(cursor, i, n) =>
        if i == n {
          @encode.end_array(writer)
        } else {
          pending.push(ArrayRest(cursor, i + 1, n))
          pending.push(Value(@decode.element_at(cursor, i).unwrap()))
        }
      ObjectRest(fields, i) =>
        if i == fields.length() {
          @encode.end_object(writer)
        } else {
          let (name, child) = fields[i]
          @encode.key(writer, name)
          pending.push(ObjectRest(fields, i + 1))
          pending.push(Value(child))
        }
    }
  }
}

///|
pub fn collection(steps : Steps) -> @collection.Collected {
  steps.owner
}

///|
pub fn work(steps : Steps) -> Int {
  steps.work
}
