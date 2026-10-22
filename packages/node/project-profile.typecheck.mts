import type {EmbeddedLocalOptions,NodeConnectionOptions,OpenOptions} from '@actql/node';
import type {connect as connectLocal} from '@actql/local-node';

const selected={mode:'local',profile:'mock'} satisfies EmbeddedLocalOptions;
const omitted={mode:'local'} satisfies EmbeddedLocalOptions;
const provider={mode:'local',profile:'mock'} satisfies Parameters<typeof connectLocal>[0];
const opened={stateDir:'.actql',profile:'mock'} satisfies OpenOptions;
// @ts-expect-error A profile is an original String choice, not an allowance flag.
const booleanProfile:EmbeddedLocalOptions={mode:'local',profile:false};
// @ts-expect-error Null is not original absence.
const nullProfile:EmbeddedLocalOptions={mode:'local',profile:null};
// @ts-expect-error Project profile selection belongs to embedded Local, not a Remote transport packet.
const remoteProfile:NodeConnectionOptions={mode:'remote',endpoint:'https://host.example/',token:'fixture',profile:'mock'};
void[selected,omitted,provider,opened,booleanProfile,nullProfile,remoteProfile];
