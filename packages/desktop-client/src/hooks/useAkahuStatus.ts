import { useEffect, useState } from 'react';

import { send } from '@actual-app/core/platform/client/connection';

import { useMetadataPref } from './useMetadataPref';
import { useSyncServerStatus } from './useSyncServerStatus';

export function useAkahuStatus(enabled = true) {
  const [configuredAkahu, setConfiguredAkahu] = useState<boolean | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const status = useSyncServerStatus();
  const [cloudFileId] = useMetadataPref('cloudFileId');

  useEffect(() => {
    if (!enabled) return;

    async function fetch() {
      setIsLoading(true);

      const results = await send('akahu-status', { fileId: cloudFileId });

      setConfiguredAkahu(results.configured || false);
      setIsLoading(false);
    }

    if (status === 'online') {
      void fetch();
    }
  }, [status, enabled, cloudFileId]);

  return {
    configuredAkahu,
    isLoading,
  };
}
