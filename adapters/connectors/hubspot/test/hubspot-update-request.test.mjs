import * as moon from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {registerHubSpotUpdateRequestTests, registerHubSpotTargetReadOriginalTests} from './hubspot-update-request.fixture.mjs';
registerHubSpotUpdateRequestTests(moon);
registerHubSpotTargetReadOriginalTests(moon);
