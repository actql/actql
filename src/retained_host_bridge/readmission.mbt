///|
/// Installed Host assembly only. The receipt check is fixed by that assembly,
/// not supplied by a Program or Connector execution request.
struct InstalledRetainedReadmission {
  port : @execution.TrustedRetainedReadmission[
    @execution.AdmittedOutputStreamReceipt,
  ]
  current : Ref[@execution.RetainedOutputHandle[Unit]?]
  live : Ref[Bool]
  permitted : () -> Bool
}

///|
suberror RetainedReadmissionFailure {
  Admission(@execution.TrustedOutputIssue)
}

///|
#export_name("retainedReadmissionInstall")
pub fn retained_readmission_install(
  preparation : @execution.CompletionPreparation,
  expected : @execution.RetainedCompletionDescriptor,
  accepts : (@execution.AdmittedOutputStreamReceipt) -> Bool,
  permitted : () -> Bool,
) -> InstalledRetainedReadmission raise RetainedReadmissionFailure {
  let facts = match
    @execution.prepare_retained_readmission_facts(
      preparation,
      expected,
      expected.rows,
      {
        producer_inputs: Some(100),
        schema_columns: Some(100),
        name_bytes: Some(10000),
      },
    ) {
    Ok(value) => value
    Err(issue) => raise Admission(issue)
  }
  let current : Ref[@execution.RetainedOutputHandle[Unit]?] = Ref(None)
  let live = Ref(true)
  let port = match
    @execution.prepare_trusted_retained_readmission(
      preparation,
      expected,
      facts,
      fn(receipt : @execution.AdmittedOutputStreamReceipt) {
        if !live.val || !permitted() || !accepts(receipt) {
          return None
        }
        guard current.val is Some(handle) else { return None }
        let material = @execution.retained_output_material(handle)
        if @execution.retained_output_matches_receipt(material, receipt) {
          Some(material)
        } else {
          None
        }
      },
    ) {
    Ok(port) => port
    Err(issue) => raise Admission(issue)
  }
  { port, current, live, permitted, }
}

///|
#export_name("retainedReadmissionComplete")
pub fn retained_readmission_complete(
  installed : InstalledRetainedReadmission,
  receipt : @execution.AdmittedOutputStreamReceipt,
) -> @execution.CompletedOutput raise RetainedReadmissionFailure {
  if !installed.live.val || installed.current.val is Some(_) {
    raise Admission(@execution.Unverified)
  }
  let live = installed.live
  let permitted = installed.permitted
  let handle = @execution.retain_admitted_output_stream(receipt, (), fn() {
    live.val && permitted()
  })
  installed.current.val = Some(handle)
  match @execution.readmit_trusted_retained_output(installed.port, receipt) {
    Ok(output) => output
    Err(issue) => raise Admission(issue)
  }
}

///|
#export_name("retainedReadmissionReadable")
pub fn retained_readmission_readable(
  installed : InstalledRetainedReadmission,
  input : @execution.ProducerRead,
) -> Bool {
  match installed.current.val {
    Some(handle) =>
      @execution.retained_producer_payload(handle, input) is Some(_)
    None => false
  }
}

///|
#export_name("retainedReadmissionClose")
pub fn retained_readmission_close(
  installed : InstalledRetainedReadmission,
) -> Unit {
  installed.live.val = false
}

///|
#export_name("retainedReadmissionFactsControlBytes")
pub fn retained_readmission_facts_control_bytes() -> Int64 {
  @execution.retained_readmission_facts_control_bytes()
}
