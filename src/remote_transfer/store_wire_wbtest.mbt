///|
test "Store upload replies preserve exact resume and sealed state" {
  let request = transfer_request(TransferStore)
  let admitted = remote_transfer_store_upload_reply_json(
    request,
    StoreUploadAdmissionReply,
    1,
    false,
  ).unwrap()
  let restored = admit_remote_transfer_store_upload_reply_json(
    admitted,
    request,
    StoreUploadAdmissionReply,
  ).unwrap()
  assert_eq(remote_transfer_store_upload_reply_projection(restored), [
    request_cid(request),
    "1",
    "0",
  ])
  let chunk = remote_transfer_store_upload_reply_json(
    request,
    StoreUploadChunkReply,
    2,
    false,
  ).unwrap()
  assert_eq(
    remote_transfer_store_upload_reply_projection(
      admit_remote_transfer_store_upload_reply_json(
        chunk,
        request,
        StoreUploadChunkReply,
      ).unwrap(),
    ),
    [request_cid(request), "2", "0"],
  )
  let committed = remote_transfer_store_upload_reply_json(
    request,
    StoreUploadCommitReply,
    2,
    true,
  ).unwrap()
  assert_eq(
    remote_transfer_store_upload_reply_projection(
      admit_remote_transfer_store_upload_reply_json(
        committed,
        request,
        StoreUploadCommitReply,
      ).unwrap(),
    ),
    [request_cid(request), "2", "1"],
  )
}

///|
test "Store upload replies reject route identity and shape changes" {
  let request = transfer_request(TransferStore)
  let body = remote_transfer_store_upload_reply_json(
    request,
    StoreUploadAdmissionReply,
    0,
    false,
  ).unwrap()
  assert_true(
    admit_remote_transfer_store_upload_reply_json(
      body + " ",
      request,
      StoreUploadAdmissionReply,
    )
    is Err(InvalidTransfer),
  )
  assert_true(
    admit_remote_transfer_store_upload_reply_json(
      body,
      transfer_request(DirectStream),
      StoreUploadAdmissionReply,
    )
    is Err(TransferIdentityMismatch),
  )
  assert_true(
    remote_transfer_store_upload_reply_json(
      request,
      StoreUploadCommitReply,
      1,
      true,
    )
    is Err(InvalidTransfer),
  )
}

///|
test "Store use replies bind the exact occurrence and completion" {
  let request = transfer_request(TransferStore)
  let admitted = remote_transfer_store_use_reply_json(
    request,
    "use-a",
    StoreUseAdmissionReply,
    false,
  ).unwrap()
  assert_eq(
    remote_transfer_store_use_reply_projection(
      admit_remote_transfer_store_use_reply_json(
        admitted,
        request,
        "use-a",
        StoreUseAdmissionReply,
      ).unwrap(),
    ),
    [request_cid(request), "use-a", "0"],
  )
  let completed = remote_transfer_store_use_reply_json(
    request,
    "use-a",
    StoreUseCompletionReply,
    true,
  ).unwrap()
  assert_eq(
    remote_transfer_store_use_reply_projection(
      admit_remote_transfer_store_use_reply_json(
        completed,
        request,
        "use-a",
        StoreUseCompletionReply,
      ).unwrap(),
    ),
    [request_cid(request), "use-a", "1"],
  )
  assert_true(
    admit_remote_transfer_store_use_reply_json(
      admitted,
      request,
      "use-b",
      StoreUseAdmissionReply,
    )
    is Err(TransferIdentityMismatch),
  )
}

///|
test "Store cancellation reply confirms the exact stopped occurrence" {
  let request = transfer_request(TransferStore)
  let body = remote_transfer_store_use_cancellation_reply_json(
    request, "cancel-a",
  ).unwrap()
  assert_eq(
    remote_transfer_store_use_cancellation_reply_projection(
      admit_remote_transfer_store_use_cancellation_reply_json(
        body, request, "cancel-a",
      ).unwrap(),
    ),
    [request_cid(request), "cancel-a"],
  )
  assert_true(
    admit_remote_transfer_store_use_cancellation_reply_json(
      body, request, "cancel-b",
    )
    is Err(TransferIdentityMismatch),
  )
}
