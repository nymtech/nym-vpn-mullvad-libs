import { IOpenVpnConstraints, IRelaySettingsNormal, IWireguardConstraints, Ownership, wrapConstraint } from '../../shared/daemon-rpc-types';
import { RelaySettingsRedux } from '../redux/settings/reducers';

export function toRawNormalRelaySettings(relaySettings: RelaySettingsRedux): IRelaySettingsNormal<IOpenVpnConstraints, IWireguardConstraints> {
  if ('normal' in relaySettings) {
    const openvpnPort = wrapConstraint(relaySettings.normal.openvpn.port);
    const openvpnProtocol = wrapConstraint(relaySettings.normal.openvpn.protocol);
    const wgPort = wrapConstraint(relaySettings.normal.wireguard.port);
    const wgIpVersion = wrapConstraint(relaySettings.normal.wireguard.ipVersion);
    const wgEntryLocation = wrapConstraint(relaySettings.normal.wireguard.entryLocation);
    const location = wrapConstraint(relaySettings.normal.location);
    const tunnelProtocol = wrapConstraint(relaySettings.normal.tunnelProtocol);

    return {
      providers: [...relaySettings.normal.providers],
      ownership: relaySettings.normal.ownership,
      tunnelProtocol,
      openvpnConstraints: {
        port: openvpnPort,
        protocol: openvpnProtocol,
      },
      wireguardConstraints: {
        port: wgPort,
        ipVersion: wgIpVersion,
        useMultihop: relaySettings.normal.wireguard.useMultihop,
        entryLocation: wgEntryLocation,
      },
      location,
    };
  }

  return {
    location: 'any',
    tunnelProtocol: 'any',
    providers: [],
    ownership: Ownership.any,
    openvpnConstraints: {
      port: 'any',
      protocol: 'any',
    },
    wireguardConstraints: {
      port: 'any',
      ipVersion: 'any',
      useMultihop: false,
      entryLocation: 'any',
    },
  };
}
