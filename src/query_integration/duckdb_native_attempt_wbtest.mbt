///|
fn native_candidate_fixture(
  ceiling? : Int = 100,
  rows? : Int = 2,
) -> (
  @connector.CapabilityRegistry,
  @planning.QueryRequirement,
  @planning.DuckDBQueryPreparation,
) raise {
  let checked = query_checked_program_fixture()
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(
      query_checked_sequence(checked),
      query_material_limits(),
    ).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: rows, max_value_bytes: ceiling, },
    query_material_limits(),
  ).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "duckdb", acquisition: true, fixed_compute: true, }],
    1,
    6,
  ).unwrap()
  (
    registry,
    requirement,
    @planning.prepare_duckdb_query(
      requirement,
      "main",
      "records",
      10,
      native_compile_limits(),
    ).unwrap(),
  )
}

///|
fn native_selected_attempt(
  rows? : Int = 2,
) -> @planning.DuckDBNativeAttempt raise {
  let (registry, requirement, prepared) = native_candidate_fixture(rows~)
  let candidate = @planning.duckdb_native_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    prepared,
    [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        milliseconds: Some(10L),
      },
    ],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("fixture selection")
  }
  @planning.prepare_duckdb_native_attempt(
    choice,
    candidate,
    { max_rows: 5, max_cells: 5, max_nodes: 5, max_text_bytes: 0, },
    100,
    native_demand_physical(),
  ).unwrap()
}

///|
fn native_attempt_receive_fixture(
  attempt : @planning.DuckDBNativeAttempt,
) -> Unit {
  @planning.admit_duckdb_native_metadata(
    attempt,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  for
    (role, rows, cells) in [
      (
        @duckdb.ValidationScan,
        3,
        "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
      ),
      (@duckdb.NativeResult, 2, "[\"4008000000000000\",\"4000000000000000\"]"),
    ] {
    let port = @planning.begin_duckdb_native_receipt(attempt, role, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    @planning.accept_duckdb_native_chunk(attempt, port, rows, [
      input_cursor(cells),
    ]).unwrap()
    @planning.finish_duckdb_native_receipt(attempt, port).unwrap()
  }
}

///|
fn native_attempt_wire() -> @execution.RowWireLimits {
  {
    max_columns: 1,
    max_order_work: 100,
    max_bytes: 47,
    max_nodes: 12,
    max_depth: 10,
  }
}

///|
test "native selected attempt keeps common output guard and exact receipt owner" {
  let limited = native_selected_attempt(rows=1)
  @planning.admit_duckdb_native_metadata(
    limited,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  let scan = @planning.begin_duckdb_native_receipt(
    limited,
    @duckdb.ValidationScan,
    [("id", @duckdb.Float64)],
  ).unwrap()
  assert_true(
    @planning.accept_duckdb_native_chunk(limited, scan, 3, [
      input_cursor(
        "[\"4008000000000000\",\"3ff0000000000\",\"4000000000000000\"]",
      ),
    ])
    is Err(Receiving(Values(_))),
  )
  // A malformed physical scalar is terminal, including on a row filtered out.
  assert_true(
    @planning.finish_duckdb_native_receipt(limited, scan) is Err(InvalidState),
  )
  let limited = native_selected_attempt(rows=1)
  @planning.admit_duckdb_native_metadata(
    limited,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  let scan = @planning.begin_duckdb_native_receipt(
    limited,
    @duckdb.ValidationScan,
    [("id", @duckdb.Float64)],
  ).unwrap()
  @planning.accept_duckdb_native_chunk(limited, scan, 3, [
    input_cursor(
      "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
    ),
  ]).unwrap()
  @planning.finish_duckdb_native_receipt(limited, scan).unwrap()
  let output = @planning.begin_duckdb_native_receipt(
    limited,
    @duckdb.NativeResult,
    [("id", @duckdb.Float64)],
  ).unwrap()
  @planning.accept_duckdb_native_chunk(limited, output, 2, [
    input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
  ]).unwrap()
  assert_true(
    @planning.finish_duckdb_native_receipt(limited, output)
    is Err(Receiving(Guard(NativeResult, _, _, _))),
  )
  assert_true(
    @planning.settle_duckdb_native_transport(limited) is Err(InvalidState),
  )
  let first = native_selected_attempt()
  let second = native_selected_attempt()
  for attempt in [first, second] {
    @planning.admit_duckdb_native_metadata(
      attempt,
      1,
      [("table_type", @duckdb.Varchar)],
      [input_cursor("[\"BASE TABLE\"]")],
    ).unwrap()
  }
  let port = @planning.begin_duckdb_native_receipt(
    first,
    @duckdb.ValidationScan,
    [("id", @duckdb.Float64)],
  ).unwrap()
  assert_true(
    @planning.accept_duckdb_native_chunk(second, port, 0, [input_cursor("[]")])
    is Err(Receiving(ForeignReceipt)),
  )
  @planning.accept_duckdb_native_chunk(first, port, 0, [input_cursor("[]")]).unwrap()
  @planning.finish_duckdb_native_receipt(first, port).unwrap()
  assert_true(
    @planning.begin_duckdb_native_receipt(second, @duckdb.ValidationScan, [
      ("id", @duckdb.Float64),
    ])
    is Err(InvalidState),
  )
}

///|
test "native and broad candidates share comparison without dropping either receipt cost" {
  let (registry, requirement, prepared) = native_candidate_fixture()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let quantities : @connector.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let native = @planning.duckdb_native_candidate(
    registration,
    prepared,
    [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        milliseconds: Some(10L),
      },
    ],
    quantities,
    100,
  ).unwrap()
  let broad = @planning.duckdb_broad_candidate(
    registration,
    prepared,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(20L), }],
    quantities,
    100,
  ).unwrap()
  for
    candidates in [
      [
        @planning.prepared_acquisition_candidate(native),
        @planning.prepared_acquisition_candidate(broad),
      ],
      [
        @planning.prepared_acquisition_candidate(broad),
        @planning.prepared_acquisition_candidate(native),
      ],
    ] {
    guard @planning.choose_acquisition_candidate(
        registry,
        requirement,
        candidates,
        None,
        100,
      ).unwrap()
      is Proposed(choice) else {
      abort("expected native")
    }
    assert_true(@planning.acquisition_choice_payload(choice, native) is Some(_))
    assert_true(@planning.acquisition_choice_payload(choice, broad) is None)
    let other = @planning.duckdb_native_candidate(
      registration,
      prepared,
      [
        {
          work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          milliseconds: Some(10L),
        },
      ],
      quantities,
      100,
    ).unwrap()
    assert_true(
      @planning.prepare_duckdb_native_attempt(
        choice,
        other,
        { max_rows: 5, max_cells: 5, max_nodes: 5, max_text_bytes: 0, },
        100,
        native_demand_physical(),
      )
      is Err(ForeignChoice),
    )
  }
  for omitted in [2, 5, 9] {
    let slots = []
    for i in 0..<11 {
      if i != omitted {
        slots.push(i)
      }
    }
    let unknown = @planning.duckdb_native_candidate(
      registration,
      prepared,
      [{ work_slots: slots, milliseconds: Some(1L), }],
      quantities,
      100,
    ).unwrap()
    assert_true(
      @planning.choose_acquisition_candidate(
        registry,
        requirement,
        [
          @planning.prepared_acquisition_candidate(unknown),
          @planning.prepared_acquisition_candidate(broad),
        ],
        None,
        100,
      )
      is Ok(Deferred),
    )
  }
  assert_true(
    @planning.duckdb_native_candidate(
      registration,
      prepared,
      [
        {
          work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          milliseconds: Some(10L),
        },
        { work_slots: [2], milliseconds: Some(1L), },
      ],
      quantities,
      100,
    )
    is Err(Planning(Cost(DuplicateSlot(2)))),
  )
  let (tiny_registry, _, tiny) = native_candidate_fixture(ceiling=4)
  assert_true(
    @planning.duckdb_native_candidate(
      @connector.capability_registration_at(tiny_registry, 0).unwrap(),
      tiny,
      [],
      quantities,
      100,
    )
    is Err(Unsupported(RootGuard(UnsupportedCeiling))),
  )
  assert_true(@planning.duckdb_native_work_at(2) is Some(ValidationTransfer))
  assert_true(@planning.duckdb_native_work_at(5) is Some(NativeTransfer))
  assert_true(@planning.duckdb_native_work_at(11) is None)
}

///|
test "selected native attempt measures exact receipts only after settlement and cancellation is terminal" {
  let attempt = native_selected_attempt()
  native_attempt_receive_fixture(attempt)
  @planning.settle_duckdb_native_transport(attempt).unwrap()
  let measured = @planning.measure_duckdb_native_attempt(
    attempt,
    native_demand_physical(),
    native_attempt_wire(),
    5,
    47,
  ).unwrap()
  assert_true(@planning.duckdb_native_measurement_matches(measured, attempt))
  let demand = @planning.duckdb_native_measured_demand(measured)
  assert_eq(
    (demand.rows, demand.true_rows, demand.false_rows, demand.null_rows),
    (3, 2, 1, 0),
  )
  let (_, scan_bytes, scan_nodes, scan_rows) = @planning.duckdb_native_measured_receipt(
    measured,
    @duckdb.ValidationScan,
  )
  let (_, output_bytes, output_nodes, output_rows) = @planning.duckdb_native_measured_receipt(
    measured,
    @duckdb.NativeResult,
  )
  assert_eq((scan_bytes, scan_nodes, scan_rows), (28, 7, 3))
  assert_eq((output_bytes, output_nodes, output_rows), (19, 5, 2))
  assert_false(
    @planning.duckdb_native_measurement_matches(
      measured,
      native_selected_attempt(),
    ),
  )
  @planning.abort_duckdb_native_attempt(attempt)
  assert_false(@planning.duckdb_native_measurement_matches(measured, attempt))
  assert_true(
    @planning.settle_duckdb_native_transport(attempt) is Err(InvalidState),
  )
  for received in [false, true] {
    let early = native_selected_attempt()
    if received {
      native_attempt_receive_fixture(early)
    }
    assert_true(
      @planning.measure_duckdb_native_attempt(
        early,
        native_demand_physical(),
        native_attempt_wire(),
        5,
        47,
      )
      is Err(InvalidState),
    )
    assert_true(
      @planning.settle_duckdb_native_transport(early) is Err(InvalidState),
    )
  }
}

///|
test "native attempt measurement exhaustion cannot be retried as a successful attempt" {
  for
    (nodes, bytes, received_rows, received_bytes) in [
      (7, 47, 5, 47),
      (11, 47, 5, 47),
      (12, 46, 5, 47),
      (12, 47, 4, 47),
      (12, 47, 5, 46),
    ] {
    let attempt = native_selected_attempt()
    native_attempt_receive_fixture(attempt)
    @planning.settle_duckdb_native_transport(attempt).unwrap()
    let wire = { ..native_attempt_wire(), max_nodes: nodes, max_bytes: bytes, }
    assert_true(
      @planning.measure_duckdb_native_attempt(
        attempt,
        native_demand_physical(),
        wire,
        received_rows,
        received_bytes,
      )
      is Err(Receipts(_)),
    )
    assert_true(
      @planning.measure_duckdb_native_attempt(
        attempt,
        native_demand_physical(),
        native_attempt_wire(),
        5,
        47,
      )
      is Err(InvalidState),
    )
  }
  let attempt = native_selected_attempt()
  native_attempt_receive_fixture(attempt)
  @planning.settle_duckdb_native_transport(attempt).unwrap()
  assert_true(
    @planning.measure_duckdb_native_attempt(
      attempt,
      { ..native_demand_physical(), max_work: 3, },
      native_attempt_wire(),
      5,
      47,
    )
    is Err(Demand(Operand(2, false, _))),
  )
}
