///|
priv suberror NativeLookupDependencyStop {
  NativeLookupDependencyStop(ClientEffectDependencyCaptureIssue)
}

///|
fn[T] require_native_lookup_dependency(
  value : Result[T, ClientEffectDependencyCaptureIssue],
) -> T raise NativeLookupDependencyStop {
  match value {
    Ok(value) => value
    Err(issue) => raise NativeLookupDependencyStop(issue)
  }
}

///|
/// Retain the existing completed Native Lookup's original protocol, Source,
/// Carrier and checked Catalog bodies for Effect dependency custody. This
/// executes no Source, Model, compiler or Request issuer. The caller backs the
/// bounded metadata/first durable wire copies before entry; the lookup still
/// owns all physical children, consumed work and failed-cleanup obligations.
pub fn client_keyed_lookup_native_dependency_bodies(
  lookup : ClientKeyedLookupInput,
  retention : @publication.PublicationContract,
  limits : @publication.CapturedEffectDependencyLimits,
  max_nodes : Int,
  max_depth : Int,
  physical_source? : (String, String)? = None,
  before_body? : ((Int, Int, Int) -> Bool)? = None,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  ClientEffectDependencyCaptureIssue,
] {
  guard client_keyed_lookup_native_completion(lookup) is Some(completed) else {
    return Err(ForeignInput)
  }
  keyed_lookup_native_dependency_bodies_from_original(
    lookup, completed, retention, limits, max_nodes, max_depth, physical_source,
    before_body,
  )
}

///|
// The completion constructor uses its SAME retained original before the
// reservation becomes a holding/Model Read. The public wrapper above still
// requires the existing completed-input entrance; no phase flag escapes.
fn keyed_lookup_native_dependency_bodies_from_original(
  lookup : ClientKeyedLookupInput,
  completed : ClientKeyedNativeCompletion,
  retention : @publication.PublicationContract,
  limits : @publication.CapturedEffectDependencyLimits,
  max_nodes : Int,
  max_depth : Int,
  physical_source : (String, String)?,
  before_body : ((Int, Int, Int) -> Bool)?,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  ClientEffectDependencyCaptureIssue,
] {
  if limits.max_entries < 0 ||
    limits.max_entries > 4096 ||
    limits.max_total_bytes < 1 ||
    limits.max_total_bytes > 16777216 ||
    limits.max_references < 0 ||
    limits.max_references > 65536 ||
    max_nodes < 1 ||
    max_depth < 1 {
    return Err(Dependency(InvalidLimits))
  }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.native_completion is Some(same_completion) &&
    physical_equal(same_completion, completed) &&
    lookup.left.composed is Some(original) &&
    original.plan.keyed is Some(component) &&
    original.keyed.program is KeyedEffect(prepared) &&
    lookup.native_sources is Some(native) &&
    native.relation is Some(left) &&
    lookup.native_left_identity is Some(left_identity) &&
    lookup.identity_receipt is Some(right_receipt) &&
    lookup.identity_bodies is Some(right_bodies) &&
    lookup.native_transport is Some(transport) &&
    lookup.native_batch_plan is Some(batch) &&
    lookup.native_read_profile is Some(profile) &&
    lookup.planned_order is Some(order) &&
    order.length() == lookup.known.length() &&
    native.sources.length() == original.sources.length() else {
    return Err(ForeignInput)
  }
  if physical_source is Some((cid, _)) &&
    @publication.file_read_profile_physical_source_contract_cid(profile) !=
    Some(cid) {
    return Err(ForeignInput)
  }
  let program = @checked.effect_program_static_checked_computation(
    prepared.candidate,
  )
  let bodies : Array[@publication.CapturedEffectDependencyBody] = []
  let seen : Map[String, String] = Map([])
  let mut remaining = limits.max_total_bytes
  fn append(
    kind : String,
    cid : String,
    wire : String,
  ) -> Unit raise NativeLookupDependencyStop {
    let key = kind + "\u0000" + cid
    if seen.get(key) is Some(previous) {
      if previous != wire {
        raise NativeLookupDependencyStop(Dependency(DuplicateIdentity))
      }
      return
    }
    if bodies.length() >= limits.max_entries {
      raise NativeLookupDependencyStop(Dependency(EntryLimit))
    }
    if wire.length() > remaining {
      raise NativeLookupDependencyStop(Dependency(ByteLimit))
    }
    let (body, bytes) = require_native_lookup_dependency(
      admit_client_effect_dependency_capture_body(
        kind,
        Some(cid),
        wire,
        remaining,
        max_nodes,
        max_depth,
        before_body,
        () => {
          !lookup.closed &&
          lookup.left.lookup_issue is None &&
          lookup.native_completion
          .map(value => physical_equal(value, completed))
          .unwrap_or(false)
        },
      ),
    )
    bodies.push(body)
    seen[key] = wire
    remaining -= bytes
  }
  fn contract(
    kind : String,
    value : @publication.PublicationContract,
  ) -> Unit raise NativeLookupDependencyStop {
    append(
      kind,
      @publication.publication_contract_identity(value),
      @publication.publication_contract_json(value),
    )
  }
  fn evidence(
    kind : String,
    value : @publication.RunEvidenceValue,
  ) -> Unit raise NativeLookupDependencyStop {
    append(
      kind,
      @publication.run_evidence_value_identity(value),
      @publication.run_evidence_value_json(value),
    )
  }
  fn emit(
    kind : String,
    cid : String,
    produce : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
  ) -> Unit raise NativeLookupDependencyStop {
    if before_body is Some(prepare) {
      let measure = try {
        let writer = @encode.measuring_writer(remaining, max_nodes, max_depth)
        produce(writer)
        @encode.finish_measurement_usage(writer)
      } catch {
        _ => raise NativeLookupDependencyStop(Dependency(InvalidBody))
      }
      if !prepare(measure.0, measure.1, measure.2) {
        raise NativeLookupDependencyStop(ConstructionRefused)
      }
      if lookup.closed || lookup.left.lookup_issue is Some(_) {
        raise NativeLookupDependencyStop(ForeignInput)
      }
    }
    let wire = try {
      let writer = @encode.writer(remaining, max_nodes, max_depth)
      produce(writer)
      @encode.finish(writer)
    } catch {
      _ => raise NativeLookupDependencyStop(Dependency(InvalidBody))
    }
    append(kind, cid, wire)
  }
  fn carrier(
    original : @carrier.Carrier,
    cid : String,
    schema_cid : String,
    schema_wire : String,
  ) -> Unit raise NativeLookupDependencyStop {
    if cid == schema_cid {
      // PresenceRelation identifies the complete field map. The actual first
      // export already retained it, including conditional presence wrappers.
      append("relation_schema", cid, schema_wire)
      return
    }
    guard client_task_contract_source(original) is Some(ObjectRelation(row)) else {
      raise NativeLookupDependencyStop(ForeignInput)
    }
    // ObjectRelation identifies the checked non-null row ValueContract, not
    // its Catalog envelope or field map. Serialize that same typed original
    // once for durable custody; do not recompile or hash the whole Graph.
    emit("carrier_contract", cid, writer => @contract.emit_checked(row, writer))
  }
  try {
    for
      (kind, value) in [
        ("lookup_accounting", completed.accounting),
        ("acquisition_attempt_receipt", completed.receipt),
        ("lookup_evidence", completed.evidence),
        ("acquisition_relation", completed.relation),
        (
          "ordering_evidence",
          @publication.result_ordering_evidence_contract(completed.ordering),
        ),
        (
          "derivation_evidence",
          @publication.result_ordering_derivation_contract(completed.ordering),
        ),
        ("result_retention_policy", completed.retention),
        ("acquisition_relation", left.artifact),
        (
          "ordering_evidence",
          @publication.result_ordering_evidence_contract(left.ordering),
        ),
        (
          "derivation_evidence",
          @publication.result_ordering_derivation_contract(left.ordering),
        ),
        ("acquisition_scope", left.scope),
        ("result_retention_policy", left.retention),
        ("native_file_lookup_transport", transport),
        ("native_file_lookup_batch_plan", batch),
        (@publication.publication_contract_name(profile), profile),
      ] {
      contract(kind, value)
    }
    evidence("source_input_logical", completed.input)
    evidence("source_evidence", completed.source)
    guard lookup.publication_identity is Some(identity) else {
      return Err(ForeignInput)
    }
    contract("request_key_set", identity.keys)
    contract("acquisition_scope", identity.scope)
    append(
      "lookup_barrier",
      component.barrier.logical_cid,
      @encode.document_text(component.barrier_body),
    )
    append(
      "relation_value",
      left_identity.logical_value_cid,
      left_identity.body,
    )
    append(
      "relation_schema",
      left_identity.relation_schema_cid,
      left_identity.schema_wire,
    )
    let right_schema = @execution.completed_relation_export_schema_identity(
      right_receipt,
    )
    append(
      "relation_value",
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(right_receipt),
      ),
      right_bodies.0,
    )
    append(
      "relation_schema",
      @execution.relation_schema_cid(right_schema),
      right_bodies.1,
    )
    guard @lower.node_at(
        @lower.bound_preparation(original.keyed.owner),
        component.original.fragments.left_step,
      )
      is Some(left_node) &&
      @pipeline.input_at(
        @lower.pipeline(@lower.bound_preparation(original.keyed.owner)),
        @acquisition.keyed_join_input(original.keyed.binding.join),
      )
      is Some((_, right)) else {
      return Err(ForeignInput)
    }
    carrier(
      @lower.node_output_carrier(left_node),
      component.left.output_contract_cid,
      left_identity.relation_schema_cid,
      left_identity.schema_wire,
    )
    carrier(
      right,
      component.original.output_contract_cid,
      @execution.relation_schema_cid(right_schema),
      right_bodies.1,
    )
    guard original.plan.graph_nodes
      .iter()
      .find_first(node => {
        @canonical.object_field(node, "node_id")
        is Some(@canonical.String(name)) &&
        name == component.left.node_id
      })
      is Some(node) &&
      @canonical.object_field(node, "pipeline") is Some(pipeline) else {
      return Err(ForeignInput)
    }
    if before_body is None {
      let pipeline_wire = @canonical.stringify_value(
        pipeline, remaining, max_nodes, max_depth,
      )
      append("task_fragment", component.left.logical_cid, pipeline_wire)
    } else {
      emit("task_fragment", component.left.logical_cid, writer => {
        @canonical.emit_value(pipeline, writer)
      })
    }
    for index, source in native.sources {
      evidence("source_input_logical", source.logical)
      evidence("source_evidence", source.observation)
      contract("acquisition_relation", source.relation)
      contract("ordering_evidence", source.ordering)
      contract("acquisition_scope", source.scope)
      contract("result_retention_policy", source.retention)
      append(
        "request_values",
        source.request_cid,
        @encode.document_text(source.request),
      )
      guard original.sources.get(index) is Some(captured) &&
        @query.captured_source_relation_dependency_bodies(
          source.identity,
          captured,
        )
        is Some((body, schema)) else {
        return Err(ForeignInput)
      }
      append(
        "relation_value",
        @query.captured_source_relation_logical_cid(source.identity),
        body,
      )
      append(
        "relation_schema",
        @query.captured_source_relation_schema_cid(source.identity),
        schema,
      )
    }
    for slot in order {
      guard lookup.known.get(slot) is Some((_, Some(_), Some(history))) &&
        history._retained_activation is Some(activation) &&
        history._retained_native_page is Some(partial) &&
        partial.result is Some(page) else {
        return Err(ForeignInput)
      }
      for
        (kind, value) in [
          ("native_file_lookup_request", activation.semantic_request),
          ("native_file_lookup_call_slot", activation.slot),
          ("native_file_lookup_activation", activation.activation),
          ("native_file_lookup_raw_response", page.raw),
          ("result_retention_policy", page.raw_retention),
          ("native_file_lookup_attempt_event", page.event),
          ("native_file_lookup_adoption", page.adoption),
        ] {
        contract(kind, value)
      }
      append("relation_value", page.logical_value_cid, page.body)
    }
    guard @environment.lookup_execution_policy(
        @acquisition.lookup_bounds_policy(original.keyed.binding.bounds),
      )
      is Some(execution) else {
      return Err(ForeignInput)
    }
    emit("lookup_execution_policy", component.original.lookup_execution_cid, writer => {
      @environment.emit_lookup_execution_policy(execution, writer)
    })
    emit("data_policy", component.original.request_policy_cid, writer => {
      @checked.emit_effective_policy(
        component.original.policies.request,
        writer,
      )
    })
    emit("data_policy", component.original.response_policy_cid, writer => {
      @checked.emit_source_response_policy(
        @checked.source_execution_subject(original.keyed.check).response_policy,
        writer,
      )
    })
    for
      policy in [
        component.original.policies.left,
        Some(component.original.output_policy),
      ] {
      if policy is Some(policy) {
        let selected = require_native_lookup_dependency(
          checked_client_source_policy_bodies(
            program,
            policy,
            remaining,
            max_nodes,
            max_depth,
            max_nodes,
            retain_catalog=true,
            retained_body_keys=Some(seen),
            before_body~,
          ).map_err(issue => Static(issue)),
        )
        for (kind, cid, wire) in selected {
          append(kind, cid, wire)
        }
      }
    }
    // Resolve only Catalog/retention references derived by the typed decoder.
    // The same checked Program selects exact bodies. Already retained checked
    // policies never fall back to a Catalog guess or another Host policy.
    let mut index = 0
    let mut references = 0
    while index < bodies.length() {
      guard @publication.captured_effect_dependency_body_references(
          bodies[index],
          limits.max_references - references,
        )
        is Some(required) else {
        return Err(Dependency(ReferenceLimit))
      }
      references += required.length()
      index += 1
      for (kind, cid) in required {
        if seen.contains(kind + "\u0000" + cid) {
          continue
        }
        if kind == "result_retention_policy" &&
          cid == @publication.publication_contract_identity(retention) {
          contract(kind, retention)
        } else if kind == "source_view_contract" &&
          physical_source is Some((original_cid, original_wire)) &&
          cid == original_cid {
          // The physical descriptor owns this implementation-only view;
          // the logical checked Source Catalog need not contain it.
          append(kind, cid, original_wire)
        } else if [
            "source_contract", "source_view_contract", "data_policy", "request_schema",
            "carrier_schema", "schema_evidence", "capability_evidence",
          ].contains(kind) {
          let body = require_native_lookup_dependency(
            @checked.checked_local_catalog_dependency_body(
              program,
              original.plan.stage,
              kind,
              cid,
              remaining,
              max_nodes,
              max_depth,
              before_body~,
            ).map_err(issue => Static(issue)),
          )
          append(kind, cid, @checked.checked_local_dependency_body_json(body))
        }
      }
    }
    if lookup.closed ||
      lookup.left.lookup_issue is Some(_) ||
      !lookup.native_completion
      .map(value => physical_equal(value, completed))
      .unwrap_or(false) {
      return Err(ForeignInput)
    }
    Ok(bodies)
  } catch {
    NativeLookupDependencyStop(issue) => Err(issue)
    _ => Err(Dependency(InvalidBody))
  }
}
