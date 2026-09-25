///|
/// Runtime error codes with phase `admission` pinned by Execution, Account
/// authorization routing.
pub const ACCOUNT_DENIED_CODE : String = "ACTQL_E_ACCOUNT_DENIED"

///|
pub const ACCOUNT_NO_MATCH_CODE : String = "ACTQL_E_ACCOUNT_NO_MATCH"

///|
pub const ACCOUNT_CONFIG_INVALID_CODE : String = "ACTQL_E_ACCOUNT_CONFIG_INVALID"

///|
pub const DELEGATION_REJECTED_CODE : String = "ACTQL_E_DELEGATION_REJECTED"

///|
pub const DELEGATION_UNAVAILABLE_CODE : String = "ACTQL_E_DELEGATION_UNAVAILABLE"

///|
/// Explicit deny and no-match stay distinct. A missing configuration is never
/// allow; it reports the invalid-configuration code.
pub fn deny_reason_error_code(reason : DenyReason) -> String {
  match reason {
    Explicit(_) => ACCOUNT_DENIED_CODE
    NoMatch => ACCOUNT_NO_MATCH_CODE
    ConfigurationMissing => ACCOUNT_CONFIG_INVALID_CODE
  }
}

///|
pub fn denial_error_code(denial : Denial) -> String {
  match denial {
    Account(reason) => deny_reason_error_code(reason)
    RejectedByHost(_, _) => DELEGATION_REJECTED_CODE
  }
}

///|
/// Every configuration issue leaves the account without an admitted
/// configuration, which is never treated as allow.
pub fn configuration_issue_error_code(_issue : ConfigurationIssue) -> String {
  ACCOUNT_CONFIG_INVALID_CODE
}

///|
/// A technical decision failure is not a rejection. When the Host ends the
/// Run instead of retrying, this is its code.
pub fn decision_failure_error_code(_reason : DecisionFailureReason) -> String {
  DELEGATION_UNAVAILABLE_CODE
}

///|
/// The admission error code for a runtime action that ends the affected unit,
/// or `None` for dispatch and for a deferred decision (Checkpoint).
pub fn runtime_action_error_code(action : RuntimeAction) -> String? {
  match action {
    AuthorizedForDispatch(_) | Checkpoint(_) => None
    Deny(denial) => Some(denial_error_code(denial))
    DecisionFailure(reason) => Some(decision_failure_error_code(reason))
  }
}
