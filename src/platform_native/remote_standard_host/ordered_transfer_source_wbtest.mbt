// Registered physical-provider diagnostics. Transfer bytes are fixed by the
// manifest; these fixtures do not claim Native I/O or public Cloud execution.

///|
fn ordered_transfer_source_input(
  chunks : Array[Bytes],
  rows : Array[Int],
  codec_cid? : String = @execution.ordered_rows_canonical_contract_cid(),
) -> NativeRemoteStandardTransferInput {
  let total = chunks.fold(init=0L, (sum, chunk) => {
    sum + chunk.length().to_int64()
  })
  let physical = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    standard_transfer_input_cid("1"),
    standard_transfer_input_cid("2"),
    codec_cid,
    rows.fold(init=0, (sum, row) => sum + row),
    chunks.map(chunk => "sha256:" + @sha.hex(chunk)),
    chunks.map(chunk => chunk.length().to_int64()),
    rows,
    10,
    4096,
    total,
  ).unwrap()
  let request = @transfer.prepare_request(
    "coordinator-a",
    "ordered-transfer",
    @transfer.TransferStore,
    "source-a",
    1,
    "destination-a",
    1,
    "ordered-material",
    physical,
    total,
    4102444800000L,
    standard_transfer_input_cid("4"),
    standard_transfer_input_cid("5"),
    standard_transfer_input_cid("6"),
  ).unwrap()
  let receipt = @transfer.prepare_destination_receipt(
    request,
    standard_transfer_input_cid("7"),
  ).unwrap()
  prepare_native_remote_standard_transfer_input(
    request,
    "ordered-use",
    @transfer.destination_receipt_cid(receipt),
    262144,
  ).unwrap()
}

///|
fn ordered_transfer_source_capture(
  chunks : Array[Bytes],
  rows : Array[Int],
  cleanup_ready : Ref[Bool],
  releases : Ref[Int],
  codec_cid? : String = @execution.ordered_rows_canonical_contract_cid(),
) -> Result[
  NativeRemoteStandardTransferSource,
  NativeRemoteStandardInputFailure,
] {
  let input = ordered_transfer_source_input(chunks, rows, codec_cid~)
  let physical = register_native_remote_standard_physical_source(
    input,
    () => true,
    (max_bytes, emit) => {
      for index, chunk in chunks {
        let mut offset = 0
        while offset < chunk.length() {
          let count = Int::min(max_bytes, chunk.length() - offset)
          match
            emit(
              index,
              Bytes::from_array(Array::makei(count, i => chunk[offset + i])),
            ) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
          offset += count
        }
      }
      Ok(())
    },
    () => {
      releases.val += 1
      cleanup_ready.val
    },
  )
  let codec = register_native_remote_standard_row_codec(
    standard_transfer_input_cid("1"),
    standard_transfer_input_cid("2"),
    codec_cid,
  ).unwrap()
  let (prepared, _, _, _) = retained_transfer_run()
  let (sequence, program) = retained_source_sequence(prepared)
  acquire_native_remote_standard_physical_source(
    input,
    physical,
    codec,
    sequence,
    program,
    retained_source_limits(),
  )
}

///|
test "ordered export Transfer admits exact fragmented first middle and last chunks" {
  let releases = Ref(0)
  let source = ordered_transfer_source_capture(
    [b"[{\"id\":3}", b",{\"id\":1}", b",{\"id\":2}]"],
    [1, 1, 1],
    Ref(true),
    releases,
  ).unwrap()
  let captured = native_remote_standard_transfer_captured_source(source)
  assert_eq(@query.captured_source_row_count(captured), Some(3))
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 100,
    max_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
  }
  let output = @query.prepare_captured_source_relation_export(
    captured,
    10,
    retained_source_limits().values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
    1000,
  ).unwrap()
  let text = Ref("")
  while true {
    match @execution.next_completed_output_export(output) {
      Ok(Some(row)) => text.val += row
      Ok(None) => break
      Err(_) => abort("ordered export failed")
    }
  }
  let (receipt, tail) = @execution.finish_completed_output_export(output).unwrap()
  text.val += tail
  assert_eq(text.val, "[{\"id\":3},{\"id\":1},{\"id\":2}]")
  @execution.cancel_completed_export_receipt(receipt)
  assert_true(finish_native_remote_standard_transfer_source(source))
  assert_true(finish_native_remote_standard_transfer_source(source))
  assert_eq(releases.val, 1)
}

///|
test "ordered export Transfer requires the exact empty array chunk" {
  let source = ordered_transfer_source_capture([b"[]"], [0], Ref(true), Ref(0)).unwrap()
  assert_eq(
    @query.captured_source_row_count(
      native_remote_standard_transfer_captured_source(source),
    ),
    Some(0),
  )
  assert_true(finish_native_remote_standard_transfer_source(source))
  for (chunks, rows) in [([], []), ([b"{}"], [0]), ([b"[ ]"], [0])] {
    let failure = ordered_transfer_source_capture(
      chunks,
      rows,
      Ref(true),
      Ref(0),
    ).unwrap_err()
    assert_true(retry_native_remote_standard_input_failure_cleanup(failure))
  }
}

///|
test "ordered export Transfer rejects missing separators and tails without a codec fallback" {
  for
    chunks in [
      [b"{\"id\":3}"],
      [b"[{\"id\":3}"],
      [b"[{\"id\":3}}"],
      [b"[{\"id\":3}", b"[{\"id\":1}]"],
      [b"[{\"id\":3}]", b",{\"id\":1}]"],
      [b"[{\"id\":3},{\"id\":1}]"],
    ] {
    let ready = Ref(false)
    let releases = Ref(0)
    let failure = ordered_transfer_source_capture(
      chunks,
      Array::make(chunks.length(), 1),
      ready,
      releases,
    ).unwrap_err()
    assert_false(retry_native_remote_standard_input_failure_cleanup(failure))
    assert_true(native_remote_standard_input_failure_cleanup_pending(failure))
    ready.val = true
    assert_true(retry_native_remote_standard_input_failure_cleanup(failure))
    assert_true(retry_native_remote_standard_input_failure_cleanup(failure))
    assert_eq(releases.val, 2)
  }
  let failure = ordered_transfer_source_capture(
    [b"[{\"id\":3}]"],
    [1],
    Ref(true),
    Ref(0),
    codec_cid=standard_transfer_input_cid("8"),
  ).unwrap_err()
  assert_true(retry_native_remote_standard_input_failure_cleanup(failure))
}

///|
test "ordered export Transfer keeps physical frame limits and partial cleanup ownership" {
  let input = ordered_transfer_source_input([b"[{\"id\":3}]"], [1])
  let ready = Ref(false)
  let releases = Ref(0)
  let pin = () => {
    register_native_remote_standard_physical_source(
      input,
      () => true,
      (_, _) => Err("incremental-only"),
      () => {
        releases.val += 1
        ready.val
      },
    )
  }
  let codec = register_native_remote_standard_row_codec(
    standard_transfer_input_cid("1"),
    standard_transfer_input_cid("2"),
    @execution.ordered_rows_canonical_contract_cid(),
  ).unwrap()
  let (prepared, _, _, _) = retained_transfer_run()
  let (sequence, program) = retained_source_sequence(prepared)
  let limits = retained_source_limits()
  let failure = prepare_native_remote_standard_physical_admission(
    input,
    pin(),
    codec,
    sequence,
    program,
    { ..limits, wire: { ..limits.wire, max_bytes: 8, }, },
  ).unwrap_err()
  assert_false(retry_native_remote_standard_input_failure_cleanup(failure))
  let admission = prepare_native_remote_standard_physical_admission(
    input,
    pin(),
    codec,
    sequence,
    program,
    limits,
  ).unwrap()
  assert_true(
    feed_native_remote_standard_physical_admission(admission, 0, b"[{\"i")
    is Err(InvalidProfile),
  )
  feed_native_remote_standard_physical_admission(admission, 0, b"[{").unwrap()
  let partial = cancel_native_remote_standard_physical_admission(admission)
  assert_false(retry_native_remote_standard_input_failure_cleanup(partial))
  ready.val = true
  assert_true(retry_native_remote_standard_input_failure_cleanup(failure))
  assert_true(retry_native_remote_standard_input_failure_cleanup(partial))
  assert_true(retry_native_remote_standard_input_failure_cleanup(partial))
  assert_eq(releases.val, 4)
}
