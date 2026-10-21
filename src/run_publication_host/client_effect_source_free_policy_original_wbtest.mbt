///|
fn source_free_original_test_policy_pair(wire : String) -> String raise {
  let writer = @encode.writer(1024, 2, 1)
  @encode.string_value(
    writer, "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
  )
  target_projection_replace_raw_field(
    target_projection_replace_raw_field(
      wire,
      "source_free_result_policy_cid",
      Some(
        "\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"",
      ),
    ),
    "source_free_result_policy_json",
    Some(@encode.finish(writer)),
  )
}

///|
test "source-free Content originals leave legacy and Model bodies absent and reject another purpose" {
  let store = published_selection_prepare().unwrap()
  let (store_allowed, store_definition, store_request) = published_selection_run(
    store,
  )
  let model = selected_infer_original_fixture()
  for
    (owner, allowed, definition, request) in [
      (store, store_allowed, store_definition, store_request),
      model,
    ] {
    let compilation = allowed.compilation
    assert_true(
      client_effect_original_source_free_policy_input(compilation) is Ok(None),
    )
    let original = issue_client_effect_prepared_original(compilation).unwrap()
    let materials = issue_prepared_client_effect_run_materials(
      allowed,
      definition,
      request=Some(request),
    ).unwrap()
    assert_false(original.contains("source_free_result_policy_"))
    assert_false(materials.contains("source_free_result_policy_"))
    let plan = @publication.publication_contract_identity(
      compilation.compiled.compiled_plan,
    )
    let held = selected_infer_original_admit(original, plan).unwrap()
    assert_eq(
      issue_client_effect_prepared_original(held.compilation).unwrap(),
      original,
    )
    let run = @publication.publication_contract_identity(definition)
    let restored = target_selection_materials_admit(
      materials,
      run,
      Some(request),
    ).unwrap()
    assert_eq(
      issue_prepared_client_effect_run_materials(
        restored.allowed,
        restored.run_definition,
        request=restored.request,
      ).unwrap(),
      materials,
    )
    assert_true(
      selected_infer_original_admit(
        source_free_original_test_policy_pair(original),
        plan,
      )
      is Err(Input(MaterialsEvidence("source_free_result_policy"))),
    )
    assert_true(
      target_selection_materials_admit(
        source_free_original_test_policy_pair(materials),
        run,
        Some(request),
      )
      is Err(Input(MaterialsEvidence("source_free_result_policy"))),
    )
    assert_true(
      restore_client_effect_original_source_free_policy(owner, None) is Ok(None),
    )
  }
}

///|
test "source-free Content originals cannot smuggle an Effect policy into Values materials" {
  let wire = run_materials_json([
    ("check_environment", Some(run_materials_environment_wire)),
    ("check_environment_cid", Some(run_materials_environment_cid)),
    ("created_at", Some("2026-10-20T00:00:00.000Z")),
    ("parameters", None),
    // Read-input admission does not admit these as invocation or authority.
    ("prepared_invocation", Some("{}")),
    ("program", Some(run_materials_document)),
    ("program_format", Some("json")),
    ("run_authorization", Some("{}")),
    ("run_id", Some("shape-only-values")),
    ("scope_id", Some("shape-only-scope")),
    ("valid_until", Some("2099-01-01T00:00:00.000Z")),
    ("version", Some("actql-remote-run-materials/0.1")),
  ])
  let read = fn(wire) {
    read_client_run_materials_input(
      wire,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_limits(),
    )
  }
  assert_true(read(wire) is Ok(_))
  assert_true(
    read(source_free_original_test_policy_pair(wire))
    is Err(MaterialsEvidence("source_free_result_policy")),
  )
}
