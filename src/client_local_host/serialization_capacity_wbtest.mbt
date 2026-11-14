///|
fn content_workspace_fixture() -> ClientSerializationWorkspaceLimits {
  {
    generation_bytes: 7,
    generation_nodes: 2,
    generation_depth: 1,
    generation_frames: 3,
    identity_slots: 4,
    reference_bytes: 5,
    reference_nodes: 6,
    reference_depth: 2,
    contract_bytes: 8,
    contract_nodes: 9,
    contract_depth: 3,
    export_limits: {
      max_result_fields: 2,
      max_result_mapping_work: 20,
      max_result_order_work: 20,
      max_result_workspace_entries: 6,
      max_rows: 1,
      values: { max_nodes: 2, max_text_bytes: 7, max_depth: 1, max_work: 20, },
      payload_wire: {
        max_bytes: 11,
        max_nodes: 4,
        max_depth: 2,
        max_columns: 2,
        max_order_work: 20,
      },
      logical_wire: {
        max_bytes: 13,
        max_nodes: 7,
        max_depth: 3,
        max_columns: 2,
        max_order_work: 20,
      },
      schema: { max_fields: 2, max_bytes: 17, max_nodes: 5, max_depth: 4, },
      max_batch_bytes: 5,
    },
  }
}

///|
test "Content workspace reserves overlapping byte proof and cursor allowances independently" {
  let workspace = client_serialization_workspace_capacity(
    content_workspace_fixture(),
  ).unwrap()
  // Retained: 8192 roots + 65 text units * 8 + 66 evidence nodes * 256.
  assert_eq(@execution.execution_capacity_retained_bytes(workspace), 25608L)
  // Payload/logical export allowances include 64 control bytes each:
  // 1715 + 1781. Additional
  // identity/recheck/mapper/schema roots: 34 * 256; schema text: 17 * 8.
  assert_eq(@execution.execution_capacity_execution_bytes(workspace), 37944L)
  let combined = @execution.add_execution_capacity(
    @execution.execution_capacity(1L, 2L).unwrap(),
    workspace,
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(combined), 25609L)
  assert_eq(@execution.execution_capacity_execution_bytes(combined), 37946L)
  for limit in [37945L, 37946L] {
    let ledger = serialization_test_ledger(25609L, limit)
    match @resources.reserve_attempt(ledger, 0L, 25609L, 37946L) {
      Err(ExecutionLimit) => {
        assert_eq(limit, 37945L)
        assert_eq(@resources.ledger_usage(ledger).attempts, 0)
        assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
      }
      Ok(reservation) => {
        assert_eq(limit, 37946L)
        assert_eq(
          @resources.ledger_usage(ledger).reserved_execution_bytes,
          37946L,
        )
        @resources.settle_reservation(ledger, reservation).unwrap() |> ignore
        assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
      }
      _ => fail("unexpected reservation failure")
    }
  }
}

///|
test "Content workspace refuses invalid ceilings and capacity overflow" {
  let limits = content_workspace_fixture()
  assert_true(
    client_serialization_workspace_capacity({ ..limits, identity_slots: -1, })
    is None,
  )
  assert_true(
    client_serialization_workspace_capacity({ ..limits, generation_nodes: 0, })
    is None,
  )
  let workspace = client_serialization_workspace_capacity(limits).unwrap()
  let maximum = @execution.execution_capacity(0L, 9223372036854775807L).unwrap()
  assert_true(@execution.add_execution_capacity(maximum, workspace) is None)
}
