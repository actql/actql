///|
fn mean_resource_test_profile() -> MeanLimits {
  {
    max_samples: 3,
    max_exact_operations: 100000,
    max_coefficient_bits: 8192,
    max_temporary_bytes: 36400,
  }
}

///|
test "Mean reserves an independent finite coefficient and cursor envelope before input use" {
  let carrier = union_fold_test_carrier()
  let checked = mean_fold_test_checked(carrier)
  let profile = mean_resource_test_profile()
  // Maximum append width is three (one key plus two property values):
  // 32*100 + 8*100 + 4*100*3 + 2*3 + 160 = 5366.
  // Mean private roots add 2*3 + 100 + 16*100 + 8*100 + 64 = 2570.
  let slots = 5366 + 2570
  // 8192 coefficient bits plus one guard bit require 1025 bit-bytes.
  // Sixteen simultaneous units plus two 10000-byte value scratch quotas.
  let bytes = 16 * 1025 + 2 * 10000
  assert_eq(bytes, 36400)
  let limits = {
    ..union_fold_test_limits(),
    max_workspace_slots: slots,
    max_retained_value_bytes: bytes,
  }
  let exact = prepare_mean_reservation(checked, limits, profile).unwrap()
  assert_eq(mean_reserved_scratch_slots(exact), slots)
  assert_eq(mean_reserved_scratch_bytes(exact), bytes)
  assert_eq(mean_reserved_output_limits(exact).max_workspace_slots, 0)
  assert_eq(mean_reserved_output_limits(exact).max_retained_value_bytes, bytes)
  assert_true(
    prepare_mean_reservation(
      checked,
      { ..limits, max_workspace_slots: slots - 1, },
      profile,
    )
    is Err(MeanWorkspaceLimit),
  )
  assert_true(
    prepare_mean_reservation(checked, limits, {
      ..profile,
      max_temporary_bytes: bytes - 1,
    })
    is Err(MeanTemporaryLimit),
  )
  assert_true(
    prepare_mean_reservation(checked, limits, { ..profile, max_samples: 2, })
    is Err(MeanSampleLimit),
  )
  for bits in [0, 8193] {
    assert_true(
      prepare_mean_reservation(checked, limits, {
        ..profile,
        max_coefficient_bits: bits,
      })
      is Err(InvalidMeanLimits),
    )
  }
}

///|
test "Mean private reservation and output share one peak ceiling without input custody transfer" {
  let carrier = union_fold_test_carrier()
  let input = union_fold_test_input(carrier)
  let checked = mean_fold_test_checked(carrier)
  let reserved = prepare_mean_reservation(
    checked,
    union_fold_test_limits(),
    mean_resource_test_profile(),
  ).unwrap()
  let limits = mean_reserved_output_limits(reserved)
  let builder = @storage.prepare(
    @graph_type.mean_output(checked),
    DeclaredNodes,
    limits,
  ).unwrap()
  let fold = prepare_mean_fold(
    checked,
    [Accumulated(input), Accumulated(input), Accumulated(input)],
    builder,
    limits,
    limits.max_work,
    mean_reserved_arithmetic(reserved),
  ).unwrap()
  let (output, _) = mean_fold_test_finish(fold, 1)
  assert_eq(@storage.node_count(output), 2)
  assert_eq(@storage.edge_count(output), 2)
  assert_true(
    @storage.retained_workspace_slots(output) +
    mean_reserved_scratch_slots(reserved) <=
    union_fold_test_limits().max_workspace_slots,
  )
  assert_true(
    @storage.retained_value_bytes(output) +
    mean_reserved_scratch_bytes(reserved) <=
    union_fold_test_limits().max_retained_value_bytes +
    mean_resource_test_profile().max_temporary_bytes,
  )
  cleanup_mean_fold(fold)
  assert_true(@storage.available(input) && @storage.available(output))
  @storage.discard(output)
  @storage.discard(input)
}
