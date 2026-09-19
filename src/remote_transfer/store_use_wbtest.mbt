///|
fn store_use_request() -> RemoteTransferRequest {
  prepare_request(
    "coordinator-a",
    "transfer-store-a",
    TransferStore,
    "source-a",
    1,
    "destination-b",
    2,
    "source-material-a",
    @manifest.admit(
      "actql-managed-physical-manifest/0.1",
      "sha256:" + "1".repeat(64),
      "sha256:" + "2".repeat(64),
      "sha256:" + "3".repeat(64),
      2,
      ["sha256:" + "a".repeat(64), "sha256:" + "b".repeat(64)],
      [5L, 7L],
      [1, 1],
      2,
      4096,
      12L,
    ).unwrap(),
    12L,
    2000000000000L,
    "sha256:" + "4".repeat(64),
    "sha256:" + "5".repeat(64),
    "sha256:" + "6".repeat(64),
  ).unwrap()
}

///|
fn commit_store_use(
  transition : RemoteTransferStoreUseTransition,
) -> RemoteTransferStoreUseRecord {
  commit_store_use_transition(transition, true).unwrap()
}

///|
test "Store download use requires receipt before completion" {
  let request = store_use_request()
  let store_use = prepare_store_use(request, "download-a").unwrap()
  let record = open_store_use(store_use)
  commit_store_use(prepare_store_use_start(record).unwrap()) |> ignore
  commit_store_use(prepare_store_use_progress(record, 1, 5L).unwrap()) |> ignore
  assert_true(
    prepare_store_use_complete(
      record,
      prepare_destination_receipt(request, "material-a").unwrap(),
    )
    is Err(_),
  )
  commit_store_use(prepare_store_use_progress(record, 2, 12L).unwrap())
  |> ignore
  let receipt = prepare_destination_receipt(request, "material-a").unwrap()
  commit_store_use(prepare_store_use_complete(record, receipt).unwrap())
  |> ignore
  assert_eq(store_use_record_projection(record), [
    "4",
    "2",
    "0",
    "2",
    "12",
    "1",
    destination_receipt_cid(receipt),
  ])
  commit_store_use(prepare_store_use_cleanup(record).unwrap()) |> ignore
  assert_eq(store_use_record_projection(record)[2], "1")
}

///|
test "Store use restore rejects released readers that never stopped" {
  let store_use = prepare_store_use(store_use_request(), "download-b").unwrap()
  assert_true(
    restore_store_use_record(store_use, 2, 1, 0, 1, 6L, false, "") is Err(_),
  )
  assert_true(
    restore_store_use_record(store_use, 2, 3, 1, 1, 5L, false, "") is Err(_),
  )
  let restored = restore_store_use_record(store_use, 2, 3, 1, 1, 5L, true, "").unwrap()
  assert_eq(store_use_record_projection(restored), [
    "2", "3", "1", "1", "5", "1", "",
  ])
}
