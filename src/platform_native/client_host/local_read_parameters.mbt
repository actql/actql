///|
/// Original disclosure settings only. This metadata is not a grant, current
/// Account decision, expiry observation or permission to open another attempt.
pub(all) struct NativeLocalReadDisclosureParameters {
  purpose : String
  max_output_bytes : Int
}

///|
/// Read the purpose and ceiling from this Host's exact selected original. The
/// public CLI must not invent them from defaults or parse a current project as
/// a replacement. The existing request/admission/delivery owners still check
/// the Run, named Result, format, current permissions, time and original uses.
pub fn NativeLocalReadPolicyBinding::disclosure_parameters(
  self : NativeLocalReadPolicyBinding,
) -> Result[NativeLocalReadDisclosureParameters, NativeLocalReadBindingIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !self.selection.enabled {
    return Err(Disabled)
  }
  let parameters : NativeLocalReadDisclosureParameters = {
    purpose: self.selection.purpose,
    max_output_bytes: self.selection.max_bytes,
  }
  match self.require_current() {
    Ok(_) => Ok(parameters)
    Err(issue) => Err(issue)
  }
}
