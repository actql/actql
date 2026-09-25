///|
/// The execution boundary a delegated decision guards.
pub(all) enum DecisionBoundary {
  Preparation
  Acquisition
  Activation
  Transfer
  EffectCommit
} derive(Eq, Debug)

///|
/// The exact subject a Host answer must echo. CIDs are supplied by the
/// caller: `configuration_cid` identifies the admitted configuration,
/// `subject_cid` the sealed decision subject (review projection, run unit,
/// plan and preview, ...) and `context_cid` the authorization context.
pub(all) struct DecisionSubject {
  account_id : String
  configuration_cid : String
  entry_id : String
  tuple : AccessTuple
  boundary : DecisionBoundary
  subject_cid : String
  context_cid : String
} derive(Eq, Debug)

///|
/// A bound delegated decision request. Only `prepare_decision_request`
/// creates it, and only from a `DelegatedMatch`.
struct DecisionRequest {
  subject : DecisionSubject
  answering_authorities : Array[String]
  required_claims : Array[String]
} derive(Eq, Debug)

///|
pub fn DecisionRequest::subject(self : DecisionRequest) -> DecisionSubject {
  self.subject
}

///|
/// Host-supplied authenticated principals allowed to permit or reject, in
/// ascending order.
pub fn DecisionRequest::answering_authorities(
  self : DecisionRequest,
) -> Array[String] {
  self.answering_authorities.copy()
}

///|
/// Host-declared claims a permit must satisfy, in ascending order.
pub fn DecisionRequest::required_claims(
  self : DecisionRequest,
) -> Array[String] {
  self.required_claims.copy()
}

///|
pub(all) enum RequestIssue {
  InvalidConfigurationCid
  InvalidSubjectCid
  InvalidContextCid
  NoAnsweringAuthority
  InvalidAnsweringAuthority
  DuplicateAnsweringAuthority(String)
  InvalidRequiredClaim
  DuplicateRequiredClaim(String)
} derive(Eq, Debug)

///|
fn sorted_unique_names(
  values : Array[String],
  invalid : RequestIssue,
  duplicate : (String) -> RequestIssue,
) -> Result[Array[String], RequestIssue] {
  if values.length() > MAX_SELECTOR_VALUES {
    return Err(invalid)
  }
  for value in values {
    if !valid_name(value) {
      return Err(invalid)
    }
  }
  let sorted = sort_names(values)
  for index in 1..<sorted.length() {
    if sorted[index - 1] == sorted[index] {
      return Err(duplicate(sorted[index]))
    }
  }
  Ok(sorted)
}

///|
/// Bind a delegated match to its boundary, sealed subject and context. The
/// answering authority set and optional required claims (for example
/// `partial_application_accepted`) are Host-declared; the core does not
/// model the Host's business procedure.
pub fn prepare_decision_request(
  delegated : DelegatedMatch,
  configuration_cid~ : String,
  boundary~ : DecisionBoundary,
  subject_cid~ : String,
  context_cid~ : String,
  answering_authorities~ : Array[String],
  required_claims? : Array[String] = [],
) -> Result[DecisionRequest, RequestIssue] {
  if !valid_cid(configuration_cid) {
    return Err(InvalidConfigurationCid)
  }
  if !valid_cid(subject_cid) {
    return Err(InvalidSubjectCid)
  }
  if !valid_cid(context_cid) {
    return Err(InvalidContextCid)
  }
  if answering_authorities.is_empty() {
    return Err(NoAnsweringAuthority)
  }
  let authorities = match
    sorted_unique_names(answering_authorities, InvalidAnsweringAuthority, name => {
      DuplicateAnsweringAuthority(name)
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let claims = match
    sorted_unique_names(required_claims, InvalidRequiredClaim, name => {
      DuplicateRequiredClaim(name)
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    subject: {
      account_id: delegated.account_id,
      configuration_cid,
      entry_id: delegated.entry_id,
      tuple: delegated.tuple,
      boundary,
      subject_cid,
      context_cid,
    },
    answering_authorities: authorities,
    required_claims: claims,
  })
}

///|
/// The echoed subject and the answering authority. `authority` must be the
/// principal authenticated by the Host adapter, never a value read from an
/// unauthenticated answer body.
pub(all) struct AnswerBinding {
  subject : DecisionSubject
  authority : String
} derive(Eq, Debug)

///|
/// A technical failure to obtain a decision. It is not a rejection.
pub(all) enum DecisionFailureReason {
  Timeout
  Unavailable
  MalformedAnswer
  AdapterError(String)
} derive(Eq, Debug)

///|
/// Adapter vocabulary. `Permit` carries the claims the authority satisfied.
/// `Defer` echoes the subject but needs no answering authority: it grants
/// nothing and leads to a Checkpoint.
pub(all) enum HostAnswer {
  Permit(AnswerBinding, Array[String])
  Reject(AnswerBinding)
  Defer(DecisionSubject)
  Failure(DecisionFailureReason)
} derive(Eq, Debug)

///|
/// Why an answer is not admitted. A rejected answer changes no state.
pub(all) enum AnswerIssue {
  SubjectMismatch
  UnauthorizedAuthority(String)
  MissingRequiredClaim(String)
  UnrequestedClaim(String)
  DuplicateClaim(String)
} derive(Eq, Debug)

///|
/// Why dispatch is authorized. The caller still runs every independent
/// technical check (types, bounds, capabilities, provider requirements).
pub enum DispatchBasis {
  AccountAllow(String)
  HostPermit(DecisionSubject, String, Array[String])
} derive(Eq, Debug)

///|
pub enum Denial {
  Account(DenyReason)
  RejectedByHost(DecisionSubject, String)
} derive(Eq, Debug)

///|
/// What the runtime does at the boundary. `Checkpoint` requires the caller to
/// persist the sealed request and continuation before claiming a wait.
/// `DecisionFailure` dispatches nothing and is not an intentional rejection.
pub enum RuntimeAction {
  AuthorizedForDispatch(DispatchBasis)
  Deny(Denial)
  Checkpoint(DecisionRequest)
  DecisionFailure(DecisionFailureReason)
} derive(Eq, Debug)

///|
/// The action for an outcome that needs no Host decision: allow and deny.
/// Returns `None` for `Delegate`, which requires `prepare_decision_request`
/// and `admit_host_answer`.
pub fn runtime_action_for(outcome : AccountOutcome) -> RuntimeAction? {
  match outcome {
    Allow(entry_id) => Some(AuthorizedForDispatch(AccountAllow(entry_id)))
    Deny(reason) => Some(Deny(Account(reason)))
    Delegate(_) => None
  }
}

///|
fn check_binding(
  request : DecisionRequest,
  binding : AnswerBinding,
) -> Result[Unit, AnswerIssue] {
  if binding.subject != request.subject {
    return Err(SubjectMismatch)
  }
  if !sorted_contains(request.answering_authorities, binding.authority) {
    return Err(UnauthorizedAuthority(binding.authority))
  }
  Ok(())
}

///|
/// Admit a Host answer to a delegated request. The echoed subject must match
/// exactly and permit/reject must come from an allowed answering authority.
/// A permit must satisfy exactly the Host-required claims, else it is not an
/// accepted delegation. Adapter failure maps to `DecisionFailure`, never to
/// a rejection or a permit.
pub fn admit_host_answer(
  request : DecisionRequest,
  answer : HostAnswer,
) -> Result[RuntimeAction, AnswerIssue] {
  match answer {
    Failure(reason) => Ok(DecisionFailure(reason))
    Defer(subject) =>
      if subject != request.subject {
        Err(SubjectMismatch)
      } else {
        Ok(Checkpoint(request))
      }
    Reject(binding) => {
      if check_binding(request, binding) is Err(issue) {
        return Err(issue)
      }
      Ok(Deny(RejectedByHost(binding.subject, binding.authority)))
    }
    Permit(binding, claims) => {
      if check_binding(request, binding) is Err(issue) {
        return Err(issue)
      }
      let sorted = sort_names(claims)
      for index in 1..<sorted.length() {
        if sorted[index - 1] == sorted[index] {
          return Err(DuplicateClaim(sorted[index]))
        }
      }
      for claim in sorted {
        if !sorted_contains(request.required_claims, claim) {
          return Err(UnrequestedClaim(claim))
        }
      }
      for claim in request.required_claims {
        if !sorted_contains(sorted, claim) {
          return Err(MissingRequiredClaim(claim))
        }
      }
      Ok(
        AuthorizedForDispatch(
          HostPermit(binding.subject, binding.authority, sorted),
        ),
      )
    }
  }
}
