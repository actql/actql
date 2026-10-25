///|
test "submitted intent uses selected finite limits beyond obsolete internal ceilings" {
  let builder = StringBuilder()
  builder.write_string("{\"input\":{\"rows\":[")
  for i = 0; i < 100000; i = i + 1 {
    if i > 0 {
      builder.write_string(",")
    }
    builder.write_string("{\"v0\":")
    builder.write_string(i.to_string())
    builder.write_string("}")
  }
  builder.write_string("]},\"kind\":\"program\",\"parameters\":null}")
  let body = builder.to_string()
  assert_true(body.length() > 1048576)
  assert_true(
    @publication_host.prepare_client_submitted_intent(body, 1048576, 65536, 64)
    is Err(@publication_host.ClientSubmittedIntentIssue::Limit),
  )
  let admitted = @publication_host.prepare_client_submitted_intent(
    body,
    body.length(),
    300010,
    4,
  ).unwrap()
  assert_eq(@publication_host.client_submitted_intent_wire(admitted), body)
  assert_eq(
    @publication_host.client_submitted_intent_cid(admitted).length(),
    71,
  )
  let small = "{\"input\":{},\"kind\":\"program\",\"parameters\":null}"
  assert_eq(
    @publication_host.prepare_client_submitted_intent(small, 1048576, 65536, 64),
    @publication_host.prepare_client_submitted_intent(
      small, 2000000, 300010, 100,
    ),
  )
}

///|
test "submitted intent preserves checked hash-envelope representation headroom" {
  let body = "{}"
  assert_eq(
    @publication_host.prepare_client_submitted_intent(body, 2147483520, 10, 2),
    Err(@publication_host.ClientSubmittedIntentIssue::InvalidLimits),
  )
  assert_eq(
    @publication_host.prepare_client_submitted_intent(body, 100, 2147483644, 2),
    Err(@publication_host.ClientSubmittedIntentIssue::InvalidLimits),
  )
  assert_eq(
    @publication_host.prepare_client_submitted_intent(body, 100, 10, 2147483647),
    Err(@publication_host.ClientSubmittedIntentIssue::InvalidLimits),
  )
}
