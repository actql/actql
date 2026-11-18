///|
fn public_catalogue_wire_fixture() -> String {
  (
    #|{"views":[{"resource":"records雪","resource_kind":"record","schema":{"id":{"type":"string","nullable":false}}}]}
  )
}

///|
test "public catalogue wire construction projects the same original without a Native encoder policy" {
  let wire = public_catalogue_wire_fixture()
  let g = relation_public_projection_geometry(wire).unwrap()
  assert_true(g.input.bytes > g.input.units)
  assert_true(g.output_depth < 64)
  let projected = project_relation_declaration_wire_input(wire).unwrap()
  let expected = "{\"views\":[{\"resource\":\"records雪\",\"resource_kind\":\"record\",\"schema_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"schema_wire\":\"{\\\"id\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"}}\"}]}"
  assert_eq(projected, expected)
  assert_true(@utf8.encode(projected).length() <= g.output_bytes)
  // The projector preserves Unicode DATA; the existing declaration Owner
  // still refuses a non-identifier resource. Do not widen its name contract.
  assert_true(
    restore_relation_row_declaration(
      "original",
      "fixture",
      "fixture/0.1",
      projected,
      None,
    )
    is Err(Declaration(InvalidView)),
  )
}

///|
test "public catalogue wire construction quotes complete failure prefixes before parse" {
  let small = relation_public_projection_construction_inventory("{bad").unwrap()
  assert_true(
    small.record_headers > 0L &&
    small.owned_utf16_units > 0L &&
    small.owned_wire_bytes > 0L,
  )
  assert_true(
    project_relation_declaration_wire_input("{bad") is Err(InvalidSpecification),
  )
  assert_true(relation_public_projection_construction_inventory("") is None)
  assert_true(
    project_relation_declaration_wire_input("") is Err(InvalidSpecification),
  )
  let full = relation_public_projection_construction_inventory(
    public_catalogue_wire_fixture(),
  ).unwrap()
  assert_true(full.record_headers > small.record_headers)
  assert_true(full.reference_slots > small.reference_slots)
  assert_true(full.owned_utf16_units > small.owned_utf16_units)
  assert_true(full.owned_wire_bytes > small.owned_wire_bytes)
}

///|
test "public catalogue wire construction grows SAME original before constructors with exact and one short bounds" {
  let wire = public_catalogue_wire_fixture()
  let inventory = relation_public_projection_construction_inventory(wire).unwrap()
  let cost = @execution.preparation_representation_cost(inventory).unwrap()
  assert_true(cost > 0L)
  let r = 17L + cost
  let e = 23L + cost
  for (rs, es) in [(0L, 0L), (1L, 0L), (0L, 1L)] {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: r - rs,
      execution_bytes: e - es,
    }).unwrap()
    let original = @resources.reserve_attempt(ledger, 0L, 17L, 23L).unwrap()
    let grown = @resources.grow_execution_reservation_capacity(
      ledger, original, r, e,
    )
    if rs == 0L && es == 0L {
      grown.unwrap()
      let projected = project_relation_declaration_wire_input(wire).unwrap()
      assert_true(projected.contains("schema_wire"))
      assert_eq(@resources.ledger_usage(ledger).live_reservations, 1)
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, r)
    } else {
      if rs == 1L {
        assert_true(grown is Err(@resources.RetentionLimit))
      } else {
        assert_true(grown is Err(@resources.ExecutionLimit))
      }
      // No parse/projector ran, no debt was replaced/refunded on refusal.
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 17L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 23L)
    }
    @resources.settle_reservation(ledger, original).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
}
