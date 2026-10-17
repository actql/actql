///|
fn limits() -> GmailLabelListLimits {
  {
    max_bytes: 8192,
    max_nodes: 512,
    max_depth: 16,
    max_rows: 10,
    max_value_nodes: 100,
    max_value_text_bytes: 4096,
  }
}

///|
fn project(text : String) -> Result[GmailLabelListPage, GmailLabelListIssue] {
  project_gmail_label_list(@utf8.encode(text), limits())
}

///|
fn original() -> String {
  (
    #|{"labels":[{"id":"INBOX","name":"Inbox","type":"system","messageListVisibility":"show"},{"id":"Label_1","name":"顧客 / é 📩","type":"user","color":{"textColor":"#ffffff"}}]}
  )
}

///|
fn rejected(text : String) -> Unit raise {
  match project(text) {
    Err(_) => ()
    Ok(_) => fail("Expected Gmail whole-page refusal")
  }
}

///|
test "Gmail label list preserves original full rows identity order strings and declared schema" {
  let body = original()
  let page = project(body).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(body)))
  assert_eq(gmail_label_list_row_count(page), 2)
  assert_eq(gmail_label_list_ids(page), ["INBOX", "Label_1"])
  assert_eq(gmail_label_list_column_names(), ["id", "name", "type"])
  assert_eq(
    gmail_label_list_rows_wire(page, ["id", "name", "type"], 8192, 100, 8).unwrap(),
    (
      #|[{"id":"INBOX","name":"Inbox","type":"system"},{"id":"Label_1","name":"顧客 / é 📩","type":"user"}]
    ),
  )
  assert_eq(
    gmail_label_list_schema_wire(2048, 100, 8).unwrap(),
    (
      #|{"id":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"type":{"nullable":false,"type":"string"}}
    ),
  )
  assert_eq(
    gmail_label_list_facts_wire(),
    (
      #|{"relation_keys":{"candidate_keys":[["id"]]}}
    ),
  )
}

///|
test "Gmail empty endpoint forms are empty and explicit empty label name is retained" {
  for body in ["{}", "{\"labels\":[]}"] {
    let page = project(body).unwrap()
    assert_eq(gmail_label_list_row_count(page), 0)
    assert_eq(
      gmail_label_list_rows_wire(page, ["id"], 100, 10, 4).unwrap(),
      "[]",
    )
  }
  let page = project(
    (
      #|{"labels":[{"id":"Label_1","name":"","type":"user"}]}
    ),
  ).unwrap()
  assert_eq(
    gmail_label_list_rows_wire(page, ["name"], 100, 10, 4).unwrap(),
    "[{\"name\":\"\"}]",
  )
}

///|
test "Gmail label list rejects foreign error and continuation envelopes instead of empty mailbox success" {
  for
    body in [
      "null",
      "[]",
      "true",
      (
        #|{"labels":null}
      ),
      (
        #|{"labels":{}}
      ),
      (
        #|{"error":{"code":403}}
      ),
      (
        #|{"messages":[]}
      ),
      (
        #|{"labels":[],"nextPageToken":"unhandled"}
      ),
      (
        #|{"labels":[],"labels":[]}
      ),
      (
        #|{"labels":[],"\u006cabels":[]}
      ),
      original() + "{}",
    ] {
    rejected(body)
  }
}

///|
test "Gmail label keys and every declared cell are checked before any selected projection" {
  for
    body in [
      (
        #|{"labels":[{"id":"","name":"x","type":"user"}]}
      ),
      (
        #|{"labels":[{"id":"x","name":"x","type":"user"},{"id":"x","name":"y","type":"user"}]}
      ),
      (
        #|{"labels":[{"name":"x","type":"user"}]}
      ),
      (
        #|{"labels":[{"id":"x","type":"user"}]}
      ),
      (
        #|{"labels":[{"id":"x","name":"x"}]}
      ),
      (
        #|{"labels":[{"id":"x","name":null,"type":"user"}]}
      ),
      (
        #|{"labels":[{"id":"x","name":"x","type":null}]}
      ),
      (
        #|{"labels":[{"id":"x","name":"x","type":"admin"}]}
      ),
      (
        #|{"labels":[{"id":"x","name":0,"type":"user"}]}
      ),
      (
        #|{"labels":[{"id":"x","name":"\ud800","type":"user"}]}
      ),
      (
        #|{"labels":[{"id":"x","id":"y","name":"x","type":"user"}]}
      ),
    ] {
    rejected(body)
  }
}

///|
test "Gmail label projection does not hide key refusals or accept unknown duplicate columns" {
  let page = project(original()).unwrap()
  assert_eq(
    gmail_label_list_rows_wire(page, ["name"], 8192, 100, 8).unwrap(),
    (
      #|[{"name":"Inbox"},{"name":"顧客 / é 📩"}]
    ),
  )
  for names in [["name", "name"], ["mailbox"], ["id", "missing"]] {
    match gmail_label_list_rows_wire(page, names, 8192, 100, 8) {
      Err(InvalidSelection(_)) => ()
      _ => fail("Expected exact column selection refusal")
    }
  }
}

///|
test "Gmail label limits separately bound complete raw decode rows and admitted value graphs" {
  let body = @utf8.encode(original())
  let original_limits = limits()
  for
    bound in [
      { ..original_limits, max_bytes: body.length() - 1, },
      { ..original_limits, max_nodes: 1, },
      { ..original_limits, max_depth: 1, },
      { ..original_limits, max_rows: 1, },
      { ..original_limits, max_value_nodes: 5, },
      { ..original_limits, max_value_text_bytes: 1, },
    ] {
    match project_gmail_label_list(body, bound) {
      Err(BudgetExceeded) => ()
      _ => fail("Expected independent whole-page resource refusal")
    }
  }
  ignore(
    project_gmail_label_list(body, {
      ..original_limits,
      max_bytes: body.length(),
    }).unwrap(),
  )
  for
    bound in [
      { ..original_limits, max_bytes: 0, },
      { ..original_limits, max_nodes: 0, },
      { ..original_limits, max_depth: 0, },
      { ..original_limits, max_rows: 0, },
      { ..original_limits, max_value_nodes: 0, },
      { ..original_limits, max_value_text_bytes: 0, },
    ] {
    match project_gmail_label_list(body, bound) {
      Err(InvalidLimits) => ()
      _ => fail("Expected missing explicit resource limit refusal")
    }
  }
}

///|
test "Gmail label emitted row and schema wire bounds refuse before returning partial output" {
  let page = project(original()).unwrap()
  for bound in [(1, 100, 8), (8192, 1, 8), (8192, 100, 1)] {
    match
      gmail_label_list_rows_wire(
        page,
        ["id", "name", "type"],
        bound.0,
        bound.1,
        bound.2,
      ) {
      Err(BudgetExceeded) => ()
      _ => fail("Expected bounded row emission refusal")
    }
    match gmail_label_list_schema_wire(bound.0, bound.1, bound.2) {
      Err(BudgetExceeded) => ()
      _ => fail("Expected bounded schema emission refusal")
    }
  }
}
