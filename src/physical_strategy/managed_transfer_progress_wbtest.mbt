///|
test "transfer commit order is fixed by common progress" {
  assert_eq(
    managed_transfer_commit_step(
      false, false, false, false, false, false, false, false, false,
    ).unwrap(),
    TransferAwaitSourceStop,
  )
  assert_eq(
    managed_transfer_commit_step(
      false, false, false, true, false, true, false, false, false,
    ).unwrap(),
    TransferSettleSourceSite,
  )
  assert_eq(
    managed_transfer_commit_step(
      false, false, false, true, true, true, false, false, false,
    ).unwrap(),
    TransferSettleRun,
  )
  assert_true(
    managed_transfer_commit_step(
      false, false, false, true, true, false, false, false, false,
    )
    is Err(NotReady),
  )
  assert_eq(
    managed_transfer_commit_step(
      true, false, false, true, true, true, false, false, false,
    ).unwrap(),
    TransferRetainDestinationSite,
  )
  assert_eq(
    managed_transfer_commit_step(
      true, false, false, true, true, true, true, false, false,
    ).unwrap(),
    TransferSettleDestinationSite,
  )
  assert_eq(
    managed_transfer_commit_step(
      true, false, false, true, true, true, true, true, false,
    ).unwrap(),
    TransferReleaseDestinationCleanup,
  )
  assert_eq(
    managed_transfer_commit_step(
      true, false, false, true, true, true, true, true, true,
    ).unwrap(),
    TransferCompleteRun,
  )
  assert_eq(
    managed_transfer_commit_step(
      true, true, false, true, true, true, true, true, true,
    ).unwrap(),
    TransferFinished,
  )
  assert_true(
    managed_transfer_commit_step(
      true, false, true, true, true, true, true, true, true,
    )
    is Err(NotReady),
  )
}

///|
test "transfer cleanup separates source stop and destination reclaim" {
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, true, false, false, false, false, false, false, true,
    ).unwrap(),
    TransferMarkCleanupPending,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, true, true, false, false, true, false, false, true,
    ).unwrap(),
    TransferSettleDestinationSite,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, true, true, false, false, true, true, false, true,
    ).unwrap(),
    TransferReleaseDestinationCleanup,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, true, true, false, false, true, true, true, true,
    ).unwrap(),
    TransferAwaitSourceStop,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, true, true, true, false, false, false, false, true,
    ).unwrap(),
    TransferSettleSourceSite,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, true, true, true, true, false, false, false, true,
    ).unwrap(),
    TransferReclaimDestination,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, true, true, true, true, true, false, false, true,
    ).unwrap(),
    TransferSettleDestinationSite,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, true, true, true, true, true, true, false, true,
    ).unwrap(),
    TransferReleaseDestinationCleanup,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, true, true, true, true, true, true, true, true,
    ).unwrap(),
    TransferAbortRun,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      false, false, false, false, true, true, true, true, true, true,
    ).unwrap(),
    TransferFinished,
  )
}

///|
test "successful transfer release keeps both holdings independent" {
  assert_eq(
    managed_transfer_cleanup_step(
      true, false, false, false, true, true, false, true, true, false,
    ).unwrap(),
    TransferReclaimDestination,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      true, false, false, false, true, true, true, true, true, false,
    ).unwrap(),
    TransferReleaseRun,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      true, true, false, false, true, true, true, true, true, false,
    ).unwrap(),
    TransferReleaseSiteHolding,
  )
  assert_eq(
    managed_transfer_cleanup_step(
      true, true, false, false, true, true, true, true, true, true,
    ).unwrap(),
    TransferFinished,
  )
}

///|
test "transfer destination admission owns common bounds and independence" {
  let valid : ManagedTransferDestinationFacts = {
    distinct_material: true,
    distinct_generation: true,
    rows: 2,
    batches: 1,
    max_batch_rows: 128,
    max_batch_bytes: 4096,
    transferred_bytes: 16L,
    retained_bytes: 32L,
  }
  assert_true(managed_transfer_destination_admitted(valid, 16L, 32L))
  assert_false(
    managed_transfer_destination_admitted(
      { ..valid, distinct_material: false, },
      16L,
      32L,
    ),
  )
  assert_false(
    managed_transfer_destination_admitted(
      { ..valid, distinct_generation: false, },
      16L,
      32L,
    ),
  )
  assert_false(
    managed_transfer_destination_admitted(
      { ..valid, transferred_bytes: 17L, },
      16L,
      32L,
    ),
  )
  assert_false(
    managed_transfer_destination_admitted(
      { ..valid, retained_bytes: 33L, },
      16L,
      32L,
    ),
  )
  assert_false(
    managed_transfer_destination_admitted(
      { ..valid, max_batch_rows: 0, },
      16L,
      32L,
    ),
  )
}
