import {admitEnvironment, admitProfileSelection, admitEffectRunMaterials,
  type ProfileSelection} from '@actql/run-host-core';
import type {WorkersFiniteConfiguration} from '@actql/run-host-core/workers-finite';

const profiles: ProfileSelection = {rela: true, numericProfileCid: 'installed-profile'};
const selected = admitProfileSelection(profiles);
const rela: boolean = selected.rela;
const numeric: string | undefined = selected.numericProfileCid;
admitEnvironment('wire', 'environment', selected);
admitEffectRunMaterials('wire', 'original-definition', selected);
declare const originalEnvironment: WorkersFiniteConfiguration['environment'];
const environment: WorkersFiniteConfiguration['environment'] = {
  ...originalEnvironment, numeric_profile_cid: 'installed-profile',
};
void [rela, numeric, environment];

// @ts-expect-error Numeric profile selection is an exact CID, never a boolean grant.
admitEnvironment('wire', 'environment', {numericProfileCid: true});
// @ts-expect-error Omission does not become a mandatory available numeric profile.
const enabled: string = selected.numericProfileCid;
// @ts-expect-error The admitted selection remains immutable.
selected.numericProfileCid = 'replacement';
// @ts-expect-error Worker installation also uses the exact numeric profile identity.
const wrong: WorkersFiniteConfiguration['environment'] = {...originalEnvironment, numeric_profile_cid: true};
void [enabled, wrong];
