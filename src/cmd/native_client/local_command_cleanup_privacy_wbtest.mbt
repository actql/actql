///|
test "Native cleanup categories retain real payload families without disclosing private DATA" {
  let private_message = "PRIVATE_PATH_KEY_OR_APPLICATION_DATA"
  let cases : Array[(LocalCommandPreparationIssue, String, String)] = [
    (
      CommandFilesystemCleanup(RootOpen(private_message)),
      "filesystem-cleanup",
      "RootOpen",
    ),
    (
      CommandFilesystemCleanup(Read(private_message)),
      "filesystem-cleanup",
      "Read",
    ),
    (
      CommandFilesystemCleanup(Cleanup(private_message)),
      "filesystem-cleanup",
      "Cleanup",
    ),
    (
      CommandSignature(InvalidPrivateKey(private_message)),
      "signature",
      "InvalidPrivateKey",
    ),
    (
      CommandSignature(Verification(private_message)),
      "signature",
      "Verification",
    ),
    (
      CommandBusinessStore(LegacyStoreFormat(private_message)),
      "business-store",
      "LegacyStoreFormat",
    ),
    (
      CommandAdoption(Filesystem(RootOpen(private_message))),
      "adoption",
      "Filesystem",
    ),
    (CommandApplication(private_message), "application", "CommandApplication"),
  ]
  for (issue, kind, cause) in cases {
    assert_eq(command_preparation_cleanup_kind(issue), kind)
    assert_eq(command_preparation_cleanup_cause(issue), cause)
    assert_false(
      command_preparation_cleanup_cause(issue).contains(private_message),
    )
  }
  // Classification borrows the real retained error; it cannot replace its DATA.
  guard cases[0].0 is CommandFilesystemCleanup(RootOpen(message)) else {
    abort("Original cleanup family changed")
  }
  assert_eq(message, private_message)
  guard cases[3].0 is CommandSignature(InvalidPrivateKey(message)) else {
    abort("Original signing family changed")
  }
  assert_eq(message, private_message)
  guard cases[7].0 is CommandApplication(message) else {
    abort("Original application family changed")
  }
  assert_eq(message, private_message)
}

///|
test "Native preparation diagnostics use closed cleanup labels for real nested failures" {
  let cases : Array[(LocalCommandPreparationIssue, String)] = [
    (CommandFilesystemCleanup(RootOpen("PRIVATE_ROOT")), "filesystem-cleanup"),
    (CommandSignature(InvalidPrivateKey("PRIVATE_KEY")), "signature"),
    (CommandBusinessStore(LegacyStoreFormat("PRIVATE_STORE")), "business-store"),
    (CommandAdoption(Filesystem(Cleanup("PRIVATE_CLEANUP"))), "adoption"),
  ]
  for (issue, kind) in cases {
    local_command_diagnostic_reset()
    let result : Result[Unit, LocalCommandPreparationIssue] = Err(issue)
    let message = try {
      command_preparation_result(result, stage=Some("cleanup"))
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(message, "LocalCommandPreparationUnavailable:cleanup:" + kind)
    assert_false(message.contains("PRIVATE_"))
  }
  local_command_diagnostic_reset()
}

///|
test "File entry Read refusal tags borrow the actual constructor without physical DATA" {
  let cases : Array[(@initial_arena.InstalledArenaOriginalReadIssue, String)] = [
    (Domain(Bootstrap(Physical(-847))), "Domain"),
    (Child(Unknown), "Child"),
    (Read(CleanupPending), "Read"),
    (Buffer(Capacity), "Buffer"),
  ]
  for (original, tag) in cases {
    local_command_diagnostic_reset()
    let refusal : Result[Unit, LocalCommandPreparationIssue] = Err(
      CommandRead(original),
    )
    let message = try {
      command_preparation_result(refusal, stage=Some("file-entry-read"))
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(
      message,
      "LocalCommandPreparationUnavailable:file-entry-read:read:" + tag,
    )
    assert_false(message.contains("847"))
    assert_eq(command_preparation_cleanup_kind(CommandRead(original)), "read")
    assert_eq(command_preparation_cleanup_cause(CommandRead(original)), tag)
  }
  guard cases[0].0 is Domain(Bootstrap(Physical(code))) else {
    fail("projection must not replace the same original typed cause")
  }
  assert_eq(code, -847)
  local_command_diagnostic_reset()
}
