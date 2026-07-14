import { useEffect, useState } from 'react';

import { send } from '@actual-app/core/platform/client/connection';

import { useMetadataPref } from './useMetadataPref';
import { useSyncServerStatus } from './useSyncServerStatus';

export function useSimpleFinStatus() {
  const [configuredSimpleFin, setConfiguredSimpleFin] = useState<
    boolean | null
  >(null);
  const [isLoading, setIsLoading] = useState(false);
  const status = useSyncServerStatus();
  const [cloudFileId] = useMetadataPref('cloudFileId');

  useEffect(() => {
    async function fetch() {
      setIsLoading(true);

      const results = await send('simplefin-status', { fileId: cloudFileId });

      setConfiguredSimpleFin(results.configured || false);
      setIsLoading(false);
    }

    if (status === 'online') {
      void fetch();
    }
  }, [status, cloudFileId]);

  return {
    configuredSimpleFin,
    isLoading,
  };
}
