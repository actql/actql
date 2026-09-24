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
test "Effect member receipt admits applied and unattempted partial failure" {
  let preview = effect_receipt_test_cid("a")
  let applied = effect_receipt_test_cid("b")
  let unattempted = effect_receipt_test_cid("c")
  let body = effect_receipt_test_member_body(
    preview,
    preview,
    "[\"" + applied + "\"]",
    "[]",
    "partial_failure",
    "{\"state\":\"failed\",\"error\":{\"code\":\"halted\",\"message\":\"not attempted\"}}",
  ).replace_all(
    old="\"unattempted\":[]",
    new="\"unattempted\":[\"" + unattempted + "\"]",
  )
  for variant in 0..<2 {
    let candidate = if variant == 0 {
      body
    } else {
      body.replace_all(
        old="\"applied\":[\"" + applied + "\"],\"accepted\":[]",
        new="\"applied\":[],\"accepted\":[\"" + applied + "\"]",
      )
    }
    let receipt = seal_publication_contract(
      "effect_apply_receipt", candidate, 8192, 256, 16,
    ).unwrap()
    assert_true(
      admit_publication_contract(
        "effect_apply_receipt",
        publication_contract_json(receipt),
        8192,
        256,
        16,
      )
      is Ok(_),
    )
    assert_true(
      seal_publication_contract(
        "effect_apply_receipt",
        candidate.replace_all(
          old="\"status\":\"partial_failure\"",
          new="\"status\":\"failed\"",
        ),
        8192,
        256,
        16,
      )
      is Err(ConditionalField("status")),
    )
  }
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
fn effect_receipt_test_preview(empty? : Bool = false) -> EffectPreviewIdentity {
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
    empty~,
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
    empty~,
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
      empty~,
    ),
    run,
    authoring,
    8192,
    256,
    12,
  ).unwrap()
}

///|
fn effect_receipt_test_two_member_wire(
  run : String,
  authoring : String,
  first_cid : String,
  second_cid : String,
  preview_cid : String,
) -> String {
  let base = preview_identity_test_wire(
    run,
    authoring,
    effect_receipt_test_cid("4"),
    "001000000000001",
    first_cid,
    preview_cid,
  )
  let parsed = parse_effect_preview_shape(base, 16384, 512, 16).unwrap()
  let first_row = derive_effect_preview_row_identities(base, 16384, 512, 16).unwrap()[0][0]
  let first = match @json.object_field(parsed, "effects") {
    Some(@json.Array(items)) =>
      @json.stringify_value(@json.array_values(items)[0], 8192, 256, 12) catch {
        _ => abort("Expected a serializable Effect member")
      }
    _ => abort("Expected a single Effect member")
  }
  let second = first
    .replace_all(
      old="\"effect_id\":\"WriteOne\"",
      new="\"effect_id\":\"WriteTwo\"",
    )
    .replace_all(
      old="\"effect_member_preview_cid\":\"" + first_cid + "\"",
      new="\"effect_member_preview_cid\":\"" + second_cid + "\"",
    )
    .replace_all(
      old="\"row_preview_cid\":\"" + first_row + "\"",
      new="\"row_preview_cid\":\"" + effect_receipt_test_cid("5") + "\"",
    )
    .replace_all(
      old="\"row_order\":[\"" + first_row + "\"]",
      new="\"row_order\":[\"" + effect_receipt_test_cid("5") + "\"]",
    )
    .replace_all(
      old="\"row_idempotency_key\":\"" + effect_receipt_test_cid("4") + "\"",
      new="\"row_idempotency_key\":\"" + effect_receipt_test_cid("6") + "\"",
    )
    .replace_all(
      old="\"target_row_identity\":\"001000000000001\"",
      new="\"target_row_identity\":\"001000000000002\"",
    )
    .replace_all(
      old="\"provider_object_identity_cids\":[\"" +
        effect_receipt_test_cid("1") +
        "\"]",
      new="\"provider_object_identity_cids\":[\"" +
        effect_receipt_test_cid("2") +
        "\"]",
    )
  let provisional = base.replace_all(
    old="\"effects\":[" + first + "]",
    new="\"effects\":[" + first + "," + second + "]",
  )
  let rows = derive_effect_preview_row_identities(provisional, 16384, 512, 16).unwrap()
  provisional.replace_all(old=effect_receipt_test_cid("5"), new=rows[1][0])
}

///|
fn effect_receipt_test_two_member_preview() -> EffectPreviewIdentity {
  let run = effect_receipt_test_cid("b")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let placeholder = effect_receipt_test_cid("a")
  let (_, members) = derive_effect_preview_identities(
    effect_receipt_test_two_member_wire(
      run, authoring, placeholder, placeholder, placeholder,
    ),
    16384,
    512,
    16,
  ).unwrap()
  let fixed = effect_receipt_test_two_member_wire(
    run,
    authoring,
    members[0],
    members[1],
    placeholder,
  )
  let (preview_cid, _) = derive_effect_preview_identities(fixed, 16384, 512, 16).unwrap()
  admit_effect_preview_identity(
    effect_receipt_test_two_member_wire(
      run,
      authoring,
      members[0],
      members[1],
      preview_cid,
    ),
    run,
    authoring,
    16384,
    512,
    16,
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
  let row = effect_preview_row_identity(preview, 0, 0).unwrap()
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

///|
test "empty Effect member receipts still require the exact member identity" {
  let preview = effect_receipt_test_preview(empty=true)
  let preview_cid = effect_preview_semantic_identity(preview)
  let member_cid = effect_preview_member_identity(preview, 0).unwrap()
  assert_eq(effect_preview_row_count(preview, 0), Some(0))
  let body = effect_receipt_test_member_body(
    preview_cid, member_cid, "[]", "[]", "applied", "{\"state\":\"applied\",\"result\":{}}",
  )
  let exact = seal_publication_contract(
    "effect_apply_receipt", body, 8192, 256, 12,
  ).unwrap()
  assert_true(
    admit_effect_apply_receipt_for_member(
      preview,
      0,
      publication_contract_json(exact),
      8192,
      256,
      12,
    )
    is Ok(_),
  )
  let foreign = seal_publication_contract(
    "effect_apply_receipt",
    effect_receipt_test_member_body(
      preview_cid,
      effect_receipt_test_cid("d"),
      "[]",
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
    is Err(ForeignMember),
  )
}

///|
fn effect_receipt_test_set_body(
  preview_cid : String,
  member_cid : String,
  member_receipt_cid : String,
  effect_id : String,
) -> String {
  "{\"version\":\"actql-effect-set-apply-receipt/0.1\"," +
  "\"effect_preview_cid\":\"" +
  preview_cid +
  "\",\"apply_policy\":\"attempt_all\",\"effects\":[{" +
  "\"effect_id\":\"" +
  effect_id +
  "\",\"effect_member_preview_cid\":\"" +
  member_cid +
  "\",\"state\":\"applied\",\"replayed\":false," +
  "\"member_receipt_cid\":\"" +
  member_receipt_cid +
  "\"}],\"status\":\"applied\"}"
}

///|
test "Effect Set receipt references every exact Preview member receipt" {
  let preview = effect_receipt_test_preview()
  let preview_cid = effect_preview_semantic_identity(preview)
  let member_cid = effect_preview_member_identity(preview, 0).unwrap()
  let member_receipt = seal_publication_contract(
    "effect_apply_receipt",
    effect_receipt_test_member_body(
      preview_cid,
      member_cid,
      "[\"" + effect_preview_row_identity(preview, 0, 0).unwrap() + "\"]",
      "[]",
      "applied",
      "{\"state\":\"applied\",\"result\":{}}",
    ),
    8192,
    256,
    12,
  ).unwrap()
  let member_wires = [publication_contract_json(member_receipt)]
  let set = seal_publication_contract(
    "effect_set_apply_receipt",
    effect_receipt_test_set_body(
      preview_cid,
      member_cid,
      publication_contract_identity(member_receipt),
      "WriteOne",
    ),
    8192,
    256,
    12,
  ).unwrap()
  assert_true(
    admit_effect_set_apply_receipt_references(
      preview,
      publication_contract_json(set),
      member_wires,
      8192,
      256,
      12,
    )
    is Ok(_),
  )
  for
    (body, expected) in [
      (
        effect_receipt_test_set_body(
          preview_cid,
          member_cid,
          effect_receipt_test_cid("d"),
          "WriteOne",
        ),
        1,
      ),
      (
        effect_receipt_test_set_body(
          preview_cid,
          member_cid,
          publication_contract_identity(member_receipt),
          "Other",
        ),
        2,
      ),
      (
        effect_receipt_test_set_body(
          preview_cid,
          effect_receipt_test_cid("d"),
          publication_contract_identity(member_receipt),
          "WriteOne",
        ),
        3,
      ),
    ] {
    let wrong = seal_publication_contract(
      "effect_set_apply_receipt", body, 8192, 256, 12,
    ).unwrap()
    let result = admit_effect_set_apply_receipt_references(
      preview,
      publication_contract_json(wrong),
      member_wires,
      8192,
      256,
      12,
    )
    match expected {
      1 => assert_true(result is Err(ForeignMemberReceipt(0)))
      2 => assert_true(result is Err(ForeignEffectId(0)))
      _ => assert_true(result is Err(ForeignMember(0)))
    }
  }
}

///|
fn effect_receipt_test_set_entry(
  effect_id : String,
  member_cid : String,
  receipt_cid : String,
) -> String {
  "{\"effect_id\":\"" +
  effect_id +
  "\",\"effect_member_preview_cid\":\"" +
  member_cid +
  "\",\"state\":\"applied\",\"replayed\":false," +
  "\"member_receipt_cid\":\"" +
  receipt_cid +
  "\"}"
}

///|
test "Effect Set receipt closes two members regardless of dispatch order" {
  let preview = effect_receipt_test_two_member_preview()
  assert_eq(effect_preview_member_count(preview), 2)
  let preview_cid = effect_preview_semantic_identity(preview)
  let member_cids = [
    effect_preview_member_identity(preview, 0).unwrap(),
    effect_preview_member_identity(preview, 1).unwrap(),
  ]
  let receipts = [
    seal_publication_contract(
      "effect_apply_receipt",
      effect_receipt_test_member_body(
        preview_cid,
        member_cids[0],
        "[\"" + effect_preview_row_identity(preview, 0, 0).unwrap() + "\"]",
        "[]",
        "applied",
        "{\"state\":\"applied\",\"result\":{}}",
      ),
      8192,
      256,
      12,
    ).unwrap(),
    seal_publication_contract(
      "effect_apply_receipt",
      effect_receipt_test_member_body(
        preview_cid,
        member_cids[1],
        "[\"" + effect_preview_row_identity(preview, 1, 0).unwrap() + "\"]",
        "[]",
        "applied",
        "{\"state\":\"applied\",\"result\":{}}",
      ),
      8192,
      256,
      12,
    ).unwrap(),
  ]
  let wires = receipts.map(publication_contract_json)
  let first = effect_receipt_test_set_entry(
    "WriteOne",
    member_cids[0],
    publication_contract_identity(receipts[0]),
  )
  let second = effect_receipt_test_set_entry(
    "WriteTwo",
    member_cids[1],
    publication_contract_identity(receipts[1]),
  )
  for entries in [first + "," + second, second + "," + first] {
    let set = seal_publication_contract(
      "effect_set_apply_receipt",
      "{\"version\":\"actql-effect-set-apply-receipt/0.1\"," +
      "\"effect_preview_cid\":\"" +
      preview_cid +
      "\",\"apply_policy\":\"attempt_all\",\"effects\":[" +
      entries +
      "],\"status\":\"applied\"}",
      16384,
      512,
      16,
    ).unwrap()
    assert_true(
      admit_effect_set_apply_receipt_references(
        preview,
        publication_contract_json(set),
        wires,
        16384,
        512,
        16,
      )
      is Ok(_),
    )
  }
  let duplicate = seal_publication_contract(
    "effect_set_apply_receipt",
    "{\"version\":\"actql-effect-set-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"apply_policy\":\"attempt_all\",\"effects\":[" +
    first +
    "," +
    first +
    "],\"status\":\"applied\"}",
    16384,
    512,
    16,
  ).unwrap()
  assert_true(
    admit_effect_set_apply_receipt_references(
      preview,
      publication_contract_json(duplicate),
      wires,
      16384,
      512,
      16,
    )
    is Err(DuplicateMember(1)),
  )
  let wrong_state = seal_publication_contract(
    "effect_set_apply_receipt",
    "{\"version\":\"actql-effect-set-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"apply_policy\":\"attempt_all\",\"effects\":[" +
    first.replace_all(old="\"state\":\"applied\"", new="\"state\":\"failed\"") +
    "," +
    second +
    "],\"status\":\"applied\"}",
    16384,
    512,
    16,
  ).unwrap()
  assert_true(
    admit_effect_set_apply_receipt_references(
      preview,
      publication_contract_json(wrong_state),
      wires,
      16384,
      512,
      16,
    )
    is Err(MemberStateMismatch(0)),
  )
  let wrong_outcome = seal_publication_contract(
    "effect_set_apply_receipt",
    "{\"version\":\"actql-effect-set-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"apply_policy\":\"attempt_all\",\"effects\":[" +
    first.replace_all(
      old="\"replayed\":false,",
      new="\"outcome\":{\"state\":\"applied\",\"result\":{\"different\":true}},\"replayed\":false,",
    ) +
    "," +
    second +
    "],\"status\":\"applied\"}",
    16384,
    512,
    16,
  ).unwrap()
  assert_true(
    admit_effect_set_apply_receipt_references(
      preview,
      publication_contract_json(wrong_outcome),
      wires,
      16384,
      512,
      16,
    )
    is Err(MemberOutcomeMismatch(0)),
  )
  let wrong_status = seal_publication_contract(
    "effect_set_apply_receipt",
    "{\"version\":\"actql-effect-set-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"apply_policy\":\"attempt_all\",\"effects\":[" +
    first +
    "," +
    second +
    "],\"status\":\"failed\"}",
    16384,
    512,
    16,
  ).unwrap()
  assert_true(
    admit_effect_set_apply_receipt_references(
      preview,
      publication_contract_json(wrong_status),
      wires,
      16384,
      512,
      16,
    )
    is Err(SetStatusMismatch),
  )
  let failed_second = seal_publication_contract(
    "effect_apply_receipt",
    effect_receipt_test_member_body(
      preview_cid,
      member_cids[1],
      "[]",
      "[{\"row_preview_cid\":\"" +
      effect_preview_row_identity(preview, 1, 0).unwrap() +
      "\",\"error_cid\":\"" +
      effect_receipt_test_cid("7") +
      "\"}]",
      "failed",
      "{\"state\":\"failed\",\"error\":{\"code\":\"rejected\",\"message\":\"rejected\"}}",
    ),
    8192,
    256,
    12,
  ).unwrap()
  let failed_entry = effect_receipt_test_set_entry(
    "WriteTwo",
    member_cids[1],
    publication_contract_identity(failed_second),
  ).replace_all(old="\"state\":\"applied\"", new="\"state\":\"failed\"")
  let mixed = seal_publication_contract(
    "effect_set_apply_receipt",
    "{\"version\":\"actql-effect-set-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"apply_policy\":\"attempt_all\",\"effects\":[" +
    first +
    "," +
    failed_entry +
    "],\"status\":\"partial_failure\"}",
    16384,
    512,
    16,
  ).unwrap()
  assert_true(
    admit_effect_set_apply_receipt_references(
      preview,
      publication_contract_json(mixed),
      [wires[0], publication_contract_json(failed_second)],
      16384,
      512,
      16,
    )
    is Ok(_),
  )
}

///|
test "Effect Preview rejects duplicate member identifiers before receipt binding" {
  let placeholder = effect_receipt_test_cid("a")
  let wire = effect_receipt_test_two_member_wire(
    effect_receipt_test_cid("b"),
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    placeholder,
    placeholder,
    placeholder,
  ).replace_all(
    old="\"effect_id\":\"WriteTwo\"",
    new="\"effect_id\":\"WriteOne\"",
  )
  assert_true(
    derive_effect_preview_identities(wire, 16384, 512, 16) is Err(InvalidMember),
  )
}
