///|
// Signing is deliberately not constructed until its trusted supplier is wired.
// Keep the typed metadata alternative and its independent refusal cases.
#warnings("-unused_constructor")
priv enum NativeOwnedCredentialGrant {
  RemoteGrant(@credential.RemoteCredentialGrant)
  LocalGrant(@credential.LocalCredentialGrant)
  PreparationGrant(@credential.LocalPreparationCredentialGrant)
  SigningGrant(@credential.LocalSigningCredentialGrant)
}

///|
// This scope cannot select an HTTP operation or grant current signing authority.
#warnings("-unused_constructor")
priv enum NativeOwnedCredentialScope {
  RemoteScope(NativeCredentialScope)
  LocalScope(@credential.LocalCredentialScope)
  PreparationScope(@credential.LocalPreparationCredentialScope)
  SigningScope(@credential.LocalSigningCredentialScope)
}

///|
priv enum NativeOwnedCredentialUse {
  RemoteUse(@credential.RemoteCredentialUse)
  LocalUse(@credential.LocalCredentialUse)
  PreparationUse(@credential.LocalPreparationCredentialUse)
  SigningUse(@credential.LocalSigningCredentialUse)
}

///|
pub(all) struct NativeLocalCredentialAuthorization {
  stage : String
  grant_cid : String
  use_cid : String?
  scope : @credential.LocalCredentialScope
  request : NativeCredentialRequest?
}

///|
priv struct NativeOwnedCredentialAuthorizationFacts {
  stage : String
  grant_cid : String
  use_cid : String?
  request : NativeCredentialRequest?
}

///|
pub(all) struct NativeLocalPreparationCredentialAuthorization {
  stage : String
  grant_cid : String
  use_cid : String?
  scope : @credential.LocalPreparationCredentialScope
  request : NativeCredentialRequest?
}

///|
fn authorize_owned_credential(
  service : NativeCredentialResourceService,
  scope : NativeOwnedCredentialScope,
  facts : NativeOwnedCredentialAuthorizationFacts,
) -> Bool {
  match scope {
    // No signing current supplier is installed by this metadata unit.
    // HTTP authorization is never borrowed for either signing purpose.
    SigningScope(_) => false
    RemoteScope(remote) =>
      (service.authorize)({
        stage: facts.stage,
        grant_cid: facts.grant_cid,
        use_cid: facts.use_cid,
        scope: remote,
        request: facts.request,
      })
    LocalScope(direct_scope) =>
      match service.authorize_local {
        None => false
        Some(authorize) =>
          authorize({
            stage: facts.stage,
            grant_cid: facts.grant_cid,
            use_cid: facts.use_cid,
            scope: direct_scope,
            request: facts.request,
          })
      }
    PreparationScope(preparation) =>
      match service.authorize_preparation {
        None => false
        Some(authorize) =>
          authorize({
            stage: facts.stage,
            grant_cid: facts.grant_cid,
            use_cid: facts.use_cid,
            scope: preparation,
            request: facts.request,
          })
      }
  }
}

///|
fn owned_operation_for(
  service : NativeCredentialResourceService,
  scope : NativeOwnedCredentialScope,
) -> NativeCredentialOperation? {
  match scope {
    SigningScope(_) => None
    RemoteScope(remote) => operation_for(service, remote)
    LocalScope(direct_scope) => {
      let mut found = None
      for operation in service.operations {
        if operation.resource_origin == direct_scope.resource_origin &&
          operation.operation == direct_scope.operation {
          if found is Some(_) {
            return None
          }
          found = Some(operation)
        }
      }
      found
    }
    PreparationScope(preparation) => {
      let mut found = None
      for operation in service.operations {
        if operation.resource_origin == preparation.resource_origin &&
          operation.operation == preparation.operation &&
          operation.operation == "salesforce:record:observe" &&
          operation.verb == @http.Get &&
          operation.max_request_bytes == 0 {
          if found is Some(_) {
            return None
          }
          found = Some(operation)
        }
      }
      found
    }
  }
}

///|
fn owned_credential_grant_cid(grant : NativeOwnedCredentialGrant) -> String {
  match grant {
    SigningGrant(value) => @credential.local_signing_credential_grant_cid(value)
    RemoteGrant(value) => @credential.credential_grant_cid(value)
    LocalGrant(value) => @credential.local_credential_grant_cid(value)
    PreparationGrant(value) =>
      @credential.local_preparation_credential_grant_cid(value)
  }
}

///|
fn owned_grant_matches_scope(
  grant : NativeOwnedCredentialGrant,
  scope : NativeOwnedCredentialScope,
) -> (Int, Int64)? {
  match (grant, scope) {
    (SigningGrant(value), SigningScope(current)) =>
      if @credential.local_signing_credential_grant_scope(value) == current &&
        @credential.local_signing_credential_grant_json(value) is Ok(_) {
        Some(@credential.local_signing_credential_grant_limits(value))
      } else {
        None
      }
    (RemoteGrant(value), RemoteScope(current)) =>
      grant_matches_scope(value, current)
    (LocalGrant(value), LocalScope(current)) =>
      if @credential.local_credential_grant_scope(value) == current &&
        @credential.local_credential_grant_json(value) is Ok(_) {
        Some(@credential.local_credential_grant_limits(value))
      } else {
        None
      }
    (PreparationGrant(value), PreparationScope(current)) =>
      if @credential.local_preparation_credential_grant_scope(value) == current &&
        @credential.local_preparation_credential_grant_json(value) is Ok(_) {
        Some(@credential.local_preparation_credential_grant_limits(value))
      } else {
        None
      }
    _ => None
  }
}

///|
fn owned_request_matches_scope(
  scope : NativeOwnedCredentialScope,
  verb : @http.NativeHttpMethod,
  path : String,
  body : Bytes,
) -> Bool {
  match scope {
    // A signing purpose has no HTTP request. Even matching dummy fields must
    // never select the HTTP claim/send path.
    SigningScope(_) => false
    RemoteScope(_) => true
    LocalScope(direct_scope) => {
      let request_method = match verb {
        Get => "GET"
        Post => "POST"
        Put => "PUT"
        Patch => "PATCH"
      }
      request_method == direct_scope.request_method &&
      path == direct_scope.request_path &&
      @credential.local_credential_request_body_cid(body) ==
      Ok(direct_scope.request_body_cid)
    }
    PreparationScope(preparation) =>
      verb == @http.Get &&
      preparation.request_method == "GET" &&
      preparation.operation == "salesforce:record:observe" &&
      path == preparation.request_path &&
      body.length() == 0 &&
      @credential.local_credential_request_body_cid(body) ==
      Ok(preparation.request_body_cid)
  }
}

///|
fn prepare_owned_credential_use(
  grant : NativeOwnedCredentialGrant,
  use_id : String,
  now : Int64,
  used_count : Int,
  revoked : Bool,
  scope : NativeOwnedCredentialScope,
) -> Result[NativeOwnedCredentialUse, @credential.RemoteCredentialIssue] {
  match (grant, scope) {
    (SigningGrant(value), SigningScope(current)) =>
      @credential.prepare_local_signing_credential_use(
        value, use_id, now, used_count, revoked, current,
      ).map(value => SigningUse(value))
    (RemoteGrant(value), RemoteScope(current)) =>
      @credential.prepare_credential_use(
        value,
        use_id,
        now,
        used_count,
        revoked,
        current.principal,
        current.namespace_id,
        current.environment,
        current.site_key,
        current.site_generation,
        current.runtime_bundle_cid,
        current.connector_registration,
        current.connector_revision,
        current.resource_origin,
        current.operation,
        current.run_invocation_cid,
        current.task_attempt,
        current.dispatch_request_cid,
      ).map(value => RemoteUse(value))
    (LocalGrant(value), LocalScope(current)) =>
      @credential.prepare_local_credential_use(
        value, use_id, now, used_count, revoked, current,
      ).map(value => LocalUse(value))
    (PreparationGrant(value), PreparationScope(current)) =>
      @credential.prepare_local_preparation_credential_use(
        value, use_id, now, used_count, revoked, current,
      ).map(value => PreparationUse(value))
    _ => Err(@credential.CredentialGrantInactive)
  }
}

///|
fn authorize_owned_credential_use(
  credential_use : NativeOwnedCredentialUse,
  now : Int64,
  revoked : Bool,
  scope : NativeOwnedCredentialScope,
) -> Result[Unit, @credential.RemoteCredentialIssue] {
  match (credential_use, scope) {
    (SigningUse(value), SigningScope(current)) =>
      @credential.validate_local_signing_credential_use_binding(
        value, now, revoked, current,
      )
    (RemoteUse(value), RemoteScope(current)) =>
      @credential.authorize_credential_use(
        value,
        now,
        revoked,
        current.principal,
        current.namespace_id,
        current.environment,
        current.site_key,
        current.site_generation,
        current.runtime_bundle_cid,
        current.connector_registration,
        current.connector_revision,
        current.resource_origin,
        current.operation,
        current.run_invocation_cid,
        current.task_attempt,
        current.dispatch_request_cid,
      )
    (LocalUse(value), LocalScope(current)) =>
      @credential.authorize_local_credential_use(value, now, revoked, current)
    (PreparationUse(value), PreparationScope(current)) =>
      @credential.authorize_local_preparation_credential_use(
        value, now, revoked, current,
      )
    _ => Err(@credential.CredentialGrantInactive)
  }
}

///|
fn owned_credential_use_cid(
  credential_use : NativeOwnedCredentialUse,
) -> String {
  match credential_use {
    SigningUse(value) => @credential.local_signing_credential_use_cid(value)
    RemoteUse(value) => @credential.credential_use_cid(value)
    LocalUse(value) => @credential.local_credential_use_cid(value)
    PreparationUse(value) =>
      @credential.local_preparation_credential_use_cid(value)
  }
}

///|
fn owned_credential_use_json(
  credential_use : NativeOwnedCredentialUse,
) -> Result[String, @credential.RemoteCredentialIssue] {
  match credential_use {
    SigningUse(value) => @credential.local_signing_credential_use_json(value)
    RemoteUse(value) => @credential.credential_use_json(value)
    LocalUse(value) => @credential.local_credential_use_json(value)
    PreparationUse(value) =>
      @credential.local_preparation_credential_use_json(value)
  }
}

///|
fn owned_credential_use_id(credential_use : NativeOwnedCredentialUse) -> String {
  match credential_use {
    SigningUse(value) => {
      let (_, use_id, _) = @credential.local_signing_credential_use_projection(
        value,
      )
      use_id
    }
    RemoteUse(value) => @credential.credential_use_projection(value)[2]
    LocalUse(value) => {
      let (_, use_id, _) = @credential.local_credential_use_projection(value)
      use_id
    }
    PreparationUse(value) => {
      let (_, use_id, _) = @credential.local_preparation_credential_use_projection(
        value,
      )
      use_id
    }
  }
}

///|
fn owned_credential_use_matches_ordinal(
  credential_use : NativeOwnedCredentialUse,
  ordinal : Int64,
) -> Bool {
  match credential_use {
    SigningUse(value) => {
      let (_, _, saved_ordinal) = @credential.local_signing_credential_use_projection(
        value,
      )
      saved_ordinal.to_int64() == ordinal
    }
    RemoteUse(value) =>
      @credential.credential_use_projection(value)[3] == ordinal.to_string()
    LocalUse(value) => {
      let (_, _, saved_ordinal) = @credential.local_credential_use_projection(
        value,
      )
      saved_ordinal.to_int64() == ordinal
    }
    PreparationUse(value) => {
      let (_, _, saved_ordinal) = @credential.local_preparation_credential_use_projection(
        value,
      )
      saved_ordinal.to_int64() == ordinal
    }
  }
}

///|
fn admit_owned_credential_use(
  grant : NativeOwnedCredentialGrant,
  wire : String,
  cid : String,
) -> Result[NativeOwnedCredentialUse, @credential.RemoteCredentialIssue] {
  match grant {
    SigningGrant(value) =>
      @credential.admit_local_signing_credential_use_json(value, wire, cid).map(value => {
          SigningUse(value)
        },
      )
    RemoteGrant(value) =>
      @credential.admit_credential_use_json(value, wire, cid).map(value => {
        RemoteUse(value)
      })
    LocalGrant(value) =>
      @credential.admit_local_credential_use_json(value, wire, cid).map(value => {
        LocalUse(value)
      })
    PreparationGrant(value) =>
      @credential.admit_local_preparation_credential_use_json(value, wire, cid).map(value => {
          PreparationUse(value)
        },
      )
  }
}
