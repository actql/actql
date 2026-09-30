///|
fn option(matches : @argparse.Matches, name : String) -> Result[String, String] {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => Ok(value)
    _ => Err("missing or repeated option --" + name)
  }
}

///|
fn parse_int(value : String, name : String) -> Result[Int, String] {
  let parsed : Int = @string.from_str(value) catch {
    _ => return Err("invalid integer option --" + name)
  }
  Ok(parsed)
}

///|
fn parse_int64(value : String, name : String) -> Result[Int64, String] {
  let parsed : Int64 = @string.from_str(value) catch {
    _ => return Err("invalid integer option --" + name)
  }
  Ok(parsed)
}

///|
fn int_option(
  matches : @argparse.Matches,
  name : String,
) -> Result[Int, String] {
  match option(matches, name) {
    Ok(value) => parse_int(value, name)
    Err(issue) => Err(issue)
  }
}

///|
fn int64_option(
  matches : @argparse.Matches,
  name : String,
) -> Result[Int64, String] {
  match option(matches, name) {
    Ok(value) => parse_int64(value, name)
    Err(issue) => Err(issue)
  }
}

///|
fn journal_issue_code(issue : @journal.NativeRemoteJournalIssue) -> String {
  match issue {
    @journal.UnsupportedTarget => "unsupported-target"
    @journal.Closed => "closed"
    @journal.Physical(_) => "physical"
    @journal.Protocol(_) => "protocol"
    @journal.StaleSiteBinding => "stale-site-binding"
    @journal.MissingDispatch => "missing-dispatch"
    @journal.StateCollision => "state-collision"
    @journal.InitializationCleanupPending(_, _, _) =>
      "initialization-cleanup-pending"
  }
}

///|
fn client_issue_code(issue : @client.NativeRemoteClientIssue) -> String {
  match issue {
    @client.UnsupportedTarget => "unsupported-target"
    @client.Closed => "closed"
    @client.Http(_) => "http"
    @client.Journal(value) => "journal-" + journal_issue_code(value)
    @client.Protocol(_) => "protocol"
    @client.HttpStatus(value) => "http-status-" + value.to_string()
    @client.InvalidUtf8 => "invalid-utf8"
    @client.NotAuthorized => "not-authorized"
    @client.OutcomeUnknownPersistence(_, primary) =>
      "outcome-unknown-" + client_issue_code(primary)
  }
}

///|
fn site_from(
  matches : @argparse.Matches,
  binding_matches : @argparse.Matches,
  generation_name : String,
  revision_name : String,
) -> Result[@site.ExecutionSite, String] {
  let key = match option(matches, "site-key") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let generation = match int_option(binding_matches, generation_name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let revision = match option(binding_matches, revision_name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_operations = match int_option(matches, "max-operations") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_transfers = match int_option(matches, "max-transfers") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_retained = match int64_option(matches, "max-retained-bytes") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_execution = match int64_option(matches, "max-execution-bytes") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    @site.create_site(
      key, generation, revision, max_operations, max_transfers, max_retained, max_execution,
    ) {
    Some(value) => Ok(value)
    None => Err("invalid Site configuration")
  }
}

///|
fn open_journal(
  matches : @argparse.Matches,
  site : @site.ExecutionSite,
) -> Result[@journal.Journal, String] {
  let sqlite_library = match option(matches, "sqlite-library") {
    Ok(path) =>
      match @sqlite.load_library(path) {
        Ok(value) => value
        Err(_) => return Err("SQLite library load failed")
      }
    Err(issue) => return Err(issue)
  }
  let path = match option(matches, "journal-path") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_record_bytes = match int64_option(matches, "max-record-bytes") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let control = match
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1") {
    Ok(value) => value
    Err(_) => return Err("invalid Site journal configuration")
  }
  match @journal.open_journal(sqlite_library, path, max_record_bytes, control) {
    Ok(value) => Ok(value)
    Err(issue) => Err("journal " + journal_issue_code(issue))
  }
}

///|
fn request_from_file(
  matches : @argparse.Matches,
  max_bytes : Int64,
) -> Result[@remote.DispatchRequest, String] {
  let root = match option(matches, "request-root") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let name = match option(matches, "request-name") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let claimed_cid = match option(matches, "request-cid") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = match @files.read_bounded_text_file(root, name, max_bytes) {
    Ok(value) => value
    Err(_) => return Err("dispatch request read failed")
  }
  match @remote.admit_dispatch_request_json(body, claimed_cid) {
    Ok(value) => Ok(value)
    Err(_) => Err("dispatch request admission failed")
  }
}

///|
fn force_loss(
  matches : @argparse.Matches,
  journal : @journal.Journal,
  max_record_bytes : Int64,
) -> Result[String, String] {
  let request = match request_from_file(matches, max_record_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let record = match journal.require(request) {
    Ok(value) => value
    Err(issue) => return Err("force-loss " + journal_issue_code(issue))
  }
  let authorized = match option(matches, "operator-confirmation") {
    Ok("quarantine-unreclaimed-capacity") => true
    Ok(_) => false
    Err(issue) => return Err(issue)
  }
  match journal.force_loss(record, authorized) {
    Ok(_) => Ok("{\"forced_loss\":true,\"capacity_released\":false}")
    Err(issue) => Err("force-loss " + journal_issue_code(issue))
  }
}

///|
fn poll_result_json(
  kind : String,
  request_cid : String,
  revision : Int,
) -> Result[String, String] {
  let writer = @encode.writer(4096, 8, 1) catch {
    _ => return Err("result encoding failed")
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, kind)
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, request_cid)
    @encode.key(writer, "revision")
    @encode.number_value(writer, revision.to_double())
    @encode.end_object(writer)
  } catch {
    _ => return Err("result encoding failed")
  }
  Ok(@encode.finish(writer) catch { _ => return Err("result encoding failed") })
}

///|
fn poll_once(
  matches : @argparse.Matches,
  journal : @journal.Journal,
) -> Result[String, String] {
  let http_library = match option(matches, "http-library") {
    Ok(path) =>
      match @http.load_library(path) {
        Ok(value) => value
        Err(_) => return Err("HTTP library load failed")
      }
    Err(issue) => return Err(issue)
  }
  let ca = match option(matches, "ca") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let cert = match option(matches, "cert") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let key = match option(matches, "key") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_response_bytes = match int64_option(matches, "max-response-bytes") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let connect_timeout = match int_option(matches, "connect-timeout-ms") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let total_timeout = match int_option(matches, "total-timeout-ms") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let client = match
    http_library.create_client(
      ca, cert, key, max_response_bytes, connect_timeout, total_timeout,
    ) {
    Ok(value) => value
    Err(_) => return Err("HTTP client creation failed")
  }
  let poll_url = match option(matches, "poll-url") {
    Ok(value) => value
    Err(issue) => {
      ignore(client.close())
      return Err(issue)
    }
  }
  let observation_url = match option(matches, "observation-url") {
    Ok(value) => value
    Err(issue) => {
      ignore(client.close())
      return Err(issue)
    }
  }
  let operation = match @client.poll_operation(client, poll_url) {
    Ok(value) => value
    Err(issue) => {
      ignore(client.close())
      return Err("poll " + client_issue_code(issue))
    }
  }
  let result = match operation {
    None => Ok("{\"kind\":\"idle\"}")
    Some(@remote.Dispatch(_)) =>
      Err("dispatch requires a runtime-linked Site component")
    Some(@remote.Plan(_)) | Some(@remote.Output(_)) =>
      Err("output requires an application-linked Site component")
    Some(@remote.Query(request)) =>
      match
        @client.acknowledge_status(journal, client, observation_url, request) {
        Ok(Some(record)) =>
          poll_result_json(
            "query",
            @remote.dispatch_request_identity(request),
            @remote.dispatch_record_revision(record),
          )
        Ok(None) =>
          poll_result_json(
            "not-seen",
            @remote.dispatch_request_identity(request),
            0,
          )
        Err(issue) => Err("query " + client_issue_code(issue))
      }
    Some(@remote.Release(request)) =>
      match
        @client.acknowledge_status(journal, client, observation_url, request) {
        Ok(Some(record)) =>
          poll_result_json(
            "release-pending",
            @remote.dispatch_request_identity(request),
            @remote.dispatch_record_revision(record),
          )
        Ok(None) =>
          poll_result_json(
            "not-seen",
            @remote.dispatch_request_identity(request),
            0,
          )
        Err(issue) => Err("release " + client_issue_code(issue))
      }
  }
  if !client.close() {
    return match result {
      Ok(_) => Err("HTTP client close failed")
      Err(issue) => Err(issue + "; HTTP client close failed")
    }
  }
  result
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "actql-native-remote-site",
    about="Operate one native outbound ActQL Site control occurrence",
    version="0.1",
    subcommand_required=true,
    options=[
      @argparse.OptionArg("sqlite-library", required=true, global=true),
      @argparse.OptionArg("journal-path", required=true, global=true),
      @argparse.OptionArg("site-key", required=true, global=true),
      @argparse.OptionArg("site-generation", required=true, global=true),
      @argparse.OptionArg("runtime-revision", required=true, global=true),
      @argparse.OptionArg("max-operations", default_values=["16"], global=true),
      @argparse.OptionArg("max-transfers", default_values=["16"], global=true),
      @argparse.OptionArg(
        "max-retained-bytes",
        default_values=["1073741824"],
        global=true,
      ),
      @argparse.OptionArg(
        "max-execution-bytes",
        default_values=["1073741824"],
        global=true,
      ),
      @argparse.OptionArg(
        "max-record-bytes",
        default_values=["1048576"],
        global=true,
      ),
      @argparse.OptionArg("http-library", global=true),
      @argparse.OptionArg("ca", global=true),
      @argparse.OptionArg("cert", global=true),
      @argparse.OptionArg("key", global=true),
      @argparse.OptionArg("poll-url", global=true),
      @argparse.OptionArg("observation-url", global=true),
      @argparse.OptionArg(
        "max-response-bytes",
        default_values=["131072"],
        global=true,
      ),
      @argparse.OptionArg(
        "connect-timeout-ms",
        default_values=["2000"],
        global=true,
      ),
      @argparse.OptionArg(
        "total-timeout-ms",
        default_values=["5000"],
        global=true,
      ),
    ],
    subcommands=[
      @argparse.Command("poll-once"),
      @argparse.Command("force-loss", options=[
        @argparse.OptionArg("request-root", required=true),
        @argparse.OptionArg("request-name", required=true),
        @argparse.OptionArg("request-cid", required=true),
        @argparse.OptionArg("operator-confirmation", required=true),
      ]),
      @argparse.Command("restart", options=[
        @argparse.OptionArg("next-generation", required=true),
        @argparse.OptionArg("next-runtime-revision", required=true),
      ]),
    ],
  )
}

///|
fn execute(matches : @argparse.Matches) -> Result[String, String] {
  let current = match
    site_from(matches, matches, "site-generation", "runtime-revision") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let journal = match open_journal(matches, current) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result = match matches.subcommand {
    Some(("poll-once", _)) => poll_once(matches, journal)
    Some(("force-loss", child)) =>
      match int64_option(matches, "max-record-bytes") {
        Ok(max_record_bytes) => force_loss(child, journal, max_record_bytes)
        Err(issue) => Err(issue)
      }
    Some(("restart", child)) => {
      let next = match
        site_from(matches, child, "next-generation", "next-runtime-revision") {
        Ok(value) => value
        Err(issue) => {
          ignore(journal.close())
          return Err(issue)
        }
      }
      match journal.restart(next) {
        Ok(count) => Ok("{\"reconciled_records\":" + count.to_string() + "}")
        Err(issue) => Err("restart " + journal_issue_code(issue))
      }
    }
    Some((name, _)) => Err("unsupported operation " + name)
    None => Err("missing operation")
  }
  if !journal.close() {
    return match result {
      Ok(_) => Err("journal close failed")
      Err(issue) => Err(issue + "; journal close failed")
    }
  }
  result
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  match execute(matches) {
    Ok(value) => println(value)
    Err(issue) => abort("actql-native-remote-site: " + issue)
  }
}
