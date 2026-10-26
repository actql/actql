///|
/// Immutable installed data: asking for the pre-projection inventory does not
/// itself allocate another request-owned unit record. The installed bootstrap
/// funds the initial capacity check; subsequent quote construction is held on
/// that SAME preparation's execution reservation before any helper is called.
///
/// This is a conservative constructor-callsite envelope, NOT a lexical-variable
/// census, runtime frame price, represented input-buffer allocation, or RSS
/// claim. Each branch's actual record/tuple/Array/Option constructors is counted
/// conservatively; all five phases are summed even though they are sequential.
/// The frozen baseline additionally retains harmless bare-None branch-block
/// census slack; those inline tags are not actual allocated records. No new
/// tariff is assigned to them, and this change does not spend that slack.
/// Unit records have five words. Composite record fields are conservatively
/// counted as both references and words. Scalar arithmetic Some carriers have
/// one header and two words. Literal arrays own wrapper/backing and their exact
/// slots. Fixed nonrecursive VM frames are the installed execution baseline.
///
/// Call-expanded (headers, refs, words), including literal sum-array lengths:
///   text eligibility setup       (  53,   56,  102)
///   snapshot + intent             ( 298,  128,  689)
///   source + generic guard quote  ( 166,   71,  368)
///   Program decoder quote         (  68,   39,  159)
///   Context + compiler + plan     (3601, 1290, 8043)
/// = (4186,1584,9361). The metadata projector has four fixed templates;
/// their inner sum calls execute 2*(1+3+3+7)=28 times. Numeric capacity/sort
/// loops allocate no per-iteration containers. Shared writer count14 is an
/// arithmetic multiplicity, not fourteen calls. No F/R-sized unit array exists.
///
/// Installed Catalog eligibility adds (313,363,315):
/// - 43 field_at calls, each Cursor/tuple/closure/two Some: 43*(5,7,3);
/// - 40 scalar readers, conservatively 40*(2,1,4);
/// - four object_length Some: (4,0,8);
/// - dependency record/Some and source-usage tuple: (3,1,7);
/// - two catalog Result carriers plus required-reuse wrapper: (3,6,4);
/// - one failing diagnostic path of depth<=3: (8,15,7).
/// Environment read.mbt constructs policy from the standalone admitted root's
/// host_policy_profile: component depth2, scalar depth3. No foreign nested
/// Cursor is accepted as that installed WireEnvironment. Registry/reference
/// scans borrow original arrays and are independently work-bounded.
///
/// Finally two later initial-control-capacity calls tariff this immutable
/// recipe: ten arithmetic Some carriers add (10,0,20). Its original first
/// pricing call belongs to the existing installed bootstrap, not this child.
/// This deliberate cumulative slack is reported rather than hidden in a new
/// allowance. Keep this execution slice through every growth until projection
/// and constructor locals have unwound; it is never a second resource pool.
/// Identity specialization adds four shared-writer calls, not new represented
/// writer buffers: each call's unit/hash/checked-add/Result constructors are
/// (14,12,34). Its five-item literal Array adds (2,6,2), and the five-item
/// sum's unit/Some plus30 arithmetic Some carriers add (32,1,66).
/// Additional projection owners: (90,55,204), or3512 logical bytes. Bare None
/// tags are explicitly excluded from this delta. All former phase slack stays.
/// Intent lifetime composition keeps JS/Core constructor peaks separate. Its
/// quote helpers still allocate before growth, so append the following fixed
/// construction packets without reclaiming any old phase census slack:
/// - new intent recipe delta (37,20,88), including its spread unit record;
/// - snapshot second sum2 + literal Array + two tariffs (29,14,58);
/// - source two extra tariffs (10,10,20); old sum5 remains conservative for3;
/// - two complete initial-control-capacity calls (54,60,134), including their
///   original control Units, four tariffs each, policy/scan/header carriers;
/// - three execution-peak Some carriers (3,3,6);
/// - original-bound intent's extra source-facts call (2,1,12);
/// - four additional refusal alternatives (4,4,8).
/// This additive envelope does not use fixed VM frames or allocate represented
/// matrices. Sequential phase overlap credit applies only to returned constructor
/// owners, never to the quote constructors funded by this original fixed slice.
/// Authored sequence demand adds two unit records (2,0,10), two list slots
/// (0,2,0), and ten checked-add Some carriers (10,0,20) to the compiler
/// projector. Additional fixed quote scratch (12,2,30),448 logical bytes.
/// Funded compilation quote construction adds a finite call-expanded packet.
/// This prices the SMALL descriptors/Arrays/Some values created by projection,
/// not the represented source/canonical/writer payload and not VM call frames.
/// Families (calls * headers/references/words):
/// -112 sum+literal-array scopes, each <=13 items:112*(74,15,148).
///   These cover54 parse sums,46 metadata repetition sums,2 final metadata,
///   3 outer sums,2 Program emitter,2 contract emitter,1 witness,2 ancestry
///   wrapper scopes; one ancestry scope is conservative sequential slack.
/// -18 parse projections (13 metadata +5 large):18*(36,18,116).
/// -16 shared writer envelopes:16*(14,2,32), plus two ancestry wrapper
///   descriptors:2*(16,2,42). The second wrapper is conservative slack.
/// -3 other repeat-unit projections:3*(12,1,26).
/// -30 metadata facts (including7-scalar tuple):30*(3,1,18).
/// -2 metadata shape sums/literal Arrays:2*(4,15,26).
/// -metadata direct records/arrays/carriers:(25,11,126).
/// -outer shape/parts/wire/cell/return descriptors:(33,21,165).
/// -Program emitter descriptor:(11,3,43);2 Number contract descriptors:
///   2*(3,1,11);2 canonical emitter descriptors:2*(7,1,16).
/// -artifact descriptor:(7,1,16); witness descriptor including the append
///   capacity Some:(20,3,55); added body tariff/list/error carriers:(12,2,21).
/// Sum=(9454,2148,20410),331728 logical bytes. All loops have fixed13-family,
///23-repetition or<=13-element bounds; no F/R-sized quote collection exists.
/// The source guard pins helper bodies and this table's cardinalities.
let closed_values_projection_scratch_original : @execution.PreparationRepresentationUnits = {
  record_headers: 4186L + 313L + 10L + 90L + 139L + 12L + 9454L,
  reference_slots: 1584L + 363L + 55L + 112L + 2L + 2148L,
  scalar_words: 9361L + 315L + 20L + 204L + 326L + 30L + 20410L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
fn closed_values_projection_scratch_units() -> @execution.PreparationRepresentationUnits {
  closed_values_projection_scratch_original
}
