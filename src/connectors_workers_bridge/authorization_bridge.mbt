// Handwritten execution-authorization adapter for the Node Host gate. All
// account interpretation, decision binding and answer admission stay in
// `@authorization`; this file only exposes opaque handles and projections.
// Sharing this runtime with the strategy bridge lets an evaluated dispatch
// action become a task activation grant without re-evaluation.

///|
/// Admitted, missing or rejected account configuration. A rejected
/// configuration grants nothing and evaluates exactly like a missing one.
struct AuthorizationAccount {
  state : @authorization.AccountConfigurationState
  issue : String
}

///|
struct AuthorizationEvaluation {
  outcome : @authorization.AccountOutcome
}

///|
struct AuthorizationRequest {
  request : @authorization.DecisionRequest?
  issue : String
}

///|
struct AuthorizationDecision {
  action : @authorization.RuntimeAction?
  issue : String
}

///|
fn authorization_boundary(token : String) -> @authorization.DecisionBoundary? {
  match token {
    "preparation" => Some(Preparation)
    "acquisition" => Some(Acquisition)
    "activation" => Some(Activation)
    "transfer" => Some(Transfer)
    "effect_commit" => Some(EffectCommit)
    _ => None
  }
}

///|
fn authorization_boundary_token(
  boundary : @authorization.DecisionBoundary,
) -> String {
  match boundary {
    Preparation => "preparation"
    Acquisition => "acquisition"
    Activation => "activation"
    Transfer => "transfer"
    EffectCommit => "effect_commit"
  }
}

///|
fn authorization_subject_json(subject : @authorization.DecisionSubject) -> Json {
  Json::object({
    "account_id": Json::string(subject.account_id),
    "configuration_cid": Json::string(subject.configuration_cid),
    "entry_id": Json::string(subject.entry_id),
    "principal": Json::string(subject.tuple.principal),
    "connection": Json::string(subject.tuple.connection),
    "resource": Json::string(subject.tuple.resource),
    "operation": Json::string(subject.tuple.operation),
    "boundary": Json::string(authorization_boundary_token(subject.boundary)),
    "subject_cid": Json::string(subject.subject_cid),
    "context_cid": Json::string(subject.context_cid),
  })
}

///|
/// Subject fields in the fixed order used by `executionAuthorizationAnswer`.
fn authorization_subject_from(
  fields : Array[String],
) -> @authorization.DecisionSubject? {
  if fields.length() != 10 {
    return None
  }
  guard authorization_boundary(fields[7]) is Some(boundary) else { return None }
  Some({
    account_id: fields[0],
    configuration_cid: fields[1],
    entry_id: fields[2],
    tuple: {
      principal: fields[3],
      connection: fields[4],
      resource: fields[5],
      operation: fields[6],
    },
    boundary,
    subject_cid: fields[8],
    context_cid: fields[9],
  })
}

///|
fn authorization_strings(values : Array[String]) -> Json {
  Json::array(values.map(value => Json::string(value)))
}

///|
#export_name("executionAuthorizationAdmit")
pub fn execution_authorization_admit(body : String) -> AuthorizationAccount {
  match @authorization.admit_account_configuration_json(body) {
    Ok(configuration) => { state: Admitted(configuration), issue: "", }
    Err(issue) => { state: Missing, issue: @debug.to_string(issue), }
  }
}

///|
#export_name("executionAuthorizationMissing")
pub fn execution_authorization_missing() -> AuthorizationAccount {
  { state: Missing, issue: "", }
}

///|
#export_name("executionAuthorizationAccountJson")
pub fn execution_authorization_account_json(
  account : AuthorizationAccount,
) -> String {
  let fields : Map[String, Json] = match account.state {
    Admitted(configuration) =>
      {
        "state": Json::string("admitted"),
        "account_id": Json::string(configuration.account_id()),
        "configuration_cid": Json::string(configuration.configuration_cid()),
        "entry_count": Json::number(configuration.entry_count().to_double()),
      }
    Missing =>
      if account.issue == "" {
        { "state": Json::string("missing") }
      } else {
        {
          "state": Json::string("rejected"),
          "issue": Json::string(account.issue),
        }
      }
  }
  Json::object(fields).stringify()
}

///|
/// Cheap local evaluation of one concrete tuple. No Host call, no hashing.
#export_name("executionAuthorizationEvaluate")
pub fn execution_authorization_evaluate(
  account : AuthorizationAccount,
  principal : String,
  connection : String,
  resource : String,
  operation : String,
) -> AuthorizationEvaluation {
  {
    outcome: @authorization.evaluate_account_state(account.state, {
      principal,
      connection,
      resource,
      operation,
    }),
  }
}

///|
#export_name("executionAuthorizationEvaluationJson")
pub fn execution_authorization_evaluation_json(
  evaluation : AuthorizationEvaluation,
) -> String {
  let fields : Map[String, Json] = match evaluation.outcome {
    Allow(entry) =>
      { "outcome": Json::string("allow"), "entry_id": Json::string(entry) }
    Delegate(delegated) =>
      {
        "outcome": Json::string("delegate"),
        "entry_id": Json::string(delegated.entry_id),
      }
    Deny(NoMatch) =>
      { "outcome": Json::string("deny"), "reason": Json::string("no_match") }
    Deny(Explicit(entry)) =>
      {
        "outcome": Json::string("deny"),
        "reason": Json::string("explicit"),
        "entry_id": Json::string(entry),
      }
    Deny(ConfigurationMissing) =>
      {
        "outcome": Json::string("deny"),
        "reason": Json::string("configuration_missing"),
      }
  }
  Json::object(fields).stringify()
}

///|
/// The runtime action for allow and deny. Delegate has none: it needs a bound
/// request and an admitted Host answer.
#export_name("executionAuthorizationEvaluationAction")
pub fn execution_authorization_evaluation_action(
  evaluation : AuthorizationEvaluation,
) -> AuthorizationDecision {
  match @authorization.runtime_action_for(evaluation.outcome) {
    Some(action) => { action: Some(action), issue: "", }
    None => { action: None, issue: "Delegate", }
  }
}

///|
#export_name("executionAuthorizationPrepare")
pub fn execution_authorization_prepare(
  evaluation : AuthorizationEvaluation,
  configuration_cid : String,
  boundary : String,
  subject_cid : String,
  context_cid : String,
  answering_authorities : Array[String],
  required_claims : Array[String],
) -> AuthorizationRequest {
  guard evaluation.outcome is Delegate(delegated) else {
    return { request: None, issue: "NotDelegated", }
  }
  guard authorization_boundary(boundary) is Some(boundary) else {
    return { request: None, issue: "InvalidBoundary", }
  }
  match
    @authorization.prepare_decision_request(
      delegated,
      configuration_cid~,
      boundary~,
      subject_cid~,
      context_cid~,
      answering_authorities~,
      required_claims~,
    ) {
    Ok(request) => { request: Some(request), issue: "", }
    Err(issue) => { request: None, issue: @debug.to_string(issue), }
  }
}

///|
#export_name("executionAuthorizationRequestJson")
pub fn execution_authorization_request_json(
  request : AuthorizationRequest,
) -> String {
  match request.request {
    None =>
      Json::object({
        "ok": Json::boolean(false),
        "issue": Json::string(request.issue),
      }).stringify()
    Some(value) =>
      Json::object({
        "ok": Json::boolean(true),
        "subject": authorization_subject_json(value.subject()),
        "answering_authorities": authorization_strings(
          value.answering_authorities(),
        ),
        "required_claims": authorization_strings(value.required_claims()),
      }).stringify()
  }
}

///|
/// Admit one Host answer. `kind` is permit, reject, defer or failure; the
/// echoed subject is the fixed ten-field projection. A malformed or
/// unbindable answer is a decision failure, never a rejection or a permit.
#export_name("executionAuthorizationAnswer")
pub fn execution_authorization_answer(
  request : AuthorizationRequest,
  kind : String,
  subject : Array[String],
  authority : String,
  claims : Array[String],
  failure : String,
) -> AuthorizationDecision {
  guard request.request is Some(bound) else {
    return { action: None, issue: "NoDecisionRequest", }
  }
  let malformed : @authorization.HostAnswer = Failure(MalformedAnswer)
  let answer : @authorization.HostAnswer = match kind {
    "failure" =>
      Failure(
        match failure {
          "timeout" => Timeout
          "unavailable" => Unavailable
          "malformed_answer" => MalformedAnswer
          detail => AdapterError(detail)
        },
      )
    "defer" =>
      match authorization_subject_from(subject) {
        Some(echoed) => Defer(echoed)
        None => malformed
      }
    "reject" =>
      match authorization_subject_from(subject) {
        Some(echoed) => Reject({ subject: echoed, authority, })
        None => malformed
      }
    "permit" =>
      match authorization_subject_from(subject) {
        Some(echoed) => Permit({ subject: echoed, authority, }, claims)
        None => malformed
      }
    _ => malformed
  }
  match @authorization.admit_host_answer(bound, answer) {
    Ok(action) => { action: Some(action), issue: "", }
    Err(issue) =>
      // An answer that does not bind to the exact request is an adapter
      // failure: it grants nothing and is not an intentional rejection.
      match @authorization.admit_host_answer(bound, Failure(MalformedAnswer)) {
        Ok(action) => { action: Some(action), issue: @debug.to_string(issue), }
        Err(_) => { action: None, issue: @debug.to_string(issue), }
      }
  }
}

///|
#export_name("executionAuthorizationDecisionJson")
pub fn execution_authorization_decision_json(
  decision : AuthorizationDecision,
) -> String {
  let fields : Map[String, Json] = match decision.action {
    None => { "action": Json::string("invalid") }
    Some(AuthorizedForDispatch(AccountAllow(entry))) =>
      {
        "action": Json::string("dispatch"),
        "basis": Json::string("account_allow"),
        "entry_id": Json::string(entry),
      }
    Some(AuthorizedForDispatch(HostPermit(subject, authority, claims))) =>
      {
        "action": Json::string("dispatch"),
        "basis": Json::string("host_permit"),
        "subject": authorization_subject_json(subject),
        "authority": Json::string(authority),
        "claims": authorization_strings(claims),
      }
    Some(Deny(Account(reason))) =>
      {
        "action": Json::string("deny"),
        "basis": Json::string("account"),
        "reason": Json::string(
          match reason {
            NoMatch => "no_match"
            Explicit(_) => "explicit"
            ConfigurationMissing => "configuration_missing"
          },
        ),
        "entry_id": match reason {
          Explicit(entry) => Json::string(entry)
          _ => Json::null()
        },
      }
    Some(Deny(RejectedByHost(subject, authority))) =>
      {
        "action": Json::string("deny"),
        "basis": Json::string("rejected_by_host"),
        "subject": authorization_subject_json(subject),
        "authority": Json::string(authority),
      }
    Some(Checkpoint(request)) =>
      {
        "action": Json::string("checkpoint"),
        "subject": authorization_subject_json(request.subject()),
      }
    Some(DecisionFailure(reason)) =>
      {
        "action": Json::string("failure"),
        "reason": Json::string(
          match reason {
            Timeout => "timeout"
            Unavailable => "unavailable"
            MalformedAnswer => "malformed_answer"
            AdapterError(_) => "adapter_error"
          },
        ),
        "detail": match reason {
          AdapterError(detail) => Json::string(detail)
          _ => Json::null()
        },
      }
  }
  if decision.issue != "" {
    fields["issue"] = Json::string(decision.issue)
  }
  Json::object(fields).stringify()
}

///|
/// Grant exactly the next ready task from an evaluated dispatch action. Any
/// other action, a stale task or a stopped Run grants nothing.
#export_name("strategyHostAuthorizeActivation")
pub fn strategy_host_authorize_activation(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
  decision : AuthorizationDecision,
) -> Bool {
  guard decision.action is Some(action) else { return false }
  guard @strategy.task_activation_authorized(action) is Some(grant) else {
    return false
  }
  @strategy.authorize_captured_task_activation(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
    task,
    grant,
  )
  is Ok(_)
}
