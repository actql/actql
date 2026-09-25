///|
/// Wire version accepted by the JSON decoder.
pub const ACCOUNT_CONFIG_VERSION : String = "actql-execution-account-config/0.1"

///|
/// Largest encoded configuration accepted by the JSON decoder (UTF-8 bytes).
pub const MAX_CONFIG_INPUT_BYTES : Int = 1048576

///|
/// Largest number of entries in one account configuration.
pub const MAX_ENTRIES : Int = 1024

///|
/// Largest number of exclusion boxes attached to one entry.
pub const MAX_EXCLUSIONS_PER_ENTRY : Int = 64

///|
/// Largest number of named values in one `any_of` selector.
pub const MAX_SELECTOR_VALUES : Int = 256

///|
/// Largest UTF-16 length of an identifier or selector value.
pub const MAX_NAME_LENGTH : Int = 512

///|
/// Work budget of the exact overlap check for one configuration. Each pair of
/// differing-outcome entries and each region split step is charged one unit
/// plus the number of named values its set operations may visit. Exceeding
/// the budget rejects the configuration; the check never approximates.
pub const MAX_OVERLAP_WORK : Int = 32000000

///|
/// One coordinate of the configuration address tuple.
pub(all) enum Dimension {
  Principal
  Connection
  Resource
  Operation
} derive(Eq, Debug)

///|
/// A selector over one dimension of an open universe. `All` is an explicit
/// broad selection that also contains values not named anywhere, including
/// future members. `AnyOf` is a non-empty finite set of distinct values; the
/// order of values is not significant.
pub(all) enum Selector {
  All
  AnyOf(Array[String])
} derive(Eq, Debug)

///|
/// A Cartesian selection principal × connection × resource × operation.
pub(all) struct SelectorBox {
  principal : Selector
  connection : Selector
  resource : Selector
  operation : Selector
} derive(Eq, Debug)

///|
/// Configured outcome of an entry. `Delegate` selects who decides; it is not
/// a third final permission.
pub(all) enum ConfiguredOutcome {
  Allow
  Deny
  Delegate
} derive(Eq, Debug)

///|
/// An unadmitted entry. It denotes `scope` minus the union of `exclusions`
/// over the open tuple universe.
pub(all) struct RawAccountEntry {
  entry_id : String
  outcome : ConfiguredOutcome
  scope : SelectorBox
  exclusions : Array[SelectorBox]
} derive(Eq, Debug)

///|
/// Identity of a published, versioned bootstrap profile. It is provenance
/// only; the core never generates configuration from it.
pub(all) struct BootstrapProfile {
  profile_id : String
  profile_version : String
  profile_cid : String
} derive(Eq, Debug)

///|
/// An unadmitted account configuration.
pub(all) struct RawAccountConfiguration {
  account_id : String
  entries : Array[RawAccountEntry]
  bootstrap : BootstrapProfile?
} derive(Eq, Debug)

///|
/// A concrete configuration address.
pub(all) struct AccessTuple {
  principal : String
  connection : String
  resource : String
  operation : String
} derive(Eq, Debug)

///|
/// Where a selector sits inside an entry.
pub(all) enum SelectorLocation {
  Scope(Dimension)
  Exclusion(Int, Dimension)
} derive(Eq, Debug)

///|
/// One coordinate of an overlap witness. `AnyOtherThan(names)` stands for any
/// value outside `names` (every value when `names` is empty); such a value
/// may not be discovered yet.
pub(all) enum WitnessValue {
  Named(String)
  AnyOtherThan(Array[String])
} derive(Eq, Debug)

///|
/// A tuple contained in both conflicting effective scopes.
pub(all) struct WitnessTuple {
  principal : WitnessValue
  connection : WitnessValue
  resource : WitnessValue
  operation : WitnessValue
} derive(Eq, Debug)

///|
/// Two entries with different outcomes whose effective scopes intersect.
/// `first_entry_id` precedes `second_entry_id` in admitted entry order.
pub(all) struct OutcomeConflict {
  first_entry_id : String
  first_outcome : ConfiguredOutcome
  second_entry_id : String
  second_outcome : ConfiguredOutcome
  witness : WitnessTuple
} derive(Eq, Debug)

///|
pub(all) enum WireIssueKind {
  InputTooLarge
  InvalidJson
  InvalidShape
  UnsupportedVersion
} derive(Eq, Debug)

///|
/// A JSON decoding failure; `path` is a JSONPath-like location.
pub(all) struct WireIssue {
  kind : WireIssueKind
  path : String
} derive(Eq, Debug)

///|
/// Reasons a configuration is not admitted. A rejected configuration grants
/// nothing.
pub(all) enum ConfigurationIssue {
  MalformedWire(WireIssue)
  InvalidAccountId
  InvalidBootstrapProfile
  TooManyEntries(Int)
  InvalidEntryId(Int)
  DuplicateEntryId(String)
  TooManyExclusions(String)
  EmptyAnyOf(String, SelectorLocation)
  InvalidSelectorValue(String, SelectorLocation)
  DuplicateSelectorValue(String, SelectorLocation, String)
  SelectorTooLarge(String, SelectorLocation)
  ConflictingOutcomes(OutcomeConflict)
  OverlapCheckBudgetExceeded(String, String)
} derive(Eq, Debug)

///|
/// Why an account outcome denies.
pub(all) enum DenyReason {
  NoMatch
  Explicit(String)
  ConfigurationMissing
} derive(Eq, Debug)

///|
/// A tuple matched by a delegate entry. Only `evaluate_account` creates it, so
/// a decision request can never be prepared for an allow or deny outcome.
pub struct DelegatedMatch {
  account_id : String
  entry_id : String
  tuple : AccessTuple
} derive(Eq, Debug)

///|
/// The account-configuration outcome for one concrete tuple. Constructed only
/// by this package.
pub enum AccountOutcome {
  Allow(String)
  Deny(DenyReason)
  Delegate(DelegatedMatch)
} derive(Eq, Debug)
