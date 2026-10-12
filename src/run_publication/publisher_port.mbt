///|
/// These are the original request's references, not published policy bodies or
/// a current authorization. The request preimage binds both external CIDs.
pub(all) struct PublicationRequestContext {
  namespace_id : String
  authority_scope_cid : String
  run_definition_cid : String
  publication_policy_cid : String
  publication_target_cid : String
  publication_request_cid : String
} derive(Eq, Debug)

///|
pub(all) enum PublicationPublisherStage {
  Request
  Commit
  ReturnCommitted
} derive(Eq, Debug)

///|
/// The same six facts as the existing Native publication authority callback.
/// Policy and target remain bound by publication_request_cid, not extra facts.
pub(all) struct PublicationPublisherAuthorization {
  stage : String
  namespace_id : String
  authority_scope_cid : String
  run_definition_cid : String
  publication_request_cid : String
  public_index_entry_cid : String?
} derive(Eq, Debug)

///|
pub(all) enum PublicationPublisherIssue {
  WrongContract
  ReferenceMismatch
  ForeignRequest
  InvalidStore
  NotCurrent
  AccessDenied
} derive(Eq, Debug)

///|
/// A trusted Host callback port, not a new authorization or publication Owner.
/// Installation must use the Host's independent publisher authority; neither
/// SDK booleans nor Run/Source access implement authorize.
struct PublicationPublisherPort {
  request : PublicationContract
  attempt : PublicationContract
  store_authority_cid : String
  require_current : () -> Bool
  authorize : (PublicationPublisherAuthorization) -> Bool
}

///|
pub fn project_publication_request_context(
  request : PublicationContract,
) -> Result[PublicationRequestContext, PublicationPublisherIssue] {
  if request.name != "publication_request" {
    return Err(WrongContract)
  }
  guard contract_string(request, "namespace_id") is Some(namespace_id) &&
    contract_string(request, "authority_scope_cid") is Some(authority_scope_cid) &&
    contract_string(request, "run_definition_cid") is Some(run_definition_cid) &&
    contract_string(request, "publication_policy_cid")
    is Some(publication_policy_cid) &&
    contract_string(request, "publication_target_cid")
    is Some(publication_target_cid) else {
    return Err(ReferenceMismatch)
  }
  Ok({
    namespace_id,
    authority_scope_cid,
    run_definition_cid,
    publication_policy_cid,
    publication_target_cid,
    publication_request_cid: request.identity,
  })
}

///|
pub fn install_publication_publisher_port(
  request : PublicationContract,
  attempt : PublicationContract,
  store_authority_cid : String,
  require_current : () -> Bool,
  authorize : (PublicationPublisherAuthorization) -> Bool,
) -> Result[PublicationPublisherPort, PublicationPublisherIssue] {
  let context = match project_publication_request_context(request) {
    Ok(context) => context
    Err(issue) => return Err(issue)
  }
  if attempt.name != "publication_attempt" {
    return Err(WrongContract)
  }
  if contract_string(attempt, "publication_request_cid") !=
    Some(request.identity) ||
    contract_string(attempt, "run_definition_cid") !=
    Some(context.run_definition_cid) {
    return Err(ReferenceMismatch)
  }
  if !valid_contract_cid(store_authority_cid) {
    return Err(InvalidStore)
  }
  if !require_current() {
    return Err(NotCurrent)
  }
  Ok({ request, attempt, store_authority_cid, require_current, authorize, })
}

///|
/// Inspect only scope before invoking the authority. Full-chain validation,
/// physical payload verification and Store commit still belong to their Owners.
fn publication_publisher_fact(
  request : PublicationContract,
  stage : PublicationPublisherStage,
  index : PublicationContract?,
) -> Result[PublicationPublisherAuthorization, PublicationPublisherIssue] {
  let context = match project_publication_request_context(request) {
    Ok(context) => context
    Err(issue) => return Err(issue)
  }
  let (stage_name, index_cid) = match (stage, index) {
    (Request, None) => ("request", None)
    (Commit, Some(index)) | (ReturnCommitted, Some(index)) => {
      if index.name != "public_index_entry" {
        return Err(WrongContract)
      }
      if contract_string(index, "namespace_id") != Some(context.namespace_id) ||
        contract_string(index, "authority_scope_cid") !=
        Some(context.authority_scope_cid) ||
        contract_string(index, "run_definition_cid") !=
        Some(context.run_definition_cid) ||
        contract_string(index, "publication_request_cid") !=
        Some(request.identity) {
        return Err(ReferenceMismatch)
      }
      (
        if stage == Commit {
          "commit"
        } else {
          "return_committed"
        },
        Some(index.identity),
      )
    }
    _ => return Err(ReferenceMismatch)
  }
  Ok({
    stage: stage_name,
    namespace_id: context.namespace_id,
    authority_scope_cid: context.authority_scope_cid,
    run_definition_cid: context.run_definition_cid,
    publication_request_cid: request.identity,
    public_index_entry_cid: index_cid,
  })
}

///|
/// Re-evaluate every stage. A successful earlier callback never caches a grant.
/// Failure leaves the original attempt, Result and payload responsibility intact.
pub fn PublicationPublisherPort::check(
  self : PublicationPublisherPort,
  request : PublicationContract,
  attempt : PublicationContract,
  store_authority_cid : String,
  stage : PublicationPublisherStage,
  index : PublicationContract?,
) -> Result[Unit, PublicationPublisherIssue] {
  if !physical_equal(self.request, request) ||
    !physical_equal(self.attempt, attempt) {
    return Err(ForeignRequest)
  }
  if self.store_authority_cid != store_authority_cid {
    return Err(InvalidStore)
  }
  let fact = match publication_publisher_fact(request, stage, index) {
    Ok(fact) => fact
    Err(issue) => return Err(issue)
  }
  if stage == Commit {
    guard index is Some(index) &&
      contract_string(index, "publication_attempt_cid") ==
      Some(attempt.identity) else {
      return Err(ReferenceMismatch)
    }
  }
  if !(self.require_current)() {
    return Err(NotCurrent)
  }
  let allowed = (self.authorize)(fact)
  if !(self.require_current)() {
    return Err(NotCurrent)
  }
  if allowed {
    Ok(())
  } else {
    Err(AccessDenied)
  }
}
