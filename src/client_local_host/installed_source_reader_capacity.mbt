///|
/// Selected JSON-page reader representation. Inputs are rejection bounds,
/// never Ledger limits, permission, reservations or runtime heap measurements.
/// The original acquisition still reserves this declaration on its B parent.
pub fn installed_source_reader_policy() -> Array[Int] {
  let preparation = @publication_host.client_standard_program_preparation_limits()
  let values = @publication_host.client_standard_values_sequence_limits()
  [
    preparation.checking.input.tree.max_string_bytes,
    preparation.checking.compilation.structure.bindings,
    values.max_cells / values.max_rows,
  ]
}

///|
/// One response's Source-owned non-ASCII parser, exact indexed admission and
/// key-normalization workspace. The original received Bytes are borrowed;
/// parse_json_bytes owns a separate decoded String. No ASCII eligibility or
/// string-value normalization is inferred, and no capacity is granted here.
fn installed_source_response_workspace(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @source.json_literal_construction_extent(bytes, nodes, depth)
    is Some(literal) &&
    scalar_snapshot_name_normalization_layout(bytes) is Some(normalization) else {
    return None
  }
  // Reuse ONLY the decoder's structural families. Each category is separately
  // bounded by all parsed nodes; simultaneous objects+arrays deliberately
  // overcount. These are constructor bounds, not facts from the ASCII scan.
  // Its parser/text/ASCII-control inventories are not consumed below.
  let indexed = closed_values_source_inventories({
    input_bytes: bytes,
    node_upper: nodes,
    objects: nodes,
    arrays: nodes,
    fields_upper: nodes,
    quoted_tokens: 0,
    quoted_utf16_units: 0,
    longest_quoted_utf16: 0,
    longest_atom_utf16: 0,
    depth_upper: Int::min(nodes, depth),
  })
  let source : @execution.PreparationRepresentationUnits = {
    record_headers: literal.record_headers,
    reference_slots: literal.reference_slots,
    scalar_words: literal.scalar_words,
    owned_utf16_units: literal.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  // Use the SAME canonical Owner's generated UTF16 expansion, including
  // supplementary mappings. Sum all normalized key output with the
  // non-normalizing tree bound, even if old text would already be unrooted.
  // The separate one-key normalization workspace includes scalar arrays,
  // stable ordering, builder, LF passes and bounded recursive controls.
  let input_and_keys : @execution.PreparationRepresentationUnits = {
    record_headers: 1L + nodes.to_int64(),
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: bytes.to_int64() +
    @canonical.nfc_lf_retained_output_units(bytes.to_int64()).unwrap(),
    owned_wire_bytes: 0L,
  }
  @execution.compose_preparation_representation([
    source,
    indexed.indexed_additional,
    indexed.key_admission_peak,
    indexed.decoder_ancestry_peak,
    indexed.decoder_controls_peak,
    normalization,
    input_and_keys,
  ])
}

///|
fn installed_source_response_preserving_workspace(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @decode.preserving_json_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(original) else {
    return None
  }
  Some({
    record_headers: original.record_headers,
    reference_slots: original.reference_slots,
    scalar_words: original.scalar_words,
    owned_utf16_units: original.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
pub fn installed_json_source_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
) -> @execution.ExecutionCapacity? {
  installed_json_source_reader_capacity_with_decoder(
    limits, columns, secret_bytes, installed_source_response_workspace,
  )
}

///|
fn installed_source_reader_retained_inventory(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  track_row_identity? : Bool = true,
) -> @execution.PreparationRepresentationUnits? {
  // Same field order as the installed JSON reader's immutable limits view.
  // response/total/nodes/depth/rows/totalRows/pages/pageSize/cursor/identity/
  // target/valueNodes/valueText/rowWire/rowNodes/rowDepth.
  if limits.length() != 16 || columns < 1 || secret_bytes < 1 {
    return None
  }
  for value in limits {
    if value < 1 {
      return None
    }
  }
  let response = limits[0].to_int64()
  let total = limits[1].to_int64()
  // JSON page decoding owns its id/cursor duplicate-tracking state. A native
  // managed sequence never constructs it; its selected codec owns and quotes
  // the original protocol's actual identity/locator material instead.
  let ids = if track_row_identity { limits[5].to_int64() } else { 0L }
  let pages = limits[6].to_int64()
  let cursors = if track_row_identity { pages } else { 0L }
  let originals = pages + 1L
  let fields = columns.to_int64()
  // Charge/retain the original received body before a total-byte refusal.
  // One offending response overlaps the admitted total; no new request is
  // allowed after it. The response inventory includes that same original.
  guard @execution.checked_preparation_add_product(total, response, 1L)
    is Some(raw) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      0L,
      ids,
      limits[9].to_int64(),
    )
    is Some(id_text) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      id_text,
      cursors,
      limits[8].to_int64(),
    )
    is Some(text) else {
    return None
  }
  // The exact use CID is retained by each received response; credential text
  // stays only in the original per-read binding, never in provider rows.
  guard @execution.checked_preparation_add_product(text, originals, 71L)
    is Some(text) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      text,
      secret_bytes.to_int64(),
      1L,
    )
    is Some(text) else {
    return None
  }
  // Source-owned reader frame, handle/custody/binding envelopes, captured
  // methods and callback environments, provider invocation context/limits,
  // prepared reader/state, two projected-name vectors and two live Sets.
  // Original installation/schema/Account/Journal backing remains borrowed.
  // The same reader retains one optional direct sequence reference in its
  // existing frame until original read/binding retirement; no child Owner.
  // RowRun's existing preparation flag now retains its SAME original response
  // borrow through workspace return and final cleanup. The reference replaces
  // that flag in the SAME resident slot; they never coexist in that frame.
  // The SAME growth callback captures one additional original constructor
  // method. Its private phase argument is a call-local scalar, not another
  // reader, callback environment or received-page ticket.
  let common_fields = 38L + 4L + 1L + 3L + 3L + 21L + 6L + 2L + 2L + 1L
  let provider_fields = 5L + 5L + 6L + 3L + 18L + 16L + 5L + 6L + 8L + 4L
  let closures = 13L
  // One resolver-close carrier (six fields), its original binding field and
  // four joined callback environments. The same FD remains with its existing
  // file Owner; these are managed control records, not a physical FD price.
  let resolver_headers = 5L
  let resolver_slots = 11L
  // Two typed-value callbacks share the original RowRun/sequence state.
  let native_callback_headers = 2L
  let native_callback_slots = 4L
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 39L +
    resolver_headers +
    native_callback_headers +
    3L * originals,
    reference_slots: common_fields +
    provider_fields +
    closures +
    resolver_slots +
    native_callback_slots +
    4L +
    2L * fields +
    9L * originals +
    2L * ids +
    2L * cursors,
    // The one native-prepared selection flag survives until reader retirement.
    scalar_words: 20L + 3L * originals + ids + cursors,
    owned_utf16_units: text,
    owned_wire_bytes: raw,
  }
  Some(retained)
}

///|
fn installed_source_reader_control_inventory() -> @execution.PreparationRepresentationUnits {
  let native_control_headers = 7L
  let native_control_slots = 14L
  let native_control_words = 11L
  {
    record_headers: 20L + native_control_headers,
    reference_slots: 3L +
    18L +
    3L +
    18L +
    5L +
    6L +
    2L +
    1L +
    6L +
    4L +
    4L +
    15L +
    native_control_slots,
    scalar_words: 12L + native_control_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
fn installed_json_source_reader_capacity_with_decoder(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  response_workspace : (Int, Int, Int) -> @execution.PreparationRepresentationUnits?,
  sequential_preserving? : Bool = false,
) -> @execution.ExecutionCapacity? {
  guard installed_source_reader_retained_inventory(
      limits, columns, secret_bytes,
    )
    is Some(retained) else {
    return None
  }
  let response = limits[0].to_int64()
  let rows = limits[4].to_int64()
  let fields = columns.to_int64()
  // Provider projection, admitted values and the parsed output row page
  // coexist with the Source/indexed workspace below. JSON-node pricing comes
  // from B's shared
  // fold, not another provider-specific byte tariff.
  // The fixed preserving Sheets codecs parse the response with Source and
  // return only projected rows/scalars. They never JSON.parse the raw body in
  // Host JS. Its complete Source tree is already owned by response_workspace;
  // do not price that SAME raw tree again as generic Host value-node slots.
  // Returned row/value nodes, Strings, output wire and failure peaks stay.
  let response_value_nodes = if sequential_preserving {
    0L
  } else {
    limits[2].to_int64()
  }
  guard @execution.checked_preparation_add_product(
      response_value_nodes,
      limits[14].to_int64(),
      1L,
    )
    is Some(nodes) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      nodes,
      limits[11].to_int64(),
      1L,
    )
    is Some(nodes) else {
    return None
  }
  guard @execution.checked_preparation_add_product(nodes, rows, fields)
    is Some(nodes) else {
    return None
  }
  // Current raw decode, provider row wire, parsed-row serialization, target
  // encoding and literal admission text are distinct live work buffers.
  // A native signed child retains both original field descriptors, the
  // two-field handoff and its extra argument through the current await.
  // Include the optional method envelope and typed-consumption callback
  // controls alongside that whole prefix, even though those calls ordinarily
  // complete in sequence. No new variable payload or credential is copied.
  // Prepared-native entry adds one own-field descriptor (one reference and
  // three Boolean words), two original-fact references in the existing input
  // record and one first-invocation reference in the existing read arguments.
  // These are borrowed originals, never copied acquisition or grant payloads.
  let controls = installed_source_reader_control_inventory()
  let workspace : @execution.PreparationRepresentationUnits = {
    ..controls,
    owned_utf16_units: response +
    3L * limits[13].to_int64() +
    limits[10].to_int64() +
    limits[12].to_int64(),
    owned_wire_bytes: response + limits[13].to_int64(),
  }
  guard response_workspace(limits[0], limits[2], limits[3])
    is Some(response_parse) else {
    return None
  }
  if sequential_preserving {
    // The fixed Sheets bridge returns only Json rows/scalars (or a scalar
    // refusal) from project_grid/check_target. Its raw Source Cursor/index
    // cannot escape into the later stringify/Host JSON.parse/acceptPage call.
    // Keep all received bodies and the returned row/value envelope. Only the
    // two complete parser peaks are sequential; neither is omitted, including
    // a failed response or a failed output-page admission.
    let response_buffers = {
      ..workspace,
      owned_utf16_units: response +
      limits[10].to_int64() +
      limits[12].to_int64(),
      owned_wire_bytes: response,
    }
    guard response_workspace(limits[13], limits[14], limits[15])
      is Some(row_parse) &&
      @execution.compose_preparation_representation([
        response_buffers, response_parse,
      ])
      is Some(response_peak) &&
      @execution.compose_preparation_representation([workspace, row_parse])
      is Some(row_peak) &&
      @execution.preparation_execution_capacity({
        retained,
        workspace: response_peak,
        retained_nodes: 0L,
        workspace_nodes: nodes,
        retained_bytes: 0L,
        workspace_bytes: 0L,
      })
      is Some(response_capacity) &&
      @execution.preparation_execution_capacity({
        retained,
        workspace: row_peak,
        retained_nodes: 0L,
        workspace_nodes: nodes,
        retained_bytes: 0L,
        workspace_bytes: 0L,
      })
      is Some(row_capacity) else {
      return None
    }
    return @execution.execution_capacity(
      @execution.execution_capacity_retained_bytes(response_capacity),
      Int64::max(
        @execution.execution_capacity_execution_bytes(response_capacity),
        @execution.execution_capacity_execution_bytes(row_capacity),
      ),
    )
  }
  guard @execution.compose_preparation_representation([
      workspace, response_parse,
    ])
    is Some(workspace) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: nodes,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// The existing Gmail list/get control retains all nominal pages, requests and
/// admitted thread projections until its original reader retires. Compose that
/// actual inventory with the SAME JSON response/row/failed-body recipe. Neither
/// this quote nor a matching operation name issues a grant or an admission.
pub fn installed_gmail_thread_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  list_pages : Int,
  mailbox_bytes : Int,
) -> @execution.ExecutionCapacity? {
  guard limits.length() == 16 &&
    columns == 5 &&
    list_pages > 0 &&
    mailbox_bytes > 0 &&
    limits[4] == 1 &&
    limits[5] > 0 &&
    list_pages <= 2147483647 - limits[5] &&
    limits[6] == list_pages + limits[5] &&
    installed_json_source_reader_capacity(limits, columns, secret_bytes)
    is Some(json) else {
    return None
  }
  let pages = list_pages.to_int64()
  let threads = limits[5].to_int64()
  guard @execution.checked_preparation_add_product(
      0L,
      threads,
      limits[11].to_int64(),
    )
    is Some(values) &&
    @execution.checked_preparation_add_product(
      mailbox_bytes.to_int64() + 71L * (pages + threads),
      threads,
      limits[12].to_int64(),
    )
    is Some(text) else {
    return None
  }
  // GmailThreadRead(16), its two original limits(6+10), retained list pages(3),
  // ThreadProjection(5), original Request(3), request kind/Option wrappers,
  // page/thread vectors and seen-id/token maps. The generic JSON reader already
  // covers raw bodies, id/token text and its own response/custody bindings.
  // The managed sequence's original context/project/perform/observe closures,
  // original reader/retirement state and captured eleven provider callbacks
  // remain alongside that control, including on a failed child.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 15L + 5L + 11L + 2L * pages + 7L * threads,
    reference_slots: 16L +
    6L +
    10L +
    27L +
    11L +
    4L * pages +
    12L * threads +
    2L * pages +
    2L * threads,
    scalar_words: 12L + 4L * pages + 4L * threads,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  }
  // One original request's JSON projection may escape each JSON character;
  // mailbox/id/token are bounded independently. The current request and DTO
  // overlap its admitted response and the retained nominal prefix. The fixed
  // spelling/decimal fields fit within the original 128-unit syntax inventory.
  let workspace : @execution.PreparationRepresentationUnits = {
    record_headers: 12L,
    reference_slots: 36L,
    scalar_words: 8L,
    owned_utf16_units: 6L *
    (mailbox_bytes.to_int64() + limits[8].to_int64() + limits[9].to_int64()) +
    128L,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_execution_capacity({
      retained,
      workspace,
      retained_nodes: values,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(sequence) else {
    return None
  }
  @execution.add_execution_capacity(json, sequence)
}

///|
/// Slack's installed reader retains the original conversation pages and the
/// Catalog history/reply controls through coalescence, including failed child
/// prefixes. Compose this selected inventory with the existing JSON/HTTP
/// recipe; neither amount issues an Account grant or a new Resource owner.
pub fn installed_slack_source_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  protocol_pages : Int,
) -> @execution.ExecutionCapacity? {
  guard limits.length() == 16 &&
    columns == 11 &&
    protocol_pages > 0 &&
    protocol_pages < 2147483647 &&
    limits[6] == protocol_pages + 1 &&
    installed_json_source_reader_capacity(limits, columns, secret_bytes)
    is Some(json) else {
    return None
  }
  let pages = limits[6].to_int64()
  let rows = limits[5].to_int64()
  let fields = columns.to_int64()
  // The messages caller counts conversation, history AND reply rows against
  // the same total before retaining them. One history per selected channel,
  // one reply control per original history row, at most two controls per row.
  let controls = 2L * rows
  guard @execution.checked_preparation_add_product(0L, rows, fields)
    is Some(cells) &&
    @execution.checked_preparation_add_product(
      0L,
      rows,
      fields + 2L * limits[11].to_int64(),
    )
    is Some(values) &&
    @execution.checked_preparation_add_product(0L, cells, limits[12].to_int64())
    is Some(value_text) &&
    @execution.checked_preparation_add_product(
      value_text,
      pages,
      limits[8].to_int64() + 2L * limits[9].to_int64() + 256L,
    )
    is Some(text) else {
    return None
  }
  // Sequence frame/closures, captured 39 provider functions, two sets and
  // original page/id vectors. Per control: the <=20-field Catalog control,
  // page/comparison limits, pending Option/request and cursor/id maps. Per
  // page: original response hash/rows/cursor/facts and request associations.
  // Three row/field reference views cover original, replies and coalescence;
  // checked values are retained once while all views overlap. The existing
  // 11-field message schema has two composite cells (reactions/files); the
  // other cells and both list schemas are scalar, not columns * valueNodes.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 24L + 39L + 12L * controls + 8L * pages + 8L * rows,
    reference_slots: 70L +
    39L +
    60L * controls +
    24L * pages +
    20L * rows +
    3L * cells,
    scalar_words: 24L + 30L * controls + 12L * pages + 6L * rows,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  }
  // Original request JSON/target, comparison ancestry and coalescence maps
  // coexist with the received body and the full retained prefix. The existing
  // JSON recipe already funds its Source parser/NFC and row-wire workspace.
  let workspace : @execution.PreparationRepresentationUnits = {
    record_headers: 12L + 3L * rows,
    reference_slots: 40L + 8L * rows + 3L * cells,
    scalar_words: 16L + 4L * rows,
    owned_utf16_units: 6L * (limits[8].to_int64() + 2L * limits[9].to_int64()) +
    256L,
    // The original auth.test POST body is exactly the two UTF8 bytes {}.
    owned_wire_bytes: 2L,
  }
  guard @execution.preparation_execution_capacity({
      retained,
      workspace,
      retained_nodes: values,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(sequence) else {
    return None
  }
  @execution.add_execution_capacity(json, sequence)
}

///|
/// Add the selected implementation's original request-constructor DATA to
/// the SAME existing JSON reader recipe. This neither issues capacity nor
/// infers HTTP permission from a byte limit; Core still admits the full reader
/// on its original acquisition. Missing/overflowing constructors fail closed.
pub fn installed_json_source_reader_capacity_with_request(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  request : @execution.ExecutionCapacity?,
) -> @execution.ExecutionCapacity? {
  guard request is Some(request) &&
    installed_json_source_reader_capacity(limits, columns, secret_bytes)
    is Some(reader) else {
    return None
  }
  @execution.add_execution_capacity(reader, request)
}

///|
/// The fixed preserving Source decoder keeps the SAME common Reader/response/
/// projection inventory. Only its absent normalization constructor is omitted.
/// The installing caller must actually use preserving parsing and exact-key
/// admission; this quantity grants no parser mode, admission or capacity.
pub fn installed_preserving_json_source_reader_capacity_with_request(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  request : @execution.ExecutionCapacity?,
) -> @execution.ExecutionCapacity? {
  guard request is Some(request) &&
    installed_json_source_reader_capacity_with_decoder(
      limits,
      columns,
      secret_bytes,
      installed_source_response_preserving_workspace,
      sequential_preserving=true,
    )
    is Some(reader) else {
    return None
  }
  // The fixed standard Reader calls its synchronous request projector before
  // sending, and invokes the response decoder only after that request returns.
  // An invalid async/throwing request cannot proceed to receive/decode. Keep
  // all original response-prefix and returned request data simultaneously;
  // only their completed constructor workspaces are sequential.
  standard_create_sequence_pair_capacity(reader, request)
}

///|
/// Same shared Reader/response/binding controls for a native typed protocol.
/// Its original domain recipe supplies all parser/index/typed-codec material;
/// no generic JSON row serialization or a second raw decoder is selected.
/// A missing native constructor quote remains unavailable, never zero/default.
pub fn installed_native_source_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  native : @execution.ExecutionCapacity?,
) -> @execution.ExecutionCapacity? {
  guard native is Some(native) &&
    installed_source_reader_retained_inventory(
      limits,
      columns,
      secret_bytes,
      track_row_identity=false,
    )
    is Some(retained) else {
    return None
  }
  let controls = installed_source_reader_control_inventory()
  guard @execution.preparation_execution_capacity({
      retained,
      workspace: {
        ..controls,
        owned_utf16_units: limits[10].to_int64(),
        owned_wire_bytes: limits[0].to_int64(),
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(reader) else {
    return None
  }
  @execution.add_execution_capacity(reader, native)
}
