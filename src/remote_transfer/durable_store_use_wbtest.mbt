///|
test "durable Store use restores exact progress and identity" {
  let request = store_use_request()
  let store_use = prepare_store_use(request, "durable-download").unwrap()
  let record = open_store_use(store_use)
  commit_store_use(prepare_store_use_start(record).unwrap()) |> ignore
  commit_store_use(prepare_store_use_progress(record, 1, 5L).unwrap()) |> ignore
  let body = remote_transfer_store_use_record_durable_json(record).unwrap()
  let durable = admit_durable_remote_transfer_store_use_record(
    @utf8.encode(body),
    2,
    4096,
    12L,
  ).unwrap()
  assert_eq(durable_remote_transfer_store_use_revision(durable), 2)
  assert_eq(
    durable_remote_transfer_store_use_identity(durable),
    store_use_cid(store_use),
  )
  assert_eq(durable_remote_transfer_store_use_json(durable), body)
  assert_eq(
    store_use_record_projection(
      restore_durable_remote_transfer_store_use_record(durable).unwrap(),
    ),
    store_use_record_projection(record),
  )
}

///|
test "durable Store use rejects noncanonical and altered records" {
  let store_use = prepare_store_use(store_use_request(), "durable-reject").unwrap()
  let body = remote_transfer_store_use_record_durable_json(
    open_store_use(store_use),
  ).unwrap()
  assert_true(
    admit_durable_remote_transfer_store_use_record(
      @utf8.encode(body + " "),
      2,
      4096,
      12L,
    )
    is Err(InvalidTransfer),
  )
  assert_true(
    admit_durable_remote_transfer_store_use_record(
      @utf8.encode(body.replace(old="durable-reject", new="foreign-download")),
      2,
      4096,
      12L,
    )
    is Err(InvalidTransfer),
  )
}
