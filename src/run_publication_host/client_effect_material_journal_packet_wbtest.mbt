///|
// Independent six-field fixture framed with Python json, without product output.
fn effect_material_packet_test_original() -> ClientEffectMaterialJournalPacket {
  {
    intent_cid: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    materials_cid: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    materials_wire: "{\"payload\":\"é\\r\\n\",\"raw\":[true,null]}",
    request_scope_cid: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    run_definition_cid: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    submission_reference: "original-é\r\n-reference",
  }
}

///|
let effect_material_packet_test_wire = "{\"intent_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"materials_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"materials_wire\":\"{\\\"payload\\\":\\\"é\\\\r\\\\n\\\",\\\"raw\\\":[true,null]}\",\"request_scope_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"run_definition_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"submission_reference\":\"original-é\\r\\n-reference\"}"

///|
test "portable Effect material envelope retains all six exact original fields" {
  let original = effect_material_packet_test_original()
  assert_eq(
    client_effect_material_journal_packet_wire(original),
    Ok(effect_material_packet_test_wire),
  )
  let decoded = read_client_effect_material_journal_packet(
    effect_material_packet_test_wire,
  ).unwrap()
  assert_eq(decoded.intent_cid, original.intent_cid)
  assert_eq(decoded.materials_cid, original.materials_cid)
  assert_eq(decoded.materials_wire, original.materials_wire)
  assert_eq(decoded.request_scope_cid, original.request_scope_cid)
  assert_eq(decoded.run_definition_cid, original.run_definition_cid)
  assert_eq(decoded.submission_reference, original.submission_reference)
  assert_eq(
    client_effect_material_journal_packet_wire(decoded),
    Ok(effect_material_packet_test_wire),
  )
}

///|
test "portable Effect material envelope refuses missing duplicate noncanonical and empty original fields" {
  for
    wire in [
      effect_material_packet_test_wire + " ",
      effect_material_packet_test_wire.replace_all(old="{", new="{ "),
      effect_material_packet_test_wire.replace_all(
        old="\"intent_cid\":",
        new="\"unknown_field\":",
      ),
      effect_material_packet_test_wire.replace_all(
        old="\"intent_cid\":",
        new="\"materials_cid\":",
      ),
      client_effect_material_journal_packet_wire({
        ..effect_material_packet_test_original(),
        materials_wire: "",
      }).unwrap(),
      "{}",
    ] {
    assert_true(
      read_client_effect_material_journal_packet(wire) is Err(CustodyLost),
    )
  }
}

///|
test "portable Effect material envelope keeps its existing independent parser and writer limits" {
  let original = effect_material_packet_test_original()
  assert_eq(
    client_effect_material_journal_packet_wire({
      ..original,
      materials_wire: "x".repeat(131073),
    }),
    Err(CapacityExceeded),
  )
  assert_true(
    read_client_effect_material_journal_packet(" ".repeat(131073))
    is Err(CustodyLost),
  )
}
