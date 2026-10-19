///|
test "public approve and reject require one exact checkpoint ID and no Run alias" {
  for operation in ["approve", "reject"] {
    let parsed = command().parse(argv=[operation, "checkpoint-original"])
    let (actual, child) = parsed.subcommand.unwrap()
    assert_eq(actual, operation)
    assert_eq(required(child, "checkpoint-id"), "checkpoint-original")
    assert_true(optional(child, "ref") is None)
    assert_true(local_product_operation(operation))
    for
      argv in [
        [operation],
        [operation, "one", "two"],
        [operation, "--run-id", "run-original"],
      ] {
      let refused = try {
        ignore(command().parse(argv~))
        false
      } catch {
        _ => true
      }
      assert_true(refused)
    }
    let named = command().parse(argv=[
      operation, "checkpoint-original", "--signer", "reviewer",
    ])
    assert_eq(optional(named.subcommand.unwrap().1, "signer"), Some("reviewer"))
  }
}

///|
test "public Checkpoint flags select only original inspection before resolution supply" {
  for operation in ["approve", "reject"] {
    let parsed = command().parse(argv=[
      "--mode", "local", operation, "checkpoint-original", "--signer", "reviewer",
      "--json",
    ])
    let child = parsed.subcommand.unwrap().1
    assert_true(child.flags.get("json").unwrap_or(false))
    assert_eq(optional(child, "signer"), Some("reviewer"))
    assert_true(local_checkpoint_action_selected(parsed, operation))
    assert_true(local_command_preparation_selected(parsed))
    assert_true(
      local_command_preparation_operation_selected(parsed, operation, false),
    )
    assert_false(
      local_command_preparation_operation_selected(parsed, "status", false),
    )
  }
  let waited = command().parse(argv=[
    "--mode", "local", "approve", "checkpoint-original", "--wait", "--json",
  ])
  assert_true(waited.subcommand.unwrap().1.flags.get("wait").unwrap_or(false))
  assert_true(local_checkpoint_action_selected(waited, "approve"))
  assert_false(local_checkpoint_action_selected(waited, "reject"))
  let refused = try {
    ignore(command().parse(argv=["reject", "checkpoint-original", "--wait"]))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}
