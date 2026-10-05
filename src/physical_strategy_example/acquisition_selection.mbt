///|
/// Benchmark preparation over the existing data-configured example.
/// Selection still belongs to query_planning, and execution to the standard
/// Native/Broad Host. This does not change the public Client's fixed policy.
struct ApplicationAcquisitionSelection {
  requirement : @planning.QueryRequirement
  candidates : Array[@planning.AcquisitionCandidate]
  outcome : @planning.AcquisitionSelection
  native : @acquisition_host.NativeHostConfiguration?
  broad : @acquisition_host.BroadHostConfiguration?
  limits : @acquisition_host.NativeHostLimits
}

///|
fn application_broad_acquisition_limits(
  native : @acquisition_host.NativeHostLimits,
) -> @acquisition_host.BroadHostLimits {
  {
    // The same existing cumulative receiver envelope is offered to both
    // realizations. Broad residual rows remain subject to the output ceiling.
    physical: native.physical,
    metadata_work: native.metadata_work,
    retention: native.retention,
    transport: native.transport,
    completion: {
      execution: {
        rows: {
          max_rows: native.output_rows,
          metadata_entries: 10000,
          retained_entries: 10000,
          operation_entries: 10000,
          input_values: native.retention,
          output_values: native.retention,
        },
        max_work: native.retention.max_work,
        max_frames: 10000,
      },
      guards: {
        max_work: native.measurement.max_work,
        max_bytes: native.measurement.max_bytes,
        max_nodes: native.measurement.max_nodes,
        max_depth: native.measurement.max_depth,
      },
      retention: {
        received_wire_bytes: native.completion.max_received_bytes,
        retained_wire_bytes: native.completion.max_retained_wire_bytes,
        measurement: native.completion.receipts,
      },
      records: native.completion.records,
      capture: native.completion.capture,
    },
  }
}

///|
/// Before provider I/O, compare both actual preparations for one checked
/// requirement. Unknown estimates defer unless the Host supplies priority.
fn core_application_select_acquisition(
  app : Application,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  priority : Array[Int],
) -> ApplicationAcquisitionSelection raise {
  guard app.data is Some(_) else {
    fail("acquisition comparison requires an explicit data profile")
  }
  let requirement = @acquisition_host.configured_capture_requirement(
    @acquisition_host.native_capture_configuration(app.acquisition),
  )
  let limits = @acquisition_host.configured_native_host_limits(app.acquisition)
  // Reuse the original checked physical preparation. The logical Source
  // identity is not a SQL schema/table binding, and must not be reinterpreted.
  let preparation = app.acquisition_preparation
  let registration = @connector.capability_registration_at(app.registry, 1).unwrap()
  let quantities : @connector.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let native = @duckdb_query.duckdb_native_candidate(
    registration,
    preparation,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], milliseconds: None, }],
    quantities,
    100,
  ).unwrap()
  let broad = @duckdb_query.duckdb_broad_candidate(
    registration,
    preparation,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: None, }],
    quantities,
    100,
  ).unwrap()
  let candidates = [
    @planning.prepared_acquisition_candidate(native),
    @planning.prepared_acquisition_candidate(broad),
  ]
  let outcome = @planning.choose_acquisition_candidate(
    app.registry,
    requirement,
    candidates,
    if priority.is_empty() {
      None
    } else {
      Some(priority)
    },
    100,
  ).unwrap()
  let contracts = @planning.admit_query_evidence_contracts(
    contract(query_json),
    contract(evidence_json),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  ).unwrap()
  let receipts = @planning.admit_query_two_receipt_contract(
    contracts,
    contract(two_receipt_json),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  ).unwrap()
  let mut native_configuration = None
  let mut broad_configuration = None
  if outcome is Proposed(choice) {
    if @planning.acquisition_choice_payload(choice, native) is Some(_) {
      native_configuration = Some(
        @acquisition_host.configure_native_host(
          receipts, requirement, choice, native, limits,
        ),
      )
    } else if @planning.acquisition_choice_payload(choice, broad) is Some(_) {
      broad_configuration = Some(
        @acquisition_host.configure_broad_host(
          contracts,
          requirement,
          choice,
          broad,
          application_broad_acquisition_limits(limits),
        ),
      )
    } else {
      fail("foreign acquisition choice")
    }
  }
  {
    requirement,
    candidates,
    outcome,
    native: native_configuration,
    broad: broad_configuration,
    limits,
  }
}

///|
fn core_application_acquisition_selection_native(
  selected : ApplicationAcquisitionSelection,
) -> @acquisition_host.NativeHostConfiguration? {
  selected.native
}

///|
fn core_application_acquisition_selection_broad(
  selected : ApplicationAcquisitionSelection,
) -> @acquisition_host.BroadHostConfiguration? {
  selected.broad
}

///|
fn core_application_acquisition_selection_document(
  selected : ApplicationAcquisitionSelection,
) -> String {
  let names = ["nativeQuery", "broadQuery"]
  let (status, reason, index) = match selected.outcome {
    Deferred => ("deferred", "Deferred", None)
    NoCandidates => ("no_candidates", "NoCandidates", None)
    Proposed(choice) => {
      let reason : @cost.CostChoice = @planning.acquisition_choice_reason(
        choice,
      )
      match reason {
        HostPreferred(index) => ("selected", "HostPreferred", Some(index))
        EstimatedFastest(index, _) =>
          ("selected", "EstimatedFastest", Some(index))
        _ => ("invalid", "Invalid", None)
      }
    }
  }
  let limits = selected.limits
  let document : Json = {
    "requirementCid": @planning.query_requirement_cid(selected.requirement),
    "status": status,
    "reason": reason,
    "selectedIndex": match index {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
    "selectedCandidate": match index {
      Some(value) => Json::string(names[value])
      None => Json::null()
    },
    "candidates": selected.candidates.mapi((index, candidate) => {
      let duration : Json = match
        @planning.acquisition_candidate_duration(candidate) {
        Complete(value) => Json::string(value.to_string())
        Unknown => Json::null()
      }
      let entry : Json = {
        "candidate": names[index],
        "index": index,
        "registration": @connector.capability_registration_selection_key(
          @planning.acquisition_candidate_registration(candidate),
        ),
        "milliseconds": duration,
      }
      entry
    }),
    "receiver": {
      "maxRows": limits.physical.max_rows,
      "maxCells": limits.physical.max_cells,
      "maxNodes": limits.physical.max_nodes,
      "maxTextBytes": limits.physical.max_text_bytes,
      "maxOutputRows": limits.output_rows,
      "maxReceivedRows": limits.completion.max_received_rows,
      "maxReceivedBytes": limits.completion.max_received_bytes,
      "maxRetainedWireBytes": limits.completion.max_retained_wire_bytes,
    },
  }
  document.stringify()
}
