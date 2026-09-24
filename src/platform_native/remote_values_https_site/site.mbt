///|
/// Physical HTTPS ingress for one checked Values Site. The TLS server bounds
/// request and response bytes; the common MoonBit endpoint admits the exact
/// dispatch and reads durable status without installing another Run owner.
struct NativeRemoteValuesHttpsSite {
  server : @https.NativeHttpsServer
  endpoint : @values.NativeRemoteValuesSiteEndpoint
  coordinator_fingerprint : String
  dispatch_path : String
  query_path : String
}

///|
pub(all) enum NativeRemoteValuesHttpsSiteIssue {
  InvalidConfiguration
  Server(@https.NativeHttpsServerIssue)
}

///|
/// Match the transport's encoded URL segment without treating a Site key as
/// path structure. Keep the physical route bounded independently of JSON.
fn encoded_site_key(key : String) -> String? {
  let bytes = @utf8.encode(key)
  if bytes.length() == 0 || bytes.length() > 256 {
    return None
  }
  let out = StringBuilder()
  let hex = "0123456789ABCDEF"
  for byte in bytes {
    let n = byte.to_int()
    let unreserved = (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 45 ||
      n == 46 ||
      n == 95 ||
      n == 126 ||
      n == 33 ||
      n == 39 ||
      n == 40 ||
      n == 41 ||
      n == 42
    if unreserved {
      out.write_char(n.to_char().unwrap())
    } else {
      out.write_char('%')
      out.write_char(hex[n >> 4].to_int().to_char().unwrap())
      out.write_char(hex[n & 15].to_int().to_char().unwrap())
    }
  }
  Some(out.to_string())
}

///|
pub fn open_native_remote_values_https_site(
  server : @https.NativeHttpsServer,
  endpoint : @values.NativeRemoteValuesSiteEndpoint,
  coordinator_fingerprint : String,
) -> Result[NativeRemoteValuesHttpsSite, NativeRemoteValuesHttpsSiteIssue] {
  if coordinator_fingerprint.is_empty() {
    return Err(InvalidConfiguration)
  }
  let (site_key, site_generation) = endpoint.route()
  let encoded_key = match encoded_site_key(site_key) {
    Some(value) => value
    None => return Err(InvalidConfiguration)
  }
  let path = "/v1/sites/" +
    encoded_key +
    "/generations/" +
    site_generation.to_string() +
    "/dispatches"
  Ok({
    server,
    endpoint,
    coordinator_fingerprint,
    dispatch_path: path,
    query_path: path + "/query",
  })
}

///|
fn NativeRemoteValuesHttpsSite::reply(
  self : NativeRemoteValuesHttpsSite,
  request : @https.NativeHttpsRequest,
  status : Int,
  body : String,
) -> Result[Unit, NativeRemoteValuesHttpsSiteIssue] {
  self.server
  .respond(request, status, "application/json", @utf8.encode(body))
  .map_err(issue => Server(issue))
}

///|
/// Advance one physically received request. Neither an invalid peer nor a
/// malformed envelope reaches the common runtime or its Site journal.
pub fn NativeRemoteValuesHttpsSite::poll(
  self : NativeRemoteValuesHttpsSite,
  timeout_milliseconds : Int,
) -> Result[Bool, NativeRemoteValuesHttpsSiteIssue] {
  let request = match self.server.poll(timeout_milliseconds) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(false)
    Err(issue) => return Err(Server(issue))
  }
  if request.peer_fingerprint() != self.coordinator_fingerprint ||
    request.request_method() != "POST" ||
    (request.path() != self.dispatch_path && request.path() != self.query_path) {
    return self.reply(request, 404, "{\"error\":\"not_found\"}").map(_ => true)
  }
  if request.header("content-type") != Some("application/json") {
    return self
      .reply(request, 400, "{\"error\":\"invalid_request\"}")
      .map(_ => true)
  }
  let claimed_cid = match request.header("actql-dispatch-cid") {
    Some(value) if !value.is_empty() => value
    _ =>
      return self
        .reply(request, 400, "{\"error\":\"invalid_request\"}")
        .map(_ => true)
  }
  let body = @utf8.decode(request.body()) catch {
    _ =>
      return self
        .reply(request, 400, "{\"error\":\"invalid_request\"}")
        .map(_ => true)
  }
  let response = if request.path() == self.dispatch_path {
    self.endpoint.dispatch_json(body, claimed_cid)
  } else {
    self.endpoint.query_json(body, claimed_cid)
  }
  let sent = match response {
    Ok(wire) => self.reply(request, 200, wire)
    Err(@values.ForeignDispatch) =>
      self.reply(request, 404, "{\"error\":\"not_found\"}")
    Err(@values.InvalidEnvelope) =>
      self.reply(request, 400, "{\"error\":\"invalid_request\"}")
    Err(@values.Journal(@journal.MissingDispatch)) if request.path() ==
      self.query_path => self.reply(request, 404, "{\"error\":\"not_found\"}")
    Err(_) => self.reply(request, 503, "{\"error\":\"site_unavailable\"}")
  }
  sent.map(_ => true)
}

///|
pub fn NativeRemoteValuesHttpsSite::port(
  self : NativeRemoteValuesHttpsSite,
) -> Int {
  self.server.port()
}

///|
pub fn NativeRemoteValuesHttpsSite::close(
  self : NativeRemoteValuesHttpsSite,
) -> Bool {
  self.server.close()
}
