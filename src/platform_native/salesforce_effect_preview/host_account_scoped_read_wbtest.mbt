///|
test "unselected strict Account installation performs no read" {
  let reads = Ref(0)
  let installed = install_host_account_with_read(
    None,
    _ => {
      reads.val += 1
      Ok(host_account_test_wire())
    },
    require_current_read_context=true,
  )
  assert_true(installed is Ok(None))
  assert_eq(reads.val, 0)
}

///|
test "strict Account physical selection requires a positive diagnostic bound before read" {
  for diagnostic in [None, Some(0), Some(-1)] {
    let reads = Ref(0)
    assert_true(
      install_host_account_with_read(
        Some(host_account_test_file()),
        _ => {
          reads.val += 1
          Ok(host_account_test_wire())
        },
        diagnostic_ceiling=diagnostic,
        require_current_read_context=true,
      )
      is Err(InvalidSelection),
    )
    assert_eq(reads.val, 0)
  }
}

///|
test "strict Account selection survives installation and never treats a true callback as a context" {
  // The private seam's original checked bytes prove neither a physical read
  // nor the installer's capacity/current authority.
  let reads = Ref(0)
  let installed = install_host_account_with_read(
      Some(host_account_test_file()),
      _ => {
        reads.val += 1
        Ok(host_account_test_wire())
      },
      diagnostic_ceiling=Some(16),
      require_current_read_context=true,
      read_scope_current=Some(() => true),
    )
    .unwrap()
    .unwrap()
  assert_eq(reads.val, 1)
  assert_true(installed.require_current_read_context)
  assert_eq(installed.diagnostic_ceiling, Some(16))
  // Stock/portable builds have no installed physical context. Both current
  // configuration and approval-time permission must fail closed.
  assert_true(installed.read_current_configuration() is None)
  assert_false(installed.current_permission("sha256:" + "a".repeat(64), false))
  assert_false(installed.current_permission("sha256:" + "a".repeat(64), true))
}

///|
test "strict Account read retains its physical refusal through repeated cleanup" {
  let observed : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  let failure = read_host_account_file_with_custody(
    host_account_test_file(),
    512,
    Some(original => observed.val = Some(original)),
    diagnostic_ceiling=Some(16),
    require_current_read_context=true,
  )
  assert_true(failure is Err(_))
  guard observed.val is Some(original) else {
    fail("original physical refusal lost")
  }
  assert_true(failure is Err(issue) && physical_equal(issue, original.issue()))
  match original.issue() {
    @bounded_files.Filesystem(@files.UnsupportedTarget) => ()
    @bounded_files.Filesystem(@files.RootOpen(detail)) =>
      assert_eq(detail, "Current read scope was refused")
    _ => fail("strict read reached an unscoped physical port")
  }
  original.retry_cleanup().unwrap()
  original.retry_cleanup().unwrap()
  assert_true(failure is Err(issue) && physical_equal(issue, original.issue()))
}

///|
test "omitted strict selection preserves the existing independent Account seam" {
  let installed = install_host_account_with_read(
      Some(host_account_test_file()),
      _ => Ok(host_account_test_wire()),
    )
    .unwrap()
    .unwrap()
  assert_false(installed.require_current_read_context)
  assert_eq(
    installed.subject().configuration_cid,
    host_account_test_file().subject.configuration_cid,
  )
}

///|
test "public strict Account installation refuses without actual context before legacy file access" {
  let observed : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  let result = install_native_effect_host_account(
    Some(host_account_test_file()),
    diagnostic_ceiling=Some(16),
    require_current_read_context=true,
    read_scope_current=Some(() => true),
    on_read_failure=Some(original => observed.val = Some(original)),
  )
  assert_true(result is Err(File(_)))
  guard observed.val is Some(original) else { fail("original refusal lost") }
  match original.issue() {
    @bounded_files.Filesystem(@files.UnsupportedTarget) => ()
    @bounded_files.Filesystem(@files.RootOpen(detail)) =>
      assert_eq(detail, "Current read scope was refused")
    _ => fail("initial strict read reached the legacy port")
  }
  original.retry_cleanup().unwrap()
}
