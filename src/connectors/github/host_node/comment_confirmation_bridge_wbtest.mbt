///|
test "Comment bridge retains original context and returns confirmation DATA only" {
  let tag = "sha256:" + String::make(64, 'a')
  let physical = "\n\n<!-- actql:effect:" + tag + " -->"
  let wire = @catalog.add_comment_request("I_1", physical).unwrap()
  let held = github_prepare_comment_confirmation("I_1", "", tag, wire,
    "R_1", 11.0, "owner/repo", 200, true, [], [],
    @utf8.encode("{\"data\":{\"addComment\":{\"commentEdge\":{\"node\":{\"id\":\"IC_7\",\"databaseId\":7}},\"subject\":{\"__typename\":\"Issue\",\"id\":\"I_1\"}}}}"),
    10000, 10000, 1000, 32).unwrap()
  let request = github_comment_confirmation_request_json(held)
  assert_true(request.contains("\"kind\":\"ConfirmationRequest\""))
  assert_true(request.contains("IC_7"))
  let repo : Json = { "__typename": "Repository", "id": "R_1", "databaseId": 11,
    "nameWithOwner": "owner/repo" }
  let body : Json = { "data": { "node": { "__typename": "IssueComment", "id": "IC_7",
    "fullDatabaseId": "7", "body": physical.to_json(), "repository": repo,
    "issue": { "__typename": "Issue", "id": "I_1", "repository": repo }, "pullRequest": Json::null() } } }
  assert_eq(github_project_comment_confirmation_json(held, 200, @utf8.encode(body.stringify())),
    "{\"id\":\"7\",\"kind\":\"Confirmed\",\"nodeId\":\"IC_7\"}")
  assert_eq(github_project_comment_confirmation_json(held, 404, b"{}"), "{\"kind\":\"Unknown\"}")
  assert_true(!request.contains("mutation"))
}
