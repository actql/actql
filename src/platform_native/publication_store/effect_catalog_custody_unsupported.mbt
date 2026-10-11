///|
type EffectCatalogCustody

///|
pub fn Store::prepare_effect_catalog_custody(
  _self : Store,
  _catalog : @catalog.CatalogObservation,
  _binding : @catalog.CatalogObservationBinding,
  _resource : String,
  _use_cid : String,
  _status : Int,
  _body : Bytes,
  _limits : @catalog.DescribeLimits,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[EffectCatalogCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::restore_effect_catalog_custody(
  _self : Store,
  _binding : @catalog.CatalogObservationBinding,
  _resource : String,
  _original_use_cid : String,
  _limits : @catalog.DescribeLimits,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[EffectCatalogCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCatalogCustody::persist(
  _self : EffectCatalogCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCatalogCustody::confirm(
  _self : EffectCatalogCustody,
) -> Result[NativeEffectCatalogResponse, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCatalogCustody::retry_cleanup(
  _self : EffectCatalogCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCatalogCustody::reserved_bytes(
  _self : EffectCatalogCustody,
) -> Int64 {
  0L
}
