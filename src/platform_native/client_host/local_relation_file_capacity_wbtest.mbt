///|
fn relation_work_capacity_inputs() -> (
  @row_file.NativeRelationFileSelection,
  @row_file.NativeRelationFileLimits,
) {
  (
    {
      directory: "/fixture",
      name: "records.json",
      resource: "records",
      items_path: ["items"],
      key_path: None,
      primary_identity: "id",
    },
    {
      page: { max_bytes: 8192, max_nodes: 512, max_depth: 8, max_rows: 2, },
      max_work: 1000000,
      chunk_bytes: 7,
      diagnostic_ceiling: 128,
    },
  )
}

///|
test "File entry Native raw endpoint covers actual constructors and snapshot growth" {
  let (header, width, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  assert_true(header > 0L && array_header > 0L && pointer > 0L)
  assert_eq(width, 2L)
  assert_eq(terminator, width)
  assert_true(native_relation_file_entries_read_raw_bytes(0) is None)
  assert_true(native_relation_file_entries_read_raw_bytes(-1) is None)
  let fixed = native_relation_file_entries_read_raw_bytes(1).unwrap()
  // Both implemented path bounds are16. The diagnostic has at most237
  // UTF16 units; its pinned builder doubles to256 plus the terminator.
  assert_true(fixed >= array_header + (12L + 3L * 16L) * pointer)
  assert_true(fixed >= header + 257L * width)
  // A large snapshot vector dominates fixed records. No vector or Source is
  // allocated by this arithmetic-only case and no Read capacity is granted.
  assert_eq(
    native_relation_file_entries_read_raw_bytes(100000).unwrap(),
    array_header + (12L + 3L * 100000L) * pointer,
  )
  assert_eq(native_relation_file_entry_raw_quote_control_bytes(), 176L)
}

///|
// Arithmetic only. These unfunded test Ledgers cannot enter the original Work
// route and do not establish installed Read/Account/Source execution evidence.
test "relation Work preflight requires Source and Compute simultaneous dimensions" {
  let limits : @resources.LedgerLimits = {
    planning_work: 5,
    attempts: 3,
    holdings: 2,
    transfer_bytes: 500L,
    retained_bytes: 700L,
    execution_bytes: 900L,
  }
  let ledger = @resources.create_ledger(limits).unwrap()
  let source : @resources.LedgerLimits = {
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 100L,
    retained_bytes: 200L,
    execution_bytes: 300L,
  }
  let compute : @resources.LedgerLimits = {
    planning_work: 4,
    attempts: 3,
    holdings: 2,
    transfer_bytes: 400L,
    retained_bytes: 500L,
    execution_bytes: 600L,
  }
  assert_true(relation_file_inventory_available(ledger, source, compute))
  for
    short in [
      { ..limits, planning_work: 4, },
      { ..limits, attempts: 2, },
      { ..limits, holdings: 1, },
      { ..limits, transfer_bytes: 499L, },
      { ..limits, retained_bytes: 699L, },
      { ..limits, execution_bytes: 899L, },
    ] {
    assert_false(
      relation_file_inventory_available(
        @resources.create_ledger(short).unwrap(),
        source,
        compute,
      ),
    )
  }
  let reserved = @resources.reserve_capacity(ledger, 1L, 1L).unwrap()
  assert_false(relation_file_inventory_available(ledger, source, compute))
  @resources.settle_capacity(ledger, reserved).unwrap()
  assert_true(relation_file_inventory_available(ledger, source, compute))
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
}

///|
test "relation Work preflight refuses quote overflow without reserving an attempt" {
  let limits : @resources.LedgerLimits = {
    planning_work: 1,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 1L,
    retained_bytes: 1L,
    execution_bytes: 1L,
  }
  let ledger = @resources.create_ledger(limits).unwrap()
  assert_false(
    relation_file_inventory_available(
      ledger,
      {
        ..limits,
        attempts: 1,
        holdings: 1,
        execution_bytes: 9223372036854775807L,
      },
      limits,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
}

///|
test "relation Work composes the Common captured control exactly once" {
  let native = relation_file_work_control_bytes().unwrap()
  let common = @local.captured_local_tasks_control_capacity().unwrap()
  let (selection, limits) = relation_work_capacity_inputs()
  let combined = native_relation_file_work_control_capacity(selection, limits).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(common), 128L)
  assert_eq(@execution.execution_capacity_execution_bytes(common), 128L)
  assert_eq(
    @execution.execution_capacity_retained_bytes(combined) - native - 23076038L,
    128L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(combined) - native - 23076038L,
    128L,
  )
}

///|
test "relation entry Read constructor component is distinct from the reserved business bytes" {
  let (selection, limits) = relation_work_capacity_inputs()
  let read = native_relation_file_entry_read_capacity(selection, limits).unwrap()
  // Independently authored H83/R86/S169 central-tariff vector. This is
  // constructor arithmetic, not a physical-entry or normal-profile proof.
  // The private dedicated capacity variant adds H1/R1 (24 bytes). The
  // clearable Prepared/compiler/definition tuple adds H2/R2/S1 (56 bytes).
  assert_eq(@execution.execution_capacity_retained_bytes(read), 29426L)
  assert_eq(@execution.execution_capacity_execution_bytes(read), 29426L)
  let pending_prepare = 61L * 16L + 73L * 8L + 110L * 8L
  let never_entered_cancel = 22L * 16L + 13L * 8L + 59L * 8L
  assert_eq(pending_prepare, 2440L)
  assert_eq(never_entered_cancel, 928L)
  assert_eq(
    @execution.execution_capacity_retained_bytes(read),
    pending_prepare +
    never_entered_cancel +
    288L +
    23832L +
    192L +
    552L +
    914L +
    280L,
  )
}

///|
test "relation entry authored minimum fixture and maximum constructor totals" {
  let (selection, limits) = relation_work_capacity_inputs()
  // One closed Single/Managed source tag: H1/R1/W1 on the existing field.
  let collection_tag = 16L + 8L + 8L
  // One additional borrowed Work reference in the refusal closure; no payload copy.
  let publication_failure_borrow = 8L
  assert_eq(
    relation_file_work_control_bytes().unwrap(),
    48234L + collection_tag + publication_failure_borrow,
  )
  let minimum = {
    ..limits,
    page: { max_bytes: 1, max_nodes: 1, max_depth: 1, max_rows: 1, },
  }
  let maximal = {
    ..limits,
    page: { max_bytes: 65536, max_nodes: 8192, max_depth: 32, max_rows: 100, },
  }
  let paths = {
    ..selection,
    items_path: Array::make(16, "items"),
    key_path: Some(Array::make(16, "key")),
  }
  for
    (selected, bounded, work_bytes, read_bytes) in [
      (selection, minimum, 270901L, 29426L),
      (selection, limits, 23124400L, 29426L),
      (paths, maximal, 296459152L, 32850L),
    ] {
    let work = native_relation_file_work_control_capacity(selected, bounded).unwrap()
    let read = native_relation_file_entry_read_capacity(selected, bounded).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(work),
      work_bytes + collection_tag + publication_failure_borrow,
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(work),
      work_bytes + collection_tag + publication_failure_borrow,
    )
    assert_eq(@execution.execution_capacity_retained_bytes(read), read_bytes)
    assert_eq(@execution.execution_capacity_execution_bytes(read), read_bytes)
  }
  let outer = native_relation_file_entry_outer_capacity().unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(outer), 2842L)
  assert_eq(@execution.execution_capacity_execution_bytes(outer), 2842L)
  // Work capacity is quantity DATA; the standalone Read retains admission.
  let quoted_bytes = { ..maximal, page: { ..maximal.page, max_bytes: 65537, }, }
  assert_false(
    @row_file.native_relation_file_input_valid(selection, quoted_bytes),
  )
  assert_true(
    native_relation_file_work_control_capacity(selection, quoted_bytes)
    is Some(_),
  )
  assert_true(
    native_relation_file_entry_read_capacity(selection, quoted_bytes) is None,
  )
  let excessive = { ..paths, items_path: Array::make(17, "items"), }
  assert_true(
    native_relation_file_work_control_capacity(excessive, maximal) is None,
  )
  assert_true(
    native_relation_file_entry_read_capacity(excessive, maximal) is None,
  )
}

///|
test "Whole file UTC constructor covers both original samples without allocator reuse" {
  let quoted = native_relation_whole_file_clock_capacity().unwrap()
  // Independent two-sample vector, including byte/UTF16 payloads and carriers.
  let one = 56L * 16L + 53L * 8L + 81L * 8L + 24L * 2L + 49L
  let carriers = 5L * 16L + 6L * 8L + 2L * 8L
  assert_eq(one, 2065L)
  assert_eq(carriers, 144L)
  assert_eq(
    @execution.execution_capacity_retained_bytes(quoted),
    2L * one + carriers,
  )
  assert_eq(@execution.execution_capacity_execution_bytes(quoted), 4274L)
}

///|
test "Whole prepared refusal diagnostic stays in the SAME Read constructor quote" {
  let (selection, _) = relation_work_capacity_inputs()
  let original = native_relation_file_entry_read_control_capacity(selection).unwrap()
  let diagnostic = native_relation_file_entry_read_control_capacity(
    selection,
    prepared_diagnostic=true,
  ).unwrap()
  // Three simultaneously live H1/R1/S1 envelopes at existing H16/R8/S8.
  assert_eq(
    @execution.execution_capacity_retained_bytes(diagnostic),
    @execution.execution_capacity_retained_bytes(original) + 96L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(diagnostic),
    @execution.execution_capacity_execution_bytes(original) + 96L,
  )
  // New-only caller frontier, independent of the original three failure
  // envelopes above. Business backing itself stays on its original owner.
  let preback = native_relation_whole_file_preback_read_capacity().unwrap()
  assert_eq(8L * 16L + 11L * 8L + 10L * 8L, 296L)
  assert_eq(@execution.execution_capacity_retained_bytes(preback), 296L)
  assert_eq(@execution.execution_capacity_execution_bytes(preback), 296L)
  // Exercise the actual composed Whole quote with original typed provider
  // and checked graph DATA. Neither constructor performs Source IO or admits
  // physical backing, an Account, a Run or execution permission.
  let (_, limits) = relation_work_capacity_inputs()
  let declaration = @rows.generate_row_declaration(
    "native-file-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        fields: [{ name: "id", value_type: "string", nullable: false, }],
      },
    ],
    {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
      max_views: 1,
      max_fields: 1,
    },
  ).unwrap()
  let provider = @row_file.prepare_native_relation_file_provider(
    declaration, selection, limits,
  ).unwrap()
  guard prepare_native_client_program(
      preparation_values_document(),
      Json,
      preparation_environment(),
      None,
      None,
      [],
      @host.client_standard_effect_computation_limits(),
    )
    is Ok(Computation(prepared)) else {
    fail("Whole quote: original finite graph unavailable")
  }
  let graph = @host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_captured_prefix(graph), 0)
  let work = native_relation_whole_file_work_control_capacity(
    selection, limits, provider, graph,
  ).unwrap()
  let whole_read = native_relation_whole_file_entry_read_capacity(
    selection, limits, provider, graph,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(whole_read),
    @execution.execution_capacity_retained_bytes(diagnostic) +
    @execution.execution_capacity_retained_bytes(work) +
    296L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(whole_read),
    @execution.execution_capacity_execution_bytes(diagnostic) +
    @execution.execution_capacity_execution_bytes(work) +
    296L,
  )
}
