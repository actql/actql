///|
/// Bounded canonical material only. This handle cannot issue evidence, publish
/// capture, or supply consumer input. Its owning connector separately verifies
/// the exact live attempt, retained values and issued-set identity.
struct QueryRecordArtifacts {
  requirement : QueryRequirement
  payload : QueryRecordPayload
  documents : Array[@encode.EncodedDocument]
  cids : Array[String]
  bytes : Int
  nodes : Int
}

///|
pub(all) enum QueryArtifactIssue {
  InvalidLimits
  InvalidRetainedLayout
  FieldLimit
  WorkLimit
  ForeignMaterial
  Encoding(@encode.EncodeFailure)
}

///|
pub fn build_query_record_artifacts(
  requirement : QueryRequirement,
  received : @execution.RowWireIdentity,
  output : @execution.RowWireIdentity,
  schema : @schema.Schema,
  issuer : String,
  attempt : String,
  limits : QueryMaterialLimits,
) -> Result[QueryRecordArtifacts, QueryArtifactIssue] {
  if limits.max_work < 0 ||
    limits.max_fields < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let budget : QueryMaterialBudget = {
    work: limits.max_work,
    bytes: limits.max_bytes,
    nodes: limits.max_nodes,
    depth: limits.max_depth,
  }
  let payload = match
    query_record_payload(requirement, received, output, schema, limits, budget) {
    Ok(payload) => payload
    Err(issue) =>
      return Err(
        match issue {
          InvalidRetainedLayout => InvalidRetainedLayout
          FieldLimit => FieldLimit
          WorkLimit => WorkLimit
          Encoding(issue) => Encoding(issue)
        },
      )
  }
  let documents = []
  let cids = []
  try {
    for role in [SourceValidation, Filter, Select] {
      let (document, cid) = query_record_document(budget, writer => {
        emit_query_record(payload, issuer, attempt, role, writer)
      })
      documents.push(document)
      cids.push(cid)
    }
    Ok({
      requirement,
      payload,
      documents,
      cids,
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
    })
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
pub fn query_record_artifact_at(
  value : QueryRecordArtifacts,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  guard value.documents.get(index) is Some(document) &&
    value.cids.get(index) is Some(cid) else {
    return None
  }
  Some((document, cid))
}

///|
pub fn query_record_artifact_usage(value : QueryRecordArtifacts) -> (Int, Int) {
  (value.bytes, value.nodes)
}

///|
/// Continues the artifact byte/node budget; it never resets it at capture.
/// Serialization does not establish live provenance or grant publication.
pub fn build_query_observation_artifact(
  value : QueryRecordArtifacts,
  limits : QueryEvidenceLimits,
) -> Result[(@encode.EncodedDocument, String, Int, Int), QueryArtifactIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if value.bytes > limits.max_bytes || value.nodes > limits.max_nodes {
    return Err(Encoding(@encode.OutputLimit))
  }
  let budget : QueryMaterialBudget = {
    work: 0,
    bytes: limits.max_bytes - value.bytes,
    nodes: limits.max_nodes - value.nodes,
    depth: limits.max_depth,
  }
  try {
    let material = value.requirement.material
    let request_cid = material_hash(budget, writer => {
      @encode.emit_document(writer, material.request)
    })
    if request_cid != material.request_cid {
      return Err(ForeignMaterial)
    }
    let (document, cid) = query_record_document(budget, writer => {
      emit_query_observation(
        value.requirement,
        value.payload,
        value.cids,
        writer,
      )
    })
    Ok(
      (
        document,
        cid,
        limits.max_bytes - budget.bytes,
        limits.max_nodes - budget.nodes,
      ),
    )
  } catch {
    issue => Err(Encoding(issue))
  }
}
