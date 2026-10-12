///|
pub(all) enum KeyedRowResponseIssue {
  InvalidLimits
  CorrelationArity
  WorkLimit
  InvalidCorrelation(Int)
  CorrelationMismatch(Int)
  Equality(@value.CompleteEqualityIssue)
  Closed
} derive(Eq, Debug)

///|
/// Validation of one physical response against one retained request. This
/// continuation is not transport-completion evidence or a capture authority.
/// The acquisition owner reserves its workspace and retains the input borrow.
struct KeyedRowResponseCursor {
  request : KeyedRowRequest
  responses : Array[@value.Value]
  limits : RequestLimits
  mut index : Int
  mut work : Int
  mut recheck : @value.RecheckCursor?
  mut equality : @value.CompleteEquality?
  mut finished : Bool
}

///|
pub enum KeyedRowResponsePoll {
  KeyedRowResponseContinue
  KeyedRowResponseComplete
  KeyedRowResponseFailed(KeyedRowResponseIssue)
}

///|
pub fn start_keyed_row_response(
  request : KeyedRowRequest,
  responses : Array[@value.Value],
  limits : RequestLimits,
) -> Result[KeyedRowResponseCursor, KeyedRowResponseIssue] {
  if limits.max_work < 0 ||
    limits.max_pairs < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_depth < 0 ||
    limits.values.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let count = @environment.source_correlation_pair_count(
    keyed_request_correlation(request.owner.request),
  )
  if count != responses.length() || count > limits.max_pairs {
    return Err(CorrelationArity)
  }
  if limits.max_work < 1 || count > limits.max_work - 1 {
    return Err(WorkLimit)
  }
  Ok({
    request,
    responses: responses.copy(),
    limits,
    index: 0,
    work: count + 1,
    recheck: None,
    equality: None,
    finished: false,
  })
}

///|
pub fn cancel_keyed_row_response(cursor : KeyedRowResponseCursor) -> Unit {
  if !cursor.finished {
    if cursor.recheck is Some(recheck) {
      @value.cancel_recheck_runtime_value(recheck)
    }
    cursor.recheck = None
    cursor.equality = None
    cursor.responses.clear()
    cursor.finished = true
  }
}

///|
fn keyed_row_response_fail(
  cursor : KeyedRowResponseCursor,
  issue : KeyedRowResponseIssue,
) -> KeyedRowResponsePoll {
  cancel_keyed_row_response(cursor)
  KeyedRowResponseFailed(issue)
}

///|
/// One bounded shared recheck/equality step per advance. Reference equality
/// checks current availability and its typed domain; wire text equality never
/// issues provenance or substitutes for this check.
pub fn advance_keyed_row_response(
  cursor : KeyedRowResponseCursor,
) -> KeyedRowResponsePoll {
  if cursor.finished {
    return KeyedRowResponseFailed(Closed)
  }
  if cursor.work == cursor.limits.max_work {
    return keyed_row_response_fail(cursor, WorkLimit)
  }
  cursor.work += 1
  if cursor.index == cursor.responses.length() {
    cursor.responses.clear()
    cursor.finished = true
    return KeyedRowResponseComplete
  }
  if cursor.equality is Some(equality) {
    // Reserve the shared kernel's next unit in addition to this poll before
    // entering it. No work is refunded on mismatch, cancellation or failure.
    if cursor.work == cursor.limits.max_work {
      return keyed_row_response_fail(cursor, WorkLimit)
    }
    match @value.advance_complete_equality(equality, 1) {
      EqualityContinue(work~) => {
        cursor.work += work
        KeyedRowResponseContinue
      }
      EqualityComplete(equal~, work~) => {
        cursor.work += work
        if !equal {
          return keyed_row_response_fail(
            cursor,
            CorrelationMismatch(cursor.index),
          )
        }
        cursor.equality = None
        cursor.index += 1
        KeyedRowResponseContinue
      }
      EqualityFailed(issue, work~) => {
        cursor.work += work
        keyed_row_response_fail(cursor, Equality(issue))
      }
    }
  } else if cursor.recheck is Some(recheck) {
    match @value.advance_recheck_runtime_value(recheck) {
      RecheckContinue => KeyedRowResponseContinue
      RecheckFailed =>
        keyed_row_response_fail(cursor, InvalidCorrelation(cursor.index))
      RecheckComplete(value, _, _) => {
        let expected = cursor.request.fields[cursor.request.owner.fields.length() +
          cursor.index].1
        cursor.equality = match
          @value.start_complete_equality(expected, value, cursor.limits.values) {
          Ok(equality) => Some(equality)
          Err(issue) => return keyed_row_response_fail(cursor, Equality(issue))
        }
        cursor.recheck = None
        KeyedRowResponseContinue
      }
    }
  } else {
    let role = @environment.source_correlation_pair_at(
        keyed_request_correlation(cursor.request.owner.request),
        cursor.index,
      ).unwrap().response
    cursor.recheck = @value.start_recheck_runtime_value(
      cursor.responses[cursor.index],
      role.contract,
      cursor.limits.values,
    )
    if cursor.recheck is None {
      return keyed_row_response_fail(cursor, InvalidCorrelation(cursor.index))
    }
    KeyedRowResponseContinue
  }
}

///|
pub fn keyed_row_response_work(cursor : KeyedRowResponseCursor) -> Int {
  cursor.work
}
