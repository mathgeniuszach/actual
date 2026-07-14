import { useEffect, useState } from 'react';

import { send } from '@actual-app/core/platform/client/connection';

import { useMetadataPref } from './useMetadataPref';
import { useSyncServerStatus } from './useSyncServerStatus';

export function useEnableBankingStatus(enabled = true) {
  const [configuredEnableBanking, setConfiguredEnableBanking] = useState<
    boolean | null
  >(null);
  const [isLoading, setIsLoading] = useState(true);
  const status = useSyncServerStatus();
  const [cloudFileId] = useMetadataPref('cloudFileId');

  useEffect(() => {
    if (!enabled) return;

    async function fetch() {
      setIsLoading(true);
      try {
        const results = await send('enablebanking-status', { fileId: cloudFileId });
        setConfiguredEnableBanking(results.configured || false);
      } catch {
        setConfiguredEnableBanking(false);
      } finally {
        setIsLoading(false);
      }
    }

    if (status === 'online') {
      void fetch();
    }
  }, [status, enabled, cloudFileId]);

  return {
    configuredEnableBanking,
    isLoading,
  };
}
