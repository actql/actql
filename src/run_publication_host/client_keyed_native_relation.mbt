///|
// The completed right Relation and LookupEvidence reuse the original receipt,
// compiler boundary and request inventory. No row re-execution or Ref issuer.
fn build_native_keyed_lookup_relation_evidence(
  lookup : ClientKeyedLookupInput,
  component : ClientKeyedPlanComponent,
  request : ClientRequestIdentity,
  left : ClientKeyedNativeLeftRelation,
  identity : ClientKeyedLookupRequestIdentity,
  batch : @publication.PublicationContract,
  entries : Array[(ClientKeyedNativeActivation, ClientKeyedNativeCapturedPage)],
  accounting : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  recorded_at : String,
  issuer : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedNativeCompletion, ClientKeyedRequestIssue] {
  guard lookup.identity_receipt is Some(output) &&
    lookup.native_left_receipt is Some(input) &&
    lookup.native_read_profile is Some(profile) &&
    @publication.native_file_read_profile_contract_bindings(profile)
    is Some((source, _, _)) &&
    lookup.planned_requests is Some(requests) &&
    requests.length() <= lookup.rows else {
    return Err(Assembly("missing_native_lookup_relation_originals"))
  }
  let content = match
    @execution.completed_relation_export_content_reference_cids(
      input,
      max_nodes,
      lookup.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(CompletedIdentity(issue))
  }
  // This original export-current callback may retire the lookup. Everything
  // below is immutable checked metadata, not another current/row admission.
  if lookup.closed ||
    lookup.left.lookup_issue is Some(_) ||
    lookup.native_completion is Some(_) {
    return Err(Assembly("retired_native_lookup_relation"))
  }
  content.sort_by(@canonical_value.compare_utf16)
  let content_cids : Array[String] = []
  for cid in content {
    if content_cids.is_empty() || content_cids[content_cids.length() - 1] != cid {
      content_cids.push(cid)
    }
  }
  let policy = component.original.output_policy.cid
  let authority_scope_cid = client_request_authority_scope_cid(request)
  let (source_input, captured_source) = match
    build_keyed_lookup_source_observation(
      lookup,
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(output),
      ),
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(output),
      ),
      @execution.output_stream_identity(
        @execution.completed_relation_export_content(output),
      ).0,
      authority_scope_cid,
      recorded_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let retention = match
    @publication.issue_result_retention_for_data_policy(
      left.retention,
      policy,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(@publication.Contract(issue)))
  }
  let ordering = match
    @publication.issue_local_result_occurrence_evidence(
      component.original.output_contract_cid,
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(output),
      ),
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(output),
      ),
      component.barrier.logical_cid,
      [@publication.publication_contract_identity(left.artifact)],
      @publication.publication_contract_identity(identity.scope),
      policy,
      issuer,
      client_request_authority_scope_cid(request),
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Derivation(issue))
  }
  let relation_body = try {
    let w = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(w)
    @encode.key(w, "actual_completeness")
    @encode.string_value(w, "complete")
    @encode.key(w, "actual_row_count")
    @encode.number_value(
      w,
      @execution.completed_relation_export_measurement(output).row_count.to_double(),
    )
    @encode.key(w, "effective_data_policy_cid")
    @encode.string_value(w, policy)
    @encode.key(w, "effective_retention_policy_cid")
    @encode.string_value(
      w,
      @publication.publication_contract_identity(retention),
    )
    @encode.key(w, "logical_value_cid")
    @encode.string_value(
      w,
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(output),
      ),
    )
    @encode.key(w, "observation_scope_cid")
    @encode.string_value(
      w,
      @publication.publication_contract_identity(identity.scope),
    )
    @encode.key(w, "ordering_evidence_cid")
    @encode.string_value(
      w,
      @publication.publication_contract_identity(
        @publication.result_ordering_evidence_contract(ordering),
      ),
    )
    @encode.key(w, "producer_contract_cid")
    @encode.string_value(w, component.original.output_contract_cid)
    @encode.key(w, "provenance_evidence")
    @encode.begin_array(w)
    @encode.begin_object(w)
    @encode.key(w, "cid")
    @encode.string_value(w, @publication.publication_contract_identity(receipt))
    @encode.key(w, "kind")
    @encode.string_value(w, "attempt_receipt")
    @encode.end_object(w)
    @encode.begin_object(w)
    @encode.key(w, "cid")
    @encode.string_value(
      w,
      @publication.run_evidence_value_identity(captured_source),
    )
    @encode.key(w, "kind")
    @encode.string_value(w, "source")
    @encode.end_object(w)
    @encode.end_array(w)
    @encode.key(w, "relation_schema_cid")
    @encode.string_value(
      w,
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(output),
      ),
    )
    @encode.key(w, "version")
    @encode.string_value(w, "actql-acquisition-relation/0.1")
    @encode.end_object(w)
    @encode.finish(w)
  } catch {
    _ => return Err(Assembly("native_lookup_relation_encoding"))
  }
  let relation = match
    native_lookup_seal(
      "acquisition_relation", relation_body, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The checked LEFT target owns candidate coverage. Unknown *data-policy*
  // provenance (for example an unattested static Request value) does not say
  // that a physically complete Source capture omitted candidates. Its policy
  // CID remains unchanged; LIMIT/TopK still retains incomplete coverage.
  let extent = match component.original.policies.left {
    None => "unknown"
    Some(left) =>
      if @checked.publication_policy_slice_count(left) > 0 ||
        @checked.publication_policy_top_k_count(left) > 0 {
        "incomplete"
      } else {
        "complete"
      }
  }
  let evidence_body = try {
    let w = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(w)
    @encode.key(w, "attempt_receipt_cid")
    @encode.string_value(w, @publication.publication_contract_identity(receipt))
    @encode.key(w, "attempts")
    emit_native_completed_lookup_attempts(entries, w)
    @encode.key(w, "barrier_cid")
    @encode.string_value(w, component.barrier.logical_cid)
    @encode.key(w, "batch_plan_cid")
    @encode.string_value(w, @publication.publication_contract_identity(batch))
    @encode.key(w, "effective_output_data_policy_cid")
    @encode.string_value(w, policy)
    @encode.key(w, "effective_request_data_policy_cid")
    @encode.string_value(w, component.original.request_policy_cid)
    @encode.key(w, "excluded_null_key_row_count")
    @encode.number_value(w, (lookup.rows - requests.length()).to_double())
    @encode.key(w, "input_content_ref_cids")
    @encode.begin_array(w)
    for cid in content_cids {
      @encode.string_value(w, cid)
    }
    @encode.end_array(w)
    @encode.key(w, "input_relation_artifact_cid")
    @encode.string_value(
      w,
      @publication.publication_contract_identity(left.artifact),
    )
    @encode.key(w, "lookup_for_requested_keys")
    @encode.string_value(w, "complete")
    @encode.key(w, "observed_at")
    @encode.string_value(w, recorded_at)
    @encode.key(w, "request_input_data_policy_cids")
    @encode.begin_array(w)
    for
      index in 0..<@checked.effective_policy_source_count(
        component.original.policies.request,
      ) {
      @encode.string_value(
        w,
        @checked.effective_policy_source_at(
          component.original.policies.request,
          index,
        ).unwrap(),
      )
    }
    @encode.end_array(w)
    @encode.key(w, "request_key_set_cid")
    @encode.string_value(
      w,
      @publication.publication_contract_identity(identity.keys),
    )
    @encode.key(w, "source_request_egress_admission_cid")
    @encode.null_value(w)
    @encode.key(w, "source_view_contract_cid")
    @encode.string_value(w, source)
    @encode.key(w, "upstream_candidate_extent")
    @encode.string_value(w, extent)
    @encode.key(w, "validated_lookup_relation_cid")
    @encode.string_value(
      w,
      @publication.publication_contract_identity(relation),
    )
    @encode.key(w, "version")
    @encode.string_value(w, "actql-lookup-evidence/0.1")
    @encode.end_object(w)
    @encode.finish(w)
  } catch {
    _ => return Err(Assembly("native_lookup_evidence_encoding"))
  }
  native_lookup_seal(
    "lookup_evidence", evidence_body, max_bytes, max_nodes, max_depth,
  ).map(evidence => {
    accounting,
    receipt,
    relation,
    ordering,
    retention,
    evidence,
    input: source_input,
    source: captured_source,
    authority_scope_cid,
  })
}
