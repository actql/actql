///|
/// Trusted Host estimates for one existing physical implementation. Quantities
/// are optional evidence, never authority, reservations, or latency weights.
pub(all) struct ClientDuckDBAcquisitionEstimate {
  estimates : Array[@cost.SerialEstimateLine]
  quantities : @connector.QueryQuantities
}

///|
/// Retains the exact proposed candidate and its configured physical payload.
/// A diagnostic name or canonical requirement CID cannot recreate this owner.
struct ClientDuckDBAcquisitionSelection {
  requirement : @planning.QueryRequirement
  candidates : Array[@planning.AcquisitionCandidate]
  names : Array[String]
  outcome : @planning.AcquisitionSelection
  native : @duckdb_host.NativeHostConfiguration?
  broad : @duckdb_host.BroadHostConfiguration?
  native_supported : Bool
  broad_supported : Bool
  estimates : Json
  selection_basis : String
  missing : Array[String]
}

///|
/// Prepare both real paths before choosing once. Unsupported Native work is
/// excluded before comparison; malformed estimates fail instead of silently
/// becoming capability absence. No I/O or execution-time fallback occurs here.
pub fn select_client_duckdb_acquisition(
  requirement : @planning.QueryRequirement,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
  native_estimate : ClientDuckDBAcquisitionEstimate,
  broad_estimate : ClientDuckDBAcquisitionEstimate,
  host_priority? : Array[String]? = None,
) -> Result[ClientDuckDBAcquisitionSelection, ClientDuckDBAcquisitionIssue] {
  let (contracts, receipts, preparation, registry) = match
    prepare_client_duckdb_acquisition_parts(
      requirement, database_schema, table, query_contract_body, evidence_contract_body,
      two_receipt_contract_body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @connector.capability_registration_at(registry, 0) is Some(registration) else {
    return Err(Registration)
  }
  guard validate_client_duckdb_estimate(native_estimate, 11) &&
    validate_client_duckdb_estimate(broad_estimate, 8) else {
    return Err(Candidate)
  }
  let context = match
    @duckdb_host.prepare_native_source_evidence_context(requirement) {
    Ok(value) => value
    Err(_) => return Err(InvalidContracts)
  }
  let native_candidate = if @duckdb_host.source_evidence_context_supports(
      context,
      @planning.query_two_receipt_contract_cid(receipts),
    ) {
    match
      @duckdb_query.duckdb_native_candidate(
        registration,
        preparation,
        native_estimate.estimates,
        native_estimate.quantities,
        100,
      ) {
      Ok(value) => Some(value)
      Err(Unsupported(_)) => None
      Err(Planning(_)) => return Err(Candidate)
    }
  } else {
    None
  }
  let broad_candidate = if @duckdb_host.source_evidence_context_supports(
      context,
      @planning.query_evidence_contract_identity(),
    ) {
    match
      @duckdb_query.duckdb_broad_candidate(
        registration,
        preparation,
        broad_estimate.estimates,
        broad_estimate.quantities,
        100,
      ) {
      Ok(value) => Some(value)
      Err(_) => return Err(Candidate)
    }
  } else {
    None
  }
  let candidates = []
  let names = []
  if native_candidate is Some(candidate) {
    candidates.push(@planning.prepared_acquisition_candidate(candidate))
    names.push("nativeQuery")
  }
  if broad_candidate is Some(candidate) {
    candidates.push(@planning.prepared_acquisition_candidate(candidate))
    names.push("broadQuery")
  }
  // A sole eligible implementation does not require a relative cost claim.
  // Explicit priority is mapped only after eligibility filtering, never used
  // to insert an unsupported candidate into the comparison.
  let priority = match host_priority {
    Some(order) => {
      if order.length() != 2 ||
        !(order == ["nativeQuery", "broadQuery"] ||
        order == ["broadQuery", "nativeQuery"]) {
        return Err(Selection)
      }
      let positions = []
      for name in order {
        for index in 0..<names.length() {
          if names[index] == name {
            positions.push(index)
          }
        }
      }
      Some(positions)
    }
    None => if candidates.length() == 1 { Some([0]) } else { None }
  }
  let missing = []
  for index in 0..<candidates.length() {
    let estimate = if names[index] == "nativeQuery" {
      native_estimate
    } else {
      broad_estimate
    }
    let slots = if names[index] == "nativeQuery" { 11 } else { 8 }
    for slot in 0..<slots {
      let mut known = false
      for line in estimate.estimates {
        if line.work_slots.contains(slot) && line.milliseconds is Some(_) {
          known = true
        }
      }
      if !known {
        missing.push(
          names[index] + ".workSlots[" + slot.to_string() + "].milliseconds",
        )
      }
    }
  }
  let outcome = match
    @planning.choose_acquisition_candidate(
      registry, requirement, candidates, priority, 100,
    ) {
    Ok(value) => value
    Err(_) => return Err(Selection)
  }
  let mut native = None
  let mut broad = None
  if outcome is Proposed(choice) {
    if native_candidate is Some(candidate) &&
      @planning.acquisition_choice_payload(choice, candidate) is Some(_) {
      native = Some(
        configure_client_duckdb_native(requirement, receipts, choice, candidate),
      )
    } else if broad_candidate is Some(candidate) &&
      @planning.acquisition_choice_payload(choice, candidate) is Some(_) {
      broad = Some(
        configure_client_duckdb_broad(requirement, contracts, choice, candidate),
      )
    } else {
      return Err(Selection)
    }
  }
  Ok({
    requirement,
    candidates,
    names,
    outcome,
    native,
    broad,
    native_supported: native_candidate is Some(_),
    broad_supported: broad_candidate is Some(_),
    selection_basis: if candidates.length() == 1 {
      "onlyEligible"
    } else if host_priority is Some(_) {
      "explicitPriority"
    } else {
      "estimatedLatency"
    },
    missing,
    estimates: {
      "nativeQuery": client_duckdb_estimate_json(native_estimate),
      "broadQuery": client_duckdb_estimate_json(broad_estimate),
    },
  })
}

///|
pub fn client_duckdb_selection_native(
  selected : ClientDuckDBAcquisitionSelection,
) -> @duckdb_host.NativeHostConfiguration? {
  selected.native
}

///|
pub fn client_duckdb_selection_broad(
  selected : ClientDuckDBAcquisitionSelection,
) -> @duckdb_host.BroadHostConfiguration? {
  selected.broad
}

///|
/// Bounded diagnostic projection of the actual common choice. Candidate names
/// identify physical realizations; positions are local comparison addresses.
/// Neither is a canonical identity or a substitute for the live typed owner.
pub fn client_duckdb_selection_document(
  selected : ClientDuckDBAcquisitionSelection,
) -> String {
  let candidates : Array[Json] = []
  for index in 0..<selected.candidates.length() {
    let candidate = selected.candidates[index]
    let duration = match @planning.acquisition_candidate_duration(candidate) {
      Complete(value) => Json::string(value.to_string())
      Unknown => Json::null()
    }
    let quantities = @planning.acquisition_candidate_quantities(candidate)
    let quantity = fn(value : Int64?) -> Json {
      match value {
        Some(value) => Json::string(value.to_string())
        None => Json::null()
      }
    }
    candidates.push({
      "candidate": selected.names[index],
      "index": index,
      "registration": @connector.capability_registration_selection_key(
        @planning.acquisition_candidate_registration(candidate),
      ),
      "milliseconds": duration,
      "transferBytes": quantity(quantities.transfer_bytes),
      "retainedBytes": quantity(quantities.retained_bytes),
      "moneyUnits": quantity(quantities.money_units),
    })
  }
  let (status, reason, index) = match selected.outcome {
    Deferred => ("deferred", "Deferred", None)
    NoCandidates => ("no_candidates", "NoCandidates", None)
    Proposed(choice) =>
      match @planning.acquisition_choice_reason(choice) {
        EstimatedFastest(index, _) =>
          ("selected", "EstimatedFastest", Some(index))
        HostPreferred(index) => ("selected", "HostPreferred", Some(index))
        _ => ("invalid", "Invalid", None)
      }
  }
  let document : Json = {
    "requirementCid": @planning.query_requirement_cid(selected.requirement),
    "status": status,
    "reason": reason,
    "selectionBasis": selected.selection_basis,
    "missing": selected.missing,
    "selectedIndex": match index {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
    "selectedCandidate": match index {
      Some(value) => Json::string(selected.names[value])
      None => Json::null()
    },
    "nativeSupported": selected.native_supported,
    "broadSupported": selected.broad_supported,
    "estimates": selected.estimates,
    "candidates": candidates,
  }
  document.stringify()
}

///|
fn validate_client_duckdb_estimate(
  estimate : ClientDuckDBAcquisitionEstimate,
  slots : Int,
) -> Bool {
  @cost.assess_serial(slots, estimate.estimates, 100) is Ok(_) &&
  @connector.valid_quantity(estimate.quantities.transfer_bytes) &&
  @connector.valid_quantity(estimate.quantities.retained_bytes) &&
  @connector.valid_quantity(estimate.quantities.money_units)
}

///|
fn client_duckdb_estimate_json(
  estimate : ClientDuckDBAcquisitionEstimate,
) -> Json {
  let lines : Array[Json] = []
  for line in estimate.estimates {
    lines.push({
      "workSlots": line.work_slots,
      "milliseconds": client_duckdb_quantity_json(line.milliseconds),
    })
  }
  {
    "estimates": lines,
    "quantities": {
      "transferBytes": client_duckdb_quantity_json(
        estimate.quantities.transfer_bytes,
      ),
      "retainedBytes": client_duckdb_quantity_json(
        estimate.quantities.retained_bytes,
      ),
      "moneyUnits": client_duckdb_quantity_json(estimate.quantities.money_units),
    },
  }
}

///|
/// Bounded structural ABI for the trusted Host. The common estimator validates
/// slot coverage; this constructor only preserves the supplied typed inputs.
pub fn client_duckdb_acquisition_estimate(
  work_slots : Array[Array[Int]],
  milliseconds : Array[Int64?],
  quantities : Array[Int64?],
) -> Result[ClientDuckDBAcquisitionEstimate, ClientDuckDBAcquisitionIssue] {
  if work_slots.length() != milliseconds.length() ||
    work_slots.length() > 100 ||
    quantities.length() != 3 {
    return Err(Candidate)
  }
  let estimates : Array[@cost.SerialEstimateLine] = []
  for index in 0..<work_slots.length() {
    if work_slots[index].length() > 11 {
      return Err(Candidate)
    }
    estimates.push({
      work_slots: work_slots[index].copy(),
      milliseconds: milliseconds[index],
    })
  }
  Ok({
    estimates,
    quantities: {
      transfer_bytes: quantities[0],
      retained_bytes: quantities[1],
      money_units: quantities[2],
    },
  })
}

///|
fn client_duckdb_quantity_json(value : Int64?) -> Json {
  match value {
    Some(value) => Json::string(value.to_string())
    None => Json::null()
  }
}
