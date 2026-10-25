///|
/// Verify immutable sidecar references against an already admitted Plan.
/// This checks identity/shape only: it grants no control, read, or dispatch
/// authority and does not attest installed stop/sample support.
pub fn check_interactive_logical_map_binding(
  map : RunEvidenceValue,
  plan : PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, RunEvidenceValueIssue] {
  if map.name != "logical_map" || plan.name != "compiled_plan" {
    return Err(UnknownRunEvidence)
  }
  if evidence_string(map.value, "compiled_plan_cid") != Some(plan.identity) ||
    evidence_string(map.value, "program_definition_cid") !=
    evidence_string(plan.value, "program_definition_cid") {
    return Err(RunEvidenceReferenceMismatch("logical_map.plan"))
  }
  guard @json.object_field(map.value, "steps") is Some(@json.Array(steps)) else {
    return Err(RunEvidenceInvalidShape)
  }
  let outputs : Map[String, (String, String, String)] = Map([])
  let step_ids : Map[String, Bool] = Map([])
  let port_ids : Map[String, Bool] = Map([])
  let mut remaining = max_nodes
  for i in 0..<@json.array_count(steps) {
    if remaining < 1 {
      return Err(RunEvidenceInvalidLimits)
    }
    remaining -= 1
    let step = @json.array_at(steps, i).unwrap()
    let id = evidence_string(step, "step_id").unwrap()
    let key = @json.object_field(step, "key").unwrap()
    if step_ids.contains(id) ||
      evidence_string(key, "compiled_plan_cid") != Some(plan.identity) ||
      evidence_string(key, "self_cid") != Some(id) {
      return Err(RunEvidenceReferenceMismatch("logical_map.step"))
    }
    match
      run_evidence_value(
        "logical_step_key", "self_cid", key, max_bytes, max_nodes, max_depth,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    step_ids[id] = true
    let occurrence = @json.object_field(key, "occurrence").unwrap()
    let input_only = evidence_string(occurrence, "kind") == Some("input_output")
    let operator = @json.object_field(step, "operator").unwrap()
    if (input_only && !(operator is @json.Null)) ||
      (!input_only && operator is @json.Null) {
      return Err(RunEvidenceReferenceMismatch("logical_map.operator"))
    }
    guard @json.object_field(step, "ports") is Some(@json.Array(ports)) else {
      return Err(RunEvidenceInvalidShape)
    }
    let coordinates : Map[String, Bool] = Map([])
    let mut input_contract : String? = None
    let mut output_contract : String? = None
    let mut input_count = 0
    let mut output_count = 0
    for j in 0..<@json.array_count(ports) {
      if remaining < 1 {
        return Err(RunEvidenceInvalidLimits)
      }
      remaining -= 1
      let port = @json.array_at(ports, j).unwrap()
      let role = evidence_string(port, "role").unwrap()
      let ordinal = interactive_integer(port, "port_ordinal").unwrap()
      let coordinate = role + ":" + ordinal.to_string()
      let port_id = evidence_string(port, "port_id").unwrap()
      if coordinates.contains(coordinate) || port_ids.contains(port_id) {
        return Err(RunEvidenceReferenceMismatch("logical_map.port"))
      }
      coordinates[coordinate] = true
      port_ids[port_id] = true
      // All interpolated values have already passed closed CID/enum/integer
      // admission. The canonical sealer remains the sole identity issuer.
      let body = "{\"version\":\"actql-logical-port-key/0.1\",\"compiled_plan_cid\":\"" +
        plan.identity +
        "\",\"step_id\":\"" +
        id +
        "\",\"role\":\"" +
        role +
        "\",\"port_ordinal\":" +
        ordinal.to_string() +
        "}"
      let expected = match
        seal_run_evidence_value(
          "logical_port_key", body, max_bytes, max_nodes, max_depth,
        ) {
        Ok(value) => value.identity
        Err(issue) => return Err(issue)
      }
      if port_id != expected {
        return Err(RunEvidenceReferenceMismatch("logical_map.port_identity"))
      }
      let carrier = evidence_string(port, "carrier").unwrap()
      let contract = evidence_string(port, "carrier_contract_cid").unwrap()
      if input_only {
        if ordinal != 0L || carrier != "relation" {
          return Err(RunEvidenceReferenceMismatch("logical_map.input_output"))
        }
        if role == "input" {
          input_count += 1
          input_contract = Some(contract)
        } else {
          output_count += 1
          output_contract = Some(contract)
        }
      }
      let source = @json.object_field(port, "source").unwrap()
      if evidence_string(source, "kind") == Some("logical_output") {
        let producer = evidence_string(source, "step_id").unwrap()
        let output_id = evidence_string(source, "output_port_id").unwrap()
        if role == "output" && producer == id && output_id == port_id {
          if input_only {
            return Err(RunEvidenceReferenceMismatch("logical_map.input_output"))
          }
        } else if outputs.get(output_id) != Some((producer, carrier, contract)) {
          return Err(RunEvidenceReferenceMismatch("logical_map.producer"))
        }
      } else if input_only &&
        (
          interactive_integer(source, "stage_ordinal") !=
          interactive_integer(key, "stage_ordinal") ||
          interactive_integer(source, "input_port_ordinal") !=
          interactive_integer(occurrence, "input_port_ordinal")
        ) {
        return Err(RunEvidenceReferenceMismatch("logical_map.input_output"))
      }
      if role == "output" {
        outputs[port_id] = (id, carrier, contract)
      }
    }
    if input_only &&
      (
        input_count != 1 ||
        output_count != 1 ||
        input_contract != output_contract
      ) {
      return Err(RunEvidenceReferenceMismatch("logical_map.input_output"))
    }
  }
  Ok(())
}

///|
/// Cross-record binding does not create a second admission/journal Owner.
/// The existing Owner supplies its original Plan and Run Definition identity.
pub fn check_interactive_admission_binding(
  intent : RunEvidenceValue,
  requested : RunEvidenceValue,
  effective : RunEvidenceValue,
  resolved : RunEvidenceValue,
  map : RunEvidenceValue,
  admission : RunEvidenceValue,
  plan : PublicationContract,
  original_namespace_id : String,
  original_run_definition_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, RunEvidenceValueIssue] {
  if intent.name != "control_request_intent" ||
    requested.name != "control_profile" ||
    effective.name != "control_profile" ||
    resolved.name != "resolved_control_profile" ||
    admission.name != "control_admission" {
    return Err(UnknownRunEvidence)
  }
  match
    check_interactive_logical_map_binding(
      map, plan, max_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for value in [resolved.value, admission.value] {
    if evidence_string(value, "compiled_plan_cid") != Some(plan.identity) ||
      evidence_string(value, "logical_map_cid") != Some(map.identity) {
      return Err(RunEvidenceReferenceMismatch("control_admission.plan_map"))
    }
  }
  if evidence_string(intent.value, "requested_profile_cid") !=
    Some(requested.identity) ||
    evidence_string(resolved.value, "requested_profile_cid") !=
    Some(requested.identity) ||
    evidence_string(admission.value, "request_intent_cid") !=
    Some(intent.identity) ||
    evidence_string(admission.value, "resolved_profile_cid") !=
    Some(resolved.identity) {
    return Err(RunEvidenceReferenceMismatch("control_admission.profile_intent"))
  }
  if evidence_string(resolved.value, "effective_profile_cid") !=
    Some(effective.identity) {
    return Err(
      RunEvidenceReferenceMismatch("control_admission.effective_profile"),
    )
  }
  match check_interactive_profile_bounds(requested) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match check_interactive_profile_bounds(effective) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // Resolve only against the original admitted map. Shape/CID equality alone
  // cannot make a foreign Step or an input port an output Sample target.
  let steps = match @json.object_field(map.value, "steps").unwrap() {
    @json.Array(steps) => steps
    _ => return Err(RunEvidenceInvalidShape)
  }
  let step_ids : Map[String, Bool] = Map([])
  let output_ids : Map[String, Bool] = Map([])
  for i in 0..<@json.array_count(steps) {
    let step = @json.array_at(steps, i).unwrap()
    step_ids[evidence_string(step, "step_id").unwrap()] = true
    if @json.object_field(step, "ports") is Some(@json.Array(ports)) {
      for j in 0..<@json.array_count(ports) {
        let port = @json.array_at(ports, j).unwrap()
        if evidence_string(port, "role") == Some("output") {
          output_ids[evidence_string(port, "port_id").unwrap()] = true
        }
      }
    }
  }
  if @json.object_field(resolved.value, "breakpoints")
    is Some(@json.Array(points)) {
    for i in 0..<@json.array_count(points) {
      let point = @json.array_at(points, i).unwrap()
      if evidence_string(point, "kind") == Some("logical_step") &&
        !step_ids.contains(evidence_string(point, "step_id").unwrap()) {
        return Err(RunEvidenceReferenceMismatch("control_admission.breakpoint"))
      }
    }
  }
  if @json.object_field(resolved.value, "sample_output_port_ids")
    is Some(@json.Array(ports)) {
    for i in 0..<@json.array_count(ports) {
      if @json.array_at(ports, i) is Some(@json.String(id)) &&
        !output_ids.contains(id) {
        return Err(
          RunEvidenceReferenceMismatch("control_admission.sample_output"),
        )
      }
    }
  }
  if @json.object_field(intent.value, "expected_plan_cid")
    is Some(@json.String(expected)) &&
    expected != plan.identity {
    return Err(RunEvidenceReferenceMismatch("control_admission.expected_plan"))
  }
  let submission = @json.object_field(intent.value, "submission_ref").unwrap()
  let epoch = @json.object_field(submission, "epoch").unwrap()
  let run = @json.object_field(admission.value, "run_ref").unwrap()
  if evidence_string(run, "namespaceId") != Some(original_namespace_id) ||
    evidence_string(epoch, "authorityScopeCid") !=
    evidence_string(run, "authorityScopeCid") {
    return Err(RunEvidenceReferenceMismatch("control_admission.original_scope"))
  }
  if evidence_string(run, "runDefinitionCid") !=
    Some(original_run_definition_cid) {
    return Err(RunEvidenceReferenceMismatch("control_admission.original_run"))
  }
  Ok(())
}

///|
/// Static cross-field limits only. Installed Host caps, policy and actual
/// retention admission remain separate existing-Owner obligations.
pub fn check_interactive_profile_bounds(
  profile : RunEvidenceValue,
) -> Result[Unit, RunEvidenceValueIssue] {
  if profile.name != "control_profile" {
    return Err(UnknownRunEvidence)
  }
  let retain = @json.object_field(profile.value, "retain").unwrap()
  if @json.object_field(retain, "samples") is Some(samples) {
    let graph = @json.object_field(samples, "graph").unwrap()
    let nodes = interactive_integer(graph, "max_nodes").unwrap()
    let edges = interactive_integer(graph, "max_edges").unwrap()
    let items = interactive_integer(samples, "max_items").unwrap()
    if nodes + edges > items ||
      evidence_string(samples, "max_bytes") == Some("0") {
      return Err(RunEvidenceReferenceMismatch("control_profile.sample_limits"))
    }
  }
  if @json.object_field(retain, "intermediate") is Some(intermediate) &&
    evidence_string(intermediate, "max_bytes") == Some("0") {
    return Err(
      RunEvidenceReferenceMismatch("control_profile.intermediate_limits"),
    )
  }
  Ok(())
}
