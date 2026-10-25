///|
test "preparation refusal is stable same-token data without a resource grant" {
  let ledger=@resources.create_ledger({planning_work:0,attempts:0,holdings:0,transfer_bytes:0L,retained_bytes:100L,execution_bytes:100L}).unwrap()
  let input=[1]
  let capacity : @resources.PreparationCapacity[Array[Int],Array[Int]]=@resources.reserve_preparation_capacity(ledger,input,20L,10L,max_borrowers=1).unwrap()
  let other=@resources.reserve_capacity(ledger,30L,40L).unwrap()
  let refused=reserve_closed_values_phase(capacity,input,SnapshotAndIntent,25L,61L)
  guard refused is Err(issue) else {fail("expected exact execution refusal")}
  assert_eq(closed_values_preparation_capacity_refusal(issue),Some(("snapshot_and_intent","execution",25L,61L,70L,60L)))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes,50L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes,50L)
  let retained=reserve_closed_values_phase(capacity,input,SourceParsing,71L,10L)
  guard retained is Err(issue) else {fail("expected exact retention refusal")}
  assert_eq(closed_values_preparation_capacity_refusal(issue),Some(("source_parsing","retention",71L,10L,70L,60L)))
  let foreign=reserve_closed_values_phase(capacity,[1],SnapshotAndIntent,25L,61L)
  assert_true(foreign is Err(Capacity(@resources.PreparationCapacityIssue::ForeignOriginal)))
  assert_true(@resources.preparation_capacity_available(capacity,[1]) is Err(@resources.PreparationCapacityIssue::ForeignOriginal))
  @resources.settle_capacity(ledger,other).unwrap()
  assert_eq(@resources.preparation_capacity_available(capacity,input),Ok((100L,100L)))
  reserve_closed_values_phase(capacity,input,SnapshotAndIntent,25L,61L).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes,25L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes,61L)
  assert_eq(@resources.abort_preparation_capacity_after_cleanup(capacity,input),Ok(true))
  assert_true(@resources.preparation_capacity_available(capacity,input) is Err(_))
}
