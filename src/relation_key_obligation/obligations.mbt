///|
pub(all) enum KeyObligation {
  ValidateKeyProducer
  AdmitPresentNonNullComparableComponents
  ValidateWholeTupleUniquenessAfterInputNormalization
  RevalidateReferenceComponents
} derive(Eq, Debug)
