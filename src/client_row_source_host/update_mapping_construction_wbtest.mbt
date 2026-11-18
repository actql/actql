///|
fn update_mapping_construction_sources() -> String {
  "[{\"target\":\"amount\",\"field\":\"新値😀\",\"null_behavior\":\"reject\"}]"
}

///|
test "UPDATE Mapping exact and one-short original funding precedes its real constructor" {
  let declaration = relation_mapping_declaration()
  let source_wire = update_mapping_construction_sources()
  let quantity = row_update_mapping_construction_capacity(
    declaration,
    relation_update_write_wire(),
    "records",
    source_wire,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quantity)
  let execution = @execution.execution_capacity_execution_bytes(quantity)
  assert_true(retained > 0L && execution > retained)
  let ascii = row_update_mapping_construction_capacity(
    declaration,
    relation_update_write_wire(),
    "records",
    source_wire.replace(old="新値😀", new="abcd"),
  ).unwrap()
  // Equal UTF16 length is not equal UTF8 hash/writer backing.
  assert_true(retained > @execution.execution_capacity_retained_bytes(ascii))
  // Catalog/export strings already belong to the declaration. This constructor
  // reads its original View/contract forest, not a second full export.
  let borrowed = { ..declaration, catalog: "x".repeat(100000), }
  let unchanged = row_update_mapping_construction_capacity(
    borrowed,
    relation_update_write_wire(),
    "records",
    source_wire,
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(unchanged), retained)
  assert_eq(@execution.execution_capacity_execution_bytes(unchanged), execution)
  for short in 0..<3 {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: retained - (if short == 1 { 1L } else { 0L }),
      execution_bytes: execution - (if short == 2 { 1L } else { 0L }),
    }).unwrap()
    let before = @resources.ledger_usage(ledger)
    let admitted = @resources.reserve_attempt(ledger, 0L, retained, execution)
    if short == 0 {
      let original = admitted.unwrap()
      let mapping = prepare_row_update_mapping(
        declaration,
        relation_update_write_wire(),
        "records",
        [{ target: "amount", field: "新値😀", null_behavior: "reject", }],
      ).unwrap()
      assert_true(mapping.body.contains("\"precision\":18"))
      assert_true(mapping.body.contains("\"type\":\"array\""))
      assert_eq(mapping.write_fields, ["amount"])
      assert_true(mapping.body.contains("新値😀"))
      @resources.mark_cleanup_pending(ledger, original).unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        retained,
      )
      @resources.settle_reservation(ledger, original).unwrap()
      assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    } else {
      assert_true(
        if short == 1 {
          admitted is Err(@resources.RetentionLimit)
        } else {
          admitted is Err(@resources.ExecutionLimit)
        },
      )
      assert_eq(@resources.ledger_usage(ledger), before)
    }
  }
}

///|
test "UPDATE Mapping sibling results keep separate retained debt and original identities" {
  let schema =
    #|{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}
  let declaration = generate_relation_row_declaration(
    "plural",
    "fixture",
    "fixture/0.1",
    ["first", "second"].map(resource => {
      resource,
      resource_kind: "record",
      schema_wire: schema,
      schema_cid: "sha256:a60151d1e83e0b400b04beb2388450687d5df24da1a177047fbd0d0a703d4fe8",
      request_schema_wire: None,
      facts_wire: None,
      acquisition_wire: None,
    }),
    delete_mapping_limits(),
  ).unwrap()
  let writes =
    #|{"writes":[{"resource":"first","primary_identity":"id","update":{"fields":["value"],"permission":"fixture:update","approval":"required"}},{"resource":"second","primary_identity":"id","update":{"fields":["value"],"permission":"fixture:update","approval":"required"}}]}
  let source_wire =
    #|[{"target":"value","field":"value","null_behavior":"reject"}]
  let first = row_update_mapping_construction_capacity(
    declaration, writes, "first", source_wire,
  ).unwrap()
  let second = row_update_mapping_construction_capacity(
    declaration, writes, "second", source_wire,
  ).unwrap()
  let r1 = @execution.execution_capacity_retained_bytes(first)
  let e1 = @execution.execution_capacity_execution_bytes(first)
  let r2 = @execution.execution_capacity_retained_bytes(second)
  let e2 = @execution.execution_capacity_execution_bytes(second)
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: r1 + r2,
    execution_bytes: Int64::max(e1, r1 + e2),
  }).unwrap()
  let one = @resources.reserve_capacity(ledger, r1, e1).unwrap()
  let sources = [{ target: "value", field: "value", null_behavior: "reject", }]
  let a = prepare_row_update_mapping(declaration, writes, "first", sources).unwrap()
  @resources.shrink_capacity_reservation(ledger, one, r1, r1).unwrap()
  let two = @resources.reserve_capacity(ledger, r2, e2).unwrap()
  let b = prepare_row_update_mapping(declaration, writes, "second", sources).unwrap()
  assert_true(a.mapping_cid != b.mapping_cid)
  assert_true(a.body.contains("connector://plural/first"))
  assert_true(b.body.contains("connector://plural/second"))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, r1 + r2)
  @resources.settle_capacity(ledger, two).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, r1)
  @resources.settle_capacity(ledger, one).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
