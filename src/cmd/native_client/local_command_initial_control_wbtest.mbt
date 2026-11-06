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
    NativeCommandArgumentStop(message) => message
    _ => fail("original argument failure must retain its typed parse boundary")
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

///|
test "Initial command control preserves exact application text copy" {
  let original = String::from_array([
    'e',
    (0xD800).unsafe_to_char(),
    '\u{0000}',
    (0xDC00).unsafe_to_char(),
    '\r',
    '\n',
  ])
  let copied = command_control_copy_text(original)
  assert_eq(copied.length(), original.length())
  assert_eq(copied.code_units().to_owned(), original.code_units().to_owned())
  assert_eq(command_control_copy_text(""), "")
}

///|
test "Selected command preparation frontend does not acquire before covered operation" {
  for
    arguments in [
      ["original", "--mode", "remote", "check", "SELECT 1"],
      ["original", "--mode", "local", "connect"],
      [
        "original",
        "--mode",
        "local",
        "lookup-preparation-raw",
        "--submission-ref-file",
        "unbound-submission.json",
        "--ref-file",
        "unbound-run.json",
        "--grant-ref-file",
        "unbound-grant.json",
        "--operation-cid",
        "sha256:" + "a".repeat(64),
        "--use-id",
        "unbound-use",
      ],
    ] {
    let control = parse_native_initial_arguments(arguments, false)
    let matches = control.matches.unwrap()
    assert_false(local_command_preparation_selected(matches))
    prepare_native_command_invocation(matches)
    assert_true(command_preparation_invocation.val is None)
  }
  let control = parse_native_initial_arguments(
    ["original", "--mode", "local", "check", "SELECT 1"],
    false,
  )
  assert_true(local_command_preparation_selected(control.matches.unwrap()))
  // Saved status now has its own original Read route. Selection grants no
  // RunRead or physical acquisition; preserve an actually unsupported private
  // lookup above as the negative fixture rather than rejecting valid status.
  let saved_status = parse_native_initial_arguments(
    ["original", "--mode", "local", "status", "--run-id", "unbound"],
    false,
  )
  assert_true(local_command_preparation_selected(saved_status.matches.unwrap()))
  assert_true(command_preparation_invocation.val is None)
  let initialization = parse_native_initial_arguments(
    ["original", "--mode", "local", "adopt", "--initialize-signing"],
    false,
  )
  assert_true(
    local_command_preparation_selected(initialization.matches.unwrap()),
  )
  // An unmeasured process must not select the compatibility path. Main performs
  // this real original observation before parse; reproduce that order here.
  let unmeasured = try {
    prepare_native_command_invocation(control.matches.unwrap())
    false
  } catch {
    ClientStop(message) => message == "LocalCommandPreparationUnavailable"
  }
  assert_true(unmeasured)
  assert_false(
    command_preparation_result(
      command_preargument_bound(1048576, 1048576, 1048576, 8192),
    ),
  )
  prepare_native_command_invocation(control.matches.unwrap())
  assert_true(command_preparation_invocation.val is None)
}

///|
test "Selected command preparation reports the original failure boundary without payloads" {
  let refused : Result[Unit, LocalCommandPreparationIssue] = Err(
    CommandAdoption(@local_host.CustodyLost),
  )
  let staged = try {
    ignore(command_preparation_result(refused, stage=Some("product-stage")))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(staged, "LocalCommandPreparationUnavailable:product-stage:adoption")
  let unavailable : Result[Unit, LocalCommandPreparationIssue] = Err(
    CommandUnavailable,
  )
  let unstaged = try {
    ignore(command_preparation_result(unavailable))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(unstaged, "LocalCommandPreparationUnavailable")
  let public_failure : Result[Unit, LocalCommandPreparationIssue] = Err(
    CommandApplication("OriginalPublicFailure"),
  )
  let application = try {
    ignore(
      command_preparation_result(public_failure, stage=Some("product-stage")),
    )
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(application, "OriginalPublicFailure")
}

///|
test "Original command failure survives a failed Read return without publishing a reply" {
  let returned = CommandAdoption(@local_host.OriginalResourceScopePending)
  let issue = command_preparation_read_return_issue(
    Some(Err("OriginalBusinessFailure")),
    returned,
  )
  let refused : Result[Unit, LocalCommandPreparationIssue] = Err(issue)
  let message = try {
    ignore(command_preparation_result(refused, stage=Some("command-read")))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(message, "OriginalBusinessFailure")
  assert_true(
    command_preparation_read_return_issue(
      Some(Ok("unconfirmed reply")),
      returned,
    )
    is CommandAdoption(@local_host.OriginalResourceScopePending),
  )
  assert_true(
    command_preparation_read_return_issue(None, returned)
    is CommandAdoption(@local_host.OriginalResourceScopePending),
  )
}

///|
test "Selected command preparation missing compiled layouts refuses before backing" {
  let failure = try {
    ignore(
      local_command_installed_profile(
        "0000000000000000000000000000000000000001", "0000000000000000000000000000000000000000000000000000000000000001",
      ),
    )
    "unexpected profile"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(failure, "LocalCommandPreparationLayoutUnavailable")
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}

///|
test "Selected command adoption metadata preserves existing exact reply bytes" {
  let control = parse_native_initial_arguments(
    ["original", "--mode", "local", "adopt", "--json"],
    false,
  )
  let child = control.matches.unwrap().subcommand.unwrap().1
  assert_eq(
    local_adoption_metadata_reply(
      true, "account", "configuration", "adoption", child,
    ),
    "{\"kind\":\"local_host_adopted\",\"mode\":\"local\",\"accountId\":\"account\",\"accountConfigurationCid\":\"configuration\",\"adoptionCid\":\"adoption\"}",
  )
  let plain = parse_native_initial_arguments(["original", "connect"], false)
  let child = plain.matches.unwrap().subcommand.unwrap().1
  assert_eq(
    local_adoption_metadata_reply(
      false, "account", "configuration", "adoption", child,
    ),
    "Local Host connected; no Run has been admitted.\nAccount: account\nAdoption: adoption",
  )
  assert_true(command_preparation_invocation.val is None)
}

///|
test "cleanup cause exposes only closed categories and leaves original family unchanged" {
  let issue = CommandAdoption(@local_host.CustodyLost)
  assert_eq(command_preparation_cleanup_kind(issue), "adoption")
  assert_eq(command_preparation_cleanup_cause(issue), "CustodyLost")
  let private_message = CommandApplication("private-original-message")
  assert_eq(
    command_preparation_cleanup_cause(private_message),
    "CommandApplication",
  )
  let store = CommandBusinessStore(
    @local_store.LegacyStoreFormat("private-path"),
  )
  assert_eq(command_preparation_cleanup_kind(store), "business-store")
  assert_eq(command_preparation_cleanup_cause(store), "LegacyStoreFormat")
}

///|
test "initial Crypto filesystem diagnostic retains its family without private details" {
  assert_eq(
    initial_crypto_issue_message(Filesystem(@local_filesystem.InvalidName)),
    "Filesystem(InvalidName)",
  )
}
