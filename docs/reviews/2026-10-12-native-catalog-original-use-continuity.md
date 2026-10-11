# Original Catalog-use restoration

The resident caller no longer interprets a missing credential use plus a missing
Checkpoint as permission for a first GET. A replacement or unreadable credential
DB cannot supply that proof. Process-local `read_started` also proves no original
eligibility.

The existing original Journal `effect_catalog_use` Owner reads the nominal use
for the selected original consumer request, configured grant and use ID. Its
existing admission validates the immutable dispatch, Run/task/attempt, runtime,
Site generation, grant/use body and CID. The retained original holder context is
checked around this read. Before and after the existing Resource read-only query,
the caller reads that same Journal witness and matches its nominal use CID to
the Resource status. Resource outcome and original custody errors remain
separate; claimed/unknown are not a successful Catalog response.

Missing, foreign, replaced or unconfirmed original evidence stays pending in the
same Catalog/task custody. Cleanup cannot treat a failed query as absence of an
older response/Store holding. The same restoration tick can repeat its read-only
query, but no branch issues a new grant, claim, reservation or Provider call.
Existing original Store restoration and cleanup remain the only adopted paths.

The first nominal Catalog claim is intentionally still an unfinished production
connection. It will use the funded initial accept custody and Resource pre-send
Journal retention hook after their dependency is adopted. This change does not
ban initial Catalog reads or change the language contract. It removes an unsafe
absence-based shortcut until the legitimate original proof is supplied. Root's
Journal/Host initial-custody files and D's Resource files are unchanged.

The affected Native caller and five counterexamples are compile-only: absent
original witness means no Resource query; unavailable original reasons; foreign
Resource use or changed witness; replacement DB/claimed/unknown status; and
original generation/custody change after the Resource query. Nominal fixtures
use the Common issuer, while injected statuses are caller diagnostics, not
physical Resource or Provider success. No SQLite/TLS/Provider/public Effect,
Heavy, Hosted CI or deployment is performed for this finite unit.
