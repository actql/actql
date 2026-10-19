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
