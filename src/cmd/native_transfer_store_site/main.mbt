///|
priv enum StoreSiteIssue {
  InvalidRequest
  Unauthorized
  Unavailable
  Rejected
}

///|
priv struct StoreEntry {
  request : @transfer.RemoteTransferRequest
}

///|
priv struct CompletionWaiter {
  server_request : @https.NativeHttpsRequest
  request : @transfer.RemoteTransferRequest
}

///|
fn required(matches : @argparse.Matches, name : String) -> String {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => value
    _ => abort("missing or repeated option --" + name)
  }
}

///|
fn required_int(matches : @argparse.Matches, name : String) -> Int {
  @string.from_str(required(matches, name)) catch {
    _ => abort("invalid integer option --" + name)
  }
}

///|
fn required_int64(matches : @argparse.Matches, name : String) -> Int64 {
  @string.from_str(required(matches, name)) catch {
    _ => abort("invalid integer option --" + name)
  }
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "actql-native-transfer-store-site",
    about="Retain and serve durable Transfer objects in a native Site",
    version="0.1",
    options=[
      @argparse.OptionArg("host", default_values=["127.0.0.1"]),
      @argparse.OptionArg("port", required=true),
      @argparse.OptionArg("cert", required=true),
      @argparse.OptionArg("key", required=true),
      @argparse.OptionArg("ca", required=true),
      @argparse.OptionArg("sqlite-library", required=true),
      @argparse.OptionArg("journal", required=true),
      @argparse.OptionArg("clock-journal", required=true),
      @argparse.OptionArg("root", required=true),
      @argparse.OptionArg("source-site", required=true),
      @argparse.OptionArg("source-generation", required=true),
      @argparse.OptionArg("source-fingerprint", required=true),
      @argparse.OptionArg("destination-site", required=true),
      @argparse.OptionArg("destination-generation", required=true),
      @argparse.OptionArg("destination-fingerprint", required=true),
      @argparse.OptionArg("source-grant-cid", required=true),
      @argparse.OptionArg("destination-grant-cid", required=true),
      @argparse.OptionArg("route-capability-cid", required=true),
      @argparse.OptionArg("admin-fingerprint", required=true),
      @argparse.OptionArg("max-request-bytes", default_values=["1048576"]),
      @argparse.OptionArg("max-response-bytes", default_values=["1048576"]),
      @argparse.OptionArg("max-pending", default_values=["32"]),
      @argparse.OptionArg("max-entries", default_values=["65536"]),
      @argparse.OptionArg("max-chunks", default_values=["4096"]),
      @argparse.OptionArg("max-manifest-bytes", default_values=["65536"]),
      @argparse.OptionArg("max-frame-bytes", default_values=["1048576"]),
      @argparse.OptionArg("max-bytes", default_values=["268435456"]),
      @argparse.OptionArg("max-objects", default_values=["65536"]),
    ],
  )
}

///|
fn entry_for(entries : Array[StoreEntry], request_cid : String) -> StoreEntry? {
  for entry in entries {
    if @transfer.request_cid(entry.request) == request_cid {
      return Some(entry)
    }
  }
  None
}

///|
fn upsert_entry(
  entries : Array[StoreEntry],
  request : @transfer.RemoteTransferRequest,
  max_entries : Int,
) -> Result[StoreEntry, StoreSiteIssue] {
  match entry_for(entries, @transfer.request_cid(request)) {
    Some(value) => Ok(value)
    None => {
      if entries.length() >= max_entries {
        return Err(Rejected)
      }
      let entry = { request, }
      entries.push(entry)
      Ok(entry)
    }
  }
}

///|
fn active(
  clock : @clock.NativeTrustedClock,
  request : @transfer.RemoteTransferRequest,
) -> Bool {
  match clock.observe() {
    Ok(now) => @transfer.request_active_at(request, now)
    Err(_) => false
  }
}

///|
fn peer_matches(
  request : @https.NativeHttpsRequest,
  fingerprint : String,
) -> Bool {
  request.peer_fingerprint() == fingerprint
}

///|
fn admitted_request(
  request : @https.NativeHttpsRequest,
  expected_peer : String,
  expected_site : String,
  expected_generation : Int,
  phase : String,
  source_grant_cid : String,
  destination_grant_cid : String,
  route_capability_cid : String,
  clock : @clock.NativeTrustedClock,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_bytes : Int64,
) -> Result[@transfer.RemoteTransferRequest, StoreSiteIssue] {
  if !peer_matches(request, expected_peer) {
    return Err(Unauthorized)
  }
  let request_cid = request.header("actql-transfer-cid").unwrap_or("")
  let manifest_cid = request.header("actql-manifest-cid").unwrap_or("")
  let body = @utf8.decode(request.body()) catch {
    _ => return Err(InvalidRequest)
  }
  let admitted = match
    @transfer.admit_transfer_admission_envelope_json(
      body, request_cid, manifest_cid, max_chunks, max_manifest_bytes, max_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidRequest)
  }
  let projection = @transfer.request_projection(admitted)
  let peer_site = if phase == "upload" { projection[2] } else { projection[4] }
  let peer_generation = if phase == "upload" {
    projection[3]
  } else {
    projection[5]
  }
  if projection[1] != "store" ||
    peer_site != expected_site ||
    peer_generation != expected_generation.to_string() ||
    projection[10] != source_grant_cid ||
    projection[11] != destination_grant_cid ||
    projection[12] != route_capability_cid ||
    !active(clock, admitted) {
    Err(Unauthorized)
  } else {
    Ok(admitted)
  }
}

///|
fn response_bytes(body : String) -> Result[Bytes, StoreSiteIssue] {
  Ok(@utf8.encode(body))
}

///|
fn upload_reply(
  request : @transfer.RemoteTransferRequest,
  kind : @transfer.RemoteTransferStoreUploadReplyKind,
  next_chunk : Int,
  sealed_object : Bool,
) -> Result[Bytes, StoreSiteIssue] {
  match
    @transfer.remote_transfer_store_upload_reply_json(
      request, kind, next_chunk, sealed_object,
    ) {
    Ok(value) => response_bytes(value)
    Err(_) => Err(Rejected)
  }
}

///|
fn use_reply(
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  kind : @transfer.RemoteTransferStoreUseReplyKind,
  complete : Bool,
) -> Result[Bytes, StoreSiteIssue] {
  match
    @transfer.remote_transfer_store_use_reply_json(
      request, use_id, kind, complete,
    ) {
    Ok(value) => response_bytes(value)
    Err(_) => Err(Rejected)
  }
}

///|
fn cancellation_reply(
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[Bytes, StoreSiteIssue] {
  match
    @transfer.remote_transfer_store_use_cancellation_reply_json(request, use_id) {
    Ok(value) => response_bytes(value)
    Err(_) => Err(Rejected)
  }
}

///|
fn record_reply(
  record : @transfer.RemoteTransferRecord,
) -> Result[Bytes, StoreSiteIssue] {
  match @transfer.remote_transfer_reply_json(record) {
    Ok(value) => response_bytes(value)
    Err(_) => Err(Rejected)
  }
}

///|
fn respond_json(
  server : @https.NativeHttpsServer,
  request : @https.NativeHttpsRequest,
  result : Result[Bytes, StoreSiteIssue],
) -> Unit {
  let (status, body) = match result {
    Ok(value) => (200, value)
    Err(Unauthorized) | Err(Unavailable) => (404, b"{\"error\":\"not_found\"}")
    Err(InvalidRequest) | Err(Rejected) =>
      (409, b"{\"error\":\"transfer_rejected\"}")
  }
  ignore(server.respond(request, status, "application/json", body))
}

///|
fn commit_use_transition(
  journal : @journal.Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  transition : @transfer.RemoteTransferStoreUseTransition,
) -> Result[@transfer.RemoteTransferStoreUseRecord, StoreSiteIssue] {
  match journal.commit_store_use_transition(transition) {
    Ok(_) => {
      let store_use = match @transfer.prepare_store_use(request, use_id) {
        Ok(value) => value
        Err(_) => return Err(Rejected)
      }
      match journal.require_store_use(store_use) {
        Ok(value) => Ok(value)
        Err(_) => Err(Rejected)
      }
    }
    Err(_) => Err(Rejected)
  }
}

///|
fn admit_store_use(
  journal : @journal.Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[@transfer.RemoteTransferStoreUseRecord, StoreSiteIssue] {
  let (_, accepted) = match journal.accept_store_use(request, use_id) {
    Ok(value) => value
    Err(_) => return Err(Rejected)
  }
  let mut record = accepted
  let state = @transfer.store_use_record_projection(record)
  if state[1] == "0" {
    let transition = match @transfer.prepare_store_use_start(record) {
      Ok(value) => value
      Err(_) => return Err(Rejected)
    }
    record = match commit_use_transition(journal, request, use_id, transition) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  Ok(record)
}

///|
fn complete_destination(
  journal : @journal.Journal,
  request : @transfer.RemoteTransferRequest,
  receipt : @transfer.RemoteTransferDestinationReceipt,
) -> Result[@transfer.RemoteTransferRecord, StoreSiteIssue] {
  let mut record = match journal.require(request) {
    Ok(value) => value
    Err(_) => return Err(Rejected)
  }
  if @transfer.record_is_destination_committed(record) {
    return Ok(record)
  }
  match journal.commit_destination_receipt(receipt, request) {
    Ok(_) => ()
    Err(_) => return Err(Rejected)
  }
  if @transfer.store_upload_progress(record) == @transfer.StoreUploadSealed {
    let transition = match @transfer.prepare_destination_commit(record) {
      Ok(value) => value
      Err(_) => return Err(Rejected)
    }
    match journal.commit_transition(transition) {
      Ok(_) => ()
      Err(_) => return Err(Rejected)
    }
    record = match journal.require(request) {
      Ok(value) => value
      Err(_) => return Err(Rejected)
    }
  }
  if @transfer.record_is_destination_committed(record) {
    Ok(record)
  } else {
    Err(Rejected)
  }
}

///|
fn admit_upload_object(
  journal : @journal.Journal,
  root : @filesystem.Root,
  entries : Array[StoreEntry],
  request : @transfer.RemoteTransferRequest,
  max_entries : Int,
  max_bytes : Int64,
  max_objects : Int64,
) -> Result[Bytes, StoreSiteIssue] {
  match upsert_entry(entries, request, max_entries) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let record = match
    @object.admit_durable_store_object(journal, request, max_bytes, max_objects) {
    Ok(value) => value
    Err(_) => return Err(Rejected)
  }
  let next = match
    @object.durable_store_object_next_chunk(journal, root, request) {
    Ok(value) => value
    Err(_) => return Err(Rejected)
  }
  upload_reply(
    request,
    @transfer.StoreUploadAdmissionReply,
    next,
    @transfer.store_upload_progress(record) != @transfer.StoreUploadCopying,
  )
}

///|
fn admit_download_use(
  journal : @journal.Journal,
  entries : Array[StoreEntry],
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[Bytes, StoreSiteIssue] {
  if entry_for(entries, @transfer.request_cid(request)) is None {
    return Err(Unavailable)
  }
  let record = match admit_store_use(journal, request, use_id) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let state = @transfer.store_use_record_projection(record)
  use_reply(request, use_id, @transfer.StoreUseAdmissionReply, state[1] == "2")
}

///|
fn complete_store_use(
  journal : @journal.Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  receipt : @transfer.RemoteTransferDestinationReceipt,
) -> Result[Bytes, StoreSiteIssue] {
  let use_record = match admit_store_use(journal, request, use_id) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let state = @transfer.store_use_record_projection(use_record)
  if state[1] != "2" {
    let transition = match
      @transfer.prepare_store_use_complete(use_record, receipt) {
      Ok(value) => value
      Err(_) => return Err(Rejected)
    }
    let completed = match
      commit_use_transition(journal, request, use_id, transition) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let cleanup = match @transfer.prepare_store_use_cleanup(completed) {
      Ok(value) => value
      Err(_) => return Err(Rejected)
    }
    match commit_use_transition(journal, request, use_id, cleanup) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  } else if state[6] != @transfer.destination_receipt_cid(receipt) {
    return Err(Rejected)
  }
  match complete_destination(journal, request, receipt) {
    Ok(_) => use_reply(request, use_id, @transfer.StoreUseCompletionReply, true)
    Err(issue) => Err(issue)
  }
}

///|
fn cancel_store_use(
  journal : @journal.Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[Bytes, StoreSiteIssue] {
  let mut record = match admit_store_use(journal, request, use_id) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let state = @transfer.store_use_record_projection(record)
  if state[1] != "2" && state[1] != "3" {
    let failed = match @transfer.prepare_store_use_failure(record, true) {
      Ok(value) => value
      Err(_) => return Err(Rejected)
    }
    record = match commit_use_transition(journal, request, use_id, failed) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let cleanup = match @transfer.prepare_store_use_cleanup(record) {
      Ok(value) => value
      Err(_) => return Err(Rejected)
    }
    match commit_use_transition(journal, request, use_id, cleanup) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  cancellation_reply(request, use_id)
}

///|
fn advance_store_use(
  journal : @journal.Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  record : @transfer.RemoteTransferStoreUseRecord,
  index : Int,
  confirmed_bytes : Int64,
) -> Result[Unit, StoreSiteIssue] {
  let transition = match
    @transfer.prepare_store_use_progress(record, index + 1, confirmed_bytes) {
    Ok(value) => value
    Err(_) => return Err(Rejected)
  }
  match commit_use_transition(journal, request, use_id, transition) {
    Ok(_) => Ok(())
    Err(issue) => Err(issue)
  }
}

///|
fn recover_entries(
  journal : @journal.Journal,
  entries : Array[StoreEntry],
  max_entries : Int,
) -> Result[Unit, StoreSiteIssue] {
  let mut after = ""
  while true {
    match journal.recover_after(after) {
      Ok(Some(recovered)) => {
        after = @journal.recovered_remote_transfer_key(recovered)
        let record = @journal.recovered_remote_transfer_record(recovered)
        let request = @transfer.record_request(record)
        if @transfer.request_projection(request)[1] == "store" {
          match upsert_entry(entries, request, max_entries) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
        }
      }
      Ok(None) => return Ok(())
      Err(_) => return Err(Rejected)
    }
  }
  abort("unreachable")
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  let source_site = required(matches, "source-site")
  let source_generation = required_int(matches, "source-generation")
  let source_fingerprint = required(matches, "source-fingerprint")
  let destination_site = required(matches, "destination-site")
  let destination_generation = required_int(matches, "destination-generation")
  let destination_fingerprint = required(matches, "destination-fingerprint")
  let source_grant_cid = required(matches, "source-grant-cid")
  let destination_grant_cid = required(matches, "destination-grant-cid")
  let route_capability_cid = required(matches, "route-capability-cid")
  let max_entries = required_int(matches, "max-entries")
  let max_chunks = required_int(matches, "max-chunks")
  let max_manifest_bytes = required_int(matches, "max-manifest-bytes")
  let max_frame_bytes = required_int(matches, "max-frame-bytes")
  let max_bytes = required_int64(matches, "max-bytes")
  let max_objects = required_int64(matches, "max-objects")
  let library = @sqlite.load_library(required(matches, "sqlite-library")).unwrap()
  let journal = @journal.open_journal(
    library,
    required(matches, "journal"),
    required_int64(matches, "max-request-bytes"),
    max_chunks,
    max_manifest_bytes,
    max_bytes,
  ).unwrap()
  let clock = @clock.open(
    library,
    required(matches, "clock-journal"),
    "remote-transfer-store-clock-v1",
    source_site + ":" + source_generation.to_string(),
  ).unwrap()
  let root = @filesystem.open_root(required(matches, "root")).unwrap()
  let server = @https.open(
    required(matches, "host"),
    required_int(matches, "port"),
    required(matches, "cert"),
    required(matches, "key"),
    required(matches, "ca"),
    required_int(matches, "max-request-bytes"),
    required_int(matches, "max-response-bytes"),
    required_int(matches, "max-pending"),
  ).unwrap()
  let entries : Array[StoreEntry] = []
  recover_entries(journal, entries, max_entries).unwrap()
  let waiters : Array[CompletionWaiter] = []
  let admin_fingerprint = required(matches, "admin-fingerprint")
  let mut running = true
  while running {
    match server.poll(100) {
      Err(_) => running = false
      Ok(None) => ()
      Ok(Some(request)) => {
        let path = request.path()
        let parts = path.split("/").to_array()
        if request.request_method() == "POST" &&
          path == "/v1/admin/shutdown" &&
          peer_matches(request, admin_fingerprint) {
          ignore(
            server.respond(
              request, 200, "application/json", b"{\"closed\":true}",
            ),
          )
          running = false
        } else if request.request_method() == "POST" &&
          path == "/v1/transfer-store/uploads" {
          let admitted = admitted_request(
            request, source_fingerprint, source_site, source_generation, "upload",
            source_grant_cid, destination_grant_cid, route_capability_cid, clock,
            max_chunks, max_manifest_bytes, max_bytes,
          )
          respond_json(
            server,
            request,
            match admitted {
              Err(issue) => Err(issue)
              Ok(value) =>
                admit_upload_object(
                  journal, root, entries, value, max_entries, max_bytes, max_objects,
                )
            },
          )
        } else if request.request_method() == "POST" &&
          path == "/v1/transfer-store/downloads" {
          let admitted = admitted_request(
            request, destination_fingerprint, destination_site, destination_generation,
            "download", source_grant_cid, destination_grant_cid, route_capability_cid,
            clock, max_chunks, max_manifest_bytes, max_bytes,
          )
          let use_id = request.header("actql-transfer-use-id").unwrap_or("")
          respond_json(
            server,
            request,
            match admitted {
              Err(issue) => Err(issue)
              Ok(value) => admit_download_use(journal, entries, value, use_id)
            },
          )
        } else if parts.length() >= 6 &&
          parts[1] == "v1" &&
          parts[2] == "transfer-store" {
          let operation = parts[3].to_owned()
          let request_cid = parts[4].to_owned()
          let entry = entry_for(entries, request_cid)
          match entry {
            None => respond_json(server, request, Err(Unavailable))
            Some(entry) =>
              if operation == "uploads" &&
                request.request_method() == "PUT" &&
                parts.length() == 7 &&
                parts[5] == "chunks" {
                let index : Int = @string.from_str(parts[6].to_owned()) catch {
                  _ => -1
                }
                if !peer_matches(request, source_fingerprint) ||
                  !active(clock, entry.request) {
                  respond_json(server, request, Err(Unauthorized))
                } else {
                  let next = @object.durable_store_object_next_chunk(
                    journal,
                    root,
                    entry.request,
                  )
                  let result = match next {
                    Ok(expected) if expected == index =>
                      match
                        @object.write_durable_store_object_chunk(
                          journal,
                          root,
                          entry.request,
                          index,
                          request.body(),
                        ) {
                        Ok(_) =>
                          upload_reply(
                            entry.request,
                            @transfer.StoreUploadChunkReply,
                            index + 1,
                            false,
                          )
                        Err(_) => Err(Rejected)
                      }
                    _ => Err(Rejected)
                  }
                  respond_json(server, request, result)
                }
              } else if operation == "uploads" &&
                request.request_method() == "POST" &&
                parts.length() == 6 &&
                parts[5] == "commit" {
                if !peer_matches(request, source_fingerprint) ||
                  !request.body().is_empty() ||
                  !active(clock, entry.request) {
                  respond_json(server, request, Err(Unauthorized))
                } else {
                  respond_json(
                    server,
                    request,
                    match
                      @object.seal_durable_store_object(
                        journal,
                        root,
                        entry.request,
                      ) {
                      Ok(_) =>
                        upload_reply(
                          entry.request,
                          @transfer.StoreUploadCommitReply,
                          @transfer.request_chunk_cids(entry.request).length(),
                          true,
                        )
                      Err(_) => Err(Rejected)
                    },
                  )
                }
              } else if operation == "uploads" &&
                request.request_method() == "POST" &&
                parts.length() == 6 &&
                parts[5] == "completion" {
                let admitted = admitted_request(
                  request, source_fingerprint, source_site, source_generation, "upload",
                  source_grant_cid, destination_grant_cid, route_capability_cid,
                  clock, max_chunks, max_manifest_bytes, max_bytes,
                )
                match admitted {
                  Err(issue) => respond_json(server, request, Err(issue))
                  Ok(exact) =>
                    if @transfer.request_cid(exact) !=
                      @transfer.request_cid(entry.request) {
                      respond_json(server, request, Err(Unauthorized))
                    } else {
                      let record = journal.require(entry.request)
                      match record {
                        Ok(value) if @transfer.record_is_destination_committed(
                            value,
                          ) =>
                          respond_json(server, request, record_reply(value))
                        Ok(_) =>
                          if waiters.length() >=
                            required_int(matches, "max-pending") {
                            respond_json(server, request, Err(Unavailable))
                          } else {
                            waiters.push({
                              server_request: request,
                              request: entry.request,
                            })
                          }
                        Err(_) => respond_json(server, request, Err(Rejected))
                      }
                    }
                }
              } else if operation == "downloads" && parts.length() >= 7 {
                let use_id = parts[5].to_owned()
                if !peer_matches(request, destination_fingerprint) ||
                  !active(clock, entry.request) {
                  respond_json(server, request, Err(Unauthorized))
                } else if request.request_method() == "GET" &&
                  parts.length() == 8 &&
                  parts[6] == "chunks" {
                  let index : Int = @string.from_str(parts[7].to_owned()) catch {
                    _ => -1
                  }
                  let result = match
                    admit_store_use(journal, entry.request, use_id) {
                    Err(issue) => Err(issue)
                    Ok(record) => {
                      let state = @transfer.store_use_record_projection(record)
                      let confirmed : Int = @string.from_str(state[3]) catch {
                        _ => -1
                      }
                      if confirmed != index {
                        Err(Rejected)
                      } else {
                        match
                          @object.read_durable_store_object_chunk(
                            journal,
                            root,
                            entry.request,
                            index,
                            max_frame_bytes,
                          ) {
                          Err(_) => Err(Rejected)
                          Ok(body) => {
                            let confirmed_bytes : Int64 = @string.from_str(
                              state[4],
                            ) catch {
                              _ => -1L
                            }
                            match
                              advance_store_use(
                                journal,
                                entry.request,
                                use_id,
                                record,
                                index,
                                confirmed_bytes + body.length().to_int64(),
                              ) {
                              Ok(_) => {
                                ignore(
                                  server.respond(
                                    request, 200, "application/octet-stream", body,
                                  ),
                                )
                                Ok(b"")
                              }
                              Err(issue) => Err(issue)
                            }
                          }
                        }
                      }
                    }
                  }
                  match result {
                    Ok(_) => ()
                    Err(issue) => respond_json(server, request, Err(issue))
                  }
                } else if request.request_method() == "POST" &&
                  parts.length() == 7 &&
                  parts[6] == "complete" {
                  let claimed = request
                    .header("actql-destination-receipt-cid")
                    .unwrap_or("")
                  let body = @utf8.decode(request.body()) catch { _ => "" }
                  let receipt = @transfer.admit_destination_receipt_json(
                    body,
                    entry.request,
                    claimed,
                  )
                  respond_json(
                    server,
                    request,
                    match receipt {
                      Err(_) => Err(InvalidRequest)
                      Ok(receipt) =>
                        complete_store_use(
                          journal,
                          entry.request,
                          use_id,
                          receipt,
                        )
                    },
                  )
                } else if request.request_method() == "POST" &&
                  parts.length() == 7 &&
                  parts[6] == "cancel" {
                  respond_json(
                    server,
                    request,
                    cancel_store_use(journal, entry.request, use_id),
                  )
                } else {
                  respond_json(server, request, Err(Unavailable))
                }
              } else {
                respond_json(server, request, Err(Unavailable))
              }
          }
        } else {
          respond_json(server, request, Err(Unavailable))
        }
      }
    }
    let remaining : Array[CompletionWaiter] = []
    for waiter in waiters {
      if !active(clock, waiter.request) {
        respond_json(server, waiter.server_request, Err(Unauthorized))
      } else {
        match journal.require(waiter.request) {
          Ok(record) if @transfer.record_is_destination_committed(record) =>
            respond_json(server, waiter.server_request, record_reply(record))
          Ok(_) => remaining.push(waiter)
          Err(_) => respond_json(server, waiter.server_request, Err(Rejected))
        }
      }
    }
    waiters.clear()
    for waiter in remaining {
      waiters.push(waiter)
    }
  }
  for waiter in waiters {
    respond_json(server, waiter.server_request, Err(Unavailable))
  }
  let server_closed = server.close()
  let journal_closed = journal.close()
  let clock_closed = clock.close()
  if !server_closed || !journal_closed || !clock_closed {
    abort("native Transfer Store cleanup remains pending")
  }
}
