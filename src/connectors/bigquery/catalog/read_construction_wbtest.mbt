///|
fn construction_declaration_limits() -> @rows.RowDeclarationLimits {
  { max_bytes: 200000, max_nodes: 20000, max_depth: 32, max_views: 1, max_fields: 32 }
}

///|
test "BigQuery initialization quote precedes its actual description and declaration originals" {
  let bytes = body([field("COUNT", "INT64"), field("NAME", "STRING")])
  let description_limits = limits()
  let declaration_limits = construction_declaration_limits()
  let capacity = read_declaration_construction_capacity(
    bytes.length(), 4 * ((bytes.length() + 2) / 3), 24, 5, 8, 12,
    description_limits, declaration_limits,
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(capacity)
  assert_true(peak > 0L)
  // A quantity is not an original, issuance, or evidence of cleanup. This
  // implementation deliberately retains the full peak through retirement.
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), peak)
  let ledger = @resources.create_ledger({
    planning_work: 1, attempts: 1, holdings: 1, transfer_bytes: 0L,
    retained_bytes: peak, execution_bytes: peak,
  }).unwrap()
  let reservation = @resources.reserve_capacity(ledger, peak, peak).unwrap()
  let description = project_table_description(target(), bytes, description_limits).unwrap()
  let projection = prepare_read_projection(description, ["COUNT", "NAME"], description_limits).unwrap()
  assert_true(read_projection_matches_description(projection, description))
  let declaration = generate_read_declaration(
    projection, "usage", "bigquery", "bigquery/0.1", declaration_limits,
  ).unwrap()
  assert_eq(declaration.connector_registration, "bigquery")
  assert_eq(declaration.views.length(), 1)
  assert_eq(declaration.views[0].source_ref, "connector://bigquery/usage#records")
  assert_eq(declaration.views[0].fields, ["COUNT", "NAME"])
  @resources.settle_capacity(ledger, reservation).unwrap()
  assert_false(@resources.ledger_usage_has_pending_resources(@resources.ledger_usage(ledger)))
}

///|
test "BigQuery construction quote refuses invalid and overflowing demand without constructor entry" {
  let description = limits()
  let declaration = construction_declaration_limits()
  assert_true(read_declaration_construction_capacity(
    -1, 0, 0, 0, 0, 0, description, declaration,
  ) is None)
  assert_true(read_declaration_construction_capacity(
    description.max_bytes + 1, 0, 0, 0, 0, 0, description, declaration,
  ) is None)
  assert_true(read_declaration_construction_capacity(
    1, 1, 0, 0, 0, 0, { ..description, max_fields: 0 }, declaration,
  ) is None)
  assert_true(read_declaration_construction_capacity(
    1, 1, 0, 2147483647, 2147483647, 2147483647, description, declaration,
  ) is None)
}

///|
test "BigQuery quote preserves independent input and declared output bounds" {
  let description = limits()
  let declaration = construction_declaration_limits()
  let quote = fn(bytes, encoded, declared) {
    read_declaration_construction_capacity(bytes, encoded, 24, 5, 8, 12,
      description, declared).unwrap()
  }
  let small = @execution.execution_capacity_execution_bytes(quote(200, 268, declaration))
  let large = @execution.execution_capacity_execution_bytes(quote(400, 536, declaration))
  assert_true(large > small)
  // Raising a safety ceiling does not enlarge a producer's actual syntax.
  assert_eq(@execution.execution_capacity_execution_bytes(quote(200, 268,
    { ..declaration, max_bytes: declaration.max_bytes + 1 })), small)
}

///|
test "BigQuery constructor demand is refused by the real Ledger before any original is constructed" {
  let capacity = read_declaration_construction_capacity(
    200, 268, 24, 5, 8, 12, limits(), construction_declaration_limits(),
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(capacity)
  let ledger = @resources.create_ledger({
    planning_work: 1, attempts: 1, holdings: 1, transfer_bytes: 0L,
    retained_bytes: peak - 1L, execution_bytes: peak,
  }).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(@resources.reserve_capacity(ledger, peak, peak) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), before)
}

///|
test "BigQuery ordinary fixture reports its constructor quantity under unchanged Host budget" {
  let description : DescriptionLimits = {
    max_bytes: 8192, max_nodes: 2000, max_depth: 24, max_fields: 16,
    max_name_bytes: 512, max_schema_bytes: 4096,
  }
  let declaration : @rows.RowDeclarationLimits = {
    max_bytes: 200000, max_nodes: 20000, max_depth: 24, max_views: 1, max_fields: 16,
  }
  let one = body([field("ACCOUNT_ID", "STRING")])
  let nested = body([
    field("ACCOUNT_ID", "STRING"),
    field("ATTRIBUTES", "RECORD", children=Some([
      field("COUNT", "INT64"),
      field("LABEL", "STRING"),
      field("CHILDREN", "RECORD", mode=Some("REPEATED"), children=Some([
        field("KEY", "STRING"), field("VALUE", "FLOAT64"),
      ])),
    ])),
  ])
  for bytes in [one, nested] {
    let capacity = read_declaration_construction_capacity(
      bytes.length(), 4 * ((bytes.length() + 2) / 3), 24, 5, 8, 12,
      description, declaration,
    ).unwrap()
    let peak = @execution.execution_capacity_execution_bytes(capacity)
    println("BigQuery constructor body_bytes=\{bytes.length()} peak_bytes=\{peak}")
    // This tests the unchanged ordinary total, not permission to increase it.
    // Host baseline/other holdings must still fit in the integration fixture.
    assert_true(peak < 536870912L)
  }
}

///|
test "BigQuery constructor quote funds Unicode and repeated nested decimal originals" {
  let raw = body([
    field("顧客", "STRING"),
    field("明細", "RECORD", mode=Some("REPEATED"), children=Some([
      field("金額", "NUMERIC", precision=Some("38".to_json()), scale=Some("9".to_json())),
      field("引用\"\\名", "STRING"),
    ])),
  ])
  let description_limits = limits()
  let declaration_limits = construction_declaration_limits()
  let capacity = read_declaration_construction_capacity(
    raw.length(), 4 * ((raw.length() + 2) / 3), 24, 5, 8, 12,
    description_limits, declaration_limits,
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(capacity)
  let ledger = @resources.create_ledger({
    planning_work: 1, attempts: 1, holdings: 1, transfer_bytes: 0L,
    retained_bytes: peak, execution_bytes: peak,
  }).unwrap()
  let reservation = @resources.reserve_capacity(ledger, peak, peak).unwrap()
  let original = project_table_description(target(), raw, description_limits).unwrap()
  let projection = prepare_read_projection(original, ["顧客", "明細"], description_limits).unwrap()
  assert_true(read_projection_matches_description(projection, original))
  let declaration = generate_read_declaration(
    projection, "usage", "bigquery", "bigquery/0.1", declaration_limits,
  ).unwrap()
  assert_eq(declaration.views[0].fields, ["明細", "顧客"])
  let (schemas, capabilities) = @rows.row_declaration_evidence_members(declaration)
  assert_eq(schemas.length(), 1)
  assert_eq(capabilities.length(), 1)
  @resources.settle_capacity(ledger, reservation).unwrap()
  assert_false(@resources.ledger_usage_has_pending_resources(@resources.ledger_usage(ledger)))
}

///|
test "BigQuery constructor quote preserves exact field and metadata depth boundaries" {
  let fields = [field("A", "STRING"), field("B", "INT64"), field("C", "BOOL")]
  let exact : DescriptionLimits = { ..limits(), max_fields: 3, max_depth: 4 }
  let raw = body(fields)
  let declared = construction_declaration_limits()
  let capacity = read_declaration_construction_capacity(
    raw.length(), 4 * ((raw.length() + 2) / 3), 24, 5, 8, 12, exact, declared,
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(capacity)
  let ledger = @resources.create_ledger({
    planning_work: 1, attempts: 1, holdings: 1, transfer_bytes: 0L,
    retained_bytes: peak, execution_bytes: peak,
  }).unwrap()
  let reservation = @resources.reserve_capacity(ledger, peak, peak).unwrap()
  let original = project_table_description(target(), raw, exact).unwrap()
  assert_eq(description_column_count(original), 3)
  let projection = prepare_read_projection(original, ["A", "B", "C"], exact).unwrap()
  let declaration = generate_read_declaration(
    projection, "usage", "bigquery", "bigquery/0.1", declared,
  ).unwrap()
  assert_eq(declaration.views[0].fields, ["A", "B", "C"])
  @resources.settle_capacity(ledger, reservation).unwrap()
  for refused in [{ ..exact, max_fields: 2 }, { ..exact, max_depth: 3 }, { ..exact, max_nodes: 1 }] {
    let refusal_capacity = read_declaration_construction_capacity(
      raw.length(), 4 * ((raw.length() + 2) / 3), 24, 5, 8, 12, refused, declared,
    ).unwrap()
    let refusal_peak = @execution.execution_capacity_execution_bytes(refusal_capacity)
    let refusal_ledger = @resources.create_ledger({
      planning_work: 1, attempts: 1, holdings: 1, transfer_bytes: 0L,
      retained_bytes: refusal_peak, execution_bytes: refusal_peak,
    }).unwrap()
    let held = @resources.reserve_capacity(refusal_ledger, refusal_peak, refusal_peak).unwrap()
    assert_true(project_table_description(target(), raw, refused) is Err(_))
    @resources.settle_capacity(refusal_ledger, held).unwrap()
    assert_false(@resources.ledger_usage_has_pending_resources(@resources.ledger_usage(refusal_ledger)))
  }
}
