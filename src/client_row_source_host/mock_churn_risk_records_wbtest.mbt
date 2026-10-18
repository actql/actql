///|
fn mock_document_warehouse() -> RowDeclaration {
  generate_relation_row_declaration(
    "snowflake",
    "mock_snowflake",
    "mock_snowflake/0.1",
    [
      {
        resource: "usage_30d",
        resource_kind: "table",
        schema_wire: "{\"account_id\":{\"nullable\":false,\"type\":\"string\"},\"active_users\":{\"nullable\":false,\"type\":\"int64\"},\"trend\":{\"nullable\":false,\"type\":\"string\"}}",
        schema_cid: "sha256:fd038c1aa8fe013d4838819a6011e18aee81a04a179f1994a548ff292dfae424",
        request_schema_wire: None,
        facts_wire: Some(
          "{\"relation_keys\":{\"candidate_keys\":[[\"account_id\"]]}}",
        ),
        acquisition_wire: None,
      },
    ],
    mock_update_limits(),
  ).unwrap()
}

///|
fn mock_document_text(count? : String = "4") -> String {
  "{\"salesforce\":{\"Account\":{\"key\":[\"id\"],\"rows\":[" +
  "{\"id\":\"001Acme\",\"name\":\"Acme Corp\",\"description\":\"Evaluating a competitor; usage down since June.\",\"Churn_Risk__c\":\"low\",\"Risk_Reason__c\":null}," +
  "{\"id\":\"001Globex\",\"name\":\"Globex Inc\",\"description\":\"Several support tickets about the new pricing.\",\"Churn_Risk__c\":\"medium\",\"Risk_Reason__c\":null}]}}," +
  "\"snowflake\":{\"usage_30d\":{\"key\":[\"account_id\"],\"rows\":[" +
  "{\"account_id\":\"001Acme\",\"active_users\":" +
  count +
  ",\"trend\":\"down\"}," +
  "{\"account_id\":\"001Globex\",\"active_users\":12,\"trend\":\"flat\"}]}}}"
}

///|
fn mock_document_read(warehouse? : Bool = true) -> RowSourceRead {
  // The warehouse control selects one column; unselected physical fields
  // and the other complete table must still be admitted.
  let names = if warehouse {
    ["active_users"]
  } else {
    ["id", "name", "description", "Churn_Risk__c", "Risk_Reason__c"]
  }
  let schema = @schema.from_fields(
    names.map(name => {
      (
        @schema.Unqualified(name),
        @contract.primitive(
          if name == "active_users" {
            @contract.Signed64Type
          } else {
            @contract.StringType
          },
          nullable=name == "Risk_Reason__c",
        ),
      )
    }),
    max_fields=5,
    max_name_bytes=128,
  ).unwrap()
  let pipeline = @pipeline.check(
    row_presence_cursor(
      if warehouse {
        "[{\"select\":[\"active_users\"]}]"
      } else {
        "[{\"select\":[\"id\"]}]"
      },
    ),
    [("rows", schema)],
    None,
    Some(row_presence_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 4096,
      max_nodes: 256,
      max_tokens: 256,
      max_depth: 16,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 4096,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let original = @lower.preparation_input_schema(
    @lower.bound_preparation(owner),
    0,
  ).unwrap()
  let columns = []
  for index in 0..<@schema.field_count(original) {
    columns.push(
      @schema.field_reference_name(@schema.field_at(original, index).unwrap()),
    )
  }
  new_row_source_read(
    owner,
    0,
    original,
    columns,
    names,
    { max_bytes: 65536, max_nodes: 8192, max_depth: 32, max_rows: 100, },
    100,
    row_presence_retention(),
    None,
    None,
    None,
  ).unwrap()
}

///|
test "mock physical source exact integer spans reach the original typed input without Number conversion" {
  let salesforce = mock_update_declaration()
  let snowflake = mock_document_warehouse()
  for
    text in [
      "4", "-9223372036854775808", "9007199254740992", "9007199254740993", "9223372036854775807",
    ] {
    let read = mock_document_read()
    let rows = match
      mock_churn_risk_document_rows(
        read,
        snowflake,
        salesforce,
        snowflake,
        @utf8.encode(mock_document_text(count=text)),
        10000000,
      ) {
      Ok(rows) => rows
      Err(InvalidPage) => {
        fail("InvalidPage for " + text)
        abort("failed")
      }
      Err(InvalidInputSchema) => {
        fail("InvalidInputSchema for " + text)
        abort("failed")
      }
      Err(ForeignSource) => {
        fail("ForeignSource for " + text)
        abort("failed")
      }
      Err(Value(name)) => {
        fail("Value " + name + " for " + text)
        abort("failed")
      }
      Err(MissingField(name)) => {
        fail("MissingField " + name + " for " + text)
        abort("failed")
      }
      Err(_) => {
        fail("other row issue for " + text)
        abort("failed")
      }
    }
    assert_eq(rows.length(), 2)
    assert_true(
      physical_equal(
        rows[0][0].contract,
        @schema.field_at(read.schema, 0).unwrap().contract,
      ),
    )
    let writer = @encode.writer(128, 4, 1)
    @admitted.emit_checked_wire_value(rows[0][0], writer)
    assert_eq(@encode.finish(writer), "\"" + text + "\"")
    assert_eq(accept_row_source_values(read, read.columns, rows).unwrap(), 2)
    let captured = @execution.finish_admitted_input(read.input).unwrap()
    assert_eq(@execution.captured_row_count(captured), 2)
    guard @execution.captured_cell(captured, 0, 0)
      is Some(@admitted.Signed64(value)) else {
      fail("exact signed64")
    }
    let exact = @decode.decimal_int64(row_presence_cursor("\"" + text + "\"")).unwrap()
    assert_eq(value, exact)
  }
}

///|
test "mock physical source refuses invalid unused fields keys and complete document structure before append" {
  let salesforce = mock_update_declaration()
  let snowflake = mock_document_warehouse()
  let original = mock_document_text()
  for
    wire in [
      original.replace(
        old="\"description\":\"Evaluating a competitor; usage down since June.\"",
        new="\"description\":7",
      ),
      original.replace(
        old="\"Risk_Reason__c\":null",
        new="\"Risk_Reason__c\":false",
      ),
      original.replace(old="\"key\":[\"id\"]", new="\"key\":[\"name\"]"),
      original.replace(
        old="\"001Globex\",\"active_users\"",
        new="\"001Acme\",\"active_users\"",
      ),
      original.replace(
        old="\"trend\":\"down\"",
        new="\"trend\":\"down\",\"extra\":true",
      ),
      original.replace(
        old="\"trend\":\"down\"",
        new="\"trend\":\"down\",\"trend\":\"up\"",
      ),
      original.replace(
        old="\"salesforce\":",
        new="\"foreign\":{},\"salesforce\":",
      ),
    ] {
    let read = mock_document_read()
    assert_true(
      mock_churn_risk_document_rows(
        read,
        snowflake,
        salesforce,
        snowflake,
        @utf8.encode(wire),
        10000000,
      )
      is Err(_),
    )
    let captured = @execution.finish_admitted_input(read.input).unwrap()
    assert_eq(@execution.captured_row_count(captured), 0)
  }
}

///|
test "mock physical integer codec refuses external strings fractional tokens and overflow" {
  let salesforce = mock_update_declaration()
  let snowflake = mock_document_warehouse()
  for
    token in [
      "\"4\"", "4.5", "4e0", "null", "9223372036854775808", "-9223372036854775809",
      "-0",
    ] {
    let read = mock_document_read()
    assert_true(
      mock_churn_risk_document_rows(
        read,
        snowflake,
        salesforce,
        snowflake,
        @utf8.encode(mock_document_text(count=token)),
        10000000,
      )
      is Err(_),
    )
  }
}

///|
test "mock physical codec retains explicit work and file byte bounds" {
  let salesforce = mock_update_declaration()
  let snowflake = mock_document_warehouse()
  for wire in [mock_document_text(), " ".repeat(65537)] {
    let read = mock_document_read()
    assert_true(
      mock_churn_risk_document_rows(
        read,
        snowflake,
        salesforce,
        snowflake,
        @utf8.encode(wire),
        0,
      )
      is Err(_),
    )
  }
  let read = mock_document_read()
  assert_true(
    mock_churn_risk_document_rows(
      read,
      snowflake,
      salesforce,
      snowflake,
      @utf8.encode(" ".repeat(65537)),
      10000000,
    )
    is Err(_),
  )
}

///|
test "mock Salesforce input retains both original keys and nullable values" {
  let salesforce = mock_update_declaration()
  let snowflake = mock_document_warehouse()
  let read = mock_document_read(warehouse=false)
  let rows = mock_churn_risk_document_rows(
    read,
    salesforce,
    salesforce,
    snowflake,
    @utf8.encode(mock_document_text()),
    10000000,
  ).unwrap()
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].length(), 5)
  for row in 0..<2 {
    for column in 0..<5 {
      assert_true(
        physical_equal(
          rows[row][column].contract,
          @schema.field_at(read.schema, column).unwrap().contract,
        ),
      )
    }
    assert_true(
      rows[row][read.columns.search("Risk_Reason__c").unwrap()].value
      is @admitted.Null,
    )
  }
  assert_eq(accept_row_source_values(read, read.columns, rows).unwrap(), 2)
  let captured = @execution.finish_admitted_input(read.input).unwrap()
  assert_true(
    @execution.captured_cell(captured, 0, read.columns.search("id").unwrap())
    is Some(@admitted.Text("001Acme")),
  )
  assert_true(
    @execution.captured_cell(captured, 1, read.columns.search("id").unwrap())
    is Some(@admitted.Text("001Globex")),
  )
}
