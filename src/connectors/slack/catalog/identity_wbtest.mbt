///|
test "Slack identity preserves the observed workspace and never infers it from display names" {
  let raw = @utf8.encode(
    "{\"ok\":true,\"team_id\":\"T-original\",\"user_id\":\"U-original\",\"team\":\"display\",\"bot_id\":\"B1\"}",
  )
  let identity = project_slack_workspace_identity(raw, 1024, 64, 8, 64).unwrap()
  assert_eq(identity.response_sha256, @sha.hex(raw))
  assert_eq(identity.user_id, "U-original")
  assert_true(slack_workspace_identity_matches(identity, "T-original"))
  assert_false(slack_workspace_identity_matches(identity, "display"))
  assert_false(slack_workspace_identity_matches(identity, "T-other"))
}

///|
test "Slack identity refuses errors absent or ambiguous original identity and malformed bytes" {
  for text in [
    "{}", "{\"ok\":false,\"team_id\":\"T1\",\"user_id\":\"U1\"}",
    "{\"ok\":true,\"team_id\":\"T1\"}",
    "{\"ok\":true,\"team_id\":null,\"user_id\":\"U1\"}",
    "{\"ok\":true,\"team_id\":\"\",\"user_id\":\"U1\"}",
    "{\"ok\":true,\"team_id\":\"T1\",\"user_id\":false}",
    "{\"ok\":true,\"team_id\":\"T1\",\"user_id\":\"U1\",\"error\":\"invalid_auth\"}",
    "{\"ok\":true,\"team_id\":\"T1\",\"team_id\":\"T2\",\"user_id\":\"U1\"}",
  ] {
    assert_true(project_slack_workspace_identity(@utf8.encode(text), 1024, 64, 8, 64) is Err(_))
  }
}

///|
test "Slack identity checks actual byte tree and original identity bounds without truncating" {
  let raw = @utf8.encode("{\"ok\":true,\"team_id\":\"T1\",\"user_id\":\"U1\"}")
  for bounds in [(1, 64, 8, 64), (1024, 1, 8, 64), (1024, 64, 8, 1)] {
    assert_true(project_slack_workspace_identity(raw, bounds.0, bounds.1, bounds.2, bounds.3) is Err(BudgetExceeded))
  }
}
