import type {EmbeddedLocalOptions,NodeConnectionOptions} from './index.mjs';
import type {connect as connectLocal} from '../local-node/index.mjs';

const selected={mode:'local',profile:'mock'} satisfies EmbeddedLocalOptions;
const omitted={mode:'local'} satisfies EmbeddedLocalOptions;
const provider={mode:'local',profile:'mock'} satisfies Parameters<typeof connectLocal>[0];
// @ts-expect-error A profile is an original String choice, not an allowance flag.
const booleanProfile:EmbeddedLocalOptions={mode:'local',profile:false};
// @ts-expect-error Null is not original absence.
const nullProfile:EmbeddedLocalOptions={mode:'local',profile:null};
// @ts-expect-error Project profile selection belongs to embedded Local, not a Remote transport packet.
const remoteProfile:NodeConnectionOptions={mode:'remote',endpoint:'https://host.example/',token:'fixture',profile:'mock'};
void[selected,omitted,provider,booleanProfile,nullProfile,remoteProfile];
