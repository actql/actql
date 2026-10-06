///|
priv struct Budget {
  mut nodes : Int
  mut text : Int
  max_depth : Int
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
  identifier? : Bool = false,
) -> Int raise Abort {
  let size = match @scalar.admit_utf8_length(text, budget.text) {
    Ok(size) => size
    Err(@scalar.MalformedUtf16(_)) => fail(cursor, InvalidUnicode)
    Err(_) => fail(cursor, BudgetExceeded)
  }
  budget.text -= size
  if identifier {
    match @canonical.normalize_nfc_lf(text) {
      Ok(normalized) => if normalized != text { fail(cursor, NonCanonicalText) }
      Err(_) => fail(cursor, InvalidUnicode)
    }
  }
  size
}

///|
fn number(cursor : @decode.Cursor) -> Double raise Abort {
  match @decode.finite_number(cursor) {
    Ok(value) => {
      if @scalar.read_finite_number(value) is None ||
        (value == 0.0 && 1.0 / value < 0.0) {
        fail(cursor, InvalidNumber)
      }
      value
    }
    Err(issue) =>
      if issue.kind == @decode.WrongType {
        fail(cursor, WrongType)
      } else {
        fail(cursor, InvalidNumber)
      }
  }
}

///|
/// Shared non-null scalar admission. Container readers must not call `view`
/// merely to discover a scalar mismatch: that would copy a complete child map.
fn read_scalar(
  cursor : @decode.Cursor,
  shape : @contract.Shape,
  budget : Budget,
) -> Value raise Abort {
  match shape {
    @contract.Text(bounds) => {
      let text = decoded(@decode.text(cursor))
      let bytes = text_size(text, cursor, budget).to_int64()
      let count = @scalar.unicode_scalar_count(text).unwrap().to_int64()
      if (bounds.min_length is Some(n) && count < n) ||
        (bounds.max_codepoints is Some(n) && count > n) ||
        (bounds.max_utf8_bytes is Some(n) && bytes > n) {
        fail(cursor, StringConstraint)
      }
      Text(text)
    }
    @contract.Number => Number(number(cursor))
    @contract.Boolean => Boolean(decoded(@decode.boolean(cursor)))
    @contract.Decimal(precision~, scale~) => {
      let text = decoded(@decode.text(cursor))
      ignore(text_size(text, cursor, budget))
      match decimal(text, precision, scale) {
        Some(value) => Decimal(value)
        None => fail(cursor, InvalidDecimal)
      }
    }
    @contract.Date | @contract.Timestamp => {
      let text = decoded(@decode.text(cursor))
      ignore(text_size(text, cursor, budget))
      if shape is @contract.Date {
        if text.length() != 10 || !valid_date(text) {
          fail(cursor, InvalidDate)
        }
        Date(text)
      } else {
        if !valid_timestamp(text) {
          fail(cursor, InvalidTimestamp)
        }
        Timestamp(text)
      }
    }
    _ => fail(cursor, WrongType)
  }
}

///|
// The admitted source cursor retains the key span. Resolve it directly rather
// than rebuilding the complete declaration map merely to locate a refusal.
fn cursor_key_text(
  name : String,
  child : @decode.Cursor,
  budget : Budget,
  identifier? : Bool = true,
) -> Unit raise Abort {
  ignore(text_size(name, child, budget, identifier~)) catch {
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
}

///|
/// Check exact decoded source values without coercion, repair or authority claims.
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
/// Explicit typed-wire entry. JSON envelopes are decoded only where the
/// checked contract says JSON; payload keys never select a type or authority.
pub fn admit_wire(
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  limits : Limits,
) -> Result[CheckedValue, Issue] {
  let admission = match
    start_typed_admission(contract, cursor, limits, wire=true) {
    Ok(admission) => admission
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_typed_admission(admission) {
      TypedAdmissionContinue => ()
      TypedAdmissionComplete(value, _, _) => return Ok(value)
      TypedAdmissionFailed(issue) => return Err(issue)
      TypedAdmissionTerminal => abort("wire admission terminated")
    }
  } nobreak {
    abort("wire admission stopped")
  }
}

///|
/// Returns the admitted value, visited value nodes, and charged UTF-8 text bytes
/// (including object keys). Callers can share a budget across separate values.
/// Depth is checked per value, not a cumulative counter. No partial usage or
/// admitted value is returned after failure. Explicit authored fields retain
/// the ordinary Object identifier rule after an Effect literal is typed;
/// checked JSON payload keys remain data in either admission mode.
pub fn admit_usage(
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  limits : Limits,
  authored_fields? : Bool = false,
) -> Result[(CheckedValue, Int, Int), Issue] {
  let admission = match
    start_typed_admission(contract, cursor, limits, authored_fields~) {
    Ok(admission) => admission
    Err(issue) => return Err(issue)
  }
  // Ordinary callers and resumed Store callers share the same admission
  // transitions. This convenience entry drains them without claiming that the
  // complete traversal is a single bounded execution step.
  while true {
    match advance_typed_admission(admission) {
      TypedAdmissionContinue => ()
      TypedAdmissionComplete(value, nodes, text) =>
        return Ok((value, nodes, text))
      TypedAdmissionFailed(issue) => return Err(issue)
      TypedAdmissionTerminal =>
        abort("typed admission terminated without a result")
    }
  } nobreak {
    abort("typed admission stopped without a result")
  }
}

///|
/// Admit a decoded physical number without building the generic traversal
/// stack. The caller has already admitted the physical source cursor; this
/// retains the same contract, scalar budget, and error location as admit_usage.
pub fn admit_number_usage(
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
  if limits.max_nodes == 0 {
    return Err(
      ValueIssue(
        BudgetExceeded,
        path=@decode.cursor_path(cursor),
        span=@decode.cursor_span(cursor),
      ),
    )
  }
  if !(contract.shape is @contract.Number) {
    return admit_usage(contract, cursor, limits)
  }
  match @decode.view(cursor) {
    @decode.NumberValue(value) => {
      if @scalar.read_finite_number(value) is None ||
        (value == 0.0 && 1.0 / value < 0.0) {
        return Err(
          ValueIssue(
            InvalidNumber,
            path=@decode.cursor_path(cursor),
            span=@decode.cursor_span(cursor),
          ),
        )
      }
      Ok(({ contract, value: Number(value), }, 1, 0))
    }
    _ => admit_usage(contract, cursor, limits)
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
  wire? : Bool = false,
) -> Result[CheckedValue, Issue] {
  match
    admit_host_usage(issuer, contract, cursor, limits, reference_limits, wire~) {
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
  wire? : Bool = false,
) -> Result[(CheckedValue, Int, Int), Issue] {
  let admission = match
    start_host_typed_admission(
      issuer,
      contract,
      cursor,
      limits,
      reference_limits,
      wire~,
    ) {
    Ok(admission) => admission
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_typed_admission(admission) {
      TypedAdmissionContinue => ()
      TypedAdmissionComplete(value, nodes, bytes) =>
        return Ok((value, nodes, bytes))
      TypedAdmissionFailed(issue) => return Err(issue)
      TypedAdmissionTerminal =>
        abort("terminal typed admission without a result")
    }
  } nobreak {
    abort("host typed admission stopped without a result")
  }
}
