///|
test "remote Transfer journal is explicit on unsupported targets" {
  let issue : NativeRemoteTransferJournalIssue = UnsupportedTarget
  assert_true(issue is UnsupportedTarget)
}
