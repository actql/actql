///|
/// The same checked Command occurrence and its installed, issued target.
/// The trusted issuer retains physical collection and installation currentness;
/// this projection neither issues a Reference nor grants Command dispatch.
pub struct EffectPublishedStoreTarget {
  binding : EffectCommandInputBinding
  reference : @value.ReferenceValue
  checked : @value.CheckedValue
}

///|
pub(all) enum EffectPublishedStoreTargetIssue {
  ForeignBinding
  IncompatibleReference
  Unavailable
} derive(Eq, Debug)

///|
/// The installation receives the original pair from this Command occurrence.
/// A separately resolved equal-CID pair cannot replace it. The supplied value
/// must already belong to the trusted ReferenceIssuer's original custody.
pub fn bind_effect_published_store_target(
  binding : EffectCommandInputBinding,
  pair : @environment.StoreCommandBinding,
  checked : @value.CheckedValue,
) -> Result[EffectPublishedStoreTarget, EffectPublishedStoreTargetIssue] {
  guard binding.target.store_binding is Some(original) &&
    physical_equal(original, pair) &&
    physical_equal(
      @environment.store_command_target(pair),
      binding.target.contract,
    ) else {
    return Err(ForeignBinding)
  }
  guard checked.value is @value.Reference(reference) else {
    return Err(IncompatibleReference)
  }
  if @contract.nonnull_resource_ref_kind(checked.contract) !=
    Some(@environment.command_target_resource_kind(binding.target.contract)) ||
    !@value.reference_compatible(reference, checked.contract) {
    return Err(IncompatibleReference)
  }
  if !@value.reference_available(reference) {
    return Err(Unavailable)
  }
  Ok({ binding, reference, checked, })
}

///|
/// Every use rechecks the original occurrence and its live issuer closure.
/// Equal selector bytes, a copied pair, or an expired issuer are not enough.
pub fn effect_published_store_target_current(
  original : EffectPublishedStoreTarget,
  binding : EffectCommandInputBinding,
) -> Bool {
  physical_equal(original.binding, binding) &&
  @value.reference_available(original.reference)
}
