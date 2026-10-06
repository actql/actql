# Graph material snapshot reference authority

## Repair boundary

The Graph material factory previously omitted the current Host `ReferenceIssuer`
when starting the existing snapshot reload. A graph containing an already
admitted `resource_ref` or `artifact_ref` could be saved, released and then fail
reload even though the same bytes and checked owner successfully reloaded through
the lower-level API with that issuer.

The existing material factory and Graph provider installation API now accept an
optional caller-supplied issuer. The provider passes that same capability through
both constructor and common Graph completion. The existing handoff, value
admission, Graph builder, canonical snapshot verification and completion owners
remain authoritative. The execution's alias is cleared after successful scratch
cleanup; a material factory already transferred to its consumer keeps the
capability it needs independently. Current evidence-validation and authorization
callbacks still run during reload. Neither serialized references, matching CIDs,
nor earlier admission success manufacture authority.

## Deliberate limits

The installed default Node Host currently has no reference issuer source in its
Graph provider selection. Generic row acquisition uses ordinary value admission,
which refuses opaque references without Host admission. The production retained
row decoder's reissuer resolves exact reference occurrences already in its own
custody; it is not a general Host issuer. This repair enables existing trusted
API callers to supply their current authority. It does not add public Node Host
reference-source admission or complete that integration.

The optional default preserves nonreference Graph callers. Reference reload
without an issuer remains fail-closed. The save/release/reload protocol does not
preflight future authorization before source release: the caller may explicitly
release its saved source and then fail reload because authority is missing,
foreign or revoked. Cleanup disposes private partial output and snapshot state;
it does not resurrect the released generation or reclaim borrowed producer
inputs. No recursive second type checker or recovery authority is introduced.

The new state is an alias to the caller-owned capability, not a new issuer,
reference ledger or copied capability graph. Existing installed workspace
reservations are unchanged. Their source-level bounds are not an exact model of
Host closure capture or total runtime heap size; this change does not claim such
a physical-memory proof.

## Regression coverage

The direct material-factory regression saves a current reference-keyed Graph,
checks the same-owner low-level positive control, releases the source, and
reloads through the actual factory. Provider regressions use independently sealed
SourceView schema/declaration provenance and exact-schema trusted cell admission.
They exercise constructor and normalize completion, resource and artifact
references in key/property roles, original issuer equality, current reissuance,
capable foreign-issuer rejection, missing authority, revocation after source
release, and partial-reload cleanup. Provider scratch cleanup occurs before
reload; transferred material and borrowed input custody are checked separately.

The existing nonreference snapshot, Graph provider custody and owner/consumer
cases remain selected verification targets. These focused checks do not certify
public Node Host reference admission, full Core, all-target execution, packed
consumers, or hosted CI.
