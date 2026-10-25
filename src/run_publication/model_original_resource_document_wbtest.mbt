///|
fn original_resource_document_vector() -> String {
  (
    // Independently authored complete owned artifact, not issuer output. Every
    // origin CID has a distinct value; raw decomposed Unicode/CRLF is intentional.
    #|{"cut":null,"origin":{"barrier_cid":"sha256:7777777777777777777777777777777777777777777777777777777777777777","execution_context_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","host_policy_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","layout_artifact_cid":"sha256:9999999999999999999999999999999999999999999999999999999999999999","parameter_values_cid":"sha256:6666666666666666666666666666666666666666666666666666666666666666","prepared_invocation_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","program_definition_cid":"sha256:5555555555555555555555555555555555555555555555555555555555555555","response_profile_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","run_definition_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","run_id":"original-é\r\n","runtime_artifact_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","storage_binding_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"resource_phase":"preparation_base","resource_state":["actql-original-ledger-state/0.1",["17","2","3","11","10","7"],["17","0","0","0","0","0","0","10","7","10","0","2","0"],["0","0","0"],null,[["0","0","0"],["0","0","0"],["0","0","0"]],["-3","0","0"],["1","0","0",true,true,false,"reading",true],["-1","0","3","2",true,false,null,null,[false,false,false],null,false,false],[["-2","0","7","5",true,false,null,null,[false,false,false],null,false,false]],[],[]],"resource_state_cid":"sha256:7ed6db2394d7eaa87d65b022a6bc78f722efaf7a0293115de52c09a89893aae9","version":"actql-model-original-resource-state/0.1"}
  )
}

///|
test "original resource document verifies independent whole bytes and embedded identity" {
  let wire = original_resource_document_vector()
  assert_eq(@utf8.encode(wire).length(), 1713)
  assert_eq(
    @sha.hex(@utf8.encode(wire)),
    "0c15b2030233db5aafb6ee124784d0e4e414ff8500ac9dc8ad5ee74b3b25a7cd",
  )
  let document = read_model_original_resource_document(wire, 1713, 200, 16).unwrap()
  assert_eq(
    model_original_resource_origin_field(document, "run_id"),
    Some("original-é\r\n"),
  )
  assert_eq(
    model_original_resource_origin_field(document, "run_definition_cid"),
    Some("sha256:" + "1".repeat(64)),
  )
  assert_eq(
    model_original_resource_origin_field(document, "storage_binding_cid"),
    Some("sha256:" + "b".repeat(64)),
  )
  assert_eq(model_original_resource_origin_field(document, "ledger"), None)
  // This data handle exposes neither original Ledger nor current/send grant.
  assert_true(
    read_model_original_resource_document(wire, 1712, 200, 16) is Err(_),
  )
}

///|
test "original resource document refuses CID mismatch lexical rewrite and open fields" {
  let wire = original_resource_document_vector()
  for
    changed in [
      wire.replace(
        old="7ed6db2394d7eaa87d65b022a6bc78f722efaf7a0293115de52c09a89893aae9",
        new="0".repeat(64),
      ),
      wire.replace(old="\"17\",\"2\"", new="\"18\",\"2\""),
      wire.replace(old="\"-3\"", new="\"-0\""),
      wire.replace(old="{\"cut\":null", new="{\"cut\": null"),
      wire.replace(old="\"cut\":null", new="\"cut\":null,\"ledger\":null"),
      wire.replace(old="preparation_base", new="parked"),
    ] {
    assert_true(
      read_model_original_resource_document(changed, 10000, 1000, 16) is Err(_),
    )
  }
  // Data strings are not NFC-normalized by either admission or embedded CID.
  let composed = wire.replace(old="original-é", new="original-é")
  let document = read_model_original_resource_document(
    composed, 10000, 1000, 16,
  ).unwrap()
  assert_eq(
    model_original_resource_origin_field(document, "run_id"),
    Some("original-é\r\n"),
  )
}
