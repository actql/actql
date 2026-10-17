///|
fn limits() -> TokenResponseLimits {
  {
    max_bytes: 4096,
    max_nodes: 64,
    max_depth: 8,
    max_token_bytes: 256,
    max_lifetime_seconds: 3600,
    max_scopes: 4,
    max_scope_bytes: 256,
  }
}

///|
fn response(text : String) -> Result[TokenResponse, TokenResponseIssue] {
  read_service_account_token_response(200, @utf8.encode(text), limits())
}

///|
fn original() -> String {
  (
    #|{"access_token":"original/+._~-=","token_type":"Bearer","expires_in":3600,"scope":"https://www.googleapis.com/auth/calendar.readonly https://mail.google.com/"}
  )
}

///|
fn refusal(text : String, expected : TokenResponseIssue) -> Unit raise {
  match response(text) {
    Err(issue) => assert_eq(issue, expected)
    Ok(_) => fail("Expected fixed token response refusal")
  }
}

///|
test "Google response preserves private token exact lifetime optional scopes and independent output arrays" {
  let value = response(original()).unwrap()
  assert_eq(token_response_access_token(value), "original/+._~-=")
  assert_eq(token_response_lifetime_seconds(value), 3600)
  let scopes = token_response_scopes(value).unwrap()
  assert_eq(scopes, [
    "https://www.googleapis.com/auth/calendar.readonly", "https://mail.google.com/",
  ])
  scopes[0] = "foreign"
  assert_eq(
    token_response_scopes(value).unwrap()[0],
    "https://www.googleapis.com/auth/calendar.readonly",
  )
  let missing = response(
    (
      #|{"access_token":"a","token_type":"bEaReR","expires_in":1}
    ),
  ).unwrap()
  assert_eq(token_response_scopes(missing), None)
  assert_eq(token_response_lifetime_seconds(missing), 1)
}

///|
test "Google response accepts bounded OAuth extension members without granting their contents meaning" {
  let value = response(
    (
      #|{"access_token":"a","token_type":"Bearer","expires_in":2,"extension":{"permission":"all","ignored":[1,true,null]}}
    ),
  ).unwrap()
  assert_eq(token_response_access_token(value), "a")
  assert_eq(token_response_scopes(value), None)
}

///|
test "Google response rejects error envelopes including success shaped mixtures without leaking provider text" {
  for
    body in [
      (
        #|{"error":"invalid_grant","error_description":"PRIVATE MATERIAL"}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"error":null}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"error":"invalid_grant"}
      ),
    ] {
    refusal(body, ProviderRejected)
  }
  for status in [0, 199, 201, 204, 301, 400, 401, 403, 429, 500] {
    match
      read_service_account_token_response(
        status,
        @utf8.encode(original()),
        limits(),
      ) {
      Err(issue) => assert_eq(issue, InvalidStatus)
      Ok(_) => fail("Non-success response must not yield token material")
    }
  }
}

///|
test "Google response strict JSON rejects duplicate decoded members invalid Unicode trailing and non object" {
  for
    body in [
      (
        #|{"access_token":"a","access_token":"b","token_type":"Bearer","expires_in":2}
      ),
      (
        #|{"access_token":"a","\u0061ccess_token":"b","token_type":"Bearer","expires_in":2}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"ignored":{"x":1,"x":2}}
      ),
      (
        #|{"access_token":"\ud800","token_type":"Bearer","expires_in":2}
      ),
      original() + "{}",
      "[]",
      "null",
      "true",
    ] {
    refusal(body, InvalidResponse)
  }
  match read_service_account_token_response(200, b"\xff", limits()) {
    Err(issue) => assert_eq(issue, InvalidResponse)
    Ok(_) => fail("Invalid UTF8 must not produce token material")
  }
}

///|
test "Google response only admits explicit safe Bearer material and positive bounded integer lifetime" {
  for
    body in [
      (
        #|{"token_type":"Bearer","expires_in":2}
      ),
      (
        #|{"access_token":null,"token_type":"Bearer","expires_in":2}
      ),
      (
        #|{"access_token":"","token_type":"Bearer","expires_in":2}
      ),
      (
        #|{"access_token":"=","token_type":"Bearer","expires_in":2}
      ),
      (
        #|{"access_token":"a=b","token_type":"Bearer","expires_in":2}
      ),
      (
        #|{"access_token":"a\r\nAuthorization:x","token_type":"Bearer","expires_in":2}
      ),
      (
        #|{"access_token":"秘密","token_type":"Bearer","expires_in":2}
      ),
    ] {
    refusal(body, InvalidToken)
  }
  for
    body in [
      (
        #|{"access_token":"a","expires_in":2}
      ),
      (
        #|{"access_token":"a","token_type":null,"expires_in":2}
      ),
      (
        #|{"access_token":"a","token_type":"Basic","expires_in":2}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer ","expires_in":2}
      ),
    ] {
    refusal(body, InvalidTokenType)
  }
  for
    body in [
      (
        #|{"access_token":"a","token_type":"Bearer"}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":null}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":"3600"}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":0}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":-1}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":1.5}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":9007199254740992}
      ),
    ] {
    refusal(body, InvalidLifetime)
  }
  refusal(
    (
      #|{"access_token":"a","token_type":"Bearer","expires_in":3601}
    ),
    BudgetExceeded,
  )
}

///|
test "Google response observed scopes stay ordered distinct explicit and are never inferred from token success" {
  for
    body in [
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":null}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":[]}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":""}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":" a"}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":"a "}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":"a  b"}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":"a a"}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":"a\tb"}
      ),
      (
        #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":"a\\b"}
      ),
    ] {
    refusal(body, InvalidScopes)
  }
  let value = response(
    (
      #|{"access_token":"a","token_type":"Bearer","expires_in":2,"scope":"b a"}
    ),
  ).unwrap()
  assert_eq(token_response_scopes(value), Some(["b", "a"]))
}

///|
test "Google response validates each explicit limit and exact token byte lifetime and scope boundaries" {
  let body = @utf8.encode(original())
  let original_limits = limits()
  for
    bad in [
      { ..original_limits, max_bytes: 0, },
      { ..original_limits, max_nodes: 0, },
      { ..original_limits, max_depth: 0, },
      { ..original_limits, max_token_bytes: 0, },
      { ..original_limits, max_lifetime_seconds: 0, },
      { ..original_limits, max_scopes: 0, },
      { ..original_limits, max_scope_bytes: 0, },
    ] {
    match read_service_account_token_response(200, body, bad) {
      Err(issue) => assert_eq(issue, InvalidLimits)
      Ok(_) => fail("Invalid explicit bounds must refuse")
    }
  }
  let exact = {
    ..original_limits,
    max_bytes: body.length(),
    max_token_bytes: 15,
    max_scopes: 2,
    max_scope_bytes: 74,
  }
  ignore(read_service_account_token_response(200, body, exact).unwrap())
  for
    short in [
      { ..exact, max_bytes: exact.max_bytes - 1, },
      { ..exact, max_token_bytes: exact.max_token_bytes - 1, },
      { ..exact, max_scopes: 1, },
      { ..exact, max_scope_bytes: exact.max_scope_bytes - 1, },
      { ..exact, max_lifetime_seconds: 3599, },
    ] {
    match read_service_account_token_response(200, body, short) {
      Err(issue) => assert_eq(issue, BudgetExceeded)
      Ok(_) => fail("One-short admission must refuse")
    }
  }
}

///|
test "Google response budgets ignored extension nodes depth and strings before yielding any token" {
  let body = @utf8.encode(
    (
      #|{"access_token":"a","token_type":"Bearer","expires_in":2,"ignored":[[[[0]]]]}
    ),
  )
  for bound in [{ ..limits(), max_nodes: 4, }, { ..limits(), max_depth: 3, }] {
    match read_service_account_token_response(200, body, bound) {
      Err(issue) => assert_eq(issue, BudgetExceeded)
      Ok(_) => fail("Extension content must pay complete response admission")
    }
  }
}
