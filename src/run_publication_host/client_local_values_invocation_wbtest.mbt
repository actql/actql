///|
fn local_values_invocation_fixture(
  tasks : Bool,
  document? : String = run_materials_document,
) -> (
  PreparedClientProgram,
  ClientCompiledRun,
  @publication.PublicationContract,
) {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = run_materials_limits()
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    limits.preparation,
  ).unwrap()
  let compiled = if tasks {
    let compilation = issue_prepared_client_task_compilation(
      prepared,
      run_materials_manifests(),
      limits.sequence,
      1000,
      1000,
      65536,
      8192,
      64,
    ).unwrap()
    issue_client_task_compiled_run(
      prepared,
      compilation,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    ).unwrap()
  } else {
    let compilation = issue_prepared_client_values_compilation(
      prepared,
      run_materials_manifests(),
      limits.sequence,
      limits.max_sequence_steps,
      limits.max_sequence_work,
      65536,
      8192,
      64,
    ).unwrap()
    issue_client_values_compiled_run(
      prepared,
      compilation,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    ).unwrap()
  }
  let definition = issue_client_compiled_run_definition(
    compiled, "local-values", "original-run", "2026-10-12T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (prepared, compiled, definition)
}

///|
// Independent normative preimage: user Values have unknown provenance, and
// no Source policy is invented or classified public. SHA-256 is fixed here.
let local_values_original_policy_wire : String =
  #|{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}

///|
let local_values_original_policy_cid : String = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"

///|
test "Local Values invocation keeps the original unknown policy in both compilation alternatives" {
  for tasks in [false, true] {
    let (prepared, compiled, definition) = local_values_invocation_fixture(
      tasks,
    )
    assert_true(
      prepared_client_publication_policy_bodies(prepared, 65536, 8192, 64)
      is Err(@checked.MissingDependency),
    )
    assert_true(
      client_compiled_run_publication_policy_bodies(compiled, 65536, 8192, 64)
      is Err(@checked.MissingDependency),
    )
    assert_true(
      issue_client_compiled_local_values_invocation(
        compiled, definition, 65536, 8192, 64,
      )
      is Err(_),
    )
    let compiled = with_client_source_free_result_policy(
      compiled, local_values_original_policy_cid, local_values_original_policy_wire,
      65536, 8192, 64,
    ).unwrap()
    assert_eq(
      client_compiled_run_publication_policy_bodies(compiled, 65536, 8192, 64).unwrap(),
      [
        (
          "data_policy", local_values_original_policy_cid, local_values_original_policy_wire,
        ),
      ],
    )
    let (observation, invocation) = issue_client_compiled_local_values_invocation(
      compiled, definition, 65536, 8192, 64,
    ).unwrap()
    let observation = parse_plan_identity_value(
      @publication.run_evidence_value_json(observation),
      65536,
      8192,
      64,
    ).unwrap()
    for field in ["source_evidence_cids", "captured_input_artifact_cids"] {
      assert_true(
        @canonical.object_field(observation, field)
        is Some(@canonical.Array(values)) &&
        @canonical.array_values(values).is_empty(),
      )
    }
    assert_true(
      @canonical.object_field(observation, "data_policy_cid")
      is Some(@canonical.String(cid)) &&
      cid == local_values_original_policy_cid,
    )
    assert_true(
      @canonical.object_field(observation, "consistency")
      is Some(@canonical.String(consistency)) &&
      consistency == "no_external_sources",
    )
    let invocation = parse_plan_identity_value(
      @publication.publication_contract_json(invocation),
      65536,
      8192,
      64,
    ).unwrap()
    assert_true(
      @canonical.object_field(invocation, "invocation_template_cid")
      is Some(@canonical.String(cid)) &&
      cid ==
      @publication.run_evidence_value_identity(
        client_compiled_run_template(compiled),
      ),
    )
  }
}

///|
test "Local Values invocation refuses a foreign original compilation" {
  for tasks in [false, true] {
    let (_, original, _) = local_values_invocation_fixture(tasks)
    let (_, _, foreign) = local_values_invocation_fixture(
      tasks,
      document=run_materials_document.replace(
        old="client-values",
        new="foreign-program",
      ),
    )
    assert_true(
      issue_client_compiled_local_values_invocation(
        original, foreign, 65536, 8192, 64,
      )
      is Err(@publication.RunEvidenceReferenceMismatch("local_values_run")),
    )
  }
}

///|
test "Local Values invocation refuses insufficient policy and evidence budgets" {
  let (_, compiled, definition) = local_values_invocation_fixture(true)
  let compiled = with_client_source_free_result_policy(
    compiled, local_values_original_policy_cid, local_values_original_policy_wire,
    65536, 8192, 64,
  ).unwrap()
  for (bytes, nodes, depth) in [(1, 8192, 64), (65536, 0, 64), (65536, 8192, 0)] {
    assert_true(
      issue_client_compiled_local_values_invocation(
        compiled, definition, bytes, nodes, depth,
      )
      is Err(_),
    )
  }
}

///|
test "Local Values original admission refuses wrong CID classification and budget" {
  let (_, compiled, _) = local_values_invocation_fixture(true)
  assert_true(
    with_client_source_free_result_policy(
      compiled,
      "sha256:" + "0".repeat(64),
      local_values_original_policy_wire,
      65536,
      8192,
      64,
    )
    is Err(InvalidResultPolicy),
  )
  assert_true(
    with_client_source_free_result_policy(
      compiled,
      local_values_original_policy_cid,
      local_values_original_policy_wire.replace(old="unknown", new="public"),
      65536,
      8192,
      64,
    )
    is Err(InvalidResultPolicy),
  )
  assert_true(
    with_client_source_free_result_policy(
      compiled, local_values_original_policy_cid, local_values_original_policy_wire,
      1, 8192, 64,
    )
    is Err(InvalidResultPolicy),
  )
}

///|
test "Local Values Host policy never replaces a contributing Source closure" {
  let prepared = multi_source_prepared(multi_source_program)
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    client_standard_values_sequence_limits(),
    1000,
    1000,
    65536,
    8192,
    64,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    with_client_source_free_result_policy(
      compiled, local_values_original_policy_cid, local_values_original_policy_wire,
      65536, 8192, 64,
    )
    is Err(ForeignOwner),
  )
  assert_eq(
    client_compiled_run_publication_policy_bodies(compiled, 65536, 8192, 64).unwrap(),
    prepared_client_publication_policy_bodies(prepared, 65536, 8192, 64).unwrap(),
  )
}

///|
test "local execution owner admits only its same Values or Tasks compiled definition" {
  for tasks in [false, true] {
    let (_, compiled, definition) = local_values_invocation_fixture(tasks)
    assert_true(client_compiled_local_execution_owner(compiled, definition))
    let (_, _, foreign) = local_values_invocation_fixture(
      tasks,
      document=run_materials_document.replace(
        old="client-values",
        new="foreign-execution-owner",
      ),
    )
    assert_false(client_compiled_local_execution_owner(compiled, foreign))
  }
}
