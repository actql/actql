///|
// Explicit private Preview DATA fixture through the real Common issuer. It
// supplies no captured publication, current authority or approval grant.
fn create_outcome_preview(
  changed? : Bool = false,
) -> @publication.EffectPreviewIdentity {
  let original =
    #|{"authoring_context":{"annotations":[],"authoring_context_cid":"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a","program_definition_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-authoring-context/0.1"},"barrier_provenance_cids":[],"check_environment_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effects":[{"approval":"none","authority_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","capability_evidence_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","changes":[{"after":{"state":"present","value":{"Subject":"requested","Tags":["東京","東京"]}},"before":{"state":"absent"},"intended_changes":{"state":"present","value":{"Subject":"requested","Tags":["東京","東京"]}},"row_idempotency_key":"sha256:4444444444444444444444444444444444444444444444444444444444444444","row_preview_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","target_guard":{"state":"not_applicable"},"target_row_identity":"create-original-correlation"}],"count":1,"effect_id":"CreateOne","effect_identity_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_kind":"create","effect_member_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","executed":false,"mapping":"mapping:fixture","max_items":1,"on_item_failure":"halt","preview_strength":"full_diff","required_permissions":["kintone:records:create"],"resolved_mapping_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","row_order":["sha256:3333333333333333333333333333333333333333333333333333333333333333"],"source_binding_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","target":"inquiries","write_footprint":{"kind":"collection","provider_boundary_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider_namespace":"kintone","provider_object_identity_cids":[],"resource_identity_scheme_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","resource_kind":"inquiries"}}],"encryption_required":true,"executed":false,"invocation_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","model_derived":false,"model_invocation_evidence_cids":[],"model_response_artifact_cids":[],"model_task_contract_cids":[],"program_definition_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","program_semantics_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_class":"authority-evidence","run_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sensitivity":"private","version":"actql-effect-preview/0.1"}
  let wire = if changed {
    original.replace_all(old="requested", new="different")
  } else {
    original
  }
  let after = "{\"state\":\"present\",\"value\":{\"Subject\":\"requested\",\"Tags\":[\"東京\",\"東京\"]}}"
  let selected_after = if changed {
    after.replace_all(old="requested", new="different")
  } else {
    after
  }
  let inventory = @publication.derive_effect_create_row_inventory(
    [selected_after],
    1,
    16384,
    2000,
    24,
  ).unwrap()
  let issued_wire = wire.replace_all(
    old="\"create-original-correlation\"",
    new=inventory[0].1,
  )
  let admitted = @publication.author_effect_preview_semantic_wire(
    issued_wire, "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a", 16384,
    2000, 24,
  )
  match admitted {
    Ok((_, value)) => value
    Err(issue) => {
      println("Invalid CREATE Preview DATA fixture: " + @debug.to_string(issue))
      abort("Invalid CREATE Preview DATA fixture")
    }
  }
}

///|
fn create_outcome_mapping() -> (
  RecordCreateMapping,
  @catalog.RecordCreateRequest,
) {
  let catalog = create_mapping_catalog()
  let original = create_mapping_declaration(catalog)
  let mapping = prepare_record_create_mapping(
    original,
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  (mapping, create_mapping_request(catalog, ["Subject", "Tags"]))
}

///|
fn create_outcome_write_limits() -> @catalog.RecordWriteLimits {
  {
    max_fields: 16,
    max_name_bytes: 512,
    max_nodes: 2000,
    max_depth: 24,
    max_text_bytes: 16384,
    max_output_bytes: 16384,
  }
}

///|
test "CREATE typed acknowledgement matches the exact Common Preview row and original request" {
  let (mapping, request) = create_outcome_mapping()
  let bytes = b"{\"ids\":[\"9007199254740993\"],\"revisions\":[\"9007199254740994\"]}"
  let response = @catalog.project_record_create_acknowledgement(
    request,
    200,
    bytes,
    delete_preview_limits(),
  ).unwrap()
  let preview = create_outcome_preview()
  let value = project_record_create_preview_outcome(
    mapping,
    request,
    response,
    preview,
    0,
    0,
    16384,
    create_outcome_write_limits(),
    delete_preview_limits(),
  ).unwrap()
  assert_true(
    record_create_preview_outcome_matches(
      value, mapping, request, preview, 0, 0,
    ),
  )
  assert_eq(
    record_create_preview_outcome_row_cid(value),
    @publication.effect_preview_row_identity(preview, 0, 0).unwrap(),
  )
  assert_eq(
    record_create_preview_outcome_response_sha256(value),
    @sha.hex(bytes),
  )
  assert_eq(
    record_create_preview_outcome_wire(value),
    "{\"result\":{\"created\":true,\"record_id\":\"9007199254740993\",\"revision\":\"9007199254740994\"},\"state\":\"applied\"}",
  )
  assert_false(
    record_create_preview_outcome_matches(
      value,
      mapping,
      request,
      create_outcome_preview(),
      0,
      0,
    ),
  )
}

///|
test "CREATE outcome rejects wrong Preview row value Mapping and equal foreign request" {
  let (mapping, request) = create_outcome_mapping()
  let response = @catalog.project_record_create_acknowledgement(
    request,
    200,
    b"{\"ids\":[\"1\"],\"revisions\":[\"2\"]}",
    delete_preview_limits(),
  ).unwrap()
  assert_true(
    project_record_create_preview_outcome(
      mapping,
      request,
      response,
      create_outcome_preview(changed=true),
      0,
      0,
      16384,
      create_outcome_write_limits(),
      delete_preview_limits(),
    )
    is Err(ForeignPreview),
  )
  assert_true(
    project_record_create_preview_outcome(
      mapping,
      request,
      response,
      create_outcome_preview(),
      0,
      1,
      16384,
      create_outcome_write_limits(),
      delete_preview_limits(),
    )
    is Err(ForeignPreview),
  )
  let copied : RecordCreateMapping = { ..mapping, }
  assert_true(
    project_record_create_preview_outcome(
      copied,
      request,
      response,
      create_outcome_preview(),
      0,
      0,
      16384,
      create_outcome_write_limits(),
      delete_preview_limits(),
    )
    is Err(MappingMismatch),
  )
  let (foreign, foreign_request) = create_outcome_mapping()
  assert_true(
    project_record_create_preview_outcome(
      foreign,
      foreign_request,
      response,
      create_outcome_preview(),
      0,
      0,
      16384,
      create_outcome_write_limits(),
      delete_preview_limits(),
    )
    is Err(Response(@catalog.UncorrelatedResult)),
  )
}
