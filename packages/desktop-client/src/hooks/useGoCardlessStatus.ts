import { useEffect, useState } from 'react';

import { send } from '@actual-app/core/platform/client/connection';

import { useMetadataPref } from './useMetadataPref';
import { useSyncServerStatus } from './useSyncServerStatus';

export function useGoCardlessStatus() {
  const [configuredGoCardless, setConfiguredGoCardless] = useState<
    boolean | null
  >(null);
  const [isLoading, setIsLoading] = useState(false);
  const status = useSyncServerStatus();
  const [cloudFileId] = useMetadataPref('cloudFileId');

  useEffect(() => {
    async function fetch() {
      setIsLoading(true);

      const results = await send('gocardless-status', { fileId: cloudFileId });

      setConfiguredGoCardless(results.configured || false);
      setIsLoading(false);
    }

    if (status === 'online') {
      void fetch();
    }
  }, [status, cloudFileId]);

  return {
    configuredGoCardless,
    isLoading,
  };
}
