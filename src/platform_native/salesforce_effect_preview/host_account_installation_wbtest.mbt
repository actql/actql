///|
/// Existing independent Account corpus vector; no permission or expected CID
/// is synthesized from Source, Role, Reviewer or proposed dispatch material.
fn host_account_test_wire() -> String {
  (
    #|{"version":"actql-execution-account-config/0.1","account_id":"local:operator","entries":[{"entry_id":"files","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["local-files"]},"resource":{"all":true},"operation":{"all":true},"exclusions":[]}]}
  )
}

///|
fn host_account_test_file() -> NativeEffectHostAccountFile {
  {
    root: "operator-root",
    name: "account.json",
    subject: {
      principal: "operator",
      account_id: "local:operator",
      configuration_cid: "sha256:e240525257340428cc9117b0b0e84a000996791f43b230abdb553e55223bec12",
      authorization_context_cid: "sha256:" + "b".repeat(64),
      read_connection: "local-files",
      read_resource: "original-evidence",
      publication_connection: "coordinator",
      publication_resource: "original-receiver",
    },
  }
}

///|
test "explicit Host file selection is optional but selected missing is installation failure" {
  let reads = [0]
  let missing = () => {
    reads[0] += 1
    Err(@bounded_files.Missing)
  }
  assert_true(install_host_account_with_read(None, missing) is Ok(None))
  assert_eq(reads[0], 0)
  assert_true(
    install_host_account_with_read(Some(host_account_test_file()), missing)
    is Err(File(@bounded_files.Missing)),
  )
  assert_eq(reads[0], 1)
}

///|
test "explicit Host file is admitted by Common with the independent original configuration CID" {
  let selected = host_account_test_file()
  let installation = install_host_account_with_read(Some(selected), () => {
      Ok(host_account_test_wire())
    })
    .unwrap()
    .unwrap()
  assert_eq(
    installation.subject().configuration_cid,
    selected.subject.configuration_cid,
  )
  assert_true(
    host_account_current_with_read(
      selected,
      "sha256:" + "a".repeat(64),
      false,
      () => Ok(host_account_test_wire()),
    ),
  )
}

///|
test "Host file read authority does not authorize publication" {
  assert_false(
    host_account_current_with_read(
      host_account_test_file(),
      "sha256:" + "a".repeat(64),
      true,
      () => Ok(host_account_test_wire()),
    ),
  )
}

///|
test "Host file rejects invalid oversized foreign and unknown installation" {
  let selected = host_account_test_file()
  for wire in ["not-json", "{}", "x".repeat(1000001)] {
    assert_true(
      install_host_account_with_read(Some(selected), () => Ok(wire)) is Err(_),
    )
  }
  for
    subject in [
      { ..selected.subject, account_id: "foreign", },
      { ..selected.subject, configuration_cid: "sha256:" + "c".repeat(64), },
      { ..selected.subject, authorization_context_cid: "not-a-cid", },
      { ..selected.subject, read_resource: "", },
    ] {
    assert_true(
      install_host_account_with_read(Some({ ..selected, subject, }), () => {
        Ok(host_account_test_wire())
      })
      is Err(_),
    )
  }
  assert_true(
    install_host_account_with_read(Some(selected), () => {
      Err(@bounded_files.InvalidUtf8)
    })
    is Err(File(@bounded_files.InvalidUtf8)),
  )
}

///|
test "Host Core denial no match and unresolved delegation never become Allow" {
  let selected = host_account_test_file()
  for outcome in ["deny", "delegate"] {
    let wire = host_account_test_wire().replace(
      old="\"allow\"",
      new="\"" + outcome + "\"",
    )
    // A separate explicitly installed configuration for each Core outcome.
    let configuration = @authorization.admit_account_configuration_json(wire).unwrap()
    let changed = {
      ..selected,
      subject: {
        ..selected.subject,
        configuration_cid: configuration.configuration_cid(),
      },
    }
    assert_false(
      host_account_current_with_read(
        changed,
        "sha256:" + "a".repeat(64),
        false,
        () => Ok(wire),
      ),
    )
  }
  for
    subject in [
      { ..selected.subject, principal: "site-operator", },
      { ..selected.subject, read_connection: "source-grant", },
    ] {
    assert_false(
      host_account_current_with_read(
        { ..selected, subject, },
        "sha256:" + "a".repeat(64),
        false,
        () => Ok(host_account_test_wire()),
      ),
    )
  }
}

///|
test "Host rereads current placement and refuses deletion replacement and revocation after decision" {
  let selected = host_account_test_file()
  for
    next in [
      Err(@bounded_files.Missing),
      Ok("{}"),
      Ok(host_account_test_wire().replace(old="\"allow\"", new="\"deny\"")),
      Ok(host_account_test_wire().replace(old="local:operator", new="foreign")),
    ] {
    let reads = [0]
    assert_false(
      host_account_current_with_read(
        selected,
        "sha256:" + "a".repeat(64),
        false,
        () => {
          reads[0] += 1
          if reads[0] == 1 {
            Ok(host_account_test_wire())
          } else {
            next
          }
        },
      ),
    )
    assert_eq(reads[0], 2)
  }
}

///|
test "Host first and last current decision use Common and exact original subject" {
  let reads = [0]
  assert_true(
    host_account_current_with_read(
      host_account_test_file(),
      "sha256:" + "a".repeat(64),
      false,
      () => {
        reads[0] += 1
        Ok(host_account_test_wire())
      },
    ),
  )
  assert_eq(reads[0], 2)
  assert_false(
    host_account_current_with_read(
      host_account_test_file(),
      "unbound-dispatch",
      false,
      () => Ok(host_account_test_wire()),
    ),
  )
}

///|
test "explicit independent publication selector can authorize only its original receiver" {
  let wire =
    #|{"version":"actql-execution-account-config/0.1","account_id":"local:operator","entries":[{"entry_id":"files","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["local-files"]},"resource":{"all":true},"operation":{"all":true},"exclusions":[]},{"entry_id":"publish","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["coordinator"]},"resource":{"any_of":["original-receiver"]},"operation":{"any_of":["write"]},"exclusions":[]}]}
  let base = host_account_test_file()
  let selected = {
    ..base,
    subject: {
      ..base.subject,
      configuration_cid: "sha256:5fc192ef14d0ee974bcf0c67db241f92ed91d71d70a8b9b817d129528c3d929f",
    },
  }
  assert_true(
    install_host_account_with_read(Some(selected), () => Ok(wire))
    is Ok(Some(_)),
  )
  assert_true(
    host_account_current_with_read(
      selected,
      "sha256:" + "a".repeat(64),
      false,
      () => Ok(wire),
    ),
  )
  assert_true(
    host_account_current_with_read(selected, "sha256:" + "a".repeat(64), true, () => {
      Ok(wire)
    }),
  )
  let foreign = {
    ..selected,
    subject: { ..selected.subject, publication_resource: "foreign-receiver", },
  }
  assert_false(
    host_account_current_with_read(foreign, "sha256:" + "a".repeat(64), true, () => {
      Ok(wire)
    }),
  )
}
