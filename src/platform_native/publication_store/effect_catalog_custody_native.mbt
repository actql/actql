///|
/// A typed factory over the existing encrypted evidence custody. Active
/// Catalog evidence and terminal cleanup-only restoration grant no send rights.
struct EffectCatalogCustody {
  private_custody : PrivateEffectEvidenceCustody
  response : NativeEffectCatalogResponse?
}

///|
/// Original binding comes from the retained Host/producer, not catalog wire.
/// Only the successful named observation is admitted here; failed physical
/// responses retain their caller's separate unresolved responsibility.
pub fn Store::prepare_effect_catalog_custody(
  self : Store,
  catalog : @catalog.CatalogObservation,
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  use_cid : String,
  status : Int,
  body : Bytes,
  limits : @catalog.DescribeLimits,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCatalogCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.prepare_effect_catalog_custody_in_scope(
      catalog, binding, resource, use_cid, status, body, limits, crypto, key,
    )
  })
}

///|
fn Store::prepare_effect_catalog_custody_in_scope(
  self : Store,
  catalog : @catalog.CatalogObservation,
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  use_cid : String,
  status : Int,
  body : Bytes,
  limits : @catalog.DescribeLimits,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCatalogCustody, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if !@catalog.catalog_observation_matches_binding(catalog, binding) {
    return Err(StateCollision)
  }
  let response = match
    effect_catalog_response(
      @catalog.catalog_observation_json(catalog),
      binding,
      resource,
      use_cid,
      status,
      body,
      limits,
      self.max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let holding = match
    effect_catalog_holding(
      binding,
      resource,
      self.authority_cid,
      self.max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let wire = match
    effect_catalog_record(
      response,
      binding,
      resource,
      self.authority_cid,
      self.max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let prepared = match
    prepare_private_effect_custody(
      self, holding, "effect_catalog", holding, wire, "effect_catalog_custody", "effect-catalog",
      "", crypto, key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    private_custody: {
      ..prepared,
      terminal: @utf8.encode(
        effect_catalog_terminal(holding, prepared.reservation_bytes),
      ),
    },
    response: Some(response),
  })
}

///|
/// Read exact original encrypted bytes. No describe/read is repeated and no
/// missing slot is created. A retired slot restores only capacity cleanup.
pub fn Store::restore_effect_catalog_custody(
  self : Store,
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  original_use_cid : String,
  limits : @catalog.DescribeLimits,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCatalogCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.restore_effect_catalog_custody_in_scope(
      binding, resource, original_use_cid, limits, crypto, key,
    )
  })
}

///|
fn Store::restore_effect_catalog_custody_in_scope(
  self : Store,
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  original_use_cid : String,
  limits : @catalog.DescribeLimits,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCatalogCustody, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let holding = match
    effect_catalog_holding(
      binding,
      resource,
      self.authority_cid,
      self.max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let row = match self.database.read("effect_catalog_custody", holding) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let stored = @utf8.decode(row.body) catch { _ => return Err(StateCollision) }
  if effect_catalog_terminal_bytes(stored, holding, self.max_record_bytes)
    is Some(bytes) {
    if row.revision != 0L && row.revision != 1L {
      return Err(StateCollision)
    }
    return Ok({
      private_custody: {
        store: self,
        crypto,
        key: key[:].to_owned(),
        envelope: Bytes::new(0),
        reservation_bytes: bytes,
        reservation_objects: 1L,
        preparation: None,
        terminal: row.body,
        capacity_key: "effect-catalog:" + holding,
        table: "effect_catalog_custody",
        holding,
        kind: "effect_catalog",
        semantic_cid: holding,
        wire: "",
        step_prefix: "effect-catalog",
        transaction_uncertain: false,
      },
      response: None,
    })
  }
  if row.revision != 0L {
    return Err(StateCollision)
  }
  let plain = match
    crypto.open_private_evidence(key, "effect_catalog", holding, row.body) {
    Ok(value) => value
    Err(issue) => return Err(PrivateEvidence(issue))
  }
  let wire = @utf8.decode(plain) catch { _ => return Err(StateCollision) }
  let response = match
    restore_effect_catalog_record(
      wire,
      binding,
      resource,
      original_use_cid,
      self.authority_cid,
      limits,
      self.max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let custody = match
    self.prepare_effect_catalog_custody_in_scope(
      response.catalog,
      binding,
      resource,
      response.use_cid,
      response.status,
      response.body,
      limits,
      crypto,
      key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  custody.private_custody.read().map(_ => custody)
}

///|
pub fn EffectCatalogCustody::persist(
  self : EffectCatalogCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.persist_in_scope()
  })
}

///|
fn EffectCatalogCustody::persist_in_scope(
  self : EffectCatalogCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.persist()
}

///|
pub fn EffectCatalogCustody::confirm(
  self : EffectCatalogCustody,
) -> Result[NativeEffectCatalogResponse, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.confirm_in_scope()
  })
}

///|
fn EffectCatalogCustody::confirm_in_scope(
  self : EffectCatalogCustody,
) -> Result[NativeEffectCatalogResponse, NativePublicationStoreIssue] {
  match (self.private_custody.read(), self.response) {
    (Ok((_, false)), Some(value)) =>
      Ok({ ..value, body: value.body[:].to_owned(), })
    (Ok(_), _) => Err(RecoveryRequired)
    (Err(issue), _) => Err(issue)
  }
}

///|
pub fn EffectCatalogCustody::retry_cleanup(
  self : EffectCatalogCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(true, false, fn() {
    self.retry_cleanup_in_scope()
  })
}

///|
fn EffectCatalogCustody::retry_cleanup_in_scope(
  self : EffectCatalogCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.retry_cleanup()
}

///|
pub fn EffectCatalogCustody::reserved_bytes(
  self : EffectCatalogCustody,
) -> Int64 {
  self.private_custody.reserved_bytes()
}
