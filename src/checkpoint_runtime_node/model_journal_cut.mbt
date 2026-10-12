///|
fn model_journal_array(
  value : Json,
  key : String,
) -> Array[Json] raise ModelBridgeFailure {
  guard model_field(value, key) is Array(items) else {
    raise ModelBridgeFailed("InvalidModelJournalArray:" + key)
  }
  items
}

///|
/// Project the registered six-field cut data from actual journal originals.
/// Nominal Resource park/Store custody and journal COMMIT are separate issuers.
/// This pure codec never freezes a Ledger or grants restoration/send.
#export_name("modelOriginalJournalCutData")
pub fn model_original_journal_cut_data(facts_wire : String) -> String {
  try {
    let facts = model_parse(facts_wire)
    let identity = model_field(facts, "identity")
    let scope_cid = model_member(identity, "scopeCid")
    let scopes = model_journal_array(facts, "scopes")
    let mut selected : Json? = None
    for row in scopes {
      if model_member(row, "scope_cid") == scope_cid {
        if selected is Some(_) {
          raise ModelBridgeFailed("DuplicateModelJournalScope")
        }
        selected = Some(row)
      }
    }
    guard selected is Some(scope_row) else {
      raise ModelBridgeFailed("MissingModelJournalScope")
    }
    let request_wire = model_member(scope_row, "originals_json")
    let scope = model_scope_originals(request_wire)
    let request = model_parse(request_wire)
    let original = model_scope_fields(scope)
    for
      key in [
        "runId", "runDefinitionCid", "preparedInvocationCid", "scopeCid", "inputArtifactCid",
        "providerBindingCid", "taskIndex", "strategyRevision",
      ] {
      model_journal_match(identity, key, original[key])
    }
    let fixed = model_parse(model_member(request, "fixedInputReceiptWire"))
    let run = model_field(facts, "run")
    model_journal_match(run, "run_id", model_field(identity, "runId"))
    let version = model_integer(run, "version")
    if version < 1L {
      raise ModelBridgeFailed("InvalidModelJournalRunVersion")
    }
    let all_slots = model_journal_array(facts, "slots")
    let all_attempts = model_journal_array(facts, "attempts")
    let slots : Array[Json] = []
    for row in all_slots {
      if model_member(row, "scope_cid") != scope_cid {
        continue
      }
      let ordinal = slots.length()
      model_journal_match(row, "ordinal", Json::number(ordinal.to_double()))
      guard @publication.model_invocation_scope_slot(scope, ordinal)
        is Some((slot_cid, _, _)) else {
        raise ModelBridgeFailed("ExtraModelJournalSlot")
      }
      model_journal_match(row, "slot_cid", Json::string(slot_cid))
      let index = model_integer(row, "attempt_index")
      let state = model_member(row, "state")
      let mut last : Json? = None
      let mut count = 0L
      for attempt in all_attempts {
        if model_member(attempt, "scope_cid") != scope_cid ||
          model_integer(attempt, "ordinal") != ordinal.to_int64() {
          continue
        }
        count += 1L
        model_journal_match(
          attempt,
          "attempt_index",
          Json::number(count.to_double()),
        )
        if count == index {
          last = Some(attempt)
        }
      }
      if count != index || index < 0L {
        raise ModelBridgeFailed("InvalidModelJournalAttemptHistory")
      }
      let output : Map[String, Json] = {
        "ordinal": Json::number(ordinal.to_double()),
        "slot_cid": Json::string(slot_cid),
        "attempt_index": Json::number(index.to_double()),
        "state": Json::string(state),
        "entry_identity_cid": Json::null(),
        "settlement_identity_cid": Json::null(),
      }
      if index == 0L {
        if state != "Unsent" || last is Some(_) {
          raise ModelBridgeFailed("InvalidModelJournalUnsentSlot")
        }
      } else {
        guard last is Some(attempt) else {
          raise ModelBridgeFailed("MissingModelJournalAttempt")
        }
        model_journal_match(attempt, "state", Json::string(state))
        let entry = model_parse(model_member(attempt, "entry_json"))
        let originals = if model_member(entry, "provenance") == "deferred" &&
          model_member(scope_row, "registration_kind") == "immediate" {
          model_member(scope_row, "checkpoint_originals_json")
        } else {
          request_wire
        }
        let projected = model_parse(
          model_original_journal_identity(originals, attempt.stringify()),
        )
        model_journal_match(projected, "ok", Json::boolean(true))
        output["entry_identity_cid"] = model_field(projected, "entryCid")
        output["settlement_identity_cid"] = model_field(
          projected, "settlementCid",
        )
      }
      slots.push(Json::object(output))
    }
    if slots.length() !=
      @publication.model_invocation_scope_slots(scope).length() {
      raise ModelBridgeFailed("MissingModelJournalSlot")
    }
    let mut continuation = Json::null()
    let intent = model_field(facts, "currentIntent")
    if model_member(run, "status") == "resuming" {
      model_journal_match(intent, "run_id", model_field(identity, "runId"))
      model_journal_match(intent, "state", Json::string("claimed"))
      if model_integer(intent, "generation") < 1L {
        raise ModelBridgeFailed("InvalidModelJournalGeneration")
      }
      continuation = Json::object(
        model_journal_project(intent, [
          ("checkpoint_cid", "checkpoint_cid"),
          ("intent_id", "intent_id"),
          ("claimant", "claimant"),
          ("generation", "generation"),
          ("resolution_cid", "resolution_cid"),
        ]),
      )
    }
    ok({
      "cut": Json::object({
        "scope_cid": Json::string(scope_cid),
        "input_artifact_cid": model_field(identity, "inputArtifactCid"),
        // This is the original held fixed-input content identity, borrowed
        // from its selected receipt. No new generic receipt hash is invented.
        "fixed_input_receipt_cid": model_field(fixed, "cid"),
        "run_version": Json::number(version.to_double()),
        "continuation": continuation,
        "slots": Json::array(slots),
      }),
    })
  } catch {
    ModelBridgeFailed(issue) => fail_detail("InvalidModelJournalCut", issue)
  }
}
