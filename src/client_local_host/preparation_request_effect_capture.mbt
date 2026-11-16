///|
// SAME staged Store reader only: four dedicated binary backings (encrypted
// receive, decoded ciphertext, authenticated plaintext, failed/final concat).
// Each is bounded by the selected immutable encrypted extent. These are raw
// octets, not four opaque canonical-writer allowances. Keep them through the
// trusted Store return; failure never cuts this prefix.
//
// After AEAD the Core staged inverse uses its actual authenticated plaintext
// UTF8 extent; the SAME Common Read selects that extent for nested emission.
// Before that original geometry exists the encrypted extent remains the bound.
// The actual text/hash owners therefore price that bounded constructor here.
// Existing decoded-text, tree, validation and depth inventories stay separate;
// the legacy wire-only reader retains its original generic quote.
fn request_effect_capture_staged_wire_capacity(
  bytes : Int,
  plaintext_bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard bytes >= 0 &&
    plaintext_bytes >= 0 &&
    plaintext_bytes <= bytes &&
    nodes >= 0 &&
    depth >= 0 &&
    @encode.text_writer_construction_inventory(
      plaintext_bytes,
      Int::max(1, nodes),
      depth,
    )
    is Some(text) &&
    @encode.hash_writer_construction_inventory(nodes, depth) is Some(hash) &&
    request_effect_capture_binary_bytes(bytes, true) is Some(binary) else {
    return None
  }
  guard @execution.preparation_representation_cost({
      // Dedicated Buffer/backing controls remain on the same Read until its
      // original cleanup. Variable backing lifetime is priced separately.
      record_headers: 8L,
      reference_slots: 8L,
      scalar_words: 8L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(control) &&
    @execution.preparation_representation_cost({
      record_headers: text.record_headers + hash.record_headers,
      reference_slots: text.reference_slots + hash.reference_slots,
      scalar_words: text.scalar_words + hash.scalar_words,
      owned_utf16_units: text.owned_utf16_units + hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(writer) &&
    @execution.checked_preparation_add_product(
      writer,
      plaintext_bytes.to_int64(),
      1L,
    )
    is Some(decoded) &&
    @execution.checked_preparation_add_product(control, binary, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      control,
      Int64::max(binary, decoded),
      1L,
    )
    is Some(execution) else {
    return None
  }
  // readPrivateEvidenceObject returns only authenticated plaintext. Its
  // encrypted receive/ciphertext/decipher/final-concat frame has returned
  // BEFORE releaseBytes and the decoded contract writers are entered.
  // The synchronous consume callback may still borrow its ONE plaintext
  // Buffer, so keep B beside the full text/hash constructor. Failure during
  // physical IO keeps its whole four-backing peak and never enters writers.
  // R preserves that IO peak; E is MAX(IO, one-buffer+writer), not a credit
  // for a live buffer or a cut before the original Store/Read cleanup.
  @execution.execution_capacity(retained, execution)
}

///|
fn request_effect_capture_binary_bytes(bytes : Int, staged : Bool) -> Int64? {
  @execution.execution_capacity_inventory_add(
    0L,
    if staged {
      QuotedBytes
    } else {
      CanonicalWireBytes
    },
    bytes.to_int64(),
    4,
  )
}

///|
/// Private capture read material on the existing Request reservation. These
/// are the established executor units, not a new heap tariff or a wire cap.
/// The actual encrypted extent bounds plaintext and aggregate decoded text;
/// every JSON value occupies at least one wire byte. No claimed row count or
/// smaller public collection bound can replace this original extent.
fn request_effect_capture_recovery_capacity(
  encrypted_bytes : Int,
  definition_units : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  nodes? : Int? = None,
  definition_nodes? : Int? = None,
  staged_envelope? : Bool = false,
  envelope_nodes? : Int? = None,
  plaintext_bytes? : Int? = None,
  envelope_units? : Int = 0,
) -> @execution.ExecutionCapacity? {
  let tree_nodes = nodes.unwrap_or(
    if staged_envelope {
      envelope_nodes.unwrap_or(0)
    } else {
      encrypted_bytes
    },
  )
  let definition_tree_nodes = definition_nodes.unwrap_or(definition_units)
  let decoded_bytes = plaintext_bytes.unwrap_or(encrypted_bytes)
  if encrypted_bytes < 0 ||
    decoded_bytes < 0 ||
    decoded_bytes > encrypted_bytes ||
    envelope_units < 0 ||
    envelope_units > encrypted_bytes ||
    (plaintext_bytes is Some(_) && !staged_envelope) ||
    tree_nodes < 0 ||
    definition_units < 0 ||
    definition_tree_nodes < 0 ||
    definition_tree_nodes > definition_units ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return None
  }
  let bytes = encrypted_bytes.to_int64()
  // Before AEAD, the encrypted JSON envelope itself still needs one full
  // conservative native tree. After AEAD, retain the larger of that envelope
  // peak and the three inventories bounded by the actual plaintext spelling.
  // Legacy cold callers without plaintext geometry retain their original quote.
  let node_slots = match nodes {
    None =>
      if staged_envelope {
        envelope_nodes.unwrap_or(0).to_int64()
      } else {
        bytes * 3L
      }
    Some(_) =>
      Int64::max(
        if staged_envelope {
          envelope_nodes.unwrap_or(0).to_int64()
        } else {
          bytes
        },
        tree_nodes.to_int64() * 3L,
      )
  }
  let base = @execution.execution_capacity_inventory(
    [
      // One selected physical piece and one failed-close piece can coexist.
      // The Store's original consumeObject piece bound is 65536, independent
      // of a small capture record and of the payloads it validates.
      { unit: QuotedBytes, count: 65536L, copies: 2, },
      // One fixed read/retirement control group, using the same established
      // coarse Host control allowance as the private Request entrance.
      { unit: QuotedBytes, count: 4096L, copies: 1, },
      // Key, nonce and authentication tag have dedicated original backings.
      { unit: QuotedBytes, count: 32L + 12L + 16L, copies: 1, },
      // The original Definition wire getter is an alias; re-admitting that
      // contract creates one additional bounded tree/text backing before
      // capture metadata is known. Admit it in the initial zero-extent phase.
      // Only the live owner's successful constructor may select its recorded
      // final node count. Initial/cold/failed calls keep the original peak.
      {
        unit: ValueNodeSlots,
        count: definition_tree_nodes.to_int64(),
        copies: 1,
      },
      { unit: DecodedTextBytes, count: definition_units.to_int64(), copies: 1, },
      // Capture JSON, retained typed contracts, and prepared schema/member
      // inventory coexist during construction. Successful Store return cuts
      // only the full parsed container; the returned two tree inventories
      // stay backed until their original child cleanup has completed.
      { unit: ValueNodeSlots, count: node_slots, copies: 1, },
      // Capture wire, decoded record strings, and independently decoded typed
      // strings. A getter alias of an existing wire is not another copy.
      { unit: DecodedTextBytes, count: decoded_bytes.to_int64(), copies: 3, },
      // The encrypted envelope String remains an original alias through this
      // Read. Before plaintext geometry exists its backing is covered by the
      // old byte-derived text peak; after refinement price it independently.
      {
        unit: QuotedBytes,
        count: if plaintext_bytes is Some(_) {
          envelope_units.to_int64() * 2L
        } else {
          0L
        },
        copies: 1,
      },
      // Encrypted record/ciphertext, plaintext and Store writer or failed-child
      // bytes coexist during construction. Only successful Store return cuts
      // all four buffers; retained Strings have their separate bounds above.
      // Directory/FD ownership and failed cleanup stay with that Store.
      // Staged readers fund the actual dedicated binary backings below.
      // Legacy readers keep their prior opaque wire-construction envelope.
      {
        unit: CanonicalWireBytes,
        count: bytes,
        copies: if staged_envelope {
          0
        } else {
          4
        },
      },
    ],
    [
      // Active bounded Common validation/tree and canonical writer workspace
      // overlap the complete retained inventory, including partial failure.
      {
        unit: ValueNodeSlots,
        count: Int::min(tree_nodes, max_nodes).to_int64(),
        copies: 2,
      },
      // The staged adapter's exact byte-bounded writer/hash constructor is
      // below; an opaque legacy caller still needs the original envelope.
      {
        unit: CanonicalWireBytes,
        count: bytes,
        copies: if staged_envelope {
          0
        } else {
          4
        },
      },
      {
        unit: CursorRootSlots,
        count: Int::min(encrypted_bytes, max_depth).to_int64(),
        copies: 2,
      },
    ],
    RetainedAlongsideExecution,
  )
  guard base is Some(base) else { return None }
  let work = @resources.preparation_phase_work_continuation64_construction_inventory()
  let (utf8_h, utf8_r, utf8_w) = @scalar.utf8_length_admission_construction_units()
  guard @execution.preparation_representation_cost({
      // Re-entry adds the constructCaptured closure (state/view captures and
      // its view slot:1H3R), the publications/borrow return-retainer (1H2R),
      // and one Reflect.apply Array/backing (2H2R).
      // Fund these before the Read view escapes; no later callback borrows
      // spare decode workspace for these still-live fixed control cells.
      // Final publication borrows this SAME Read through its completed owner,
      // publication options, private preparation and current Store call (4R).
      // Its synchronous call carrier has one two-reference record plus an
      // argument Array/backing with at most ten references (3H12R). Table's
      // recovered Preview is the ten-argument maximum of this same adapter;
      // its existing options carrier additionally retains this Read (1R).
      // Sequential carriers remain separate from all returned receipt trees.
      // The SAME acquired-extent scalar cell and immutable nested limits
      // record add2H/8R/4W: cell1H1W, limits1H3W; eight references cover the
      // original Read/consume async frames and their existing closures.
      // Staged geometry uses the scalar owner's allocation-free UTF8
      // admission controls plus one retained Some(P). Its field is one
      // reference on the original Read/material record even before admission;
      // the installed resize current fence also captures that SAME Option.
      // Same-wire node/longest-key/total-key facts add three material
      // references and optional scalar carriers (3H3R3W) before issue.
      // The selected retained-validation method adds1H3R and its captured
      // Core entry adds1R. Its completion-phase scalar is priced below.
      record_headers: work.record_headers +
      21L +
      (if staged_envelope { utf8_h + 1L } else { 0L }),
      reference_slots: work.reference_slots +
      57L +
      (if staged_envelope { utf8_r } else { 0L }),
      // The same Read distinguishes its prepared-token retirement from the
      // ordinary admitted capture's alias release with one retained Bool.
      // The installed Read's completion-phase word and Host validation-entry
      // reference exist before its first construction, not at later reentry.
      scalar_words: work.scalar_words +
      21L +
      (if staged_envelope { utf8_w + 1L } else { 0L }),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(control) &&
    @execution.execution_capacity(control, control) is Some(fixed) else {
    return None
  }
  guard installed_effect_dependency_fixed_capacity(0, 0, max_depth)
    is Some(lexical) else {
    return None
  }
  if staged_envelope {
    guard request_effect_capture_staged_wire_capacity(
        encrypted_bytes,
        decoded_bytes,
        Int::min(tree_nodes, max_nodes),
        Int::min(encrypted_bytes, max_depth),
      )
      is Some(wire) else {
      return None
    }
    standard_create_sum_capacities(
      [base, fixed, lexical, wire],
      sequential_workspace=false,
    )
  } else {
    standard_create_sum_capacities(
      [base, fixed, lexical],
      sequential_workspace=false,
    )
  }
}

///|
/// Bind the already authorized journal Request/Run to its existing generic
/// resource preparation. No Request, Run, compiler, Ledger, read grant, claim
/// or continuation is issued here. The fixed Host retains this parent before
/// calling, and retires its actual Store/schema children before ordinary Abort.
/// Zero extent admits the fixed physical read overlap before metadata lookup;
/// the SAME reservation grows to the exact selected extent before decryption.
pub fn[I] reserve_request_effect_capture_recovery(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  encrypted_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  reserve_request_effect_capture_recovery_owned(
    owner, input, request, definition, encrypted_bytes, max_wire_bytes, max_nodes,
    max_depth, false,
  )
}

///|
pub fn[I] reserve_request_effect_capture_encrypted(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  encrypted_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  reserve_request_effect_capture_recovery_owned(
    owner, input, request, definition, encrypted_bytes, max_wire_bytes, max_nodes,
    max_depth, true,
  )
}

///|
fn[I] reserve_request_effect_capture_recovery_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  encrypted_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  staged_envelope : Bool,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard (owner.phase == Open || owner.phase == EffectCaptureRecovery) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is None &&
    owner.effect_capacity is None &&
    @publication.publication_contract_name(definition) == "run_definition" else {
    return Err(ForeignOriginal)
  }
  let required = match
    request_effect_capture_recovery_capacity(
      encrypted_bytes,
      @publication.publication_contract_json(definition).length(),
      max_wire_bytes,
      max_nodes,
      max_depth,
      staged_envelope~,
    ) {
    None => return Err(Policy)
    Some(value) => value
  }
  match owner.program_domain_compilation_inputs {
    None => {
      if owner.phase != Open ||
        owner.snapshot_base is Some(_) ||
        owner.submitted_intent is Some(_) ||
        owner.program_json is Some(_) ||
        owner.program_check is Some(_) {
        return Err(WrongPhase)
      }
      let base = match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      // The two-reference domain variant uses the existing four-reference
      // resident slot. Its fixed controls use the Request entrance allowance.
      owner.program_domain_compilation_inputs = Some(
        RequestEffectCaptureRecovery(request, definition, None),
      )
      owner.program_plan_quote = Some(base)
      owner.phase = EffectCaptureRecovery
    }
    Some(RequestEffectCaptureRecovery(old_request, old_definition, material)) => {
      if !physical_equal(old_request, request) ||
        !physical_equal(old_definition, definition) {
        return Err(ForeignOriginal)
      }
      if material is Some(material) &&
        (
          material.max_wire_bytes != max_wire_bytes ||
          material.max_nodes != max_nodes ||
          material.max_depth != max_depth ||
          material.staged_envelope != staged_envelope
        ) {
        return Err(ForeignOriginal)
      }
    }
    _ => return Err(ForeignOriginal)
  }
  guard owner.program_plan_quote is Some((base_r, base_e)) &&
    @execution.checked_preparation_add_product(
      base_r,
      @execution.execution_capacity_retained_bytes(required),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base_e,
      @execution.execution_capacity_execution_bytes(required),
      1L,
    )
    is Some(e) else {
    return Err(Policy)
  }
  let (r, e) = match owner.program_domain_quote {
    None => (r, e)
    Some((old_r, old_e)) => (Int64::max(r, old_r), Int64::max(e, old_e))
  }
  owner.program_domain_quote = Some((r, e))
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  // The original current callback can reenter. Do not revive a closed owner
  // or replace the selected original after it returns or declines admission.
  if owner.phase != Selecting ||
    !(owner.input is Some(original) && physical_equal(original, input)) ||
    !(owner.program_domain_compilation_inputs
    is Some(RequestEffectCaptureRecovery(old_request, old_definition, _)) &&
    physical_equal(old_request, request) &&
    physical_equal(old_definition, definition)) {
    return Err(ForeignOriginal)
  }
  owner.phase = EffectCaptureRecovery
  match result {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  match owner.program_domain_compilation_inputs {
    Some(RequestEffectCaptureRecovery(_, _, Some(material))) =>
      if encrypted_bytes > 0 {
        material.encrypted_bytes = Some(
          Int::max(material.encrypted_bytes.unwrap_or(0), encrypted_bytes),
        )
      }
    _ =>
      owner.program_domain_compilation_inputs = Some(
        RequestEffectCaptureRecovery(
          request,
          definition,
          Some({
            plaintext_bytes: None,
            encrypted_bytes: if encrypted_bytes > 0 {
              Some(encrypted_bytes)
            } else {
              None
            },
            wire: None,
            staged_envelope,
            envelope_wire: None,
            envelope_nodes: None,
            observed_wire: None,
            nodes: None,
            decoded_nodes: None,
            decoded_key_units: None,
            decoded_key_total: None,
            captured: None,
            work: None,
            max_wire_bytes,
            max_nodes,
            max_depth,
          }),
        ),
      )
  }
  Ok(())
}
