///|
fn[T] invalid(cursor : @decode.Cursor, kind : IssueKind) -> T raise Abort {
  raise Abort(
    ParameterIssue(
      kind,
      path=@decode.cursor_path(cursor),
      span=@decode.cursor_span(cursor),
    ),
  )
}

///|
fn[T] decoded(result : Result[T, @decode.Issue]) -> T raise Abort {
  match result {
    Ok(value) => value
    Err(issue) => raise Abort(Decode(issue))
  }
}

///|
fn charge_text(
  text : String,
  cursor : @decode.Cursor,
  budget : Budget,
  identifier? : Bool = false,
) -> Unit raise Abort {
  match @scalar.admit_utf8_length(text, budget.text) {
    Ok(size) => budget.text -= size
    Err(@scalar.MalformedUtf16(_)) => invalid(cursor, InvalidUnicode)
    Err(_) => invalid(cursor, BudgetExceeded)
  }
  if identifier {
    match @canonical.normalize_nfc_lf(text) {
      Ok(normalized) =>
        if normalized != text {
          invalid(cursor, NonCanonicalText)
        }
      Err(_) => invalid(cursor, InvalidUnicode)
    }
  }
}

///|
fn charge_key(
  key : String,
  child : @decode.Cursor,
  budget : Budget,
) -> Unit raise Abort {
  charge_text(key, child, budget, identifier=true) catch {
    Abort(ParameterIssue(kind, path~, ..)) =>
      raise Abort(
        ParameterIssue(
          kind,
          path~,
          span=@decode.cursor_key_span(child).unwrap_or(
            @decode.cursor_span(child),
          ),
        ),
      )
    error => raise error
  }
}

///|
// Full source-tree accounting bounds the sum of declarations, defaults and meta,
// not just each independently admitted type. Input cursors are already owned.
fn preflight(root : @decode.Cursor, budget : Budget) -> Unit raise Abort {
  if budget.nodes == 0 {
    invalid(root, BudgetExceeded)
  }
  budget.nodes -= 1
  let work : Array[(@decode.Cursor, Int)] = [(root, 0)]
  while !work.is_empty() {
    let (cursor, parent_depth) = work.pop().unwrap()
    let array = @decode.array_length(cursor)
    let object = @decode.object_length(cursor)
    let container = array is Some(_) || object is Some(_)
    if container && parent_depth >= budget.depth {
      invalid(cursor, BudgetExceeded)
    }
    let depth = parent_depth + (if container { 1 } else { 0 })
    if array is Some(count) {
      if count > budget.nodes {
        invalid(cursor, BudgetExceeded)
      }
      budget.nodes -= count
      for index = count - 1; index >= 0; index = index - 1 {
        work.push((@decode.element_at(cursor, index).unwrap(), depth))
      }
    } else if object is Some(count) {
      if count > budget.nodes {
        invalid(cursor, BudgetExceeded)
      }
      budget.nodes -= count
      // Charge every original key before visiting children, in source order.
      // Immutable admission already owns exact child/key spans; no detached
      // names array, ObjectView/Map or closed-object recheck is needed here.
      for index in 0..<count {
        let (name, child) = @decode.field_at(cursor, index).unwrap()
        charge_key(name, child, budget)
      }
      for index = count - 1; index >= 0; index = index - 1 {
        work.push((@decode.field_at(cursor, index).unwrap().1, depth))
      }
    } else {
      // Container branches returned above. This original scalar view never
      // copies child Cursors, names or field Maps before a budget refusal.
      match @decode.view(cursor) {
        @decode.NullValue | @decode.BoolValue(_) => ()
        @decode.NumberValue(n) =>
          if @scalar.read_finite_number(n) is None ||
            (n == 0.0 && 1.0 / n < 0.0) {
            invalid(cursor, InvalidNumber)
          }
        @decode.TextValue(text) => charge_text(text, cursor, budget)
        _ => abort("immutable scalar cursor changed kind")
      }
    }
  }
}

///|
fn valid_name(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  for index = 0; index < name.length(); index = index + 1 {
    let c = name[index].to_int()
    if !(c == 95 ||
      (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (index > 0 && c >= 48 && c <= 57)) {
      return false
    }
  }
  true
}

///|
fn metadata(cursor : @decode.Cursor) -> Unit raise Abort {
  ignore(decoded(@decode.open_object(cursor)))
  let names = decoded(@decode.object_field_names(cursor))
  if names.is_empty() {
    invalid(cursor, InvalidMetadata)
  }
  for name in names {
    if name.has_prefix("actql_") {
      match @decode.closed_object(cursor, names.filter(n => n != name)) {
        Err(issue) =>
          raise Abort(
            ParameterIssue(
              ReservedMetadataKey,
              path=issue.path,
              span=issue.span,
            ),
          )
        Ok(_) => invalid(cursor, ReservedMetadataKey)
      }
    }
  }
}

///|
// Called only after value_admission validated the complete value tree.
fn constraints(
  root : @decode.Cursor,
  parameter : @contract.ParameterType,
) -> Unit raise Abort {
  let work : Array[(@decode.Cursor, @contract.ParameterType)] = [
    (root, parameter),
  ]
  while !work.is_empty() {
    let (cursor, parameter) = work.pop().unwrap()
    if @decode.is_null(cursor) {
      continue
    }
    match parameter.rule {
      @contract.Plain => ()
      @contract.Numeric(integer~, minimum~, maximum~) => {
        let n = decoded(@decode.finite_number(cursor))
        if (integer && @scalar.read_integer_number(n) is None) ||
          (minimum is Some(low) && n < low) ||
          (maximum is Some(high) && n > high) {
          invalid(cursor, NumericConstraint)
        }
      }
      @contract.Duration =>
        if @scalar.read_duration_ms(decoded(@decode.text(cursor))) is None {
          invalid(cursor, DurationConstraint)
        }
      @contract.Items(item, length~) => {
        let items = decoded(@decode.elements(cursor))
        if length is Some(n) && items.length().to_int64() != n {
          invalid(cursor, LengthConstraint)
        }
        for index = items.length() - 1; index >= 0; index = index - 1 {
          work.push((items[index], item))
        }
      }
      @contract.Properties(fields) => {
        let fields = @contract.parameter_fields(fields)
        let object = decoded(@decode.open_object(cursor))
        for index = fields.length() - 1; index >= 0; index = index - 1 {
          let (name, child) = fields[index]
          work.push((@decode.lookup(object, name).unwrap(), child))
        }
      }
    }
  }
}

///|
fn check_value(
  cursor : @decode.Cursor,
  parameter : @contract.ParameterType,
  limits : @value.Limits,
) -> @value.CheckedValue raise Abort {
  check_value_usage(cursor, parameter, limits).0
}

///|
// Preserve the original admission's measured usage without another Value
// read. Constraints run in the same order and failures expose no measurement.
fn check_value_usage(
  cursor : @decode.Cursor,
  parameter : @contract.ParameterType,
  limits : @value.Limits,
) -> (@value.CheckedValue, Int, Int) raise Abort {
  let admitted = match @value.admit_usage(parameter.contract, cursor, limits) {
    Ok(admitted) => admitted
    Err(issue) => raise Abort(Value(issue))
  }
  constraints(cursor, parameter)
  admitted
}
