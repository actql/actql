///|
pub(all) enum EffectPreviewIdentityIssue {
  PreviewShape(PublicationContractIssue)
  InvalidMember
  RowInventoryMismatch(Int)
  RowIdentityMismatch(Int, Int)
  MemberIdentityMismatch(Int)
  PreviewIdentityMismatch
  RunBindingMismatch
  AuthoringBindingMismatch
  AuthoringIdentityMismatch
  Encoding
} derive(Eq, Debug)

///|
pub(all) enum EffectPreviewResolvedContract {
  Mapping(String, String)
  Command(String, String)
} derive(Eq, Debug)

///|
pub struct EffectPreviewIdentity {
  semantic_cid : String
  member_cids : Array[String]
  member_effect_ids : Array[String]
  member_effect_kinds : Array[String]
  member_effect_plan_cids : Array[String?]
  member_source_results : Array[String?]
  member_result_artifact_cids : Array[String?]
  member_max_items : Array[Int64]
  member_contracts : Array[EffectPreviewResolvedContract]
  member_failure_policies : Array[String]
  member_footprints : Array[EffectPreviewFootprintIdentity]
  row_keys : Array[Array[String]]
  row_cids : Array[Array[String]]
  row_indices : Array[Map[String, Int]]
  row_correlation_wires : Array[Array[String]]
  row_intended_change_states : Array[Array[String]]
  row_intended_value_wires : Array[Array[String]]
  row_guard_version_cids : Array[Array[String]]
  ordered_row_correlation_wires : Array[Array[String]]
  ordered_row_intended_change_states : Array[Array[String]]
  ordered_row_intended_value_wires : Array[Array[String]]
  row_order : Array[Array[String]]
  run_identity_cid : String
  authoring_context_cid : String
  program_semantics_cid : String
  program_definition_cid : String
  invocation_cid : String
  compiled_plan_cid : String
  check_environment_cid : String
}

///|
/// Retained semantic footprint from the admitted private Preview. This is
/// evidence of what the Preview claims, not proof that a physical request
/// targets these objects or that the complete Effect Set is safe to send.
pub struct EffectPreviewFootprintIdentity {
  kind : String
  provider_namespace : String
  provider_boundary_cid : String
  resource_identity_scheme_cid : String
  resource_kind : String
  provider_object_identity_cids : Array[String]
}

///|
pub fn effect_preview_footprint_kind(
  value : EffectPreviewFootprintIdentity,
) -> String {
  value.kind
}

///|
pub fn effect_preview_footprint_provider_namespace(
  value : EffectPreviewFootprintIdentity,
) -> String {
  value.provider_namespace
}

///|
pub fn effect_preview_footprint_provider_boundary_cid(
  value : EffectPreviewFootprintIdentity,
) -> String {
  value.provider_boundary_cid
}

///|
pub fn effect_preview_footprint_resource_identity_scheme_cid(
  value : EffectPreviewFootprintIdentity,
) -> String {
  value.resource_identity_scheme_cid
}

///|
pub fn effect_preview_footprint_resource_kind(
  value : EffectPreviewFootprintIdentity,
) -> String {
  value.resource_kind
}

///|
pub fn effect_preview_footprint_target_count(
  value : EffectPreviewFootprintIdentity,
) -> Int {
  value.provider_object_identity_cids.length()
}

///|
pub fn effect_preview_footprint_target_cid(
  value : EffectPreviewFootprintIdentity,
  index : Int,
) -> String? {
  value.provider_object_identity_cids.get(index)
}

///|
fn retain_effect_preview_footprint(
  effect : @json.CanonicalValue,
) -> EffectPreviewFootprintIdentity? {
  guard @json.object_field(effect, "write_footprint") is Some(footprint) &&
    @json.object_field(footprint, "kind") is Some(@json.String(kind)) &&
    @json.object_field(footprint, "provider_namespace")
    is Some(@json.String(provider_namespace)) &&
    @json.object_field(footprint, "provider_boundary_cid")
    is Some(@json.String(provider_boundary_cid)) &&
    @json.object_field(footprint, "resource_identity_scheme_cid")
    is Some(@json.String(resource_identity_scheme_cid)) &&
    @json.object_field(footprint, "resource_kind")
    is Some(@json.String(resource_kind)) &&
    @json.object_field(footprint, "provider_object_identity_cids")
    is Some(@json.Array(frozen)) else {
    return None
  }
  let provider_object_identity_cids : Array[String] = []
  for item in @json.array_values(frozen) {
    guard item is @json.String(cid) else { return None }
    provider_object_identity_cids.push(cid)
  }
  Some({
    kind,
    provider_namespace,
    provider_boundary_cid,
    resource_identity_scheme_cid,
    resource_kind,
    provider_object_identity_cids,
  })
}

///|
fn emit_effect_change_semantics(
  value : @json.CanonicalValue,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let fields = @json.object_fields(value).unwrap()
  @encode.begin_object(writer)
  for (name, child) in fields {
    if name != "row_idempotency_key" {
      @encode.key(writer, name)
      @json.emit_value(child, writer)
    }
  }
  @encode.end_object(writer)
}

///|
fn emit_effect_member_semantics(
  value : @json.CanonicalValue,
  writer : @encode.Writer,
  identity_override : String?,
) -> Unit raise @encode.EncodeFailure {
  let fields = @json.object_fields(value).unwrap()
  @encode.begin_object(writer)
  for (name, child) in fields {
    if name == "effect_member_preview_cid" && identity_override is None {
      continue
    }
    @encode.key(writer, name)
    if name == "effect_member_preview_cid" {
      @encode.string_value(writer, identity_override.unwrap())
    } else if name == "changes" {
      let changes = match child {
        @json.Array(items) => @json.array_values(items)
        _ => abort("Effect Preview shape admission required")
      }
      @encode.begin_array(writer)
      for change in changes {
        emit_effect_change_semantics(change, writer)
      }
      @encode.end_array(writer)
    } else {
      @json.emit_value(child, writer)
    }
  }
  @encode.end_object(writer)
}

///|
fn effect_member_semantic_cid(
  effect : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectPreviewIdentityIssue] {
  let writer = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let digest = try {
    @encode.begin_object(writer)
    @encode.key(writer, "member")
    emit_effect_member_semantics(effect, writer, None)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-member-preview/0.1")
    @encode.end_object(writer)
    @encode.finish_hash(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok("sha256:" + digest)
}

///|
fn effect_preview_semantic_cid(
  preview : @json.CanonicalValue,
  member_cids : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectPreviewIdentityIssue] {
  let writer = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let digest = try {
    @encode.begin_object(writer)
    for (name, child) in @json.object_fields(preview).unwrap() {
      if name == "effect_preview_cid" ||
        name == "run_identity_cid" ||
        name == "authoring_context" {
        continue
      }
      @encode.key(writer, name)
      if name == "effects" {
        let members = match child {
          @json.Array(items) => @json.array_values(items)
          _ => abort("Effect Preview shape admission required")
        }
        @encode.begin_array(writer)
        for index in 0..<members.length() {
          emit_effect_member_semantics(
            members[index],
            writer,
            Some(member_cids[index]),
          )
        }
        @encode.end_array(writer)
      } else {
        @json.emit_value(child, writer)
      }
    }
    @encode.end_object(writer)
    @encode.finish_hash(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok("sha256:" + digest)
}

///|
fn effect_preview_row_cid(
  preview : @json.CanonicalValue,
  effect : @json.CanonicalValue,
  change : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectPreviewIdentityIssue] {
  guard @json.object_field(preview, "program_definition_cid") is Some(program) &&
    @json.object_field(preview, "invocation_cid") is Some(invocation) &&
    @json.object_field(effect, "effect_identity_cid") is Some(effect_identity) &&
    @json.object_field(effect, "effect_kind") is Some(@json.String(operation)) &&
    @json.object_field(effect, "preview_strength")
    is Some(@json.String(strength)) &&
    @json.object_field(change, "target_row_identity") is Some(target) &&
    @json.object_field(change, "target_guard") is Some(guard_value) &&
    @json.object_field(change, "intended_changes") is Some(intended) &&
    @json.object_field(change, "before") is Some(before) &&
    @json.object_field(change, "after") is Some(after) else {
    return Err(InvalidMember)
  }
  let contract = if operation == "command" {
    @json.object_field(effect, "resolved_command_contract_cid")
  } else {
    @json.object_field(effect, "resolved_mapping_contract_cid")
  }
  guard contract is Some(resolved_contract) else { return Err(InvalidMember) }
  guard @json.object_field(guard_value, "state")
    is Some(@json.String(guard_state)) &&
    @json.object_field(intended, "state") is Some(@json.String(intended_state)) else {
    return Err(InvalidMember)
  }
  let guarded_preview = strength == "full_diff" || strength == "targeted"
  let before_present = match @json.object_field(before, "state") {
    Some(@json.String("present")) => true
    _ => false
  }
  let update_side_upsert = operation == "upsert" && before_present
  if (
      guarded_preview &&
      (operation == "update" || operation == "delete" || update_side_upsert) &&
      guard_state != "version"
    ) ||
    (operation == "create" && guard_state != "not_applicable") ||
    (operation == "delete" && intended_state != "not_applicable") ||
    (
      operation != "delete" &&
      operation != "command" &&
      intended_state != "present"
    ) {
    return Err(InvalidMember)
  }
  let writer = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let digest = try {
    @encode.begin_object(writer)
    @encode.key(writer, "after")
    @json.emit_value(after, writer)
    @encode.key(writer, "before")
    @json.emit_value(before, writer)
    @encode.key(writer, "effect_identity_cid")
    @json.emit_value(effect_identity, writer)
    @encode.key(writer, "intended_changes")
    @json.emit_value(intended, writer)
    @encode.key(writer, "invocation_cid")
    @json.emit_value(invocation, writer)
    @encode.key(writer, "operation")
    @encode.string_value(writer, operation)
    @encode.key(writer, "preview_strength")
    @encode.string_value(writer, strength)
    @encode.key(writer, "program_definition_cid")
    @json.emit_value(program, writer)
    @encode.key(writer, "resolved_contract_cid")
    @json.emit_value(resolved_contract, writer)
    @encode.key(writer, "target_guard")
    @json.emit_value(guard_value, writer)
    @encode.key(writer, "target_row_identity")
    @json.emit_value(target, writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-preview-row/0.1")
    @encode.end_object(writer)
    @encode.finish_hash(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok("sha256:" + digest)
}

///|
/// Derive row identities before sealing member and set identities. Supplied
/// row CIDs are placeholders here; admission compares them separately.
pub fn derive_effect_preview_row_identities(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[Array[String]], EffectPreviewIdentityIssue] {
  let preview = match
    parse_effect_preview_shape(wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(PreviewShape(issue))
  }
  let members = match @json.object_field(preview, "effects") {
    Some(@json.Array(items)) => @json.array_values(items)
    _ => return Err(InvalidMember)
  }
  let row_cids : Array[Array[String]] = []
  for effect in members {
    let changes = match @json.object_field(effect, "changes") {
      Some(@json.Array(items)) => @json.array_values(items)
      _ => return Err(InvalidMember)
    }
    let rows : Array[String] = []
    for change in changes {
      let cid = match
        effect_preview_row_cid(
          preview, effect, change, max_wire_bytes, max_nodes, max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      rows.push(cid)
    }
    row_cids.push(rows)
  }
  Ok(row_cids)
}

///|
fn effect_member_row_inventory(
  preview : @json.CanonicalValue,
  effect : @json.CanonicalValue,
  index : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (
    Array[String],
    Array[String],
    Array[String],
    Array[String],
    Array[String],
    Array[String],
    Array[String],
  ),
  EffectPreviewIdentityIssue,
] {
  let changes = match @json.object_field(effect, "changes") {
    Some(@json.Array(items)) => @json.array_values(items)
    _ => return Err(InvalidMember)
  }
  guard @json.object_field(effect, "count") is Some(@json.Number(count)) &&
    @json.object_field(effect, "max_items") is Some(@json.Number(max_items)) &&
    count == changes.length().to_double() &&
    count <= max_items &&
    @json.object_field(effect, "row_order") is Some(@json.Array(order_frozen)) else {
    return Err(RowInventoryMismatch(index))
  }
  let keys : Array[String] = []
  let rows : Array[String] = []
  let correlations : Array[String] = []
  let intended_states : Array[String] = []
  let intended_values : Array[String] = []
  let guard_versions : Array[String] = []
  for row_index in 0..<changes.length() {
    let change = changes[row_index]
    match
      (
        @json.object_field(change, "row_preview_cid"),
        @json.object_field(change, "row_idempotency_key"),
      ) {
      (Some(@json.String(row)), Some(@json.String(key))) => {
        let derived = match
          effect_preview_row_cid(
            preview, effect, change, max_wire_bytes, max_nodes, max_depth,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if derived != row {
          return Err(RowIdentityMismatch(index, row_index))
        }
        if rows.contains(row) || keys.contains(key) {
          return Err(RowInventoryMismatch(index))
        }
        rows.push(row)
        keys.push(key)
        let target = match @json.object_field(change, "target_row_identity") {
          Some(value) => value
          None => return Err(InvalidMember)
        }
        let correlation = @json.stringify_value(
          target, max_wire_bytes, max_nodes, max_depth,
        ) catch {
          _ => return Err(Encoding)
        }
        correlations.push(correlation)
        let intended_value = match
          @json.object_field(change, "intended_changes") {
          Some(intended) => {
            let state = match @json.object_field(intended, "state") {
              Some(@json.String(state)) => state
              _ => return Err(InvalidMember)
            }
            intended_states.push(state)
            match @json.object_field(intended, "value") {
              Some(value) =>
                @json.stringify_value(
                  value, max_wire_bytes, max_nodes, max_depth,
                ) catch {
                  _ => return Err(Encoding)
                }
              None => ""
            }
          }
          None => return Err(InvalidMember)
        }
        intended_values.push(intended_value)
        let guard_version = match @json.object_field(change, "target_guard") {
          Some(guard_value) =>
            match @json.object_field(guard_value, "state") {
              Some(@json.String("version")) =>
                match @json.object_field(guard_value, "version_cid") {
                  Some(@json.String(version_cid)) => version_cid
                  _ => return Err(InvalidMember)
                }
              Some(@json.String("not_applicable")) => ""
              _ => return Err(InvalidMember)
            }
          None => return Err(InvalidMember)
        }
        guard_versions.push(guard_version)
      }
      _ => return Err(InvalidMember)
    }
  }
  let supplied_order = @json.array_values(order_frozen)
  if supplied_order.length() != rows.length() {
    return Err(RowInventoryMismatch(index))
  }
  let order : Array[String] = []
  for value in supplied_order {
    match value {
      @json.String(row) => {
        if !rows.contains(row) || order.contains(row) {
          return Err(RowInventoryMismatch(index))
        }
        order.push(row)
      }
      _ => return Err(RowInventoryMismatch(index))
    }
  }
  Ok(
    (
      keys, rows, order, correlations, intended_states, intended_values, guard_versions,
    ),
  )
}

///|
/// Return independently derived identities after complete 0.1 shape
/// admission. Derived row keys are excluded from both semantic preimages,
/// but remain required transport fields and must be checked at apply.
pub fn derive_effect_preview_identities(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, Array[String]), EffectPreviewIdentityIssue] {
  let preview = match
    parse_effect_preview_shape(wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(PreviewShape(issue))
  }
  let members = match @json.object_field(preview, "effects") {
    Some(@json.Array(items)) => @json.array_values(items)
    _ => return Err(InvalidMember)
  }
  let cids = []
  let seen_effect_ids : Map[String, Bool] = Map([])
  for index in 0..<members.length() {
    let effect = members[index]
    let effect_id = match @json.object_field(effect, "effect_id") {
      Some(@json.String(value)) => value
      _ => return Err(InvalidMember)
    }
    if seen_effect_ids.contains(effect_id) {
      return Err(InvalidMember)
    }
    seen_effect_ids[effect_id] = true
    match
      effect_member_row_inventory(
        preview, effect, index, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let cid = match
      effect_member_semantic_cid(effect, max_wire_bytes, max_nodes, max_depth) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    cids.push(cid)
  }
  let cid = match
    effect_preview_semantic_cid(
      preview, cids, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((cid, cids))
}

///|
/// Identity admission does not confer apply authority. Exact Run and
/// Authoring Context bindings are checked separately from the semantic CID.
pub fn admit_effect_preview_identity(
  wire : String,
  expected_run_identity_cid : String,
  expected_authoring_context_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectPreviewIdentity, EffectPreviewIdentityIssue] {
  let preview = match
    parse_effect_preview_shape(wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(PreviewShape(issue))
  }
  let members = match @json.object_field(preview, "effects") {
    Some(@json.Array(items)) => @json.array_values(items)
    _ => return Err(InvalidMember)
  }
  let cids = []
  let row_keys : Array[Array[String]] = []
  let member_effect_ids : Array[String] = []
  let member_effect_kinds : Array[String] = []
  let member_effect_plan_cids : Array[String?] = []
  let member_source_results : Array[String?] = []
  let member_result_artifact_cids : Array[String?] = []
  let member_max_items : Array[Int64] = []
  let member_contracts : Array[EffectPreviewResolvedContract] = []
  let member_failure_policies : Array[String] = []
  let member_footprints : Array[EffectPreviewFootprintIdentity] = []
  let seen_effect_ids : Map[String, Bool] = Map([])
  let row_cids : Array[Array[String]] = []
  let row_indices : Array[Map[String, Int]] = []
  let row_correlation_wires : Array[Array[String]] = []
  let row_intended_change_states : Array[Array[String]] = []
  let row_intended_value_wires : Array[Array[String]] = []
  let row_guard_version_cids : Array[Array[String]] = []
  let ordered_row_correlation_wires : Array[Array[String]] = []
  let ordered_row_intended_change_states : Array[Array[String]] = []
  let ordered_row_intended_value_wires : Array[Array[String]] = []
  let row_order : Array[Array[String]] = []
  for index in 0..<members.length() {
    let effect = members[index]
    let effect_id = match @json.object_field(effect, "effect_id") {
      Some(@json.String(value)) => value
      _ => return Err(InvalidMember)
    }
    if seen_effect_ids.contains(effect_id) {
      return Err(InvalidMember)
    }
    seen_effect_ids[effect_id] = true
    member_effect_ids.push(effect_id)
    let effect_kind = match @json.object_field(effect, "effect_kind") {
      Some(@json.String(value)) => value
      _ => return Err(InvalidMember)
    }
    member_effect_kinds.push(effect_kind)
    member_effect_plan_cids.push(
      optional_string(@json.object_field(effect, "effect_plan_logical_cid")),
    )
    let source_result = optional_string(
      @json.object_field(effect, "source_result"),
    )
    let artifact_cid = optional_string(
      @json.object_field(effect, "result_artifact_cid"),
    )
    if (source_result is Some(_)) != (artifact_cid is Some(_)) {
      return Err(InvalidMember)
    }
    member_source_results.push(source_result)
    member_result_artifact_cids.push(artifact_cid)
    match @json.object_field(effect, "max_items") {
      Some(@json.Number(limit)) if limit > 0.0 &&
        limit <= 9007199254740991.0 &&
        limit == limit.to_int64().to_double() =>
        member_max_items.push(limit.to_int64())
      _ => return Err(InvalidMember)
    }
    let contract = if effect_kind == "command" {
      match
        (
          @json.object_field(effect, "contract"),
          @json.object_field(effect, "resolved_command_contract_cid"),
        ) {
        (Some(@json.String(reference)), Some(@json.String(cid))) =>
          Command(reference, cid)
        _ => return Err(InvalidMember)
      }
    } else {
      match
        (
          @json.object_field(effect, "mapping"),
          @json.object_field(effect, "resolved_mapping_contract_cid"),
        ) {
        (Some(@json.String(reference)), Some(@json.String(cid))) =>
          Mapping(reference, cid)
        _ => return Err(InvalidMember)
      }
    }
    member_contracts.push(contract)
    let failure_policy = match @json.object_field(effect, "on_item_failure") {
      Some(@json.String(value)) => value
      _ => return Err(InvalidMember)
    }
    member_failure_policies.push(failure_policy)
    let footprint = match retain_effect_preview_footprint(effect) {
      Some(value) => value
      None => return Err(InvalidMember)
    }
    member_footprints.push(footprint)
    let (
      member_keys,
      member_rows,
      member_order,
      member_correlations,
      member_intended_states,
      member_intended_values,
      member_guard_versions,
    ) = match
      effect_member_row_inventory(
        preview, effect, index, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    row_keys.push(member_keys)
    let indices : Map[String, Int] = Map([])
    for row_index in 0..<member_rows.length() {
      indices[member_rows[row_index]] = row_index
    }
    let ordered_correlations : Array[String] = []
    let ordered_intended_states : Array[String] = []
    let ordered_intended_values : Array[String] = []
    for row_cid in member_order {
      let mut found = false
      for row_index in 0..<member_rows.length() {
        if member_rows[row_index] == row_cid {
          ordered_correlations.push(member_correlations[row_index])
          ordered_intended_states.push(member_intended_states[row_index])
          ordered_intended_values.push(member_intended_values[row_index])
          found = true
          break
        }
      }
      if !found {
        return Err(RowInventoryMismatch(index))
      }
    }
    row_indices.push(indices)
    row_cids.push(member_rows)
    row_correlation_wires.push(member_correlations)
    row_intended_change_states.push(member_intended_states)
    row_intended_value_wires.push(member_intended_values)
    row_guard_version_cids.push(member_guard_versions)
    ordered_row_correlation_wires.push(ordered_correlations)
    ordered_row_intended_change_states.push(ordered_intended_states)
    ordered_row_intended_value_wires.push(ordered_intended_values)
    row_order.push(member_order)
    let cid = match
      effect_member_semantic_cid(effect, max_wire_bytes, max_nodes, max_depth) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let supplied = match
      @json.object_field(effect, "effect_member_preview_cid") {
      Some(@json.String(value)) => value
      _ => return Err(MemberIdentityMismatch(index))
    }
    if supplied != cid {
      return Err(MemberIdentityMismatch(index))
    }
    cids.push(cid)
  }
  let cid = match
    effect_preview_semantic_cid(
      preview, cids, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let supplied = match @json.object_field(preview, "effect_preview_cid") {
    Some(@json.String(value)) => value
    _ => return Err(PreviewIdentityMismatch)
  }
  if supplied != cid {
    return Err(PreviewIdentityMismatch)
  }
  let run = match @json.object_field(preview, "run_identity_cid") {
    Some(@json.String(value)) => value
    _ => return Err(RunBindingMismatch)
  }
  if run != expected_run_identity_cid {
    return Err(RunBindingMismatch)
  }
  let (authoring, authoring_value) = match
    @json.object_field(preview, "authoring_context") {
    Some(value) =>
      match @json.object_field(value, "authoring_context_cid") {
        Some(@json.String(cid)) => (cid, value)
        _ => return Err(AuthoringBindingMismatch)
      }
    _ => return Err(AuthoringBindingMismatch)
  }
  if authoring != expected_authoring_context_cid {
    return Err(AuthoringBindingMismatch)
  }
  if !evidence_identity_valid(
      authoring_value, "authoring_context_cid", max_wire_bytes, max_nodes, max_depth,
    ) ||
    optional_string(
      @json.object_field(authoring_value, "program_definition_cid"),
    ) !=
    optional_string(@json.object_field(preview, "program_definition_cid")) {
    return Err(AuthoringIdentityMismatch)
  }
  guard @json.object_field(preview, "program_semantics_cid")
    is Some(@json.String(program_semantics_cid)) &&
    @json.object_field(preview, "program_definition_cid")
    is Some(@json.String(program_definition_cid)) &&
    @json.object_field(preview, "invocation_cid")
    is Some(@json.String(invocation_cid)) &&
    @json.object_field(preview, "compiled_plan_cid")
    is Some(@json.String(compiled_plan_cid)) &&
    @json.object_field(preview, "check_environment_cid")
    is Some(@json.String(check_environment_cid)) else {
    return Err(PreviewShape(InvalidField("run_binding")))
  }
  Ok({
    semantic_cid: cid,
    member_cids: cids,
    member_effect_ids,
    member_effect_kinds,
    member_effect_plan_cids,
    member_source_results,
    member_result_artifact_cids,
    member_max_items,
    member_contracts,
    member_failure_policies,
    member_footprints,
    row_keys,
    row_cids,
    row_indices,
    row_correlation_wires,
    row_intended_change_states,
    row_intended_value_wires,
    row_guard_version_cids,
    ordered_row_correlation_wires,
    ordered_row_intended_change_states,
    ordered_row_intended_value_wires,
    row_order,
    run_identity_cid: run,
    authoring_context_cid: authoring,
    program_semantics_cid,
    program_definition_cid,
    invocation_cid,
    compiled_plan_cid,
    check_environment_cid,
  })
}

///|
pub fn effect_preview_semantic_identity(
  value : EffectPreviewIdentity,
) -> String {
  value.semantic_cid
}

///|
pub fn effect_preview_program_semantics_cid(
  value : EffectPreviewIdentity,
) -> String {
  value.program_semantics_cid
}

///|
pub fn effect_preview_program_definition_cid(
  value : EffectPreviewIdentity,
) -> String {
  value.program_definition_cid
}

///|
pub fn effect_preview_check_environment_cid(
  value : EffectPreviewIdentity,
) -> String {
  value.check_environment_cid
}

///|
pub fn effect_preview_member_identity(
  value : EffectPreviewIdentity,
  index : Int,
) -> String? {
  value.member_cids.get(index)
}

///|
pub fn effect_preview_member_effect_id(
  value : EffectPreviewIdentity,
  index : Int,
) -> String? {
  value.member_effect_ids.get(index)
}

///|
pub fn effect_preview_member_kind(
  value : EffectPreviewIdentity,
  index : Int,
) -> String? {
  value.member_effect_kinds.get(index)
}

///|
pub fn effect_preview_member_plan_cid(
  value : EffectPreviewIdentity,
  index : Int,
) -> String? {
  match value.member_effect_plan_cids.get(index) {
    Some(cid) => cid
    None => None
  }
}

///|
/// A source Result and its captured Artifact are an inseparable member
/// binding. Their presence does not by itself prove checked membership.
pub fn effect_preview_member_source_result(
  value : EffectPreviewIdentity,
  index : Int,
) -> String? {
  match value.member_source_results.get(index) {
    Some(name) => name
    None => None
  }
}

///|
pub fn effect_preview_member_result_artifact_cid(
  value : EffectPreviewIdentity,
  index : Int,
) -> String? {
  match value.member_result_artifact_cids.get(index) {
    Some(cid) => cid
    None => None
  }
}

///|
/// The resolved, positive-safe-integer scope bound retained by the private
/// Preview. It is not an apply permit or proof of an authored guard.
pub fn effect_preview_member_max_items(
  value : EffectPreviewIdentity,
  index : Int,
) -> Int64? {
  value.member_max_items.get(index)
}

///|
pub fn effect_preview_member_resolved_contract(
  value : EffectPreviewIdentity,
  index : Int,
) -> EffectPreviewResolvedContract? {
  value.member_contracts.get(index)
}

///|
pub fn effect_preview_member_failure_policy(
  value : EffectPreviewIdentity,
  index : Int,
) -> String? {
  value.member_failure_policies.get(index)
}

///|
pub fn effect_preview_member_footprint(
  value : EffectPreviewIdentity,
  index : Int,
) -> EffectPreviewFootprintIdentity? {
  value.member_footprints.get(index)
}

///|
pub fn effect_preview_member_count(value : EffectPreviewIdentity) -> Int {
  value.member_cids.length()
}

///|
pub fn effect_preview_row_count(
  value : EffectPreviewIdentity,
  member_index : Int,
) -> Int? {
  match value.row_keys.get(member_index) {
    Some(keys) => Some(keys.length())
    None => None
  }
}

///|
pub fn effect_preview_row_key(
  value : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> String? {
  match value.row_keys.get(member_index) {
    Some(keys) => keys.get(row_index)
    None => None
  }
}

///|
pub fn effect_preview_row_identity(
  value : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> String? {
  match value.row_cids.get(member_index) {
    Some(rows) => rows.get(row_index)
    None => None
  }
}

///|
/// The approved value is retained from the private Preview, not recomputed
/// from a later target observation. None denotes an invalid row index or a
/// row with an explicit not-applicable payload.
pub fn effect_preview_row_intended_value_wire(
  value : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> String? {
  match value.row_intended_value_wires.get(member_index) {
    Some(rows) =>
      match rows.get(row_index) {
        Some("") => None
        other => other
      }
    None => None
  }
}

///|
/// The complete approved intended-changes wrapper, including its explicit
/// state. It comes from the admitted private Preview, not a fresh target read.
pub fn effect_preview_row_intended_changes_wire(
  value : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> String? {
  let state = value.row_intended_change_states
    .get(member_index)
    .bind(rows => rows.get(row_index))
  match state {
    Some("present") =>
      effect_preview_row_intended_value_wire(value, member_index, row_index).map(wire => {
          "{\"state\":\"present\",\"value\":" + wire + "}"
        },
      )
    Some("not_applicable") => Some("{\"state\":\"not_applicable\"}")
    _ => None
  }
}

///|
/// The approved version/content guard is retained from the private Preview.
/// None means the row has a not-applicable guard or the index is invalid;
/// callers checking all rows must use the admitted row count for traversal.
pub fn effect_preview_row_guard_version_cid(
  value : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> String? {
  match value.row_guard_version_cids.get(member_index) {
    Some(rows) =>
      match rows.get(row_index) {
        Some("") => None
        other => other
      }
    None => None
  }
}

///|
pub fn effect_preview_row_index(
  value : EffectPreviewIdentity,
  member_index : Int,
  row_cid : String,
) -> Int? {
  match value.row_indices.get(member_index) {
    Some(indices) => indices.get(row_cid)
    None => None
  }
}

///|
pub fn effect_preview_row_correlation_wire(
  value : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> String? {
  match value.row_correlation_wires.get(member_index) {
    Some(rows) => rows.get(row_index)
    None => None
  }
}

///|
pub fn effect_preview_ordered_row_identity(
  value : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> String? {
  match value.row_order.get(member_index) {
    Some(rows) => rows.get(row_index)
    None => None
  }
}

///|
pub fn effect_preview_ordered_row_intended_value_wire(
  value : EffectPreviewIdentity,
  member_index : Int,
  ordered_index : Int,
) -> String? {
  match value.ordered_row_intended_value_wires.get(member_index) {
    Some(rows) =>
      match rows.get(ordered_index) {
        Some("") => None
        other => other
      }
    None => None
  }
}

///|
/// Dispatch-order access retains the same admitted change body even when the
/// transport's changes array uses a different enumeration order.
pub fn effect_preview_ordered_row_intended_changes_wire(
  value : EffectPreviewIdentity,
  member_index : Int,
  ordered_index : Int,
) -> String? {
  let state = value.ordered_row_intended_change_states
    .get(member_index)
    .bind(rows => rows.get(ordered_index))
  match state {
    Some("present") =>
      effect_preview_ordered_row_intended_value_wire(
        value, member_index, ordered_index,
      ).map(wire => "{\"state\":\"present\",\"value\":" + wire + "}")
    Some("not_applicable") => Some("{\"state\":\"not_applicable\"}")
    _ => None
  }
}

///|
pub fn effect_preview_ordered_row_correlation_wire(
  value : EffectPreviewIdentity,
  member_index : Int,
  ordered_index : Int,
) -> String? {
  match value.ordered_row_correlation_wires.get(member_index) {
    Some(rows) => rows.get(ordered_index)
    None => None
  }
}
