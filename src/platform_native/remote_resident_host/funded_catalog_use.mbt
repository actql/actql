///|
/// Select only this completed consumer's actual funded acceptance, retaining
/// the original producer Ledger and Journal. No candidate wire, pending-duty
/// boolean or missing Resource record can construct that nominal custody.
fn ResidentRetainedConsumer::funded_catalog_use_custody(
  self : ResidentRetainedConsumer,
  journal : @journal.Journal,
  producer : ResidentEffectProducerExecuted,
) -> Result[
  @journal.NativeInitialCatalogUseCustody,
  @journal.NativeRemoteJournalIssue,
] {
  guard self.effect_computation(journal) is Some(_) &&
    physical_equal(producer.executed.runtime, self.handoff.runtime) &&
    @remote.dispatch_request_identity(producer.executed.request) ==
    @remote.dispatch_request_identity(self.handoff.dispatch) &&
    producer.source_for_capture(self.producer_journal) is Some(_) &&
    self.initial_catalog_use.val is Some(custody) &&
    producer.owns_initial_catalog_use_custody(custody) &&
    @journal.initial_catalog_use_custody_dispatch(custody) ==
    @remote.dispatch_request_identity(self.request) else {
    return Err(@journal.StateCollision)
  }
  Ok(custody)
}

///|
/// This read is preparation for the existing Resource initial-claim hook, not
/// a claim or permission to GET. Current Host and credential fences remain
/// independent, and absence/uncertainty must not select a replacement use.
pub fn ResidentRetainedConsumer::read_initial_catalog_use(
  self : ResidentRetainedConsumer,
  journal : @journal.Journal,
  producer : ResidentEffectProducerExecuted,
) -> Result[Unit, @journal.NativeRemoteJournalIssue] {
  match self.funded_catalog_use_custody(journal, producer) {
    Ok(custody) => journal.read_funded_initial_catalog_use(custody)
    Err(issue) => Err(issue)
  }
}

///|
/// The actual Resource caller must retain this original nominal claim through
/// use selection and Journal confirmation. Failed/uncertain claims remain
/// pending; repeating this method cannot mint another initial eligibility.
pub fn ResidentRetainedConsumer::claim_initial_catalog_use(
  self : ResidentRetainedConsumer,
  journal : @journal.Journal,
  producer : ResidentEffectProducerExecuted,
) -> Result[
  @journal.NativeInitialCatalogUseClaim,
  @journal.NativeRemoteJournalIssue,
] {
  match self.funded_catalog_use_custody(journal, producer) {
    Ok(custody) => journal.claim_funded_initial_catalog_use(custody)
    Err(issue) => Err(issue)
  }
}
