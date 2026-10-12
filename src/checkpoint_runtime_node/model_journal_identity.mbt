///|
/// A closed projection of original journal data, not a custody/currentness
/// issuer. The installed adapter selects rows through its original opaque
/// journal observation; arbitrary imported bytes confer no journal authority.
fn model_journal_closed(
  value : Json,
  required : Array[String],
  optional? : Array[String] = [],
) -> Unit raise ModelBridgeFailure {
  guard value is Object(fields) else {
    raise ModelBridgeFailed("InvalidModelJournalObject")
  }
  for key in required {
    if !fields.contains(key) {
      raise ModelBridgeFailed("MissingModelJournalField:" + key)
    }
  }
  for key in fields.keys() {
    if !required.contains(key) && !optional.contains(key) {
      raise ModelBridgeFailed("UnknownModelJournalField:" + key)
    }
  }
}

///|
fn model_journal_project(
  value : Json,
  fields : Array[(String, String)],
) -> Map[String, Json] raise ModelBridgeFailure {
  let result : Map[String, Json] = Map([])
  for (original, target) in fields {
    result[target] = model_field(value, original)
  }
  result
}

///|
fn model_journal_match(
  value : Json,
  field : String,
  expected : Json,
) -> Unit raise ModelBridgeFailure {
  if model_field(value, field) != expected {
    raise ModelBridgeFailed("ModelJournalBindingMismatch:" + field)
  }
}

///|
fn model_journal_seal(
  name : String,
  fields : Map[String, Json],
) -> @publication.RunEvidenceValue raise ModelBridgeFailure {
  let bounds = limits()
  match
    @publication.seal_run_evidence_value(
      name,
      Json::object(fields).stringify(),
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => raise ModelBridgeFailed(@debug.to_string(issue))
  }
}

///|
fn model_journal_saved_reference(value : Json) -> Json raise ModelBridgeFailure {
  model_journal_closed(value, ["cid", "holdingCid"])
  Json::object(
    model_journal_project(value, [("cid", "cid"), ("holdingCid", "holding_cid")]),
  )
}

///|
/// Canonical data projection after exact original Run/scope/Slot/attempt and
/// authority linkage. Historical admission is deliberately independent of
/// current permission, cancellation or expiry. No Store, park or send effect.
#export_name("modelOriginalJournalIdentity")
pub fn model_original_journal_identity(
  request_wire : String,
  row_wire : String,
) -> String {
  try {
    let scope = model_scope_originals(request_wire)
    let row = model_parse(row_wire)
    model_journal_closed(row, [
      "scope_cid", "ordinal", "attempt_index", "attempt_cid", "entry_json", "attempt_wire",
      "authority_wire", "state", "settlement_json", "entered_at", "settled_at",
    ])
    let entry = model_parse(model_member(row, "entry_json"))
    let provenance = model_member(entry, "provenance")
    let base = [
      "runId", "runDefinitionCid", "preparedInvocationCid", "scopeCid", "providerBindingCid",
      "inputArtifactCid", "taskIndex", "strategyRevision", "provenance", "ordinal",
      "slotCid", "attemptIndex", "attemptCid", "admittedAt", "modelGrantExpiresAt",
      "admission",
    ]
    let branch = match provenance {
      "immediate" => ["authorityCid"]
      "deferred" =>
        ["checkpointCid", "intentId", "claimant", "generation", "resolutionCid"]
      _ => raise ModelBridgeFailed("InvalidModelJournalProvenance")
    }
    model_journal_closed(entry, base + branch)
    let (run_id, definition_cid, _) = @publication.model_invocation_scope_run(
      scope,
    )
    let boundary = @publication.model_invocation_scope_boundary(scope)
    let originals : Map[String, Json] = {
      "runId": Json::string(run_id),
      "runDefinitionCid": Json::string(definition_cid),
      "preparedInvocationCid": Json::string(
        @publication.model_invocation_scope_prepared_cid(scope),
      ),
      "scopeCid": Json::string(@publication.model_invocation_scope_cid(scope)),
      "providerBindingCid": Json::string(
        @publication.model_invocation_scope_provider_cid(scope),
      ),
      "inputArtifactCid": Json::string(
        @publication.model_invocation_scope_input_cid(scope),
      ),
      "taskIndex": Json::number(boundary.task_index.to_double()),
      "strategyRevision": Json::number(boundary.strategy_revision.to_double()),
    }
    for
      key in [
        "runId", "runDefinitionCid", "preparedInvocationCid", "scopeCid", "providerBindingCid",
        "inputArtifactCid", "taskIndex", "strategyRevision",
      ] {
      model_journal_match(entry, key, originals[key])
    }
    let ordinal = model_integer(entry, "ordinal")
    if ordinal < 0L ||
      ordinal >=
      @publication.model_invocation_scope_slots(scope).length().to_int64() {
      raise ModelBridgeFailed("InvalidModelJournalOrdinal")
    }
    let (slot_cid, _, _) = @publication.model_invocation_scope_slot(
      scope,
      ordinal.to_int(),
    ).unwrap()
    model_journal_match(entry, "slotCid", Json::string(slot_cid))
    let index = model_integer(entry, "attemptIndex")
    let attempt = model_evidence(
      "model_call_attempt",
      model_member(row, "attempt_wire"),
    )
    let authority = model_evidence(
      "model_dispatch_authority",
      model_member(row, "authority_wire"),
    )
    if @publication.check_model_invocation_attempt(
        scope,
        ordinal.to_int(),
        attempt,
        authority,
        index,
      )
      is Err(_) {
      raise ModelBridgeFailed("InvalidModelJournalAttempt")
    }
    let authority_cid = @publication.run_evidence_value_identity(authority)
    model_journal_match(
      entry,
      "attemptCid",
      Json::string(@publication.run_evidence_value_identity(attempt)),
    )
    for
      (row_key, entry_key) in [
        ("scope_cid", "scopeCid"),
        ("ordinal", "ordinal"),
        ("attempt_index", "attemptIndex"),
        ("attempt_cid", "attemptCid"),
        ("entered_at", "admittedAt"),
      ] {
      model_journal_match(row, row_key, model_field(entry, entry_key))
    }
    let admission = model_field(entry, "admission")
    for key in ["provenance", "runId", "admittedAt", "modelGrantExpiresAt"] {
      model_journal_match(admission, key, model_field(entry, key))
    }
    model_journal_match(admission, "kind", Json::string("model_invocation"))
    model_journal_match(
      admission,
      "requiredArtifactCid",
      model_field(entry, "scopeCid"),
    )
    let fields = model_journal_project(entry, [
      ("runId", "run_id"),
      ("runDefinitionCid", "run_definition_cid"),
      ("preparedInvocationCid", "prepared_invocation_cid"),
      ("scopeCid", "scope_cid"),
      ("providerBindingCid", "provider_binding_cid"),
      ("inputArtifactCid", "input_artifact_cid"),
      ("taskIndex", "task_index"),
      ("strategyRevision", "strategy_revision"),
      ("ordinal", "ordinal"),
      ("slotCid", "slot_cid"),
      ("attemptIndex", "attempt_index"),
      ("attemptCid", "attempt_cid"),
      ("admittedAt", "admitted_at"),
      ("modelGrantExpiresAt", "model_grant_expires_at"),
      ("provenance", "provenance"),
    ])
    fields["version"] = Json::string("actql-model-journal-entry/0.1")
    fields["dispatch_authority_cid"] = Json::string(authority_cid)
    fields["immediate"] = Json::null()
    fields["deferred"] = Json::null()
    if provenance == "immediate" {
      model_journal_closed(
        admission,
        [
          "kind", "provenance", "runId", "requiredArtifactCid", "authorityCid", "admittedAt",
          "runValidUntil", "dispatchValidUntil", "modelGrantExpiresAt",
        ],
        optional=["parentResumeFence"],
      )
      for value in [entry, admission] {
        model_journal_match(value, "authorityCid", Json::string(authority_cid))
      }
      model_journal_match(
        admission,
        "runValidUntil",
        Json::string(@publication.model_invocation_scope_valid_until(scope)),
      )
      let immediate = model_journal_project(admission, [
        ("runValidUntil", "run_valid_until"),
        ("dispatchValidUntil", "dispatch_valid_until"),
      ])
      immediate["parent_resume_fence"] = Json::null()
      guard admission is Object(admission_fields) else {
        raise ModelBridgeFailed("InvalidModelJournalAdmission")
      }
      if admission_fields.get("parentResumeFence") is Some(parent) {
        model_journal_closed(parent, [
          "checkpointCid", "intentId", "claimant", "generation",
        ])
        immediate["parent_resume_fence"] = Json::object(
          model_journal_project(parent, [
            ("checkpointCid", "checkpoint_cid"),
            ("intentId", "intent_id"),
            ("claimant", "claimant"),
            ("generation", "generation"),
          ]),
        )
      }
      fields["immediate"] = Json::object(immediate)
    } else {
      let (bound, _) = model_call_set(request_wire)
      // Reuse the original checked Checkpoint binding, not a synthetic approval.
      if @publication.model_invocation_scope_cid(bound) !=
        @publication.model_invocation_scope_cid(scope) {
        raise ModelBridgeFailed("ModelJournalScopeMismatch")
      }
      let request = model_parse(request_wire)
      let checkpoint_body = model_parse(model_member(request, "checkpointWire"))
      model_journal_match(
        entry,
        "checkpointCid",
        model_field(checkpoint_body, "checkpoint_cid"),
      )
      // The original binding proves data linkage, not approval authentication.
      model_journal_closed(admission, [
        "kind", "provenance", "runId", "requiredArtifactCid", "checkpointCid", "intentId",
        "claimant", "generation", "resolutionCid", "verifiedResolutionCid", "leaseExpiresMs",
        "prepareAttemptId", "decisionSubjectCid", "requestedClaims", "configurationCid",
        "observedClaims", "authority", "approvalExpiresAt", "admittedAt", "modelGrantExpiresAt",
      ])
      for key in branch {
        model_journal_match(admission, key, model_field(entry, key))
      }
      fields["deferred"] = Json::object(
        model_journal_project(admission, [
          ("checkpointCid", "checkpoint_cid"),
          ("intentId", "intent_id"),
          ("claimant", "claimant"),
          ("generation", "generation"),
          ("resolutionCid", "resolution_cid"),
          ("verifiedResolutionCid", "verified_resolution_cid"),
          ("leaseExpiresMs", "lease_expires_ms"),
          ("prepareAttemptId", "prepare_attempt_id"),
          ("kind", "kind"),
          ("requiredArtifactCid", "required_artifact_cid"),
          ("decisionSubjectCid", "decision_subject_cid"),
          ("requestedClaims", "requested_claims"),
          ("configurationCid", "configuration_cid"),
          ("observedClaims", "observed_claims"),
          ("authority", "authority"),
          ("approvalExpiresAt", "approval_expires_at"),
        ]),
      )
    }
    let entry_identity = model_journal_seal("model_journal_entry", fields)
    let response : Map[String, Json] = {
      "entryWire": Json::string(
        @publication.run_evidence_value_json(entry_identity),
      ),
      "entryCid": Json::string(
        @publication.run_evidence_value_identity(entry_identity),
      ),
      "settlementWire": Json::null(),
      "settlementCid": Json::null(),
    }
    let state = model_member(row, "state")
    if state == "EnteredUnknown" {
      model_journal_match(row, "settlement_json", Json::string(""))
      model_journal_match(row, "settled_at", Json::string(""))
    } else {
      let saved = model_parse(model_member(row, "settlement_json"))
      model_journal_closed(saved, [
        "entry", "state", "durable", "evidence", "retryAllowed",
      ])
      model_journal_match(saved, "state", Json::string(state))
      let saved_entry = model_field(saved, "entry")
      let saved_keys = [
          "runId", "runDefinitionCid", "preparedInvocationCid", "scopeCid", "providerBindingCid",
          "inputArtifactCid", "taskIndex", "strategyRevision", "ordinal", "slotCid",
          "attemptIndex", "attemptCid",
        ] +
        (if provenance == "immediate" {
          ["provenance", "authorityCid"]
        } else {
          branch
        })
      model_journal_closed(saved_entry, saved_keys)
      for key in saved_keys {
        model_journal_match(saved_entry, key, model_field(entry, key))
      }
      let evidence = model_field(saved, "evidence")
      let roles = [
        "model_call_attempt", "model_dispatch_authority", "model_attempt_accounting",
        "model_attempt_outcome",
      ]
      model_journal_closed(evidence, roles, optional=[
        "model_slot_capture", "model_capture_bundle", "terminalFailure",
      ])
      let refs : Map[String, Json] = Map([])
      for role in roles {
        refs[role] = model_journal_saved_reference(model_field(evidence, role))
      }
      model_journal_match(
        model_field(evidence, "model_call_attempt"),
        "cid",
        model_field(entry, "attemptCid"),
      )
      model_journal_match(
        model_field(evidence, "model_dispatch_authority"),
        "cid",
        Json::string(authority_cid),
      )
      guard evidence is Object(evidence_fields) else {
        raise ModelBridgeFailed("InvalidModelJournalSettlement")
      }
      for role in ["model_slot_capture", "model_capture_bundle"] {
        refs[role] = match evidence_fields.get(role) {
          Some(reference) => model_journal_saved_reference(reference)
          None => Json::null()
        }
      }
      refs["terminal_failure"] = evidence_fields
        .get("terminalFailure")
        .unwrap_or(Json::null())
      let settlement = model_journal_seal("model_journal_settlement", {
        "version": Json::string("actql-model-journal-settlement/0.1"),
        "entry_identity_cid": Json::string(
          @publication.run_evidence_value_identity(entry_identity),
        ),
        "state": model_field(saved, "state"),
        "durable": model_field(saved, "durable"),
        "retry_allowed": model_field(saved, "retryAllowed"),
        "settled_at": model_field(row, "settled_at"),
        "evidence": Json::object(refs),
      })
      response["settlementWire"] = Json::string(
        @publication.run_evidence_value_json(settlement),
      )
      response["settlementCid"] = Json::string(
        @publication.run_evidence_value_identity(settlement),
      )
    }
    ok(response)
  } catch {
    ModelBridgeFailed(issue) =>
      fail_detail("InvalidModelJournalOriginal", issue)
  }
}
