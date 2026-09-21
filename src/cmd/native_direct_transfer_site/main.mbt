///|
priv enum DirectSiteIssue {
  InvalidRequest
  Unauthorized
  Unavailable
  Rejected
}

///|
priv struct DirectSiteEntry {
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
    "actql-native-direct-transfer-site",
    about="Receive durable direct Transfers in a native Site",
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
      @argparse.OptionArg("source-grant-cid", required=true),
      @argparse.OptionArg("destination-grant-cid", required=true),
      @argparse.OptionArg("route-capability-cid", required=true),
      @argparse.OptionArg("admin-fingerprint", required=true),
      @argparse.OptionArg("max-request-bytes", default_values=["1048576"]),
      @argparse.OptionArg("max-response-bytes", default_values=["65536"]),
      @argparse.OptionArg("max-pending", default_values=["32"]),
      @argparse.OptionArg("max-entries", default_values=["65536"]),
      @argparse.OptionArg("max-chunks", default_values=["4096"]),
      @argparse.OptionArg("max-manifest-bytes", default_values=["65536"]),
      @argparse.OptionArg("max-bytes", default_values=["268435456"]),
      @argparse.OptionArg("max-objects", default_values=["65536"]),
    ],
  )
}

///|
fn entry_for(
  entries : Array[DirectSiteEntry],
  request_cid : String,
) -> DirectSiteEntry? {
  for entry in entries {
    if @transfer.request_cid(entry.request) == request_cid {
      return Some(entry)
    }
  }
  None
}

///|
fn upsert_entry(
  entries : Array[DirectSiteEntry],
  request : @transfer.RemoteTransferRequest,
) -> DirectSiteEntry {
  match entry_for(entries, @transfer.request_cid(request)) {
    Some(value) => value
    None => {
      let entry = { request, }
      entries.push(entry)
      entry
    }
  }
}

///|
fn require_active(
  clock : @clock.NativeTrustedClock,
  request : @transfer.RemoteTransferRequest,
) -> Result[Unit, DirectSiteIssue] {
  match clock.observe() {
    Ok(now) if @transfer.request_active_at(request, now) => Ok(())
    _ => Err(Rejected)
  }
}

///|
fn require_source_peer(
  request : @https.NativeHttpsRequest,
  source_fingerprint : String,
) -> Result[Unit, DirectSiteIssue] {
  if request.peer_fingerprint() == source_fingerprint {
    Ok(())
  } else {
    Err(Unauthorized)
  }
}

///|
fn reply_record(
  record : @transfer.RemoteTransferRecord,
) -> Result[Bytes, DirectSiteIssue] {
  match @transfer.remote_transfer_reply_json(record) {
    Ok(value) => Ok(@utf8.encode(value))
    Err(_) => Err(Rejected)
  }
}

///|
fn admit_request(
  request : @https.NativeHttpsRequest,
  journal : @journal.Journal,
  clock : @clock.NativeTrustedClock,
  entries : Array[DirectSiteEntry],
  source_site : String,
  source_generation : Int,
  source_fingerprint : String,
  destination_site : String,
  destination_generation : Int,
  source_grant_cid : String,
  destination_grant_cid : String,
  route_capability_cid : String,
  max_chunks : Int,
  max_entries : Int,
  max_manifest_bytes : Int,
  max_bytes : Int64,
  max_objects : Int64,
) -> Result[Bytes, DirectSiteIssue] {
  match require_source_peer(request, source_fingerprint) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
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
  if projection[1] != "direct" ||
    projection[2] != source_site ||
    projection[3] != source_generation.to_string() ||
    projection[4] != destination_site ||
    projection[5] != destination_generation.to_string() ||
    projection[10] != source_grant_cid ||
    projection[11] != destination_grant_cid ||
    projection[12] != route_capability_cid {
    return Err(Unauthorized)
  }
  match require_active(clock, admitted) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if entry_for(entries, @transfer.request_cid(admitted)) is None &&
    entries.length() >= max_entries {
    return Err(Rejected)
  }
  let record = match
    @destination.admit_durable_direct_destination(
      journal, admitted, max_bytes, max_objects,
    ) {
    Ok(value) => value
    Err(_) => return Err(Rejected)
  }
  ignore(upsert_entry(entries, admitted))
  reply_record(record)
}

///|
fn suffix_parts(path : String, base : String) -> Array[StringView]? {
  let prefix = base + "/"
  if !path.has_prefix(prefix) {
    return None
  }
  Some(path[prefix.length():].split("/").to_array())
}

///|
fn handle_existing(
  server_request : @https.NativeHttpsRequest,
  journal : @journal.Journal,
  root : @filesystem.Root,
  clock : @clock.NativeTrustedClock,
  entries : Array[DirectSiteEntry],
  base : String,
  source_fingerprint : String,
) -> Result[Bytes, DirectSiteIssue] {
  match require_source_peer(server_request, source_fingerprint) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let parts = match suffix_parts(server_request.path(), base) {
    Some(value) => value
    None => return Err(Unavailable)
  }
  if parts.length() < 2 {
    return Err(Unavailable)
  }
  let entry = match entry_for(entries, parts[0].to_owned()) {
    Some(value) => value
    None => return Err(Unavailable)
  }
  match require_active(clock, entry.request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if server_request.request_method() == "PUT" &&
    parts.length() == 3 &&
    parts[1] == "chunks" {
    let index : Int = @string.from_str(parts[2].to_owned()) catch {
      _ => return Err(InvalidRequest)
    }
    let body = server_request.body()
    let announced = server_request.header("content-length").unwrap_or("")
    if announced != body.length().to_string() {
      return Err(InvalidRequest)
    }
    let record = match
      @destination.write_durable_direct_destination_chunk(
        journal,
        root,
        entry.request,
        index,
        body,
      ) {
      Ok(_) =>
        match journal.require(entry.request) {
          Ok(value) => value
          Err(_) => return Err(Rejected)
        }
      Err(_) => return Err(Rejected)
    }
    return reply_record(record)
  }
  if server_request.request_method() == "POST" && parts.length() == 2 {
    if !server_request.body().is_empty() {
      return Err(InvalidRequest)
    }
    if parts[1] == "commit" {
      match require_active(clock, entry.request) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      return match
        @destination.commit_durable_direct_destination(
          journal,
          root,
          entry.request,
        ) {
        Ok(value) => reply_record(value)
        Err(_) => Err(Rejected)
      }
    }
    if parts[1] == "cancel" {
      return match
        @destination.cancel_durable_direct_destination(
          journal,
          root,
          entry.request,
        ) {
        Ok(value) => reply_record(value)
        Err(_) => Err(Rejected)
      }
    }
  }
  Err(Unavailable)
}

///|
fn respond(
  server : @https.NativeHttpsServer,
  request : @https.NativeHttpsRequest,
  result : Result[Bytes, DirectSiteIssue],
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
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  let source_generation = required_int(matches, "source-generation")
  let destination_generation = required_int(matches, "destination-generation")
  let max_chunks = required_int(matches, "max-chunks")
  let max_entries = required_int(matches, "max-entries")
  let max_manifest_bytes = required_int(matches, "max-manifest-bytes")
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
    "remote-direct-transfer-clock-v1",
    required(matches, "destination-site") +
    ":" +
    destination_generation.to_string(),
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
  let source_site = required(matches, "source-site")
  let source_fingerprint = required(matches, "source-fingerprint")
  let destination_site = required(matches, "destination-site")
  let source_grant_cid = required(matches, "source-grant-cid")
  let destination_grant_cid = required(matches, "destination-grant-cid")
  let route_capability_cid = required(matches, "route-capability-cid")
  let admin_fingerprint = required(matches, "admin-fingerprint")
  let base = "/v1/sites/" +
    destination_site +
    "/generations/" +
    destination_generation.to_string() +
    "/transfers"
  let entries : Array[DirectSiteEntry] = []
  let mut running = true
  while running {
    match server.poll(1000) {
      Ok(Some(request)) =>
        if request.request_method() == "POST" &&
          request.path() == "/v1/admin/shutdown" &&
          request.peer_fingerprint() == admin_fingerprint {
          ignore(
            server.respond(
              request, 200, "application/json", b"{\"closed\":true}",
            ),
          )
          running = false
        } else if request.request_method() == "POST" && request.path() == base {
          respond(
            server,
            request,
            admit_request(
              request, journal, clock, entries, source_site, source_generation, source_fingerprint,
              destination_site, destination_generation, source_grant_cid, destination_grant_cid,
              route_capability_cid, max_chunks, max_entries, max_manifest_bytes,
              max_bytes, max_objects,
            ),
          )
        } else {
          respond(
            server,
            request,
            handle_existing(
              request, journal, root, clock, entries, base, source_fingerprint,
            ),
          )
        }
      Ok(None) => ()
      Err(_) => running = false
    }
  }
  let server_closed = server.close()
  let journal_closed = journal.close()
  let clock_closed = clock.close()
  if !server_closed || !journal_closed || !clock_closed {
    abort("native direct Transfer Site cleanup remains pending")
  }
}
