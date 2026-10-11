///|
test "physical observation exposes only Owner attempt metadata and disposition" {
  let attempt_cid = "sha256:" + "a".repeat(64)
  for
    (event, expected, outcome) in [
      (BeforeInvoke, "before_invoke", "not_started"),
      (InvokeStarted, "started", "running"),
      (InvokeReturned, "returned", "confirmed"),
      (InvokeFailed, "failed", "failed"),
      (InvokeCancelled, "cancelled", "cancelled"),
    ] {
    let value : ModelPhysicalObservation = { slot: 3, attempt_cid, event, }
    assert_eq(
      model_physical_observation_facts(value),
      (3, attempt_cid, expected, outcome),
    )
  }
}
