///|
// One metadata export over the existing filesystem Writer. This caller record
// owns actual partial acquisitions; a receipt string is neither a Writer ACK
// nor permission to resend an output whose attempt already exists.
priv struct LocalResultReceiptOutput {
  location : LocalProductLocation
  mut root : @local_filesystem.Root?
  mut root_failure : @local_filesystem.NativeRootOpenFailure?
  mut writer : @local_filesystem.Writer?
  mut writer_failure : @local_filesystem.NativeWriterOpenFailure?
  mut attempted : Bool
  mut closed : Bool
}

///|
let result_receipt_output : Ref[LocalResultReceiptOutput?] = Ref(None)

///|
let command_result_delivery_failed : Ref[Bool] = Ref(false)

///|
fn LocalResultReceiptOutput::close(
  self : LocalResultReceiptOutput,
) -> Result[Unit, @local_filesystem.NativeFilesystemIssue] {
  if self.closed {
    return Ok(())
  }
  if self.writer_failure is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.writer_failure = None
      Err(issue) => return Err(issue)
    }
  }
  if self.writer is Some(writer) {
    let result = if self.attempted {
      writer.close_retaining_files()
    } else {
      writer.cancel()
    }
    match result {
      Ok(_) => self.writer = None
      Err(issue) => return Err(issue)
    }
  }
  if self.root_failure is Some(original) {
    match original.retry_cleanup() {
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
fn local_finish_result_receipt() -> Result[
  Unit,
  @local_filesystem.NativeFilesystemIssue,
] {
  if result_receipt_output.val is Some(original) {
    match original.close() {
      Ok(_) => result_receipt_output.val = None
      Err(issue) => return Err(issue)
    }
  }
  Ok(())
}

///|
fn local_write_result_receipt(
  path : String,
  body : String,
  crypto : @local_crypto.Library,
) -> Unit raise ClientStop {
  if result_receipt_output.val is Some(_) {
    stop("ResultReceiptCleanupPending")
  }
  let bytes = @utf8.encode(body)
  if bytes.length() > 65536 {
    stop("ResultReceiptExportTooLarge")
  }
  let location = local_product_selected_location(Some(path), None)
  let original : LocalResultReceiptOutput = {
    location,
    root: None,
    root_failure: None,
    writer: None,
    writer_failure: None,
    attempted: false,
    closed: false,
  }
  result_receipt_output.val = Some(original)
  let root = match
    @local_filesystem.open_root_with_custody(location.parent_path) {
    Ok(value) => value
    Err(failure) => {
      original.root_failure = Some(failure)
      stop("ResultReceiptOpenFailed")
    }
  }
  original.root = Some(root)
  let observation = root
    .observe_directory()
    .unwrap_or_else(_ => stop("ResultReceiptOpenFailed"))
  let identity = observation
    .identity()
    .unwrap_or_else(_ => stop("ResultReceiptOpenFailed"))
  match root.inspect_generation(location.directory_name) {
    Ok(None) => ()
    Ok(Some(_)) => stop("ResultReceiptDestinationExists")
    Err(_) => stop("ResultReceiptOpenFailed")
  }
  let staging = ".actql-receipt-" + local_generation_cid(crypto)[7:].to_owned()
  let writer = match root.create_writer_with_custody(staging, 65536L) {
    Ok(value) => value
    Err(failure) => {
      original.writer_failure = Some(failure)
      stop("ResultReceiptOpenFailed")
    }
  }
  original.writer = Some(writer)
  if !(observation.identity() is Ok(actual) && actual == identity) {
    stop("ResultReceiptDestinationChanged")
  }
  original.attempted = true
  if writer.append(bytes) is Err(_) {
    stop("ResultReceiptWriteUnknown")
  }
  let generation = writer
    .seal(location.directory_name)
    .unwrap_or_else(_ => stop("ResultReceiptWriteUnknown"))
  if !root.verify_generation(location.directory_name, generation) ||
    !(observation.identity() is Ok(actual) && actual == identity) {
    stop("ResultReceiptWriteUnknown")
  }
  if local_finish_result_receipt() is Err(_) {
    stop("ResultReceiptCleanupPending")
  }
}
