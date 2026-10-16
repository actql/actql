///|
fn job_limits() -> JobResponseLimits {
  { max_bytes: 4096, max_nodes: 128, max_depth: 12, }
}

///|
fn refresh_request() -> JobStartRequest {
  prepare_job_start_request(
    RefreshDataSource,
    "3.29",
    "11111111-1111-1111-1111-111111111111",
    "22222222-2222-2222-2222-222222222222",
    256,
  ).unwrap()
}

///|
fn response(
  id? : String = "33333333-3333-3333-3333-333333333333",
  kind? : String = "RefreshExtract",
  mode? : String = "Asynchronous",
  target? : String = "22222222-2222-2222-2222-222222222222",
  detail? : String = "extractRefreshJob",
  resource? : String = "datasource",
) -> Bytes {
  @utf8.encode(
    "{\"job\":{\"id\":\"\{id}\",\"mode\":\"\{mode}\",\"type\":\"\{kind}\",\"\{detail}\":{\"\{resource}\":{\"id\":\"\{target}\"}}}}",
  )
}

///|
fn started() -> StartedJob {
  admit_started_job(refresh_request(), 202, response(), job_limits()).unwrap()
}

///|
test "job requests target exact LUIDs and default full operations without credentials or CAS" {
  let refresh = refresh_request()
  assert_eq(job_start_method(refresh), "POST")
  assert_eq(
    job_start_path(refresh),
    "/api/3.29/sites/11111111-1111-1111-1111-111111111111/datasources/22222222-2222-2222-2222-222222222222/refresh",
  )
  assert_eq(job_start_body(refresh), "<tsRequest/>")
  let flow = prepare_job_start_request(
    RunFlow,
    "3.29",
    "11111111-1111-1111-1111-111111111111",
    "22222222-2222-2222-2222-222222222222",
    256,
  ).unwrap()
  assert_eq(
    job_start_path(flow),
    "/api/3.29/sites/11111111-1111-1111-1111-111111111111/flows/22222222-2222-2222-2222-222222222222/run",
  )
  assert_eq(
    job_start_body(flow),
    "<tsRequest><flowRunSpec flowId=\"22222222-2222-2222-2222-222222222222\" runMode=\"full\"/></tsRequest>",
  )
  let other = prepare_job_start_request(
    RunFlow,
    "3.29",
    "11111111-1111-1111-1111-111111111111",
    "44444444-4444-4444-4444-444444444444",
    256,
  ).unwrap()
  assert_eq(
    job_start_path(other),
    "/api/3.29/sites/11111111-1111-1111-1111-111111111111/flows/44444444-4444-4444-4444-444444444444/run",
  )
  assert_eq(
    job_start_body(other),
    "<tsRequest><flowRunSpec flowId=\"44444444-4444-4444-4444-444444444444\" runMode=\"full\"/></tsRequest>",
  )
}

///|
test "names and path injection are not target LUIDs or API version selections" {
  let site = "11111111-1111-1111-1111-111111111111"
  let target = "22222222-2222-2222-2222-222222222222"
  for
    bad in [
      "",
      "Sales",
      "../flows",
      target + "?refresh=true",
      "22222222-2222-2222-2222-22222222222g",
    ] {
    assert_true(
      prepare_job_start_request(RefreshDataSource, "3.29", site, bad, 256)
      is Err(InvalidSelection),
    )
    assert_true(
      prepare_job_start_request(RunFlow, "3.29", bad, target, 256)
      is Err(InvalidSelection),
    )
  }
  for
    bad in [
      "", "3", "3.", ".29", "03.29", "3.029", "3.29?x=1", "3.29/../3.1", "3.29\n",
      "3.2.9",
    ] {
    assert_true(
      prepare_job_start_request(RunFlow, bad, site, target, 256)
      is Err(InvalidSelection),
    )
  }
}

///|
test "request bounds admit the exact path and refuse one byte less" {
  let request = refresh_request()
  let size = job_start_path(request).length()
  assert_true(
    prepare_job_start_request(
      RefreshDataSource,
      request.api_version,
      request.site_id,
      request.target_id,
      size,
    )
    is Ok(_),
  )
  assert_true(
    prepare_job_start_request(
      RefreshDataSource,
      request.api_version,
      request.site_id,
      request.target_id,
      size - 1,
    )
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_job_start_request(
      RefreshDataSource,
      request.api_version,
      request.site_id,
      request.target_id,
      0,
    )
    is Err(InvalidLimits),
  )
}

///|
test "a refresh acceptance preserves its original job id and independent response hash" {
  let job = started()
  assert_eq(started_job_id(job), "33333333-3333-3333-3333-333333333333")
  // Independent SHA256 of the exact 180-byte literal, not product-generated.
  assert_eq(
    started_job_response_sha256(job),
    "097a9c4c00c9fea4c4e40c65478d32acabffa739719d81fd2cd913bac8826b41",
  )
}

///|
test "flow acceptance uses its own status type and exact flow target" {
  let request = prepare_job_start_request(
    RunFlow,
    "3.29",
    "11111111-1111-1111-1111-111111111111",
    "22222222-2222-2222-2222-222222222222",
    256,
  ).unwrap()
  let body = response(kind="RunFlow", detail="runFlowJobType", resource="flow")
  assert_true(admit_started_job(request, 200, body, job_limits()) is Ok(_))
  assert_true(
    admit_started_job(request, 202, body, job_limits()) is Err(UnexpectedStatus),
  )
  assert_true(
    admit_started_job(request, 200, response(), job_limits())
    is Err(InvalidResponse),
  )
}

///|
test "a status code alone and queue conflicts never supply a job receipt" {
  for status in [0, 200, 201, 204, 301, 400, 401, 403, 404, 409, 429, 500] {
    assert_true(
      admit_started_job(refresh_request(), status, response(), job_limits())
      is Err(UnexpectedStatus),
    )
  }
  assert_true(
    admit_started_job(refresh_request(), 202, @utf8.encode("{}"), job_limits())
    is Err(InvalidResponse),
  )
}

///|
test "missing partial duplicate null and malformed responses do not become accepted jobs" {
  for
    bad in [
      "", "{", "[]", "null", "{\"job\":null}", "{\"job\":{}}", "{\"job\":{},\"job\":{}}",
      "{\"job\":{\"id\":\"a\",\"id\":\"b\"}}",
    ] {
    assert_true(
      admit_started_job(refresh_request(), 202, @utf8.encode(bad), job_limits())
      is Err(InvalidResponse),
    )
  }
  assert_true(
    admit_started_job(refresh_request(), 202, b"\xff", job_limits())
    is Err(InvalidResponse),
  )
}

///|
test "a same-kind response for another target cannot bind to the approved request" {
  assert_true(
    admit_started_job(
      refresh_request(),
      202,
      response(target="44444444-4444-4444-4444-444444444444"),
      job_limits(),
    )
    is Err(ForeignJob),
  )
  assert_true(
    admit_started_job(
      refresh_request(),
      202,
      response(target="Sales"),
      job_limits(),
    )
    is Err(ForeignJob),
  )
}

///|
test "foreign job kinds synchronous responses and names as job ids are refused" {
  assert_true(
    admit_started_job(
      refresh_request(),
      202,
      response(kind="RunFlow"),
      job_limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    admit_started_job(
      refresh_request(),
      202,
      response(mode="Synchronous"),
      job_limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    admit_started_job(
      refresh_request(),
      202,
      response(id="recent-job-on-same-target"),
      job_limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    admit_started_job(
      refresh_request(),
      202,
      response(detail="runFlowJobType"),
      job_limits(),
    )
    is Err(InvalidResponse),
  )
}

///|
test "complete parsing enforces byte node depth bounds before returning any receipt" {
  let exact = { ..job_limits(), max_bytes: 180, }
  assert_true(
    admit_started_job(refresh_request(), 202, response(), exact) is Ok(_),
  )
  assert_true(
    admit_started_job(refresh_request(), 202, response(), {
      ..exact,
      max_bytes: 179,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    admit_started_job(refresh_request(), 202, response(), {
      ..exact,
      max_nodes: 1,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    admit_started_job(refresh_request(), 202, response(), {
      ..exact,
      max_depth: 1,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    admit_started_job(refresh_request(), 202, response(), {
      ..exact,
      max_bytes: 0,
    })
    is Err(InvalidLimits),
  )
}

///|
test "unselected nested duplicate fields cannot be hidden by projecting just the job id" {
  let bad = @utf8.encode(
    "{\"job\":{\"id\":\"33333333-3333-3333-3333-333333333333\",\"mode\":\"Asynchronous\",\"type\":\"RefreshExtract\",\"extractRefreshJob\":{\"datasource\":{\"id\":\"22222222-2222-2222-2222-222222222222\"}},\"extra\":{\"x\":1,\"x\":2}}}",
  )
  assert_true(
    admit_started_job(refresh_request(), 202, bad, job_limits())
    is Err(InvalidResponse),
  )
}

///|
test "lookup selects only the original returned job and its original site" {
  let job = started()
  let path = "/api/3.29/sites/11111111-1111-1111-1111-111111111111/jobs/33333333-3333-3333-3333-333333333333"
  assert_eq(job_lookup_path(job, path.length()).unwrap(), path)
  assert_true(job_lookup_path(job, path.length() - 1) is Err(CapacityExceeded))
  assert_true(job_lookup_path(job, 0) is Err(InvalidLimits))
}

///|
test "a recent same-target different job or kind is not reconciliation evidence" {
  assert_true(
    admit_job_lookup_observation(
      started(),
      200,
      response(id="44444444-4444-4444-4444-444444444444"),
      job_limits(),
    )
    is Err(ForeignJob),
  )
  assert_true(
    admit_job_lookup_observation(
      started(),
      200,
      response(kind="RunFlow"),
      job_limits(),
    )
    is Err(ForeignJob),
  )
  assert_true(
    admit_job_lookup_observation(
      started(),
      200,
      response(mode="Synchronous"),
      job_limits(),
    )
    is Err(ForeignJob),
  )
  assert_true(
    admit_job_lookup_observation(started(), 404, response(), job_limits())
    is Err(UnexpectedStatus),
  )
}

///|
test "lookup identity is distinct from a completion or resend permission" {
  let body = @utf8.encode(
    "{\"job\":{\"id\":\"33333333-3333-3333-3333-333333333333\",\"mode\":\"Asynchronous\",\"type\":\"RefreshExtract\",\"progress\":\"100\",\"finishCode\":\"0\"}}",
  )
  let observed = admit_job_lookup_observation(
    started(),
    200,
    body,
    job_limits(),
  ).unwrap()
  assert_eq(job_lookup_observation_id(observed), started_job_id(started()))
  assert_eq(job_lookup_response_sha256(observed), @sha.hex(body))
  assert_true(
    admit_job_lookup_observation(
      started(),
      200,
      @utf8.encode("{\"job\":null}"),
      job_limits(),
    )
    is Err(InvalidResponse),
  )
}
