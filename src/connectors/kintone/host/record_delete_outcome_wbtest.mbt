///|
// Authored private Preview DATA, not an approval, live observation or claim.
fn delete_outcome_preview(
  mapping : RecordDeleteMapping,
  changed? : String = "",
) -> @publication.EffectPreviewIdentity {
  let original =
    #|{"authoring_context":{"annotations":[],"authoring_context_cid":"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a","program_definition_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-authoring-context/0.1"},"barrier_provenance_cids":[],"check_environment_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effects":[{"approval":"required","authority_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","capability_evidence_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","changes":[{"after":{"state":"absent"},"before":{"state":"present","value":{"$id":"9007199254740993","Subject":"original"}},"intended_changes":{"state":"not_applicable"},"row_idempotency_key":"sha256:4444444444444444444444444444444444444444444444444444444444444444","row_preview_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","target_guard":{"state":"version","version_cid":"sha256:99944ac0d4a7f14be6fac31131cccd767d5149ae8e8c65daeb50bdeee0c087cd"},"target_row_identity":"9007199254740993"}],"count":1,"effect_id":"DeleteOne","effect_identity_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_kind":"delete","effect_member_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","executed":false,"mapping":"%MAPPING_REF%","max_items":1,"on_item_failure":"halt","preview_strength":"full_diff","required_permissions":["kintone:records:delete"],"resolved_mapping_contract_cid":"%MAPPING_CID%","row_order":["sha256:3333333333333333333333333333333333333333333333333333333333333333"],"source_binding_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","target":"inquiries","write_footprint":{"kind":"opaque","provider_boundary_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider_namespace":"kintone","provider_object_identity_cids":[],"resource_identity_scheme_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","resource_kind":"inquiries"}}],"encryption_required":true,"executed":false,"invocation_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","model_derived":false,"model_invocation_evidence_cids":[],"model_response_artifact_cids":[],"model_task_contract_cids":[],"program_definition_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","program_semantics_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_class":"authority-evidence","run_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sensitivity":"private","version":"actql-effect-preview/0.1"}
  let wire = original
    .replace_all(old="%MAPPING_REF%", new=mapping.mapping.mapping_ref)
    .replace_all(old="%MAPPING_CID%", new=mapping.mapping.mapping_cid)
  let wire = match changed {
    "target" => wire.replace_all(old="9007199254740993", new="9007199254740992")
    "revision" =>
      wire.replace_all(
        old="sha256:99944ac0d4a7f14be6fac31131cccd767d5149ae8e8c65daeb50bdeee0c087cd",
        new="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      )
    "mapping" =>
      wire.replace_all(
        old=mapping.mapping.mapping_cid,
        new="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      )
    _ => wire
  }
  @publication.author_effect_preview_semantic_wire(
    wire, "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a", 16384,
    2000, 24,
  ).unwrap().1
}

///|
fn delete_outcome_originals() -> (
  RecordDeleteMapping,
  @catalog.RecordDeleteRequest,
) {
  let catalog = delete_mapping_form()
  (delete_preview_mapping(catalog), delete_original_request(catalog))
}

///|
test "DELETE typed response is bound to the original Mapping target revision and exact Preview row" {
  let (mapping, request) = delete_outcome_originals()
  let bytes = b"{}"
  let response = @catalog.project_record_delete_acknowledgement(
    request, 200, bytes, 8192, 1000, 16,
  ).unwrap()
  let preview = delete_outcome_preview(mapping)
  let projected = project_record_delete_preview_outcome(
    mapping,
    request,
    response,
    preview,
    0,
    0,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_eq(
    record_delete_preview_outcome_wire(projected),
    "{\"result\":{},\"state\":\"applied\"}",
  )
  assert_eq(
    record_delete_preview_outcome_response_sha256(projected),
    @sha.hex(bytes),
  )
  assert_eq(
    record_delete_preview_outcome_row_cid(projected),
    @publication.effect_preview_ordered_row_identity(preview, 0, 0).unwrap(),
  )
  assert_true(
    record_delete_preview_outcome_matches(
      projected, mapping, request, preview, 0, 0,
    ),
  )
  assert_false(
    record_delete_preview_outcome_matches(
      projected,
      mapping,
      request,
      delete_outcome_preview(mapping),
      0,
      0,
    ),
  )
}

///|
test "DELETE typed outcome refuses changed approved target revision Mapping and row index" {
  let (mapping, request) = delete_outcome_originals()
  let response = @catalog.project_record_delete_acknowledgement(
    request, 200, b"{}", 8192, 1000, 16,
  ).unwrap()
  for changed in ["target", "revision", "mapping"] {
    assert_true(
      project_record_delete_preview_outcome(
        mapping,
        request,
        response,
        delete_outcome_preview(mapping, changed~),
        0,
        0,
        delete_preview_values(),
        delete_preview_limits(),
      )
      is Err(ForeignPreview),
    )
  }
  for (member, row) in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
    assert_true(
      project_record_delete_preview_outcome(
        mapping,
        request,
        response,
        delete_outcome_preview(mapping),
        member,
        row,
        delete_preview_values(),
        delete_preview_limits(),
      )
      is Err(ForeignPreview),
    )
  }
}

///|
test "DELETE outcome retains nominal original request response and Mapping rather than equal copies" {
  let (mapping, request) = delete_outcome_originals()
  let response = @catalog.project_record_delete_acknowledgement(
    request, 200, b"{}", 8192, 1000, 16,
  ).unwrap()
  let preview = delete_outcome_preview(mapping)
  let copied : RecordDeleteMapping = { ..mapping, }
  assert_false(record_delete_mapping_is_original(copied))
  assert_true(
    project_record_delete_preview_outcome(
      copied,
      request,
      response,
      preview,
      0,
      0,
      delete_preview_values(),
      delete_preview_limits(),
    )
    is Err(MappingMismatch),
  )
  let (_, foreign_request) = delete_outcome_originals()
  assert_true(
    project_record_delete_preview_outcome(
      mapping,
      foreign_request,
      response,
      preview,
      0,
      0,
      delete_preview_values(),
      delete_preview_limits(),
    )
    is Err(MappingMismatch),
  )
  let equal_request = @catalog.prepare_record_delete_request(
    @catalog.record_delete_request_targets(request),
    delete_preview_limits(),
  ).unwrap()
  assert_true(
    project_record_delete_preview_outcome(
      mapping,
      equal_request,
      response,
      preview,
      0,
      0,
      delete_preview_values(),
      delete_preview_limits(),
    )
    is Err(Response(@catalog.UncorrelatedResult)),
  )
}

///|
test "DELETE outcome refuses zero bounds and incomplete original before fields" {
  let (mapping, request) = delete_outcome_originals()
  let response = @catalog.project_record_delete_acknowledgement(
    request, 200, b"{}", 8192, 1000, 16,
  ).unwrap()
  let limits = delete_preview_limits()
  for
    selected in [
      { ..limits, max_output_bytes: 1, },
      { ..limits, max_output_nodes: 1, },
      { ..limits, max_output_depth: 0, },
      { ..limits, max_comparison_work: 0, },
    ] {
    assert_true(
      project_record_delete_preview_outcome(
        mapping,
        request,
        response,
        delete_outcome_preview(mapping),
        0,
        0,
        delete_preview_values(),
        selected,
      )
      is Err(_),
    )
  }
  let catalog = delete_mapping_form()
  let incomplete = delete_original_request(catalog, fields=[])
  let other_mapping = delete_preview_mapping(catalog)
  let ack = @catalog.project_record_delete_acknowledgement(
    incomplete, 200, b"{}", 8192, 1000, 16,
  ).unwrap()
  assert_true(
    project_record_delete_preview_outcome(
      other_mapping,
      incomplete,
      ack,
      delete_outcome_preview(other_mapping),
      0,
      0,
      delete_preview_values(),
      limits,
    )
    is Err(MappingMismatch),
  )
}
