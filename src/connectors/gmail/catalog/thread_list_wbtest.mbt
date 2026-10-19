///|
fn thread_list_limits() -> GmailThreadListLimits {
  {
    max_bytes: 8192,
    max_nodes: 1024,
    max_depth: 16,
    max_rows: 500,
    max_id_bytes: 128,
    max_token_bytes: 128,
  }
}

///|
fn thread_list_page(
  text : String,
) -> Result[GmailThreadListPage, GmailThreadListIssue] {
  project_gmail_thread_list(@utf8.encode(text), thread_list_limits())
}

///|
test "Gmail thread list retains ordered original targets and opaque continuation rather than estimate rows" {
  let text =
    #|{"threads":[{"id":"é/+","historyId":"18446744073709551615","snippet":"one"},{"id":"é/+"}],"nextPageToken":"opaque/+ =","resultSizeEstimate":4294967295}
  let page = thread_list_page(text).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(text)))
  assert_eq(gmail_thread_list_count(page), 2)
  assert_eq(gmail_thread_list_id_at(page, 0), Some("é/+"))
  assert_eq(gmail_thread_list_id_at(page, 1), Some("é/+"))
  assert_eq(gmail_thread_list_id_at(page, -1), None)
  assert_eq(gmail_thread_list_id_at(page, 2), None)
  assert_eq(gmail_thread_list_next_page_token(page), Some("opaque/+ ="))
  let underestimated = thread_list_page(
    "{\"threads\":[{\"id\":\"one\"}],\"resultSizeEstimate\":0}",
  ).unwrap()
  assert_eq(gmail_thread_list_count(underestimated), 1)
}

///|
test "Gmail thread list empty pages do not end a still continued selected scan" {
  for text in ["{}", "{\"threads\":[]}", "{\"nextPageToken\":\"\"}"] {
    let page = thread_list_page(text).unwrap()
    assert_eq(gmail_thread_list_count(page), 0)
    assert_eq(gmail_thread_list_next_page_token(page), None)
  }
  for
    text in [
      "{\"threads\":[],\"nextPageToken\":\"next\"}", "{\"resultSizeEstimate\":0,\"nextPageToken\":\"next\"}",
    ] {
    let page = thread_list_page(text).unwrap()
    assert_eq(gmail_thread_list_count(page), 0)
    assert_eq(gmail_thread_list_next_page_token(page), Some("next"))
  }
  assert_true(
    project_gmail_thread_list(b"{}", {
      ..thread_list_limits(),
      max_rows: 0,
      max_id_bytes: 0,
      max_token_bytes: 0,
    })
    is Ok(_),
  )
}

///|
test "Gmail thread list validates all known metadata and complete bytes before returning targets" {
  for
    text in [
      "{\"threads\":null}", "{\"threads\":{}}", "{\"nextPageToken\":null}", "{\"nextPageToken\":1}",
      "{\"messages\":[]}", "{\"threads\":[{}]}", "{\"threads\":[{\"id\":\"\"}]}",
      "{\"threads\":[{\"id\":\"one\"},{\"id\":\"two\",\"snippet\":null}]}", "{\"threads\":[{\"id\":\"one\"},{\"id\":\"two\",\"historyId\":1}]}",
      "{\"threads\":[{\"id\":\"one\",\"messages\":[]}]}", "{\"threads\":[]} trailing",
      "{\"resultSizeEstimate\":-1}", "{\"resultSizeEstimate\":1.5}", "{\"resultSizeEstimate\":4294967296}",
      "{\"resultSizeEstimate\":\"2\"}",
    ] {
    assert_true(thread_list_page(text) is Err(InvalidResponse), msg=text)
  }
  assert_true(
    project_gmail_thread_list(b"\xff", thread_list_limits())
    is Err(InvalidResponse),
  )
  assert_true(
    thread_list_page(
      (
        #|{"threads":[{"id":"a"},{"id":"\u0061"}]}
      ),
    )
    is Err(DuplicateThread),
  )
}

///|
test "Gmail thread list enforces independent byte row node and opaque text bounds" {
  let body = @utf8.encode("{\"threads\":[{\"id\":\"界\"}]}")
  let exact = {
    ..thread_list_limits(),
    max_bytes: body.length(),
    max_id_bytes: 3,
  }
  assert_true(project_gmail_thread_list(body, exact) is Ok(_))
  for
    limits in [
      { ..exact, max_bytes: body.length() - 1, },
      { ..exact, max_rows: 0, },
      { ..exact, max_nodes: 1, },
      { ..exact, max_depth: 1, },
      { ..exact, max_id_bytes: 2, },
    ] {
    assert_true(project_gmail_thread_list(body, limits) is Err(BudgetExceeded))
  }
  assert_true(
    project_gmail_thread_list(@utf8.encode("{\"nextPageToken\":\"界\"}"), {
      ..thread_list_limits(),
      max_token_bytes: 2,
    })
    is Err(BudgetExceeded),
  )
  let rows : Array[String] = []
  for index in 0..<501 {
    rows.push("{\"id\":\"" + index.to_string() + "\"}")
  }
  assert_true(
    project_gmail_thread_list(
      @utf8.encode("{\"threads\":[" + rows.join(",") + "]}"),
      {
        ..thread_list_limits(),
        max_bytes: 20000,
        max_nodes: 5000,
        max_rows: 501,
      },
    )
    is Err(InvalidResponse),
  )
}
