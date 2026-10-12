///|
// The existing independent Preview 0.1 vector's known row/member/set CIDs.
// This tests the actual admitted member scope, not custody issuance or I/O.
fn original_approval_scope_preview_fixture() -> @publication.EffectPreviewIdentity {
  let a = "sha256:" + "a".repeat(64)
  let run = "sha256:" + "b".repeat(64)
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let raw =
    #|{"version":"actql-effect-preview/0.1","sensitivity":"private","retention_class":"authority-evidence","encryption_required":true,"program_semantics_cid":"@A@","program_definition_cid":"@A@","invocation_cid":"@A@","run_identity_cid":"@RUN@","compiled_plan_cid":"@A@","check_environment_cid":"@A@","authoring_context":{"version":"actql-authoring-context/0.1","program_definition_cid":"@A@","annotations":[],"authoring_context_cid":"@AUTHORING@"},"barrier_provenance_cids":[],"model_derived":false,"model_task_contract_cids":[],"model_invocation_evidence_cids":[],"model_response_artifact_cids":[],"effects":[{"effect_id":"WriteOne","effect_kind":"update","target":"Object","mapping":"mapping:fixture","resolved_mapping_contract_cid":"@A@","effect_identity_cid":"@A@","preview_strength":"full_diff","source_binding_cid":"@A@","capability_evidence_cid":"@A@","authority_scope_cid":"@A@","write_footprint":{"kind":"exact_targets","resource_identity_scheme_cid":"@A@","provider_namespace":"provider","provider_boundary_cid":"@A@","resource_kind":"Object","provider_object_identity_cids":["@TARGET@"]},"count":1,"max_items":1,"required_permissions":["write"],"approval":"none","on_item_failure":"halt","changes":[{"target_row_identity":"001000000000001","target_guard":{"state":"version","version_cid":"@A@"},"intended_changes":{"state":"present","value":{"Name":"After"}},"before":{"state":"present","value":{"Name":"Before"}},"after":{"state":"present","value":{"Name":"After"}},"row_preview_cid":"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8","row_idempotency_key":"@ROWKEY@"}],"row_order":["sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8"],"effect_member_preview_cid":"sha256:099721c928770511d95faed4eaeef3fef768c4b573c714fc0af16c0b5439b5b6","executed":false}],"executed":false,"effect_preview_cid":"sha256:2fe7f8e93988fcf4d7804e86b69a72d00e1c7bfd946c8fa29d6e91c706593409"}
  let wire = @publication.canonical_effect_preview_draft_wire(
    raw
    .replace_all(old="@A@", new=a)
    .replace_all(old="@RUN@", new=run)
    .replace_all(old="@AUTHORING@", new=authoring)
    .replace_all(old="@TARGET@", new="sha256:" + "1".repeat(64))
    .replace_all(old="@ROWKEY@", new="sha256:" + "4".repeat(64)),
    8192,
    256,
    12,
  ).unwrap()
  @publication.admit_effect_preview_identity(
    wire, run, authoring, 8192, 256, 12,
  ).unwrap()
}

///|
test "original approval scope accepts only the actual admitted Preview member authority" {
  let preview = original_approval_scope_preview_fixture()
  assert_true(
    original_effect_preview_authority_matches(
      preview,
      "sha256:" + "a".repeat(64),
    ),
  )
}

///|
test "original approval scope rejects a different Client scope instead of filling it from Resolution" {
  let preview = original_approval_scope_preview_fixture()
  assert_false(
    original_effect_preview_authority_matches(
      preview,
      "sha256:" + "b".repeat(64),
    ),
  )
  assert_false(original_effect_preview_authority_matches(preview, "unknown"))
}
