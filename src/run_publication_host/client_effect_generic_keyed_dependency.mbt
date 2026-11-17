///|
priv suberror GenericKeyedDependencyStop {
  GenericKeyedDependencyStop(ClientEffectDependencyCaptureIssue)
}

///|
fn[T] require_generic_keyed_dependency(
  value : Result[T, ClientEffectDependencyCaptureIssue],
) -> T raise GenericKeyedDependencyStop {
  match value {
    Ok(value) => value
    Err(issue) => raise GenericKeyedDependencyStop(issue)
  }
}

///|
fn build_client_effect_keyed_generic_dependency_bodies(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  state : ClientEffectKeyedGenericState,
  completed : ClientEffectKeyedGenericCompletion,
  max_nodes : Int,
  max_depth : Int,
  before_body : ((Int, Int, Int) -> Bool)?,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  ClientEffectDependencyCaptureIssue,
] {
  guard parent.plan.component is GenericKeyedPlan(component) &&
    lookup.identity_receipt is Some(right_receipt) &&
    lookup.identity_bodies is Some(right_bodies) &&
    lookup.publication_identity is Some(identity) &&
    lookup.left.composed is Some(original) &&
    original.sources is [captured] &&
    @query.captured_source_relation_dependency_bodies(
      state.source.identity,
      captured,
    )
    is Some((left_body, left_schema)) else {
    return Err(ForeignInput)
  }
  let program = @checked.effect_program_static_checked_computation(
    parent.prepared.candidate,
  )
  let bodies : Array[@publication.CapturedEffectDependencyBody] = []
  let seen : Map[String, String] = Map([])
  // The shared parser reserves its end position; actual cumulative bytes
  // remain funded by the original finite lookup reservation.
  let mut remaining = 2147483646
  fn append_measured(
    kind : String,
    cid : String,
    wire : String,
    wire_extent : (Int, Int)?,
  ) -> Unit raise GenericKeyedDependencyStop {
    let key = kind + "\u0000" + cid
    if seen.get(key) is Some(previous) {
      if previous != wire {
        raise GenericKeyedDependencyStop(Dependency(DuplicateIdentity))
      }
      return
    }
    if bodies.length() >= lookup.max_work {
      raise GenericKeyedDependencyStop(Dependency(EntryLimit))
    }
    if wire.length() > remaining {
      raise GenericKeyedDependencyStop(Dependency(ByteLimit))
    }
    let (body, bytes) = require_generic_keyed_dependency(
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
          state.completed
          .map(value => physical_equal(value, completed))
          .unwrap_or(false)
        },
        wire_extent~,
      ),
    )
    bodies.push(body)
    seen[key] = wire
    remaining -= bytes
  }
  fn append(
    kind : String,
    cid : String,
    wire : String,
  ) -> Unit raise GenericKeyedDependencyStop {
    append_measured(kind, cid, wire, None)
  }
  fn append_original(
    kind : String,
    cid : String,
    wire : String,
    usage : (Int, Int, Int)?,
    project : () -> Result[
      @publication.CapturedEffectDependencyBody,
      @publication.CapturedEffectDependencyIssue,
    ],
  ) -> Unit raise GenericKeyedDependencyStop {
    let key = kind + "\u0000" + cid
    if seen.get(key) is Some(previous) {
      if previous != wire {
        raise GenericKeyedDependencyStop(Dependency(DuplicateIdentity))
      }
      return
    }
    guard usage is Some((bytes, nodes, depth)) else {
      raise GenericKeyedDependencyStop(Dependency(InvalidBody))
    }
    if bodies.length() >= lookup.max_work {
      raise GenericKeyedDependencyStop(Dependency(EntryLimit))
    }
    if bytes > remaining {
      raise GenericKeyedDependencyStop(Dependency(ByteLimit))
    }
    if nodes < 1 || nodes > max_nodes || depth < 0 || depth > max_depth {
      raise GenericKeyedDependencyStop(Dependency(InvalidBody))
    }
    // The SAME original wire/value are borrowed. Only the typed edge
    // projection and member controls are constructed; no byte encoder,
    // canonical parser or hash runs a second time for these originals.
    if before_body is Some(prepare) && !prepare(0, nodes, depth) {
      raise GenericKeyedDependencyStop(ConstructionRefused)
    }
    if lookup.closed ||
      lookup.left.lookup_issue is Some(_) ||
      !state.completed
      .map(value => physical_equal(value, completed))
      .unwrap_or(false) {
      raise GenericKeyedDependencyStop(ForeignInput)
    }
    let body = require_generic_keyed_dependency(
      project().map_err(issue => {
        ClientEffectDependencyCaptureIssue::Dependency(issue)
      }),
    )
    if @publication.captured_effect_dependency_body_kind(body) != kind ||
      @publication.captured_effect_dependency_body_cid(body) != cid ||
      @publication.captured_effect_dependency_body_json(body) != wire {
      raise GenericKeyedDependencyStop(Dependency(InvalidBody))
    }
    bodies.push(body)
    seen[key] = wire
    remaining -= bytes
  }
  fn contract(
    kind : String,
    value : @publication.PublicationContract,
  ) -> Unit raise GenericKeyedDependencyStop {
    if @publication.publication_contract_wire_usage(value) is None {
      append(
        kind,
        @publication.publication_contract_identity(value),
        @publication.publication_contract_json(value),
      )
      return
    }
    append_original(
      kind,
      @publication.publication_contract_identity(value),
      @publication.publication_contract_json(value),
      @publication.publication_contract_wire_usage(value),
      () => {
        @publication.capture_publication_effect_dependency_body(
          kind, value, remaining, max_nodes, max_depth,
        )
      },
    )
  }
  fn evidence(
    kind : String,
    value : @publication.RunEvidenceValue,
  ) -> Unit raise GenericKeyedDependencyStop {
    if @publication.run_evidence_value_wire_usage(value) is None {
      append(
        kind,
        @publication.run_evidence_value_identity(value),
        @publication.run_evidence_value_json(value),
      )
      return
    }
    append_original(
      kind,
      @publication.run_evidence_value_identity(value),
      @publication.run_evidence_value_json(value),
      @publication.run_evidence_value_wire_usage(value),
      () => {
        @publication.capture_source_effect_dependency_body(
          value, remaining, max_nodes, max_depth,
        )
      },
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
    if lookup.closed || lookup.left.lookup_issue is Some(_) {
      return Err(ForeignBody)
    }
    if seen.get(key) is Some(previous) {
      return if previous == wire { Ok(()) } else { Err(ForeignBody) }
    }
    if bytes < 0 || bytes > remaining || bodies.length() >= lookup.max_work {
      return Err(BudgetExceeded)
    }
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
  ) -> Unit raise GenericKeyedDependencyStop {
    if before_body is Some(prepare) {
      let measure = try {
        let writer = @encode.measuring_writer(remaining, max_nodes, max_depth)
        produce(writer)
        @encode.finish_measurement_usage(writer)
      } catch {
        _ => raise GenericKeyedDependencyStop(Dependency(InvalidBody))
      }
      if !prepare(measure.0, measure.1, measure.2) {
        raise GenericKeyedDependencyStop(ConstructionRefused)
      }
      if lookup.closed || lookup.left.lookup_issue is Some(_) {
        raise GenericKeyedDependencyStop(ForeignInput)
      }
    }
    let (wire, bytes, nodes, _) = try {
      let writer = @encode.writer(remaining, max_nodes, max_depth)
      produce(writer)
      @encode.finish_text_usage(writer)
    } catch {
      _ => raise GenericKeyedDependencyStop(Dependency(InvalidBody))
    }
    append_measured(kind, cid, wire, Some((bytes, nodes)))
  }
  fn carrier(
    original : @carrier.Carrier,
    cid : String,
    schema_cid : String,
    schema_wire : String,
  ) -> Unit raise GenericKeyedDependencyStop {
    if cid == schema_cid {
      // PresenceRelation identifies the complete field map. The actual first
      // export already retained it, including conditional presence wrappers.
      append("relation_schema", cid, schema_wire)
      return
    }
    guard client_task_contract_source(original) is Some(ObjectRelation(row)) else {
      raise GenericKeyedDependencyStop(ForeignInput)
    }
    // ObjectRelation identifies the checked non-null row ValueContract, not
    // its Catalog envelope or field map. Serialize that same typed original
    // once for durable custody; do not recompile or hash the whole Graph.
    emit("carrier_contract", cid, writer => @contract.emit_checked(row, writer))
  }
  try {
    let source = state.source
    for
      (kind, value) in [
        ("acquisition_relation", source.relation),
        ("ordering_evidence", source.ordering),
        ("acquisition_scope", source.scope),
        ("result_retention_policy", source.retention),
        ("acquisition_relation", completed.relation),
        ("ordering_evidence", completed.ordering),
        ("acquisition_scope", completed.relation_scope),
        ("acquisition_scope", completed.scope),
        ("result_retention_policy", completed.retention),
        ("request_key_set", identity.keys),
      ] {
      contract(kind, value)
    }
    evidence("source_input_logical", source.logical)
    evidence("source_evidence", source.observation)
    evidence("source_input_logical", completed.observation.input)
    evidence("source_evidence", completed.observation.source)
    append(
      "request_values",
      source.request_cid,
      @encode.document_text(source.request),
    )
    append(
      "request_values",
      identity.static_request_cid,
      identity.static_request,
    )
    let left_usage = @query.captured_source_relation_dependency_usage(
      source.identity,
      captured,
    )
    append_measured(
      "relation_value",
      @query.captured_source_relation_logical_cid(source.identity),
      left_body,
      left_usage.map(usage => (usage.logical_bytes, usage.logical_nodes)),
    )
    append_measured(
      "relation_schema",
      @query.captured_source_relation_schema_cid(source.identity),
      left_schema,
      left_usage.map(usage => (usage.schema_bytes, usage.schema_nodes)),
    )
    let right_schema = @execution.completed_relation_export_schema_identity(
      right_receipt,
    )
    let (right_bytes, right_nodes, _) = @execution.logical_relation_usage(
      @execution.completed_relation_export_identity(right_receipt),
    )
    append_measured(
      "relation_value",
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(right_receipt),
      ),
      right_bodies.0,
      Some((right_bytes, right_nodes)),
    )
    let (right_schema_bytes, right_schema_nodes, _) = @execution.relation_schema_usage(
      right_schema,
    )
    append_measured(
      "relation_schema",
      @execution.relation_schema_cid(right_schema),
      right_bodies.1,
      Some((right_schema_bytes, right_schema_nodes)),
    )
    append(
      "lookup_barrier",
      component.barrier.logical_cid,
      @encode.document_text(component.barrier_body),
    )
    guard @lower.preparation_carrier_at(
        @lower.bound_preparation(parent.keyed.owner),
        component.original.fragments.left_target,
      )
      is Some(left_carrier) &&
      @pipeline.input_at(
        @lower.pipeline(@lower.bound_preparation(parent.keyed.owner)),
        @acquisition.keyed_join_input(parent.keyed.binding.join),
      )
      is Some((_, right_carrier)) else {
      return Err(ForeignInput)
    }
    carrier(
      left_carrier,
      component.left.output_contract_cid,
      @query.captured_source_relation_schema_cid(source.identity),
      left_schema,
    )
    carrier(
      right_carrier,
      component.barrier.output_contract_cid,
      @execution.relation_schema_cid(right_schema),
      right_bodies.1,
    )
    // Each original Request is DATA of the actual generic RowRun. Its opaque
    // attempt/capture remains borrowed on lookup.known; there is no archive,
    // Native call-slot, activation, attempt-event or adoption to manufacture.
    for (wire, _, original_history) in lookup.known {
      guard original_history is Some(history) &&
        history.wire_bytes > 0 &&
        history.wire_nodes > 0 &&
        physical_equal(history.request.left, lookup.left) else {
        return Err(ForeignInput)
      }
      let cid = match @sha.text_hex(wire) {
        Ok(value) => "sha256:" + value
        Err(_) => return Err(Dependency(InvalidBody))
      }
      append_measured(
        "request_values",
        cid,
        wire,
        Some((history.wire_bytes, history.wire_nodes)),
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
        let selected = require_generic_keyed_dependency(
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
            admitted_body=policy_receiver,
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
          lookup.max_work - references,
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
          cid == @publication.publication_contract_identity(state.retention) {
          contract(kind, state.retention)
        } else if [
            "source_contract", "source_view_contract", "data_policy", "request_schema",
            "carrier_schema", "schema_evidence", "capability_evidence",
          ].contains(kind) {
          let body = require_generic_keyed_dependency(
            capture_checked_client_catalog_dependency(
              program,
              client_composed_keyed_original_stage(original),
              kind,
              cid,
              remaining,
              max_nodes,
              max_depth,
              before_body,
            ).map_err(issue => Static(issue)),
          )
          require_generic_keyed_dependency(
            receive_policy_body(body.0, body.1).map_err(issue => Static(issue)),
          )
        }
      }
    }
    if lookup.closed ||
      lookup.left.lookup_issue is Some(_) ||
      !state.completed
      .map(value => physical_equal(value, completed))
      .unwrap_or(false) {
      return Err(ForeignInput)
    }
    Ok(bodies)
  } catch {
    GenericKeyedDependencyStop(issue) => Err(issue)
  }
}

///|
// Before-holding closure on the same lookup. The bounded shared metadata
// constructor accounts actual body bytes/nodes and its member controls; there
// is no total fixed-entry/file-byte cap or new allocation domain here.
fn prepare_client_effect_keyed_generic_dependencies(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  state : ClientEffectKeyedGenericState,
  completed : ClientEffectKeyedGenericCompletion,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard lookup.identifying &&
    !lookup.closed &&
    lookup.holding is None &&
    lookup.left.lookup_issue is None &&
    state.bodies is None &&
    state.completed is Some(same) &&
    physical_equal(same, completed) else {
    return Err(Assembly("foreign_generic_dependency_entry"))
  }
  // Begin before even the temporary receiver/callback controls. They do not
  // escape into the completed dependency bodies and cannot become a stale
  // retained baseline merely because the collector used them first.
  with_keyed_protocol_construction(
    lookup,
    1,
    64L + 2L * max_depth.to_int64(),
    max_nodes,
    max_depth,
    fn() {
      // New temporary receiver H1/R4 + Some H1/R1/W1; Catalog geometry
      // callback H1/R4 + Some H1/R1/W1 + three scalar Refs H3/W3;
      // returned body/byte tuple and Result H2/R2/W2. Total H9/R12/W7.
      // The same original reservation covers this peak before any closure/Ref.
      let controls = @execution.preparation_representation_cost({
        record_headers: 9L,
        reference_slots: 12L,
        scalar_words: 7L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }).unwrap()
      match
        keyed_lookup_body_grow(
          lookup,
          lookup.retained_bytes,
          lookup.execution_bytes,
          controls,
          None,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let primary : Ref[ClientKeyedRequestIssue?] = Ref(None)
      let before = (bytes : Int, nodes : Int, depth : Int) => {
        if primary.val is Some(_) ||
          bytes < 0 ||
          nodes < 0 ||
          depth < 0 ||
          bytes > 2147483647 - nodes ||
          lookup.closed ||
          lookup.left.lookup_issue is Some(_) {
          return false
        }
        if !charge_keyed_lookup_input_work(lookup, bytes + nodes) {
          primary.val = Some(LookupLimit("work"))
          return false
        }
        let capacity = @execution.execution_capacity_inventory(
          [
            { unit: ValueNodeSlots, count: nodes.to_int64(), copies: 3, },
            { unit: DecodedTextBytes, count: bytes.to_int64(), copies: 3, },
            { unit: CanonicalWireBytes, count: bytes.to_int64(), copies: 4, },
            // Existing shared capture-recovery member/Map/spare-array allowance.
            { unit: QuotedBytes, count: 4096L, copies: 1, },
          ],
          [{ unit: CursorRootSlots, count: depth.to_int64() + 1L, copies: 2, }],
          RetainedAlongsideExecution,
        )
        guard capacity is Some(capacity) else {
          primary.val = Some(Assembly("capacity_overflow"))
          return false
        }
        match
          keyed_lookup_body_grow(
            lookup,
            lookup.retained_bytes,
            lookup.execution_bytes,
            0L,
            Some(capacity),
          ) {
          Ok(_) => true
          Err(issue) => {
            primary.val = Some(issue)
            false
          }
        }
      }
      let bodies = match
        build_client_effect_keyed_generic_dependency_bodies(
          parent,
          lookup,
          state,
          completed,
          max_nodes,
          max_depth,
          Some(before),
        ) {
        Ok(value) => value
        Err(issue) => return Err(primary.val.unwrap_or(Dependency(issue)))
      }
      Ok(keyed_protocol_built(bodies, dependency_bodies=Some(bodies)))
    },
    bodies => {
      guard !lookup.closed &&
        lookup.left.lookup_issue is None &&
        state.completed is Some(same) &&
        physical_equal(same, completed) &&
        state.bodies is None else {
        return Err(Assembly("retired_generic_dependency_entry"))
      }
      state.bodies = Some(bodies)
      Ok(())
    },
  ).map(_ => ())
}
