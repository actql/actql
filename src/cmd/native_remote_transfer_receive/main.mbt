///|
priv suberror CommandStop {
  CommandStop(String)
}

///|
fn[T] stop(message : String) -> T raise CommandStop {
  raise CommandStop(message)
}

///|
fn required(
  matches : @argparse.Matches,
  name : String,
) -> String raise CommandStop {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => value
    _ => stop("missing or repeated option --" + name)
  }
}

///|
fn optional(matches : @argparse.Matches, name : String) -> String {
  match matches.values.get(name) {
    Some([value]) => value
    _ => ""
  }
}

///|
fn fetch_contract_body(
  matches : @argparse.Matches,
  url : String,
  max_bytes : Int64,
) -> String raise CommandStop {
  let library = match @http.load_library(required(matches, "http-library")) {
    Ok(value) => value
    Err(_) => stop("HTTP library load failed")
  }
  let client = match
    library.create_client(
      required(matches, "ca"),
      required(matches, "cert"),
      required(matches, "key"),
      max_bytes,
      2000,
      30000,
    ) {
    Ok(value) => value
    Err(_) => stop("HTTP client creation failed")
  }
  let response = client.request(@http.Get, url, [], b"")
  let closed = client.close()
  guard response is Ok(value) && value.status == 200 && closed else {
    stop("Transfer contract fetch failed")
  }
  @utf8.decode(value.body) catch {
    _ => stop("Transfer contract is not UTF-8")
  }
}

///|
fn required_int(
  matches : @argparse.Matches,
  name : String,
) -> Int raise CommandStop {
  let value : Int = @string.from_str(required(matches, name)) catch {
    _ => stop("invalid integer option --" + name)
  }
  value
}

///|
fn required_int64(
  matches : @argparse.Matches,
  name : String,
) -> Int64 raise CommandStop {
  let value : Int64 = @string.from_str(required(matches, name)) catch {
    _ => stop("invalid integer option --" + name)
  }
  value
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "actql-native-remote-transfer-receive",
    about="Receive one durable Store Transfer into a native Site",
    version="0.1",
    options=[
      @argparse.OptionArg("sqlite-library", required=true),
      @argparse.OptionArg("http-library", required=true),
      @argparse.OptionArg("journal", required=true),
      @argparse.OptionArg("root", required=true),
      @argparse.OptionArg("origin", required=true),
      @argparse.OptionArg("ca", required=true),
      @argparse.OptionArg("cert", required=true),
      @argparse.OptionArg("key", required=true),
      @argparse.OptionArg("request-root", default_values=[""]),
      @argparse.OptionArg("request-file", default_values=["request.json"]),
      @argparse.OptionArg("manifest-file", default_values=["manifest.json"]),
      @argparse.OptionArg("request-url", default_values=[""]),
      @argparse.OptionArg("manifest-url", default_values=[""]),
      @argparse.OptionArg("request-cid", required=true),
      @argparse.OptionArg("manifest-cid", required=true),
      @argparse.OptionArg("use-id", required=true),
      @argparse.OptionArg("mode", default_values=["receive"]),
      @argparse.OptionArg("max-record-bytes", default_values=["1048576"]),
      @argparse.OptionArg("max-chunks", default_values=["65536"]),
      @argparse.OptionArg("max-manifest-bytes", default_values=["1048576"]),
      @argparse.OptionArg("max-bytes", default_values=["268435456"]),
      @argparse.OptionArg("max-objects", default_values=["65536"]),
      @argparse.OptionArg("max-binding-bytes", default_values=["1048576"]),
    ],
  )
}

///|
fn execute_checked(matches : @argparse.Matches) -> Unit raise CommandStop {
  let max_record_bytes = required_int64(matches, "max-record-bytes")
  let max_chunks = required_int(matches, "max-chunks")
  let max_manifest_bytes = required_int(matches, "max-manifest-bytes")
  let max_bytes = required_int64(matches, "max-bytes")
  let max_objects = required_int64(matches, "max-objects")
  let max_binding_bytes = required_int(matches, "max-binding-bytes")
  if max_record_bytes < 1L ||
    max_chunks < 1 ||
    max_manifest_bytes < 1 ||
    max_bytes < 1L ||
    max_objects < 1L ||
    max_binding_bytes < 1 {
    stop("invalid Transfer limits")
  }
  let request_root = optional(matches, "request-root")
  let request_url = optional(matches, "request-url")
  let manifest_url = optional(matches, "manifest-url")
  let use_network = !request_url.is_empty() && !manifest_url.is_empty()
  if use_network == !request_root.is_empty() ||
    request_url.is_empty() != manifest_url.is_empty() {
    stop("select exactly one Transfer contract source")
  }
  let request_body = if use_network {
    fetch_contract_body(matches, request_url, max_record_bytes)
  } else {
    match
      @bounded_files.read_bounded_text_file(
        request_root,
        required(matches, "request-file"),
        max_record_bytes,
      ) {
      Ok(value) => value
      Err(_) => stop("failed to read Transfer request")
    }
  }
  let manifest_body = if use_network {
    fetch_contract_body(matches, manifest_url, max_manifest_bytes.to_int64())
  } else {
    match
      @bounded_files.read_bounded_text_file(
        request_root,
        required(matches, "manifest-file"),
        max_manifest_bytes.to_int64(),
      ) {
      Ok(value) => value
      Err(_) => stop("failed to read Transfer manifest")
    }
  }
  let request = match
    @transfer.admit_request_json(
      request_body,
      manifest_body,
      required(matches, "request-cid"),
      required(matches, "manifest-cid"),
      max_chunks,
      max_manifest_bytes,
      max_bytes,
    ) {
    Ok(value) => value
    Err(_) => stop("Transfer request admission failed")
  }
  let sqlite_library = match
    @sqlite.load_library(required(matches, "sqlite-library")) {
    Ok(value) => value
    Err(_) => stop("SQLite library load failed")
  }
  let transfer_journal = match
    @journal.open_journal(
      sqlite_library,
      required(matches, "journal"),
      max_record_bytes,
      max_chunks,
      max_manifest_bytes,
      max_bytes,
    ) {
    Ok(value) => value
    Err(_) => stop("Transfer journal open failed")
  }
  let destination_root = match
    @filesystem.open_root(required(matches, "root")) {
    Ok(value) => value
    Err(_) => {
      ignore(transfer_journal.close())
      stop("Transfer root open failed")
    }
  }
  let use_id = required(matches, "use-id")
  let mode = required(matches, "mode")
  if mode == "reclaim" {
    let receipt = match transfer_journal.inspect_destination_receipt(request) {
      Ok(Some(value)) => value
      _ => {
        ignore(transfer_journal.close())
        stop("destination receipt is unavailable")
      }
    }
    let material = match
      @client.pin_durable_store_destination_material(
        transfer_journal,
        destination_root,
        request,
        use_id,
        "native-transfer-reclaim",
        @transfer.destination_receipt_cid(receipt),
      ) {
      Ok(value) => value
      Err(_) => {
        ignore(transfer_journal.close())
        stop("destination material pin failed")
      }
    }
    match @client.validate_destination_material_use(material) {
      Ok(_) => ()
      Err(_) => {
        ignore(@client.release_destination_material_use(material))
        ignore(transfer_journal.close())
        stop("destination material validation failed")
      }
    }
    match @client.reclaim_durable_store_destination_material(material) {
      Ok(_) => ()
      Err(_) => {
        ignore(transfer_journal.close())
        stop("destination material reclaim failed")
      }
    }
    if !transfer_journal.close() {
      stop("Transfer journal cleanup remains pending")
    }
    println("{\"reclaimed\":true}")
    return
  }
  if mode != "receive" {
    ignore(transfer_journal.close())
    stop("invalid Transfer operation")
  }
  let http_library = match
    @http.load_library(required(matches, "http-library")) {
    Ok(value) => value
    Err(_) => {
      ignore(transfer_journal.close())
      stop("HTTP library load failed")
    }
  }
  let http_client = match
    http_library.create_client(
      required(matches, "ca"),
      required(matches, "cert"),
      required(matches, "key"),
      max_record_bytes,
      2000,
      30000,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(transfer_journal.close())
      stop("HTTP client creation failed")
    }
  }
  let received = @client.receive_durable_store_transfer(
    transfer_journal,
    http_client,
    destination_root,
    required(matches, "origin"),
    request,
    use_id,
    max_bytes,
    max_objects,
  )
  guard received is Ok(record) &&
    @transfer.record_is_destination_committed(record) else {
    ignore(http_client.close())
    ignore(transfer_journal.close())
    stop("Store Transfer receive failed")
  }
  let receipt = match transfer_journal.inspect_destination_receipt(request) {
    Ok(Some(value)) => value
    _ => {
      ignore(http_client.close())
      ignore(transfer_journal.close())
      stop("destination receipt is unavailable")
    }
  }
  let input = match
    @remote_standard.prepare_native_remote_standard_transfer_input(
      request,
      use_id,
      @transfer.destination_receipt_cid(receipt),
      max_binding_bytes,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(http_client.close())
      ignore(transfer_journal.close())
      stop("standard input binding failed")
    }
  }
  let binding = @remote_standard.native_remote_standard_transfer_binding(input)
  let body = @remote.remote_input_binding_body(binding)
  let close_client = http_client.close()
  let close_journal = transfer_journal.close()
  if !close_client || !close_journal {
    stop("native Transfer receiver cleanup remains pending")
  }
  println(body)
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  execute_checked(matches) catch {
    CommandStop(issue) =>
      abort("actql-native-remote-transfer-receive: " + issue)
  }
}
