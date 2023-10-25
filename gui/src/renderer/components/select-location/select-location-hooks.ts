import { useCallback } from 'react';

import BridgeSettingsBuilder from '../../../shared/bridge-settings-builder';
import {
  BridgeSettings,
  RelayLocation,
  RelaySettings,
} from '../../../shared/daemon-rpc-types';
import log from '../../../shared/logging';
import { useAppContext } from '../../context';
import { toRawNormalRelaySettings } from '../../lib/constraint-updater';
import { useHistory } from '../../lib/history';
import { useSelector } from '../../redux/store';
import { LocationType, SpecialBridgeLocationType } from './select-location-types';
import { useSelectLocationContext } from './SelectLocationContainer';

export function useOnSelectExitLocation() {
  const onSelectLocation = useOnSelectLocation();
  const history = useHistory();
  const relaySettings = useSelector((state) => state.settings.relaySettings);
  const { connectTunnel } = useAppContext();

  const onSelectRelay = useCallback(
    async (relayLocation: RelayLocation) => {
      history.pop();
      const settings = toRawNormalRelaySettings(relaySettings);
      settings.location = { only: relayLocation };
      await onSelectLocation({ normal: settings });
      await connectTunnel();
    },
    [history, relaySettings],
  );

  const onSelectSpecial = useCallback((_location: undefined) => {
    throw new Error('relayLocation should never be undefined');
  }, []);

  return [onSelectRelay, onSelectSpecial] as const;
}

export function useOnSelectEntryLocation() {
  const onSelectLocation = useOnSelectLocation();
  const { setLocationType } = useSelectLocationContext();
  const baseRelaySettings = useSelector((state) => state.settings.relaySettings);

  const onSelectRelay = useCallback(async (entryLocation: RelayLocation) => {
    setLocationType(LocationType.exit);
    const settings = toRawNormalRelaySettings(baseRelaySettings);
    settings.wireguardConstraints.entryLocation = { only: entryLocation };
    await onSelectLocation({ normal: settings });
  }, []);

  const onSelectSpecial = useCallback(async (_location: 'any') => {
    setLocationType(LocationType.exit);
    const settings = toRawNormalRelaySettings(baseRelaySettings);
    settings.wireguardConstraints.entryLocation = 'any';
    await onSelectLocation({ normal: settings });
  }, []);

  return [onSelectRelay, onSelectSpecial] as const;
}

function useOnSelectLocation() {
  const { updateRelaySettings } = useAppContext();

  return useCallback(async (relaySettings: RelaySettings) => {
    try {
      await updateRelaySettings(relaySettings);
    } catch (e) {
      const error = e as Error;
      log.error(`Failed to select the exit location: ${error.message}`);
    }
  }, []);
}

export function useOnSelectBridgeLocation() {
  const { updateBridgeSettings } = useAppContext();
  const { setLocationType } = useSelectLocationContext();

  const setLocation = useCallback(async (bridgeUpdate: BridgeSettings) => {
    if (bridgeUpdate) {
      setLocationType(LocationType.exit);
      try {
        await updateBridgeSettings(bridgeUpdate);
      } catch (e) {
        const error = e as Error;
        log.error(`Failed to select the bridge location: ${error.message}`);
      }
    }
  }, []);

  const onSelectRelay = useCallback((location: RelayLocation) => {
    const bridgeUpdate = new BridgeSettingsBuilder().location.fromRaw(location).build();
    return setLocation(bridgeUpdate);
  }, []);

  const onSelectSpecial = useCallback((location: SpecialBridgeLocationType) => {
    switch (location) {
      case SpecialBridgeLocationType.closestToExit: {
        const bridgeUpdate = new BridgeSettingsBuilder().location.any().build();
        return setLocation(bridgeUpdate);
      }
    }
  }, []);

  return [onSelectRelay, onSelectSpecial] as const;
}
