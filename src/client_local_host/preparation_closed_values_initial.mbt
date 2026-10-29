///|
pub(all) enum ClientClosedValuesPreparationIssue {
  ForeignOriginal
  WrongPhase
  Policy
  Syntax(@syntax.SyntaxError)
  Preparation(@publication_host.ClientProgramPreparationIssue)
  Installed(ClientInstalledManagedRunIssue)
  Compilation(@publication_host.ClientValuesCompilationIssue)
  Initial(@resources.ImportedChildLedgerIssue)
  Capacity(@resources.PreparationCapacityIssue)
  Work(@resources.PreparationWorkIssue)
  CapacityExceeded(ClientPreparationCapacityRefusal)
  Intent(@publication_host.ClientSubmittedIntentIssue)
  PublicationInvocation(@publication.RunEvidenceValueIssue)
  PublicationCapture(@publication.CapturedRunIssuanceIssue)
  PublicationSnapshot(@publication_host.PublicationOutputExportIssue)
}
