///|
fn account_limits() -> @source.ParseLimits {
  { max_input_bytes: 4096, max_nodes: 100, max_depth: 10, }
}

///|
fn account_rejection(
  result : Result[AccountIdentity, AccountIdentityIssue],
  expected : AccountIdentityIssue,
) -> Unit raise {
  match result {
    Err(issue) => assert_eq(issue, expected)
    Ok(_) => fail("Account response unexpectedly admitted")
  }
}

///|
test "account details project the original portal and complete response digest without policy inference" {
  let body =
    #|{"portalId":12345678,"accountType":"STANDARD","timeZone":"US/Eastern","companyCurrency":"USD","additionalCurrencies":["NZD"],"utcOffset":"-04:00","utcOffsetMilliseconds":-14400000,"uiDomain":"app-eu1.hubspot.com","dataHostingLocation":"eu1"}
  let original = project_account_identity(@utf8.encode(body), account_limits()).unwrap()
  assert_eq(original.portal_id, 12345678)
  assert_eq(original.response_sha256, @sha.hex(@utf8.encode(body)))
  assert_eq(recheck_account_identity(original, "12345678"), Ok(()))
  assert_eq(recheck_account_identity(original, "12345679"), Err(ForeignAccount))
  assert_eq(
    recheck_account_identity(original, "012345678"),
    Err(ForeignAccount),
  )
  // Unselected account metadata is not used to synthesize a policy or grant.
  let future = project_account_identity(
    @utf8.encode(
      "{\"portalId\":12345678,\"accountType\":\"FUTURE\",\"note\":\"é😀\"}",
    ),
    account_limits(),
  ).unwrap()
  assert_eq(recheck_account_identity(future, "12345678"), Ok(()))
  assert_true(future.response_sha256 != original.response_sha256)
}

///|
test "account int32 identifiers retain exact integer and exponent meaning" {
  for
    (token, expected) in [
      ("7", 7),
      ("7.000", 7),
      ("70e-1", 7),
      ("2147483647", 2147483647),
      ("-2147483648", -2147483648),
      ("0", 0),
    ] {
    let body = "{\"note\":\"é😀\",\"portalId\":" + token + "}"
    let observed = match
      project_account_identity(@utf8.encode(body), account_limits()) {
      Ok(value) => value
      Err(_) => fail("Integer account token unexpectedly refused: " + token)
    }
    assert_eq(observed.portal_id, expected)
    assert_eq(recheck_account_identity(observed, expected.to_string()), Ok(()))
  }
}

///|
test "account identity rejects numeric rounding into a different int32 account" {
  for
    token in [
      "7.0000000000000000001", "6.9999999999999999999", "1e-400", "2147483647.000000001",
      "2147483648", "-2147483649", "1e100", "7.1", "\"7\"", "true", "null", "{}",
      "[]",
      // The existing Source JSON owner already refuses negative zero.
       "-0", "-0.0", "-0e3",
    ] {
    account_rejection(
      project_account_identity(
        @utf8.encode("{\"portalId\":" + token + "}"),
        account_limits(),
      ),
      InvalidResponse,
    )
  }
}

///|
test "incomplete duplicate malformed and error account responses are never identity observations" {
  for
    body in [
      "{}", "[]", "{\"status\":\"error\",\"message\":\"denied\"}", "{\"portalId\":7,\"portalId\":8}",
      "{\"portalId\":7} trailing", "{\"portalId\":7", "{\"portalId\":7,\"note\":{\"x\":1,\"x\":2}}",
    ] {
    account_rejection(
      project_account_identity(@utf8.encode(body), account_limits()),
      InvalidResponse,
    )
  }
  account_rejection(
    project_account_identity(b"\xff", account_limits()),
    InvalidResponse,
  )
}

///|
test "account response bounds apply to the complete input including unselected metadata" {
  let body = @utf8.encode("{\"portalId\":7,\"note\":\"é😀\"}")
  let exact = { ..account_limits(), max_input_bytes: body.length(), }
  assert_true(project_account_identity(body, exact) is Ok(_))
  account_rejection(
    project_account_identity(body, {
      ..exact,
      max_input_bytes: body.length() - 1,
    }),
    BudgetExceeded,
  )
  for
    bounded in [
      { ..account_limits(), max_nodes: 1, },
      { ..account_limits(), max_depth: 1, },
    ] {
    account_rejection(
      project_account_identity(
        @utf8.encode("{\"portalId\":7,\"unused\":[[0]]}"),
        bounded,
      ),
      BudgetExceeded,
    )
  }
  for
    invalid in [
      { ..account_limits(), max_input_bytes: 0, },
      { ..account_limits(), max_nodes: 0, },
      { ..account_limits(), max_depth: 0, },
    ] {
    account_rejection(project_account_identity(body, invalid), InvalidLimits)
  }
}
