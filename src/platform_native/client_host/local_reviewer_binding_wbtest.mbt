///|
// Physical Native definitions, not public approval acceptance. Registration
// alone issues neither an original-scope proof nor an authenticated Resolution.
let local_reviewer_account : String =
  #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"original-client-read","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["read"]},"exclusions":[]},{"entry_id":"independent-reviewer-resolve","outcome":"allow","principal":{"any_of":["reviewer"]},"connection":{"any_of":["review-cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["resolve"]},"exclusions":[]}]}

///|
fn local_reviewer_installation_fixture(
  name : String,
  wire? : String = local_reviewer_selection_wire,
  account? : String = local_reviewer_account,
  extra_files? : Int = 0,
) -> (NativeLocalHostConnection, String) {
  let parent = @filesystem.open_private_root(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
  ).unwrap()
  let file = name + ".reviewer.json"
  let writer = parent.create_writer(name + ".reviewer.stage", 8192L).unwrap()
  writer
  .append(
    @utf8.encode(
      wire
      .replace_all(old="\"operator\"", new="\"reviewer\"")
      .replace_all(old="\"cli\"", new="\"review-cli\""),
    ),
  )
  .unwrap()
  writer.seal(file).unwrap() |> ignore
  let files = [file]
  for index in 0..<extra_files {
    let extra = name + ".selected-" + index.to_string() + ".json"
    let writer = parent.create_writer(extra + ".stage", 8192L).unwrap()
    writer.append(b"{}").unwrap()
    writer.seal(extra).unwrap() |> ignore
    files.push(extra)
  }
  (policy_host_fixture(name, files~, account_body=@utf8.encode(account)), file)
}

///|
test "Native Local Reviewer preserves existing seven and eight selected Host files" {
  for count in [7, 8] {
    let (host, file) = local_reviewer_installation_fixture(
      "reviewer-host-bound-" + count.to_string(),
      extra_files=count - 1,
    )
    assert_eq(host.session.settings.files.length(), count)
    assert_true(
      host.install_effect_reviewer(configuration_file=Some(file)) is Ok(_),
    )
    host.close().unwrap()
  }
}

///|
test "Native Local Reviewer installation separates original Client read from Reviewer resolve" {
  let (host, file) = local_reviewer_installation_fixture(
    "reviewer-distinct-roles",
  )
  let crypto = epoch_test_crypto()
  let original_scope = host
    .authority_scope_cid("operator", "cli", crypto)
    .unwrap()
  let reviewer_scope = host
    .authority_scope_cid("reviewer", "review-cli", crypto)
    .unwrap()
  assert_true(original_scope != reviewer_scope)
  assert_true(
    host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "read",
    })
    is Ok(@authorization.Allow(_)),
  )
  assert_true(
    host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "resolve",
    })
    is Ok(@authorization.Deny(_)),
  )
  assert_true(
    host.authorize({
      principal: "reviewer",
      connection: "review-cli",
      resource: "run",
      operation: "read",
    })
    is Ok(@authorization.Deny(_)),
  )
  let installed = host
    .install_effect_reviewer(configuration_file=Some(file))
    .unwrap()
  assert_eq(installed.reviewer.principal, "reviewer")
  assert_eq(installed.reviewer.connection, "review-cli")
  assert_true(installed.current())
  host.close().unwrap()
  assert_false(installed.current())
}

///|
test "Native Local Reviewer missing disabled or unselected registration cannot auto-enable" {
  for disabled in [false, true] {
    let (host, file) = local_reviewer_installation_fixture(
      "reviewer-explicit-" + disabled.to_string(),
      wire=if disabled {
        local_reviewer_selection_wire.replace_all(
          old="\"enabled\":true",
          new="\"enabled\":false",
        )
      } else {
        local_reviewer_selection_wire
      },
    )
    assert_true(host.install_effect_reviewer() is Err(ReviewerUnavailable))
    assert_true(
      host.install_effect_reviewer(configuration_file=Some("unselected.json"))
      is Err(ReviewerUnavailable),
    )
    if disabled {
      assert_true(
        host.install_effect_reviewer(configuration_file=Some(file))
        is Err(ReviewerUnavailable),
      )
    }
    host.close().unwrap()
  }
}

///|
test "Native Local Reviewer read-only or denied resolve cannot borrow original Client permission" {
  for
    (suffix, account) in [
      (
        "read-only",
        local_reviewer_account.replace_all(old="\"resolve\"", new="\"read\""),
      ),
      (
        "denied",
        local_reviewer_account.replace_all(
          old="\"entry_id\":\"independent-reviewer-resolve\",\"outcome\":\"allow\"",
          new="\"entry_id\":\"independent-reviewer-resolve\",\"outcome\":\"deny\"",
        ),
      ),
    ] {
    let (host, file) = local_reviewer_installation_fixture(
      "reviewer-" + suffix,
      account~,
    )
    assert_true(
      host.authorize({
        principal: "operator",
        connection: "cli",
        resource: "run",
        operation: "read",
      })
      is Ok(@authorization.Allow(_)),
    )
    assert_true(
      host.install_effect_reviewer(configuration_file=Some(file))
      is Err(ReviewerUnavailable),
    )
    host.close().unwrap()
  }
}

///|
test "Native Local Reviewer exact-key bytes cannot borrow a replacement file generation" {
  let (host, file) = local_reviewer_installation_fixture(
    "reviewer-file-replaced",
  )
  let installed = host
    .install_effect_reviewer(configuration_file=Some(file))
    .unwrap()
  let parent = host.session.source_root
  let old = parent.inspect_generation(file).unwrap().unwrap()
  parent.reclaim_generation(file, old).unwrap()
  let writer = parent
    .create_writer("reviewer-new-generation.stage", 8192L)
    .unwrap()
  writer.append(installed.original_bytes).unwrap()
  writer.seal(file).unwrap() |> ignore
  assert_false(installed.current())
  assert_true(
    host.install_effect_reviewer(configuration_file=Some(file))
    is Err(ReviewerUnavailable),
  )
  host.close().unwrap()
}

///|
test "Native Local Reviewer original Account replacement or lost retained installation refuses current authority" {
  for account_changed in [false, true] {
    let name = "reviewer-custody-" + account_changed.to_string()
    let (host, file) = local_reviewer_installation_fixture(name)
    let installed = host
      .install_effect_reviewer(configuration_file=Some(file))
      .unwrap()
    if account_changed {
      let parent = host.session.source_root
      let account_file = name + ".account.json"
      let old = parent.inspect_generation(account_file).unwrap().unwrap()
      parent.reclaim_generation(account_file, old).unwrap()
      let writer = parent
        .create_writer(name + ".replacement.stage", 4096L)
        .unwrap()
      writer.append(@utf8.encode(local_reviewer_account)).unwrap()
      writer.seal(account_file).unwrap() |> ignore
    } else {
      let table = @utf8.encode("client_local_settings")
      let key = @utf8.encode("file:" + file)
      assert_true(
        submitted_test_remove_record(
          host.database,
          table,
          table.length(),
          key,
          key.length(),
        ),
      )
    }
    assert_false(installed.current())
    host.close().unwrap()
  }
}
