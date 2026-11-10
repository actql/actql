///|
// Settings/caller definitions only until the matching Native fixture runs.
// No Source, signature, Store, Checkpoint admission or Provider is exercised.
let local_reviewer_cli_configuration : String =
  #|{"version":"actql-config/0.1","account_config":"account.json","native":{"check_environment":{"file":"environment.json","evidence_bundle_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"local":{"account_id":"operator","principal":"original-client","connection":"original-cli","state_parent":"/private/local-state","state_name":"host","managed_root":"/private/local-results","sqlite_library":"/private/libsqlite3.dylib","signature_library":"/private/libcrypto.dylib","submission_ttl_ms":60000,"journal_record_limit":8,"journal_snapshot_bytes":8388608,"installation_files":["reviewer.json"]}}}

///|
test "CLI Reviewer selection defaults to none without changing original Client role" {
  let settings = local_host_settings(local_reviewer_cli_configuration)
  assert_eq(settings.reviewer_file, None)
  assert_eq(settings.principal, "original-client")
  assert_eq(settings.connection, "original-cli")
  // None does not read this intentionally unavailable root or scan files.
  assert_eq(
    local_selected_effect_reviewer_original("/not-a-reviewer-root", settings),
    None,
  )
}

///|
test "CLI explicitly selects Reviewer only within existing finite installation originals" {
  let selected = local_reviewer_cli_configuration.replace_all(
    old="\"installation_files\":",
    new="\"reviewer_file\":\"reviewer.json\",\"installation_files\":",
  )
  let settings = local_host_settings(selected)
  assert_eq(settings.reviewer_file, Some("reviewer.json"))
  assert_eq(settings.installation_files, ["reviewer.json"])
  assert_eq(settings.principal, "original-client")
  assert_eq(settings.connection, "original-cli")
  let six = selected.replace_all(
    old="[\"reviewer.json\"]",
    new="[\"reviewer.json\",\"source.json\",\"run.json\",\"read.json\",\"other-one.json\",\"other-two.json\"]",
  )
  assert_eq(local_host_settings(six).installation_files.length(), 6)
  let seventh = six.replace_all(
    old="\"other-two.json\"]",
    new="\"other-two.json\",\"seventh.json\"]",
  )
  assert_eq(local_host_settings(seventh).installation_files.length(), 7)
  let eighth = seventh.replace_all(
    old="\"seventh.json\"]",
    new="\"seventh.json\",\"eighth.json\"]",
  )
  assert_eq(local_host_settings(eighth).installation_files.length(), 8)
  let ninth = eighth.replace_all(
    old="\"eighth.json\"]",
    new="\"eighth.json\",\"ninth.json\"]",
  )
  assert_true(
    try {
      local_host_settings(ninth) |> ignore
      false
    } catch {
      ClientStop(message) => message == "InvalidLocalInstallationSelection"
    },
  )
}

///|
test "CLI refuses unselected null or duplicate Reviewer field before original file read" {
  for
    (field, expected) in [
      (
        "\"reviewer_file\":\"unselected.json\",", "LocalReviewerOriginalNotSelected",
      ),
      ("\"reviewer_file\":null,", "InvalidLocalHostConfiguration"),
      (
        "\"reviewer_file\":\"reviewer.json\",\"reviewer_file\":\"other.json\",",
        "LocalInputNotAdmitted",
      ),
    ] {
    let wire = local_reviewer_cli_configuration.replace_all(
      old="\"installation_files\":",
      new=field + "\"installation_files\":",
    )
    assert_true(
      try {
        local_host_settings(wire) |> ignore
        false
      } catch {
        ClientStop(message) => message == expected
      },
    )
  }
}

///|
test "Native Host Reviewer binding retains the opaque original custody scope" {
  let caller = fn(
    host : @local_host.NativeLocalHostConnection,
    crypto : @local_crypto.Library,
    principal : String,
    connection : String,
    reference : @local_host.NativeClientSubmissionReference,
    request : @run_host.ClientRequestIdentity,
    scope : @source_owner.ResidentOriginalEffectApprovalScope,
    now : () -> Double,
  ) {
    host.bind_effect_reviewer(
      crypto, principal, connection, reference, request, scope, now,
    )
  }
  caller |> ignore
}

///|
test "CLI initial Host signing selection is explicit DATA without changing Client or Reviewer roles" {
  let before = local_host_settings(local_reviewer_cli_configuration)
  assert_eq(before.initial_host_signing, None)
  let wire = local_reviewer_cli_configuration.replace_all(
    old="\"installation_files\":",
    new="\"initial_host_signing\":{\"principal\":\"host-machine\",\"connection\":\"host-cli\",\"resource\":\"key/initial-host-attestation\"},\"installation_files\":",
  )
  let selected = local_host_settings(wire)
  assert_eq(
    selected.initial_host_signing,
    Some(("host-machine", "host-cli", "key/initial-host-attestation")),
  )
  assert_eq(selected.principal, before.principal)
  assert_eq(selected.connection, before.connection)
  assert_eq(selected.reviewer_file, None)
  assert_eq(selected.installation_files, before.installation_files)
}

///|
test "CLI initial Host signing selection refuses null incomplete unknown and unbounded actors" {
  for
    selected in [
      "null",
      "{}",
      "{\"principal\":\"p\",\"connection\":\"c\"}",
      "{\"principal\":\"p\",\"connection\":\"c\",\"resource\":\"r\",\"extra\":\"x\"}",
      "{\"principal\":\"" +
      "p".repeat(257) +
      "\",\"connection\":\"c\",\"resource\":\"r\"}",
    ] {
    let wire = local_reviewer_cli_configuration.replace_all(
      old="\"installation_files\":",
      new="\"initial_host_signing\":" + selected + ",\"installation_files\":",
    )
    assert_true(
      try {
        local_host_settings(wire) |> ignore
        false
      } catch {
        ClientStop(_) => true
      },
    )
  }
}

///|
test "CLI Journal record policy preserves checked Int boundaries above 1024" {
  for records in [1L, 1023L, 1024L, 1025L, 2147483647L] {
    assert_eq(local_host_journal_record_limit(records), Some(records.to_int()))
    let selected = local_reviewer_cli_configuration.replace_all(
      old="\"journal_record_limit\":8",
      new="\"journal_record_limit\":" + records.to_string(),
    )
    let settings = local_host_settings(selected)
    assert_eq(settings.record_limit, records.to_int())
    assert_eq(settings.snapshot_bytes, 8388608L)
    assert_eq(settings.principal, "original-client")
    assert_eq(settings.connection, "original-cli")
  }
  for records in [0L, -1L, 2147483648L, 9223372036854775807L] {
    assert_eq(local_host_journal_record_limit(records), None)
    let selected = local_reviewer_cli_configuration.replace_all(
      old="\"journal_record_limit\":8",
      new="\"journal_record_limit\":" + records.to_string(),
    )
    assert_true(
      try {
        local_host_settings(selected) |> ignore
        false
      } catch {
        ClientStop(message) => message == "InvalidLocalHostLimits"
      },
    )
  }
}
