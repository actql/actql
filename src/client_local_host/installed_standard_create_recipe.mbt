///|
// Same constructor fold as the other installed domains. These quantities do
// not admit a Run or supply its permission/current/physical cleanup duties.
fn standard_create_representation_capacity(
  retained : @execution.PreparationRepresentationUnits,
  workspace : @execution.PreparationRepresentationUnits,
) -> @execution.ExecutionCapacity? {
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
fn standard_create_sum_capacities(
  values : Array[@execution.ExecutionCapacity],
  sequential_workspace? : Bool = false,
) -> @execution.ExecutionCapacity? {
  if sequential_workspace {
    let mut retained = 0L
    let mut workspace = 0L
    for value in values {
      guard @execution.execution_capacity_inventory_add(
          retained,
          QuotedBytes,
          @execution.execution_capacity_retained_bytes(value),
          1,
        )
        is Some(next) else {
        return None
      }
      retained = next
      workspace = Int64::max(
        workspace,
        @execution.execution_capacity_execution_bytes(value) -
        @execution.execution_capacity_retained_bytes(value),
      )
    }
    guard @execution.execution_capacity_inventory_add(
        retained,
        QuotedBytes,
        workspace,
        1,
      )
      is Some(execution) else {
      return None
    }
    return @execution.execution_capacity(retained, execution)
  }
  let mut total = @execution.execution_capacity(0L, 0L).unwrap()
  for value in values {
    guard @execution.add_execution_capacity(total, value) is Some(next) else {
      return None
    }
    total = next
  }
  Some(total)
}

///|
// Binary form of the same retained-sum/workspace-maximum fold. Fixed Host
// callsites already hold the two original quantities; do not allocate another
// input Array just to compose them. The caller owns the sequential-lifetime
// proof; these immutable quantities neither grant nor return any resource.
fn standard_create_sequence_pair_capacity(
  left : @execution.ExecutionCapacity,
  right : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  let left_r = @execution.execution_capacity_retained_bytes(left)
  let right_r = @execution.execution_capacity_retained_bytes(right)
  let workspace = Int64::max(
    @execution.execution_capacity_execution_bytes(left) - left_r,
    @execution.execution_capacity_execution_bytes(right) - right_r,
  )
  if left_r > 9223372036854775807L - right_r {
    return None
  }
  let retained = left_r + right_r
  if workspace > 9223372036854775807L - retained {
    return None
  }
  @execution.execution_capacity(retained, retained + workspace)
}

///|
// Existing saved-control family, including the retained Receipt's actual
// data-key outcome path, not only the smaller logical Ledger entry. Both use
// the same synchronous original controlConstruction frame. The normalizing
// Ledger codec keeps its complete Unicode peak; this additional coarse
// envelope covers candidate Receipt, typed outcome, expected Receipt and the
// original Ledger result which can coexist during cross-reference admission.
// Use only the existing executor units and fixed4096 Host-call allowance.
fn standard_create_saved_control_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard installed_json_effect_response_construction_capacity(
      @execution.execution_capacity(0L, 0L).unwrap(),
      bytes,
      nodes,
      depth,
    )
    is Some(ledger) &&
    @execution.execution_capacity_inventory(
      [
        // Four complete returned/overlapping value families above. This
        // intentionally also retains their private construction alternatives.
        { unit: ValueNodeSlots, count: nodes.to_int64(), copies: 4, },
        // Three existing decoded-text envelopes cover12 UTF16 text domains:
        // Ledger wire/fields, candidate wire/text, typed wire/text, expected
        // body/text/wire, and three old/new returned-text alternatives. Input
        // aliases are conservatively included, never used as extra grants.
        { unit: DecodedTextBytes, count: bytes.to_int64(), copies: 3, },
        { unit: QuotedBytes, count: 4096L, copies: 1, },
      ],
      [
        // Current Source/index/schema/canonical/writer and failed prefixes.
        // Completed sibling codecs return before the next begins. Preserve
        // the full conservative phase on refusal, not a successful-body cut.
        { unit: ValueNodeSlots, count: nodes.to_int64(), copies: 6, },
        { unit: CursorRootSlots, count: depth.to_int64(), copies: 2, },
        // Encode/parse, canonical text emission and digest input alternatives
        // remain separate from retained result text and received body copies.
        { unit: CanonicalWireBytes, count: bytes.to_int64(), copies: 6, },
      ],
      RetainedAlongsideExecution,
    )
    is Some(receipts) else {
    return None
  }
  // These are two envelopes for the SAME complete control family, not two
  // simultaneous grants. The Receipt envelope already includes its Ledger
  // original. Select the dominating dimensions once; keep every other
  // Grant, native provider result and saved physical buffer additive below.
  @execution.execution_capacity(
    Int64::max(
      @execution.execution_capacity_retained_bytes(ledger),
      @execution.execution_capacity_retained_bytes(receipts),
    ),
    Int64::max(
      @execution.execution_capacity_execution_bytes(ledger),
      @execution.execution_capacity_execution_bytes(receipts),
    ),
  )
}

///|
// The SAME remote Credential owner supplies its actual encoder/decoder and
// signature domains. No Node copy of its limits or serialized grant schema.
fn standard_create_grant_capacity() -> @execution.ExecutionCapacity? {
  let profile = @credential.credential_grant_construction_profile()
  let limits = profile.grant
  let b = limits.max_input_bytes.to_int64()
  let preimage = b + profile.signature_preimage_prefix_units.to_int64()
  let signature = profile.signature_units.to_int64()
  guard @encode.text_writer_construction_inventory(
      limits.max_input_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(writer) &&
    installed_source_response_workspace(
      limits.max_input_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(decoded) else {
    return None
  }
  // Original Grant, raw Scope, authorization, purpose and issued-use entry.
  // Their strings borrow the already retained Site/Run metadata. Co-count a
  // canonical grant body/signature while the synchronous Journal accepts it.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 5L,
    reference_slots: 32L,
    scalar_words: 8L,
    owned_utf16_units: b + signature + profile.cid_units.to_int64(),
    owned_wire_bytes: 0L,
  }
  // The separately re-admitted Grant/envelope, raw signed envelope, two
  // native projection/argument vectors and current canonical body coexist
  // with signature verification and the selected Journal insert. The writer
  // and indexed decoder are original constructor inventories, not a fee.
  guard @execution.compose_preparation_representation([
      decoded,
      {
        record_headers: writer.record_headers,
        reference_slots: writer.reference_slots,
        scalar_words: writer.scalar_words,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: 9L,
        reference_slots: 56L,
        scalar_words: 12L,
        owned_utf16_units: 3L * b + signature,
        // Signing and verification preimages plus the base64url signature's
        // decoded bytes. ceil(3L/4) is a representation bound, not an algorithm.
        owned_wire_bytes: 2L * preimage + (3L * signature + 3L) / 4L,
      },
    ])
    is Some(workspace) else {
    return None
  }
  standard_create_representation_capacity(retained, workspace)
}

///|
// Back the admitted secret retained by the SAME original Credential binding,
// its physical header String and encoded request-header alternatives. The
// original resolver still owns construction/failed-prefix backing before its
// return; this cannot turn a late secret-size check into a producer allowance.
fn standard_create_secret_capacity(
  bytes : Int,
  prefix_units : Int,
) -> @execution.ExecutionCapacity? {
  if bytes < 1 || prefix_units < 0 {
    return None
  }
  let s = bytes.to_int64()
  let p = prefix_units.to_int64()
  standard_create_representation_capacity(
    {
      record_headers: 3L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 3L * s + 2L * p,
      owned_wire_bytes: 2L * (s + p),
    },
    {
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: s + p,
    },
  )
}

///|
/// The actual standard implementation's constructor capacities. Inputs are
/// its original Native codec profile, HTTP declaration, Host codec bounds,
/// SAME Site secret selection and actual Ledger response policy. They are
/// not user resource knobs or a substitute for the original checked Plan.
///
/// Output order is capture fixed/per-row, request constructor, write body,
/// pre-body controls and (when selected) the independent read body. The Node
/// owner attaches operation names/phases; Core supplies row multiplicity once
/// from the existing completed Plan. No occurrence, attempt or transfer is
/// issued by this immutable DATA constructor.
pub fn installed_standard_create_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  check_request_bytes : Int,
  check_response_bytes : Int,
  before_send : Bool,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum? : Int = 1,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  installed_standard_recipe_capacities(
    original,
    None,
    input_bytes,
    input_nodes,
    input_depth,
    input_bytes,
    input_nodes,
    input_depth,
    request_bytes,
    response_bytes,
    check_request_bytes,
    check_response_bytes,
    before_send,
    secret_bytes,
    secret_prefix_units,
    header_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    metadata_units,
    response_read_quantum~,
  )
}

///|
// The same composer receives the actual earlier proposal admission bounds.
// Preview-wide storage remains separate; no bound or admission is weakened.
pub fn installed_standard_create_request_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  row_input_bytes : Int,
  row_input_nodes : Int,
  row_input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  check_request_bytes : Int,
  check_response_bytes : Int,
  before_send : Bool,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum? : Int = 1,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  installed_standard_recipe_capacities(
    original,
    None,
    input_bytes,
    input_nodes,
    input_depth,
    row_input_bytes,
    row_input_nodes,
    row_input_depth,
    request_bytes,
    response_bytes,
    check_request_bytes,
    check_response_bytes,
    before_send,
    secret_bytes,
    secret_prefix_units,
    header_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    metadata_units,
    response_read_quantum~,
  )
}

///|
pub fn installed_standard_driver_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  capture_original : Array[@execution.ExecutionCapacity]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  row_input_bytes : Int,
  row_input_nodes : Int,
  row_input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  check_request_bytes : Int,
  check_response_bytes : Int,
  before_send : Bool,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum? : Int = 1,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  guard capture_original is Some(capture) &&
    (capture.length() == 2 || capture.length() == 3) &&
    check_request_bytes == 0 &&
    check_response_bytes == 0 &&
    !before_send else {
    return Err(Unsupported)
  }
  installed_standard_recipe_capacities(
    original,
    Some(capture),
    input_bytes,
    input_nodes,
    input_depth,
    row_input_bytes,
    row_input_nodes,
    row_input_depth,
    request_bytes,
    response_bytes,
    check_request_bytes,
    check_response_bytes,
    before_send,
    secret_bytes,
    secret_prefix_units,
    header_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    metadata_units,
    response_read_quantum~,
  )
}

///|
fn installed_standard_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  capture_original : Array[@execution.ExecutionCapacity]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  row_input_bytes : Int,
  row_input_nodes : Int,
  row_input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  check_request_bytes : Int,
  check_response_bytes : Int,
  before_send : Bool,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum? : Int = 1,
  control_wire_bytes? : Int? = None,
  host_input_bytes? : Int? = None,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  let control_bytes = control_wire_bytes.unwrap_or(stored_bytes)
  guard control_bytes > 0 &&
    control_bytes <= stored_bytes &&
    original is Some(entries) &&
    input_bytes > 0 &&
    input_nodes > 0 &&
    input_depth > 0 &&
    row_input_bytes > 0 &&
    row_input_nodes > 0 &&
    row_input_depth > 0 &&
    request_bytes > 0 &&
    response_bytes > 0 &&
    stored_bytes > 0 &&
    stored_nodes > 0 &&
    stored_depth > 0 &&
    metadata_units >= 0L &&
    metadata_units <= 2147483647L else {
    return Err(Unsupported)
  }
  let checks = check_request_bytes > 0 && check_response_bytes > 0
  if (
      !checks &&
      (check_request_bytes != 0 || check_response_bytes != 0 || before_send)
    ) ||
    (checks && entries.length() != 4 && entries.length() != 7) ||
    (entries.length() == 7 && !checks) {
    return Err(Unsupported)
  }
  let constructors = match
    installed_standard_create_constructor_capacities(original) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let confirmed = entries.length() == 7
  let write_output = if entries.length() >= 4 { 2 } else { 1 }
  guard installed_standard_host_capture_row_capacity(
      row_input_bytes, row_input_nodes, row_input_depth,
    )
    is Some(capture_rows) &&
    installed_standard_host_preview_input_parts(
      input_bytes, input_nodes, input_depth, host_input_bytes,
    )
    is Some((host_retained, host_workspace)) &&
    @execution.compose_preparation_representation([
      host_retained,
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: metadata_units,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(host_retained) &&
    @execution.compose_preparation_representation([
      host_workspace,
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        // Recovery serializes binding, individual rows, joined rows and final
        // member wire. All old text/encoding peaks and metadata remain charged.
        owned_utf16_units: 4L * input_bytes.to_int64() + 2L * metadata_units,
        owned_wire_bytes: input_bytes.to_int64(),
      },
    ])
    is Some(host_workspace) &&
    standard_create_representation_capacity(host_retained, host_workspace)
    is Some(capture_fixed) &&
    installed_effect_http_response_construction_capacity(
      response_bytes,
      header_bytes,
      response_read_quantum~,
    )
    is Some(write_receive) &&
    standard_create_secret_capacity(secret_bytes, secret_prefix_units)
    is Some(secret) &&
    standard_create_grant_capacity() is Some(grant) &&
    standard_create_saved_control_capacity(
      control_bytes, stored_nodes, stored_depth,
    )
    is Some(stored) &&
    standard_create_representation_capacity(
      {
        // The selected SQLite response row owns its Uint8Array and the
        // existing materializer returns Buffer.from of those SAME bytes.
        // There is no received HTTP child on this saved-response path.
        record_headers: 2L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 2L * stored_bytes.to_int64(),
      },
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    )
    is Some(stored_buffers) &&
    // The actual claimed write first captures its physical response, then
    // invokes owned.project through its SAME controlConstruction frame. The
    // projector below is already completely on that original control token.
    // Keep HTTP buffers/secret and physical cleanup here; do not reserve the
    // one synchronous Native projector on both simultaneous tokens.
    standard_create_sum_capacities([write_receive, secret]) is Some(write_body) &&
    // Warm and stored response projection use this SAME original frame; a
    // stored response read/project need not borrow a physical write occurrence.
    // Keep its actual Ledger-bound input and Native projector on pre-body
    // controls rather than inventing another physical write or cleanup ACK.
    // The original Ledger admit/read returns before the original provider
    // projector is called. Their Unicode Owner scratch cannot escape either
    // synchronous call; all Source/index/native/output holders remain summed.
    // The same control reservation grows before each call and retains its full
    // failed prefix until existing cleanup. Physical work keeps its old sum.
    standard_create_sum_capacities(
      [stored, stored_buffers, constructors[write_output]],
      sequential_workspace=true,
    )
    is Some(recovery) else {
    return Err(Unsupported)
  }
  let mut controls = recovery
  if checks {
    // The metadata HTTP child retains its own response and secret. Its pure
    // projector runs afterwards through the SAME controlConstruction frame,
    // just like the claimed-write and stored-response projectors above.
    // The request body runs through that same synchronous frame before the
    // physical call. Each physical occurrence retains its complete Native/Host
    // output separately; only its completed private workspace belongs here.
    let request_retained = @execution.execution_capacity_retained_bytes(
      constructors[1],
    )
    let request_workspace = @execution.execution_capacity(
      0L,
      @execution.execution_capacity_execution_bytes(constructors[1]) -
      request_retained,
    ).unwrap()
    guard standard_create_sequence_pair_capacity(controls, request_workspace)
      is Some(controls_with_request) &&
      standard_create_sequence_pair_capacity(
        controls_with_request,
        constructors[3],
      )
      is Some(next) else {
      return Err(Unsupported)
    }
    controls = next
  }
  if confirmed {
    // Original confirmation reply and saved marked-request validation use
    // this SAME synchronous control frame. Keep their returned holders and
    // only share completed private scratch; failure retains the full peak.
    let request_retained = @execution.execution_capacity_retained_bytes(
      constructors[4],
    )
    let request_workspace = @execution.execution_capacity(
      0L,
      @execution.execution_capacity_execution_bytes(constructors[4]) -
      request_retained,
    ).unwrap()
    for selected in [request_workspace, constructors[5], constructors[6]] {
      guard standard_create_sequence_pair_capacity(controls, selected)
        is Some(next) else {
        return Err(Unsupported)
      }
      controls = next
    }
  }
  // Capture/read, apply/read, optional resume/read and the write have distinct
  // slots. Preserve the existing declared resume occurrence even when this
  // process has not restored anything; do not alias it to an earlier call.
  let grant_occurrences = (if checks {
      if before_send {
        5
      } else {
        4
      }
    } else {
      1
    }) +
    (if confirmed { 2 } else { 0 })
  for _ in 0..<grant_occurrences {
    // The SAME controlConstruction frame completes each synchronous Grant,
    // Ledger read and projector before the next begins. Keep every returned
    // Grant and recovery holder; an invalid async/failed prefix stops the
    // caller with this complete peak still reserved, never a next constructor.
    guard standard_create_sequence_pair_capacity(controls, grant) is Some(next) else {
      return Err(Unsupported)
    }
    controls = next
  }
  // Provider capture/recovery constructors can retain fixed metadata and
  // native material per checked row. Keep the SAME native quantities; the
  // existing capture template applies row multiplicity once from its Plan.
  let (capture_fixed, capture_rows) = match capture_original {
    None => (capture_fixed, capture_rows)
    Some(capture) => {
      // Native receives/returns only DATA; it cannot invoke Host JSON.parse
      // during its pure codec. Host parsing/stringification completes before
      // the Native call or starts after its return. Borrow all returned native
      // and Host forests across both phases, including the failed prefix.
      guard (capture.length() == 2 || capture.length() == 3) &&
        standard_create_sequence_pair_capacity(capture_fixed, capture[0])
        is Some(fixed) &&
        standard_create_sequence_pair_capacity(capture_rows, capture[1])
        is Some(rows) else {
        return Err(Unsupported)
      }
      (fixed, rows)
    }
  }
  let capacities = [
    capture_fixed,
    capture_rows,
    constructors[0],
    write_body,
    controls,
  ]
  if checks {
    guard installed_effect_http_response_construction_capacity(
        check_response_bytes,
        header_bytes,
        response_read_quantum~,
      )
      is Some(read_receive) &&
      // The same physical child retains every request output until its real
      // alias/credential cleanup. Its pure constructor workspace is acquired
      // and completed by the existing synchronous control frame above.
      standard_create_sum_capacities([
        read_receive,
        secret,
        @execution.execution_capacity(
          @execution.execution_capacity_retained_bytes(constructors[1]),
          @execution.execution_capacity_retained_bytes(constructors[1]),
        ).unwrap(),
      ])
      is Some(read_body) else {
      return Err(Unsupported)
    }
    capacities.push(read_body)
  }
  if confirmed {
    // The old physical request constructor still runs exactly once, after
    // the Preview supplies its original DispatchKey. The logical carrier
    // borrows the approved input. Its marker/body concatenation can fail
    // before Native validates that body, so keep this original input bound.
    let empty : @execution.PreparationRepresentationUnits = {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }
    guard standard_create_representation_capacity(
        {
          ..empty,
          // Original logical body, marked body and exact-request hash input
          // may coexist with the existing native/Host returned request.
          owned_utf16_units: 3L * row_input_bytes.to_int64() +
          3L * request_bytes.to_int64(),
        },
        empty,
      )
      is Some(marker) &&
      standard_create_sum_capacities([constructors[0], marker])
      is Some(finalization) &&
      installed_effect_http_response_construction_capacity(
        check_response_bytes,
        header_bytes,
        response_read_quantum~,
      )
      is Some(confirm_receive) &&
      standard_create_sum_capacities([
        confirm_receive,
        secret,
        @execution.execution_capacity(
          @execution.execution_capacity_retained_bytes(constructors[4]),
          @execution.execution_capacity_retained_bytes(constructors[4]),
        ).unwrap(),
      ])
      is Some(confirm_body) else {
      return Err(Unsupported)
    }
    capacities.push(finalization)
    capacities.push(confirm_body)
  }
  if capture_original is Some(capture) {
    capacities.push(if capture.length() == 3 { capture[2] } else { empty })
  }
  Ok(capacities)
}

///|
// The original wire/text envelope remains prepaid. Only the Host forest and
// its private parser workspace wait for the same already-owned Preview wire.
// Some(0) denotes an absent parser phase, never an invented JSON document.
fn installed_standard_host_preview_input_parts(
  policy_bytes : Int,
  policy_nodes : Int,
  policy_depth : Int,
  input_bytes : Int?,
) -> (
  @execution.PreparationRepresentationUnits,
  @execution.PreparationRepresentationUnits,
)? {
  guard @source.json_literal_construction_extent(
      policy_bytes, policy_nodes, policy_depth,
    )
    is Some(policy) else {
    return None
  }
  let bytes = input_bytes.unwrap_or(policy_bytes)
  if bytes < 0 || bytes > policy_bytes {
    return None
  }
  let empty : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  if bytes == 0 {
    return Some(
      ({ ..empty, owned_utf16_units: policy.owned_utf16_units, }, empty),
    )
  }
  let nodes = if input_bytes is Some(_) {
    Int::min(policy_nodes, bytes)
  } else {
    policy_nodes
  }
  guard @source.json_literal_construction_extent(bytes, nodes, policy_depth)
    is Some(tree) &&
    installed_host_json_retained_roles(
      {
        record_headers: tree.record_headers,
        reference_slots: tree.reference_slots,
        scalar_words: tree.scalar_words,
        owned_utf16_units: tree.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      bytes,
      nodes,
      keep_full_text=true,
    )
    is Some((retained, workspace)) else {
    return None
  }
  Some(
    ({ ..retained, owned_utf16_units: policy.owned_utf16_units, }, workspace),
  )
}

///|
/// Existing original Ledger/Receipt envelope with the selected native outcome
/// writer's byte ceiling. Larger foreign prefixes are refused by the SAME
/// selected codec before parsing; no valid selected outcome is removed. Other
/// composed implementations retain their existing full-codec fallback.
pub fn installed_effect_control_wire_bound(
  outcome_bytes : Int,
  maximum_bytes : Int,
) -> Result[Int, ClientInstalledManagedRunIssue] {
  if outcome_bytes < 1 || maximum_bytes < 1 {
    return Err(Unsupported)
  }
  let ledger_keys = [
    "attempt_sequence", "canonical_request_cid", "capability", "dispatch_key", "effect_preview_cid",
    "fence", "intent_fingerprint_cid", "logical_item_locator_cid", "logical_request_scope_cid",
    "original_membership_cid", "outcome_receipt_cid", "prior_entry_cid", "recovery_contract_cid",
    "reservation_evidence_cid", "retention_contract_cid", "self_cid", "state", "unit_definition_cid",
    "version",
  ]
  // Braces, commas, quoted keys/colons, fourteen quoted CIDs (nullable ones
  // are smaller), two safe integers, longest capability/state and version.
  let mut ledger = 2 +
    18 +
    3 * 19 +
    14 * 73 +
    2 * 16 +
    13 +
    13 +
    "actql-logical-item-ledger-entry/0.1".length() +
    2
  for key in ledger_keys {
    ledger += key.length()
  }
  let receipt_keys = [
    "credential_use_cid", "dispatch_entry_cid", "effect_member_preview_cid", "effect_preview_cid",
    "http_status_code", "response_byte_count", "response_physical_sha256", "row_preview_cid",
    "typed_outcome", "typed_outcome_cid", "version", "self_cid",
  ]
  let mut receipt = 2 +
    11 +
    3 * 12 +
    7 * 73 +
    66 +
    3 +
    16 +
    0 +
    "actql-effect-row-outcome-receipt/0.1".length() +
    2
  for key in receipt_keys {
    receipt += key.length()
  }
  let receipt = receipt.to_int64() + outcome_bytes.to_int64()
  Ok(
    Int64::min(maximum_bytes.to_int64(), Int64::max(ledger.to_int64(), receipt)).to_int(),
  )
}
