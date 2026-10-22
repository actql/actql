///|
/// The existing Checkpoint codec prepares and checks the original unsigned
/// Resolution. This opaque value is neither a durable Checkpoint witness nor
/// signing authority, a use claim, private key or accepted approval.
struct ClientLocalCheckpointProof {
  original : @checkpoint.PreparedResolutionProof
}

///|
pub(all) enum ClientLocalCheckpointProofIssue {
  Checkpoint(@checkpoint.CheckpointIssue)
  Resolution(@checkpoint.ResolutionIssue)
  MissingRequest
  SubmissionReference
  CheckpointBinding(String)
  CheckpointUnit
  ForeignOriginal
} derive(Eq, Debug)

///|
pub fn prepare_client_local_checkpoint_proof(
  checkpoint_wire : String,
  unsigned_resolution_wire : String,
) -> Result[ClientLocalCheckpointProof, ClientLocalCheckpointProofIssue] {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 65536,
    max_depth: 64,
  }
  let checkpoint = match
    @checkpoint.admit_checkpoint_wire(checkpoint_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(Checkpoint(issue))
  }
  match
    @checkpoint.prepare_resolution_proof(
      checkpoint, unsigned_resolution_wire, limits,
    ) {
    Ok(original) => Ok({ original, })
    Err(issue) => Err(Resolution(issue))
  }
}

///|
/// Project only the explicit unit of the same admitted Run materials and its
/// original Submission identity. Durable authentication and current custody
/// remain with the Host/Journal; these identities cannot establish them.
pub fn client_local_checkpoint_effect_subject(
  materials : ClientEffectRunMaterials,
  reference_wire : String,
  checkpoint_wire : String,
) -> Result[(String, String), ClientLocalCheckpointProofIssue] {
  guard materials.request is Some(request) else { return Err(MissingRequest) }
  let reference = match
    admit_client_submission_reference_record(reference_wire) {
    Ok(value) => value
    Err(_) => return Err(SubmissionReference)
  }
  if !client_submission_reference_matches_request(reference, request) {
    return Err(ForeignOriginal)
  }
  let checkpoint = match
    admit_client_effect_review_checkpoint_binding(
      materials.allowed,
      materials.run_definition,
      checkpoint_wire,
      { max_wire_bytes: 1048576, max_nodes: 65536, max_depth: 64, },
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        CheckpointBinding(
          match issue {
            Run(_) => "run"
            Checkpoint(_) => "wire"
            ForeignSubject => "subject"
            UnsupportedReview => "review"
            OriginalLifetime => "lifetime"
          },
        ),
      )
  }
  let unit = match
    client_effect_review_checkpoint_unit_definition_cid(
      materials.allowed,
      materials.run_definition,
      checkpoint,
    ) {
    Ok(value) => value
    Err(_) => return Err(CheckpointUnit)
  }
  Ok((client_submission_reference_record_request_id(reference), unit))
}

///|
pub fn ClientLocalCheckpointProof::preimage(
  self : ClientLocalCheckpointProof,
) -> String {
  self.original.preimage()
}

///|
pub fn ClientLocalCheckpointProof::actor(
  self : ClientLocalCheckpointProof,
) -> String {
  self.original.actor()
}

///|
pub fn ClientLocalCheckpointProof::seal(
  self : ClientLocalCheckpointProof,
  key_id : String,
  signature : String,
) -> Result[String, ClientLocalCheckpointProofIssue] {
  match
    @checkpoint.seal_prepared_resolution_proof(self.original, key_id, signature) {
    Ok(wire) => Ok(wire)
    Err(issue) => Err(Resolution(issue))
  }
}
