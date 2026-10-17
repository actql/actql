import {connect, type EmbeddedLocalOptions} from '@actql/node';
import {connect as connectLocal} from '@actql/local-node';

const embedded: EmbeddedLocalOptions = {mode: 'local',
  installation: {directory: '.actql'}};
void connect(embedded);
void connect({mode: 'local'});
void connect({mode: 'local', owner: 'local'});
void connectLocal({mode: 'local'});
void connectLocal({mode: 'local', owner: 'local'});

// @ts-expect-error A foreign owner is not an embedded Local provider selection.
void connect({mode: 'local', owner: 'cloud'});
// @ts-expect-error Null is not omitted ownership.
void connect({mode: 'local', owner: null});
// @ts-expect-error Direct Local does not select Hybrid.
void connectLocal({mode: 'hybrid', owner: 'local'});
// @ts-expect-error A Host/token is not embedded Local.
void connect({mode: 'local', token: 'type-only'});
