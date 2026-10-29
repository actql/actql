///|
/// Original structural Program and checker inputs after the existing input
/// restrictions, Catalog provenance and definition evidence binding. This is
/// NOT a CheckedProgram, successful semantic verdict or execution permission.
/// Materials are the SAME binder's owned consumer arrays and exact admitted
/// HostSources/LimitClaim owners, not the caller's mutable registration array.
/// The environment, supplied Cursor, limits, original Source and optional Catalog stay attached
/// through the ordinary semantic constructor; none is selected again by CID.
pub struct ParsedCheckInput {
  program : @syntax.Program
  environment : CheckEnvironment
  priv supplied : @decode.Cursor?
  priv inputs : @context.ProgramCapacityInputs
  priv limits : CompileLimits
  priv source_catalog : PreparedSourceCatalog?
  priv source_preparation : @stages.Source?
}

///|
/// Caller must fund the actual capacity-input binder and all borrowed input
/// dependencies BEFORE this constructor. The fixed Local profile separately
/// funds its added holder. Generic binder/semantic backing is not supplied by
/// this DATA API or its retained-control descriptor.
pub fn prepare_parsed_check_input(
  program : @syntax.Program,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : CheckLimits,
  source_catalog? : PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
) -> Result[ParsedCheckInput, LocalConstructionFailure] {
  Ok(
    prepare_parsed_check_input_owned(
      program,
      environment,
      supplied,
      evidence,
      limits,
      source_catalog~,
      source_preparation~,
    ),
  ) catch {
    issue => Err(issue)
  }
}

///|
/// Continue the original full semantic checker, after its complete next-phase
/// backing has been funded by the same preparation owner. No parsing, input
/// admission or definition-evidence binding is repeated. A new/tighter request
/// must prepare its own original inputs; this is not a blanket reusable Allow.
pub fn finish_parsed_check_input(original : ParsedCheckInput) -> CheckOutcome {
  checking_outcome(original.program, original.environment, () => {
    finish_parsed_check_input_owned(original)
  })
}

///|
/// Original binder work only. Later compiler work and Ledger dispatch/attempts
/// remain their separate meters. This observes DATA, not a policy or grant.
pub fn parsed_check_input_binding_work(original : ParsedCheckInput) -> Int {
  @context.capacity_inputs_work(original.inputs)
}

///|
pub(all) struct ParsedCheckInputRetainedControlExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
/// Only this actual holder1H7R. Bound-material arrays, original Program/index,
/// supplied values, Environment/Catalog and phase/Result controls retain their
/// own inventories. Read installed DATA before constructing the holder.
pub fn parsed_check_input_retained_control_extent() -> ParsedCheckInputRetainedControlExtent {
  parsed_check_input_controls
}

///|
let parsed_check_input_controls : ParsedCheckInputRetainedControlExtent = {
  record_headers: 1L,
  reference_slots: 7L,
  scalar_words: 0L,
}

///|
/// Same typed preparation, plus exact original binder work even on failure.
/// Precheck-only refusals report zero binder work. Its Ref/Some/tuple/Result
/// controls belong to the funded original caller, not the retained holder.
pub fn observe_parsed_check_input_preparation(
  program : @syntax.Program,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : CheckLimits,
  source_catalog? : PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
) -> (Result[ParsedCheckInput, LocalConstructionFailure], Int) {
  let work = Ref(0)
  let result = Ok(
    prepare_parsed_check_input_owned(
      program,
      environment,
      supplied,
      evidence,
      limits,
      source_catalog~,
      source_preparation~,
      binding_work_out=Some(work),
    ),
  ) catch {
    issue => Err(issue)
  }
  (result, work.val)
}
