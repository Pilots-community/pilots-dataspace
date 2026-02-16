import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useCatalog, useCreateNegotiation } from "@/hooks/use-api";
import { useRole } from "@/hooks/use-role";
import { useToastContext } from "@/hooks/use-toast-context";
import { CatalogViewer } from "@/components/catalog-viewer";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export default function CatalogPage() {
  const { role } = useRole();
  const toast = useToastContext();
  const navigate = useNavigate();

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

  const catalog = useCatalog();
  const negotiate = useCreateNegotiation();

  function handleRequest(e: React.FormEvent) {
    e.preventDefault();
    catalog.mutate({ counterPartyAddress, counterPartyId });
  }

  function handleNegotiate(offer: {
    offerId: string;
    assetId: string;
    counterPartyAddress: string;
    counterPartyId: string;
  }) {
    negotiate.mutate(
      {
        "@type": "ContractRequest",
        counterPartyAddress: offer.counterPartyAddress,
        counterPartyId: offer.counterPartyId,
        protocol: "dataspace-protocol-http",
        policy: {
          "@context": "http://www.w3.org/ns/odrl.jsonld",
          "@id": offer.offerId,
          "@type": "Offer",
          assigner: offer.counterPartyId,
          target: offer.assetId,
        },
      },
      {
        onSuccess: (data) => {
          const nId = (data as Record<string, unknown>)?.["@id"];
          toast({
            title: "Negotiation initiated",
            description: String(nId ?? ""),
          });
          navigate("/negotiations");
        },
        onError: (err) =>
          toast({
            title: "Negotiation failed",
            description: String(err),
            variant: "destructive",
          }),
      }
    );
  }

  return (
    <div>
      <h1 className="mb-6 text-2xl font-bold">Catalog Browser</h1>
      <Card className="mb-6">
        <CardHeader>
          <CardTitle className="text-base">Request Catalog</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleRequest} className="space-y-4">
            <div>
              <Label htmlFor="cat-addr">Counter Party Address (protocol URL)</Label>
              <Input
                id="cat-addr"
                value={counterPartyAddress}
                onChange={(e) => setCounterPartyAddress(e.target.value)}
                required
              />
            </div>
            <div>
              <Label htmlFor="cat-id">Counter Party ID (DID)</Label>
              <Input
                id="cat-id"
                value={counterPartyId}
                onChange={(e) => setCounterPartyId(e.target.value)}
                required
              />
            </div>
            <Button type="submit" disabled={catalog.isPending}>
              {catalog.isPending ? "Fetching..." : "Fetch Catalog"}
            </Button>
          </form>
        </CardContent>
      </Card>

      {catalog.error && (
        <p className="mb-4 text-destructive">
          Error: {String(catalog.error)}
        </p>
      )}

      {catalog.data && (
        <CatalogViewer
          catalog={catalog.data}
          onNegotiate={handleNegotiate}
          counterPartyAddress={counterPartyAddress}
          counterPartyId={counterPartyId}
        />
      )}
    </div>
  );
}
