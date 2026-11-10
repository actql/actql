///|
// The existing original Node Resource current port, with no physical I/O or
// installed SDK operation. The checked Source and Local Task owners remain
// those of managed_import_data_chain, including its original finite limits.
#warnings("-deprecated")
extern "js" fn managed_import_reentry_original(
  loader : PublicationTestLoader,
  prepared : @publication_host.PreparedClientProgram,
  quote : FixedArray[Int64],
  current : () -> Unit,
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,prepared,quote,current) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(prepared,{planningWork:Number(quote[0]),attempts:Number(quote[1]),holdings:Number(quote[2]),transferBytes:quote[3],retainedBytes:quote[4],executionBytes:quote[5]},current,()=>false)

///|
test "managed import grow current cannot reenter either original input copy" {
  let pending : Ref[(() -> Unit)?] = Ref(None)
  let original : Ref[
    @resources.NodeManagedRunAdmission[@publication_host.PreparedClientProgram]?,
  ] = Ref(None)
  let ledger : Ref[@resources.Ledger?] = Ref(None)
  let observed = Ref(false)
  let unchanged = Ref(false)
  let current_calls = Ref(0)
  let nested : Array[Result[Unit, @local_driver.LocalDispatchIssue]] = []
  managed_import_data_chain(
    Complete,
    ledger_factory=(prepared, limits) => {
      let quote = FixedArray::from_array([
        limits.planning_work.to_int64(),
        limits.attempts.to_int64(),
        limits.holdings.to_int64(),
        limits.transfer_bytes,
        limits.retained_bytes,
        limits.execution_bytes,
      ])
      let input = managed_import_reentry_original(
        publication_test_loader(publication_test_url()),
        prepared,
        quote,
        () => {
          if pending.val is Some(reenter) {
            current_calls.val += 1
            // First current charges the outer transfer. Second current is
            // reserve_import -> grow, AFTER next extent has been computed.
            if current_calls.val == 2 {
              pending.val = None
              reenter()
            }
          }
        },
      )
      let admission = @resources.prepare_node_managed_run_admission(
        input, prepared,
      ).unwrap()
      original.val = Some(admission)
      let value = @resources.start_node_managed_run_admission(admission).unwrap()
      ledger.val = Some(value)
      value
    },
    before_append=(task, input, row, wire, operations) => {
      if task == 2 && input == 0 && row == 0 {
        let owner = ledger.val.unwrap()
        let before = @resources.ledger_usage(owner)
        pending.val = Some(() => {
          let during = @resources.ledger_usage(owner)
          observed.val = during.transferred_bytes ==
            before.transferred_bytes + wire.length().to_int64() &&
            during.reserved_execution_bytes == before.reserved_execution_bytes
          // Equal wire is still two independent copies. A per-copy latch
          // cannot protect the shared import extent from the other input.
          nested.push((operations.inputs[0].append)(wire))
          nested.push((operations.inputs[1].append)(wire))
          unchanged.val = @resources.ledger_usage(owner) == during
        })
      }
    },
    append_observation=() => {
      nested.is_empty() ||
      (
        observed.val &&
        unchanged.val &&
        nested.length() == 2 &&
        nested[0] is Err(@local_driver.Configuration(InputUnavailable)) &&
        nested[1] is Err(@local_driver.Configuration(InputUnavailable))
      )
    },
  )
  assert_true(observed.val)
  assert_true(unchanged.val)
  assert_eq(current_calls.val, 2)
  assert_eq(nested.length(), 2)
  assert_true(pending.val is None)
  // The complete chain checks exact rows and zero live resources before the
  // same original imported admission is retired. This is no physical ACK.
  @resources.cleanup_node_managed_run_admission(original.val.unwrap()).unwrap()
}
