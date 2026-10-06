///|
test "Cancel delivery retirement has a dedicated typed truth table" {
  // Independent expectations, including combinations rejected by admission.
  let nonterminal : Array[RemoteExecutionState] = [
    Accepted,
    Provisioning,
    Running,
    ExecutionUnknown,
  ]
  for execution in nonterminal {
    assert_false(
      cancellation_delivery_can_retire(execution, CleanupReleased, false, false),
    )
  }
  let terminal : Array[RemoteExecutionState] = [
    NativeSettled,
    ExecutionFailed,
    ExecutionCancelled,
  ]
  for execution in terminal {
    assert_true(
      cancellation_delivery_can_retire(execution, CleanupReleased, false, false),
    )
    assert_false(
      cancellation_delivery_can_retire(execution, CleanupReleased, true, false),
    )
    assert_false(
      cancellation_delivery_can_retire(execution, CleanupReleased, false, true),
    )
    let pending : Array[RemoteCleanupState] = [
      CleanupActive,
      CleanupReleasing,
      CleanupUnknown,
      CleanupForceLost,
      CleanupRecoveredAfterLoss,
    ]
    for cleanup in pending {
      assert_false(
        cancellation_delivery_can_retire(execution, cleanup, false, false),
      )
    }
  }
}
