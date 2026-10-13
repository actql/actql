///|
// Parser/caller definitions remain compiler-only until matching Native runs.
test "explicit policy upgrade and lookup retain user operation identity" {
  for operation in ["upgrade-policy", "lookup-policy-upgrade"] {
    assert_true(local_product_operation(operation))
    let parsed = command().parse(argv=[
      "--mode", "local", operation, "--operation-id", "original-upgrade", "--json",
    ])
    let child = parsed.subcommand.unwrap().1
    assert_eq(required(child, "operation-id"), "original-upgrade")
    assert_true(optional(parsed, "config-file") is None)
    assert_true(child.flags.get("json").unwrap())
  }
}

///|
test "unknown policy append keeps original identity without retry permission" {
  let issues : Array[@local_host.NativeClientRunJournalIssue] = [
    TransactionUnknown,
    Fenced,
  ]
  for issue in issues {
    let message = try {
      let value : Result[Unit, @local_host.NativeClientRunJournalIssue] = Err(
        issue,
      )
      local_policy_upgrade_result("original-upgrade", value)
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_true(message.has_prefix("LocalPolicyUpgradeUnknown"))
    assert_true(message.contains("original-upgrade"))
    assert_true(message.contains("lookup-policy-upgrade"))
  }
}
