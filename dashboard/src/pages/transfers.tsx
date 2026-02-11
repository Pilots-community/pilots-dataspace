import { useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useTransfers, useCreateTransfer } from "@/hooks/use-api";
import { useRole } from "@/hooks/use-role";
import { useToastContext } from "@/hooks/use-toast-context";
import { TransferCard } from "@/components/transfer-card";
import { EdrViewer } from "@/components/edr-viewer";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

export default function TransfersPage() {
  const { role } = useRole();
  const toast = useToastContext();
  const [searchParams] = useSearchParams();
  const prefillAgreementId = searchParams.get("agreementId") ?? "";

  const { data: transfers, isLoading, error } = useTransfers();
  const createTransfer = useCreateTransfer();

  const [open, setOpen] = useState(!!prefillAgreementId);
  const [agreementId, setAgreementId] = useState(prefillAgreementId);
  const [counterPartyAddress, setCounterPartyAddress] = useState(
    role === "consumer"
      ? "http://provider-controlplane:19194/protocol"
      : "http://consumer-controlplane:29194/protocol"
  );
  const [counterPartyId, setCounterPartyId] = useState(
    role === "consumer"
      ? "did:web:provider-identityhub%3A7093"
      : "did:web:consumer-identityhub%3A7083"
  );
  const [transferType, setTransferType] = useState<"HttpData-PULL" | "HttpData-PUSH">(
    "HttpData-PULL"
  );
  const [pushUrl, setPushUrl] = useState("http://http-receiver:4000/receiver");

  const [edrTransferId, setEdrTransferId] = useState<string | null>(null);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const body: Record<string, unknown> = {
      "@type": "TransferRequest",
      connectorAddress: counterPartyAddress,
      counterPartyAddress,
      counterPartyId,
      contractId: agreementId,
      assetId: agreementId,
      protocol: "dataspace-protocol-http",
      transferType: transferType,
    };
    if (transferType === "HttpData-PUSH") {
      body["dataDestination"] = {
        type: "HttpData",
        baseUrl: pushUrl,
      };
    }
    createTransfer.mutate(body, {
      onSuccess: (data) => {
        const tId = (data as Record<string, unknown>)?.["@id"];
        toast({
          title: "Transfer initiated",
          description: String(tId ?? ""),
        });
        setOpen(false);
      },
      onError: (err) =>
        toast({
          title: "Transfer failed",
          description: String(err),
          variant: "destructive",
        }),
    });
  }

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold">Transfer Processes</h1>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button>Initiate Transfer</Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Initiate Transfer</DialogTitle>
            </DialogHeader>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <Label htmlFor="tp-agreement">Contract Agreement ID</Label>
                <Input
                  id="tp-agreement"
                  value={agreementId}
                  onChange={(e) => setAgreementId(e.target.value)}
                  required
                />
              </div>
              <div>
                <Label htmlFor="tp-addr">Counter Party Address</Label>
                <Input
                  id="tp-addr"
                  value={counterPartyAddress}
                  onChange={(e) => setCounterPartyAddress(e.target.value)}
                  required
                />
              </div>
              <div>
                <Label htmlFor="tp-id">Counter Party ID (DID)</Label>
                <Input
                  id="tp-id"
                  value={counterPartyId}
                  onChange={(e) => setCounterPartyId(e.target.value)}
                  required
                />
              </div>
              <div>
                <Label>Transfer Type</Label>
                <Select
                  value={transferType}
                  onValueChange={(v) =>
                    setTransferType(v as "HttpData-PULL" | "HttpData-PUSH")
                  }
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="HttpData-PULL">Pull (HttpData-PULL)</SelectItem>
                    <SelectItem value="HttpData-PUSH">Push (HttpData-PUSH)</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              {transferType === "HttpData-PUSH" && (
                <div>
                  <Label htmlFor="tp-push-url">Push Destination URL</Label>
                  <Input
                    id="tp-push-url"
                    value={pushUrl}
                    onChange={(e) => setPushUrl(e.target.value)}
                    required
                  />
                </div>
              )}
              <Button
                type="submit"
                disabled={createTransfer.isPending}
                className="w-full"
              >
                {createTransfer.isPending ? "Initiating..." : "Initiate Transfer"}
              </Button>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      {isLoading && <p className="text-muted-foreground">Loading...</p>}
      {error && (
        <p className="text-destructive">Error: {String(error)}</p>
      )}
      {transfers && transfers.length > 0 ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {transfers.map((t) => (
            <TransferCard
              key={String(t["@id"])}
              transfer={t}
              onViewEdr={(id) => setEdrTransferId(id)}
            />
          ))}
        </div>
      ) : (
        !isLoading && (
          <p className="text-muted-foreground">No transfers yet.</p>
        )
      )}

      <EdrViewer
        transferId={edrTransferId}
        onClose={() => setEdrTransferId(null)}
      />
    </div>
  );
}
