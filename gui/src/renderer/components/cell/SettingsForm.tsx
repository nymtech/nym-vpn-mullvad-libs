import React, { useCallback, useContext, useEffect, useMemo, useState } from 'react';

interface SettingsFormContext {
  formSubmittable: boolean;
  reportInputSubmittable: (key: string, submittable: boolean) => void;
  removeInput: (key: string) => void;
}

const settingsFormContext = React.createContext<SettingsFormContext | undefined>(undefined);

let keyCounter = 0;
function getInputKey() {
  return ++keyCounter;
}

function useSettingsFormContext() {
  return useContext(settingsFormContext);
}

export function useSettingsFormSubmittable() {
  const context = useSettingsFormContext();
  return context?.formSubmittable ?? true;
}

export function useSettingsFormSubmittableReporter() {
  const context = useSettingsFormContext();
  const key = useMemo(() => `input-${getInputKey()}`, []);

  const reportInputSubmittable = useCallback(
    (submittable: boolean) => {
      context?.reportInputSubmittable(key, submittable);
    },
    [context?.reportInputSubmittable],
  );

  useEffect(() => () => context?.removeInput(key), []);

  return reportInputSubmittable;
}

export function SettingsForm(props: React.PropsWithChildren) {
  const [inputStatuses, setInputStatuses] = useState<Record<string, boolean>>({});

  const reportInputSubmittable = useCallback((key: string, submittable: boolean) => {
    setInputStatuses((prevInputStatuses) => ({ ...prevInputStatuses, [key]: submittable }));
  }, []);

  const removeInput = useCallback((key: string) => {
    setInputStatuses((prevInputStatuses) => {
      const { [key]: _, ...inputStatuses } = prevInputStatuses;
      return inputStatuses;
    });
  }, []);

  const value = useMemo(
    () => ({
      formSubmittable: Object.values(inputStatuses).every((item) => item === true),
      reportInputSubmittable,
      removeInput,
    }),
    [inputStatuses, removeInput, reportInputSubmittable],
  );

  return (
    <settingsFormContext.Provider value={value}>{props.children}</settingsFormContext.Provider>
  );
}
