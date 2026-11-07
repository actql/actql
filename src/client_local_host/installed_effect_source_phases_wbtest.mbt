///|
fn effect_source_phase_fixture() -> (
  ClientInstalledCaptureCapacity,
  ClientInstalledCaptureCapacity,
) {
  let prepared = single_installed_prepared()
  let acquisition = original_row_acquisition_fixture(
    original_row_requirement(prepared),
  )
  let original = installed_row_capture_capacity(acquisition).unwrap()
  let provider = @execution.execution_capacity(7L, 1000L).unwrap()
  let complete = installed_provider_row_capture_capacity(
    acquisition,
    Some(provider),
  ).unwrap()
  (original, complete)
}

///|
test "binary sequential constructor fold retains both outputs and closes overflow without an input Array" {
  let left = @execution.execution_capacity(3L, 100L).unwrap()
  let right = @execution.execution_capacity(7L, 9L).unwrap()
  for pair in [(left, right), (right, left)] {
    let actual = standard_create_sequence_pair_capacity(pair.0, pair.1).unwrap()
    assert_eq(@execution.execution_capacity_retained_bytes(actual), 10L)
    assert_eq(@execution.execution_capacity_execution_bytes(actual), 107L)
  }
  let maximum = @execution.execution_capacity(
    9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  let byte = @execution.execution_capacity(1L, 1L).unwrap()
  let workspace = @execution.execution_capacity(0L, 9223372036854775807L).unwrap()
  assert_true(standard_create_sequence_pair_capacity(maximum, byte) is None)
  assert_true(standard_create_sequence_pair_capacity(workspace, byte) is None)
}

///|
test "provider execution phases retain acquisition scratch and tail beyond actual reader retirement" {
  let (original, capture) = effect_source_phase_fixture()
  let (reading, completed) = installed_effect_provider_execution_phases(
    [capture],
    [11L],
    19L,
    capture.retained_bytes + 17L,
  ).unwrap()
  assert_eq(reading, original.execution_bytes + 1000L + 11L + 17L)
  assert_eq(completed, original.execution_bytes + 7L + 11L + 19L)
  assert_true(completed > 19L)
  // A tail larger than the reader is not recoverable by subtracting reader
  // workspace from max(reader, tail). Keep its complete original envelope.
  let tail = reading * 2L
  let large_tail = installed_effect_provider_execution_phases(
    [capture],
    [11L],
    tail,
    capture.retained_bytes + 17L,
  ).unwrap()
  assert_eq(large_tail.0, reading)
  assert_eq(large_tail.1, original.execution_bytes + 7L + 11L + tail)
}

///|
test "provider execution phases count repeated originals and simultaneous earlier capture remainders" {
  let (original, capture) = effect_source_phase_fixture()
  let (reading, completed) = installed_effect_provider_execution_phases(
    [capture, capture],
    [11L, 13L],
    19L,
    2L * capture.retained_bytes + 17L,
  ).unwrap()
  let first_remaining = original.execution_bytes + 7L + 11L
  let second_remaining = original.execution_bytes + 7L + 13L
  assert_eq(
    reading,
    first_remaining + original.execution_bytes + 1000L + 13L + 17L,
  )
  assert_eq(completed, first_remaining + second_remaining + 19L)
}

///|
test "provider execution phases reject missing ordinary mismatched negative and overflow inventories" {
  let (ordinary, capture) = effect_source_phase_fixture()
  assert_true(
    installed_effect_provider_execution_phases([], [], 19L, 17L) is None,
  )
  assert_true(
    installed_effect_provider_execution_phases(
      [capture],
      [],
      19L,
      capture.retained_bytes + 17L,
    )
    is None,
  )
  assert_true(
    installed_effect_provider_execution_phases(
      [ordinary],
      [11L],
      19L,
      ordinary.retained_bytes + 17L,
    )
    is None,
  )
  assert_true(
    installed_effect_provider_execution_phases(
      [capture],
      [-1L],
      19L,
      capture.retained_bytes + 17L,
    )
    is None,
  )
  assert_true(
    installed_effect_provider_execution_phases(
      [capture],
      [11L],
      -1L,
      capture.retained_bytes + 17L,
    )
    is None,
  )
  assert_true(
    installed_effect_provider_execution_phases([capture], [11L], 19L, -1L)
    is None,
  )
  assert_true(
    installed_effect_provider_execution_phases(
      [capture],
      [11L],
      19L,
      capture.retained_bytes - 1L,
    )
    is None,
  )
  let (_, foreign) = effect_source_phase_fixture()
  let mismatched = { ..capture, acquisition: foreign.acquisition, }
  assert_true(
    installed_effect_provider_execution_phases(
      [mismatched],
      [11L],
      19L,
      capture.retained_bytes + 17L,
    )
    is None,
  )
  assert_true(
    installed_effect_provider_execution_phases(
      [capture],
      [11L],
      9223372036854775807L,
      capture.retained_bytes + 17L,
    )
    is None,
  )
  let excessive = { ..capture, execution_bytes: 9223372036854775807L, }
  assert_true(
    installed_effect_provider_execution_phases(
      [excessive],
      [1L],
      0L,
      capture.retained_bytes + 17L,
    )
    is None,
  )
}
