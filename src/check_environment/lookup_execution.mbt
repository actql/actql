///|
pub(all) enum LookupExecutionCeiling {
  NetworkAttemptsPerRequest
  RequestBytesPerAttempt
  TotalRequestBytes
  TotalResponseWireBytes
  TotalResponseDecodedBytes
  TotalDurationMs
} derive(Eq, Debug)

///|
pub(all) struct LookupExecutionLimits {
  max_work : Int
  max_bytes : Int
}

///|
pub(all) enum LookupExecutionIssueKind {
  InvalidLimits
  WorkLimit
  InvalidComponent
  ByteLimit
} derive(Eq, Debug)

///|
pub(all) struct LookupExecutionIssue {
  kind : LookupExecutionIssueKind
  source : @decode.Cursor?
}

///|
struct LookupExecutionPolicy {
  source : @decode.Cursor
  cid : String
  ceilings : Array[Int64]
}

///|
struct LookupExecution {
  environment : WireEnvironment
  policy : LookupExecutionPolicy?
  work : Int
  bytes : Int
}

///|
fn lookup_ceiling_index(name : String) -> Int? {
  match name {
    "max_network_attempts_per_request" => Some(0)
    "max_request_bytes_per_attempt" => Some(1)
    "max_total_request_bytes" => Some(2)
    "max_total_response_bytes" => Some(3)
    "max_total_decoded_response_bytes" => Some(4)
    "max_total_duration_ms" => Some(5)
    _ => None
  }
}

///|
/// Validates the optional component, including unused policies. Missing is
/// retained explicitly without defaults; CID validity is not Host authority.
pub fn check_lookup_execution(
  environment : WireEnvironment,
  limits : LookupExecutionLimits,
) -> Result[LookupExecution, LookupExecutionIssue] {
  if limits.max_work < 0 || limits.max_bytes < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let b = { limit: limits.max_work, used: 0, }
  let mut selected = None
  try {
    let root = environment.policy
    for i in 0..<@decode.object_length(root).unwrap() {
      let (name, value) = @decode.field_at(root, i).unwrap()
      lookup_charge(b, 1, value)
      lookup_charge(b, name.length(), value)
      if name == "lookup_execution" {
        selected = Some(value)
      }
    }
    guard selected is Some(body) else {
      return Ok({ environment, policy: None, work: b.used, bytes: 0, })
    }
    lookup_charge(b, 1, body)
    if @decode.object_length(body) != Some(7) {
      lookup_invalid(body)
    }
    let ceilings = Array::make(6, 0L)
    let mut version = false
    for i in 0..<7 {
      let (name, value) = @decode.field_at(body, i).unwrap()
      lookup_charge(b, 1, value)
      lookup_charge(b, name.length(), value)
      if name == "version" {
        let text = match @decode.text(value) {
          Ok(v) => v
          Err(_) => lookup_invalid(value)
        }
        lookup_charge(b, text.length(), value)
        if text != "actql-lookup-execution-policy/0.1" {
          lookup_invalid(value)
        }
        version = true
      } else {
        let index = match lookup_ceiling_index(name) {
          Some(v) => v
          None => lookup_invalid(value)
        }
        let n = match @decode.safe_integer(value) {
          Ok(v) => v
          Err(_) => lookup_invalid(value)
        }
        if n <= 0 {
          lookup_invalid(value)
        }
        ceilings[index] = n
      }
    }
    if !version || ceilings.any(n => n <= 0) {
      lookup_invalid(body)
    }
    // Validated scalar-only body: no whole serialized String or Bytes retained.
    try {
      let writer = @encode.hashing_writer(limits.max_bytes, 8, 1)
      emit_cursor(body, writer, false)
      let (hex, bytes, _) = @encode.finish_hash_usage(writer)
      Ok({
        environment,
        policy: Some({ source: body, cid: "sha256:" + hex, ceilings, }),
        work: b.used,
        bytes,
      })
    } catch {
      _ => Err({ kind: ByteLimit, source: Some(body), })
    }
  } catch {
    LookupCapacityStop(issue) =>
      Err({
        kind: if issue.kind == WorkLimit {
          WorkLimit
        } else {
          InvalidComponent
        },
        source: issue.source,
      })
  }
}

///|
pub fn lookup_execution_environment(v : LookupExecution) -> WireEnvironment {
  v.environment
}

///|
pub fn lookup_execution_policy(v : LookupExecution) -> LookupExecutionPolicy? {
  v.policy
}

///|
pub fn lookup_execution_usage(v : LookupExecution) -> (Int, Int) {
  (v.work, v.bytes)
}

///|
pub fn lookup_execution_source(v : LookupExecutionPolicy) -> @decode.Cursor {
  v.source
}

///|
pub fn lookup_execution_cid(v : LookupExecutionPolicy) -> String {
  v.cid
}

///|
pub fn lookup_execution_ceiling(
  v : LookupExecutionPolicy,
  field : LookupExecutionCeiling,
) -> Int64 {
  v.ceilings[match field {
    NetworkAttemptsPerRequest => 0
    RequestBytesPerAttempt => 1
    TotalRequestBytes => 2
    TotalResponseWireBytes => 3
    TotalResponseDecodedBytes => 4
    TotalDurationMs => 5
  }]
}
