import { useCallback } from 'react';
import { IOpenVpnConstraints, IRelaySettingsNormal, IWireguardConstraints, Ownership, wrapConstraint } from '../../shared/daemon-rpc-types';
import { NormalRelaySettingsRedux } from '../redux/settings/reducers';
import { useNormalRelaySettings } from './utilityHooks';
import { useAppContext } from '../context';

export function wrapRelaySettingsOrDefault(relaySettings?: NormalRelaySettingsRedux): IRelaySettingsNormal<IOpenVpnConstraints, IWireguardConstraints> {
  if (relaySettings) {
    const openvpnPort = wrapConstraint(relaySettings.openvpn.port);
    const openvpnProtocol = wrapConstraint(relaySettings.openvpn.protocol);
    const wgPort = wrapConstraint(relaySettings.wireguard.port);
    const wgIpVersion = wrapConstraint(relaySettings.wireguard.ipVersion);
    const wgEntryLocation = wrapConstraint(relaySettings.wireguard.entryLocation);
    const location = wrapConstraint(relaySettings.location);
    const tunnelProtocol = wrapConstraint(relaySettings.tunnelProtocol);

    return {
      providers: [...relaySettings.providers],
      ownership: relaySettings.ownership,
      tunnelProtocol,
      openvpnConstraints: {
        port: openvpnPort,
        protocol: openvpnProtocol,
      },
      wireguardConstraints: {
        port: wgPort,
        ipVersion: wgIpVersion,
        useMultihop: relaySettings.wireguard.useMultihop,
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

export function useRelaySettingsModifier() {
  const relaySettings = useNormalRelaySettings();

  return useCallback((fn: (settings: IRelaySettingsNormal<IOpenVpnConstraints, IWireguardConstraints>) => IRelaySettingsNormal<IOpenVpnConstraints, IWireguardConstraints>) => {
    const settings = wrapRelaySettingsOrDefault(relaySettings);
    return fn(settings);
  }, [relaySettings]);
}

export function useRelaySettingsUpdater() {
  const { updateRelaySettings } = useAppContext();
  const modifyRelaySettings = useRelaySettingsModifier();

  return useCallback((fn: (settings: IRelaySettingsNormal<IOpenVpnConstraints, IWireguardConstraints>) => IRelaySettingsNormal<IOpenVpnConstraints, IWireguardConstraints>) => {
    const modifiedSettings = modifyRelaySettings(fn);
    updateRelaySettings({ normal: modifiedSettings });
  }, [updateRelaySettings, modifyRelaySettings]);
}
