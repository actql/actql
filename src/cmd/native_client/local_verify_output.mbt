///|
// A retained caller record over the existing filesystem Root/Reader. Metadata
// and hash equality create no read, delivery, Account or egress authority.
priv struct LocalOutputVerificationFile {
  location : LocalProductLocation
  mut root : @local_filesystem.Root?
  mut root_failure : @local_filesystem.NativeRootOpenFailure?
  mut reader : @local_filesystem.Reader?
  mut reader_failure : @local_filesystem.NativeReaderOpenFailure?
  mut generation : @local_filesystem.NativeFileGeneration?
  mut closed : Bool
}

///|
let output_verification_files : Ref[Array[LocalOutputVerificationFile]] = Ref([])

///|
fn local_output_verification_path(
  directory : String,
  value : String,
) -> String raise ClientStop {
  if value.is_empty() || value.has_suffix("/") {
    stop("InvalidOutputVerificationPath")
  }
  let absolute = local_project_absolute_path(directory, value) catch {
    ClientStop(_) => stop("InvalidOutputVerificationPath")
  }
  if local_product_selected_location(Some(absolute), None).directory_name.length() > 128 {
    stop("InvalidOutputVerificationPath")
  }
  absolute
}

///|
fn local_output_verification_file(
  path : String,
) -> LocalOutputVerificationFile raise ClientStop {
  let location = local_product_selected_location(Some(path), None)
  let original : LocalOutputVerificationFile = {
    location,
    root: None,
    root_failure: None,
    reader: None,
    reader_failure: None,
    generation: None,
    closed: false,
  }
  // Retain before the first constructor; even a failed open may own cleanup.
  if output_verification_files.val.length() >= 2 {
    stop("OutputVerificationAlreadyStarted")
  }
  output_verification_files.val.push(original)
  original
}

///|
fn LocalOutputVerificationFile::open(
  self : LocalOutputVerificationFile,
  maximum : Int64,
) -> Unit raise ClientStop {
  if self.closed || self.root is Some(_) || self.root_failure is Some(_) {
    stop("OutputVerificationAlreadyStarted")
  }
  let root = match
    @local_filesystem.open_root_with_custody(self.location.parent_path) {
    Ok(value) => value
    Err(failure) => {
      self.root_failure = Some(failure)
      stop("OutputVerificationOpenFailed")
    }
  }
  self.root = Some(root)
  let generation = match root.inspect_generation(self.location.directory_name) {
    Ok(Some(value)) if value.size >= 0L && value.size <= maximum => value
    Ok(_) => stop("OutputVerificationInputUnavailable")
    Err(_) => stop("OutputVerificationInputUnavailable")
  }
  self.generation = Some(generation)
  let reader = match
    root.open_reader_with_custody(self.location.directory_name, generation) {
    Ok(value) => value
    Err(failure) => {
      self.reader_failure = Some(failure)
      stop("OutputVerificationReadFailed")
    }
  }
  self.reader = Some(reader)
}

///|
fn LocalOutputVerificationFile::read(
  self : LocalOutputVerificationFile,
  capture : Bool,
) -> (Bytes, Int64, String) raise ClientStop {
  guard !self.closed &&
    self.reader is Some(reader) &&
    self.generation is Some(generation) &&
    self.root is Some(root) else {
    stop("OutputVerificationReadUnavailable")
  }
  let bytes : Array[Byte] = Array::make(
    if capture {
      generation.size.to_int()
    } else {
      0
    },
    0,
  )
  let digest = @sha.hasher()
  let mut count = 0L
  // The original generation bounds both total bytes and calls, including one
  // EOF observation. Empty non-EOF chunks cannot turn this into an open loop.
  let maximum_calls = generation.size + 1L
  let mut complete = false
  for _ in 0..<maximum_calls.to_int() {
    let chunk = match reader.next(16384) {
      Ok(value) => value
      Err(_) => stop("OutputVerificationReadFailed")
    }
    if chunk.bytes.length().to_int64() > generation.size - count ||
      (chunk.bytes.is_empty() && !chunk.eof) {
      stop("OutputVerificationInputChanged")
    }
    if capture {
      for index in 0..<chunk.bytes.length() {
        bytes[count.to_int() + index] = chunk.bytes[index]
      }
    }
    @sha.update(digest, chunk.bytes) catch {
      _ => stop("OutputVerificationDigestFailed")
    }
    count += chunk.bytes.length().to_int64()
    if chunk.eof {
      complete = true
      break
    }
  }
  if !complete ||
    count != generation.size ||
    reader.finish() is Err(_) ||
    !root.verify_generation(self.location.directory_name, generation) {
    stop("OutputVerificationInputChanged")
  }
  let hash = @sha.finish_hex(digest) catch {
    _ => stop("OutputVerificationDigestFailed")
  }
  (Bytes::from_array(bytes), count, hash)
}

///|
fn LocalOutputVerificationFile::close(
  self : LocalOutputVerificationFile,
) -> Result[Unit, @local_filesystem.NativeFilesystemIssue] {
  if self.closed {
    return Ok(())
  }
  if self.reader_failure is Some(failure) {
    match failure.retry_cleanup() {
      Ok(_) => self.reader_failure = None
      Err(issue) => return Err(issue)
    }
  }
  if self.reader is Some(reader) {
    match reader.close() {
      Ok(_) => self.reader = None
      Err(issue) => return Err(issue)
    }
  }
  if self.root_failure is Some(failure) {
    match failure.retry_cleanup() {
      Ok(_) => self.root_failure = None
      Err(issue) => return Err(issue)
    }
  }
  if self.root is Some(root) {
    match root.close() {
      Ok(_) => self.root = None
      Err(issue) => return Err(issue)
    }
  }
  self.closed = true
  Ok(())
}

///|
fn local_finish_output_verification() -> Result[
  Unit,
  @local_filesystem.NativeFilesystemIssue,
] {
  for original in output_verification_files.val {
    match original.close() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  output_verification_files.val = []
  Ok(())
}

///|
fn local_verify_output_command(
  parent : @argparse.Matches,
) -> String raise ClientStop {
  guard parent.subcommand is Some(("output", child)) else {
    stop("OutputVerificationSelectionRequired")
  }
  if !output_verification_files.val.is_empty() {
    stop("OutputVerificationAlreadyStarted")
  }
  let directory = @env.current_dir().unwrap_or_else(() => {
    stop("OutputVerificationDirectoryUnavailable")
  })
  let receipt_path = local_output_verification_path(
    directory,
    required(child, "receipt"),
  )
  let output_path = local_output_verification_path(
    directory,
    required(child, "output"),
  )
  let receipt_file = local_output_verification_file(receipt_path)
  receipt_file.open(65536L)
  let (receipt_bytes, _, _) = receipt_file.read(true)
  let wire = @utf8.decode(receipt_bytes) catch {
    _ => stop("InvalidResultDeliveryReceiptContainer")
  }
  // Validate every object and self-CID before opening the explicit output.
  let receipts = @run_host.admit_client_result_delivery_receipts(wire).unwrap_or_else(() => {
      stop("InvalidResultDeliveryReceiptContainer")
    },
  )
  if receipts.count() == 0 {
    stop("ResultDeliveryReceiptOutputMismatch")
  }
  let output = local_output_verification_file(output_path)
  output.open(536870912L)
  let (_, count, digest) = output.read(false)
  let matches = receipts
    .matching_identities(count, digest)
    .unwrap_or_else(() => stop("ResultDeliveryReceiptOutputMismatch"))
  if child.flags.get("json").unwrap_or(false) {
    let report = Json::object(
      Map::from_array([
        ("verified", Json::boolean(true)),
        ("byte_count", Json::number(count.to_double())),
        ("sha256", Json::string(digest)),
        ("supplied_receipt_count", Json::number(receipts.count().to_double())),
        ("matching_receipt_count", Json::number(matches.length().to_double())),
        ("receipt_cids", Json::array(matches.map(Json::string))),
      ]),
    )
    encode_request_json(report, 65536)
  } else {
    "verified output; matching receipts=" +
    matches.length().to_string() +
    "; supplied receipts=" +
    receipts.count().to_string()
  }
}
