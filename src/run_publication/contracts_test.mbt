///|
fn contract_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
test "Run Invocation has one portable canonical identity owner" {
  let body = "{\"version\":\"actql-run-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    contract_cid("1") +
    "\",\"observation_set_cid\":\"" +
    contract_cid("2") +
    "\"}"
  let contract = seal_publication_contract("run_invocation", body, 4096, 32, 4).unwrap()
  assert_eq(publication_contract_name(contract), "run_invocation")
  assert_eq(publication_contract_identity_field(contract), "invocation_cid")
  assert_eq(
    publication_contract_identity(contract),
    "sha256:49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18",
  )
  let complete = "{\"invocation_cid\":\"sha256:" +
    "49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18" +
    "\",\"invocation_template_cid\":\"" +
    contract_cid("1") +
    "\",\"observation_set_cid\":\"" +
    contract_cid("2") +
    "\",\"version\":\"actql-run-invocation/0.1\"}"
  assert_eq(publication_contract_json(contract), complete)
  let admitted = admit_publication_contract(
    "run_invocation", complete, 4096, 32, 4,
  ).unwrap()
  assert_eq(publication_contract_json(admitted), complete)
}

///|
test "Run Definition and Result Artifact use fixed independent identities" {
  let run = seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\"," +
    "\"scope_id\":\"scope\",\"run_id\":\"run\"," +
    "\"compiled_plan_cid\":\"" +
    contract_cid("1") +
    "\",\"invocation_template_cid\":\"" +
    contract_cid("2") +
    "\",\"authorization_context_cid\":\"" +
    contract_cid("3") +
    "\",\"input_artifact_set_cid\":\"" +
    contract_cid("4") +
    "\",\"created_at\":\"2026-09-18T00:00:00.000Z\"," +
    "\"valid_until\":\"2026-09-18T01:00:00.000Z\"}",
    8192,
    64,
    4,
  ).unwrap()
  assert_eq(
    publication_contract_identity(run),
    "sha256:4a288ff6406340fbcf51438ee9f493b1cb32c8d804be16cab0774cdbdfe3484f",
  )
  let artifact = seal_publication_contract(
    "result_artifact",
    "{\"version\":\"actql-result-artifact/0.1\"," +
    "\"result_definition_cid\":\"" +
    contract_cid("1") +
    "\",\"invocation_cid\":\"" +
    contract_cid("2") +
    "\",\"logical_result_cid\":\"" +
    contract_cid("3") +
    "\",\"result_schema_cid\":\"" +
    contract_cid("7") +
    "\",\"ordering_evidence_cid\":\"" +
    contract_cid("4") +
    "\",\"actual_row_count\":2,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    contract_cid("5") +
    "\",\"effective_retention_policy_cid\":\"" +
    contract_cid("6") +
    "\",\"provenance_evidence_cids\":[]}",
    8192,
    64,
    4,
  ).unwrap()
  assert_eq(
    publication_contract_identity(artifact),
    "sha256:ffd75122db1282710004afc340b1777265d292e05006b8143f658262a85a2914",
  )
}

///|
fn chain_artifact(
  definition : ResultDefinition,
  invocation : PublicationContract,
  digit : String,
) -> PublicationContract {
  seal_publication_contract(
    "result_artifact",
    "{\"version\":\"actql-result-artifact/0.1\"," +
    "\"result_definition_cid\":\"" +
    result_definition_cid(definition) +
    "\",\"invocation_cid\":\"" +
    publication_contract_identity(invocation) +
    "\",\"logical_result_cid\":\"" +
    contract_cid(digit) +
    "\",\"result_schema_cid\":\"" +
    contract_cid("7") +
    "\",\"ordering_evidence_cid\":\"" +
    contract_cid("8") +
    "\",\"actual_row_count\":1,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    contract_cid("5") +
    "\",\"effective_retention_policy_cid\":\"" +
    contract_cid("6") +
    "\",\"provenance_evidence_cids\":[]}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
test "Run publication chain fixes every declared Result exactly once" {
  let template = contract_cid("2")
  let run = seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\"," +
    "\"scope_id\":\"scope\",\"run_id\":\"run\"," +
    "\"compiled_plan_cid\":\"" +
    contract_cid("1") +
    "\",\"invocation_template_cid\":\"" +
    template +
    "\",\"authorization_context_cid\":\"" +
    contract_cid("3") +
    "\",\"input_artifact_set_cid\":\"" +
    contract_cid("4") +
    "\",\"created_at\":\"2026-09-18T00:00:00.000Z\"," +
    "\"valid_until\":\"2026-09-18T01:00:00.000Z\"}",
    8192,
    64,
    4,
  ).unwrap()
  let invocation = seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    template +
    "\",\"observation_set_cid\":\"" +
    contract_cid("9") +
    "\"}",
    8192,
    64,
    4,
  ).unwrap()
  let answer = prepare_result_definition(contract_cid("a"), "answer").unwrap()
  let detail = prepare_result_definition(contract_cid("a"), "detail").unwrap()
  let answer_artifact = chain_artifact(answer, invocation, "b")
  let detail_artifact = chain_artifact(detail, invocation, "c")
  let manifest = seal_publication_contract(
    "result_manifest",
    "{\"version\":\"actql-result-manifest/0.1\"," +
    "\"run_definition_cid\":\"" +
    publication_contract_identity(run) +
    "\",\"invocation_cid\":\"" +
    publication_contract_identity(invocation) +
    "\",\"results\":{\"answer\":" +
    publication_contract_json(answer_artifact) +
    ",\"detail\":" +
    publication_contract_json(detail_artifact) +
    "}}",
    65536,
    512,
    12,
  ).unwrap()
  assert_true(
    validate_run_publication_chain(
      run,
      invocation,
      [result_definition_contract(answer), result_definition_contract(detail)],
      [answer_artifact, detail_artifact],
      manifest,
      65536,
      512,
      12,
    )
    is Ok(_),
  )
  assert_true(
    validate_run_publication_chain(
      run,
      invocation,
      [result_definition_contract(answer), result_definition_contract(detail)],
      [answer_artifact],
      manifest,
      65536,
      512,
      12,
    )
    is Err(ChainArtifactMismatch("inventory")),
  )
}

///|
test "Manifest sealing rejects a nested Artifact with a false self identity" {
  let c = contract_cid("1")
  let false_artifact = "{\"version\":\"actql-result-artifact/0.1\"," +
    "\"result_definition_cid\":\"" +
    c +
    "\",\"invocation_cid\":\"" +
    c +
    "\",\"logical_result_cid\":\"" +
    c +
    "\",\"result_schema_cid\":\"" +
    c +
    "\",\"ordering_evidence_cid\":\"" +
    c +
    "\",\"actual_row_count\":0,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    c +
    "\",\"effective_retention_policy_cid\":\"" +
    c +
    "\",\"provenance_evidence_cids\":[],\"result_artifact_cid\":\"" +
    c +
    "\"}"
  assert_true(
    seal_publication_contract(
      "result_manifest",
      "{\"version\":\"actql-result-manifest/0.1\"," +
      "\"run_definition_cid\":\"" +
      c +
      "\",\"invocation_cid\":\"" +
      c +
      "\",\"results\":{\"answer\":" +
      false_artifact +
      "}}",
      32768,
      256,
      12,
    )
    is Err(InvalidField("results")),
  )
}

///|
test "generated protocol descriptor admits one exact delivery receipt" {
  let body = "{\"version\":\"actql-result-delivery-receipt/0.1\"," +
    "\"run_definition_cid\":\"" +
    contract_cid("1") +
    "\",\"invocation_cid\":\"" +
    contract_cid("2") +
    "\",\"result_manifest_cid\":\"" +
    contract_cid("3") +
    "\",\"result_name\":\"answer\",\"result_artifact_cid\":\"" +
    contract_cid("5") +
    "\",\"serialization_contract_cid\":\"" +
    contract_cid("6") +
    "\",\"delivered_byte_count\":4,\"delivered_sha256\":\"" +
    "8".repeat(64) +
    "\",\"authorization_context_cid\":\"" +
    contract_cid("7") +
    "\",\"egress_admission_cid\":\"" +
    contract_cid("9") +
    "\"}"
  let receipt = seal_publication_contract(
    "result_delivery_receipt", body, 16384, 128, 8,
  ).unwrap()
  assert_eq(
    publication_contract_identity(receipt),
    "sha256:1b672f923a8f34e603d8246a3541922ccb1eedb4be8d1691f9a290d14fe1e2ea",
  )
  assert_true(
    admit_publication_contract(
      "result_delivery_receipt",
      publication_contract_json(receipt),
      16384,
      128,
      8,
    )
    is Ok(_),
  )
  assert_true(
    seal_publication_contract(
      "result_delivery_receipt",
      body[:body.length() - 1].to_owned() + ",\"extra\":true}",
      16384,
      128,
      8,
    )
    is Err(InvalidField("protocol_schema")),
  )
}

///|
test "closed contract admission rejects ambiguous bodies and identities" {
  let prefix = "{\"version\":\"actql-run-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    contract_cid("1") +
    "\",\"observation_set_cid\":\"" +
    contract_cid("2") +
    "\""
  assert_true(
    seal_publication_contract(
      "run_invocation",
      prefix + ",\"extra\":true}",
      4096,
      32,
      4,
    )
    is Err(UnknownField("extra")),
  )
  assert_true(
    seal_publication_contract(
      "run_invocation",
      "{\"version\":\"actql-run-invocation/0.1\"," +
      "\"observation_set_cid\":\"" +
      contract_cid("2") +
      "\"}",
      4096,
      32,
      4,
    )
    is Err(MissingField("invocation_template_cid")),
  )
  assert_true(
    seal_publication_contract(
      "run_invocation",
      prefix + ",\"invocation_cid\":\"" + contract_cid("3") + "\"}",
      4096,
      32,
      4,
    )
    is Err(IdentityAlreadyPresent),
  )
  let mismatched = prefix + ",\"invocation_cid\":\"" + contract_cid("3") + "\"}"
  assert_true(
    admit_publication_contract("run_invocation", mismatched, 4096, 32, 4)
    is Err(IdentityMismatch),
  )
}

///|
test "publication and delivery terminal records enforce conditional evidence" {
  let publication = "{\"version\":\"actql-publication-record/0.1\"," +
    "\"publication_attempt_cid\":\"" +
    contract_cid("1") +
    "\",\"sequence\":0,\"state\":\"succeeded\"," +
    "\"observed_at\":\"2026-09-18T00:00:01.000Z\"," +
    "\"cleanup_owner_cids\":[]}"
  assert_true(
    seal_publication_contract("publication_record", publication, 4096, 32, 4)
    is Err(ConditionalField("public_index_entry_cid")),
  )
  let delivery = "{\"version\":\"actql-delivery-record/0.1\"," +
    "\"delivery_attempt_cid\":\"" +
    contract_cid("1") +
    "\",\"sequence\":0,\"state\":\"succeeded\"," +
    "\"confirmed_byte_count\":0,\"exposure\":\"unknown_additional\"," +
    "\"possible_unconfirmed_max_bytes\":4," +
    "\"observed_at\":\"2026-09-18T00:00:01.000Z\"," +
    "\"cleanup_owner_cids\":[]}"
  assert_true(
    seal_publication_contract("delivery_record", delivery, 4096, 32, 4)
    is Err(ConditionalField("succeeded")),
  )
}

///|
fn publication_record_contract(
  sequence : Int,
  state : String,
  prior : String?,
) -> PublicationContract {
  let prior_field = match prior {
    Some(value) => "\"prior_record_cid\":\"" + value + "\","
    None => ""
  }
  let evidence = match state {
    "succeeded" => "\"public_index_entry_cid\":\"" + contract_cid("9") + "\","
    "failed" => "\"failure_cid\":\"" + contract_cid("8") + "\","
    _ => ""
  }
  seal_publication_contract(
    "publication_record",
    "{\"version\":\"actql-publication-record/0.1\"," +
    "\"publication_attempt_cid\":\"" +
    contract_cid("1") +
    "\"," +
    prior_field +
    "\"sequence\":" +
    sequence.to_string() +
    ",\"state\":\"" +
    state +
    "\"," +
    evidence +
    "\"observed_at\":\"2026-09-18T00:00:01.000Z\"," +
    "\"cleanup_owner_cids\":[]}",
    4096,
    32,
    4,
  ).unwrap()
}

///|
test "publication transition owner separates intent from durable CAS" {
  let preparing = publication_record_contract(0, "preparing", None)
  assert_true(
    validate_publication_record_transition(None, preparing, false) is Ok(_),
  )
  let committing = publication_record_contract(
    1,
    "committing",
    Some(publication_contract_identity(preparing)),
  )
  assert_true(
    validate_publication_record_transition(Some(preparing), committing, false)
    is Ok(_),
  )
  assert_true(publication_record_allows_commit(committing))
  let cancelled = publication_record_contract(
    2,
    "cancelled",
    Some(publication_contract_identity(committing)),
  )
  assert_true(
    validate_publication_record_transition(Some(committing), cancelled, false)
    is Err(UncommittedNotConfirmed),
  )
  assert_true(
    validate_publication_record_transition(Some(committing), cancelled, true)
    is Ok(_),
  )
  assert_true(!publication_record_allows_commit(cancelled))
}

///|
fn delivery_record_contract(
  sequence : Int,
  state : String,
  bytes : Int,
  prior : String?,
) -> PublicationContract {
  let prior_field = match prior {
    Some(value) => "\"prior_record_cid\":\"" + value + "\","
    None => ""
  }
  let success = if state == "succeeded" {
    "\"delivered_sha256\":\"" +
    "1".repeat(64) +
    "\",\"result_delivery_receipt_cid\":\"" +
    contract_cid("9") +
    "\","
  } else {
    ""
  }
  seal_publication_contract(
    "delivery_record",
    "{\"version\":\"actql-delivery-record/0.1\"," +
    "\"delivery_attempt_cid\":\"" +
    contract_cid("1") +
    "\"," +
    prior_field +
    "\"sequence\":" +
    sequence.to_string() +
    ",\"state\":\"" +
    state +
    "\",\"confirmed_byte_count\":" +
    bytes.to_string() +
    ",\"exposure\":\"exact\"," +
    success +
    "\"observed_at\":\"2026-09-18T00:00:01.000Z\"," +
    "\"cleanup_owner_cids\":[]}",
    4096,
    32,
    4,
  ).unwrap()
}

///|
test "delivery transition owner preserves attempts and confirmed prefixes" {
  let streaming = delivery_record_contract(0, "streaming", 10, None)
  assert_true(validate_delivery_record_transition(None, streaming) is Ok(_))
  let decreased = delivery_record_contract(
    1,
    "failed",
    9,
    Some(publication_contract_identity(streaming)),
  )
  assert_true(
    validate_delivery_record_transition(Some(streaming), decreased)
    is Err(ConfirmedBytesDecreased),
  )
  let succeeded = delivery_record_contract(
    1,
    "succeeded",
    10,
    Some(publication_contract_identity(streaming)),
  )
  assert_true(
    validate_delivery_record_transition(Some(streaming), succeeded) is Ok(_),
  )
  let late = delivery_record_contract(
    2,
    "streaming",
    10,
    Some(publication_contract_identity(succeeded)),
  )
  assert_true(
    validate_delivery_record_transition(Some(succeeded), late)
    is Err(DeliveryStateMismatch),
  )
}

///|
test "publication inventory names and Result grants are occurrence-unique" {
  let duplicate_inventory = "{\"version\":\"actql-publication-request/0.1\"," +
    "\"tenant_id\":\"tenant\",\"authority_scope_cid\":\"" +
    contract_cid("1") +
    "\",\"run_definition_cid\":\"" +
    contract_cid("2") +
    "\",\"inventory\":[" +
    "{\"result_name\":\"answer\",\"result_definition_cid\":\"" +
    contract_cid("3") +
    "\"},{\"result_name\":\"answer\",\"result_definition_cid\":\"" +
    contract_cid("4") +
    "\"}],\"publication_policy_cid\":\"" +
    contract_cid("5") +
    "\",\"publication_target_cid\":\"" +
    contract_cid("6") +
    "\",\"requested_at\":\"2026-09-18T00:00:00.000Z\"}"
  assert_true(
    seal_publication_contract(
      "publication_request", duplicate_inventory, 8192, 64, 6,
    )
    is Err(InvalidField("inventory")),
  )
}

///|
test "contract parsing keeps explicit budgets and strict JSON" {
  assert_true(
    seal_publication_contract("run_invocation", "{}", 0, 1, 1)
    is Err(InvalidLimits),
  )
  assert_true(
    seal_publication_contract(
      "run_invocation",
      "{\"version\":\"actql-run-invocation/0.1\"," +
      "\"version\":\"actql-run-invocation/0.1\"}",
      4096,
      16,
      3,
    )
    is Err(InvalidWire),
  )
  assert_true(
    seal_publication_contract("result_definition", "{}", 4096, 16, 3)
    is Err(MissingField("version")),
  )
}

///|
test "finite publication registry admits every non-Result contract" {
  let c = contract_cid("1")
  let digest = "1".repeat(64)
  let time = "2026-09-18T00:00:00.000Z"
  let contracts = [
    (
      "result_retention_policy",
      "{\"version\":\"actql-result-retention-policy/0.1\"," +
      "\"retention_contract_cid\":\"" +
      c +
      "\",\"effective_data_policy_cid\":\"" +
      c +
      "\",\"available_until\":\"" +
      time +
      "\",\"delete_by\":\"" +
      time +
      "\",\"extension_ceiling_at\":\"" +
      time +
      "\",\"metadata_retention_policy_cid\":\"" +
      c +
      "\",\"clock_contract_cid\":\"" +
      c +
      "\"}",
    ),
    (
      "durable_result_binding",
      "{\"version\":\"actql-durable-result-binding/0.1\"," +
      "\"run_definition_cid\":\"" +
      c +
      "\",\"result_definition_cid\":\"" +
      c +
      "\",\"invocation_cid\":\"" +
      c +
      "\",\"logical_result_cid\":\"" +
      c +
      "\",\"result_schema_cid\":\"" +
      c +
      "\",\"ordering_evidence_cid\":\"" +
      c +
      "\",\"codec_contract_cid\":\"" +
      c +
      "\",\"material_generation_cid\":\"" +
      c +
      "\",\"store_authority_cid\":\"" +
      c +
      "\",\"effective_retention_policy_cid\":\"" +
      c +
      "\",\"row_count\":0,\"byte_count\":0," +
      "\"physical_sha256\":\"" +
      digest +
      "\"}",
    ),
    (
      "publication_request",
      "{\"version\":\"actql-publication-request/0.1\"," +
      "\"tenant_id\":\"tenant\",\"authority_scope_cid\":\"" +
      c +
      "\",\"run_definition_cid\":\"" +
      c +
      "\",\"inventory\":[{\"result_name\":\"answer\"," +
      "\"result_definition_cid\":\"" +
      c +
      "\"}],\"publication_policy_cid\":\"" +
      c +
      "\",\"publication_target_cid\":\"" +
      c +
      "\",\"requested_at\":\"" +
      time +
      "\"}",
    ),
    (
      "publication_attempt",
      "{\"version\":\"actql-publication-attempt/0.1\"," +
      "\"publication_request_cid\":\"" +
      c +
      "\",\"run_definition_cid\":\"" +
      c +
      "\",\"attempt_id\":\"attempt\",\"fence_cid\":\"" +
      c +
      "\",\"started_at\":\"" +
      time +
      "\"}",
    ),
    (
      "publication_record",
      "{\"version\":\"actql-publication-record/0.1\"," +
      "\"publication_attempt_cid\":\"" +
      c +
      "\",\"sequence\":0,\"state\":\"preparing\"," +
      "\"observed_at\":\"" +
      time +
      "\",\"cleanup_owner_cids\":[]}",
    ),
    (
      "manifest_read_grant",
      "{\"version\":\"actql-manifest-read-grant/0.1\"," +
      "\"tenant_id\":\"tenant\",\"authority_scope_cid\":\"" +
      c +
      "\",\"principal_id\":\"principal\",\"run_definition_cid\":\"" +
      c +
      "\",\"result_manifest_cid\":\"" +
      c +
      "\",\"purpose\":\"read\",\"data_ceiling_cid\":\"" +
      c +
      "\",\"max_bytes\":0,\"max_uses\":1,\"expires_at\":\"" +
      time +
      "\",\"authorization_context_cid\":\"" +
      c +
      "\"}",
    ),
    (
      "result_read_grant",
      "{\"version\":\"actql-result-read-grant/0.1\"," +
      "\"tenant_id\":\"tenant\",\"authority_scope_cid\":\"" +
      c +
      "\",\"principal_id\":\"principal\",\"run_definition_cid\":\"" +
      c +
      "\",\"result_manifest_cid\":\"" +
      c +
      "\",\"purpose\":\"read\",\"data_ceiling_cid\":\"" +
      c +
      "\",\"max_bytes\":0,\"max_uses\":1,\"expires_at\":\"" +
      time +
      "\",\"authorization_context_cid\":\"" +
      c +
      "\",\"results\":[{\"result_name\":\"answer\"," +
      "\"result_artifact_cid\":\"" +
      c +
      "\"}],\"formats\":[\"json\",\"jsonl\",\"csv\"]," +
      "\"egress_admission_cid\":\"" +
      c +
      "\"}",
    ),
    (
      "delivery_attempt",
      "{\"version\":\"actql-delivery-attempt/0.1\"," +
      "\"attempt_id\":\"attempt\",\"result_read_grant_cid\":\"" +
      c +
      "\",\"run_definition_cid\":\"" +
      c +
      "\",\"result_manifest_cid\":\"" +
      c +
      "\",\"result_name\":\"answer\",\"result_artifact_cid\":\"" +
      c +
      "\",\"serialization_contract_cid\":\"" +
      c +
      "\",\"requested_at\":\"" +
      time +
      "\"}",
    ),
    (
      "delivery_record",
      "{\"version\":\"actql-delivery-record/0.1\"," +
      "\"delivery_attempt_cid\":\"" +
      c +
      "\",\"sequence\":0,\"state\":\"streaming\"," +
      "\"confirmed_byte_count\":0,\"exposure\":\"exact\"," +
      "\"observed_at\":\"" +
      time +
      "\",\"cleanup_owner_cids\":[]}",
    ),
    (
      "public_index_entry",
      "{\"version\":\"actql-public-index-entry/0.1\"," +
      "\"tenant_id\":\"tenant\",\"authority_scope_cid\":\"" +
      c +
      "\",\"run_definition_cid\":\"" +
      c +
      "\",\"invocation_cid\":\"" +
      c +
      "\",\"result_manifest_cid\":\"" +
      c +
      "\",\"run_receipt_cid\":\"" +
      c +
      "\",\"captured_run_cid\":\"" +
      c +
      "\",\"durable_result_binding_cids\":[\"" +
      c +
      "\"],\"publication_request_cid\":\"" +
      c +
      "\",\"publication_attempt_cid\":\"" +
      c +
      "\",\"committed_at\":\"" +
      time +
      "\"}",
    ),
  ]
  for (name, wire) in contracts {
    let contract = seal_publication_contract(name, wire, 32768, 256, 8).unwrap()
    assert_eq(publication_contract_name(contract), name)
    assert_true(
      admit_publication_contract(
        name,
        publication_contract_json(contract),
        32768,
        256,
        8,
      )
      is Ok(_),
    )
  }
}
