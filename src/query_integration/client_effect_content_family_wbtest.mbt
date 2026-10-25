///|
fn effect_content_workspace() -> @client_local_host.ClientSerializationWorkspaceLimits {
  {
    generation_bytes: 32,
    generation_nodes: 1000,
    generation_depth: 64,
    generation_frames: 100,
    identity_slots: 10000,
    reference_bytes: 16384,
    reference_nodes: 256,
    reference_depth: 32,
    contract_bytes: 100000,
    contract_nodes: 10000,
    contract_depth: 100,
    export_limits: {
      max_rows: 2,
      values: {
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 64,
        max_work: 100000,
      },
      payload_wire: {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 64,
        max_columns: 16,
        max_order_work: 10000,
      },
      logical_wire: {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 64,
        max_columns: 16,
        max_order_work: 10000,
      },
      schema: {
        max_fields: 16,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 64,
      },
      max_batch_bytes: 128,
      max_result_fields: 16,
      max_result_mapping_work: 10000,
      max_result_order_work: 10000,
      max_result_workspace_entries: 1000,
    },
  }
}

///|
test "Content family advances actual generation inside the original Relation chain and retains pending physical cleanup" {
  for preserve in [false, true] {
    let totals : Array[Int64] = []
    for quantum in [1, 7] {
      let prepared = effect_serialization_prefix_fixture(preserve~)
      let serialization_step = if preserve { 4 } else { 3 }
      let (registry, values, fragment, ordered) = acquired_serialization_contracts()
      let sequences = @client_local_host.prepare_client_effect_local_sequences(
        prepared, registry, values, fragment, ordered,
      ).unwrap()
      let dispatch = dispatch_test_limits()
      let selected : Array[@client_local_host.ClientLocalContentStep] = []
      let physically_stopped = Ref(true)
      let physical_clean = Ref(true)
      let cancelled = Ref(false)
      let closes = Ref(0)
      let enter_attempt : Ref[() -> Bool] = Ref(fn() { false })
      let family = @client_local_host.client_effect_content_local_provider(
        prepared,
        1,
        serialization_step,
        registry,
        values,
        fragment,
        ordered,
        dispatch.local_execution,
        dispatch.guards,
        effect_content_workspace(),
        {
          cancel: () => {
            cancelled.val = true
            true
          },
          stopped: () => physically_stopped.val,
          cleanup: () => {
            closes.val += 1
            Ok(physical_clean.val)
          },
        },
        active => {
          // The fixture owns the declared capacity lifecycle at this actual
          // original Content handoff, not at capability preparation.
          if !(enter_attempt.val)() {
            return false
          }
          selected.push(active)
          true
        },
      ).unwrap()
      assert_true(
        @local_connector.local_bounded_relation_provider(
          dispatch.local_execution,
          dispatch.guards,
          sequences[1],
        )
        is None,
      )
      let provider = @local_connector.local_bounded_relation_provider(
        dispatch.local_execution,
        dispatch.guards,
        sequences[1],
        family=[family],
      ).unwrap()
      let capacity = @local_connector.managed_provider_capacity(
        provider,
        sequences[1],
      ).unwrap()
      let retained = @execution.execution_capacity_retained_bytes(capacity)
      let executing = @execution.execution_capacity_execution_bytes(capacity)
      let inventory = @client_local_host.client_effect_family_ledger_limits(
        prepared,
        registry,
        values,
        fragment,
        ordered,
        dispatch.local_execution,
        dispatch.guards,
        [family],
      ).unwrap()
      assert_eq(inventory.attempts, 2)
      assert_eq(inventory.holdings, 2)
      assert_true(inventory.retained_bytes > retained)
      assert_true(inventory.execution_bytes >= executing)
      assert_eq(
        selected.length(),
        0,
        msg="capacity preparation must not enter Compute or allocate a Store",
      )
      assert_true(
        @client_local_host.client_effect_family_ledger_limits(
          prepared,
          registry,
          values,
          fragment,
          ordered,
          dispatch.local_execution,
          dispatch.guards,
          [],
        )
        is None,
      )
      let foreign = effect_serialization_prefix_fixture()
      assert_true(
        @client_local_host.client_effect_family_ledger_limits(
          foreign,
          registry,
          values,
          fragment,
          ordered,
          dispatch.local_execution,
          dispatch.guards,
          [family],
        )
        is None,
        msg="equal serialized Programs do not share their checked owner",
      )
      let short = @resources.create_ledger({
        planning_work: 0,
        attempts: 1,
        holdings: 0,
        transfer_bytes: 0L,
        retained_bytes: retained,
        execution_bytes: executing - 1L,
      }).unwrap()
      assert_true(
        @resources.reserve_attempt(short, 0L, retained, executing)
        is Err(ExecutionLimit),
      )
      assert_eq(selected.length(), 0)
      let ledger = @resources.create_ledger({
        planning_work: 0,
        attempts: 1,
        holdings: 0,
        transfer_bytes: 0L,
        retained_bytes: retained,
        execution_bytes: executing,
      }).unwrap()
      let reservation = @resources.reserve_attempt(
        ledger, 0L, retained, executing,
      ).unwrap()
      let source_provider = @local_connector.local_bounded_relation_provider(
        dispatch.local_execution,
        dispatch.guards,
        sequences[0],
      ).unwrap()
      let source = @local_connector.start_managed_provider_with_execution(
        source_provider,
        sequences[0],
        [],
        100,
        10000,
        dispatch.local_execution,
      ).unwrap()
      let original = effect_prefix_complete(source, quantum)
      let receiver = @execution.generated_sequence_owner(sequences[1])
      let binding = @execution.bind_completed_input(
        receiver,
        0,
        @execution.generated_sequence_owner(sequences[0]),
        original,
      ).unwrap()
      let read = @execution.prepare_producer_read(
        receiver, binding, 10000, 10000,
      ).unwrap()
      let barrier = @publication_host.prepare_client_effect_serialization(
        prepared,
        1,
        serialization_step,
        max_work=10000,
      ).unwrap()
      assert_true(
        @execution.serialization_completed_producer_input(barrier, read) is None,
        msg="the Stage input cannot substitute for the exact internal pre-SERIALIZE edge",
      )
      // Reserving capacity alone does not consume an attempt. Install the
      // fixture-owned debit only for the original provider's actual handoff.
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
      assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 1)
      enter_attempt.val = fn() {
        let usage = @resources.ledger_usage(ledger)
        if usage.attempts != 0 || usage.reserved_attempts != 1 {
          return false
        }
        @resources.consume_reserved_attempt(ledger, reservation) is Ok(_)
      }
      let active = @local_connector.start_managed_provider_with_execution(
        provider,
        sequences[1],
        [read],
        100,
        10000,
        dispatch.local_execution,
      ).unwrap()
      assert_eq(selected.length(), 0)
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
      assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 1)
      let bytes = StringBuilder()
      let mut sealing = false
      for _ in 0..<10000 {
        match
          @local_connector.advance_managed_provider(active, quantum).unwrap() {
          Continue(..) => ()
          Settling(0, ..) => {
            assert_eq(selected.length(), 1)
            let step = selected[0]
            let (revision, piece) = @client_local_host.client_local_content_pending_piece(
              step,
            ).unwrap()
            bytes.write_string(piece)
            assert_false(
              @client_local_host.acknowledge_client_local_content_piece(
                step,
                revision - 1,
              ),
            )
            assert_true(
              @client_local_host.acknowledge_client_local_content_piece(
                step, revision,
              ),
            )
            assert_false(
              @client_local_host.acknowledge_client_local_content_piece(
                step, revision,
              ),
            )
          }
          Settling(1, ..) => {
            sealing = true
            break
          }
          _ =>
            fail(
              "Content must not complete its original task without physical custody and issuance",
            )
        }
      }
      assert_true(sealing)
      assert_eq(selected.length(), 1)
      assert_eq(@resources.ledger_usage(ledger).attempts, 1)
      assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
      let expected = if preserve {
        "{\"value\":2}\n{\"value\":1}\n"
      } else {
        "{\"value\":1}\n{\"value\":2}\n"
      }
      assert_eq(bytes.to_string(), expected)
      let step = selected[0]
      let completed = @client_local_host.client_local_content_byte_completion(
        step,
      ).unwrap()
      assert_eq(completed.size_bytes, 24)
      assert_eq(completed.row_count, 2)
      assert_eq(completed.name, "out.jsonl")
      assert_eq(completed.media_type, "application/x-ndjson")
      assert_eq(
        completed.content_cid,
        "sha256:" + @sha.hex(@utf8.encode(expected)),
      )
      let (_, receipt, _) = @client_local_host.client_local_content_generation_input(
        step,
      ).unwrap()
      assert_eq(
        @execution.completed_relation_export_measurement(receipt).row_count,
        2,
      )
      assert_true(
        @client_local_host.client_local_content_step_generation(step) is None,
      )
      assert_true(@execution.producer_read_available(read))
      totals.push(
        @local_connector.managed_provider_cumulative_work(active).unwrap(),
      )
      assert_true(totals.last().unwrap() > 0L)
      assert_false(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        executing,
      )
      physically_stopped.val = false
      physical_clean.val = false
      assert_true(@local_connector.cancel_managed_provider(active))
      assert_true(cancelled.val)
      assert_true(
        @local_connector.advance_managed_provider(active, quantum).unwrap()
        is Waiting(..),
      )
      assert_false(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(closes.val, 0)
      assert_true(
        @client_local_host.client_local_content_generation_input(step) is None,
      )
      physically_stopped.val = true
      let mut stopped = false
      for _ in 0..<10000 {
        match
          @local_connector.advance_managed_provider(active, quantum).unwrap() {
          Stopped(..) => {
            stopped = true
            break
          }
          Continue(..) | Waiting(..) => ()
          _ => fail("Cancelled Content chain must not compute or publish again")
        }
      }
      assert_true(stopped)
      // The conservative chain first retires its original key guards. Each
      // one-column/two-row guard needs at most two map selections, two tuple
      // atoms, two tuple releases, one column, one partial tuple and its final
      // acknowledgement. Bound both guard sides for every entered prefix step.
      let guard_cleanup_polls = 2 *
        (serialization_step + 1) *
        (2 * 3 + 1 + 1 + 1)
      let cleanup_usage = @resources.ledger_usage(ledger)
      let cleanup_work = @local_connector.managed_provider_cumulative_work(
        active,
      ).unwrap()
      for _ in 0..<guard_cleanup_polls {
        assert_false(@local_connector.cleanup_managed_provider(active).unwrap())
        assert_eq(@resources.ledger_usage(ledger), cleanup_usage)
        assert_true(@execution.producer_read_available(read))
        assert_true(
          @client_local_host.client_local_content_generation_input(step) is None,
        )
        assert_eq(
          @local_connector.managed_provider_cumulative_work(active).unwrap(),
          cleanup_work,
        )
        if closes.val > 0 {
          break
        }
      }
      assert_eq(closes.val, 1)
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        executing,
      )
      physical_clean.val = true
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(closes.val, 2)
      @resources.settle_reservation(ledger, reservation).unwrap() |> ignore
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).attempts, 1)
      assert_true(@execution.producer_read_available(read))
      assert_true(@local_connector.cleanup_managed_provider(source).unwrap())
    }
    assert_eq(totals[0], totals[1])
  }
}
