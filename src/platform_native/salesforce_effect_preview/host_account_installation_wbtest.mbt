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
test "unavailable capacity scope refuses before Account read" {
  let reads = [0]
  assert_true(
    install_host_account_with_read(
      Some(host_account_test_file()),
      _ => {
        reads[0] += 1
        Ok(host_account_test_wire())
      },
      read_scope_current=Some(() => false),
    )
    is Err(ReadScopeUnavailable),
  )
  assert_eq(reads[0], 0)
}

///|
test "scope loss after physical read prevents Common acceptance" {
  let current = Ref(true)
  let reads = [0]
  assert_true(
    install_host_account_with_read(
      Some(host_account_test_file()),
      _ => {
        reads[0] += 1
        current.val = false
        Ok(host_account_test_wire())
      },
      read_scope_current=Some(() => current.val),
    )
    is Err(ReadScopeUnavailable),
  )
  assert_eq(reads[0], 1)
}

///|
test "unselected Host does not read or report a physical failure" {
  let failures = [0]
  assert_true(
    install_native_effect_host_account(
      None,
      on_read_failure=Some(_ => failures[0] += 1),
    )
    is Ok(None),
  )
  assert_eq(failures[0], 0)
}

///|
test "Host failure observer retains original refusal without supplying bytes" {
  let retained : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  let result = read_host_account_file_with_custody(
    host_account_test_file(),
    0,
    Some(failure => retained.val = Some(failure)),
  )
  assert_true(result is Err(@bounded_files.InvalidLimit))
  guard retained.val is Some(failure) else {
    fail("original failure not retained by caller")
  }
  assert_true(failure.issue() is @bounded_files.InvalidLimit)
  assert_true(failure.root_cleanup_issue() is None)
  failure.retry_cleanup().unwrap()
  assert_true(result is Err(@bounded_files.InvalidLimit))
}

///|
test "explicit Host file selection is optional but selected missing is installation failure" {
  let reads = [0]
  let missing = _limit => {
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
  let installation = install_host_account_with_read(Some(selected), _limit => {
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
      _limit => Ok(host_account_test_wire()),
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
      _limit => Ok(host_account_test_wire()),
    ),
  )
}

///|
test "Host file rejects invalid oversized foreign and unknown installation" {
  let selected = host_account_test_file()
  for wire in ["not-json", "{}", "x".repeat(1000001)] {
    assert_true(
      install_host_account_with_read(Some(selected), _limit => Ok(wire))
      is Err(_),
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
      install_host_account_with_read(Some({ ..selected, subject, }), _limit => {
        Ok(host_account_test_wire())
      })
      is Err(_),
    )
  }
  assert_true(
    install_host_account_with_read(Some(selected), _limit => {
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
        _limit => Ok(wire),
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
        _limit => Ok(host_account_test_wire()),
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
        _limit => {
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
      _limit => {
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
      _limit => Ok(host_account_test_wire()),
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
    install_host_account_with_read(Some(selected), _limit => Ok(wire))
    is Ok(Some(_)),
  )
  assert_true(
    host_account_current_with_read(
      selected,
      "sha256:" + "a".repeat(64),
      false,
      _limit => Ok(wire),
    ),
  )
  assert_true(
    host_account_current_with_read(selected, "sha256:" + "a".repeat(64), true, _limit => {
      Ok(wire)
    }),
  )
  let foreign = {
    ..selected,
    subject: { ..selected.subject, publication_resource: "foreign-receiver", },
  }
  assert_false(
    host_account_current_with_read(foreign, "sha256:" + "a".repeat(64), true, _limit => {
      Ok(wire)
    }),
  )
}

///|
test "Host omitted ceiling preserves the original million byte read limit" {
  let limits = []
  let installation = install_host_account_with_read(
      Some(host_account_test_file()),
      limit => {
        limits.push(limit)
        Ok(host_account_test_wire())
      },
    )
    .unwrap()
    .unwrap()
  assert_eq(installation.read_ceiling, 1000000)
  assert_eq(limits.length(), 1)
  assert_eq(limits[0], 1000000)
  let explicit = install_host_account_with_read(
      Some(host_account_test_file()),
      _limit => Ok(host_account_test_wire()),
      read_ceiling=1000000,
    )
    .unwrap()
    .unwrap()
  assert_eq(explicit.read_ceiling, installation.read_ceiling)
}

///|
test "Host rejects invalid operator ceilings before any read" {
  for limit in [-1, 0, 1000001] {
    let reads = [0]
    let read = _limit => {
      reads[0] += 1
      Ok(host_account_test_wire())
    }
    assert_true(
      install_host_account_with_read(
        Some(host_account_test_file()),
        read,
        read_ceiling=limit,
      )
      is Err(InvalidSelection),
    )
    assert_eq(reads[0], 0)
    assert_true(
      install_host_account_with_read(None, read, read_ceiling=limit) is Ok(None),
    )
    assert_eq(reads[0], 0)
  }
}

///|
test "Host selected ceiling accepts exact UTF8 bytes and refuses one extra byte" {
  let selected = host_account_test_file()
  let wire = host_account_test_wire()
  let ceiling = 32768
  let exact = wire + " ".repeat(ceiling - @utf8.encode(wire).length())
  // JSON whitespace does not change the independent original configuration.
  assert_eq(@utf8.encode(exact).length(), ceiling)
  let limits = []
  let installation = install_host_account_with_read(
      Some(selected),
      limit => {
        limits.push(limit)
        Ok(exact)
      },
      read_ceiling=ceiling,
    )
    .unwrap()
    .unwrap()
  assert_eq(installation.read_ceiling, ceiling)
  assert_eq(limits.length(), 1)
  assert_eq(limits[0], ceiling)
  assert_true(
    install_host_account_with_read(
      Some(selected),
      _limit => Ok(exact + " "),
      read_ceiling=ceiling,
    )
    is Err(File(@bounded_files.CapacityExceeded)),
  )
}

///|
test "Host ceiling uses UTF8 bytes before Common configuration admission" {
  let wire = "\"é\""
  assert_eq(wire.length(), 3)
  assert_eq(@utf8.encode(wire).length(), 4)
  assert_true(
    host_account_configuration(
      host_account_test_file(),
      _limit => Ok(wire),
      read_ceiling=3,
    )
    is Err(File(@bounded_files.CapacityExceeded)),
  )
  // Exact byte length reaches Common admission, which refuses a scalar config.
  assert_true(
    host_account_configuration(
      host_account_test_file(),
      _limit => Ok(wire),
      read_ceiling=4,
    )
    is Err(Configuration(_)),
  )
}

///|
test "Host current first and final reads retain the installed ceiling" {
  let selected = host_account_test_file()
  let wire = host_account_test_wire()
  let ceiling = @utf8.encode(wire).length()
  let installation = install_host_account_with_read(
      Some(selected),
      _limit => Ok(wire),
      read_ceiling=ceiling,
    )
    .unwrap()
    .unwrap()
  let limits = []
  assert_true(
    host_account_current_with_read(
      installation.selected,
      "sha256:" + "a".repeat(64),
      false,
      limit => {
        limits.push(limit)
        Ok(wire)
      },
      read_ceiling=installation.read_ceiling,
    ),
  )
  assert_eq(limits.length(), 2)
  assert_eq(limits[0], ceiling)
  assert_eq(limits[1], ceiling)
  for changed_read in [1, 2] {
    let reads = [0]
    let limits = []
    assert_false(
      host_account_current_with_read(
        installation.selected,
        "sha256:" + "a".repeat(64),
        false,
        limit => {
          reads[0] += 1
          limits.push(limit)
          Ok(if reads[0] == changed_read { wire + " " } else { wire })
        },
        read_ceiling=installation.read_ceiling,
      ),
    )
    assert_eq(reads[0], changed_read)
    assert_eq(limits.length(), changed_read)
    for limit in limits {
      assert_eq(limit, ceiling)
    }
  }
}

///|
test "Host bounded current failure foreign CID and revocation remain refusal" {
  let selected = host_account_test_file()
  let wire = host_account_test_wire()
  for
    next in [
      Err(@bounded_files.Missing),
      Err(@bounded_files.InvalidUtf8),
      Ok(wire.replace(old="local:operator", new="foreign")),
      Ok(wire.replace(old="\"allow\"", new="\"deny\"")),
    ] {
    let reads = [0]
    let limits = []
    assert_false(
      host_account_current_with_read(
        selected,
        "sha256:" + "a".repeat(64),
        false,
        limit => {
          limits.push(limit)
          reads[0] += 1
          if reads[0] == 1 {
            Ok(wire)
          } else {
            next
          }
        },
        read_ceiling=32768,
      ),
    )
    assert_eq(reads[0], 2)
    assert_eq(limits.length(), 2)
    for limit in limits {
      assert_eq(limit, 32768)
    }
  }
}

///|
test "Host diagnostic selection is immutable and independent of Account body ceiling" {
  let selected = host_account_test_file()
  let read = _ => Ok(host_account_test_wire())
  let legacy = install_host_account_with_read(Some(selected), read).unwrap().unwrap()
  assert_true(legacy.diagnostic_ceiling is None)
  let explicit = install_host_account_with_read(
    Some(selected), read, read_ceiling=32768, diagnostic_ceiling=Some(7),
  ).unwrap().unwrap()
  assert_eq(explicit.read_ceiling, 32768)
  assert_eq(explicit.diagnostic_ceiling, Some(7))
  assert_eq(explicit.subject().principal, legacy.subject().principal)
  assert_eq(explicit.subject().configuration_cid, legacy.subject().configuration_cid)
}

///|
test "invalid selected Host diagnostic ceiling refuses before Account read" {
  let reads = [0]
  for ceiling in [-1, 0] {
    assert_true(
      install_host_account_with_read(
        Some(host_account_test_file()),
        _ => { reads[0] += 1; Ok(host_account_test_wire()) },
        diagnostic_ceiling=Some(ceiling),
      ) is Err(InvalidSelection),
    )
    assert_true(
      install_native_effect_host_account(
        Some(host_account_test_file()), diagnostic_ceiling=Some(ceiling),
      ) is Err(InvalidSelection),
    )
  }
  assert_eq(reads[0], 0)
}

///|
test "unselected Host diagnostic ceiling creates no installation or failure" {
  let reads = [0]
  let failures = [0]
  for ceiling in [-1, 0, 7] {
    assert_true(
      install_host_account_with_read(
        None,
        _ => { reads[0] += 1; Ok(host_account_test_wire()) },
        diagnostic_ceiling=Some(ceiling),
      ) is Ok(None),
    )
    assert_true(
      install_native_effect_host_account(
        None,
        diagnostic_ceiling=Some(ceiling),
        on_read_failure=Some(_ => failures[0] += 1),
      ) is Ok(None),
    )
  }
  assert_eq(reads[0], 0)
  assert_eq(failures[0], 0)
}
