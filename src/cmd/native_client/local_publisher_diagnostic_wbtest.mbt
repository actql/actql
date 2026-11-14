///|
test "publisher diagnostic keeps original primary and return code without physical strings" {
  let issue : @local_host.NativeLocalPublisherBindingIssue = OriginalOperation(
    Some(Journal(Physical(BodyTooLarge))),
    StoreOperationSqlite(
      OperationRoutingAfter(Some(Physical("private SQL and key")), -17),
    ),
  )
  assert_eq(
    local_publisher_binding_issue_code(issue, 0),
    "OriginalOperation(Some(Journal(Physical(BodyTooLarge))),StoreOperationSqlite(OperationRoutingAfter(Some(Physical),-17)))",
  )
  assert_eq(
    local_publisher_sqlite_issue_code(
      OperationRoutingAfter(Some(Physical("private Account and Source")), -17),
      0,
    ),
    "OperationRoutingAfter(Some(Physical),-17)",
  )
}

///|
test "publisher diagnostic distinguishes same original Read resource and current refusal" {
  assert_eq(
    local_publisher_binding_issue_code(
      OriginalOperation(
        None,
        StoreOperationCapture(OriginalResourceScopePending),
      ),
      0,
    ),
    "OriginalOperation(None,StoreOperationCapture(OriginalResourceScopePending))",
  )
  assert_eq(
    local_publisher_adoption_issue_code(
      OriginalResources(Read(Read(Resource(ExecutionLimit)))),
      0,
    ),
    "OriginalResources(Read.Read(Resource(ExecutionLimit)))",
  )
  assert_eq(
    local_publisher_binding_issue_code(AuthorizationDenied, 0),
    "AuthorizationDenied",
  )
}

///|
test "publisher diagnostic recursion remains finite with both outer failure slots" {
  let mut issue : @local_host.NativeLocalPublisherBindingIssue = AuthorizationDenied
  for _ in 0..<16 {
    issue = OriginalOperation(
      Some(issue),
      StoreOperationSqlite(Physical("private body")),
    )
  }
  let code = local_publisher_binding_issue_code(issue, 0)
  assert_true(code.length() < 1024)
  assert_true(code.has_prefix("OriginalOperation(Some("))
  assert_true(code.has_suffix(",StoreOperationSqlite(Physical))"))
}
