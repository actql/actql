///|
pub(all) enum NativeSalesforceCatalogCustodyIssue {
  Read(NativeSalesforceNamedCatalogIssue)
  Store(@store.NativePublicationStoreIssue)
  ReadAuthorityChanged
}

///|
/// A failed save keeps the original physical response and, when preparation
/// succeeded, the same Store custody. This is not another resource Owner.
pub struct NativeSalesforceCatalogCustodyFailure {
  issue : NativeSalesforceCatalogCustodyIssue
  response : @resource.NativeCredentialResponse?
  pending : @store.EffectCatalogCustody?
}

///|
/// Persistence is still necessary when disclosure authority changes. It does
/// not authorize a read or send; only adoption of confirmed evidence is fenced.
fn[T, E] native_catalog_persist_and_confirm(
  persist : () -> Result[Unit, E],
  confirm : () -> Result[T, E],
  current : () -> Bool,
) -> Result[T?, E] {
  let before = current()
  match persist() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let saved = match confirm() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let after = current()
  if before && after {
    Ok(Some(saved))
  } else {
    Ok(None)
  }
}

///|
/// Retry only this prepared original Store responsibility. There is no service,
/// grant, use ID or physical-read callback here, so a lost save reply cannot
/// become another Provider read. Cleanup-only custody cannot supply evidence.
pub fn retry_native_salesforce_catalog_custody(
  pending : @store.EffectCatalogCustody,
  current : () -> Bool,
) -> Result[
  (@store.EffectCatalogCustody, @store.NativeEffectCatalogResponse),
  NativeSalesforceCatalogCustodyFailure,
] {
  match
    native_catalog_persist_and_confirm(
      () => pending.persist(),
      () => pending.confirm(),
      current,
    ) {
    Ok(Some(response)) => Ok((pending, response))
    Ok(None) =>
      Err({
        issue: ReadAuthorityChanged,
        response: None,
        pending: Some(pending),
      })
    Err(issue) =>
      Err({ issue: Store(issue), response: None, pending: Some(pending), })
  }
}

///|
/// Save an already observed response without repeating its credential use.
/// The original binding is independently selected by the trusted Host. A
/// failed preparation leaves the exact response with that caller; it is not
/// durable evidence until the Store has persisted and confirmed its custody.
pub fn retain_native_salesforce_named_catalog_response(
  store : @store.Store,
  catalog : @catalog.CatalogObservation,
  response : @resource.NativeCredentialResponse,
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  limits : @catalog.DescribeLimits,
  crypto : @signature.Library,
  key : Bytes,
  current : () -> Bool,
) -> Result[
  (@store.EffectCatalogCustody, @store.NativeEffectCatalogResponse),
  NativeSalesforceCatalogCustodyFailure,
] {
  let original = { ..response, body: response.body[:].to_owned(), }
  let pending = match
    store.prepare_effect_catalog_custody(
      catalog,
      binding,
      resource,
      original.use_cid,
      original.status,
      original.body,
      limits,
      crypto,
      key,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err({
        issue: Store(issue),
        response: Some(original),
        pending: None,
      })
  }
  match retry_native_salesforce_catalog_custody(pending, current) {
    Ok(value) => Ok(value)
    Err(failure) => Err({ ..failure, response: Some(original), })
  }
}

///|
/// The production read/save boundary reuses the existing signed credential,
/// exact use, named Catalog admission and Store custody Owners. It performs
/// at most one physical call; an error is returned with its existing evidence,
/// never retried here. Provider permission remains independent of approval.
pub fn observe_and_retain_native_salesforce_named_catalog(
  service : @resource.NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : @resource.NativeCredentialScope,
  binding : @catalog.CatalogObservationBinding,
  credential_org_id : String,
  api_version : String,
  resource : String,
  limits : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  store : @store.Store,
  crypto : @signature.Library,
  key : Bytes,
  current : () -> Bool,
) -> Result[
  (@store.EffectCatalogCustody, @store.NativeEffectCatalogResponse),
  NativeSalesforceCatalogCustodyFailure,
] {
  let (catalog, response) = match
    observe_native_salesforce_named_catalog(
      service, grant, use_id, scope, binding, credential_org_id, api_version, resource,
      limits, max_observation_bytes, current,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err({ issue: Read(issue), response: None, pending: None, })
  }
  retain_native_salesforce_named_catalog_response(
    store, catalog, response, binding, resource, limits, crypto, key, current,
  )
}
