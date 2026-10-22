///|
/// Generated-fragment integrity from completed typed construction. Runtime input obligations and
/// backend limits still have to be discharged before evaluating its kernel.
/// This is intentionally not an arbitrary saved-JSON execution entry.
priv struct CheckedFragment {
  candidate : FragmentCandidate
}

///|
pub(all) enum FragmentAdmissionIssue {
  InvalidContract
  Integrity
  Material(FragmentMaterialIssue)
  Artifact(RootArtifactIssue)
  Budget
}
