///|
pub(all) enum RecordWriteResponseIssue {
  InvalidLimits
  BudgetExceeded
  UnexpectedStatus
  InvalidResponse
  IncompleteResponse
  UncorrelatedResult
  DuplicateRecord
} derive(Eq, Debug)

///|
pub struct RecordWriteResult {
  id : String
  created : Bool
}

///|
/// Complete provider acknowledgement, in original request order. This DATA
/// neither commits an Effect Ledger nor settles an uncertain physical send.
pub struct RecordWriteResponse {
  response_sha256 : String
  priv request : RecordBatchRequest
  priv results : Array[RecordWriteResult]
}

///|
pub fn record_write_response_result(
  response : RecordWriteResponse,
  index : Int,
) -> RecordWriteResult? {
  response.results.get(index)
}

///|
pub fn record_write_response_count(response : RecordWriteResponse) -> Int {
  response.results.length()
}

///|
pub fn record_write_response_request(
  response : RecordWriteResponse,
) -> RecordBatchRequest {
  response.request
}

///|
/// No response-order assumption: updates correlate by record ID; multi-row
/// creates/upserts require the original trace echoed by the provider. A
/// one-input response belongs to that one original physical request. A trace,
/// when present, must still agree. Trace IDs are not idempotency guarantees.
pub fn project_record_write_success(
  request : RecordBatchRequest,
  status : Int,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
) -> Result[RecordWriteResponse, RecordWriteResponseIssue] {
  if max_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 ||
    max_rows <= 0 ||
    max_rows > 100 {
    return Err(InvalidLimits)
  }
  let expected = match request.operation {
    Create => 201
    Update | Upsert(_) => 200
  }
  if status != expected {
    return Err(UnexpectedStatus)
  }
  if bytes.length() > max_bytes || request.inputs.length() > max_rows {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes,
      max_depth,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }) {
    Ok(value) =>
      match @decode.open_object(value) {
        Ok(value) => value
        Err(_) => return Err(InvalidResponse)
      }
    Err(_) => return Err(InvalidResponse)
  }
  if text(root, "status") != Some("COMPLETE") {
    return Err(IncompleteResponse)
  }
  match @decode.field(root, "errors") {
    Missing => ()
    Present(value) if @decode.array_length(value) == Some(0) => ()
    _ => return Err(IncompleteResponse)
  }
  match @decode.field(root, "numErrors") {
    Missing => ()
    Present(value) if @decode.int32(value) == Ok(0) => ()
    _ => return Err(IncompleteResponse)
  }
  guard @decode.lookup(root, "results") is Some(results) &&
    @decode.array_length(results) == Some(request.inputs.length()) else {
    return Err(IncompleteResponse)
  }
  let by_trace : Map[String, Int] = Map([])
  let by_id : Map[String, Int] = Map([])
  for index, input in request.inputs {
    by_trace[input.trace_id] = index
    if request.operation is Update && input.target is Some(target) {
      by_id[target.provider_value] = index
    }
  }
  let ordered : Map[Int, RecordWriteResult] = Map([])
  let seen_ids : Map[String, Bool] = Map([])
  for index in 0..<request.inputs.length() {
    guard @decode.element_at(results, index) is Some(cursor) &&
      @decode.open_object(cursor) is Ok(row) &&
      text(row, "id") is Some(id) &&
      !id.is_empty() &&
      @decode.lookup(row, "archived") is Some(archived) &&
      @decode.boolean(archived) == Ok(false) &&
      @decode.lookup(row, "properties") is Some(properties) &&
      @decode.open_object(properties) is Ok(_) else {
      return Err(InvalidResponse)
    }
    if seen_ids.contains(id) {
      return Err(DuplicateRecord)
    }
    seen_ids[id] = true
    let trace_index = match @decode.field(row, "objectWriteTraceId") {
      Missing => None
      Present(value) =>
        match @decode.text(value) {
          Ok(value) =>
            match by_trace.get(value) {
              Some(index) => Some(index)
              None => return Err(UncorrelatedResult)
            }
          Err(_) => return Err(UncorrelatedResult)
        }
      ExplicitNull => return Err(UncorrelatedResult)
    }
    let original_index = match request.operation {
      Update =>
        match by_id.get(id) {
          Some(index) => index
          None => return Err(UncorrelatedResult)
        }
      Create | Upsert(_) =>
        match trace_index {
          Some(index) => index
          None if request.inputs.length() == 1 => 0
          None => return Err(UncorrelatedResult)
        }
    }
    if (trace_index is Some(index) && index != original_index) ||
      ordered.contains(original_index) {
      return Err(UncorrelatedResult)
    }
    let created = match request.operation {
      Create => true
      Update => false
      Upsert(_) =>
        match @decode.lookup(row, "new") {
          Some(value) =>
            match @decode.boolean(value) {
              Ok(value) => value
              Err(_) => return Err(InvalidResponse)
            }
          None => return Err(InvalidResponse)
        }
    }
    ordered[original_index] = { id, created, }
  }
  let values = []
  for index in 0..<request.inputs.length() {
    guard ordered.get(index) is Some(value) else {
      return Err(IncompleteResponse)
    }
    values.push(value)
  }
  Ok({ request, results: values, response_sha256: @sha.hex(bytes), })
}
