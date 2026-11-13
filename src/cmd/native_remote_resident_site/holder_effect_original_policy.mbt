///|
/// Borrowed original preparation facts for the installed Provider policy. This
/// is not another custody Owner or permission: Runtime, journal, receiver and
/// consumer retain all resources. No proposed wire supplies these materials.
priv struct HolderEffectOriginalPolicyContext {
  task : HolderTaskCustody
  producer_task : HolderTaskCustody
  consumer : @resident_host.ResidentRetainedConsumer
  producer : @resident_host.ResidentEffectProducerExecuted
  journal : @journal.Journal
  request : @host.ClientRequestIdentity
  materials : @host.ClientEffectRunMaterials
}

///|
/// Missing operator installation denies evidence before original-context reads.
/// The present path passes the same selected values to the existing authority
/// boundary; this helper supplies no custody, currentness or cleanup evidence.
/// Select again after context callbacks at the original installation fence.
fn[Installation, Original] holder_effect_installed_evidence(
  installation : () -> Installation?,
  original : () -> Original?,
  authorize : (Installation, Original) -> Bool,
) -> Bool {
  guard installation() is Some(_) &&
    original() is Some(selected) &&
    installation() is Some(installed) else {
    return false
  }
  authorize(installed, selected)
}

///|
/// Select only the producer already recorded on the admitted retained edge.
/// Both existing physical Owners must still expose the same original request.
/// Missing restored custody is unavailable, never permission to reprepare.
fn holder_effect_original_policy_context(
  task : HolderTaskCustody,
  tasks : Map[String, HolderTaskCustody],
  journal : @journal.Journal,
) -> HolderEffectOriginalPolicyContext? {
  guard !task.released &&
    !task.release_requested &&
    task.consumer is Some(consumer) &&
    task.producer_identity is Some(identity) &&
    tasks.get(identity) is Some(producer_task) &&
    @remote.dispatch_request_identity(producer_task.request) == identity &&
    !producer_task.released &&
    !producer_task.release_requested &&
    producer_task.effect_producer is Some(producer) &&
    producer.materials_for_capture(journal) is Some(materials) &&
    producer.request_for_capture(journal) is Some(request) &&
    consumer.effect_computation(journal) is Some(computation) &&
    computation.effect_materials_for_capture() is Some(admitted) &&
    admitted.request == Some(request) else {
    return None
  }
  Some({ task, producer_task, consumer, producer, journal, request, materials, })
}

///|
/// Recheck after a configured Catalog/Provider policy read. Cancellation,
/// retirement or changed holder custody cannot grant evidence permission.
fn HolderEffectOriginalPolicyContext::current(
  self : HolderEffectOriginalPolicyContext,
) -> Bool {
  guard !self.task.released &&
    !self.task.release_requested &&
    !self.producer_task.released &&
    !self.producer_task.release_requested &&
    self.task.producer_identity ==
    Some(@remote.dispatch_request_identity(self.producer_task.request)) &&
    self.task.consumer is Some(consumer) &&
    physical_equal(consumer, self.consumer) &&
    self.producer_task.effect_producer is Some(producer) &&
    physical_equal(producer, self.producer) &&
    producer.materials_for_capture(self.journal) is Some(materials) &&
    physical_equal(materials.prepared, self.materials.prepared) &&
    producer.request_for_capture(self.journal) == Some(self.request) &&
    consumer.effect_computation(self.journal) is Some(computation) &&
    computation.effect_materials_for_capture() is Some(admitted) &&
    admitted.request == Some(self.request) else {
    return false
  }
  true
}
