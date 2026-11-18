///|
// The existing three-rule catalogue is unchanged for originals without a
// Source completion. This successor records only the original resolver fact.
fn local_source_normalization_catalog_cid() -> String {
  "sha256:6ce13b0a83618ec8ccadb33c3ee5bf4ae12214a0ac16c1e0394b75e1eea78153"
}

///|
fn common_normalization_catalog_cid(
  inventory : @checked.LocalCommonNormalizationInventory,
) -> String {
  if @checked.local_common_normalization_uses_source_completion(inventory) {
    local_source_normalization_catalog_cid()
  } else {
    local_common_normalization_catalog_cid()
  }
}
