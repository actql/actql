///|
test "Initial command control retains exact argv and pinned parsed matches" {
  let arguments = [
    "original executable", "--mode", "local", "check", "SELECT '日本語 😀'",
  ]
  let control = parse_native_initial_arguments(arguments, false)
  assert_true(physical_equal(control.arguments, arguments))
  assert_eq(control.arguments[0], "original executable")
  assert_eq(required(control.matches, "mode"), "local")
  guard control.matches.subcommand is Some(("check", child)) else {
    abort("missing original check matches")
  }
  assert_eq(required(child, "program"), "SELECT '日本語 😀'")
  assert_true(control.classes is None)
  assert_true(command_preparation_invocation.val is None)
  command_initial_control_keep_alive(control)
}

///|
test "Initial command control keeps contextual parse failure without physical acquisition" {
  let arguments = ["original executable", "--definitely-unknown"]
  let message = try {
    ignore(parse_native_initial_arguments(arguments, false))
    "unexpected parse success"
  } catch {
    error => error.to_string()
  }
  assert_true(message.contains("--definitely-unknown"))
  assert_true(message.contains("Usage:"))
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}

///|
test "Initial command control rejects selected input without original raw observation" {
  let arguments = ["original executable", "check", "SELECT 1"]
  let failed = try {
    ignore(parse_native_initial_arguments(arguments, true))
    false
  } catch {
    ClientStop(message) => message == "LocalCommandPreparationUnavailable"
    _ => false
  }
  assert_true(failed)
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}

///|
test "Local original home selection skips acquisition for explicit state directory" {
  let reads = Ref(0)
  let location = local_product_location_with_home(Some("/original/state"), () => {
    reads.val += 1
    stop("must not acquire HOME")
  })
  assert_eq(reads.val, 0)
  assert_eq(location.parent_path, "/original")
  assert_eq(location.directory_name, "state")
}

///|
test "Local original home selection reads once only for absent state directory" {
  let reads = Ref(0)
  let location = local_product_location_with_home(None, () => {
    reads.val += 1
    Some("/original/home")
  })
  assert_eq(reads.val, 1)
  assert_eq(location.parent_path, "/original/home")
  assert_eq(location.directory_name, ".actql-local")
}

///|
test "Local original home selection preserves missing original refusal" {
  let reads = Ref(0)
  let issue = try {
    ignore(
      local_product_location_with_home(None, () => {
        reads.val += 1
        None
      }),
    )
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(reads.val, 1)
  assert_eq(issue, "LocalProductHomeUnavailable")
  assert_true(command_preparation_invocation.val is None)
}
