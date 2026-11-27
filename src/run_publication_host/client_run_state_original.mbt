///|
/// Private saved metadata, not execution authority, current availability,
/// control revision or a new versioned RunState. Preserve exact original bytes.
struct ClientRunStateOriginal {
  manifest : @publication.PublicationContract?
  status : @publication.RunOutcomeStatus
  state_wire : String
  wire : String
}

///|
/// The same validated immutable Manifest DATA retained by this original.
/// It supplies no Store fact, current availability or read authorization.
pub fn ClientRunStateOriginal::original_manifest(
  self : ClientRunStateOriginal,
) -> @publication.PublicationContract? {
  self.manifest
}

///|
pub fn ClientRunStateOriginal::state_wire(
  self : ClientRunStateOriginal,
) -> String {
  self.state_wire
}

///|
pub fn ClientRunStateOriginal::wire(self : ClientRunStateOriginal) -> String {
  self.wire
}

///|
/// The existing Core owns both closed Manifest and RunState validation. This
/// serializer cannot issue the Native opaque actual-Store observation.
pub fn prepare_client_run_state_original(
  definition : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  state_wire : String,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  match
    @publication.validate_original_succeeded_run_state(
      definition, manifest, state_wire, 65536, 8192, 64,
    ) {
    Ok(_) => ()
    Err(_) => return Err(CustodyLost)
  }
  encode_client_run_state_original(
    definition,
    Some(manifest),
    state_wire,
    @publication.Succeeded,
  )
}

///|
/// Metadata for an original unpublished Run. No successful Manifest, Result
/// read, dispatch or physical-stop authority is synthesized by this encoder.
pub fn prepare_client_unpublished_run_state_original(
  definition : @publication.PublicationContract,
  state_wire : String,
  model_failure? : @publication.BoundModelHttpFailure? = None,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  let locator = model_failure.map(failure => {
    let (attempt_cid, raw_cid) = @publication.model_http_failure_evidence_identity(
      failure,
    )
    ModelFailure(attempt_cid, raw_cid)
  })
  let bound = model_failure.map(failure => {
    let (attempt_cid, _) = @publication.model_http_failure_evidence_identity(
      failure,
    )
    (attempt_cid, failure)
  })
  let status = match
    @publication.validate_original_unpublished_run_state(
      definition,
      state_wire,
      65536,
      8192,
      64,
      model_failure=bound,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  encode_client_run_state_original(
    definition,
    None,
    state_wire,
    status,
    locator~,
  )
}

///|
/// Seal the selected Entry locator beside the public Unknown observation.
/// The original Native transaction authenticates Entry before this encoder.
pub fn prepare_client_dependent_model_unknown_run_state_original(
  definition : @publication.PublicationContract,
  state_wire : String,
  attempt_cid : String,
  entry_digest : String,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  guard valid_client_request_cid(attempt_cid) &&
    valid_client_request_cid(entry_digest) &&
    @publication.validate_original_unpublished_run_state(
      definition, state_wire, 65536, 8192, 64,
    )
    is Ok(@publication.NeedsReconciliation) else {
    return Err(CustodyLost)
  }
  encode_client_run_state_original(
    definition,
    None,
    state_wire,
    @publication.NeedsReconciliation,
    locator=Some(DependentModelUnknown(attempt_cid, entry_digest)),
  )
}

///|
// These locators are private observation metadata, never dispatch or replay
// permission. Only an authenticated current reader can resolve either role.
priv enum ClientRunStateModelLocator {
  ModelFailure(String, String)
  DependentModelUnknown(String, String)
}

///|
fn encode_client_run_state_original(
  definition : @publication.PublicationContract,
  manifest : @publication.PublicationContract?,
  state_wire : String,
  status : @publication.RunOutcomeStatus,
  locator? : ClientRunStateModelLocator? = None,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  try {
    let writer = @encode.writer(131072, 8, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "manifest")
    match manifest {
      Some(manifest) =>
        @encode.string_value(
          writer,
          @publication.publication_contract_json(manifest),
        )
      None => @encode.null_value(writer)
    }
    match locator {
      Some(ModelFailure(attempt_cid, raw_cid)) => {
        @encode.key(writer, "model_failure_attempt_cid")
        @encode.string_value(writer, attempt_cid)
        @encode.key(writer, "model_failure_raw_cid")
        @encode.string_value(writer, raw_cid)
      }
      Some(DependentModelUnknown(attempt_cid, entry_digest)) => {
        @encode.key(writer, "model_unknown_attempt_cid")
        @encode.string_value(writer, attempt_cid)
        @encode.key(writer, "model_unknown_entry_digest")
        @encode.string_value(writer, entry_digest)
      }
      None => ()
    }
    @encode.key(writer, "run_definition_cid")
    let definition_cid = @publication.publication_contract_identity(definition)
    @encode.string_value(writer, definition_cid)
    @encode.key(writer, "state")
    @encode.string_value(writer, state_wire)
    @encode.end_object(writer)
    Ok({ manifest, status, state_wire, wire: @encode.finish(writer), })
  } catch {
    _ => Err(CustodyLost)
  }
}

///|
/// Canonical saved DATA held under an authenticated Submission and Run.
/// A selected Model locator remains opaque until its Store proof is admitted.
pub struct ClientRetainedRunStateOriginal {
  definition : @publication.PublicationContract
  original : ClientRunStateOriginal
  priv model_locator : ClientRunStateModelLocator?
  observation : (Int64, String)?
}

///|
/// Join the canonical envelope to the observation of the original Run row.
/// Admission alone cannot expose a pending Model diagnostic.
pub fn admit_client_retained_run_state_original(
  definition : @publication.PublicationContract,
  wire : String,
  revision : Int64,
  key : String,
) -> Result[ClientRetainedRunStateOriginal, ClientJournalDecodingIssue] {
  let retained = match
    decode_client_run_state_original_body(definition, wire, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @publication.run_definition_run_id(definition) is Ok(run_id) &&
    @publication.prepare_run_state_observation(
      retained.original.state_wire,
      run_id,
      revision,
      65536,
      8192,
      64,
    )
    is Ok(observation) &&
    observation.key() == key &&
    observation.wire(revision).to_option() == Some(retained.original.state_wire) else {
    return Err(CustodyLost)
  }
  Ok({ ..retained, observation: Some((revision, key)), })
}

///|
/// Match the original observation again without rescanning either wire. This
/// comparison does not resolve a pending Model diagnostic.
pub fn ClientRetainedRunStateOriginal::matches(
  self : Self,
  definition : @publication.PublicationContract,
  wire : String,
  revision : Int64,
  key : String,
) -> Bool {
  @publication.publication_contract_identity(self.definition) ==
  @publication.publication_contract_identity(definition) &&
  self.original.wire == wire &&
  self.observation == Some((revision, key))
}

///|
/// A pending diagnostic requires the authorized original Store reader.
pub fn ClientRetainedRunStateOriginal::requires_model_proof(
  self : Self,
) -> Bool {
  self.model_locator is Some(_)
}

///|
/// Select the saved operation's resolver without exposing its Entry locator.
pub fn ClientRetainedRunStateOriginal::requires_dependent_model_unknown_proof(
  self : Self,
) -> Bool {
  self.model_locator is Some(DependentModelUnknown(_, _))
}

///|
/// Return the public original only after resolving the exact selected proof.
pub fn ClientRetainedRunStateOriginal::resolve(
  self : Self,
  resolve_model_failure? : ((String, String) -> @publication.BoundModelHttpFailure?)? = None,
  resolve_dependent_model_unknown? : ((String, String) -> Bool)? = None,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  match self.model_locator {
    None => Ok(self.original)
    Some(ModelFailure(attempt, raw)) => {
      guard resolve_model_failure is Some(resolve) &&
        resolve(attempt, raw) is Some(failure) &&
        @publication.model_http_failure_evidence_identity(failure) ==
        (attempt, raw) &&
        @publication.validate_original_unpublished_run_state(
          self.definition,
          self.original.state_wire,
          65536,
          8192,
          64,
          model_failure=Some((attempt, failure)),
        )
        is Ok(@publication.Failed) else {
        return Err(CustodyLost)
      }
      Ok(self.original)
    }
    Some(DependentModelUnknown(attempt, entry_digest)) => {
      guard self.observation is Some(_) &&
        resolve_dependent_model_unknown is Some(resolve) &&
        resolve(attempt, entry_digest) else {
        return Err(CustodyLost)
      }
      Ok(self.original)
    }
  }
}

///|
/// Read original metadata under the authenticated original Run. No recompile,
/// recapture, availability query, grant or permission is issued on restoration.
pub fn restore_client_run_state_original(
  definition : @publication.PublicationContract,
  wire : String,
  resolve_model_failure? : ((String, String) -> @publication.BoundModelHttpFailure?)? = None,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  decode_client_run_state_original_body(definition, wire, false).bind(retained => {
    retained.resolve(resolve_model_failure~)
  })
}

///|
/// Validate authentic retained metadata without making missing historical
/// observation counters into public state, permission or a restoration repair.
pub fn validate_client_historical_run_state_original(
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[Unit, ClientJournalDecodingIssue] {
  decode_client_run_state_original_body(definition, wire, true).map(_ => ())
}

///|
fn decode_client_run_state_original_body(
  definition : @publication.PublicationContract,
  wire : String,
  historical : Bool,
) -> Result[ClientRetainedRunStateOriginal, ClientJournalDecodingIssue] {
  let parsed = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 131072,
      max_nodes: 8,
      max_depth: 1,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard @decode.admit(parsed, {
      max_nodes: 8,
      max_depth: 1,
      max_string_bytes: 65536,
      max_total_string_bytes: 131072,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "manifest", "model_failure_attempt_cid", "model_failure_raw_cid", "model_unknown_attempt_cid",
      "model_unknown_entry_digest", "run_definition_cid", "state",
    ])
    is Ok(object) else {
    return Err(CustodyLost)
  }
  let text = key => {
    @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
  }
  guard text("state") is Some(state_wire) &&
    text("run_definition_cid") ==
    Some(@publication.publication_contract_identity(definition)) else {
    return Err(CustodyLost)
  }
  match
    (
      @decode.lookup(object, "model_failure_attempt_cid"),
      @decode.lookup(object, "model_failure_raw_cid"),
      @decode.lookup(object, "model_unknown_attempt_cid"),
      @decode.lookup(object, "model_unknown_entry_digest"),
    ) {
    (None, None, None, None) => ()
    (Some(attempt), Some(raw), None, None) => {
      guard !historical &&
        @decode.lookup(object, "manifest") is Some(value) &&
        @decode.is_null(value) &&
        @decode.text(attempt) is Ok(attempt_cid) &&
        @decode.text(raw) is Ok(raw_cid) &&
        valid_client_request_cid(attempt_cid) &&
        valid_client_request_cid(raw_cid) else {
        return Err(CustodyLost)
      }
      let locator = ModelFailure(attempt_cid, raw_cid)
      guard encode_client_run_state_original(
          definition,
          None,
          state_wire,
          @publication.Failed,
          locator=Some(locator),
        )
        is Ok(original) &&
        original.wire == wire else {
        return Err(CustodyLost)
      }
      return Ok({
        definition,
        original,
        model_locator: Some(locator),
        observation: None,
      })
    }
    (None, None, Some(attempt), Some(entry)) => {
      guard !historical &&
        @decode.lookup(object, "manifest") is Some(value) &&
        @decode.is_null(value) &&
        @decode.text(attempt) is Ok(attempt_cid) &&
        @decode.text(entry) is Ok(entry_digest) &&
        prepare_client_dependent_model_unknown_run_state_original(
          definition, state_wire, attempt_cid, entry_digest,
        )
        is Ok(original) &&
        original.wire == wire else {
        return Err(CustodyLost)
      }
      return Ok({
        definition,
        original,
        model_locator: Some(DependentModelUnknown(attempt_cid, entry_digest)),
        observation: None,
      })
    }
    _ => return Err(CustodyLost)
  }
  if @decode.lookup(object, "manifest") is Some(value) && @decode.is_null(value) {
    // New unpublished metadata always requires its real saved observation
    // revision. Historical absence is not repaired to an executable zero.
    return match
      prepare_client_unpublished_run_state_original(definition, state_wire) {
      Ok(original) if original.wire == wire =>
        Ok({ definition, original, model_locator: None, observation: None, })
      _ => Err(CustodyLost)
    }
  }
  guard text("manifest") is Some(manifest_wire) else { return Err(CustodyLost) }
  let manifest = match
    @publication.admit_publication_contract(
      "result_manifest", manifest_wire, 65536, 8192, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if historical {
    if @publication.validate_historical_original_succeeded_run_state(
        definition, manifest, state_wire, 65536, 8192, 64,
      )
      is Err(_) {
      return Err(CustodyLost)
    }
    return match
      encode_client_run_state_original(
        definition,
        Some(manifest),
        state_wire,
        @publication.Succeeded,
      ) {
      Ok(original) if original.wire == wire =>
        Ok({ definition, original, model_locator: None, observation: None, })
      _ => Err(CustodyLost)
    }
  }
  match prepare_client_run_state_original(definition, manifest, state_wire) {
    Ok(original) if original.wire == wire =>
      Ok({ definition, original, model_locator: None, observation: None, })
    _ => Err(CustodyLost)
  }
}
