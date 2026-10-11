///|
// Project existing typed refusals without exposing the grant packet, issuer
// configuration, credential or private journal. Absence remains unresolved.
fn local_preparation_grant_lookup_issue(
  issue : @local_host.NativeLocalSalesforcePreparationIssue,
) -> String {
  match issue {
    AuthorizationDenied | Issuer(Authorization(_)) =>
      "LocalPreparationGrantLookupAuthorizationDenied"
    ForeignInstallation => "LocalPreparationGrantReferenceMismatch"
    Adoption(issue) => local_host_issue(issue)
    Issuer(Expired) => "LocalPreparationGrantIssuerExpired"
    Issuer(Disabled) => "LocalPreparationGrantIssuerDisabled"
    Journal(CustodyLost) => "LocalPreparationGrantCustodyLost"
    Journal(ChangedIntent) => "LocalPreparationGrantReferenceMismatch"
    _ => "LocalPreparationGrantLookupUnavailable"
  }
}

///|
// Metadata-only lookup of the original issuance/adoption operation. The
// bounded reference is identity, not a live Work token, grant ACK or use.
// Only the existing current-authorized Owner reads its immutable custody;
// neither this command nor a missing original opens a Provider or renews it.
fn local_preparation_grant_lookup(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  input_root : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let scope = local_host_result(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
  )
  let current = () => {
    local_run_operation_allowed(host, settings, crypto, scope, "read")
  }
  if !current() {
    stop("LocalPreparationGrantLookupAuthorizationDenied")
  }
  let issuer_file = required(child, "issuer-file")
  if !settings.installation_files.contains(issuer_file) {
    stop("LocalPreparationGrantIssuerNotSelected")
  }
  let reference = @local_host.admit_native_local_preparation_grant_reference(
    crypto,
    required(child, "operation-cid"),
    @utf8.encode(
      text_file(input_root, required(child, "grant-ref-file"), 49152L),
    ),
  ).unwrap_or_else(() => stop("InvalidLocalPreparationGrantReference"))
  if !current() {
    stop("LocalPreparationGrantLookupAuthorizationDenied")
  }
  let observed = match
    host.lookup_preparation_grant_operation(
      crypto,
      issuer_file,
      settings.principal,
      settings.connection,
      reference,
    ) {
    Ok(value) => value
    Err(issue) => stop(local_preparation_grant_lookup_issue(issue))
  }
  if !current() {
    stop("LocalPreparationGrantLookupAuthorizationDenied")
  }
  encode_request_json(
    Json::object(
      Map([
        ("kind", Json::string("local_preparation_grant_lookup")),
        ("operationCid", Json::string(reference.operation_cid())),
        (
          "history",
          Json::string(
            match observed {
              RetainedOriginal => "retained"
              UnresolvedOriginal => "unresolved"
            },
          ),
        ),
      ]),
    ),
    4096,
  )
}
