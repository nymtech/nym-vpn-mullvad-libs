import React, { useContext, useEffect, useRef } from 'react';

import log from '../../shared/logging';

// This context tells its subtree if it should stop rendering or not. This is useful during
// transitions, e.g. on log out, since data might be updated which makes the disappearing view
// update a lot during the transition. There's currently no support for unpausing, which can be
// added later if needed.
const willExitContext = React.createContext<boolean>(false);

// export const WillExit = willExitContext.Provider;
export function WillExit(props: { value: boolean; children: React.ReactNode }) {
  const prevValue = useRef(false);
  if (prevValue.current !== props.value) {
    log.info('willExit set to', props.value);
  }
  prevValue.current = props.value;

  useEffect(() => {
    return () => log.info('willExit set to false by unmount');
  }, []);

  return <willExitContext.Provider value={props.value}>{props.children}</willExitContext.Provider>;
}

export function useWillExit() {
  return useContext(willExitContext);
}
