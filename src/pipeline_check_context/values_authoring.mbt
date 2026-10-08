///|
/// Static resource admission for an exact prebinding Values occurrence. The
/// same selectors retain wire, row and recursive scopes and future enforcement
/// limits. This is neither a Program template certificate nor execution proof.
struct AuthoringValuesPublicationCheck {
  owner : ValuesResourceOwner
  recursive : ValuesRecursiveAdmission
  recursive_limit : @wire.LimitClaim?
  work : Int
  payload_bytes : Int
  payload_nodes : Int
  metadata_bytes : Int
  metadata_nodes : Int
}

///|
pub fn resolve_authoring_values_resources(
  profiles : PipelineOperationProfileChecks,
  step_index : Int,
  capacity : @environment.Capacity,
  limits : ValuesPublicationLimits,
  total_limits? : @wire.Limits? = None,
) -> Result[AuthoringValuesPublicationCheck, ValuesPublicationIssue] {
  if limits.max_work < 0 ||
    limits.max_values < 0 ||
    limits.max_payload_bytes < 0 ||
    limits.max_payload_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.metadata.max_bytes < 0 ||
    limits.metadata.max_nodes < 0 ||
    limits.metadata.max_depth < 0 ||
    limits.metadata.max_candidates < 0 {
    return Err(InvalidLimits)
  }
  if profiles.work >= limits.max_work || limits.max_values == 0 {
    return Err(BudgetExceeded)
  }
  let owner = match
    authored_values_resource_owner(profiles, step_index, capacity) {
    Ok(value) => value
    Err(issue) => return Err(Wire(step_index, Measurement(issue)))
  }
  let prefix_work = profiles.work + 1
  let total = total_limits.unwrap_or({
    max_bytes: 2147483647,
    max_nodes: 2147483647,
    max_depth: limits.max_depth,
  })
  if total.max_bytes < 0 || total.max_nodes < 0 || total.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let meter : ValuesMetadataBudget = {
    bytes: total.max_bytes,
    nodes: total.max_nodes.min(limits.max_work - prefix_work),
    used_bytes: 0,
    used_nodes: 0,
  }
  let metadata : @wire.LimitLimits = {
    ..limits.metadata,
    max_depth: limits.metadata.max_depth.min(total.max_depth),
  }
  let depth = limits.max_depth.min(total.max_depth)
  let wire = match
    resolve_values_resource_wire_limit(
      owner,
      {
        max_bytes: limits.max_payload_bytes.min(meter.bytes),
        max_nodes: limits.max_payload_nodes.min(meter.nodes),
        max_depth: depth,
      },
      metadata,
      Some(meter),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Wire(step_index, issue))
  }
  let rows = match
    resolve_values_row_limit_metered(wire, metadata, Some(meter)) {
    Ok(value) => value
    Err(issue) => return Err(Rows(step_index, issue))
  }
  if !values_rows_fit_selected_limit(rows) {
    return Err(RowsExceeded(step_index))
  }
  let recursive = match
    check_values_recursive_resources(
      rows,
      (limits.max_payload_nodes - wire.bound.nodes).min(meter.nodes),
      (limits.max_payload_bytes - wire.bound.bytes).min(meter.bytes),
      depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Recursive(step_index, issue))
  }
  meter.bytes -= recursive.bytes
  meter.nodes -= recursive.work
  let recursive_limit = match
    values_recursive_limit(recursive, metadata, meter=Some(meter)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    owner,
    recursive,
    recursive_limit,
    work: prefix_work + wire.bound.nodes + recursive.work + meter.used_nodes,
    payload_bytes: wire.bound.bytes + recursive.bytes,
    payload_nodes: wire.bound.nodes + recursive.work,
    metadata_bytes: meter.used_bytes,
    metadata_nodes: meter.used_nodes,
  })
}

///|
pub fn authoring_values_profiles(
  value : AuthoringValuesPublicationCheck,
) -> PipelineOperationProfileChecks {
  match value.owner.source {
    Authored(profiles, _, _) => profiles
    BoundCells(_, _, _) => abort("Invalid authoring Values owner")
  }
}

///|
pub fn authoring_values_capacity(
  value : AuthoringValuesPublicationCheck,
) -> @environment.Capacity {
  match value.owner.source {
    Authored(_, _, capacity) => capacity
    BoundCells(_, _, _) => abort("Invalid authoring Values owner")
  }
}

///|
pub fn authoring_values_step(value : AuthoringValuesPublicationCheck) -> Int {
  values_resource_step(value.owner)
}

///|
pub fn authoring_values_recursive(
  value : AuthoringValuesPublicationCheck,
) -> ValuesRecursiveAdmission {
  value.recursive
}

///|
pub fn authoring_values_recursive_limit(
  value : AuthoringValuesPublicationCheck,
) -> @wire.LimitClaim? {
  value.recursive_limit
}

///|
pub fn authoring_values_work(value : AuthoringValuesPublicationCheck) -> Int {
  value.work
}

///|
pub fn authoring_values_payload_usage(
  value : AuthoringValuesPublicationCheck,
) -> (Int, Int) {
  (value.payload_bytes, value.payload_nodes)
}

///|
pub fn authoring_values_metadata_usage(
  value : AuthoringValuesPublicationCheck,
) -> (Int, Int) {
  (value.metadata_bytes, value.metadata_nodes)
}
