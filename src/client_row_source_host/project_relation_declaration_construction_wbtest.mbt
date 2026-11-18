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

///|
fn public_catalogue_long_text_wire(text : String) -> String {
  "{\"views\":[{\"resource\":\"records\",\"resource_kind\":\"record\",\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false}},\"facts\":{\"note\":" +
  Json::string(text).stringify() +
  "}}]}"
}

///|
test "public catalogue structural quote keeps equal AST nodes for long punctuation and escaped Text" {
  for text in ["{}[]:,".repeat(512), "\\\"{}[]:,".repeat(512)] {
    let ordinary = public_catalogue_long_text_wire("a".repeat(text.length()))
    let punctuated = public_catalogue_long_text_wire(text)
    let plain = relation_public_projection_geometry(ordinary).unwrap()
    let escaped = relation_public_projection_geometry(punctuated).unwrap()
    // Independent literal fixture: six containers, nine ':' and four ','.
    // Initial scalar slot1 + 2*6 + 9 + 4 =26, independent of Text content.
    assert_eq(plain.input.nodes, 26)
    assert_eq(escaped.input.nodes, 26)
    assert_eq(plain.output_nodes, escaped.output_nodes)
    assert_eq(plain.aggregate_depth, escaped.aggregate_depth)
    assert_eq(plain.input.depth, escaped.input.depth)
    let a = relation_public_projection_construction_inventory(ordinary).unwrap()
    let b = relation_public_projection_construction_inventory(punctuated).unwrap()
    assert_eq(a.record_headers, b.record_headers)
    assert_eq(a.reference_slots, b.reference_slots)
    assert_true(b.owned_utf16_units >= a.owned_utf16_units)
    assert_true(b.owned_wire_bytes >= a.owned_wire_bytes)
  }
  // Unterminated quoted Text is still funded before the same parser refuses.
  // Its many punctuation characters do not invent allocated AST children.
  let incomplete = "{\"views\":[{\"resource\":\"records\",\"resource_kind\":\"record\",\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false}},\"facts\":{\"note\":\"" +
    "{}[]:,".repeat(512)
  assert_eq(
    relation_public_projection_geometry(incomplete).unwrap().input.nodes,
    26,
  )
  assert_true(
    relation_public_projection_construction_inventory(incomplete) is Some(_),
  )
  assert_true(
    project_relation_declaration_wire_input(incomplete)
    is Err(InvalidSpecification),
  )
}

///|
test "public catalogue structural quote retains escaped output and SAME original resource boundaries" {
  let text = "\\\"{}[]:,".repeat(512)
  let wire = public_catalogue_long_text_wire(text)
  let geometry = relation_public_projection_geometry(wire).unwrap()
  let inventory = relation_public_projection_construction_inventory(wire).unwrap()
  let cost = @execution.preparation_representation_cost(inventory).unwrap()
  for (rs, es) in [(0L, 0L), (1L, 0L), (0L, 1L)] {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 17L + cost - rs,
      execution_bytes: 23L + cost - es,
    }).unwrap()
    let original = @resources.reserve_attempt(ledger, 0L, 17L, 23L).unwrap()
    let grown = @resources.grow_execution_reservation_capacity(
      ledger,
      original,
      17L + cost,
      23L + cost,
    )
    if rs == 0L && es == 0L {
      grown.unwrap()
      let output = project_relation_declaration_wire_input(wire).unwrap()
      let bytes = @utf8.encode(output).length()
      assert_true(bytes <= geometry.output_bytes)
      let entry = @json.parse(wire) catch { _ => fail("fixture") }
      assert_eq(
        project_relation_declaration_input(
          entry,
          bytes,
          geometry.output_nodes,
          geometry.output_depth,
        ).unwrap(),
        output,
      )
      assert_true(
        project_relation_declaration_input(
          entry,
          bytes - 1,
          geometry.output_nodes,
          geometry.output_depth,
        )
        is Err(InvalidSpecification),
      )
      let parsed = @json.parse(output) catch { _ => fail("output") }
      guard parsed is Object(root) &&
        root.get("views") is Some(Array(views)) &&
        views[0] is Object(fields) &&
        fields.get("facts_wire") is Some(String(facts)) else {
        fail("saved facts")
      }
      let saved = @json.parse(facts) catch { _ => fail("facts") }
      guard saved is Object(values) &&
        values.get("note") is Some(String(actual)) else {
        fail("saved Text")
      }
      assert_eq(actual, text)
      assert_eq(@resources.ledger_usage(ledger).live_reservations, 1)
    } else {
      if rs == 1L {
        assert_true(grown is Err(@resources.RetentionLimit))
      } else {
        assert_true(grown is Err(@resources.ExecutionLimit))
      }
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 17L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 23L)
    }
    @resources.settle_reservation(ledger, original).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
}
