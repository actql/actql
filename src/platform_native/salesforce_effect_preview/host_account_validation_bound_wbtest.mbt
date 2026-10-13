///|
test "private Account read validation keeps byte overflow and Core refusal distinct" {
  let reads = [0]
  assert_true(
    host_account_configuration(
      host_account_test_file(),
      _ => {
        reads[0] += 1
        Ok(" ".repeat(32769))
      },
      read_ceiling=32768,
    )
    is Err(File(@bounded_files.CapacityExceeded)),
  )
  assert_eq(reads[0], 1)
  for (ceiling, capacity_failure) in [(3, true), (4, false)] {
    let result = host_account_configuration(
      host_account_test_file(),
      _ => Ok("\"é\""),
      read_ceiling=ceiling,
    )
    if capacity_failure {
      assert_true(result is Err(File(@bounded_files.CapacityExceeded)))
    } else {
      assert_true(result is Err(Configuration(_)))
    }
  }
}

///|
test "Account root and name byte ceilings refuse before the private read" {
  let selected = host_account_test_file()
  let reads = [0]
  for root in ["x".repeat(4097), "é".repeat(2049)] {
    assert_true(
      install_host_account_with_read(
        Some({ ..selected, root, }),
        _ => {
          reads[0] += 1
          Ok(host_account_test_wire())
        },
      )
      is Err(InvalidSelection),
    )
  }
  for name in ["x".repeat(4097), "é".repeat(2049)] {
    assert_true(
      install_host_account_with_read(
        Some({ ..selected, name, }),
        _ => {
          reads[0] += 1
          Ok(host_account_test_wire())
        },
      )
      is Err(InvalidSelection),
    )
  }
  assert_eq(reads[0], 0)
  assert_true(
    install_host_account_with_read(
      Some({ ..selected, root: "é".repeat(2048), name: "x".repeat(4096), }),
      _ => Ok(host_account_test_wire()),
    )
    is Ok(Some(_)),
  )
}

///|
test "Account subject byte bound preserves original values without a permission" {
  let selected = host_account_test_file()
  let reads = [0]
  for principal in ["x".repeat(513), "é".repeat(257)] {
    assert_true(
      install_host_account_with_read(
        Some({ ..selected, subject: { ..selected.subject, principal, }, }),
        _ => {
          reads[0] += 1
          Ok(host_account_test_wire())
        },
      )
      is Err(InvalidSelection),
    )
  }
  assert_eq(reads[0], 0)
  for principal in ["x".repeat(512), "é".repeat(256), "e\u{301}"] {
    let installed = install_host_account_with_read(
        Some({ ..selected, subject: { ..selected.subject, principal, }, }),
        _ => Ok(host_account_test_wire()),
      )
      .unwrap()
      .unwrap()
    assert_eq(installed.subject().principal, principal)
    assert_false(
      host_account_current_with_read(
        installed.selected,
        "sha256:" + "a".repeat(64),
        false,
        _ => Ok(host_account_test_wire()),
      ),
    )
  }
}
