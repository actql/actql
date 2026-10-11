///|
priv enum NativeOwnedCredentialGrant {
  RemoteGrant(@credential.RemoteCredentialGrant)
  LocalGrant(@credential.LocalCredentialGrant)
}

///|
priv enum NativeOwnedCredentialScope {
  RemoteScope(NativeCredentialScope)
  LocalScope(@credential.LocalCredentialScope)
}

///|
priv enum NativeOwnedCredentialUse {
  RemoteUse(@credential.RemoteCredentialUse)
  LocalUse(@credential.LocalCredentialUse)
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
fn authorize_owned_credential(
  service : NativeCredentialResourceService,
  scope : NativeOwnedCredentialScope,
  facts : NativeOwnedCredentialAuthorizationFacts,
) -> Bool {
  match scope {
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
  }
}

///|
fn owned_operation_for(
  service : NativeCredentialResourceService,
  scope : NativeOwnedCredentialScope,
) -> NativeCredentialOperation? {
  match scope {
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
  }
}

///|
fn owned_credential_grant_cid(grant : NativeOwnedCredentialGrant) -> String {
  match grant {
    RemoteGrant(value) => @credential.credential_grant_cid(value)
    LocalGrant(value) => @credential.local_credential_grant_cid(value)
  }
}

///|
fn owned_grant_matches_scope(
  grant : NativeOwnedCredentialGrant,
  scope : NativeOwnedCredentialScope,
) -> (Int, Int64)? {
  match (grant, scope) {
    (RemoteGrant(value), RemoteScope(current)) =>
      grant_matches_scope(value, current)
    (LocalGrant(value), LocalScope(current)) =>
      if @credential.local_credential_grant_scope(value) == current &&
        @credential.local_credential_grant_json(value) is Ok(_) {
        Some(@credential.local_credential_grant_limits(value))
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
    _ => Err(@credential.CredentialGrantInactive)
  }
}

///|
fn owned_credential_use_cid(
  credential_use : NativeOwnedCredentialUse,
) -> String {
  match credential_use {
    RemoteUse(value) => @credential.credential_use_cid(value)
    LocalUse(value) => @credential.local_credential_use_cid(value)
  }
}

///|
fn owned_credential_use_json(
  credential_use : NativeOwnedCredentialUse,
) -> Result[String, @credential.RemoteCredentialIssue] {
  match credential_use {
    RemoteUse(value) => @credential.credential_use_json(value)
    LocalUse(value) => @credential.local_credential_use_json(value)
  }
}

///|
fn owned_credential_use_id(credential_use : NativeOwnedCredentialUse) -> String {
  match credential_use {
    RemoteUse(value) => @credential.credential_use_projection(value)[2]
    LocalUse(value) => {
      let (_, use_id, _) = @credential.local_credential_use_projection(value)
      use_id
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
    RemoteGrant(value) =>
      @credential.admit_credential_use_json(value, wire, cid).map(value => {
        RemoteUse(value)
      })
    LocalGrant(value) =>
      @credential.admit_local_credential_use_json(value, wire, cid).map(value => {
        LocalUse(value)
      })
  }
}
