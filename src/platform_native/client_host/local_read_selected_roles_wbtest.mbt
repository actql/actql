///|
// Physical definitions use the existing selected-file and journal Owners.
// Compiler-only validation does not establish Native execution or public read.
fn selected_read_roles_fixture(
  name : String,
  existing? : Bool = false,
) -> NativeLocalHostConnection raise {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let names = [
    name + ".profile",
    name + ".run-a",
    name + ".run-b",
    name + ".retention",
    name + ".store",
    name + ".read-a",
    name + ".read-b",
  ]
  let account_name = name + ".account"
  if !existing {
    let originals = @host.client_local_product_finite_originals(
      root,
      "/physical/sqlite.dylib",
      "/physical/crypto.dylib",
      "2026-10-12T00:00:00.000Z",
      @host.client_local_product_assets(),
    ).unwrap()
    let original = key => {
      originals.iter().find_first(pair => pair.0 == key).unwrap().1
    }
    let read = @utf8.decode(original("read.json"))
      .replace_all(old="run.json", new=names[1])
      .replace_all(old="retention.json", new=names[3])
      .replace_all(old="store.json", new=names[4])
    let parent = @filesystem.open_private_root(root).unwrap()
    for
      (file, body) in [
        (account_name, original("account.json")),
        (names[0], original("profile.json")),
        (names[1], original("run.json")),
        (names[2], original("run.json")),
        (names[3], original("retention.json")),
        (names[4], original("store.json")),
        (names[5], @utf8.encode(read)),
        (
          names[6],
          @utf8.encode(
            read
            .replace_all(old=names[1], new=names[2])
            .replace_all(old="cli-read", new="cli-read-b"),
          ),
        ),
      ] {
      let writer = parent.create_writer(file + ".stage", 65536L).unwrap()
      writer.append(body).unwrap()
      writer.seal(file).unwrap() |> ignore
    }
  }
  begin_native_local_host_adoption(
    root,
    name + ".host",
    root,
    account_name,
    "local-cli",
    epoch_test_crypto(),
    existing_only=existing,
    configuration_files=names,
  )
  .unwrap()
  .open_journal(
    local_journal_test_library(),
    epoch_test_crypto(),
    100.0,
    8,
    8388608L,
  )
  .unwrap()
}

///|
test "Native custom role groups restore each original read independently after reopen" {
  let name = "local-read-custom-roles"
  let host = selected_read_roles_fixture(name)
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("local-cli", "local", crypto).unwrap()
  let epoch = host.epoch.issue_epoch(scope, true, 1000.0).unwrap()
  let retained : Array[
    (
      NativeClientSubmissionReference,
      @host.ClientRequestIdentity,
      @result_access.NativeResultReadFacts,
      String,
    ),
  ] = []
  let policy_cid = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  for (suffix, purpose) in [("a", "cli-read"), ("b", "cli-read-b")] {
    let policy = host
      .bind_run_policy_profile(
        crypto,
        "local-cli",
        "local",
        name + ".profile",
        name + ".read-" + suffix,
        name + ".run-" + suffix,
        name + ".retention",
        name + ".store",
      )
      .unwrap()
    let reference = prepare_native_client_submission_reference(
      epoch,
      "custom-read-" + suffix,
    ).unwrap()
    let intent = @host.prepare_client_submitted_intent(
      "{\"kind\":\"program\",\"input\":" +
      preparation_values_document() +
      ",\"parameters\":null}",
      65536,
      8192,
      64,
    ).unwrap()
    let preparation = submitted_prepare(intent).unwrap()
    guard preparation.preparation is Computation(prepared) else {
      fail("original checked preparation missing")
    }
    let (request, _, unselected, _) = journal_test_prepared_run(
      prepared,
      reference.request_id,
      "custom-run-" + suffix,
      scope~,
    )
    // Source-free preparation has no contributing Source policy. Admit the
    // independently authored Result policy before accepting this original Run.
    assert_eq(@host.prepared_client_publication_data_policy_cid(prepared), None)
    assert_true(
      @host.client_compiled_run_publication_policy_bodies(
        unselected, 65536, 8192, 64,
      )
      is Err(@checked.MissingDependency),
    )
    let (compiled, original_policy_cid) = policy_test_result_original(
      unselected,
    )
    assert_eq(original_policy_cid, policy_cid)
    let definition = @host.issue_client_compiled_run_definition(
      compiled,
      "local-test",
      "custom-run-" + suffix,
      "2026-10-13T00:00:00.001Z",
      "2026-10-14T00:00:00.001Z",
    ).unwrap()
    host.journal
    .record_submitted_intent(host.epoch, reference, intent, scope, true, 1001.0)
    .unwrap()
    |> ignore
    let retention = @host.issue_client_local_run_retention_policy(
      policy.profile,
      "2026-10-13T00:00:00.001Z",
    ).unwrap()
    policy
    .accept_issued_submitted_run_policy(
      reference, preparation, request, compiled, definition, retention, "2026-10-13T00:00:00.001Z",
      1002.0,
    )
    .unwrap()
    |> ignore
    host
    .retain_publication_policy_originals(
      crypto, "local-cli", "local", request, prepared, compiled, definition,
    )
    .unwrap()
    |> ignore
    let binding = host
      .bind_result_read_policy_for_run(policy, reference, request, 1003.0)
      .unwrap()
    let wrong = host
      .bind_run_policy_profile(
        crypto,
        "local-cli",
        "local",
        name + ".profile",
        name + ".read-" + suffix,
        name + ".run-" + (if suffix == "a" { "b" } else { "a" }),
        name + ".retention",
        name + ".store",
      )
      .unwrap()
    assert_true(
      host.bind_result_read_policy_for_run(wrong, reference, request, 1003.0)
      is Err(SelectionMismatch),
    )
    let facts : @result_access.NativeResultReadFacts = {
      request: {
        namespace_id: "original-namespace",
        authority_scope_cid: scope,
        run_definition_cid: @publication.publication_contract_identity(
          definition,
        ),
        principal_id: "local-cli",
        purpose,
        result_name: "answer",
        format: "jsonl",
        attempt_id: "original-read-" + suffix,
      },
      public_index_entry_cid: "sha256:" + "b".repeat(64),
      result_manifest_cid: "sha256:" + "c".repeat(64),
      result_artifact_cid: "sha256:" + "d".repeat(64),
      result_definition_cid: "sha256:" + "e".repeat(64),
      material_generation_cid: "sha256:" + "f".repeat(64),
      observed_at: "2026-10-13T01:00:00.001Z",
    }
    // Private post-resolution custody only; no payload or grant is invented.
    let first = binding
      .retain_read_admission(request, facts, policy_cid)
      .unwrap()
    retained.push((reference, request, facts, first.egress_admission_cid))
  }
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"2",
  )
  host.close().unwrap()
  let reopened = selected_read_roles_fixture(name, existing=true)
  for index, (reference, request, facts, cid) in retained {
    let suffix = if index == 0 { "a" } else { "b" }
    let policy = reopened
      .bind_run_policy_profile(
        crypto,
        "local-cli",
        "local",
        name + ".profile",
        name + ".read-" + suffix,
        name + ".run-" + suffix,
        name + ".retention",
        name + ".store",
      )
      .unwrap()
    let binding = reopened
      .bind_result_read_policy_for_run(policy, reference, request, 1004.0)
      .unwrap()
    assert_eq(
      binding.retained_read_admission(request, facts, policy_cid).unwrap().egress_admission_cid,
      cid,
    )
  }
  assert_eq(
    reopened.database.read("client_local_read_custody", "issued").unwrap().body,
    b"2",
  )
  reopened.close().unwrap()
}
