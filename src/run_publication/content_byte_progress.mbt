///|
/// Common byte generation under the publication owner. Provisional pieces are
/// not ContentRefs: the barrier owns order/policy, input custody, reservations,
/// durable Store I/O and issuance after verified completion.
struct ContentByteEncoder {
  profile : ContentSerializationProfile
  max_rows : Int
  max_bytes : Int
  max_value_nodes : Int
  max_value_depth : Int
  max_frames : Int
  hash : @sha.Hasher
  mut rows : Int
  mut bytes : Int
  mut phase : Int
  mut column : Int
  mut printed : Int
  mut header_position : Int
  mut header_quoted : Bool
  mut next_phase : Int
  mut cell : @admitted.CheckedValue?
  mut cells : ((Int) -> @admitted.CheckedValue?)?
  mut runtime_cells : ((Int) -> ContentInputCell)?
  mut input_available : (() -> Bool)?
  mut source_available : (() -> Bool)?
  mut expected_rows : Int?
  mut recheck : @admitted.RecheckCursor?
  mut equality : @contract.TypeEquality?
  mut text : CsvQuotedText?
  mut wire : @admitted.WireEmitCursor?
  mut writer : @encode.Writer?
  mut error : ContentSerializationIssue?
  mut completion : ContentByteCompletion?
}

///|
/// Representation failure is not an absent Conditional field. The retained
/// input owner supplies this distinction; no scalar Missing value is added.
pub(all) enum ContentInputCell {
  ContentAbsent
  ContentPresent(@admitted.Value)
  // Raw immutable Text enters the shared cursor without a synchronous scan.
  ContentText(String)
  ContentInputUnavailable
}

///|
pub enum ContentBytePoll {
  ContentBytesContinue(String, work~ : Int)
  ContentBytesReady(String, work~ : Int)
  ContentBytesFailed(ContentSerializationIssue, work~ : Int)
}

///|
pub(all) struct ContentByteCompletion {
  name : String
  media_type : String
  size_bytes : Int
  row_count : Int
  content_cid : String
} derive(Eq, Debug)

///|
pub fn start_content_byte_encoder(
  profile : ContentSerializationProfile,
  max_rows~ : Int,
  max_bytes~ : Int,
  max_value_nodes~ : Int,
  max_value_depth~ : Int,
  max_frames~ : Int,
) -> Result[ContentByteEncoder, ContentSerializationIssue] {
  if max_rows < 0 ||
    max_bytes < 0 ||
    max_value_nodes < 1 ||
    max_value_depth < 0 ||
    max_frames < 1 {
    return Err(ContentInvalidLimits)
  }
  Ok({
    profile,
    max_rows,
    max_bytes,
    max_value_nodes,
    max_value_depth,
    max_frames,
    hash: @sha.hasher(),
    rows: 0,
    bytes: 0,
    phase: 0,
    column: 0,
    printed: 0,
    header_position: 0,
    header_quoted: false,
    next_phase: 4,
    cell: None,
    cells: None,
    runtime_cells: None,
    input_available: None,
    source_available: None,
    expected_rows: None,
    recheck: None,
    equality: None,
    text: None,
    wire: None,
    writer: None,
    error: None,
    completion: None,
  })
}

///|
fn clear_content_byte_input(owner : ContentByteEncoder) -> Unit {
  if owner.recheck is Some(cursor) {
    @admitted.cancel_recheck_runtime_value(cursor)
  }
  if owner.equality is Some(cursor) {
    @contract.cancel_type_equality(cursor)
  }
  if owner.text is Some(cursor) {
    cancel_csv_quoted_text(cursor)
  }
  if owner.wire is Some(cursor) {
    @admitted.cancel_wire_emit(cursor)
  }
  if owner.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  owner.equality = None
  owner.text = None
  owner.wire = None
  owner.writer = None
  owner.cell = None
  owner.cells = None
  owner.runtime_cells = None
  owner.input_available = None
  owner.recheck = None
}

///|
/// Input release and physical sink cleanup remain with the caller's owner.
/// Cancelling this byte cursor is not a physical release confirmation.
pub fn cancel_content_byte_encoder(owner : ContentByteEncoder) -> Unit {
  clear_content_byte_input(owner)
  owner.source_available = None
  owner.phase = 91
  if owner.error is None {
    owner.error = Some(ContentClosed)
  }
}

///|
fn fail_content_bytes(
  owner : ContentByteEncoder,
  issue : ContentSerializationIssue,
) -> Unit {
  clear_content_byte_input(owner)
  owner.source_available = None
  owner.error = Some(issue)
  owner.phase = 91
}

///|
/// The completed Relation owner supplies the full input cardinality and live
/// borrow before the first generation poll, including for a typed empty input.
/// This binds completion, not order realization, reservations or byte custody.
pub fn bind_content_byte_input(
  owner : ContentByteEncoder,
  rows : Int,
  available : () -> Bool,
) -> Result[Unit, ContentSerializationIssue] {
  if owner.phase != 0 || owner.expected_rows is Some(_) {
    return Err(ContentBusy)
  }
  if rows < 0 || rows > owner.max_rows {
    return Err(ContentRowLimit)
  }
  if !available() {
    return Err(ContentInputUnavailableIssue)
  }
  owner.expected_rows = Some(rows)
  owner.source_available = Some(available)
  Ok(())
}

///|
pub fn content_byte_completed_rows(owner : ContentByteEncoder) -> Int {
  owner.rows
}

///|
/// None denotes a genuinely absent Conditional cell, not explicit SQL NULL.
/// The getter must borrow the existing admitted Relation input until Ready.
pub fn start_content_byte_row(
  owner : ContentByteEncoder,
  cells : (Int) -> @admitted.CheckedValue?,
) -> Result[Unit, ContentSerializationIssue] {
  if owner.phase >= 90 {
    return Err(owner.error.unwrap_or(ContentClosed))
  }
  if owner.phase != 4 {
    return Err(ContentBusy)
  }
  if owner.source_available is Some(available) && !available() {
    fail_content_bytes(owner, ContentInputUnavailableIssue)
    return Err(ContentInputUnavailableIssue)
  }
  if owner.expected_rows is Some(rows) && owner.rows >= rows {
    return Err(ContentRowLimit)
  }
  if owner.rows >= owner.max_rows {
    fail_content_bytes(owner, ContentRowLimit)
    return Err(ContentRowLimit)
  }
  owner.cells = Some(cells)
  owner.column = 0
  owner.printed = 0
  owner.phase = if owner.profile.format == ContentJsonl { 15 } else { 5 }
  Ok(())
}

///|
/// Borrow immutable runtime cells and recheck through the existing bounded
/// value owner. The caller retains the input and physical reservation until
/// Ready or confirmed cleanup; this cursor cannot issue or publish a reference.
pub fn start_content_runtime_row(
  owner : ContentByteEncoder,
  cells : (Int) -> ContentInputCell,
  available : () -> Bool,
) -> Result[Unit, ContentSerializationIssue] {
  if !available() {
    return Err(ContentInputUnavailableIssue)
  }
  start_content_byte_row(owner, _ => None).map(_ => {
    owner.cells = None
    owner.runtime_cells = Some(cells)
    owner.input_available = Some(available)
  })
}

///|
/// Profile identity is the actual checked object, not equal schema or bytes.
pub fn content_byte_profile_matches(
  owner : ContentByteEncoder,
  profile : ContentSerializationProfile,
) -> Bool {
  physical_equal(owner.profile, profile)
}

///|
/// Plan-bound generation ceilings, not actual output quantities or a Store
/// reservation. Physical adapters must still admit their original resources.
pub fn content_byte_generation_limits(owner : ContentByteEncoder) -> (Int, Int) {
  (owner.max_rows, owner.max_bytes)
}

///|
fn append_content_piece(
  owner : ContentByteEncoder,
  output : StringBuilder,
  piece : String,
) -> Bool {
  let bytes = @utf8.encode(piece)
  if bytes.length() > owner.max_bytes - owner.bytes {
    fail_content_bytes(owner, ContentByteLimit)
    return false
  }
  @sha.update(owner.hash, bytes) catch {
    _ => {
      fail_content_bytes(owner, ContentByteLimit)
      return false
    }
  }
  owner.bytes += bytes.length()
  output.write_string(piece)
  true
}

///|
fn begin_content_text(
  owner : ContentByteEncoder,
  text : String,
  quoted~ : Bool,
  next_phase : Int,
) -> Unit {
  match start_csv_text(text, owner.max_bytes - owner.bytes, quoted~) {
    Ok(cursor) => {
      owner.text = Some(cursor)
      owner.next_phase = next_phase
      owner.phase = 3
    }
    Err(_) => fail_content_bytes(owner, ContentByteLimit)
  }
}

///|
fn begin_content_wire(
  owner : ContentByteEncoder,
  value : @admitted.Value,
) -> Unit {
  let writer = @encode.buffered_hashing_writer(
    owner.max_bytes - owner.bytes,
    owner.max_value_nodes,
    owner.max_value_depth,
    1024,
  ) catch {
    _ => {
      fail_content_bytes(owner, ContentByteLimit)
      return
    }
  }
  owner.writer = Some(writer)
  owner.wire = Some(@admitted.start_wire_emit(value, writer))
  owner.cell = None
  owner.phase = 8
}

///|
// The existing checked scalar owner supplies exact decimal/number spelling.
// Text cells use the bounded shared quote cursor; structured and reference
// cells use the existing canonical typed wire emitter, never dereference I/O.
fn begin_content_csv_value(owner : ContentByteEncoder) -> Unit {
  let checked = owner.cell.unwrap()
  match checked.value {
    @admitted.Null => {
      owner.cell = None
      begin_content_text(owner, owner.profile.null_marker, quoted=false, 10)
    }
    @admitted.Text(text) | @admitted.Date(text) | @admitted.Timestamp(text) => {
      owner.cell = None
      begin_content_text(owner, text, quoted=true, 10)
    }
    @admitted.Boolean(_) | @admitted.Number(_) | @admitted.Decimal(_) => {
      guard @admitted.canonical_scalar_text(checked, 64) is Some(text) else {
        fail_content_bytes(owner, ContentValueEncoding)
        return
      }
      owner.cell = None
      begin_content_text(owner, text, quoted=false, 10)
    }
    _ => owner.phase = 7
  }
}

///|
/// One unit advances one profile/frame/field or one CSV Unicode scalar. Nested
/// values use the existing bounded wire frames. Quantum changes batching, not
/// field order, row boundaries or the summed logical work.
pub fn advance_content_bytes(
  owner : ContentByteEncoder,
  quantum : Int,
) -> ContentBytePoll {
  if quantum < 1 || quantum > 64 {
    fail_content_bytes(owner, ContentInvalidLimits)
    return ContentBytesFailed(ContentInvalidLimits, work=0)
  }
  if owner.phase >= 90 {
    return ContentBytesFailed(owner.error.unwrap_or(ContentClosed), work=0)
  }
  if owner.source_available is Some(available) && !available() {
    fail_content_bytes(owner, ContentInputUnavailableIssue)
    return ContentBytesFailed(ContentInputUnavailableIssue, work=0)
  }
  let output = StringBuilder()
  let mut work = 0
  while work < quantum && owner.phase != 4 && owner.phase < 90 {
    if (owner.source_available is Some(available) && !available()) ||
      (owner.input_available is Some(available) && !available()) {
      fail_content_bytes(owner, ContentInputUnavailableIssue)
      break
    }
    work += 1
    match owner.phase {
      0 => {
        if owner.profile.bom {
          ignore(append_content_piece(owner, output, "\u{feff}"))
        }
        if owner.phase < 90 {
          owner.phase = if owner.profile.format == ContentCsv &&
            owner.profile.header {
            1
          } else {
            4
          }
        }
      }
      1 =>
        if owner.column >= owner.profile.fields.length() {
          owner.phase = 14
        } else {
          owner.header_position = 0
          owner.header_quoted = false
          if owner.column > 0 {
            ignore(append_content_piece(owner, output, owner.profile.delimiter))
          }
          if owner.phase < 90 {
            owner.phase = 2
          }
        }
      2 => {
        let text = @schema.field_reference_name(
          owner.profile.fields[owner.column],
        )
        if owner.header_position < text.length() {
          let unit = text[owner.header_position]
          if unit == '"' ||
            unit == '\r' ||
            unit == '\n' ||
            (unit == ',' && owner.profile.delimiter == ",") ||
            (unit == ';' && owner.profile.delimiter == ";") {
            owner.header_quoted = true
          }
          owner.header_position += 1
        } else {
          owner.column += 1
          begin_content_text(owner, text, quoted=owner.header_quoted, 1)
        }
      }
      3 => {
        let cursor = owner.text.unwrap()
        match advance_csv_quoted_text(cursor, 1) {
          Err(DeliverySerializationOutputLimit) =>
            fail_content_bytes(owner, ContentByteLimit)
          Err(_) => fail_content_bytes(owner, ContentValueEncoding)
          Ok((piece, done, _)) => {
            ignore(append_content_piece(owner, output, piece))
            if done && owner.phase < 90 {
              owner.text = None
              owner.phase = owner.next_phase
            }
          }
        }
      }
      5 =>
        if owner.column >= owner.profile.fields.length() {
          owner.phase = 11
        } else {
          let field = owner.profile.fields[owner.column]
          if owner.runtime_cells is Some(read) {
            match read(owner.profile.columns[owner.column]) {
              ContentInputUnavailable =>
                fail_content_bytes(owner, ContentInputUnavailableIssue)
              ContentAbsent =>
                if field.presence == @schema.Required {
                  fail_content_bytes(
                    owner,
                    ContentMissingRequired(owner.column),
                  )
                } else {
                  owner.column += 1
                }
              ContentPresent(value) => {
                owner.recheck = @admitted.start_recheck_runtime_value(
                  value,
                  field.contract,
                  {
                    max_nodes: owner.max_value_nodes,
                    max_depth: Int::min(
                      owner.max_value_depth,
                      owner.max_frames - 1,
                    ),
                    max_text_bytes: owner.max_bytes,
                  },
                )
                if owner.recheck is None {
                  fail_content_bytes(owner, ContentForeignValue(owner.column))
                } else {
                  owner.phase = 19
                }
              }
              ContentText(text) => {
                owner.recheck = @admitted.start_recheck_runtime_text(
                  text,
                  field.contract,
                  {
                    max_nodes: owner.max_value_nodes,
                    max_depth: Int::min(
                      owner.max_value_depth,
                      owner.max_frames - 1,
                    ),
                    max_text_bytes: owner.max_bytes,
                  },
                )
                if owner.recheck is None {
                  fail_content_bytes(owner, ContentForeignValue(owner.column))
                } else {
                  owner.phase = 19
                }
              }
            }
            continue
          }
          let cell = owner.cells.unwrap()(owner.profile.columns[owner.column])
          match cell {
            None =>
              if field.presence == @schema.Required {
                fail_content_bytes(owner, ContentMissingRequired(owner.column))
              } else {
                owner.column += 1
              }
            Some(checked) => {
              owner.cell = Some(checked)
              owner.equality = Some(
                @contract.start_type_equality(
                  checked.contract,
                  field.contract,
                  owner.max_value_nodes,
                ),
              ) catch {
                _ => None
              }
              if owner.equality is None {
                fail_content_bytes(owner, ContentForeignValue(owner.column))
              } else {
                owner.phase = 6
              }
            }
          }
        }
      6 => {
        let cursor = owner.equality.unwrap()
        if @contract.type_equality_next_frames(cursor) > owner.max_frames {
          fail_content_bytes(owner, ContentValueEncoding)
          continue
        }
        let equal = @contract.advance_type_equality(cursor) catch {
          _ => Some(false)
        }
        if equal is Some(value) {
          owner.equality = None
          if !value {
            fail_content_bytes(owner, ContentForeignValue(owner.column))
          } else if owner.profile.format == ContentCsv {
            if owner.printed > 0 {
              ignore(
                append_content_piece(owner, output, owner.profile.delimiter),
              )
            }
            if owner.phase < 90 {
              begin_content_csv_value(owner)
            }
          } else {
            owner.phase = 16
          }
        }
      }
      7 =>
        if append_content_piece(owner, output, "\"") {
          begin_content_wire(owner, owner.cell.unwrap().value)
        }
      8 => {
        let cursor = owner.wire.unwrap()
        // One step can add at most one continuation, including the nested
        // canonical Ref emitter. Reserve that conservative peak before advance.
        if @admitted.wire_emit_pending_frames(cursor) >= owner.max_frames {
          fail_content_bytes(owner, ContentValueEncoding)
        } else if @admitted.wire_emit_next_reference(cursor) is Some(reference) &&
          !@admitted.reference_available(reference) {
          fail_content_bytes(owner, ContentReferenceUnavailable)
        } else {
          let progress = try {
            let done = @admitted.advance_wire_emit(cursor)
            let writer = owner.writer.unwrap()
            let piece = @encode.drain_hash_output(writer)
            if done {
              ignore(@encode.finish_hash(writer))
            }
            Some((piece, done))
          } catch {
            _ => None
          }
          match progress {
            None => fail_content_bytes(owner, ContentValueEncoding)
            Some((piece, done)) => {
              if done {
                owner.wire = None
                owner.writer = None
              }
              if owner.profile.format == ContentCsv {
                begin_content_text(
                  owner,
                  piece,
                  quoted=false,
                  if done {
                    9
                  } else {
                    8
                  },
                )
              } else {
                ignore(append_content_piece(owner, output, piece))
                if done && owner.phase < 90 {
                  owner.phase = 10
                }
              }
            }
          }
        }
      }
      9 => {
        ignore(append_content_piece(owner, output, "\""))
        if owner.phase < 90 {
          owner.phase = 10
        }
      }
      10 => {
        owner.column += 1
        owner.printed += 1
        owner.phase = 5
      }
      11 => {
        if owner.profile.format == ContentJsonl {
          ignore(append_content_piece(owner, output, "}"))
        }
        if owner.phase < 90 &&
          append_content_piece(owner, output, owner.profile.line_ending) {
          owner.rows += 1
          owner.cells = None
          owner.runtime_cells = None
          owner.input_available = None
          owner.phase = 4
        }
      }
      14 =>
        if append_content_piece(owner, output, owner.profile.line_ending) {
          owner.phase = 4
        }
      15 => if append_content_piece(owner, output, "{") { owner.phase = 5 }
      16 => {
        // JSON object keys use the same bounded string emitter as data values.
        // Outer row punctuation is profile framing, not another JSON encoder.
        if owner.printed > 0 {
          ignore(append_content_piece(owner, output, ","))
        }
        if owner.phase < 90 {
          let field = owner.profile.fields[owner.column]
          let name = @schema.field_reference_name(field)
          let writer = @encode.buffered_hashing_writer(
            owner.max_bytes - owner.bytes,
            1,
            0,
            1024,
          ) catch {
            _ => {
              fail_content_bytes(owner, ContentByteLimit)
              return ContentBytesFailed(ContentByteLimit, work~)
            }
          }
          owner.writer = Some(writer)
          owner.wire = Some(
            @admitted.start_wire_emit(
              @admitted.text_value(name, name.length() * 4).unwrap(),
              writer,
            ),
          )
          owner.phase = 17
        }
      }
      17 => {
        let progress = try {
          let done = @admitted.advance_wire_emit(owner.wire.unwrap())
          let writer = owner.writer.unwrap()
          let piece = @encode.drain_hash_output(writer)
          if done {
            ignore(@encode.finish_hash(writer))
          }
          Some((piece, done))
        } catch {
          _ => None
        }
        match progress {
          None => fail_content_bytes(owner, ContentValueEncoding)
          Some((piece, done)) => {
            ignore(append_content_piece(owner, output, piece))
            if done && owner.phase < 90 {
              owner.wire = None
              owner.writer = None
              owner.phase = 18
            }
          }
        }
      }
      18 =>
        if append_content_piece(owner, output, ":") {
          begin_content_wire(owner, owner.cell.unwrap().value)
        }
      19 =>
        match @admitted.advance_recheck_runtime_value(owner.recheck.unwrap()) {
          @admitted.RecheckContinue => ()
          @admitted.RecheckFailed =>
            fail_content_bytes(owner, ContentForeignValue(owner.column))
          @admitted.RecheckComplete(checked, _, _) => {
            owner.recheck = None
            owner.cell = Some(checked)
            if owner.profile.format == ContentCsv {
              if owner.printed > 0 {
                ignore(
                  append_content_piece(owner, output, owner.profile.delimiter),
                )
              }
              if owner.phase < 90 {
                begin_content_csv_value(owner)
              }
            } else {
              owner.phase = 16
            }
          }
        }
      _ => fail_content_bytes(owner, ContentClosed)
    }
  }
  if owner.phase == 91 {
    ContentBytesFailed(owner.error.unwrap(), work~)
  } else if owner.phase == 4 {
    ContentBytesReady(output.to_string(), work~)
  } else {
    ContentBytesContinue(output.to_string(), work~)
  }
}

///|
pub fn finish_content_bytes(
  owner : ContentByteEncoder,
) -> Result[ContentByteCompletion, ContentSerializationIssue] {
  if owner.phase >= 90 {
    return Err(owner.error.unwrap_or(ContentClosed))
  }
  if owner.phase != 4 {
    return Err(ContentBusy)
  }
  if owner.source_available is Some(available) && !available() {
    fail_content_bytes(owner, ContentInputUnavailableIssue)
    return Err(ContentInputUnavailableIssue)
  }
  if owner.expected_rows is Some(rows) && owner.rows != rows {
    return Err(ContentIncompleteInput)
  }
  let hash = @sha.finish_hex(owner.hash) catch {
    _ => {
      fail_content_bytes(owner, ContentByteLimit)
      return Err(ContentByteLimit)
    }
  }
  owner.phase = 90
  // Exact input completion is now owned. The physical generation caller may
  // end the borrow after adopting these bytes into its existing Store custody.
  owner.source_available = None
  let completion : ContentByteCompletion = {
    name: owner.profile.name,
    media_type: content_serialization_media_type(owner.profile),
    size_bytes: owner.bytes,
    row_count: owner.rows,
    content_cid: "sha256:" + hash,
  }
  owner.completion = Some(completion)
  Ok(completion)
}
