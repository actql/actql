///|
const LOCAL_CSV_OFFER_KIND : Int = 20

///|
const LOCAL_CSV_RESPONSE_KIND : Int = 21

///|
priv enum SDKLocalCsvReadPhase {
  AwaitingOffer
  PreparingOffer
  Offered(Int)
  ReservingExtent
  ReadyToRead(Int, Int64)
  Supplying(Int64?)
  Received
  Failed(Int, Int64?)
}

///|
priv struct StoredSDKLocalCsvRead {
  capture : Int
  root : String
  path : String
  max_bytes : Int
  selected : @host.ClientProjectLocalCsvSelection
  mut response : @row_host.LocalCsvWholeResponse?
  mut phase : SDKLocalCsvReadPhase
}

///|
priv struct StoredSDKWholeSourceTransfer {
  mut capture : Int?
  mut csv_read : StoredSDKLocalCsvRead?
}

///|
fn sdk_whole_source_transfer(start : StoredPhysicalStart) -> StoredSDKWholeSourceTransfer? {
  match (start.file_managed, start.model_file) {
    (Some(file), None) if !file.closing => Some(file.source)
    (None, Some(model)) => Some(model.source)
    _ => None
  }
}

///|
/// Retain the exact claimed Source before exposing its physical locator.
/// The regular file cannot open until the original RowRun funds its extent.
fn open_sdk_local_csv_rows(
  source : StoredSDKWholeSourceTransfer,
  owner : @local_host.ClientInstalledManagedRun,
  prepared : @host.PreparedClientProgram,
  request : @host.ClientRequestIdentity,
  child : StoredMockEffectCapture,
  selected : @host.ClientProjectLocalCsvSelection,
  handle : Int,
) -> Int {
  guard source.capture == Some(handle) && source.csv_read is None else { return -2 }
  let declared = selected.source_acquisition()
  let declaration = selected.declaration()
  let (read, original, acquisition, _) = match
    @local_host.begin_installed_managed_whole_source_read(
      owner,
      prepared,
      request,
      declaration,
    ) {
    Ok(read) => read
    Err(AlreadyBound) => return -35
    Err(InsufficientCapacity | MetadataCapacityUnavailable) => return -4
    Err(_) => return -20
  }
  child.read = Some(read)
  child.acquisition = Some(acquisition)
  guard physical_equal(original, declared) else { return -2 }
  let (root, path) = selected.file_locator()
  source.csv_read = Some({
    capture: handle,
    root,
    path,
    max_bytes: selected.transport().transfer_bytes.to_int(),
    selected,
    response: None,
    phase: AwaitingOffer,
  })
  0
}

///|
/// The same Source gets its RowRun and starts a funded page only after the
/// original Host returns the fenced file extent. No file bytes have crossed.
fn fund_sdk_local_csv_extent(
  value : Instance,
  csv : StoredSDKLocalCsvRead,
  child : StoredMockEffectCapture,
  extent : Int64,
) -> Int {
  guard child.read is Some(read) &&
    child.acquisition is Some(acquisition) &&
    value.physical_starts.get(child.start) is Some(custody) &&
    sdk_whole_source_transfer(custody) is Some(source) &&
    value.original_metadata.get(csv.capture) is Some(record) &&
    value.copies.get(record.input) is Some((_, physical)) &&
    csv.selected.observed_extent_transport(extent) is Some((quote, _)) else {
    return -35
  }
  let geometry = @row_host.row_input_acquisition_limits(acquisition)
  let run = match
    @local_host.start_installed_whole_source_read_rows(
      read,
      acquisition,
      "local-csv",
      _ => {
        sdk_local_csv_capture_owner_current(
          value,
          child.start,
          custody,
          source,
          csv.capture,
        )
      },
      quote.transfer_bytes,
      Int64::max(quote.execution_bytes, geometry.page.max_bytes.to_int64()),
    ) {
    Ok(run) => run
    Err(Acquisition(issue)) => return mock_effect_capture_issue(issue)
    Err(_) => return -23
  }
  child.rows = Some(run)
  match
    @row_host.begin_row_run_with_page_limits(
      run,
      geometry.page,
      geometry.max_rows,
    ) {
    Err(issue) => return mock_effect_capture_issue(issue)
    Ok(_) => ()
  }
  let response = match
    @row_host.borrow_row_input_run_responses(run, acquisition) {
    Ok(response) => response
    Err(issue) => return mock_effect_capture_issue(issue)
  }
  match
    @row_host.bind_row_run_response_borrow_cleanup(response, () => {
      physical_reader_stop(physical, csv.capture) == 0
    }) {
    Ok(_) => ()
    Err(issue) => return mock_effect_capture_issue(issue)
  }
  let prepared = match csv.selected.prepare_response(response, observed_bytes=Some(extent)) {
    Ok((root, path, prepared)) if root == csv.root && path == csv.path => prepared
    Ok(_) => return -35
    Err(issue) => return local_csv_capture_issue(issue)
  }
  csv.response = Some(prepared)
  match @row_host.begin_local_csv_whole_response(prepared) {
    Ok(_) => ()
    Err(issue) => return local_csv_capture_issue(issue)
  }
  0
}

///|
fn sdk_local_csv_capture_owner_current(
  value : Instance,
  start : Int,
  custody : StoredPhysicalStart,
  source : StoredSDKWholeSourceTransfer,
  capture : Int,
) -> Bool {
  value.physical_starts.get(start) is Some(active) &&
  physical_equal(active, custody) &&
  sdk_whole_source_transfer(active) is Some(current) &&
  physical_equal(current, source) &&
  source.capture == Some(capture)
}

///|
fn retained_sdk_local_csv_capture(
  value : Instance,
  capture : Int,
) -> Result[(StoredSDKLocalCsvRead, StoredMockEffectCapture), Int] {
  guard value.original_metadata.get(capture) is Some(original) &&
    original.kind == MOCK_EFFECT_SOURCE_CAPTURE_KIND &&
    original.invoked &&
    !original.output_closed &&
    original.project is Some(FileCapture(child)) &&
    value.physical_starts.get(child.start) is Some(custody) &&
    sdk_whole_source_transfer(custody) is Some(source) &&
    source.capture == Some(capture) &&
    source.csv_read is Some(csv) &&
    csv.capture == capture else {
    return Err(-2)
  }
  Ok((csv, child))
}

///|
fn sdk_local_csv_capture_current(
  value : Instance,
  capture : Int,
) -> Result[(StoredSDKLocalCsvRead, StoredMockEffectCapture), Int] {
  let (csv, child) = match retained_sdk_local_csv_capture(value, capture) {
    Ok(original) => original
    Err(code) => return Err(code)
  }
  guard value.physical_starts.get(child.start) is Some(start) else { return Err(-2) }
  let source = match start.model_file {
    Some(_) =>
      match portable_model_file_source_current(value, child.start) {
        Ok((_, work)) => work.source
        Err(code) => return Err(code)
      }
    None =>
      match sdk_file_source_current(value, child.start) {
        Ok((_, work, _, _, LocalCsv(_))) => work.source
        Ok(_) => return Err(-35)
        Err(code) => return Err(code)
      }
  }
  guard source.capture == Some(capture) &&
    source.csv_read is Some(actual) &&
    physical_equal(actual, csv) else {
    return Err(-35)
  }
  Ok((csv, child))
}

///|
fn local_csv_capture_issue(issue : @row_host.LocalCsvWholeResponseIssue) -> Int {
  match issue {
    Csv(_) => -31
    Row(cause) => mock_effect_capture_issue(cause)
  }
}

///|
fn local_csv_offer_wire(
  value : Instance,
  child : StoredMockEffectCapture,
  source : StoredSDKLocalCsvRead,
) -> Result[Bytes, Int] {
  let bytes = 6L *
    (source.root.length().to_int64() + source.path.length().to_int64()) +
    96L
  guard bytes <= 65536L &&
    @encode.text_writer_construction_inventory(bytes.to_int(), 4, 1)
    is Some(inventory) &&
    fund_mock_effect_capture(
      value,
      child,
      Some({
        record_headers: inventory.record_headers,
        reference_slots: inventory.reference_slots,
        scalar_words: inventory.scalar_words,
        owned_utf16_units: inventory.owned_utf16_units,
        owned_wire_bytes: bytes,
      }),
    ) else {
    return Err(-4)
  }
  try {
    let writer = @encode.writer(bytes.to_int(), 4, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "root")
    @encode.string_value(writer, source.root)
    @encode.key(writer, "path")
    @encode.string_value(writer, source.path)
    @encode.key(writer, "max_bytes")
    @encode.decimal_number_value(writer, source.max_bytes.to_string())
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(-31)
  }
}

///|
/// Publish the descriptor only after one existing RowRun enters its paid
/// transfer. The original open can then happen outside the Wasm call.
fn produce_sdk_local_csv_offer(
  value : Instance,
  handle : Int,
  record : StoredOriginalMetadata,
  wire : Bytes,
) -> Int {
  guard wire.length() == 4 else { return -31 }
  let capture = mock_effect_descriptor_field(wire, 0)
  let (csv, child) = match sdk_local_csv_capture_current(value, capture) {
    Ok(current) => current
    Err(code) => return code
  }
  guard csv.phase is AwaitingOffer else { return -33 }
  record.project = Some(LocalCsvOffer(capture))
  csv.phase = PreparingOffer
  let descriptor = match local_csv_offer_wire(value, child, csv) {
    Ok(descriptor) => descriptor
    Err(code) => return code
  }
  match sdk_local_csv_capture_current(value, capture) {
    Err(code) => return code
    Ok((active, original)) => {
      guard physical_equal(active, csv) &&
        physical_equal(original, child) &&
        csv.phase is PreparingOffer else {
        return -2
      }
    }
  }
  // Retain the fact that a physical offer may escape before output is supplied.
  // A trap after this latch leaves an uncertain read until observed or closed.
  csv.phase = Offered(handle)
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, descriptor),
  )
  if code == 0 {
    record.produced = true
  }
  code
}

///|
priv enum SDKLocalCsvDelivery {
  Complete(BytesView)
  Extent(Int64)
  FailedKnown(Int64)
  FailedUnknown
}

///|
fn sdk_local_csv_delivery(wire : Bytes, maximum : Int) -> SDKLocalCsvDelivery? {
  guard wire.length() >= 12 else { return None }
  let disposition = mock_effect_descriptor_field(wire, 4)
  let count = mock_effect_descriptor_field(wire, 8)
  guard count >= 0 && count <= maximum else { return None }
  match disposition {
    0 if wire.length() - 12 == count => Some(Complete(wire[12:]))
    1 if wire.length() == 12 => Some(FailedKnown(count.to_int64()))
    2 if wire.length() == 12 && count == 0 => Some(FailedUnknown)
    3 if wire.length() == 12 => Some(Extent(count.to_int64()))
    _ => None
  }
}

///|
/// Consume the exact offered response once. No error makes the offer
/// reusable, and an uncertain response never permits a capture to start.
fn produce_sdk_local_csv_response(
  value : Instance,
  record : StoredOriginalMetadata,
  wire : Bytes,
) -> Int {
  guard wire.length() >= 12 else { return -31 }
  let offer = mock_effect_descriptor_field(wire, 0)
  guard value.original_metadata.get(offer) is Some(original) &&
    original.kind == LOCAL_CSV_OFFER_KIND &&
    original.produced &&
    !original.output_closed &&
    original.project is Some(LocalCsvOffer(capture)) else {
    return -2
  }
  let (csv, child) = match retained_sdk_local_csv_capture(value, capture) {
    Ok(current) => current
    Err(code) => return code
  }
  let extent_stage = match csv.phase {
    Offered(chosen) if chosen == offer => true
    ReadyToRead(chosen, _) if chosen == offer => false
    _ => return -33
  }
  record.project = Some(LocalCsvResponse(offer))
  guard sdk_local_csv_delivery(wire, csv.max_bytes) is Some(delivery) else {
    csv.phase = Failed(-31, None)
    return -31
  }
  if extent_stage {
    guard delivery is Extent(extent) else {
      let code = if delivery is FailedKnown(0L) { -23 } else { -36 }
      csv.phase = Failed(code, Some(0L))
      return code
    }
    csv.phase = ReservingExtent
    let code = fund_sdk_local_csv_extent(value, csv, child, extent)
    if code != 0 {
      csv.phase = Failed(code, Some(0L))
      return code
    }
    match sdk_local_csv_capture_current(value, capture) {
      Ok((active, original)) if physical_equal(active, csv) &&
        physical_equal(original, child) => ()
      Err(code) => {
        csv.phase = Failed(code, Some(0L))
        return code
      }
      _ => {
        csv.phase = Failed(-35, Some(0L))
        return -35
      }
    }
    let code = status(@buffers.supply_buffer_output(value.pool, record.slot, b""))
    csv.phase = if code == 0 { ReadyToRead(offer, extent) } else {
      Failed(code, Some(0L))
    }
    if code == 0 { record.produced = true }
    return code
  }
  guard csv.phase is ReadyToRead(_, extent) &&
    csv.response is Some(response) &&
    child.rows is Some(rows) else { return -33 }
  match delivery {
    Complete(bytes) if bytes.length().to_int64() != extent => {
      csv.phase = Failed(-35, None)
      return -35
    }
    Extent(_) => return -33
    _ => ()
  }
  let observed = match delivery {
    Complete(bytes) => Some(bytes.length().to_int64())
    FailedKnown(count) => Some(count)
    FailedUnknown => None
    Extent(_) => return -33
  }
  csv.phase = Supplying(observed)
  // Preserve the measured transfer even if currentness fails after physical
  // return. Only the same still-current owner can decode or retain rows.
  let current = match sdk_local_csv_capture_current(value, capture) {
    Err(code) => code
    Ok((active, original)) =>
      if physical_equal(active, csv) && physical_equal(original, child) {
        0
      } else {
        -2
      }
  }
  if current != 0 {
    csv.phase = Failed(current, observed)
    return current
  }
  let code = match delivery {
    Complete(bytes) =>
      accept_sdk_local_csv_response(value, csv, child, rows, response, bytes)
    FailedKnown(known) =>
      match @row_host.fail_local_csv_whole_response(response, Some(known)) {
        Ok(_) => -23
        Err(issue) => local_csv_capture_issue(issue)
      }
    FailedUnknown =>
      match @row_host.fail_local_csv_whole_response(response, None) {
        Ok(_) => -36
        Err(issue) => local_csv_capture_issue(issue)
      }
    Extent(_) => -33
  }
  if code != 0 {
    csv.phase = Failed(code, observed)
    return code
  }
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, b""))
  csv.phase = if code == 0 { Received } else { Failed(code, observed) }
  if code == 0 {
    record.produced = true
  }
  code
}

///|
fn accept_sdk_local_csv_response(
  value : Instance,
  csv : StoredSDKLocalCsvRead,
  child : StoredMockEffectCapture,
  rows : @row_host.RowRun,
  response : @row_host.LocalCsvWholeResponse,
  bytes : BytesView,
) -> Int {
  match
    @row_host.accept_local_csv_whole_response(response, bytes.to_owned()) {
    Err(issue) => return local_csv_capture_issue(issue)
    Ok(_) => ()
  }
  match sdk_local_csv_capture_current(value, csv.capture) {
    Err(code) => return code
    Ok((active, original)) => {
      guard physical_equal(active, csv) && physical_equal(original, child) else {
        return -2
      }
    }
  }
  match @row_host.finish_row_run(rows) {
    Err(issue) => return mock_effect_capture_issue(issue)
    Ok(_) => ()
  }
  match @row_host.begin_row_capture(rows) {
    Err(issue) => return mock_effect_capture_issue(issue)
    Ok(_) => ()
  }
  child.advancing = true
  0
}

///|
fn retire_sdk_local_csv_read(
  value : Instance,
  start : Int,
  capture : Int,
) -> Int {
  guard value.physical_starts.get(start) is Some(custody) &&
    sdk_whole_source_transfer(custody) is Some(source) else {
    return -9
  }
  guard source.csv_read is Some(csv) else { return 0 }
  guard csv.capture == capture else { return -2 }
  let observed = match csv.phase {
    AwaitingOffer | PreparingOffer | Offered(_) | ReservingExtent => Some(0L)
    Supplying(observed) | Failed(_, observed) => observed
    ReadyToRead(_, _) | Received => None
  }
  guard csv.response is Some(response) else {
    source.csv_read = None
    return 0
  }
  match @row_host.retire_local_csv_whole_response(response, observed) {
    Ok(_) => {
      source.csv_read = None
      0
    }
    Err(issue) => local_csv_capture_issue(issue)
  }
}
