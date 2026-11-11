///|
/// Physical observations accumulate on the original borrowed left handle.
/// Neither a new per-key reader nor cleanup can reset these totals. This is
/// acquisition accounting, not Source completion, billing authority or custody.
fn keyed_lookup_fail(
  left : ClientKeyedLeftRead,
  issue : ClientKeyedRequestIssue,
) -> Result[Unit, ClientKeyedRequestIssue] {
  if left.lookup_issue is None {
    left.lookup_issue = Some(issue)
  }
  Err(left.lookup_issue.unwrap())
}

///|
fn keyed_lookup_observation(
  request : ClientKeyedRequest,
  now_ms : Int64,
) -> Result[@environment.LookupExecutionPolicy, ClientKeyedRequestIssue] {
  let left = request.left
  if left.lookup_issue is Some(issue) {
    return Err(issue)
  }
  if !keyed_lookup_request_dispatch_available(request) {
    return Err(Assembly("request_plan_not_ready"))
  }
  let original = client_keyed_request_matches_acquisition(
    request,
    left.acquisition,
  )
  // The actual current callback can stop the plan or retain its first cause.
  // Preserve that cause before checking the post-callback local phase.
  if left.lookup_issue is Some(issue) {
    return Err(issue)
  }
  if !original || !keyed_lookup_request_dispatch_available(request) {
    return Err(ForeignLeft)
  }
  if request.io_complete || now_ms < 0L || now_ms < left.observed_ms {
    keyed_lookup_fail(left, InvalidObservation) |> ignore
    return Err(InvalidObservation)
  }
  guard @environment.lookup_execution_policy(
      @acquisition.lookup_bounds_policy(left.acquisition.binding.bounds),
    )
    is Some(policy) else {
    keyed_lookup_fail(left, LookupLimit("missing_policy")) |> ignore
    return Err(LookupLimit("missing_policy"))
  }
  if left.started_ms is None {
    left.started_ms = Some(now_ms)
  }
  left.observed_ms = now_ms
  if now_ms - left.started_ms.unwrap() >
    @environment.lookup_execution_ceiling(policy, @environment.TotalDurationMs) {
    keyed_lookup_fail(left, LookupLimit("duration_ms")) |> ignore
    return Err(LookupLimit("duration_ms"))
  }
  Ok(policy)
}

///|
/// Called before each physical send with its actual encoded request size.
/// An over-limit observation is retained; a failed request is not free and
/// re-entering with another request does not restore the original allowance.
pub fn observe_client_keyed_request_attempt(
  request : ClientKeyedRequest,
  bytes : Int64,
  now_ms : Int64,
) -> Result[Unit, ClientKeyedRequestIssue] {
  let left = request.left
  if bytes < 0L ||
    bytes > 9007199254740991L ||
    left.request_bytes > 9007199254740991L - bytes ||
    left.attempts == 9007199254740991L ||
    request.attempts == 9007199254740991L ||
    (request.attempts == 0L && left.requests == 9007199254740991L) {
    return keyed_lookup_fail(left, InvalidObservation)
  }
  let policy = match keyed_lookup_observation(request, now_ms) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if request.attempts == 0L {
    left.requests += 1L
  }
  request.attempts += 1L
  left.attempts += 1L
  left.request_bytes += bytes
  if native_keyed_observed_activation(request) is Some(original) {
    let usage = original.usage
    if usage.started_ms < 0L {
      usage.started_ms = now_ms
    }
    usage.observed_ms = now_ms
    usage.request_bytes += bytes
  }
  // Optional whole-Run estimates do not authorize a physical attempt. The
  // original RowRun admits its finite cumulative Ledger attempt before send;
  // this owner retains actual byte/time totals and the per-request contract.
  if request.attempts >
    @environment.lookup_execution_ceiling(
      policy,
      @environment.NetworkAttemptsPerRequest,
    ) {
    return keyed_lookup_fail(left, LookupLimit("network_attempts"))
  }
  if bytes >
    @environment.lookup_execution_ceiling(
      policy,
      @environment.RequestBytesPerAttempt,
    ) {
    return keyed_lookup_fail(left, LookupLimit("request_bytes_per_attempt"))
  }
  if left.request_bytes >
    @environment.lookup_execution_ceiling(
      policy,
      @environment.TotalRequestBytes,
    ) {
    return keyed_lookup_fail(left, LookupLimit("total_request_bytes"))
  }
  Ok(())
}

///|
/// Wire bodies are reported when received, before decoding. Decoded bodies
/// are reported separately before admission, so no projected body replaces
/// the physical charge and no response is counted twice merely by polling.
pub fn observe_client_keyed_response(
  request : ClientKeyedRequest,
  wire_bytes : Int64,
  decoded_bytes : Int64,
  now_ms : Int64,
) -> Result[Unit, ClientKeyedRequestIssue] {
  let left = request.left
  if wire_bytes < 0L ||
    decoded_bytes < 0L ||
    wire_bytes > 9007199254740991L ||
    decoded_bytes > 9007199254740991L ||
    left.response_bytes > 9007199254740991L - wire_bytes ||
    left.decoded_bytes > 9007199254740991L - decoded_bytes ||
    request.attempts == 0L {
    return keyed_lookup_fail(left, InvalidObservation)
  }
  let policy = match keyed_lookup_observation(request, now_ms) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  left.response_bytes += wire_bytes
  left.decoded_bytes += decoded_bytes
  if native_keyed_observed_activation(request) is Some(original) {
    original.usage.response_wire_bytes += wire_bytes
    original.usage.response_decoded_bytes += decoded_bytes
    original.usage.observed_ms = now_ms
  }
  if left.response_bytes >
    @environment.lookup_execution_ceiling(
      policy,
      @environment.TotalResponseWireBytes,
    ) {
    return keyed_lookup_fail(left, LookupLimit("total_response_wire_bytes"))
  }
  if left.decoded_bytes >
    @environment.lookup_execution_ceiling(
      policy,
      @environment.TotalResponseDecodedBytes,
    ) {
    return keyed_lookup_fail(left, LookupLimit("total_response_decoded_bytes"))
  }
  Ok(())
}

///|
/// Seals only this request's physical observation interval. The caller still
/// needs its exact successful RowRun capture and the entire original JOIN.
pub fn finish_client_keyed_request_io(
  request : ClientKeyedRequest,
  now_ms : Int64,
) -> Result[Unit, ClientKeyedRequestIssue] {
  match keyed_lookup_observation(request, now_ms) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if request.attempts == 0L {
    return keyed_lookup_fail(request.left, InvalidObservation)
  }
  request.io_complete = true
  if native_keyed_observed_activation(request) is Some(original) {
    original.usage.observed_ms = now_ms
    original.usage.usage_final = true
  }
  Ok(())
}

///|
/// A failed dispatched occurrence invalidates the original lookup, not its
/// physical cleanup owner. Keep a more specific prior accounting issue.
pub fn fail_client_keyed_request_io(request : ClientKeyedRequest) -> Unit {
  if request.attempts > 0L && request.left.lookup_issue is None {
    request.left.lookup_issue = Some(LookupIncomplete)
  }
}

///|
/// The Host applies this remaining common policy allowance to its transport
/// abort signal. An abort is not physical-stop or successful Source evidence.
pub fn client_keyed_request_remaining_ms(
  request : ClientKeyedRequest,
  now_ms : Int64,
) -> Result[Int64, ClientKeyedRequestIssue] {
  keyed_lookup_observation(request, now_ms).map(policy => {
    @environment.lookup_execution_ceiling(policy, @environment.TotalDurationMs) -
    (now_ms - request.left.started_ms.unwrap())
  })
}

///|
/// Observation totals remain available after failure or producer closure;
/// this read neither reauthorizes I/O nor revives a capture.
pub fn client_keyed_lookup_usage(
  left : ClientKeyedLeftRead,
) -> (Int64, Int64, Int64, Int64, Int64, Int64) {
  (
    left.requests,
    left.attempts,
    left.request_bytes,
    left.response_bytes,
    left.decoded_bytes,
    match left.started_ms {
      Some(start) => left.observed_ms - start
      None => 0L
    },
  )
}
