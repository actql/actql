///|
// Actual readonly compiled layout and quantity/capacity admission only. No
// Root, Account, Reader, Run, physical cleanup or installed success is issued.
test "Query assets add their original initial Read quote after execution clipping" {
  let arithmetic = native_storage_finite_arithmetic_profile()
  let base = {
    ..arithmetic,
    read_domain_limits: {
      ..arithmetic.read_domain_limits,
      retained_bytes: 2097152L,
      execution_bytes: 4194304L,
    },
  }
  let (retained, execution) = local_command_query_assets_capacity(
    base.diagnostic_ceiling,
  ).unwrap()
  let layout = @local_filesystem.native_filesystem_read_layout().unwrap()
  // Independent shared-tariff vectors: controlsH4/R10/W1/U37 =226;
  // witness ArrayH3/R88/W2 =768; two text constructors131456/590208.
  assert_eq(
    retained,
    226L +
    768L +
    2L * 131456L +
    2L * layout.observation_payload_bytes +
    2L * layout.external_object_overhead_bytes,
  )
  assert_eq(
    execution,
    226L +
    768L +
    2472L +
    7536L +
    416L +
    1296L +
    2L * 590208L +
    236L +
    12L * base.diagnostic_ceiling.to_int64() +
    12L +
    2L * layout.observation_payload_bytes +
    2L * layout.reader_payload_bytes +
    4L * layout.external_object_overhead_bytes,
  )
  let budget = local_command_initial_read_budget(base).unwrap()
  assert_true(retained > 2L * 65536L * 2L)
  assert_true(execution > retained)
  assert_eq(budget.read_retained, base.read_budget.read_retained + retained)
  assert_eq(
    budget.read_execution,
    Int64::min(
      base.read_budget.read_execution,
      Int64::max(
        base.read_budget.bootstrap_execution,
        base.read_budget.workspace_execution,
      ),
    ) +
    execution,
  )
  assert_eq(budget.bootstrap_retained, base.read_budget.bootstrap_retained)
  assert_eq(budget.bootstrap_execution, base.read_budget.bootstrap_execution)
  assert_eq(budget.workspace_execution, base.read_budget.workspace_execution)
  let exact = {
    ..base,
    read_domain_limits: {
      ..base.read_domain_limits,
      retained_bytes: budget.bootstrap_retained + budget.read_retained,
      execution_bytes: budget.bootstrap_execution +
      budget.workspace_execution +
      budget.read_execution,
    },
  }
  let accepted = local_command_initial_read_budget(exact).unwrap()
  assert_eq(accepted.read_retained, budget.read_retained)
  assert_eq(accepted.read_execution, budget.read_execution)
  assert_true(
    local_command_initial_read_budget({
      ..exact,
      read_domain_limits: {
        ..exact.read_domain_limits,
        retained_bytes: exact.read_domain_limits.retained_bytes - 1L,
      },
    })
    is None,
  )
  assert_true(
    local_command_initial_read_budget({
      ..exact,
      read_domain_limits: {
        ..exact.read_domain_limits,
        execution_bytes: exact.read_domain_limits.execution_bytes - 1L,
      },
    })
    is None,
  )
}

///|
test "Query asset initial constructor rejects invalid and overflowing original quantities" {
  assert_true(local_command_query_assets_capacity(0) is None)
  let base = native_storage_finite_arithmetic_profile()
  assert_true(
    local_command_initial_read_budget({
      ..base,
      read_budget: { ..base.read_budget, read_retained: 9223372036854775807L, },
    })
    is None,
  )
}
