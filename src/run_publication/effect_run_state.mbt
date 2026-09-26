///|
/// Project an Effectful Run whose publication was refused because its
/// complete admitted Effect Set has unknown outcomes. The Effects to reconcile
/// are exactly the members whose admitted receipt state is unknown; no
/// Checkpoint answer, retry count or Store write can relabel them as success
/// or failure. A set without unknown outcomes has no reconciliation state.
pub fn issue_effect_reconciliation_run_state_wire(
  preview : EffectPreviewIdentity,
  set_wire : String,
  member_receipt_wires : Array[String],
  run_id : String,
  updated_at : String,
  declared_results : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RunStateIssue] {
  if run_id.is_empty() {
    return Err(InvalidRunId)
  }
  if !valid_timestamp(updated_at) {
    return Err(InvalidObservationTime("run"))
  }
  let set = match
    admit_effect_set_apply_receipt_references(
      preview, set_wire, member_receipt_wires, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(EffectSetMismatch)
  }
  if contract_string(set, "status") != Some("unknown_outcome") {
    return Err(ActionStatusMismatch)
  }
  let effects : Array[String] = []
  match @json.object_field(set.value, "effects") {
    Some(@json.Array(frozen)) =>
      for row in @json.array_values(frozen) {
        match
          (
            @json.object_field(row, "effect_id"),
            @json.object_field(row, "state"),
          ) {
          (Some(@json.String(effect_id)), Some(@json.String("unknown"))) =>
            if !effects.contains(effect_id) {
              effects.push(effect_id)
            }
          (Some(@json.String(_)), Some(@json.String(_))) => ()
          _ => return Err(EffectSetMismatch)
        }
      }
    _ => return Err(EffectSetMismatch)
  }
  if effects.is_empty() {
    return Err(ActionStatusMismatch)
  }
  effects.sort_by(@canonical.compare_utf16)
  let names = declared_results.copy()
  names.sort_by(@canonical.compare_utf16)
  let observations : Array[ResultAvailability] = []
  for name in names {
    observations.push({ name, state: Unavailable, reason: NotPublished, })
  }
  match
    validate_run_state(
      NeedsReconciliation,
      names,
      observations,
      false,
      Reconcile,
      false,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "next_action")
    @encode.begin_object(writer)
    @encode.key(writer, "effects")
    @encode.begin_array(writer)
    for effect_id in effects {
      @encode.string_value(writer, effect_id)
    }
    @encode.end_array(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, "reconcile")
    @encode.end_object(writer)
    @encode.key(writer, "result_availability")
    @encode.begin_object(writer)
    for name in names {
      @encode.key(writer, name)
      @encode.begin_object(writer)
      @encode.key(writer, "observed_at")
      @encode.string_value(writer, updated_at)
      @encode.key(writer, "reason")
      @encode.string_value(writer, "not_published")
      @encode.key(writer, "state")
      @encode.string_value(writer, "unavailable")
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "result_available")
    @encode.bool_value(writer, false)
    @encode.key(writer, "run_id")
    @encode.string_value(writer, run_id)
    @encode.key(writer, "status")
    @encode.string_value(writer, "needs_reconciliation")
    @encode.key(writer, "updated_at")
    @encode.string_value(writer, updated_at)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-run-state/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}
