///|
fn effect_receipt_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn effect_receipt_test_reconciliation_body(
  terminal : String,
  sequence : String,
  previous : String,
  correlation : String,
) -> String {
  let cid = effect_receipt_test_cid("a")
  "{\"version\":\"actql-effect-reconciliation-receipt/0.1\"," +
  "\"effect_id\":\"WriteOne\",\"effect_set_receipt_cid\":\"" +
  cid +
  "\",\"prior_receipt_cid\":\"" +
  cid +
  "\",\"attempt_sequence\":" +
  sequence +
  ",\"terminal\":" +
  terminal +
  "," +
  previous +
  correlation +
  "\"outcome\":{\"state\":\"unknown\",\"command_id\":\"request-1\"," +
  "\"reconciliation_contract\":{\"id\":\"manual\",\"version\":\"0.1\"," +
  "\"cid\":\"" +
  cid +
  "\"},\"idempotency_key\":\"key-1\"," +
  "\"reason\":\"provider_outcome_unknown\"}}"
}

///|
test "Effect receipt schemas admit closed canonical bodies and self identities" {
  let cid = effect_receipt_test_cid("a")
  let row = effect_receipt_test_cid("b")
  let member_receipt = seal_publication_contract(
    "effect_apply_receipt",
    "{\"version\":\"actql-effect-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    cid +
    "\",\"effect_member_preview_cid\":\"" +
    cid +
    "\",\"applied\":[\"" +
    row +
    "\"],\"accepted\":[],\"unknown\":[],\"failed\":[]," +
    "\"unattempted\":[],\"status\":\"applied\"," +
    "\"outcome\":{\"state\":\"applied\",\"result\":{\"id\":\"001\"}}}",
    8192,
    256,
    16,
  ).unwrap()
  assert_eq(publication_contract_name(member_receipt), "effect_apply_receipt")
  assert_eq(
    publication_contract_identity(member_receipt),
    "sha256:ad67e9df7e023c77e6e3c1db0ef11988ec651f31172801cb36dec71cdce731dc",
  )
  let admitted = admit_publication_contract(
    "effect_apply_receipt",
    publication_contract_json(member_receipt),
    8192,
    256,
    16,
  ).unwrap()
  assert_eq(
    publication_contract_identity(admitted),
    publication_contract_identity(member_receipt),
  )
  let missing_member = publication_contract_json(member_receipt).replace_all(
    old="\"effect_member_preview_cid\":\"" + cid + "\",",
    new="",
  )
  assert_true(
    admit_publication_contract(
      "effect_apply_receipt", missing_member, 8192, 256, 16,
    )
    is Err(InvalidField("protocol_schema")),
  )
  assert_true(
    seal_publication_contract(
      "effect_apply_receipt",
      effect_receipt_test_member_body(
        cid,
        cid,
        "[\"" + row + "\"]",
        "[{\"row_preview_cid\":\"" + row + "\",\"error_cid\":\"" + cid + "\"}]",
        "applied",
        "{\"state\":\"applied\",\"result\":{}}",
      ),
      8192,
      256,
      16,
    )
    is Err(ConditionalField("status")),
  )
  assert_true(
    seal_publication_contract(
      "effect_apply_receipt",
      effect_receipt_test_member_body(
        cid,
        cid,
        "[\"" + row + "\"]",
        "[{\"row_preview_cid\":\"" + row + "\",\"error_cid\":\"" + cid + "\"}]",
        "partial_failure",
        "{\"state\":\"failed\",\"error\":{\"code\":\"rejected\",\"message\":\"rejected\"}}",
      ),
      8192,
      256,
      16,
    )
    is Err(ConditionalField("status")),
  )
  let set = seal_publication_contract(
    "effect_set_apply_receipt",
    "{\"version\":\"actql-effect-set-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    cid +
    "\",\"apply_policy\":\"attempt_all\",\"effects\":[{" +
    "\"effect_id\":\"WriteOne\",\"effect_member_preview_cid\":\"" +
    cid +
    "\",\"state\":\"applied\",\"replayed\":false," +
    "\"member_receipt_cid\":\"" +
    publication_contract_identity(member_receipt) +
    "\"}],\"status\":\"applied\"}",
    8192,
    256,
    16,
  ).unwrap()
  assert_eq(publication_contract_name(set), "effect_set_apply_receipt")
  let reconciliation = seal_publication_contract(
    "effect_reconciliation_receipt",
    effect_receipt_test_reconciliation_body(
      "false", "1", "", "\"command_id\":\"request-1\",\"idempotency_key\":\"key-1\",",
    ),
    8192,
    256,
    16,
  ).unwrap()
  assert_eq(
    publication_contract_name(reconciliation),
    "effect_reconciliation_receipt",
  )
}

///|
test "Effect reconciliation receipt enforces correlation and attempt conditions" {
  let command = "\"command_id\":\"request-1\",\"idempotency_key\":\"key-1\","
  let cid = effect_receipt_test_cid("a")
  let valid = effect_receipt_test_reconciliation_body("false", "1", "", command)
  assert_true(
    seal_publication_contract(
      "effect_reconciliation_receipt", valid, 8192, 256, 16,
    )
    is Ok(_),
  )
  for
    body in [
      effect_receipt_test_reconciliation_body("true", "1", "", command),
      effect_receipt_test_reconciliation_body("false", "2", "", command),
      effect_receipt_test_reconciliation_body(
        "false",
        "1",
        "\"previous_reconciliation_receipt_cid\":\"" + cid + "\",",
        command,
      ),
      effect_receipt_test_reconciliation_body("false", "1", "", ""),
      effect_receipt_test_reconciliation_body(
        "false",
        "1",
        "",
        command +
        "\"operation_ref\":{\"$actql_ref\":\"resource\",\"version\":\"actql-resource-ref/0.1\"," +
        "\"resource_kind\":\"operation\",\"provider_namespace\":\"sf\"," +
        "\"provider_identity_cid\":\"" +
        cid +
        "\",\"authority_scope_cid\":\"" +
        cid +
        "\",\"boundary_cid\":\"" +
        cid +
        "\",\"identity_cid\":\"" +
        cid +
        "\"},",
      ),
    ] {
    assert_true(
      seal_publication_contract(
        "effect_reconciliation_receipt", body, 8192, 256, 16,
      )
      is Err(_),
    )
  }
}

///|
fn effect_receipt_test_preview() -> EffectPreviewIdentity {
  let cid = effect_receipt_test_cid("a")
  let run = effect_receipt_test_cid("b")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let placeholder = preview_identity_test_wire(
    run,
    authoring,
    effect_receipt_test_cid("4"),
    "001000000000001",
    cid,
    cid,
  )
  let (_, members) = derive_effect_preview_identities(
    placeholder, 8192, 256, 12,
  ).unwrap()
  let member_fixed = preview_identity_test_wire(
    run,
    authoring,
    effect_receipt_test_cid("4"),
    "001000000000001",
    members[0],
    cid,
  )
  let (preview_cid, _) = derive_effect_preview_identities(
    member_fixed, 8192, 256, 12,
  ).unwrap()
  admit_effect_preview_identity(
    preview_identity_test_wire(
      run,
      authoring,
      effect_receipt_test_cid("4"),
      "001000000000001",
      members[0],
      preview_cid,
    ),
    run,
    authoring,
    8192,
    256,
    12,
  ).unwrap()
}

///|
fn effect_receipt_test_member_body(
  preview_cid : String,
  member_cid : String,
  applied : String,
  failed : String,
  status : String,
  outcome : String,
) -> String {
  "{\"version\":\"actql-effect-apply-receipt/0.1\"," +
  "\"effect_preview_cid\":\"" +
  preview_cid +
  "\",\"effect_member_preview_cid\":\"" +
  member_cid +
  "\",\"applied\":" +
  applied +
  ",\"accepted\":[],\"unknown\":[],\"failed\":" +
  failed +
  ",\"unattempted\":[],\"status\":\"" +
  status +
  "\",\"outcome\":" +
  outcome +
  "}"
}

///|
test "Effect apply receipt partitions exactly one admitted member inventory" {
  let preview = effect_receipt_test_preview()
  let preview_cid = effect_preview_semantic_identity(preview)
  let member_cid = effect_preview_member_identity(preview, 0).unwrap()
  let row = effect_receipt_test_cid("3")
  let good = seal_publication_contract(
    "effect_apply_receipt",
    effect_receipt_test_member_body(
      preview_cid,
      member_cid,
      "[\"" + row + "\"]",
      "[]",
      "applied",
      "{\"state\":\"applied\",\"result\":{}}",
    ),
    8192,
    256,
    12,
  ).unwrap()
  assert_true(
    admit_effect_apply_receipt_for_member(
      preview,
      0,
      publication_contract_json(good),
      8192,
      256,
      12,
    )
    is Ok(_),
  )
  let foreign = seal_publication_contract(
    "effect_apply_receipt",
    effect_receipt_test_member_body(
      effect_receipt_test_cid("c"),
      member_cid,
      "[\"" + row + "\"]",
      "[]",
      "applied",
      "{\"state\":\"applied\",\"result\":{}}",
    ),
    8192,
    256,
    12,
  ).unwrap()
  assert_true(
    admit_effect_apply_receipt_for_member(
      preview,
      0,
      publication_contract_json(foreign),
      8192,
      256,
      12,
    )
    is Err(ForeignPreview),
  )
  let foreign_member = seal_publication_contract(
    "effect_apply_receipt",
    effect_receipt_test_member_body(
      preview_cid,
      effect_receipt_test_cid("d"),
      "[\"" + row + "\"]",
      "[]",
      "applied",
      "{\"state\":\"applied\",\"result\":{}}",
    ),
    8192,
    256,
    12,
  ).unwrap()
  assert_true(
    admit_effect_apply_receipt_for_member(
      preview,
      0,
      publication_contract_json(foreign_member),
      8192,
      256,
      12,
    )
    is Err(ForeignMember),
  )
  for
    (applied, failed, status, outcome) in [
      ("[]", "[]", "applied", "{\"state\":\"applied\",\"result\":{}}"),
      (
        "[\"" + effect_receipt_test_cid("d") + "\"]",
        "[]",
        "applied",
        "{\"state\":\"applied\",\"result\":{}}",
      ),
    ] {
    let receipt = seal_publication_contract(
      "effect_apply_receipt",
      effect_receipt_test_member_body(
        preview_cid, member_cid, applied, failed, status, outcome,
      ),
      8192,
      256,
      12,
    ).unwrap()
    assert_true(
      admit_effect_apply_receipt_for_member(
        preview,
        0,
        publication_contract_json(receipt),
        8192,
        256,
        12,
      )
      is Err(RowPartitionMismatch),
    )
  }
}
