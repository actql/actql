///|
test "request ceiling witness and resolved identity match fixed independent vectors" {
  let request = prepare_request_artifact(
    artifact_request("{\"literal\":7}", 10L),
    10000,
    1000,
    100,
  ).unwrap()
  let limits = {
    max_body_bytes: 10000,
    max_body_nodes: 1000,
    max_body_depth: 100,
  }
  let rows = prepare_request_limit(request, Rows, limits).unwrap()
  assert_true(physical_equal(rows.request, request))
  assert_eq(
    rows.witness_cid,
    "sha256:9a26e64a6a4eec85f250868bd9e6712a534b0cb8e173c7d5efe60cc19eec8b31",
  )
  assert_eq(
    rows.cid,
    "sha256:3e9f78b5041150f2621d68c17ed0bc6f42b1d8cef60f1c6cfa78d44931625dc7",
  )
  let bytes = prepare_request_limit(request, ValueBytes, limits).unwrap()
  assert_true(rows.cid != bytes.cid)
  assert_eq(
    request_ceiling_fields(request, ValueBytes),
    ("/max_value_bytes", "bytes", 1000L),
  )
  let other = prepare_request_artifact(
    artifact_request("{\"literal\":8}", 10L),
    10000,
    1000,
    100,
  ).unwrap()
  assert_true(
    prepare_request_limit(other, Rows, limits).unwrap().cid != rows.cid,
  )
  let out = @encode.writer(10000, 1000, 100)
  emit_request_limits(request, limits, out)
  let text = @encode.finish(out)
  let parsed = @json.parse(text)
  match parsed {
    Array(entries) => {
      assert_eq(entries.length(), 2)
      match (entries[0], entries[1]) {
        (Object(first), Object(second)) => {
          assert_true(first.get("request_pointer") is Some(String("/max_rows")))
          assert_true(
            second.get("request_pointer") is Some(String("/max_value_bytes")),
          )
        }
        _ => fail("expected closed limit entries")
      }
    }
    _ => fail("expected limit array")
  }
  let short = @encode.writer(text.length() - 1, 1000, 100)
  let rejected = try {
    emit_request_limits(request, limits, short)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(
    prepare_request_limit(request, Rows, { ..limits, max_body_bytes: 1, })
    is Err(OutputLimit),
  )
  assert_true(
    prepare_request_limit(request, Rows, { ..limits, max_body_nodes: 0, })
    is Err(InvalidLimits),
  )
}
