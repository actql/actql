///|
fn saved_effect_review_codec_fixture() -> String {
  (
    // Codec DATA only: these deliberately are not admitted computation bodies,
    // a persisted Checkpoint, a current approval scope or a signing authority.
    #|{"version":"actql-native-local-effect-review/0.1","provider":"native-local-project-mock","request_scope_cid":"request-scope","authority_scope_cid":"authority","request_id":"request","run_definition_wire":"run original","invocation_wire":"invocation original","result_manifest_wire":"manifest original","computation_receipt_wire":"receipt original","captured_run_wire":"capture original","review_wire":"preview original","authoring_context_cid":"authoring original","result_definition_wires":["definition one","definition two"],"result_artifact_wires":["artifact one","artifact two"]}
  )
}

///|
test "Native saved review wire retains the authored ordered original DATA" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 4096,
    max_nodes: 64,
    max_depth: 4,
  }
  let original = saved_effect_review_codec_fixture()
  let fields = saved_effect_review_fields(original, limits).unwrap()
  assert_eq(epoch_text(fields, "run_definition_wire"), Some("run original"))
  assert_eq(epoch_text(fields, "review_wire"), Some("preview original"))
  let array = @decode.lookup(fields, "result_definition_wires").unwrap()
  let elements = @decode.elements(array).unwrap()
  assert_eq(elements.length(), 2)
  assert_eq(@decode.text(elements[0]).unwrap(), "definition one")
  assert_eq(@decode.text(elements[1]).unwrap(), "definition two")
  // Shape admission never promotes those strings to a PublicationContract.
  assert_true(
    saved_effect_review_contract(
      fields, "invocation_wire", "run_invocation", limits,
    )
    is Err(CustodyLost),
  )
}

///|
test "Native saved review wire refuses missing duplicate foreign and malformed fields" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 4096,
    max_nodes: 64,
    max_depth: 4,
  }
  let original = saved_effect_review_codec_fixture()
  for
    (old, replacement) in [
      ("\"version\":\"actql-native-local-effect-review/0.1\",", ""),
      (
        "\"request_id\":\"request\"", "\"request_id\":\"request\",\"request_id\":\"other\"",
      ),
      (
        "\"request_id\":\"request\"", "\"request_id\":\"request\",\"extra\":true",
      ),
      ("native-local-project-mock", "foreign-provider"),
      ("[\"definition one\",\"definition two\"]", "[1]"),
      ("[\"artifact one\",\"artifact two\"]", "null"),
    ] {
    assert_true(
      saved_effect_review_fields(
        original.replace_all(old~, new=replacement),
        limits,
      )
      is Err(CustodyLost),
    )
  }
  assert_true(
    saved_effect_review_fields(original, { ..limits, max_wire_bytes: 8, })
    is Err(CustodyLost),
  )
}
