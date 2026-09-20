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
