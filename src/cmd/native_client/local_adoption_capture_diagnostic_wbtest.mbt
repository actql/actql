///|
test "Adoption capture failure discloses closed actual cause without payload or custody change" {
  let cases : Array[(@local_host.NativeLocalAdoptionCaptureIssue, String)] = [
    (
      AdoptionOriginal(Filesystem(RootOpen("PRIVATE_ROOT_MESSAGE"))),
      "AdoptionOriginal:Filesystem:RootOpen",
    ),
    (
      AdoptionOriginal(Filesystem(Cleanup("PRIVATE_CLEANUP_MESSAGE"))),
      "AdoptionOriginal:Filesystem:Cleanup",
    ),
    (
      AdoptionOriginal(Crypto(Verification("PRIVATE_KEY_MESSAGE"))),
      "AdoptionOriginal:Crypto:Verification",
    ),
    (AdoptionOriginal(CustodyLost), "AdoptionOriginal:CustodyLost"),
    (
      AdoptionOriginal(ConfigurationLimit),
      "AdoptionOriginal:ConfigurationLimit",
    ),
  ]
  for (original, cause) in cases {
    local_command_diagnostic_reset()
    let issue = CommandCapture(original)
    let result : Result[Unit, LocalCommandPreparationIssue] = Err(issue)
    let message = try {
      command_preparation_result(result, stage=Some("adoption-open"))
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(
      message,
      "LocalCommandPreparationUnavailable:adoption-open:adoption-capture:" +
      cause,
    )
    assert_false(message.contains("PRIVATE_"))
    assert_eq(command_preparation_cleanup_kind(issue), "adoption-capture")
    assert_eq(command_preparation_cleanup_cause(issue), "AdoptionOriginal")
  }
  local_command_diagnostic_reset()
}

///|
test "Adoption capture diagnostic retains unfinished capture states as distinct closed causes" {
  for
    (issue, expected) in [
      (@local_host.AdoptionNotOpened, "AdoptionNotOpened"),
      (AdoptionOpeningUnconfirmed, "AdoptionOpeningUnconfirmed"),
      (AdoptionCaptureClosed, "AdoptionCaptureClosed"),
      (AdoptionJournalAlreadyCaptured, "AdoptionJournalAlreadyCaptured"),
    ] {
    assert_eq(command_adoption_capture_cause(issue), expected)
    assert_eq(
      command_preparation_cleanup_kind(CommandCapture(issue)),
      "adoption-capture",
    )
  }
}
