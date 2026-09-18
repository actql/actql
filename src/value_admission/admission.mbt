///|
priv struct Budget {
  mut nodes : Int
  mut text : Int
  max_depth : Int
}

///|
priv enum Work {
  Read(@decode.Cursor, @contract.Contract?, Int)
  BuildArray(Int)
  BuildObject(Array[String])
}

///|
fn[T] fail(cursor : @decode.Cursor, kind : IssueKind) -> T raise Abort {
  raise Abort(
    ValueIssue(
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
fn reserve(
  cursor : @decode.Cursor,
  count : Int,
  budget : Budget,
) -> Unit raise Abort {
  if count > budget.nodes {
    fail(cursor, BudgetExceeded)
  }
  budget.nodes -= count
}

///|
fn text_size(
  text : String,
  cursor : @decode.Cursor,
  budget : Budget,
) -> Int raise Abort {
  let size = match @scalar.admit_utf8_length(text, budget.text) {
    Ok(size) => size
    Err(@scalar.MalformedUtf16(_)) => fail(cursor, InvalidUnicode)
    Err(_) => fail(cursor, BudgetExceeded)
  }
  budget.text -= size
  match @canonical.normalize_nfc_lf(text) {
    Ok(normalized) => if normalized != text { fail(cursor, NonCanonicalText) }
    Err(_) => fail(cursor, InvalidUnicode)
  }
  size
}

///|
fn number(cursor : @decode.Cursor) -> Double raise Abort {
  match @decode.view(cursor) {
    @decode.NumberValue(value) => {
      if @scalar.read_finite_number(value) is None ||
        (value == 0.0 && 1.0 / value < 0.0) {
        fail(cursor, InvalidNumber)
      }
      value
    }
    _ => fail(cursor, WrongType)
  }
}

///|
// Resolve the key's span only on failure. Successful admission never rebuilds
// the declaration map per field.
fn key_text(
  name : String,
  names : Array[String],
  object : @decode.Cursor,
  child : @decode.Cursor,
  budget : Budget,
) -> Unit raise Abort {
  ignore(text_size(name, child, budget)) catch {
    Abort(ValueIssue(kind, ..)) =>
      match @decode.closed_object(object, names.filter(n => n != name)) {
        Err(location) =>
          raise Abort(ValueIssue(kind, path=location.path, span=location.span))
        Ok(_) => fail(child, kind)
      }
    error => raise error
  }
}

///|
fn take(values : Array[Value], count : Int) -> Array[Value] {
  let result : Array[Value] = []
  for index = 0; index < count; index = index + 1 {
    result.push(values.pop().unwrap())
  }
  for left = 0; left < count / 2; left = left + 1 {
    let right = count - 1 - left
    let saved = result[left]
    result[left] = result[right]
    result[right] = saved
  }
  result
}

///|
fn run(
  root : @decode.Cursor,
  contract : @contract.Contract,
  budget : Budget,
  reference_issuer? : ReferenceIssuer,
  reference_limits? : ReferenceLimits,
) -> Value raise Abort {
  reserve(root, 1, budget)
  let work : Array[Work] = [Read(root, Some(contract), 0)]
  let values : Array[Value] = []
  while !work.is_empty() {
    match work.pop().unwrap() {
      BuildArray(count) => values.push(Array({ values: take(values, count), }))
      BuildObject(names) => {
        let children = take(values, names.length())
        let entries : Array[(String, Value)] = []
        for index = 0; index < names.length(); index = index + 1 {
          entries.push((names[index], children[index]))
        }
        values.push(Object({ values: entries, }))
      }
      Read(cursor, expected, parent_depth) => {
        if @decode.is_null(cursor) {
          if expected is Some(c) && !c.nullable {
            fail(cursor, UnexpectedNull)
          }
          values.push(Null)
          continue
        }
        let input = @decode.view(cursor)
        let container = input
          is (@decode.ArrayValue(_) | @decode.ObjectValue(_))
        if container && parent_depth >= budget.max_depth {
          fail(cursor, BudgetExceeded)
        }
        let depth = parent_depth + (if container { 1 } else { 0 })
        let shape = expected.map(c => c.shape)
        match shape {
          Some(@contract.Text(bounds)) => {
            let text = decoded(@decode.text(cursor))
            let bytes = text_size(text, cursor, budget).to_int64()
            let count = @scalar.unicode_scalar_count(text).unwrap().to_int64()
            if (bounds.min_length is Some(n) && count < n) ||
              (bounds.max_codepoints is Some(n) && count > n) ||
              (bounds.max_utf8_bytes is Some(n) && bytes > n) {
              fail(cursor, StringConstraint)
            }
            values.push(Text(text))
          }
          Some(@contract.Number) => values.push(Number(number(cursor)))
          Some(@contract.Boolean) =>
            values.push(Boolean(decoded(@decode.boolean(cursor))))
          Some(@contract.Decimal(precision~, scale~)) => {
            let text = decoded(@decode.text(cursor))
            ignore(text_size(text, cursor, budget))
            match decimal(text, precision, scale) {
              Some(value) => values.push(Decimal(value))
              None => fail(cursor, InvalidDecimal)
            }
          }
          Some(@contract.Date) | Some(@contract.Timestamp) => {
            let text = decoded(@decode.text(cursor))
            ignore(text_size(text, cursor, budget))
            if shape is Some(@contract.Date) {
              if text.length() != 10 || !valid_date(text) {
                fail(cursor, InvalidDate)
              }
              values.push(Date(text))
            } else {
              if !valid_timestamp(text) {
                fail(cursor, InvalidTimestamp)
              }
              values.push(Timestamp(text))
            }
          }
          Some(@contract.Vector(dimensions~)) => {
            let items = decoded(@decode.elements(cursor))
            if items.length().to_double() != dimensions {
              fail(cursor, VectorDimension)
            }
            reserve(cursor, items.length(), budget)
            let components : Array[Double] = []
            for item in items {
              components.push(number(item))
            }
            values.push(Vector({ values: components, }))
          }
          Some(@contract.ResourceRef(_)) | Some(@contract.ArtifactRef(_)) => {
            guard reference_issuer is Some(issuer) &&
              reference_limits is Some(limits) &&
              expected is Some(reference_contract) else {
              fail(cursor, UnsupportedReference)
            }
            let issued = match
              issue_reference_cursor_usage(issuer, reference_contract, cursor, {
                ..limits,
                max_depth: Int::min(
                  limits.max_depth,
                  budget.max_depth - parent_depth,
                ),
              }) {
              Ok(value) => value
              Err(Unauthorized) => fail(cursor, UnauthorizedReference)
              Err(_) => fail(cursor, InvalidReference)
            }
            let (checked, nodes, text) = issued
            if nodes < 1 || nodes - 1 > budget.nodes || text > budget.text {
              fail(cursor, BudgetExceeded)
            }
            budget.nodes -= nodes - 1
            budget.text -= text
            values.push(checked.value)
          }
          Some(@contract.Array(_, max_items~)) => {
            let items = decoded(@decode.elements(cursor))
            if max_items is Some(n) && items.length().to_int64() > n {
              fail(cursor, ArrayConstraint)
            }
            reserve(cursor, items.length(), budget)
            let child = match shape {
              Some(@contract.Array(child, ..)) => Some(child)
              _ => None
            }
            work.push(BuildArray(items.length()))
            for index = items.length() - 1; index >= 0; index = index - 1 {
              work.push(Read(items[index], child, depth))
            }
          }
          Some(@contract.Object(fields)) => {
            let fields = @contract.fields(fields)
            let names = fields.map(f => f.name)
            let view = decoded(@decode.closed_object(cursor, names))
            reserve(cursor, fields.length(), budget)
            let children : Array[(@decode.Cursor, @contract.Contract)] = []
            for field in fields {
              // lookup preserves explicit null; required() intentionally does not.
              let child = match @decode.lookup(view, field.name) {
                Some(child) => child
                None => decoded(@decode.required(view, field.name))
              }
              key_text(field.name, names, cursor, child, budget)
              children.push((child, field.contract))
            }
            work.push(BuildObject(names))
            for index = children.length() - 1; index >= 0; index = index - 1 {
              let (child, contract) = children[index]
              work.push(Read(child, Some(contract), depth))
            }
          }
          Some(@contract.Json) | None =>
            match input {
              @decode.NullValue => values.push(Null)
              @decode.BoolValue(value) => values.push(Boolean(value))
              @decode.NumberValue(_) => values.push(Number(number(cursor)))
              @decode.TextValue(text) => {
                ignore(text_size(text, cursor, budget))
                values.push(Text(text))
              }
              @decode.ArrayValue(items) => {
                reserve(cursor, items.length(), budget)
                work.push(BuildArray(items.length()))
                for index = items.length() - 1; index >= 0; index = index - 1 {
                  work.push(Read(items[index], None, depth))
                }
              }
              @decode.ObjectValue(view) => {
                let names = decoded(@decode.object_field_names(cursor))
                reserve(cursor, names.length(), budget)
                names.sort_by(@canonical.compare_utf16)
                let children : Array[@decode.Cursor] = []
                for name in names {
                  let child = @decode.lookup(view, name).unwrap()
                  key_text(name, names, cursor, child, budget)
                  children.push(child)
                }
                work.push(BuildObject(names))
                for index = children.length() - 1; index >= 0; index = index - 1 {
                  work.push(Read(children[index], None, depth))
                }
              }
            }
        }
      }
    }
  }
  values.pop().unwrap()
}

///|
/// Check normalized source values without coercion, repair or authority claims.
pub fn admit(
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  limits : Limits,
) -> Result[CheckedValue, Issue] {
  match admit_usage(contract, cursor, limits) {
    Ok((value, _, _)) => Ok(value)
    Err(issue) => Err(issue)
  }
}

///|
/// Returns the admitted value, visited value nodes, and charged UTF-8 text bytes
/// (including object keys). Callers can share a budget across separate values.
/// Depth is checked per value, not a cumulative counter. No partial usage or
/// admitted value is returned after failure.
pub fn admit_usage(
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  limits : Limits,
) -> Result[(CheckedValue, Int, Int), Issue] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(
      ValueIssue(
        InvalidLimits,
        path=@decode.cursor_path(cursor),
        span=@decode.cursor_span(cursor),
      ),
    )
  }
  try {
    let budget = {
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      max_depth: limits.max_depth,
    }
    let value = run(cursor, contract, budget)
    Ok(
      (
        { contract, value, },
        limits.max_nodes - budget.nodes,
        limits.max_text_bytes - budget.text,
      ),
    )
  } catch {
    Abort(issue) => Err(issue)
  }
}

///|
/// Admit a value supplied by a trusted Host representation. The issuer proves
/// reference provenance and retains current authorization; ordinary authored
/// admission intentionally has no route to this entry.
pub fn admit_host(
  issuer : ReferenceIssuer,
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  limits : Limits,
  reference_limits : ReferenceLimits,
) -> Result[CheckedValue, Issue] {
  match admit_host_usage(issuer, contract, cursor, limits, reference_limits) {
    Ok((value, _, _)) => Ok(value)
    Err(issue) => Err(issue)
  }
}

///|
/// Host admission with exact value-node and UTF-8 text usage.
pub fn admit_host_usage(
  issuer : ReferenceIssuer,
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  limits : Limits,
  reference_limits : ReferenceLimits,
) -> Result[(CheckedValue, Int, Int), Issue] {
  if limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 ||
    reference_limits.max_bytes < 0 ||
    reference_limits.max_nodes < 1 ||
    reference_limits.max_depth < 0 ||
    reference_limits.max_text_units < 0 {
    return Err(
      ValueIssue(
        InvalidLimits,
        path=@decode.cursor_path(cursor),
        span=@decode.cursor_span(cursor),
      ),
    )
  }
  try {
    let budget = {
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      max_depth: limits.max_depth,
    }
    let value = run(
      cursor,
      contract,
      budget,
      reference_issuer=issuer,
      reference_limits~,
    )
    Ok(
      (
        { contract, value, },
        limits.max_nodes - budget.nodes,
        limits.max_text_bytes - budget.text,
      ),
    )
  } catch {
    Abort(issue) => Err(issue)
  }
}
