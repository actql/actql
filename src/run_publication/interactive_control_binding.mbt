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
// Match the checked Step before considering whether any of its output ports
// can be retained. Charge each selector/name visit against the binding scan.
fn interactive_sample_step_selected(
  step : @json.CanonicalValue,
  targets : @json.FrozenArray[@json.CanonicalValue],
  remaining : Int,
) -> Result[(Bool, Int), RunEvidenceValueIssue] {
  let mut work = remaining
  for i in 0..<@json.array_count(targets) {
    if work == 0 {
      return Err(RunEvidenceInvalidLimits)
    }
    work -= 1
    let target = @json.array_at(targets, i).unwrap()
    let selected = match evidence_string(target, "by") {
      Some("id") =>
        evidence_string(target, "step_id") == evidence_string(step, "step_id")
      Some("operator") =>
        evidence_string(target, "operator") == evidence_string(step, "operator")
      Some("name") => {
        guard @json.object_field(step, "names") is Some(@json.Array(names)) &&
          evidence_string(target, "name") is Some(name) else {
          return Err(RunEvidenceInvalidShape)
        }
        for j in 0..<@json.array_count(names) {
          if work == 0 {
            return Err(RunEvidenceInvalidLimits)
          }
          work -= 1
          if @json.array_at(names, j) is Some(@json.String(actual)) &&
            actual == name {
            return Ok((true, work))
          }
        }
        false
      }
      _ => return Err(RunEvidenceInvalidShape)
    }
    if selected {
      return Ok((true, work))
    }
  }
  Ok((false, work))
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
  checked_interactive_admission_outputs(
    intent, requested, effective, resolved, map, admission, plan, original_namespace_id,
    original_run_definition_cid, max_bytes, max_nodes, max_depth,
  ).map(_ => ())
}

///|
fn checked_interactive_admission_outputs(
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
) -> Result[Map[String, Bool], RunEvidenceValueIssue] {
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
  let retain = @json.object_field(effective.value, "retain").unwrap()
  let samples = @json.object_field(retain, "samples")
  let mut remaining = max_nodes
  for i in 0..<@json.array_count(steps) {
    let step = @json.array_at(steps, i).unwrap()
    step_ids[evidence_string(step, "step_id").unwrap()] = true
    guard samples is Some(samples) else { continue }
    if evidence_string(samples, "capture_scope") == Some("selected_outputs") {
      guard @json.object_field(samples, "targets") is Some(@json.Array(targets)) else {
        return Err(RunEvidenceInvalidShape)
      }
      match interactive_sample_step_selected(step, targets, remaining) {
        Err(issue) => return Err(issue)
        Ok((selected, work)) => {
          remaining = work
          if !selected {
            continue
          }
        }
      }
    }
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
    if @json.array_count(ports) != output_ids.length() {
      return Err(
        RunEvidenceReferenceMismatch("control_admission.sample_output"),
      )
    }
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
  Ok(output_ids)
}

///|
pub(all) struct InteractiveRelationSampleLimits {
  max_items : Int64
  max_bytes : Int64
  max_artifacts : Int64
  ttl_seconds : Int64
  required : Bool
}

///|
/// The already admitted profile's exact output inventory and retention bounds.
/// The existing Run owner binds these facts to its authenticated admission.
struct InteractiveRelationSampleSelection {
  limits : InteractiveRelationSampleLimits
  outputs : Map[String, Bool]
}

///|
pub fn bind_interactive_relation_sample_selection(
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
) -> Result[InteractiveRelationSampleSelection?, RunEvidenceValueIssue] {
  checked_interactive_admission_outputs(
    intent, requested, effective, resolved, map, admission, plan, original_namespace_id,
    original_run_definition_cid, max_bytes, max_nodes, max_depth,
  ).map(outputs => {
    inspect_interactive_relation_sample_selection(effective, outputs)
  })
}

///|
fn inspect_interactive_relation_sample_selection(
  effective : RunEvidenceValue,
  outputs : Map[String, Bool],
) -> InteractiveRelationSampleSelection? {
  guard outputs.length() > 0 &&
    @json.object_field(effective.value, "retain") is Some(retain) &&
    @json.object_field(retain, "samples") is Some(samples) &&
    interactive_integer(samples, "max_items") is Some(max_items) &&
    evidence_string(samples, "max_bytes") is Some(bytes) &&
    @scalar.read_decimal_int64(bytes) is Ok(max_bytes) &&
    max_bytes > 0L &&
    interactive_integer(samples, "max_artifacts") is Some(max_artifacts) &&
    interactive_integer(samples, "ttl_seconds") is Some(ttl_seconds) &&
    @json.object_field(samples, "required") is Some(@json.Bool(required)) else {
    return None
  }
  Some({
    limits: { max_items, max_bytes, max_artifacts, ttl_seconds, required, },
    outputs,
  })
}

///|
fn interactive_terminal_execution(
  profile : RunEvidenceValue,
) -> @json.CanonicalValue? {
  guard profile.name == "control_profile" &&
    @json.object_field(profile.value, "execution") is Some(execution) &&
    evidence_string(execution, "default_until") == Some("terminal") &&
    @json.object_field(execution, "breakpoints")
    is Some(@json.Array(breakpoints)) &&
    @json.array_count(breakpoints) == 0 &&
    @json.object_field(execution, "guards") is Some(@json.Null) else {
    return None
  }
  Some(execution)
}

///|
/// The admitted profile must allow the entire terminal interval and
/// explicitly disable the entry stop before using the unattended starter.
pub fn interactive_profile_allows_unattended_terminal(
  profile : RunEvidenceValue,
) -> Bool {
  interactive_terminal_execution(profile) is Some(execution) &&
  @json.object_field(execution, "stop_on_entry") is Some(@json.Bool(false))
}

///|
/// The installed first-resume path accepts only the checked entry stop
/// without a guard or breakpoint that would alter its explicit interval.
pub fn interactive_profile_requires_entry_stop(
  profile : RunEvidenceValue,
) -> Bool {
  interactive_terminal_execution(profile) is Some(execution) &&
  @json.object_field(execution, "stop_on_entry") is Some(@json.Bool(true))
}

///|
/// Look up the original logical output in the set already checked during
/// admission. Permission and physical output remain separate.
pub fn interactive_relation_sample_output_limits(
  selection : InteractiveRelationSampleSelection,
  port_id : String,
) -> InteractiveRelationSampleLimits? {
  if selection.outputs.contains(port_id) {
    Some(selection.limits)
  } else {
    None
  }
}

///|
/// Resolve an explicitly installed all-output Sample profile on the original
/// accepted Run. The Host supplies the authenticated Journal reference, and
/// funds emission and validation before entering this structural issuer.
/// This profile leaves control commands to the existing Run owner.
pub fn issue_interactive_relation_sample_admission(
  run : PublicationContract,
  plan : PublicationContract,
  prepared : RunEvidenceValue,
  authorization : RunEvidenceValue,
  requested : RunEvidenceValue,
  map : RunEvidenceValue,
  reference_wire : String,
  fingerprint_cid : String,
  authority_scope_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (RunEvidenceValue, RunEvidenceValue, RunEvidenceValue),
  RunEvidenceValueIssue,
] {
  guard reference_wire.length() <= Int::min(4096, max_bytes) &&
    valid_contract_cid(fingerprint_cid) &&
    valid_contract_cid(authority_scope_cid) else {
    return Err(
      RunEvidenceReferenceMismatch("control_admission.original_request"),
    )
  }
  guard validate_original_interactive_run_evidence(run, prepared, authorization)
    is Ok(_) &&
    contract_string(run, "compiled_plan_cid") == Some(plan.identity) &&
    contract_string(run, "scope_id") is Some(namespace_id) &&
    evidence_string(authorization.value, "host_policy_cid") is Some(policy_cid) else {
    return Err(RunEvidenceReferenceMismatch("control_admission.original_run"))
  }
  match check_interactive_profile_bounds(requested) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard interactive_terminal_execution(requested) is Some(_) &&
    @json.object_field(requested.value, "retain") is Some(retain) &&
    @json.object_field(retain, "intermediate") is None &&
    @json.object_field(retain, "samples") is Some(samples) &&
    evidence_string(samples, "capture_scope") == Some("all_outputs") else {
    return Err(RunEvidenceReferenceMismatch("control_profile.installed_sample"))
  }
  // Read the admitted map here. The same-Run consumer still checks full
  // key and port binding before it can issue a physical start ticket.
  guard map.name == "logical_map" &&
    evidence_string(map.value, "compiled_plan_cid") == Some(plan.identity) &&
    evidence_string(map.value, "program_definition_cid") ==
    evidence_string(plan.value, "program_definition_cid") &&
    @json.object_field(map.value, "steps") is Some(@json.Array(steps)) else {
    return Err(RunEvidenceReferenceMismatch("control_admission.plan_map"))
  }
  let (resolved_wire, run_ref_wire) = try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-resolved-control-profile/0.1")
    @encode.key(writer, "requested_profile_cid")
    @encode.string_value(writer, requested.identity)
    @encode.key(writer, "effective_profile_cid")
    @encode.string_value(writer, requested.identity)
    @encode.key(writer, "compiled_plan_cid")
    @encode.string_value(writer, plan.identity)
    @encode.key(writer, "logical_map_cid")
    @encode.string_value(writer, map.identity)
    @encode.key(writer, "breakpoints")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "sample_output_port_ids")
    @encode.begin_array(writer)
    for i in 0..<@json.array_count(steps) {
      let step = @json.array_at(steps, i).unwrap()
      guard @json.object_field(step, "ports") is Some(@json.Array(ports)) else {
        return Err(RunEvidenceInvalidShape)
      }
      for j in 0..<@json.array_count(ports) {
        let port = @json.array_at(ports, j).unwrap()
        if evidence_string(port, "role") == Some("output") {
          @encode.string_value(
            writer,
            evidence_string(port, "port_id").unwrap(),
          )
        }
      }
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    let resolved_wire = @encode.finish(writer)
    let reference = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(reference)
    @encode.key(reference, "namespaceId")
    @encode.string_value(reference, namespace_id)
    @encode.key(reference, "authorityScopeCid")
    @encode.string_value(reference, authority_scope_cid)
    @encode.key(reference, "runDefinitionCid")
    @encode.string_value(reference, run.identity)
    @encode.end_object(reference)
    (resolved_wire, @encode.finish(reference))
  } catch {
    _ => return Err(RunEvidenceEncoding)
  }
  let intent_wire = "{\"version\":\"actql-control-request-intent/0.1\",\"submission_ref\":" +
    reference_wire +
    ",\"legacy_request_fingerprint_cid\":\"" +
    fingerprint_cid +
    "\",\"requested_profile_cid\":\"" +
    requested.identity +
    "\",\"expected_plan_cid\":null}"
  let intent = match
    seal_run_evidence_value(
      "control_request_intent", intent_wire, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let resolved = match
    seal_run_evidence_value(
      "resolved_control_profile", resolved_wire, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let admission_wire = "{\"version\":\"actql-control-admission/0.1\",\"run_ref\":" +
    run_ref_wire +
    ",\"request_intent_cid\":\"" +
    intent.identity +
    "\",\"compiled_plan_cid\":\"" +
    plan.identity +
    "\",\"logical_map_cid\":\"" +
    map.identity +
    "\",\"resolved_profile_cid\":\"" +
    resolved.identity +
    "\",\"policy_revision_cid\":\"" +
    policy_cid +
    "\"}"
  let admission = match
    seal_run_evidence_value(
      "control_admission", admission_wire, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  Ok((intent, resolved, admission))
}

///|
/// Finite geometry for comparing one complete original submission reference.
pub fn interactive_submission_reference_limits() -> (Int, Int, Int) {
  (4096, 32, 4)
}

///|
/// Match the adopted Request and exact retained reference, including epoch
/// authenticator and nonce. The existing Journal authenticates the supplied
/// original beforehand. The caller funds the bounded canonical comparison.
pub fn check_interactive_admission_request_identity(
  intent : RunEvidenceValue,
  admission : RunEvidenceValue,
  fingerprint_cid : String,
  authority_scope_cid : String,
  original_reference_wire : String,
) -> Bool {
  guard intent.name == "control_request_intent" &&
    admission.name == "control_admission" &&
    evidence_string(intent.value, "legacy_request_fingerprint_cid") ==
    Some(fingerprint_cid) &&
    @json.object_field(admission.value, "run_ref") is Some(run) &&
    evidence_string(run, "authorityScopeCid") == Some(authority_scope_cid) &&
    @json.object_field(intent.value, "submission_ref") is Some(reference) else {
    return false
  }
  let (bytes, nodes, depth) = interactive_submission_reference_limits()
  canonical_value_wire(reference, bytes, nodes, depth) ==
  Some(original_reference_wire)
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
