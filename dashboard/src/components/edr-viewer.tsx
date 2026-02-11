import { useState } from "react";
import { useEdrs, fetchWithAuth } from "@/hooks/use-api";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";

interface EdrViewerProps {
  transferId: string | null;
  onClose: () => void;
}

export function EdrViewer({ transferId, onClose }: EdrViewerProps) {
  const { data: edr, isLoading, error } = useEdrs(transferId);
  const [fetchedData, setFetchedData] = useState<string | null>(null);
  const [fetching, setFetching] = useState(false);

  const endpoint = edr ? String(edr["endpoint"] ?? "") : "";
  const authorization = edr ? String(edr["authorization"] ?? "") : "";

  function proxyUrl(url: string): string {
    return url
      .replace(/^https?:\/\/provider-dataplane:\d+\/public/, "/api/public/provider")
      .replace(/^https?:\/\/consumer-dataplane:\d+\/public/, "/api/public/consumer");
  }

  async function handleFetch() {
    if (!endpoint || !authorization) return;
    setFetching(true);
    try {
      const text = await fetchWithAuth(proxyUrl(endpoint), authorization);
      setFetchedData(text);
    } catch (err) {
      setFetchedData(`Error: ${err}`);
    } finally {
      setFetching(false);
    }
  }

  return (
    <Dialog open={!!transferId} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>EDR for Transfer {transferId}</DialogTitle>
        </DialogHeader>
        {isLoading && <p className="text-sm text-muted-foreground">Loading EDR...</p>}
        {error && (
          <p className="text-sm text-destructive">
            Error loading EDR: {String(error)}
          </p>
        )}
        {edr && (
          <div className="space-y-3">
            <div>
              <p className="text-xs font-medium text-muted-foreground">Endpoint</p>
              <p className="text-sm font-mono break-all">{endpoint}</p>
            </div>
            <div>
              <p className="text-xs font-medium text-muted-foreground">
                Authorization
              </p>
              <p className="text-sm font-mono break-all truncate">
                {authorization.slice(0, 80)}...
              </p>
            </div>
            <Button onClick={handleFetch} disabled={fetching}>
              {fetching ? "Fetching..." : "Fetch Data"}
            </Button>
            {fetchedData !== null && (
              <Textarea
                readOnly
                value={fetchedData}
                className="min-h-[200px] font-mono text-xs"
              />
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
