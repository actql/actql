///|
test "preparation phase work is original one-shot per phase and not dispatch or session quota" {
  let ledger=@resources.create_ledger({planning_work:7,attempts:0,holdings:0,transfer_bytes:0L,retained_bytes:100L,execution_bytes:100L}).unwrap()
  let input=[1]
  let owner : @resources.PreparationCapacity[Array[Int],Array[Int]]=@resources.reserve_preparation_capacity(ledger,input,40L,40L,max_borrowers=1).unwrap()
  assert_true(@resources.begin_preparation_phase_work(owner,[1],@resources.LexicalScan,5) is Err(@resources.PreparationWorkIssue::ForeignOriginal))
  let work=@resources.begin_preparation_phase_work(owner,input,@resources.LexicalScan,5).unwrap()
  @resources.spend_preparation_phase_work(work,5).unwrap()
  assert_true(@resources.spend_preparation_phase_work(work,1) is Err(@resources.PreparationWorkIssue::WorkLimit))
  assert_true(@resources.complete_preparation_capacity(owner,input,[2],20L,0L) is Err(@resources.PreparationCapacityIssue::WorkActive))
  assert_eq(@resources.finish_preparation_phase_work(work).unwrap(),5)
  assert_true(@resources.spend_preparation_phase_work(work,0) is Err(@resources.PreparationWorkIssue::Closed))
  assert_true(@resources.finish_preparation_phase_work(work) is Err(@resources.PreparationWorkIssue::Closed))
  assert_true(@resources.begin_preparation_phase_work(owner,input,@resources.LexicalScan,500) is Err(@resources.PreparationWorkIssue::AlreadyClaimed))
  let next=@resources.begin_preparation_phase_work(owner,input,@resources.SourceAndIndex,3).unwrap()
  assert_true(@resources.spend_preparation_phase_work(next,-1) is Err(@resources.PreparationWorkIssue::InvalidWork))
  @resources.spend_preparation_phase_work(next,2).unwrap()
  assert_eq(@resources.finish_preparation_phase_work(next).unwrap(),2)
  assert_eq(@resources.ledger_usage(ledger).planning_work,0)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes,40L)
  @resources.abort_preparation_capacity_after_cleanup(owner,input).unwrap() |> ignore
  // A later independent preparation is not limited by historical issuance.
  let again : @resources.PreparationCapacity[Array[Int],Array[Int]]=@resources.reserve_preparation_capacity(ledger,input,40L,40L,max_borrowers=1).unwrap()
  let fresh=@resources.begin_preparation_phase_work(again,input,@resources.LexicalScan,5).unwrap()
  @resources.spend_preparation_phase_work(fresh,5).unwrap()
  @resources.finish_preparation_phase_work(fresh).unwrap() |> ignore
  @resources.abort_preparation_capacity_after_cleanup(again,input).unwrap() |> ignore
}

///|
test "preparation Node scan uses one tariff and exact component capacity boundary" {
  // The funded ASCII eligibility state adds one owned Bool word.
  assert_eq(preparation_node_own_data_scan_cost(),Some(352L))
  assert_eq(preparation_node_own_data_header_cost(),Some(64L))
  assert_eq(preparation_node_own_data_scan_work(10,990),Some(63790))
  assert_eq(preparation_node_own_data_scan_work(100,99),Some(71836))
  assert_true(preparation_node_own_data_scan_work(2147483647,1) is None)
  for allowance in [351L,352L] {
    let ledger=@resources.create_ledger({planning_work:0,attempts:0,holdings:0,transfer_bytes:0L,retained_bytes:1L,execution_bytes:allowance}).unwrap()
    let owner : Result[@resources.PreparationCapacity[Array[Int],Array[Int]],@resources.PreparationCapacityIssue]=@resources.reserve_preparation_capacity(ledger,[1],1L,preparation_node_own_data_scan_cost().unwrap(),max_borrowers=1)
    if allowance==351L {
      assert_true(owner is Err(@resources.PreparationCapacityIssue::Resource(@resources.LedgerIssue::ExecutionLimit)))
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes,0L)
    } else {
      assert_true(owner is Ok(_))
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes,352L)
    }
  }
}
