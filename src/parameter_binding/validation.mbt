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
  names : Array[String],
  object : @decode.Cursor,
  budget : Budget,
) -> Unit raise Abort {
  charge_text(key, object, budget, identifier=true) catch {
    Abort(ParameterIssue(kind, ..)) =>
      match @decode.closed_object(object, names.filter(n => n != key)) {
        Err(location) =>
          raise Abort(
            ParameterIssue(kind, path=location.path, span=location.span),
          )
        Ok(_) => invalid(object, kind)
      }
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
    let view = @decode.view(cursor)
    let container = view is (@decode.ArrayValue(_) | @decode.ObjectValue(_))
    if container && parent_depth >= budget.depth {
      invalid(cursor, BudgetExceeded)
    }
    let depth = parent_depth + (if container { 1 } else { 0 })
    match view {
      @decode.NullValue | @decode.BoolValue(_) => ()
      @decode.NumberValue(n) =>
        if @scalar.read_finite_number(n) is None || (n == 0.0 && 1.0 / n < 0.0) {
          invalid(cursor, InvalidNumber)
        }
      @decode.TextValue(text) => charge_text(text, cursor, budget)
      @decode.ArrayValue(items) => {
        if items.length() > budget.nodes {
          invalid(cursor, BudgetExceeded)
        }
        budget.nodes -= items.length()
        for index = items.length() - 1; index >= 0; index = index - 1 {
          work.push((items[index], depth))
        }
      }
      @decode.ObjectValue(object) => {
        let names = decoded(@decode.object_field_names(cursor))
        if names.length() > budget.nodes {
          invalid(cursor, BudgetExceeded)
        }
        budget.nodes -= names.length()
        for name in names {
          charge_key(name, names, cursor, budget)
        }
        for index = names.length() - 1; index >= 0; index = index - 1 {
          work.push((@decode.lookup(object, names[index]).unwrap(), depth))
        }
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
  let value = match @value.admit(parameter.contract, cursor, limits) {
    Ok(value) => value
    Err(issue) => raise Abort(Value(issue))
  }
  constraints(cursor, parameter)
  value
}
