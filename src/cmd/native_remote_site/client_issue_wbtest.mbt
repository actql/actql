///|
test "checkpoint refusal preserves its Native client error code" {
  assert_eq(
    client_issue_code(@client.EffectCheckpointRefused("binding-mismatch")),
    "effect-checkpoint-binding-mismatch",
  )
  assert_eq(
    client_issue_code(
      @client.OutcomeUnknownPersistence(
        @journal.Closed,
        @client.EffectCheckpointRefused("binding-mismatch"),
      ),
    ),
    "outcome-unknown-effect-checkpoint-binding-mismatch",
  )
}
