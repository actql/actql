///|
test "automatic standard recipe retains original body header secret and stored response constructor domains" {
  let native = @execution.execution_capacity(17L, 23L).unwrap()
  let wire : @source.ParseLimits = {
    max_input_bytes: 256,
    max_nodes: 16,
    max_depth: 4,
  }
  let original = Some([
    (native, Some(wire), Some(wire)),
    (native, Some(wire), Some(wire)),
    (native, Some(wire), Some(wire)),
    (native, Some(wire), Some(wire)),
  ])
  let selected = installed_standard_create_recipe_capacities(
    original, 512, 32, 8, 128, 64, 64, 32, true, 16, 7, 32, 1024, 64, 4, 40L,
  ).unwrap()
  assert_eq(selected.length(), 6)
  let write = prepare_installed_effect_operation_extent(
    "write",
    selected[3],
    193L,
    true,
  ).unwrap()
  assert_true(installed_effect_operation_response_backing_fits(write, 64, 32))
  let read = prepare_installed_effect_operation_extent(
    "read",
    selected[5],
    97L,
    true,
  ).unwrap()
  assert_true(installed_effect_operation_response_backing_fits(read, 32, 32))
  let fewer = installed_standard_create_recipe_capacities(
    original, 512, 32, 8, 128, 64, 64, 32, false, 16, 7, 32, 1024, 64, 4, 40L,
  ).unwrap()
  let grant = standard_create_grant_capacity().unwrap()
  // The fifth before-send read has one original grant/control occurrence,
  // not a refunded or aliased capture/apply/resume slot.
  assert_eq(
    @execution.execution_capacity_retained_bytes(selected[4]) -
    @execution.execution_capacity_retained_bytes(fewer[4]),
    @execution.execution_capacity_retained_bytes(grant),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected[4]) -
    @execution.execution_capacity_execution_bytes(fewer[4]),
    // The extra original Grant remains live, but its completed constructor
    // does not run simultaneously with one of the four preceding Grants.
    @execution.execution_capacity_retained_bytes(grant),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(selected[4]) >
    @execution.execution_capacity_retained_bytes(selected[2]),
  )
}

///|
test "metadata projector uses the control frame while its physical response backing stays unchanged" {
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let metadata = @execution.execution_capacity(17L, 10000017L).unwrap()
  let capacities = fn(projector) {
    installed_standard_create_recipe_capacities(
      Some([
        (empty, None, None),
        (empty, None, None),
        (empty, None, None),
        (projector, None, None),
      ]),
      512,
      32,
      8,
      128,
      64,
      64,
      32,
      false,
      16,
      7,
      32,
      1024,
      64,
      4,
      40L,
    ).unwrap()
  }
  let before = capacities(empty)
  let after = capacities(metadata)
  // HTTP receive, secret and request construction are the same original
  // physical child, irrespective of the pure projector's scratch geometry.
  assert_eq(
    @execution.execution_capacity_retained_bytes(before[5]),
    @execution.execution_capacity_retained_bytes(after[5]),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(before[5]),
    @execution.execution_capacity_execution_bytes(after[5]),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(after[4]) -
    @execution.execution_capacity_retained_bytes(before[4]),
    17L,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(after[4]) >= 10000017L,
  )
}

///|
test "automatic standard recipe preserves absent checks and refuses incomplete native or logical constructor bounds" {
  let native = @execution.execution_capacity(0L, 0L).unwrap()
  let wire : @source.ParseLimits = {
    max_input_bytes: 128,
    max_nodes: 8,
    max_depth: 3,
  }
  let original = Some([(native, None, Some(wire)), (native, None, Some(wire))])
  let plain = installed_standard_create_recipe_capacities(
    original, 256, 16, 4, 64, 32, 0, 0, false, 16, 7, 32, 256, 64, 4, 0L,
  ).unwrap()
  assert_eq(plain.length(), 5)
  for
    (check_request, check_response, before_send) in [
      (1, 0, false),
      (0, 1, false),
      (0, 0, true),
      (1, 1, false),
    ] {
    assert_true(
      installed_standard_create_recipe_capacities(
        original, 256, 16, 4, 64, 32, check_request, check_response, before_send,
        16, 7, 32, 256, 64, 4, 0L,
      )
      is Err(Unsupported),
    )
  }
  assert_true(
    installed_standard_create_recipe_capacities(
      original, 256, 16, 4, 64, 32, 0, 0, false, 16, 7, 0, 256, 64, 4, 0L,
    )
    is Err(Unsupported),
  )
  assert_true(
    installed_standard_create_recipe_capacities(
      original, 256, 16, 4, 64, 32, 0, 0, false, 16, 7, 32, 256, 64, 4, -1L,
    )
    is Err(Unsupported),
  )
}

///|
test "Effect response buffer backing composes pinned Array growth and retains failed receive window" {
  assert_true(installed_effect_response_buffer_construction_capacity(0) is None)
  assert_true(
    installed_effect_response_buffer_construction_capacity(-1) is None,
  )
  let small = installed_effect_response_buffer_representation(1).unwrap()
  let larger = installed_effect_response_buffer_representation(64).unwrap()
  // Independent receiver lifetimes: copied bytes + concat body + current
  // B+1 read. The failed receive cannot erase its already copied prefix.
  assert_eq(small.owned_wire_bytes, 1L + 1L + 2L)
  assert_eq(larger.owned_wire_bytes, 64L + 64L + 65L)
  assert_true(larger.record_headers > small.record_headers)
  assert_true(larger.reference_slots > small.reference_slots)
  assert_eq(larger.owned_utf16_units, 0L)
  // All arithmetic is logical Int64 quantity DATA, not an allocation of this
  // body or a claim that Node/Native can physically supply it.
  assert_true(
    installed_effect_response_buffer_construction_capacity(2147483647)
    is Some(_),
  )
}

///|
test "Effect response buffer backing checks exact original extent before an occurrence can use it" {
  let capacity = installed_effect_http_response_construction_capacity(64, 32).unwrap()
  let selected = prepare_installed_effect_operation_extent(
    "read", capacity, 65L, true,
  ).unwrap()
  assert_true(
    installed_effect_operation_response_backing_fits(selected, 64, 32),
  )
  assert_false(
    installed_effect_operation_response_backing_fits(selected, 65, 32),
  )
  assert_false(
    installed_effect_operation_response_backing_fits(selected, 64, 33),
  )
  assert_false(
    installed_effect_operation_response_backing_fits(selected, 0, 32),
  )
  assert_false(
    installed_effect_operation_response_backing_fits(selected, 64, 0),
  )
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let execution = @execution.execution_capacity_execution_bytes(capacity)
  let short = @execution.execution_capacity(retained - 1L, execution).unwrap()
  let short_extent = prepare_installed_effect_operation_extent(
    "read", short, 65L, true,
  ).unwrap()
  assert_false(
    installed_effect_operation_response_backing_fits(short_extent, 64, 32),
  )
  let pure = prepare_installed_effect_operation_extent(
    "read", capacity, 0L, false,
  ).unwrap()
  assert_false(installed_effect_operation_response_backing_fits(pure, 64, 32))
  // There is no borrow, binding, request, transfer debit or permission here.
  // Native capacity correspondence is a necessary component, not a full Plan.
}

///|
test "HTTP response inventory retains initial headers and trailers beside the original body" {
  let body = installed_effect_response_buffer_construction_capacity(64).unwrap()
  let original = prepare_installed_effect_operation_extent(
    "read", body, 65L, true,
  ).unwrap()
  // A funded body alone cannot fund either header block. This same original
  // check runs before any borrow; no physical ACK or allowance is inferred.
  assert_false(
    installed_effect_operation_response_backing_fits(original, 64, 1),
  )
  let fields = installed_effect_response_headers_representation(32).unwrap()
  assert_eq(fields.owned_utf16_units, 640L)
  assert_eq(fields.owned_wire_bytes, 128L)
  assert_true(fields.reference_slots > 2L * 32L)
  let full = installed_effect_http_response_construction_capacity(64, 32).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(full) >
    @execution.execution_capacity_retained_bytes(body),
  )
  assert_true(
    installed_effect_http_response_construction_capacity(64, 0) is None,
  )
  assert_true(
    installed_effect_http_response_construction_capacity(0, 32) is None,
  )
  // Int32 rejection bounds still fold to checked Int64 logical units. This
  // does not allocate the described representation or grant its capacity.
  assert_true(
    installed_effect_http_response_construction_capacity(2147483647, 2147483647)
    is Some(_),
  )
}

///|
// Constructor DATA only. A zero native fixed value can return a borrowed
// literal, but its Host JSON object still needs real constructed backing.
test "standard JSON constructor adapter rejects malformed and overflowing opaque profiles" {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  let output : @source.ParseLimits = {
    max_input_bytes: 1,
    max_nodes: 1,
    max_depth: 1,
  }
  let pair = [(zero, None, Some(output)), (zero, None, Some(output))]
  let capacities = installed_standard_create_constructor_capacities(Some(pair)).unwrap()
  assert_eq(capacities.length(), 2)
  assert_true(@execution.execution_capacity_retained_bytes(capacities[0]) > 0L)
  assert_true(
    installed_standard_create_constructor_capacities(Some([pair[0]]))
    is Err(Unsupported),
  )
  assert_true(
    installed_standard_create_constructor_capacities(
      Some([pair[0], pair[1], pair[0]]),
    )
    is Err(Unsupported),
  )
  let invalid : @source.ParseLimits = {
    max_input_bytes: 0,
    max_nodes: 1,
    max_depth: 1,
  }
  assert_true(
    installed_standard_create_constructor_capacities(
      Some([(zero, None, Some(invalid)), pair[1]]),
    )
    is Err(Unsupported),
  )
  assert_true(
    installed_standard_create_constructor_capacities(
      Some([(zero, Some(invalid), Some(output)), pair[1]]),
    )
    is Err(Unsupported),
  )
  let maximum = @execution.execution_capacity(
    9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  assert_true(
    installed_standard_create_constructor_capacities(
      Some([(maximum, None, Some(output)), pair[1]]),
    )
    is Err(Unsupported),
  )
}

///|
test "standard constructor absence preserves native capacity without invented JSON output" {
  let native = @execution.execution_capacity(17L, 23L).unwrap()
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ] = [(native, None, None), (empty, None, None)]
  let selected = installed_standard_create_constructor_capacities(
    Some(original),
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(selected[0]), 17L)
  assert_eq(@execution.execution_capacity_execution_bytes(selected[0]), 23L)
  assert_eq(@execution.execution_capacity_retained_bytes(selected[1]), 0L)
  assert_eq(@execution.execution_capacity_execution_bytes(selected[1]), 0L)
  let limits : @source.ParseLimits = {
    max_input_bytes: 64,
    max_nodes: 8,
    max_depth: 3,
  }
  // Input decoding remains an independent actual constructor even when its
  // native consumer returns Unit rather than a JSON String.
  let input = installed_standard_create_constructor_capacities(
    Some([(native, Some(limits), None), original[1]]),
  ).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(input[0]) > 17L)
  assert_true(@execution.execution_capacity_execution_bytes(input[0]) > 23L)
}

///|
test "Command recipe adds SAME native capture fixed and row quantities once without changing physical work" {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  let original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]? = Some([(zero, None, None), (zero, None, None)])
  let fixed = @execution.execution_capacity(17L, 23L).unwrap()
  let row = @execution.execution_capacity(31L, 37L).unwrap()
  let base = installed_standard_create_recipe_capacities(
    original, 256, 16, 4, 64, 32, 0, 0, false, 16, 7, 32, 256, 64, 4, 0L,
  ).unwrap()
  let selected = installed_standard_driver_recipe_capacities(
    original,
    Some([fixed, row]),
    256,
    16,
    4,
    256,
    16,
    4,
    64,
    32,
    0,
    0,
    false,
    16,
    7,
    32,
    256,
    64,
    4,
    0L,
  ).unwrap()
  for index in 0..<base.length() {
    let extra = if index == 0 { fixed } else if index == 1 { row } else { zero }
    assert_eq(
      @execution.execution_capacity_retained_bytes(selected[index]),
      @execution.execution_capacity_retained_bytes(base[index]) +
      @execution.execution_capacity_retained_bytes(extra),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(selected[index]),
      Int64::max(
        @execution.execution_capacity_execution_bytes(base[index]) +
        @execution.execution_capacity_retained_bytes(extra),
        @execution.execution_capacity_execution_bytes(extra) +
        @execution.execution_capacity_retained_bytes(base[index]),
      ),
    )
  }
  assert_eq(selected.length(), base.length() + 1)
  assert_eq(@execution.execution_capacity_execution_bytes(selected[5]), 0L)
  let with_name = installed_standard_driver_recipe_capacities(
    original,
    Some([fixed, row, fixed]),
    256,
    16,
    4,
    256,
    16,
    4,
    64,
    32,
    0,
    0,
    false,
    16,
    7,
    32,
    256,
    64,
    4,
    0L,
  ).unwrap()
  assert_true(physical_equal(with_name[5], fixed))
  for invalid in [None, Some([]), Some([fixed]), Some([fixed, row, fixed, row])] {
    assert_true(
      installed_standard_driver_recipe_capacities(
        original, invalid, 256, 16, 4, 256, 16, 4, 64, 32, 0, 0, false, 16, 7, 32,
        256, 64, 4, 0L,
      )
      is Err(Unsupported),
    )
  }
}

///|
test "driver row input follows its original body while fixed capture keeps the original Preview bound" {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  let original = Some([(zero, None, None), (zero, None, None)])
  let capture = Some([zero, zero])
  let small = installed_standard_driver_recipe_capacities(
    original, capture, 1024, 64, 8, 128, 8, 2, 64, 32, 0, 0, false, 16, 7, 32, 256,
    64, 4, 0L,
  ).unwrap()
  let large = installed_standard_driver_recipe_capacities(
    original, capture, 1024, 64, 8, 256, 16, 4, 64, 32, 0, 0, false, 16, 7, 32, 256,
    64, 4, 0L,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(small[0]),
    @execution.execution_capacity_retained_bytes(large[0]),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(small[0]),
    @execution.execution_capacity_execution_bytes(large[0]),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(small[1]) <
    @execution.execution_capacity_retained_bytes(large[1]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(small[1]) <
    @execution.execution_capacity_execution_bytes(large[1]),
  )
  for index in 2..<small.length() {
    assert_eq(
      @execution.execution_capacity_retained_bytes(small[index]),
      @execution.execution_capacity_retained_bytes(large[index]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(small[index]),
      @execution.execution_capacity_execution_bytes(large[index]),
    )
  }
  for (bytes, nodes, depth) in [(0, 8, 2), (128, 0, 2), (128, 8, 0)] {
    assert_true(
      installed_standard_driver_recipe_capacities(
        original, capture, 1024, 64, 8, bytes, nodes, depth, 64, 32, 0, 0, false,
        16, 7, 32, 256, 64, 4, 0L,
      )
      is Err(Unsupported),
    )
  }
}

///|
test "response input construction returns original NFC scratch while preserving input and output backing" {
  let provider = @execution.execution_capacity(17L, 23L).unwrap()
  for (bytes, nodes, depth) in [(256, 16, 4), (1000000, 64, 4)] {
    let actual = installed_json_effect_response_construction_capacity(
      provider, bytes, nodes, depth,
    ).unwrap()
    let original = installed_source_response_workspace(bytes, nodes, depth).unwrap()
    let scratch = @canonical.nfc_lf_construction_scratch_extent(bytes).unwrap()
    let old = @execution.preparation_execution_capacity({
      retained: original,
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    }).unwrap()
    let temporary = @execution.preparation_execution_capacity({
      retained: {
        record_headers: scratch.record_headers,
        reference_slots: scratch.reference_slots,
        scalar_words: scratch.scalar_words,
        owned_utf16_units: scratch.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    }).unwrap()
    // All old Source/index/normalized output and original provider backing
    // remain. Only the SAME Unicode Owner's returned-away scratch changes
    // lifetime, and the complete constructor/refusal peak stays exact.
    assert_eq(
      @execution.execution_capacity_execution_bytes(actual),
      @execution.execution_capacity_execution_bytes(provider) +
      @execution.execution_capacity_execution_bytes(old),
    )
    assert_eq(
      @execution.execution_capacity_retained_bytes(actual),
      @execution.execution_capacity_retained_bytes(provider) +
      @execution.execution_capacity_retained_bytes(old) -
      @execution.execution_capacity_retained_bytes(temporary),
    )
    assert_true(
      @execution.execution_capacity_retained_bytes(actual) >
      @execution.execution_capacity_retained_bytes(provider),
    )
    assert_true(
      @execution.execution_capacity_retained_bytes(actual) <
      @execution.execution_capacity_execution_bytes(actual),
    )
  }
}

///|
test "successful binary receiver retains only its returned body with the complete old receive peak" {
  for bytes in [1, 64, 65536, 2147483647] {
    let original = installed_effect_response_buffer_representation(bytes).unwrap()
    let body = installed_effect_response_buffer_construction_capacity(bytes).unwrap()
    let returned : @execution.PreparationRepresentationUnits = {
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: bytes.to_int64(),
    }
    assert_eq(
      @execution.execution_capacity_retained_bytes(body),
      @execution.preparation_representation_cost(returned).unwrap(),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(body),
      @execution.preparation_representation_cost(original).unwrap(),
    )
    assert_true(
      @execution.execution_capacity_retained_bytes(body) <
      @execution.execution_capacity_execution_bytes(body),
    )
    let headers = installed_effect_response_headers_representation(32).unwrap()
    let full = installed_effect_http_response_construction_capacity(bytes, 32).unwrap()
    let header_bytes = @execution.preparation_representation_cost(headers).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(full),
      2L * @execution.execution_capacity_retained_bytes(body) + header_bytes,
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(full),
      @execution.preparation_representation_cost(original).unwrap() +
      header_bytes,
    )
  }
}

///|
test "stored Ledger admission and original projector keep all outputs without summing returned synchronous scratch" {
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let selected = []
  for execution in [17L, 37L] {
    let projector = @execution.execution_capacity(7L, execution).unwrap()
    selected.push(
      installed_standard_create_recipe_capacities(
        Some([(empty, None, None), (projector, None, None)]),
        256,
        16,
        4,
        64,
        32,
        0,
        0,
        false,
        16,
        7,
        32,
        4096,
        64,
        4,
        0L,
      ).unwrap(),
    )
  }
  // The unchanged stored input owns more scratch than either small projector.
  // Their original callbacks are serial. Physical HTTP/secret backing stays
  // complete; the one Native projector belongs only to the control frame.
  // This counter issues no Run or permission.
  assert_eq(
    @execution.execution_capacity_retained_bytes(selected[1][4]),
    @execution.execution_capacity_retained_bytes(selected[0][4]),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected[1][4]) -
    @execution.execution_capacity_execution_bytes(selected[0][4]),
    0L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected[1][3]) -
    @execution.execution_capacity_execution_bytes(selected[0][3]),
    0L,
  )
}

///|
test "stored control includes retained Receipt outcomes beyond the smaller Ledger syntax" {
  let selected = standard_create_saved_control_capacity(1000000, 512, 16).unwrap()
  // The actual Host outcome bounds are512/16, independently of the logical
  // entry's64/4. Preserve the existing coarse retained and failed-prefix
  // envelopes, even for a data-key outcome with no Unicode normalization.
  let retained = @execution.execution_capacity_inventory(
    [
      { unit: ValueNodeSlots, count: 512L, copies: 4, },
      { unit: DecodedTextBytes, count: 1000000L, copies: 3, },
      { unit: QuotedBytes, count: 4096L, copies: 1, },
    ],
    [],
    RetainedAlongsideExecution,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(selected) >=
    @execution.execution_capacity_retained_bytes(retained),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(selected) >=
    @execution.execution_capacity_retained_bytes(retained) + 48000000L,
  )
  let entry_only = standard_create_saved_control_capacity(1000000, 64, 4).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(selected) >
    @execution.execution_capacity_retained_bytes(entry_only),
  )
  for
    (bytes, nodes, depth) in [(0, 512, 16), (1000000, 0, 16), (1000000, 512, 0)] {
    assert_true(
      standard_create_saved_control_capacity(bytes, nodes, depth) is None,
    )
  }
}

///|
test "saved contract control keeps its complete peak without retaining private decoder families per row" {
  let selected = standard_create_saved_control_capacity(1000000, 512, 16).unwrap()
  // Four returned Receipt families and the original logical Ledger still
  // coexist. A private million-byte decoder/index is not one returned family.
  let receipts = @execution.execution_capacity_inventory(
    [
      { unit: ValueNodeSlots, count: 512L, copies: 4, },
      { unit: DecodedTextBytes, count: 1000000L, copies: 3, },
      { unit: QuotedBytes, count: 4096L, copies: 1, },
    ],
    [],
    RetainedAlongsideExecution,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(selected),
    @execution.execution_capacity_retained_bytes(receipts),
  )
  let complete = installed_json_effect_response_construction_capacity(
    @execution.execution_capacity(0L, 0L).unwrap(),
    1000000,
    512,
    16,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(selected) >=
    @execution.execution_capacity_execution_bytes(complete),
  )
}

///|
test "stored control sequential scratch keeps retained and execution overflow closed" {
  let maximum = @execution.execution_capacity(
    9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  let byte = @execution.execution_capacity(1L, 1L).unwrap()
  assert_true(
    standard_create_sum_capacities([maximum, byte], sequential_workspace=true)
    is None,
  )
  let scratch = @execution.execution_capacity(0L, 1L).unwrap()
  assert_true(
    standard_create_sum_capacities(
      [maximum, scratch],
      sequential_workspace=true,
    )
    is None,
  )
}

///|
test "standard write projection belongs to its existing control frame rather than both reservations" {
  let profiles = [
    @execution.execution_capacity(2000L, 3000L).unwrap(),
    @execution.execution_capacity(1000000L, 9000000000L).unwrap(),
  ]
  let selections = profiles.map(response => {
    installed_standard_create_recipe_capacities(
      Some([
        (@execution.execution_capacity(100L, 200L).unwrap(), None, None),
        (response, None, None),
      ]),
      1024,
      64,
      8,
      2048,
      4096,
      0,
      0,
      false,
      17,
      7,
      32,
      1024,
      64,
      4,
      0L,
    ).unwrap()
  })
  // Synthetic opaque Native capacities establish only this constructor-fold
  // relation. No selected provider/Run, input, grant or allocation is issued.
  // Normal writes already call the SAME owned.project through the existing
  // controlConstruction frame after their physical response is captured.
  assert_eq(
    @execution.execution_capacity_retained_bytes(selections[0][3]),
    @execution.execution_capacity_retained_bytes(selections[1][3]),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(selections[0][3]),
    @execution.execution_capacity_execution_bytes(selections[1][3]),
  )
  // The real original Native bound is still fully on its pre-call control
  // reservation. This is relocation of one owner, never deletion of work.
  assert_true(
    @execution.execution_capacity_retained_bytes(selections[1][4]) >
    @execution.execution_capacity_retained_bytes(selections[0][4]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(selections[1][4]) >
    @execution.execution_capacity_execution_bytes(selections[0][4]),
  )
}

///|
test "observed response quantum bounds admitted copies without changing body or refusal bytes" {
  for
    (bytes, quantum, copies) in [
      (1, 16384, 1L),
      (16383, 16384, 1L),
      (16384, 16384, 1L),
      (16385, 16384, 2L),
      (32768, 16384, 2L),
      (32769, 16384, 3L),
      (2147483647, 16384, 131072L),
    ] {
    let old = installed_effect_response_buffer_representation(bytes).unwrap()
    let observed = installed_effect_response_buffer_representation(
      bytes,
      response_read_quantum=quantum,
    ).unwrap()
    let containers = @shape.collection_construction_extent({
      records: copies + 2L,
      record_references: 1L,
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: copies,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    }).unwrap()
    assert_eq(observed.record_headers, containers.record_headers)
    assert_eq(observed.reference_slots, containers.reference_slots)
    assert_eq(observed.owned_wire_bytes, 3L * bytes.to_int64() + 1L)
    let plain = installed_effect_response_buffer_construction_capacity(bytes).unwrap()
    let selected = installed_effect_response_buffer_construction_capacity(
      bytes,
      response_read_quantum=quantum,
    ).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(selected),
      @execution.execution_capacity_retained_bytes(plain),
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(selected) <=
      @execution.execution_capacity_execution_bytes(plain),
    )
    assert_eq(old.owned_wire_bytes, observed.owned_wire_bytes)
  }
  for invalid in [0, -1] {
    assert_true(
      installed_effect_response_buffer_construction_capacity(
        64,
        response_read_quantum=invalid,
      )
      is None,
    )
  }
  let capacity = installed_effect_http_response_construction_capacity(
    32769,
    32,
    response_read_quantum=16384,
  ).unwrap()
  let original = prepare_installed_effect_operation_extent(
    "read", capacity, 32770L, true,
  ).unwrap()
  assert_true(
    installed_effect_operation_response_backing_fits(
      original,
      32769,
      32,
      response_read_quantum=16384,
    ),
  )
  assert_false(
    installed_effect_operation_response_backing_fits(original, 32769, 32),
  )
}

///|
test "standard Host JSON output retains returned tree rather than parser construction controls" {
  let limits : @source.ParseLimits = {
    max_input_bytes: 4096,
    max_nodes: 128,
    max_depth: 8,
  }
  let original = @execution.execution_capacity(17L, 23L).unwrap()
  let peak = @source.json_literal_construction_extent(4096, 128, 8).unwrap()
  // The bare Host JSON result has no Source path/coordinate Span records.
  // Keep its conservative Value/Field/String tree, not another parser call.
  // All containers together fit N; this Owner uses their combined population.
  let returned = @source.json_tree_retained_construction_extent(
    128,
    127,
    128,
    0,
    4096L,
    keep_spans=false,
  ).unwrap()
  // Independent shared Array inventory: 383 Value/Field records, 128 growing
  // containers (384H/2045R/256W), and 255 original String headers, without
  // 255 Source Spans (255H/255R/1530W). Decoded text is still retained in full.
  assert_eq(
    (
      returned.record_headers,
      returned.reference_slots,
      returned.scalar_words,
      returned.owned_utf16_units,
    ),
    (1022L, 2810L, 512L, 4096L),
  )
  let price = (value : @source.JsonConstructionExtent) => {
    @execution.preparation_representation_cost({
      record_headers: value.record_headers,
      reference_slots: value.reference_slots,
      scalar_words: value.scalar_words,
      owned_utf16_units: value.owned_utf16_units,
      owned_wire_bytes: 0L,
    }).unwrap()
  }
  for native_peak in [23L, 9000000000L] {
    let native = @execution.execution_capacity(17L, native_peak).unwrap()
    let values = installed_standard_create_constructor_capacities(
      Some([(native, None, Some(limits)), (original, None, None)]),
    ).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(values[0]),
      17L + price(returned),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(values[0]),
      17L +
      price(returned) +
      Int64::max(native_peak - 17L, price(peak) - price(returned)),
    )
    assert_eq(@execution.execution_capacity_retained_bytes(values[1]), 17L)
    assert_eq(@execution.execution_capacity_execution_bytes(values[1]), 23L)
  }
}
