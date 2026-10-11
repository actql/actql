///|
test "Effect observation classifies only the existing recovery Owner's actions" {
  for
    action in [
      @effect.PersistPrepared,
      ClaimPrepared,
      ReturnApplied,
      ReturnAccepted,
      ReturnFailed,
    ] {
    assert_eq(
      native_effect_unknowns_for_action(
        "original-effect",
        @effect.effect_row_action_code(action),
      ).unwrap(),
      [],
    )
  }
  for action in [@effect.ReconcilePossibleDispatch, ReconcileUnknown] {
    assert_eq(
      native_effect_unknowns_for_action(
        "original-effect",
        @effect.effect_row_action_code(action),
      ).unwrap(),
      ["original-effect"],
    )
  }
  for action in [@effect.JoinActive, RequestConflict, InvalidRecord] {
    assert_true(
      native_effect_unknowns_for_action(
        "original-effect",
        @effect.effect_row_action_code(action),
      )
      is Err(ForeignRequest),
    )
  }
}
