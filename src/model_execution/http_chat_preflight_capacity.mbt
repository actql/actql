///|
/// Inventory one portable preflight while its original Plan is retained.
/// Provider/contract/input values are borrowed from their existing owners.
pub fn model_http_chat_preflight_capacity(
  profile : @environment.ModelResponseProfile,
  max_frames : Int,
) -> @relation.ExecutionCapacity? {
  let bounds = @environment.model_response_profile_limits(profile)
  guard @encode.text_writer_construction_inventory(
      bounds.request_bytes,
      bounds.parse_nodes,
      bounds.parse_depth,
    )
    is Some(writer) &&
    @contract.json_schema_emission_bounded_construction_extent(max_frames)
    is Some(schema) &&
    @admitted.wire_emit_bounded_construction_inventory(max_frames)
    is Some(input) else {
    return None
  }
  let bytes = bounds.request_bytes.to_int64()
  @relation.preparation_execution_capacity({
    // The preflight pair and closures, retired projection shells, Plan and
    // invocation variant/closure, empty attachment vector, prepared body and
    // returned carriers. The body has a single no-BOM UTF8 backing.
    retained: {
      record_headers: 14L,
      reference_slots: 40L,
      scalar_words: 20L,
      owned_utf16_units: 0L,
      owned_wire_bytes: bytes,
    },
    workspace: {
      // One writer and one active emitter. The intermediate input and schema
      // strings overlap the final writer. UTF8 encoding can also retain a JS
      // input slice. The pinned non-JS encoder fills one exact byte array.
      // The fixed remainder covers projection phases/results, generation,
      // the two-message array and pair records, and the UTF8 view.
      // The bound original-startup guard and result can overlap this call.
      record_headers: writer.record_headers +
      Int64::max(schema.record_headers, input.record_headers) +
      22L,
      reference_slots: writer.reference_slots +
      Int64::max(schema.reference_slots, input.reference_slots) +
      40L,
      scalar_words: writer.scalar_words +
      Int64::max(schema.scalar_words, input.scalar_words) +
      28L,
      owned_utf16_units: writer.owned_utf16_units +
      3L * bytes +
      input.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// Additional Model Read capacity for an invocation where every eligible
/// attempt reserves before projection. All prepared Plans can coexist;
/// their writers advance serially. Use the original upper bound on slots.
pub fn model_http_chat_preflight_scope_capacity(
  profile : @environment.ModelResponseProfile,
  max_frames : Int,
  slots : Int,
  scope? : @relation.ExecutionCapacity? = None,
) -> @relation.ExecutionCapacity? {
  if slots < 0 {
    return None
  }
  if slots == 0 {
    return if scope is Some(_) {
      scope
    } else {
      @relation.execution_capacity(0L, 0L)
    }
  }
  guard model_http_chat_preflight_capacity(profile, max_frames) is Some(unit) else {
    return None
  }
  let retained = @relation.execution_capacity_retained_bytes(unit)
  let execution = @relation.execution_capacity_execution_bytes(unit)
  let bounds = @environment.model_response_profile_limits(profile)
  // ReserveSlots already buys the request bytes in its retention envelope,
  // and the existing preflight bookkeeping in its execution envelope.
  // Account each remainder in its own dimension and only one writer peak.
  let slot_retained = retained - bounds.request_bytes.to_int64()
  let slot_execution = retained - physical_preflight_metadata_bytes
  let scope_retained = scope
    .map(@relation.execution_capacity_retained_bytes)
    .unwrap_or(0L)
  let scope_execution = scope
    .map(@relation.execution_capacity_execution_bytes)
    .unwrap_or(0L)
  // The completed codec keeps only its Plan and request body. Sealing the
  // invocation Scope uses its own workspace after all request writers retire.
  let workspace = Int64::max(
    execution - retained,
    scope_execution - scope_retained,
  )
  guard @relation.checked_preparation_add_product(workspace, scope_retained, 1L)
    is Some(execution_floor) else {
    return None
  }
  guard @relation.checked_preparation_add_product(
      scope_retained,
      slots.to_int64(),
      slot_retained,
    )
    is Some(total_retained) &&
    @relation.checked_preparation_add_product(
      execution_floor,
      slots.to_int64(),
      slot_execution,
    )
    is Some(total_execution) else {
    return None
  }
  @relation.execution_capacity(total_retained, total_execution)
}

///|
/// Recheck a Portable codec against the same consumed Model startup loan.
/// No aggregate headroom, other component's token or new reservation qualifies.
pub fn check_original_model_http_chat_preflight_capacity(
  startup : OriginalModelStartup,
  provider : AdmittedStructuredModelProvider,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, ModelExecutionIssue] {
  guard startup.used &&
    startup.shared_mock is Some(purpose) &&
    physical_equal(purpose.provider, provider.capability.provider) &&
    @resources.capacity_reservation_matches(
      startup.ledger,
      startup.capacity,
      startup.retained_bytes,
      startup.execution_bytes,
    ) &&
    retained_bytes >= 0L &&
    execution_bytes >= retained_bytes else {
    return Err(RequestIdentity)
  }
  match @resources.check_original_resources_mutable(startup.ledger) {
    Err(issue) => return Err(Ledger(issue))
    Ok(_) => ()
  }
  if retained_bytes > startup.retained_bytes {
    return Err(Ledger(@resources.RetentionLimit))
  }
  if execution_bytes > startup.execution_bytes {
    return Err(Ledger(@resources.ExecutionLimit))
  }
  Ok(())
}
