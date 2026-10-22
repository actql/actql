///|
fn mock_target_limits() -> RowPageLimits {
  { max_bytes: 65536, max_nodes: 8192, max_depth: 32, max_rows: 100, }
}

///|
test "Mock target spans preserve Unicode and reversed physical field ordering" {
  let salesforce = mock_update_declaration()
  let warehouse = mock_document_warehouse()
  let original = mock_document_text(count="9007199254740993")
    .replace(old="Acme Corp", new="会社🌱")
    .replace(
      old="\"Churn_Risk__c\":\"low\",\"Risk_Reason__c\":null",
      new="\"Risk_Reason__c\" : null , \"Churn_Risk__c\" : \"low\"",
    )
  let document = admit_mock_churn_risk_target_document(
    salesforce,
    warehouse,
    @utf8.encode(original),
    mock_target_limits(),
    10000000,
  ).unwrap()
  let row = observe_mock_churn_risk_target(document, salesforce, "001Acme").unwrap()
  let output = prepare_mock_churn_risk_target_update(
    document,
    row,
    mock_churn_risk_target_version(row).unwrap(),
    "{\"Risk_Reason__c\":\"理由🌱\\n\\\"ok\\\"\",\"Churn_Risk__c\":\"high\"}",
    10000000,
  ).unwrap()
  assert_eq(
    @utf8.decode(output),
    original.replace(
      old="\"Risk_Reason__c\" : null , \"Churn_Risk__c\" : \"low\"",
      new="\"Risk_Reason__c\" : \"理由🌱\\n\\\"ok\\\"\" , \"Churn_Risk__c\" : \"high\"",
    ),
  )
  assert_true(
    observe_mock_churn_risk_target(document, salesforce, "missing")
    is Err(InvalidPage),
  )
}

///|
test "Mock target second row update preserves the first change and its original value version" {
  let salesforce = mock_update_declaration()
  let warehouse = mock_document_warehouse()
  let original = mock_document_text()
  let first = admit_mock_churn_risk_target_document(
    salesforce,
    warehouse,
    @utf8.encode(original),
    mock_target_limits(),
    10000000,
  ).unwrap()
  let acme = observe_mock_churn_risk_target(first, salesforce, "001Acme").unwrap()
  let globex = observe_mock_churn_risk_target(first, salesforce, "001Globex").unwrap()
  let updated = prepare_mock_churn_risk_target_update(
    first,
    acme,
    mock_churn_risk_target_version(acme).unwrap(),
    "{\"Churn_Risk__c\":\"high\",\"Risk_Reason__c\":\"first\"}",
    10000000,
  ).unwrap()
  let second = admit_mock_churn_risk_target_document(
    salesforce,
    warehouse,
    updated,
    mock_target_limits(),
    10000000,
  ).unwrap()
  let next_acme = observe_mock_churn_risk_target(second, salesforce, "001Acme").unwrap()
  let next_globex = observe_mock_churn_risk_target(
    second, salesforce, "001Globex",
  ).unwrap()
  assert_true(
    mock_churn_risk_target_version(acme) !=
    mock_churn_risk_target_version(next_acme),
  )
  assert_eq(
    mock_churn_risk_target_version(globex),
    mock_churn_risk_target_version(next_globex),
  )
  let final_bytes = prepare_mock_churn_risk_target_update(
    second,
    next_globex,
    mock_churn_risk_target_version(globex).unwrap(),
    "{\"Churn_Risk__c\":\"high\",\"Risk_Reason__c\":\"second\"}",
    10000000,
  ).unwrap()
  assert_eq(
    @utf8.decode(final_bytes),
    original
    .replace(
      old="\"Churn_Risk__c\":\"low\",\"Risk_Reason__c\":null",
      new="\"Churn_Risk__c\":\"high\",\"Risk_Reason__c\":\"first\"",
    )
    .replace(
      old="\"Churn_Risk__c\":\"medium\",\"Risk_Reason__c\":null",
      new="\"Churn_Risk__c\":\"high\",\"Risk_Reason__c\":\"second\"",
    ),
  )
}

///|
test "Mock target update preserves raw full signed64 tokens and every unselected byte" {
  let salesforce = mock_update_declaration()
  let warehouse = mock_document_warehouse()
  for
    count in ["-9223372036854775808", "9007199254740993", "9223372036854775807"] {
    let original = " \n" + mock_document_text(count~) + "\n "
    let document = admit_mock_churn_risk_target_document(
      salesforce,
      warehouse,
      @utf8.encode(original),
      mock_target_limits(),
      10000000,
    ).unwrap()
    let row = observe_mock_churn_risk_target(document, salesforce, "001Acme").unwrap()
    let before = mock_churn_risk_target_before(row).unwrap()
    assert_true(before.contains("\"Churn_Risk__c\":\"low\""))
    assert_true(before.contains("\"Risk_Reason__c\":null"))
    let output = prepare_mock_churn_risk_target_update(
      document,
      row,
      mock_churn_risk_target_version(row).unwrap(),
      "{\"Churn_Risk__c\":\"high\",\"Risk_Reason__c\":\"reason\"}",
      10000000,
    ).unwrap()
    // The selected substring is unique. This independent expectation keeps
    // all whitespace, key ordering, warehouse tokens and the second row.
    let expected = original.replace(
      old="\"Churn_Risk__c\":\"low\",\"Risk_Reason__c\":null",
      new="\"Churn_Risk__c\":\"high\",\"Risk_Reason__c\":\"reason\"",
    )
    assert_eq(@utf8.decode(output), expected)
    assert_eq(mock_churn_risk_target_before(row), Some(before))
    // The complete updated file still passes the original full document law.
    admit_mock_churn_risk_target_document(
      salesforce,
      warehouse,
      output,
      mock_target_limits(),
      10000000,
    ).unwrap()
    |> ignore
  }
}

///|
test "Mock target owns original bytes and rejects copied row or foreign document correspondence" {
  let salesforce = mock_update_declaration()
  let warehouse = mock_document_warehouse()
  let bytes = @utf8.encode(mock_document_text())
  let document = admit_mock_churn_risk_target_document(
    salesforce,
    warehouse,
    bytes,
    mock_target_limits(),
    10000000,
  ).unwrap()
  let row = observe_mock_churn_risk_target(document, salesforce, "001Acme").unwrap()
  assert_false(physical_equal(document.bytes, bytes))
  assert_true(mock_churn_risk_target_before(row) is Some(_))
  let copied = { ..row, }
  assert_eq(mock_churn_risk_target_before(copied), None)
  assert_true(
    observe_mock_churn_risk_target({ ..document, }, salesforce, "001Acme")
    is Err(ForeignSource),
  )
  assert_true(
    observe_mock_churn_risk_target(
      document,
      mock_update_declaration(),
      "001Acme",
    )
    is Err(ForeignSource),
  )
  let other = admit_mock_churn_risk_target_document(
    salesforce,
    warehouse,
    @utf8.encode(mock_document_text()),
    mock_target_limits(),
    10000000,
  ).unwrap()
  let update = "{\"Churn_Risk__c\":\"high\",\"Risk_Reason__c\":\"reason\"}"
  assert_true(
    prepare_mock_churn_risk_target_update(
      other,
      row,
      mock_churn_risk_target_version(row).unwrap(),
      update,
      10000000,
    )
    is Err(ForeignSource),
  )
  assert_true(
    prepare_mock_churn_risk_target_update(
      document,
      row,
      "sha256:" + "0".repeat(64),
      update,
      10000000,
    )
    is Err(ForeignSource),
  )
  assert_true(
    prepare_mock_churn_risk_target_update(
      document,
      copied,
      mock_churn_risk_target_version(row).unwrap(),
      update,
      10000000,
    )
    is Err(ForeignSource),
  )
}

///|
test "Mock target refuses malformed whole documents and non-Mapping updates before output" {
  let salesforce = mock_update_declaration()
  let warehouse = mock_document_warehouse()
  for
    text in [
      mock_document_text(count="9007199254740993.0"),
      mock_document_text(count="9223372036854775808"),
      mock_document_text().replace(
        old="\"name\":\"Acme Corp\"",
        new="\"name\":null",
      ),
    ] {
    assert_true(
      admit_mock_churn_risk_target_document(
        salesforce,
        warehouse,
        @utf8.encode(text),
        mock_target_limits(),
        10000000,
      )
      is Err(_),
    )
  }
  let document = admit_mock_churn_risk_target_document(
    salesforce,
    warehouse,
    @utf8.encode(mock_document_text()),
    mock_target_limits(),
    10000000,
  ).unwrap()
  let row = observe_mock_churn_risk_target(document, salesforce, "001Acme").unwrap()
  for
    value in [
      "{}", "{\"Churn_Risk__c\":null,\"Risk_Reason__c\":\"reason\"}", "{\"Churn_Risk__c\":\"high\",\"Risk_Reason__c\":\"reason\",\"id\":\"changed\"}",
      "{\"Churn_Risk__c\":\"high\",\"Churn_Risk__c\":\"low\",\"Risk_Reason__c\":\"reason\"}",
    ] {
    assert_true(
      prepare_mock_churn_risk_target_update(
        document,
        row,
        mock_churn_risk_target_version(row).unwrap(),
        value,
        10000000,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_mock_churn_risk_target_update(
      document,
      row,
      mock_churn_risk_target_version(row).unwrap(),
      "{\"Churn_Risk__c\":\"high\",\"Risk_Reason__c\":\"reason\"}",
      0,
    )
    is Err(_),
  )
}
