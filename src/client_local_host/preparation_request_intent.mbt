///|
// Default native intake derives byte/node bounds from this original Request's
// observed SDK snapshot. The existing recursion bound and all explicitly
// selected limits remain separate; these counts never grant Resource capacity.
let request_intent_max_depth : Int = 64

///|
fn request_captured_intent_limits(
  units : Int64,
  values : Int64,
) -> @source.ParseLimits? {
  if units < 1L || values < 1L || values > units {
    return None
  }
  // SAME constructor geometry as native Program intake: six bytes per
  // observed key/Text code unit; at most32 per value for Number spelling,
  // keys' delimiters and container punctuation. This is not a new traversal.
  guard @execution.checked_preparation_add_product(0L, units - values, 6L)
    is Some(text) &&
    @execution.checked_preparation_add_product(text, values, 32L) is Some(bytes) &&
    bytes <= 2147483519L &&
    values <= 2147483643L else {
    return None
  }
  Some({
    max_input_bytes: bytes.to_int(),
    max_nodes: values.to_int(),
    max_depth: request_intent_max_depth,
  })
}

///|
// A retained intent already belongs to the original Journal/Host admission.
// Its SAME immutable wire bounds preflight; that original cursor returns actual
// node/Text geometry before native decoding. No legacy node/byte ceiling or
// second scan is inserted between this owner and its new process Request.
fn request_retained_intent_limits(wire : String) -> @source.ParseLimits? {
  let units = wire.length().to_int64()
  if units < 1L || units > 2147483519L / 3L {
    return None
  }
  Some({
    max_input_bytes: (3L * units).to_int(),
    max_nodes: units.to_int(),
    max_depth: request_intent_max_depth,
  })
}

///|
/// Default captured Program intake consumes the SAME original Request input
/// envelope as submitted-intent admission. This is immutable compiler DATA,
/// not a reservation or permission. Explicitly selected preparation limits
/// keep their original separate entry and are never recognized by equality.
pub fn[I] request_default_program_preparation_limits(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @publication_host.ClientProgramPreparationLimits,
  ClientRequestTerminalIssue,
] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  guard owner.phase == Open && request_intent_input_ready(owner) else {
    return Err(Preparation(WrongPhase))
  }
  guard request_captured_intent_limits(
      owner.snapshot_units,
      owner.snapshot_values,
    )
    is Some(selected) else {
    return Err(Preparation(Policy))
  }
  let standard = @publication_host.client_standard_program_preparation_limits()
  Ok({
    ..standard,
    checking: {
      ..standard.checking,
      input: {
        source: selected,
        tree: {
          max_nodes: selected.max_nodes,
          max_depth: selected.max_depth,
          max_string_bytes: selected.max_input_bytes,
          max_total_string_bytes: selected.max_input_bytes,
        },
        max_stages: standard.checking.input.max_stages,
      },
    },
  })
}

///|
// One bounded native Source/canonical expansion, then sequential text/hash
// emission. SDK-owned native DATA stays on its already retained snapshot.
// Source's generic Unicode/key inventory applies; no ClosedValues eligibility,
// Program geometry, policy-sized padding or second whole-input scan is used.
fn request_intent_construction_bytes(
  units : Int64,
  values : Int64,
  limits : @source.ParseLimits,
  captured? : Bool = true,
) -> Int64? {
  guard request_native_input_geometry(
      units,
      values,
      limits.max_input_bytes,
      limits.max_depth,
    )
    is Some((bytes, observed_nodes, depth)) &&
    (if captured {
      @source.captured_json_construction_extent(observed_nodes, depth)
    } else {
      @source.json_construction_extent(
        bytes,
        observed_nodes,
        depth,
        normalize_keys=false,
      )
    })
    is Some(source) else {
    return None
  }
  // Key enumeration may precede the node-limit refusal, so the Source quote
  // above retains ALL observed slots. Canonical conversion starts only after
  // that bounded Source succeeds; its SAME selected node envelope bounds the
  // canonical constructor without borrowing policy capacity.
  let nodes = Int::min(observed_nodes, limits.max_nodes)
  let n = nodes.to_int64()
  let d = depth.to_int64() + 1L
  guard @shape.map_construction_extent(n, n) is Some(maps) &&
    closed_values_sort_scratch_layout(nodes) is Some(sort) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(text) &&
    @encode.hash_writer_construction_inventory(nodes + 2, depth + 1)
    is Some(hash) else {
    return None
  }
  // from_source(data_keys=true) borrows the validated Strings. Per node:
  // canonical tag; at most FrozenArray/Array/backing and a field tuple.
  // Maps own exact-key membership; one synchronous sort peak is reused.
  let canonical : @execution.PreparationRepresentationUnits = {
    record_headers: 5L * n,
    reference_slots: 6L * n,
    scalar_words: 3L * n,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let source_units : @execution.PreparationRepresentationUnits = {
    record_headers: source.record_headers,
    reference_slots: source.reference_slots,
    scalar_words: source.scalar_words,
    owned_utf16_units: source.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  // Actual map callback/closure and emit-parent cursor families. Fixed VM
  // call frames remain trusted overhead. No per-node Resource/current calls.
  let traversal : @execution.PreparationRepresentationUnits = {
    record_headers: 8L * d + 9L,
    reference_slots: 17L * d + 15L,
    scalar_words: 10L * d + 14L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      source_units,
      canonical,
      sort,
      traversal,
      {
        record_headers: maps.record_headers,
        reference_slots: maps.reference_slots,
        scalar_words: maps.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(admission) &&
    @execution.preparation_representation_cost(admission) is Some(a) &&
    @execution.compose_preparation_representation([
      canonical,
      traversal,
      {
        record_headers: text.record_headers,
        reference_slots: text.reference_slots,
        scalar_words: text.scalar_words,
        owned_utf16_units: text.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(rendering) &&
    @execution.preparation_representation_cost(rendering) is Some(b) &&
    @execution.compose_preparation_representation([
      canonical,
      traversal,
      {
        record_headers: hash.record_headers + 3L,
        reference_slots: hash.reference_slots + 2L,
        scalar_words: hash.scalar_words + 2L,
        owned_utf16_units: hash.owned_utf16_units + bytes.to_int64() + 71L,
        owned_wire_bytes: hash.owned_wire_bytes,
      },
    ])
    is Some(hashing) &&
    @execution.preparation_representation_cost(hashing) is Some(c) else {
    return None
  }
  // Source/admission returned before rendering, whose writer returned before
  // hashing. Their scalar peaks share ONE reservation; they are not summed.
  Some(Int64::max(a, Int64::max(b, c)))
}

///|
/// SAME native SDK snapshot, identity law and Request reservation. The fixed
/// Host authenticates its original body/receipt before projecting this DATA.
pub fn[I, T] prepare_request_submitted_intent(
  owner : ClientRequestPreparation[I],
  input : I,
  captured : T,
  reader : @source.JsonDataReader[T],
) -> Result[String, ClientRequestPreparationIssue] {
  guard owner.phase == Open && !owner.intent_attempted else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  guard request_captured_intent_limits(
      owner.snapshot_units,
      owner.snapshot_values,
    )
    is Some(limits) &&
    request_intent_construction_bytes(
      owner.snapshot_units,
      owner.snapshot_values,
      limits,
    )
    is Some(bytes) else {
    return Err(Policy)
  }
  let base = match owner.intent_base {
    Some(value) => value
    None =>
      match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => {
          owner.intent_base = Some(value)
          value
        }
      }
  }
  guard @execution.checked_preparation_add_product(base.0, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(base.1, bytes, 1L) is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => {
      owner.phase = Open
      return Err(Capacity(issue))
    }
    Ok(_) => ()
  }
  owner.intent_peak_live = true
  owner.intent_attempted = true
  let result : Result[Unit, ClientRequestPreparationIssue] = preparation_module_call(
    () => {
      // One finite phase bound from the SAME observed capture, not CPU or an
      // invocation count. Existing Source/canonical/writer budgets bound work.
      let work = match
        @resources.begin_preparation_phase_work64(
          owner.capacity,
          input,
          @resources.IntentIdentity,
          owner.snapshot_units,
        ) {
        Err(issue) => return Err(Work(issue))
        Ok(value) => value
      }
      owner.intent_work = Some(work)
      match
        @resources.spend_preparation_phase_work64(work, owner.snapshot_units) {
        Err(issue) => return Err(Work(issue))
        Ok(_) => ()
      }
      let result = @publication_host.prepare_captured_client_submitted_intent(
        captured,
        reader,
        limits.max_input_bytes,
        limits.max_nodes,
        limits.max_depth,
        max_key_units_out=Some(owner.snapshot_key_units),
      )
      match @resources.finish_preparation_phase_work64(work) {
        Err(issue) => return Err(Work(issue))
        Ok(spent) => {
          owner._observed_intent_work = spent
          owner.intent_work = None
        }
      }
      match result {
        Err(issue) => Err(Intent(issue))
        Ok(value) => {
          owner.submitted_intent = Some(value)
          Ok(())
        }
      }
    },
    () => owner.phase = Open,
  )
  result.map(_ => {
    @publication_host.client_submitted_intent_cid(
      owner.submitted_intent.unwrap(),
    )
  })
}

///|
/// Separate fixed call after the constructor stack unwound. Only its exact
/// wire/CID remain beside the original snapshot; no Source/Map/writer survives.
pub fn[I] finish_request_submitted_intent(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Open &&
    owner.intent_peak_live &&
    owner.submitted_intent is Some(intent) &&
    owner.intent_base is Some((r0, e0)) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  guard @execution.preparation_representation_cost({
      record_headers: 3L,
      reference_slots: 2L,
      scalar_words: 2L,
      owned_utf16_units: @publication_host.client_submitted_intent_wire(intent)
      .length()
      .to_int64() +
      71L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) &&
    @execution.checked_preparation_add_product(r0, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e0, bytes, 1L) is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  let result = @resources.reconcile_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  owner.phase = Open
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      owner.intent_peak_live = false
      Ok(())
    }
  }
}

///|
/// Immutable intent DATA for the existing active handler/Journal borrow.
/// No current callback, reparse, new identity or permission is manufactured.
pub fn[I] request_submitted_intent_original(
  owner : ClientRequestPreparation[I],
  input : I,
) -> @publication_host.ClientSubmittedIntent? {
  if owner.phase == Selecting ||
    owner.phase == Retiring ||
    owner.phase == Closed ||
    !(owner.input is Some(original) && physical_equal(original, input)) {
    None
  } else {
    owner.submitted_intent
  }
}

///|
// One private phase predicate, not caller evidence or an admission Bool. A
// quoted/failed intent cannot be bypassed by choosing another input driver.
fn[I] request_intent_input_ready(owner : ClientRequestPreparation[I]) -> Bool {
  !owner.intent_peak_live &&
  (owner.intent_base is None || owner.submitted_intent is Some(_))
}

///|
// The existing Source cursor and Resource phase receipt coexist only during
// retained-wire preflight. Caller/resize frames use the unchanged Request
// entrance control envelope; no Program, Catalog or native tree is built here.
let request_retained_intent_control_bytes : Int64 = {
  let source = @source.json_source_preflight_control_extent()
  let work = @resources.preparation_phase_work_construction_inventory()
  @execution.preparation_representation_cost({
    record_headers: source.record_headers + work.record_headers,
    reference_slots: source.reference_slots + work.reference_slots,
    scalar_words: source.scalar_words + work.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
/// Retain the Journal's SAME admitted intent on a fresh physical-process
/// Request. This issues no intent, Request, Run or permission. The existing
/// Source preflight supplies observed geometry before native decoding; a long
/// String is never counted as one node per wire character. The cursor is
/// cancelled before the caller's native tree construction, and the original
/// snapshot quote covers that tree through the usual compiler/Plan handoff.
pub fn[I] retain_request_submitted_intent(
  owner : ClientRequestPreparation[I],
  input : I,
  intent : @publication_host.ClientSubmittedIntent,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Open &&
    !owner.intent_attempted &&
    owner.snapshot_base is None &&
    owner.submitted_intent is None else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  // Even this first extent read enters the original current callback. Fence
  // reentry before that boundary; the same Request cannot retain twice.
  owner.phase = Selecting
  let initial : Result[(Int64, Int64), ClientRequestPreparationIssue] = preparation_module_call(
    () => {
      @resources.preparation_capacity_working_extents(owner.capacity, input).map_err(issue => {
          Capacity(issue)
        },
      )
    },
    () => owner.phase = Open,
  )
  let base = match initial {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(
      base.0,
      request_retained_intent_control_bytes,
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base.1,
      request_retained_intent_control_bytes,
      1L,
    )
    is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => {
      owner.phase = Open
      return Err(Capacity(issue))
    }
    Ok(_) => ()
  }
  owner.intent_attempted = true
  owner.submitted_intent = Some(intent)
  let wire = @publication_host.client_submitted_intent_wire(intent)
  guard request_retained_intent_limits(wire) is Some(limits) else {
    return Err(Policy)
  }
  let mut cursor : @source.JsonSourcePreflight? = None
  let geometry : Result[
    @source.JsonSourceGeometry,
    ClientRequestPreparationIssue,
  ] = preparation_module_call(
    () => {
      let work = match
        @resources.begin_preparation_phase_work64(
          owner.capacity,
          input,
          IntentIdentity,
          wire.length().to_int64() + 1L,
        ) {
        Err(issue) => return Err(Work(issue))
        Ok(value) => value
      }
      owner.intent_work = Some(work)
      let source = match
        @source.start_json_source_preflight(wire, limits, data_keys=true) {
        Err(_) => return Err(Intent(InvalidEnvelope))
        Ok(value) => value
      }
      cursor = Some(source)
      while true {
        let poll = match @source.advance_json_source_preflight(source, 4096) {
          Err(_) => return Err(Intent(InvalidEnvelope))
          Ok(value) => value
        }
        let (geometry, spent) = match poll {
          @source.JsonSourceContinue(work~) => (None, work)
          @source.JsonSourceReady(value, work~) => (Some(value), work)
          @source.JsonSourceFailed(_, work=spent) => {
            match
              @resources.spend_preparation_phase_work64(work, spent.to_int64()) {
              Err(issue) => return Err(Work(issue))
              Ok(_) => ()
            }
            return Err(Intent(InvalidEnvelope))
          }
        }
        match
          @resources.spend_preparation_phase_work64(work, spent.to_int64()) {
          Err(issue) => return Err(Work(issue))
          Ok(_) => ()
        }
        if geometry is Some(value) {
          match @resources.finish_preparation_phase_work64(work) {
            Err(issue) => return Err(Work(issue))
            Ok(spent) => {
              owner._observed_intent_work = spent
              owner.intent_work = None
            }
          }
          return Ok(value)
        }
      } nobreak {
        Err(Intent(InvalidEnvelope))
      }
    },
    () => {
      if cursor is Some(source) {
        @source.cancel_json_source_preflight(source)
      }
      cursor = None
      owner.phase = Open
    },
  )
  let geometry = match geometry {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // The Source cursor has returned before native decoding. These sequential
  // peaks share the larger original reservation, never a sum or a node count
  // invented from long Text. A small snapshot reuses its larger fixed prelude;
  // the existing grow-only snapshot API must not be used as a shrink request.
  let values = geometry.node_upper.to_int64()
  let units = values + geometry.quoted_raw_utf16_units.to_int64()
  // The existing retained-wire preflight already observed quoted extents.
  // Its longest token bounds any decoded key without another scan or issuer.
  owner.snapshot_key_units.val = geometry.longest_quoted_raw_utf16
  let bytes = match request_snapshot_data_bytes(units, values) {
    None => return Err(Policy)
    Some(value) => value
  }
  owner.snapshot_base = Some(base)
  if bytes <= request_retained_intent_control_bytes {
    owner.snapshot_units = units
    owner.snapshot_values = values
    Ok(())
  } else {
    reserve_request_snapshot(owner, input, units, values)
  }
}

///|
/// Back the installed caller's retained structured Program reconstruction on
/// this SAME Request before native material decoding or full-input comparison.
/// The wire selects no semantic owner, grant, limits or admission. The later
/// original materials codec still binds the Run, compiler and complete bytes.
pub fn[I] reserve_request_retained_program_material(
  owner : ClientRequestPreparation[I],
  input : I,
  wire : String,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Open &&
    owner.intent_attempted &&
    !owner.intent_peak_live &&
    owner.submitted_intent is Some(_) &&
    owner.snapshot_base is Some(base) &&
    !owner.native_parameters_ready &&
    owner.program_json is None &&
    owner.query_syntax is None else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  // Each native JSON value needs at least one encoded code unit. This bound
  // includes the outer material and its decoded Program/Parameters Strings.
  // Reuse three existing detached-value envelopes for the simultaneously live
  // native inputs, canonical comparison collections and comparison output.
  // They depend on this actual wire, never a codec/policy maximum or spare
  // capacity. Borrowed original wire and fixed VM frames are not copies.
  let units = wire.length().to_int64() + 1L
  guard request_snapshot_data_bytes(units, units) is Some(one) &&
    @execution.checked_preparation_add_product(0L, one, 3L) is Some(bytes) &&
    @execution.checked_preparation_add_product(base.0, bytes, 1L)
    is Some(base_r) &&
    @execution.checked_preparation_add_product(base.1, bytes, 1L)
    is Some(base_e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      let (r, e) = match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
        @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
        return Err(Policy)
      }
      match
        @resources.reserve_working_preparation_phase(
          owner.capacity,
          input,
          r,
          e,
        ) {
        Err(issue) => return Err(Capacity(issue))
        Ok(_) => ()
      }
      // Imported currentness can reenter. These local original checks add no
      // callback, and the existing snapshot base retains the complete grown
      // envelope through subsequent input/Program/Plan construction.
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.snapshot_base == Some(base) &&
        owner.program_json is None &&
        !owner.native_parameters_ready else {
        return Err(ForeignOriginal)
      }
      owner.snapshot_base = Some((base_r, base_e))
      Ok(())
    },
    () => owner.phase = Open,
  )
}
