///|
pub(all) enum RemoteTransferStoreUploadReplyKind {
  StoreUploadAdmissionReply
  StoreUploadChunkReply
  StoreUploadCommitReply
} derive(Eq, Debug)

///|
struct RemoteTransferStoreUploadReply {
  request_cid : String
  next_chunk : Int
  is_sealed : Bool
}

///|
priv suberror RemoteTransferStoreWireStop {
  RemoteTransferStoreWireStop
}

///|
fn[T] store_wire_decoded(
  value : Result[T, @decode.Issue],
) -> T raise RemoteTransferStoreWireStop {
  match value {
    Ok(result) => result
    Err(_) => raise RemoteTransferStoreWireStop
  }
}

///|
fn valid_store_upload_reply(
  request : RemoteTransferRequest,
  kind : RemoteTransferStoreUploadReplyKind,
  next_chunk : Int,
  is_sealed : Bool,
) -> Bool {
  let count = request.physical.chunks.length()
  request.route == TransferStore &&
  valid_request_fields(request) &&
  next_chunk >= 0 &&
  next_chunk <= count &&
  (match kind {
    StoreUploadAdmissionReply => !is_sealed || next_chunk == count
    StoreUploadChunkReply => !is_sealed && next_chunk > 0
    StoreUploadCommitReply => is_sealed && next_chunk == count
  })
}

///|
pub fn remote_transfer_store_upload_reply_json(
  request : RemoteTransferRequest,
  kind : RemoteTransferStoreUploadReplyKind,
  next_chunk : Int,
  is_sealed : Bool,
) -> Result[String, RemoteTransferIssue] {
  if !valid_store_upload_reply(request, kind, next_chunk, is_sealed) {
    return Err(InvalidTransfer)
  }
  let writer = @encode.writer(4096, 8, 2) catch {
    _ => return Err(InvalidTransfer)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "requestCid")
    @encode.string_value(writer, request.request_cid)
    match kind {
      StoreUploadAdmissionReply => {
        @encode.key(writer, "sealed")
        @encode.bool_value(writer, is_sealed)
        if !is_sealed {
          @encode.key(writer, "nextChunk")
          @encode.number_value(writer, next_chunk.to_double())
        }
      }
      StoreUploadChunkReply => {
        @encode.key(writer, "nextChunk")
        @encode.number_value(writer, next_chunk.to_double())
      }
      StoreUploadCommitReply => {
        @encode.key(writer, "sealed")
        @encode.bool_value(writer, true)
      }
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidTransfer)
  }
}

///|
pub fn admit_remote_transfer_store_upload_reply_json(
  body : String,
  request : RemoteTransferRequest,
  kind : RemoteTransferStoreUploadReplyKind,
) -> Result[RemoteTransferStoreUploadReply, RemoteTransferIssue] {
  try {
    let node = match
      @source.parse_json_bytes(@utf8.encode(body), {
        max_input_bytes: 4096,
        max_nodes: 8,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise RemoteTransferStoreWireStop
    }
    let cursor = store_wire_decoded(
      @decode.admit(node, {
        max_nodes: 8,
        max_depth: 2,
        max_string_bytes: 1024,
        max_total_string_bytes: 4096,
      }),
    )
    let names = match kind {
      StoreUploadAdmissionReply =>
        if body.contains("\"nextChunk\"") {
          ["nextChunk", "requestCid", "sealed"]
        } else {
          ["requestCid", "sealed"]
        }
      StoreUploadChunkReply => ["nextChunk", "requestCid"]
      StoreUploadCommitReply => ["requestCid", "sealed"]
    }
    let object = store_wire_decoded(@decode.closed_object(cursor, names))
    let request_cid = store_wire_decoded(
      @decode.text(store_wire_decoded(@decode.required(object, "requestCid"))),
    )
    if request_cid != request.request_cid {
      return Err(TransferIdentityMismatch)
    }
    let is_sealed = match @decode.lookup(object, "sealed") {
      Some(value) => store_wire_decoded(@decode.boolean(value))
      None => false
    }
    let next_chunk = match @decode.lookup(object, "nextChunk") {
      Some(value) => {
        let number = store_wire_decoded(@decode.safe_integer(value))
        if number < 0L || number > 2147483647L {
          raise RemoteTransferStoreWireStop
        }
        number.to_int()
      }
      None => request.physical.chunks.length()
    }
    if !valid_store_upload_reply(request, kind, next_chunk, is_sealed) {
      return Err(InvalidTransfer)
    }
    let reply = { request_cid, next_chunk, is_sealed, }
    if remote_transfer_store_upload_reply_json(
        request, kind, next_chunk, is_sealed,
      ) ==
      Ok(body) {
      Ok(reply)
    } else {
      Err(InvalidTransfer)
    }
  } catch {
    RemoteTransferStoreWireStop => Err(InvalidTransfer)
  }
}

///|
pub fn remote_transfer_store_upload_reply_projection(
  reply : RemoteTransferStoreUploadReply,
) -> Array[String] {
  [
    reply.request_cid,
    reply.next_chunk.to_string(),
    if reply.is_sealed {
      "1"
    } else {
      "0"
    },
  ]
}
