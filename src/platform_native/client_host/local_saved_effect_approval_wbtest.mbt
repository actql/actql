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

///|
test "Native saved review preserves complete original publication metadata without upgrading legacy DATA" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 4096,
    max_nodes: 128,
    max_depth: 4,
  }
  let legacy = saved_effect_review_codec_fixture()
  let suffix =
    #|,"result_derivation_wires":["derivation one","derivation two"],"result_ordering_wires":["ordering one","ordering two"],"result_retention_wires":["retention one","retention two"],"result_schema_wires":["schema one","schema two"],"result_codec_cids":["codec one","codec two"]}
  let current = legacy[0:legacy.length() - 1].to_owned() + suffix
  let fields = saved_effect_review_fields(current, limits).unwrap()
  assert_eq(saved_effect_review_texts(fields, "result_schema_wires").unwrap(), [
    "schema one", "schema two",
  ])
  assert_true(
    saved_effect_review_contracts(
      fields, "result_derivation_wires", "derivation_evidence", limits,
    )
    is Err(CustodyLost),
  )
  let old_fields = saved_effect_review_fields(legacy, limits).unwrap()
  assert_true(
    saved_effect_review_texts(old_fields, "result_schema_wires")
    is Err(CustodyLost),
  )
  for
    (old, replacement) in [
      (
        (
          #|,"result_codec_cids":["codec one","codec two"]
        ),
        "",
      ),
      (
        (
          #|["schema one","schema two"]
        ),
        (
          #|["schema one"]
        ),
      ),
      (
        (
          #|["retention one","retention two"]
        ),
        (
          #|["retention one",null]
        ),
      ),
    ] {
    assert_true(
      saved_effect_review_fields(
        current.replace_all(old~, new=replacement),
        limits,
      )
      is Err(CustodyLost),
    )
  }
}

///|
test "Native saved review closed codec accepts same one-use observed cursor" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 4096,
    max_nodes: 128,
    max_depth: 4,
  }
  let (preflight, _) = saved_effect_observed_fixture(
    saved_effect_review_codec_fixture(),
    limits,
  )
  defer @source.cancel_json_source_preflight(preflight)
  let cursor = saved_effect_admit_preflight(preflight, limits).unwrap()
  let fields = saved_effect_review_fields_from_cursor(cursor).unwrap()
  assert_eq(epoch_text(fields, "review_wire"), Some("preview original"))
  assert_eq(
    saved_effect_review_texts(fields, "result_definition_wires").unwrap(),
    ["definition one", "definition two"],
  )
  assert_true(saved_effect_admit_preflight(preflight, limits) is Err(_))
}
