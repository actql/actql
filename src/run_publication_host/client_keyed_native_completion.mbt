///|
// Immutable protocol DATA on the original lookup. This is neither a new
// acquisition owner nor evidence of Native Journal COMMIT or physical release.
pub struct ClientKeyedNativeCompletion {
  accounting : @publication.PublicationContract
  receipt : @publication.PublicationContract
  relation : @publication.PublicationContract
  ordering : @publication.ResultOrderingEvidence
  retention : @publication.PublicationContract
  evidence : @publication.PublicationContract
  input : @publication.RunEvidenceValue
  source : @publication.RunEvidenceValue
  authority_scope_cid : String
}

///|
/// Borrow immutable completed protocol DATA. The same lookup/Source still
/// owns current access, durable persistence and retirement; this is no ACK.
pub fn client_keyed_lookup_native_completion(
  lookup : ClientKeyedLookupInput,
) -> ClientKeyedNativeCompletion? {
  if lookup.closed ||
    lookup.left.lookup_issue is Some(_) ||
    lookup.identity is None {
    None
  } else {
    lookup.native_completion
  }
}

///|
// Finish before converting the original reservation to a holding and before
// claiming the Model Read. Failure retains the same original spent counters,
// captured children and peak backing for their existing cleanup owner.
fn prepare_native_keyed_lookup_completion(
  lookup : ClientKeyedLookupInput,
  recorded_at : String,
  now_ms : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard max_bytes > 0 &&
    max_nodes > 0 &&
    max_depth > 0 &&
    lookup.native_completion is None &&
    lookup.identifying &&
    !lookup.closed &&
    lookup.holding is None &&
    lookup.left.lookup_issue is None &&
    lookup.native_started_at is Some(started_at) &&
    lookup.left.started_ms is Some(started_ms) &&
    now_ms >= lookup.left.observed_ms &&
    now_ms >= started_ms &&
    @values.timestamp_epoch_milliseconds(started_at) is Some(start_epoch) &&
    @values.timestamp_epoch_milliseconds(recorded_at) is Some(recorded_epoch) &&
    recorded_epoch >= start_epoch &&
    lookup.native_issuer is Some(issuer) &&
    lookup.native_sources is Some(sources) &&
    sources.request is Some(request) &&
    sources.relation is Some(left) &&
    lookup.publication_identity is Some(identity) &&
    lookup.native_batch_plan is Some(batch) &&
    lookup.native_read_profile is Some(_) &&
    lookup.planned_order is Some(order) &&
    lookup.completed_responses == order.length() &&
    order.length() == lookup.known.length() &&
    lookup.left.composed is Some(original) &&
    original.plan.keyed is Some(component) &&
    @environment.lookup_execution_policy(
      @acquisition.lookup_bounds_policy(lookup.left.acquisition.binding.bounds),
    )
    is Some(policy) else {
    return Err(Assembly("unavailable_native_completion_originals"))
  }
  let elapsed = now_ms - started_ms
  if elapsed > 9007199254740991L ||
    elapsed >
    @environment.lookup_execution_ceiling(policy, @environment.TotalDurationMs) {
    return Err(LookupLimit("duration_ms"))
  }
  // The declared-file route has a frozen singleton inventory already. Its
  // accounting/receipt emit only fixed field spellings, bounded numeric counts
  // and CID references per original; actual time/issuer text is quoted here.
  // Preserve the Native codec policy; do not allocate the declared wire ceiling.
  let codec_bytes = if @publication.publication_contract_name(
      component.original.profile,
    ) ==
    "declared_file_content_read" {
    let text = issuer.length().to_int64() +
      started_at.length().to_int64() +
      recorded_at.length().to_int64() +
      @publication.publication_contract_json(left.scope).length().to_int64() +
      client_keyed_acquisition_source_evidence_facts(original.keyed)
      .map(facts => facts.source_ref.length().to_int64())
      .unwrap_or(0L)
    guard @execution.checked_preparation_add_product(
        8192L,
        order.length().to_int64(),
        4096L,
      )
      is Some(fixed) &&
      @execution.checked_preparation_add_product(fixed, text, 6L) is Some(bound) else {
      return Err(Assembly("capacity_overflow"))
    }
    Int64::min(bound, max_bytes.to_int64()).to_int()
  } else {
    max_bytes
  }
  // Existing protocol workspace plus the actual original-pair/sort inventory.
  // The two bounded writers allocate at most max_bytes each; they never build
  // an unbounded intermediate JSON array before applying the wire ceiling.
  let phase = match
    grow_keyed_lookup_protocol_metadata(
      lookup,
      codec_bytes,
      4L * order.length().to_int64() + 4L,
      copies=10,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result = match
    build_native_keyed_lookup_completion(
      lookup, original, component, request, left, identity, batch, started_at, recorded_at,
      issuer, elapsed, codec_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Retain before the fallible workspace return; no retry issues a second
  // receipt or resets actual consumed work after a partial failure.
  lookup.native_completion = Some(result)
  lookup.left.observed_ms = now_ms
  match
    finish_keyed_lookup_protocol_metadata(
      lookup,
      phase,
      max_nodes,
      max_depth,
      [
        result.accounting,
        result.receipt,
        result.relation,
        result.retention,
        result.evidence,
        @publication.result_ordering_evidence_contract(result.ordering),
        @publication.result_ordering_derivation_contract(result.ordering),
      ],
      evidence=[result.input, result.source],
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if @publication.publication_contract_name(component.original.profile) ==
    "declared_file_content_read" {
    prepare_declared_file_lookup_dependencies(
      lookup, result, max_nodes, max_depth,
    )
  } else {
    Ok(())
  }
}

///|
fn build_native_keyed_lookup_completion(
  lookup : ClientKeyedLookupInput,
  original : ClientComposedKeyedOriginal,
  component : ClientKeyedPlanComponent,
  request : ClientRequestIdentity,
  left : ClientKeyedNativeLeftRelation,
  identity : ClientKeyedLookupRequestIdentity,
  batch : @publication.PublicationContract,
  started_at : String,
  recorded_at : String,
  issuer : String,
  elapsed : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedNativeCompletion, ClientKeyedRequestIssue] {
  let entries : Array[
    (ClientKeyedNativeActivation, ClientKeyedNativeCapturedPage),
  ] = []
  let mut request_bytes = 0L
  let mut wire_bytes = 0L
  let mut decoded_bytes = 0L
  for slot in lookup.planned_order.unwrap() {
    guard lookup.known.get(slot) is Some((_, Some(_), Some(history))) &&
      history._retained_activation is Some(activation) &&
      history._retained_native_page is Some(partial) &&
      partial.result is Some(page) &&
      partial.receipt is Some(_) &&
      physical_equal(activation.original, lookup) &&
      physical_equal(activation.request, history.request) &&
      physical_equal(activation.definition, original.definition) &&
      physical_equal(activation.graph, original.plan) &&
      physical_equal(activation.batch, batch) &&
      client_request_identity_relation(activation.client_request, request)
      is SameRequest &&
      activation.issuer_id == issuer &&
      activation.batch_index == entries.length() &&
      history.request.attempts == 1L &&
      history.request.io_complete &&
      activation.usage.usage_final &&
      activation.usage.started_ms >= 0L &&
      activation.usage.observed_ms >= activation.usage.started_ms &&
      activation.usage.observed_ms - activation.usage.started_ms <= elapsed &&
      page.call_slot_cid ==
      @publication.publication_contract_identity(activation.slot) &&
      page.activation_cid ==
      @publication.publication_contract_identity(activation.activation) &&
      page.batch_plan_cid == @publication.publication_contract_identity(batch) &&
      @publication.lookup_raw_response_attempt(page.raw)
      is Some((raw_slot, 1L, _)) &&
      raw_slot == page.call_slot_cid &&
      @publication.lookup_raw_response_content(page.raw) is Some((_, size)) &&
      size <= activation.usage.response_decoded_bytes else {
      return Err(Assembly("incomplete_native_attempt_history"))
    }
    let usage = activation.usage
    for
      count in [
        usage.request_bytes,
        usage.response_wire_bytes,
        usage.response_decoded_bytes,
        activation.reserved_wire_bytes,
        activation.reserved_decoded_bytes,
        activation.reserved_duration_ms,
      ] {
      if count < 0L || count > 9007199254740991L {
        return Err(InvalidObservation)
      }
    }
    if request_bytes > 9007199254740991L - usage.request_bytes ||
      wire_bytes > 9007199254740991L - usage.response_wire_bytes ||
      decoded_bytes > 9007199254740991L - usage.response_decoded_bytes {
      return Err(InvalidObservation)
    }
    request_bytes += usage.request_bytes
    wire_bytes += usage.response_wire_bytes
    decoded_bytes += usage.response_decoded_bytes
    entries.push((activation, page))
  }
  // Independent aggregate correspondence: repeated left occurrences do not
  // become extra physical attempts, and no retained attempt disappears.
  if lookup.left.attempts != entries.length().to_int64() ||
    lookup.left.requests != entries.length().to_int64() ||
    lookup.left.request_bytes != request_bytes ||
    lookup.left.response_bytes != wire_bytes ||
    lookup.left.decoded_bytes != decoded_bytes {
    return Err(Assembly("native_attempt_accounting_mismatch"))
  }
  let barrier = component.barrier.logical_cid
  let input = @publication.publication_contract_identity(left.artifact)
  let batch_cid = @publication.publication_contract_identity(batch)
  entries.sort_by((a, b) => {
    @publication.publication_contract_identity(a.0.slot).compare(
      @publication.publication_contract_identity(b.0.slot),
    )
  })
  let accounting_body = try {
    let w = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(w)
    @encode.key(w, "attempts")
    @encode.begin_array(w)
    for (activation, _) in entries {
      let usage = activation.usage
      @encode.begin_object(w)
      @encode.key(w, "call_slot_cid")
      @encode.string_value(
        w,
        @publication.publication_contract_identity(activation.slot),
      )
      @encode.key(w, "dispatched")
      @encode.bool_value(w, true)
      @encode.key(w, "duration_ms")
      @encode.number_value(
        w,
        (usage.observed_ms - usage.started_ms).to_double(),
      )
      @encode.key(w, "network_attempt")
      @encode.number_value(w, 1.0)
      @encode.key(w, "redirect_count")
      @encode.number_value(w, 0.0)
      @encode.key(w, "request_bytes")
      @encode.number_value(w, usage.request_bytes.to_double())
      @encode.key(w, "reserved_decoded_bytes")
      @encode.number_value(w, activation.reserved_decoded_bytes.to_double())
      @encode.key(w, "reserved_duration_ms")
      @encode.number_value(w, activation.reserved_duration_ms.to_double())
      @encode.key(w, "reserved_wire_bytes")
      @encode.number_value(w, activation.reserved_wire_bytes.to_double())
      @encode.key(w, "response_decoded_bytes")
      @encode.number_value(w, usage.response_decoded_bytes.to_double())
      @encode.key(w, "response_wire_bytes")
      @encode.number_value(w, usage.response_wire_bytes.to_double())
      @encode.key(w, "usage_final")
      @encode.bool_value(w, true)
      @encode.key(w, "usage_resolution_event_cid")
      @encode.null_value(w)
      @encode.end_object(w)
    }
    @encode.end_array(w)
    @encode.key(w, "authority_scope_cid")
    @encode.string_value(w, client_request_authority_scope_cid(request))
    @encode.key(w, "barrier_cid")
    @encode.string_value(w, barrier)
    @encode.key(w, "batch_plan_cid")
    @encode.string_value(w, batch_cid)
    @encode.key(w, "elapsed_ms")
    @encode.number_value(w, elapsed.to_double())
    @encode.key(w, "input_relation_artifact_cid")
    @encode.string_value(w, input)
    @encode.key(w, "issuer_id")
    @encode.string_value(w, issuer)
    @encode.key(w, "previous_accounting_cid")
    @encode.null_value(w)
    @encode.key(w, "recorded_at")
    @encode.string_value(w, recorded_at)
    @encode.key(w, "totals")
    @encode.begin_object(w)
    @encode.key(w, "network_attempts")
    @encode.number_value(w, entries.length().to_double())
    @encode.key(w, "request_bytes")
    @encode.number_value(w, request_bytes.to_double())
    @encode.key(w, "response_decoded_bytes")
    @encode.number_value(w, decoded_bytes.to_double())
    @encode.key(w, "response_wire_bytes")
    @encode.number_value(w, wire_bytes.to_double())
    @encode.end_object(w)
    @encode.key(w, "version")
    @encode.string_value(w, "actql-lookup-accounting-evidence/0.1")
    @encode.end_object(w)
    @encode.finish(w)
  } catch {
    _ => return Err(Assembly("native_accounting_encoding"))
  }
  let accounting = match
    native_lookup_seal(
      "lookup_accounting", accounting_body, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  entries.sort_by((a, b) => a.0.batch_index.compare(b.0.batch_index))
  let lifecycle = [
    ("accounting", @publication.publication_contract_identity(accounting)),
  ]
  for (activation, page) in entries {
    for
      (kind, contract) in [
        ("activation", activation.activation),
        ("adoption", page.adoption),
        ("attempt_event", page.event),
      ] {
      lifecycle.push(
        (kind, @publication.publication_contract_identity(contract)),
      )
    }
  }
  lifecycle.sort_by((a, b) => {
    let order = @canonical_value.compare_utf16(a.0, b.0)
    if order == 0 {
      @canonical_value.compare_utf16(a.1, b.1)
    } else {
      order
    }
  })
  let receipt_body = try {
    let w = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(w)
    @encode.key(w, "attempts")
    emit_native_completed_lookup_attempts(entries, w)
    @encode.key(w, "barrier_cid")
    @encode.string_value(w, barrier)
    @encode.key(w, "batch_plan_cid")
    @encode.string_value(w, batch_cid)
    @encode.key(w, "input_relation_artifact_cid")
    @encode.string_value(w, input)
    @encode.key(w, "lifecycle_evidence")
    @encode.begin_array(w)
    // Sort our exact original references before issuance; incoming sealed
    // bodies must already have this order and are never silently repaired.
    for (kind, cid) in lifecycle {
      @encode.begin_object(w)
      @encode.key(w, "cid")
      @encode.string_value(w, cid)
      @encode.key(w, "kind")
      @encode.string_value(w, kind)
      @encode.end_object(w)
    }
    @encode.end_array(w)
    @encode.key(w, "previous_receipt_cid")
    @encode.null_value(w)
    @encode.key(w, "recorded_at")
    @encode.string_value(w, recorded_at)
    @encode.key(w, "request_key_set_cid")
    @encode.string_value(
      w,
      @publication.publication_contract_identity(identity.keys),
    )
    @encode.key(w, "source_request_egress_admission_cid")
    @encode.null_value(w)
    @encode.key(w, "started_at")
    @encode.string_value(w, started_at)
    @encode.key(w, "state")
    @encode.string_value(w, "succeeded")
    @encode.key(w, "version")
    @encode.string_value(w, "actql-lookup-attempt-receipt/0.1")
    @encode.end_object(w)
    @encode.finish(w)
  } catch {
    _ => return Err(Assembly("native_attempt_receipt_encoding"))
  }
  let receipt = match
    native_lookup_seal(
      "acquisition_attempt_receipt", receipt_body, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  build_native_keyed_lookup_relation_evidence(
    lookup, component, request, left, identity, batch, entries, accounting, receipt,
    recorded_at, issuer, max_bytes, max_nodes, max_depth,
  )
}

///|
fn emit_native_completed_lookup_attempts(
  entries : Array[(ClientKeyedNativeActivation, ClientKeyedNativeCapturedPage)],
  w : @encode.Writer,
) -> Unit raise {
  @encode.begin_array(w)
  for (activation, page) in entries {
    @encode.begin_object(w)
    @encode.key(w, "batch_index")
    @encode.number_value(w, activation.batch_index.to_double())
    @encode.key(w, "call_slot_cid")
    @encode.string_value(w, page.call_slot_cid)
    @encode.key(w, "network_attempt")
    @encode.number_value(w, 1.0)
    @encode.key(w, "outcome")
    @encode.string_value(w, "captured")
    @encode.key(w, "page_index")
    @encode.number_value(w, 0.0)
    @encode.key(w, "raw_response_artifact_cid")
    @encode.string_value(
      w,
      @publication.publication_contract_identity(page.raw),
    )
    @encode.key(w, "semantic_request_cid")
    @encode.string_value(
      w,
      @publication.publication_contract_identity(activation.semantic_request),
    )
    @encode.end_object(w)
  }
  @encode.end_array(w)
}
