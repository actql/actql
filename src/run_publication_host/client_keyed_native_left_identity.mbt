///|
/// Actual completed left carrier, not a fabricated Result Artifact or an
/// acquisition/attempt receipt. The SAME lookup backs these retained preimages;
/// original captured Sources/prefix keep their physical and cleanup duties.
/// No strong lookup/Scope/Source backpointer escapes in this metadata token;
/// cleanup revokes the same retained export receipt before returning backing.
pub struct ClientKeyedNativeLeftIdentity {
  priv _retained_receipt : @execution.CompletedRelationExportReceipt
  logical_value_cid : String
  relation_schema_cid : String
  producer_contract_cid : String
  computation_contract_cid : String
  body : String
  schema_wire : String
  rows : Int
}

///|
// The SAME pure preplanning predicate brackets callbacks. These are mutable
// phase/slot observations only; checking it invokes no Source/current work.
fn native_left_identity_preplanning(lookup : ClientKeyedLookupInput) -> Bool {
  !lookup.closed &&
  !lookup.growing &&
  !lookup.identifying &&
  lookup.native_left_receipt is None &&
  lookup.native_left_identity is None &&
  lookup.identity_scan is None &&
  lookup.planned_requests is None &&
  lookup.left.lookup_issue is None &&
  lookup.left.requests == 0L &&
  lookup.left.attempts == 0L
}

///|
/// Freeze the actual left Relation ONCE, before request planning/dispatch and
/// before claiming the later Model Read. Borrow the original completed segment
/// output, never re-execute the prefix, copy rows or wrap it as a new Result.
pub fn prepare_client_keyed_native_left_identity(
  lookup : ClientKeyedLookupInput,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  workspace : Int,
) -> Result[ClientKeyedNativeLeftIdentity, ClientKeyedRequestIssue] {
  prepare_client_keyed_native_left_identity_owned(
    lookup,
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema,
    max_work,
    Some(workspace),
  )
}

///|
// Explicit Native callers retain their selected workspace ceiling. The
// installed captured-input entrance instead uses the existing scan geometry
// for this SAME completed output and its already selected wire/value limits.
fn prepare_client_keyed_native_left_identity_owned(
  lookup : ClientKeyedLookupInput,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  workspace : Int?,
) -> Result[ClientKeyedNativeLeftIdentity, ClientKeyedRequestIssue] {
  guard native_left_identity_preplanning(lookup) &&
    lookup.left.composed is Some(original) &&
    original.plan.keyed is Some(component) &&
    client_keyed_left_available(lookup.left) &&
    @execution.completed_segment_inputs_output(
      original.completed,
      original.sequence,
      original.inputs,
    )
    is Some(output) else {
    return Err(Assembly("foreign_or_started_native_left_identity"))
  }
  // The preceding original-current/output observations may reenter this very
  // constructor. After the LAST callback, preserve any original already
  // returned by the inner call; do not overwrite its receipt or poison it.
  guard native_left_identity_preplanning(lookup) else {
    return Err(Assembly("claimed_native_left_identity"))
  }
  lookup.identifying = true
  let result = build_client_keyed_native_left_identity(
    lookup, original, component, output, max_rows, values, payload_wire, logical_wire,
    schema, max_work, workspace,
  )
  lookup.identifying = false
  match result {
    Ok(value) => Ok(value)
    Err(issue) => {
      keyed_lookup_fail(lookup.left, issue) |> ignore
      Err(issue)
    }
  }
}

///|
fn build_client_keyed_native_left_identity(
  lookup : ClientKeyedLookupInput,
  original : ClientComposedKeyedOriginal,
  component : ClientKeyedPlanComponent,
  output : @execution.CompletedOutput,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  workspace : Int?,
) -> Result[ClientKeyedNativeLeftIdentity, ClientKeyedRequestIssue] {
  // Original token H1/R7/W1 + two retained Some H2/R2/W2, with
  // scan/grow/finish/body/measurement tuple and success/refusal frontiers.
  // The scan's actual start/next quote separately funds its writers, rows,
  // retained preimages and schema. These are this call's controls only.
  let controls = @execution.preparation_representation_cost({
    record_headers: 15L,
    reference_slots: 25L,
    scalar_words: 20L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let basis_retained = lookup.retained_bytes
  let basis_execution = lookup.execution_bytes
  guard @execution.completed_relation_identity_scan_start_construction_capacity(
      output,
      retain_body=true,
    )
    is Some(start) else {
    return Err(Assembly("native_left_start_capacity"))
  }
  match
    keyed_lookup_body_grow(
      lookup,
      basis_retained,
      basis_execution,
      controls,
      Some(start),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // RowWorkspace is a structural-entry counter, not an allocated buffer or
  // parent byte debit. Keep all selected writer/value limits unchanged. The
  // actual scan still grows its original parent before each construction.
  let workspace = match workspace {
    Some(selected) => selected
    None => {
      guard @execution.completed_relation_identity_scan_workspace_slots(
          output, values, payload_wire, logical_wire,
        )
        is Some(slots) else {
        return Err(Assembly("native_left_workspace_geometry"))
      }
      slots
    }
  }
  let scan = match
    @execution.start_completed_relation_identity_scan(
      output,
      max_rows,
      values,
      payload_wire,
      logical_wire,
      schema,
      max_work,
      workspace,
      incremental_metadata=true,
      retain_body=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(CompletedIdentity(issue))
  }
  lookup.identity_scan = Some(scan)
  while true {
    guard @execution.completed_relation_identity_scan_next_construction_capacity(
        scan,
      )
      is Some(next) else {
      return Err(Assembly("native_left_next_capacity"))
    }
    match
      keyed_lookup_body_grow(
        lookup,
        basis_retained,
        basis_execution,
        controls,
        Some(next),
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let advanced = @execution.advance_completed_relation_identity_scan(
      scan,
      31,
      construction_capacity=Some(next),
    )
    // Preserve actual consumed identity work, including every failing prefix.
    // Later right identity work has its own counter and cannot overwrite it.
    lookup.native_left_work = @execution.completed_relation_identity_scan_work(
      scan,
    )
    match advanced {
      Err(issue) => return Err(CompletedIdentity(issue))
      Ok((false, _)) => ()
      Ok((true, _)) => break
    }
  }
  let receipt = match @execution.finish_completed_relation_identity_scan(scan) {
    Ok(value) => value
    Err(issue) => return Err(CompletedIdentity(issue))
  }
  // Retain the original receipt BEFORE any later body/current failure. Cleanup
  // stops the SAME scan/receipt; failure issues neither another scan nor Read.
  lookup.native_left_receipt = Some(receipt)
  guard @execution.completed_relation_export_matches_output(receipt, output) &&
    @execution.completed_relation_export_measurement(receipt).row_count ==
    lookup.rows &&
    @execution.completed_relation_identity_scan_body(scan, receipt)
    is Some(body) else {
    return Err(Assembly("native_left_receipt"))
  }
  let logical = @execution.completed_relation_export_identity(receipt)
  let actual_schema = @execution.completed_relation_export_schema_identity(
    receipt,
  )
  let result = {
    _retained_receipt: receipt,
    logical_value_cid: @execution.logical_relation_cid(logical),
    relation_schema_cid: @execution.relation_schema_cid(actual_schema),
    // Normative input producer is the checked output contract feeding the
    // barrier, never its whole Plan, current consumer or fragment identity.
    producer_contract_cid: component.left.output_contract_cid,
    computation_contract_cid: component.left.logical_cid,
    body,
    schema_wire: @execution.relation_schema_wire(actual_schema),
    rows: lookup.rows,
  }
  @execution.cancel_completed_relation_identity_scan(scan) |> ignore
  lookup.identity_scan = None
  // Original Ref emission/current callbacks may reenter retirement. After the
  // LAST external boundary retain only pure identity/phase comparisons.
  guard client_keyed_left_available(lookup.left) &&
    !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.native_left_identity is None &&
    lookup.native_left_receipt is Some(same) &&
    physical_equal(same, receipt) &&
    lookup.left.composed is Some(same_original) &&
    physical_equal(same_original, original) else {
    return Err(Assembly("retired_native_left_identity"))
  }
  lookup.native_left_identity = Some(result)
  Ok(result)
}

///|
/// Borrow this same retained identity with no rehash, row scan or callback.
/// Upstream scope/Source evidence and durable Artifact admission remain owed.
pub fn client_keyed_native_left_identity(
  lookup : ClientKeyedLookupInput,
) -> ClientKeyedNativeLeftIdentity? {
  if lookup.closed || lookup.left.lookup_issue is Some(_) {
    None
  } else {
    match (lookup.native_left_identity, lookup.native_left_receipt) {
      (Some(value), Some(receipt)) if physical_equal(
          value._retained_receipt,
          receipt,
        ) => Some(value)
      _ => None
    }
  }
}

///|
/// The completed checked prefix already bounded its rows and column inventory.
/// Result-output row/width limits do not reclassify that earlier private input.
/// Reuse its actual counts and the selected value/wire/work policies; never
/// re-execute, copy or replace the original completed output.
pub fn prepare_client_keyed_captured_left_identity(
  lookup : ClientKeyedLookupInput,
  limits : PublicationOutputExportLimits,
  max_work : Int,
) -> Result[ClientKeyedNativeLeftIdentity, ClientKeyedRequestIssue] {
  guard lookup.left.composed is Some(original) &&
    original.plan.keyed is Some(component) else {
    return Err(Assembly("foreign_captured_left_identity"))
  }
  let width = component.original.left_fields.length()
  prepare_client_keyed_native_left_identity_owned(
    lookup,
    lookup.rows,
    limits.values,
    { ..limits.payload_wire, max_columns: width, },
    { ..limits.logical_wire, max_columns: width, },
    { ..limits.schema, max_fields: width, },
    max_work,
    None,
  )
}
