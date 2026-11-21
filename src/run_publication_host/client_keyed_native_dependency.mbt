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
priv enum NativeLookupAppendScope {
  StandaloneWire
  ReturnedWire
  CatalogWire
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
  serial? : KeyedDependencySerialFunding? = None,
  retain_catalog? : Bool = true,
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
    client_composed_keyed_original_component(original) is Some(component) &&
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
  fn append_measured(
    kind : String,
    cid : String,
    wire : String,
    wire_extent : (Int, Int)?,
    scope : NativeLookupAppendScope,
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
    let funding = if !(scope is StandaloneWire) && serial is Some(funding) {
      funding.before
    } else {
      before_body
    }
    let (body, bytes) = require_native_lookup_dependency(
      admit_client_effect_dependency_capture_body(
        kind,
        Some(cid),
        wire,
        remaining,
        max_nodes,
        max_depth,
        funding,
        () => {
          !lookup.closed &&
          lookup.left.lookup_issue is None &&
          lookup.native_completion
          .map(value => physical_equal(value, completed))
          .unwrap_or(false)
        },
        wire_extent~,
      ),
    )
    bodies.push(body)
    seen[key] = wire
    remaining -= bytes
    // The synchronous admission returned. No parser cursor is in the
    // retained dependency body or the duplicate table.
    if scope is ReturnedWire &&
      serial is Some(funding) &&
      !(funding.record)(bodies) {
      raise NativeLookupDependencyStop(ConstructionRefused)
    }
  }
  fn append(
    kind : String,
    cid : String,
    wire : String,
  ) -> Unit raise NativeLookupDependencyStop {
    append_measured(kind, cid, wire, None, StandaloneWire)
  }
  fn contract(
    kind : String,
    value : @publication.PublicationContract,
    serial_member : Bool,
  ) -> Unit raise NativeLookupDependencyStop {
    // The SAME sealed original owns these encoder facts and the wire below.
    // Preserve full body/CID admission; unknown wires keep the byte-node bound.
    let extent = @publication.publication_contract_wire_usage(value).map(usage => {
      (usage.0, usage.1)
    })
    append_measured(
      kind,
      @publication.publication_contract_identity(value),
      @publication.publication_contract_json(value),
      extent,
      if serial_member {
        ReturnedWire
      } else {
        StandaloneWire
      },
    )
  }
  fn evidence(
    kind : String,
    value : @publication.RunEvidenceValue,
  ) -> Unit raise NativeLookupDependencyStop {
    let extent = @publication.run_evidence_value_wire_usage(value).map(usage => {
      (usage.0, usage.1)
    })
    append_measured(
      kind,
      @publication.run_evidence_value_identity(value),
      @publication.run_evidence_value_json(value),
      extent,
      StandaloneWire,
    )
  }
  fn receive_policy_body(
    body : @publication.CapturedEffectDependencyBody,
    bytes : Int,
  ) -> Result[Unit, @checked.LocalDependencyBodyIssue] {
    let kind = @publication.captured_effect_dependency_body_kind(body)
    let cid = @publication.captured_effect_dependency_body_cid(body)
    let wire = @publication.captured_effect_dependency_body_json(body)
    let key = kind + "\u0000" + cid
    if lookup.closed ||
      lookup.left.lookup_issue is Some(_) ||
      !lookup.native_completion
      .map(value => physical_equal(value, completed))
      .unwrap_or(false) {
      return Err(ForeignBody)
    }
    if seen.get(key) is Some(previous) {
      return if previous == wire { Ok(()) } else { Err(ForeignBody) }
    }
    if bytes < 0 || bytes > remaining || bodies.length() >= limits.max_entries {
      return Err(BudgetExceeded)
    }
    // The policy codec already admitted this SAME body after its measured
    // construction. Keep its original, rather than decode a wire copy again.
    bodies.push(body)
    seen[key] = wire
    remaining -= bytes
    Ok(())
  }
  let policy_receiver = Some(receive_policy_body)
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
    let (wire, bytes, nodes, _) = try {
      let writer = @encode.writer(remaining, max_nodes, max_depth)
      produce(writer)
      @encode.finish_text_usage(writer)
    } catch {
      _ => raise NativeLookupDependencyStop(Dependency(InvalidBody))
    }
    append_measured(kind, cid, wire, Some((bytes, nodes)), StandaloneWire)
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
      contract(kind, value, false)
    }
    evidence("source_input_logical", completed.input)
    evidence("source_evidence", completed.source)
    guard lookup.publication_identity is Some(identity) else {
      return Err(ForeignInput)
    }
    contract("request_key_set", identity.keys, false)
    contract("acquisition_scope", identity.scope, false)
    // The keyed scope names this SAME checked template's static request.
    // Each Whole Source request below is an independent scope obligation.
    append(
      "request_values",
      identity.static_request_cid,
      identity.static_request,
    )
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
    guard @lower.preparation_carrier_at(
        @lower.bound_preparation(original.keyed.owner),
        component.original.fragments.left_target,
      )
      is Some(left_carrier) &&
      @pipeline.input_at(
        @lower.pipeline(@lower.bound_preparation(original.keyed.owner)),
        @acquisition.keyed_join_input(original.keyed.binding.join),
      )
      is Some((_, right)) else {
      return Err(ForeignInput)
    }
    carrier(
      left_carrier,
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
    guard client_composed_keyed_original_graph_nodes(original)
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
      contract("acquisition_relation", source.relation, false)
      contract("ordering_evidence", source.ordering, false)
      contract("acquisition_scope", source.scope, false)
      contract("result_retention_policy", source.retention, false)
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
        contract(kind, value, true)
      }
      append_measured(
        "relation_value",
        page.logical_value_cid,
        page.body,
        None,
        ReturnedWire,
      )
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
        let funding = match serial {
          None => before_body
          Some(policy_funding) => {
            if !(policy_funding.begin_batch)(bodies.length()) {
              raise NativeLookupDependencyStop(ConstructionRefused)
            }
            policy_funding.before
          }
        }
        {
          let selected = require_native_lookup_dependency(
            checked_client_source_policy_bodies(
              program,
              policy,
              remaining,
              max_nodes,
              max_depth,
              max_nodes,
              retain_catalog~,
              retained_body_keys=Some(seen),
              before_body=funding,
              admitted_body=policy_receiver,
            ).map_err(issue => Static(issue)),
          )
          if serial is Some(_) && !selected.is_empty() {
            raise NativeLookupDependencyStop(ForeignInput)
          }
          for (kind, cid, wire) in selected {
            append(kind, cid, wire)
          }
        }
        if serial is Some(policy_funding) && !(policy_funding.record)(bodies) {
          raise NativeLookupDependencyStop(ConstructionRefused)
        }
      }
    }
    // Resolve only Catalog/retention references derived by the typed decoder.
    // The same checked Program selects exact bodies. Already retained checked
    // policies never fall back to a Catalog guess or another Host policy.
    let mut index = 0
    let mut references = 0
    while index < bodies.length() {
      let body = bodies[index]
      let count = @publication.captured_effect_dependency_body_reference_count(
        body,
      )
      if count > limits.max_references - references {
        return Err(Dependency(ReferenceLimit))
      }
      references += count
      index += 1
      // The admitted body keeps its immutable edges. One borrowed pair and
      // its Option are live across each nested call, instead of a copied vector.
      for slot in 0..<count {
        guard @publication.captured_effect_dependency_body_reference_at(
            body, slot,
          )
          is Some((kind, cid)) else {
          return Err(Dependency(InvalidBody))
        }
        if seen.contains(kind + "\u0000" + cid) {
          continue
        }
        if kind == "result_retention_policy" &&
          cid == @publication.publication_contract_identity(retention) {
          contract(kind, retention, true)
        } else if kind == "source_view_contract" &&
          physical_source is Some((original_cid, original_wire)) &&
          cid == original_cid {
          // The physical descriptor owns this implementation-only view;
          // the logical checked Source Catalog need not contain it.
          append_measured(kind, cid, original_wire, None, ReturnedWire)
        } else if retain_catalog &&
          [
            "source_contract", "source_view_contract", "data_policy", "request_schema",
            "carrier_schema", "schema_evidence", "capability_evidence",
          ].contains(kind) {
          let funding = match serial {
            None => before_body
            Some(catalog) => {
              if !(catalog.begin_batch)(bodies.length()) {
                raise NativeLookupDependencyStop(ConstructionRefused)
              }
              catalog.before
            }
          }
          {
            let body = require_native_lookup_dependency(
              @checked.checked_local_catalog_dependency_body(
                program,
                client_composed_keyed_original_stage(original),
                kind,
                cid,
                remaining,
                max_nodes,
                max_depth,
                before_body=funding,
              ).map_err(issue => Static(issue)),
            )
            append_measured(
              kind,
              cid,
              @checked.checked_local_dependency_body_json(body),
              None,
              CatalogWire,
            )
          }
          if serial is Some(catalog) && !(catalog.record)(bodies) {
            raise NativeLookupDependencyStop(ConstructionRefused)
          }
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
