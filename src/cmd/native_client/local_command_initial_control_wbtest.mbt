///|
test "Initial command control retains exact argv and pinned parsed matches" {
  let arguments = [
    "original executable", "--mode", "local", "check", "SELECT '日本語 😀'",
  ]
  let control = parse_native_initial_arguments(arguments, false)
  assert_true(physical_equal(control.arguments, arguments))
  assert_eq(control.arguments[0], "original executable")
  assert_eq(required(control.matches.unwrap(), "mode"), "local")
  guard control.matches.unwrap().subcommand is Some(("check", child)) else {
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

///|
test "Initial command control transfers mutable Matches before caller cleanup" {
  let arguments = ["original executable", "check", "SELECT 1"]
  let control = parse_native_initial_arguments(arguments, false)
  let calls = Ref(0)
  let transferred = Ref(false)
  let selected = Ref("")
  control.consume_matches(matches => {
    calls.val += 1
    transferred.val = control.matches is None
    // The actual selection paths mutate these maps. This counter proves the
    // caller transfer only; these literal values are not a physical Read loan.
    matches.values["state-dir"] = ["/selected/original"]
    matches.values["config-root"] = ["/selected/original/config"]
    selected.val = required(matches, "state-dir")
  })
  assert_eq(calls.val, 1)
  assert_true(transferred.val)
  assert_eq(selected.val, "/selected/original")
  assert_true(control.matches is None)
  assert_eq(control.arguments, arguments)
  command_initial_control_keep_alive(control)
}

///|
test "Initial command control does not redispatch consumed Matches after failure" {
  let control = parse_native_initial_arguments(
    ["original executable", "check", "SELECT 1"],
    false,
  )
  let calls = Ref(0)
  let issue = try {
    control.consume_matches(_matches => {
      calls.val += 1
      stop("OriginalCommandFailure")
    })
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "OriginalCommandFailure")
  assert_true(control.matches is None)
  let duplicate = try {
    control.consume_matches(_matches => calls.val += 1)
    "unexpected duplicate"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(duplicate, "LocalCommandAlreadyConsumed")
  assert_eq(calls.val, 1)
  assert_true(command_preparation_invocation.val is None)
  command_initial_control_keep_alive(control)
}
