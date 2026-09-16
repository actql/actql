///|
fn managed_retention_test_stream(
  owner : @lower.BoundPrepared,
) -> ManagedOutputValues {
  prepare_managed_output_values(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
}

///|
fn managed_retention_test_receipt(
  stream : ManagedOutputValues,
) -> ManagedOutputValueReceipt {
  for row in 0..<2 {
    let values = output_fixture_row(stream.owner, row)
    append_managed_output_values(stream, values.length(), column => {
      values.get(column)
    }).unwrap()
  }
  finish_managed_output_values(stream).unwrap()
}

///|
test "managed retention binds the exact admission stream rather than equal owner or rows" {
  let owner = capture_fixture()
  for foreign in [false, true] {
    let stream = managed_retention_test_stream(owner)
    let live = Ref(true)
    let port = prepare_managed_output_retention_port(stream, (
      receipt : ManagedOutputValueReceipt,
    ) => Some((receipt, "owned-generation", 19L, fn() { live.val }))).unwrap()
    let receipt = managed_retention_test_receipt(
      if foreign {
        managed_retention_test_stream(owner)
      } else {
        stream
      },
    )
    let result = retain_managed_output(port, receipt)
    if foreign {
      assert_true(result is Err(ForeignReceipt))
    } else {
      let material = result.unwrap()
      assert_true(managed_retained_output_matches(material, receipt))
      assert_eq(
        managed_retained_output_payload(material),
        Some("owned-generation"),
      )
      assert_eq(managed_retained_output_storage_bytes(material), Some(19L))
      let other = managed_retention_test_receipt(
        managed_retention_test_stream(owner),
      )
      assert_false(managed_retained_output_matches(material, other))
      live.val = false
      assert_false(managed_retained_output_matches(material, receipt))
      assert_true(managed_retained_output_payload(material) is None)
      assert_true(managed_retained_output_storage_bytes(material) is None)
    }
    assert_true(retain_managed_output(port, receipt) is Err(Closed))
  }
}

///|
test "managed retention rejects unavailable invalid unverified and cancelled issuance" {
  for mode in 0..<4 {
    let stream = managed_retention_test_stream(capture_fixture())
    let port = prepare_managed_output_retention_port(stream, (
      receipt : ManagedOutputValueReceipt,
    ) => {
      if mode == 0 {
        None
      } else {
        Some((receipt, 7, if mode == 1 { -1L } else { 7L }, fn() { mode != 2 }))
      }
    }).unwrap()
    let receipt = managed_retention_test_receipt(stream)
    if mode == 3 {
      assert_true(cancel_managed_output_retention_port(port))
      assert_false(cancel_managed_output_retention_port(port))
    }
    let result = retain_managed_output(port, receipt)
    match mode {
      0 => assert_true(result is Err(Unverified))
      1 => assert_true(result is Err(InvalidStorageBytes))
      2 => assert_true(result is Err(Unavailable))
      _ => assert_true(result is Err(Closed))
    }
    assert_true(retain_managed_output(port, receipt) is Err(Closed))
    assert_true(
      prepare_managed_output_retention_port(stream, (
        value : ManagedOutputValueReceipt,
      ) => Some((value, 7, 7L, fn() { true })))
      is Err(Closed),
    )
  }
}

///|
test "managed retention cannot revive cancellation during verifier or availability callback" {
  for during_available in [false, true] {
    let stream = managed_retention_test_stream(capture_fixture())
    let reentrant_rejected = Ref(false)
    let cancelled = Ref(false)
    let holder : Ref[
      ManagedOutputRetentionPort[ManagedOutputValueReceipt, Int]?,
    ] = Ref(None)
    let port = prepare_managed_output_retention_port(stream, (
      receipt : ManagedOutputValueReceipt,
    ) => {
      let port = holder.val.unwrap()
      reentrant_rejected.val = retain_managed_output(port, receipt)
        is Err(Closed)
      if !during_available {
        cancelled.val = cancel_managed_output_retention_port(port)
      }
      Some(
        (
          receipt,
          7,
          7L,
          fn() {
            if during_available {
              cancelled.val = cancel_managed_output_retention_port(port)
            }
            true
          },
        ),
      )
    }).unwrap()
    holder.val = Some(port)
    let receipt = managed_retention_test_receipt(stream)
    assert_true(retain_managed_output(port, receipt) is Err(Closed))
    assert_true(reentrant_rejected.val)
    assert_true(cancelled.val)
    holder.val = None
  }
}
