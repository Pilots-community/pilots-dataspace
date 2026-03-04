import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useCatalog, useCreateNegotiation, useTrustedIssuers } from "@/hooks/use-api";
import { useToastContext } from "@/hooks/use-toast-context";
import { CatalogViewer } from "@/components/catalog-viewer";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export default function CatalogPage() {
  const toast = useToastContext();
  const navigate = useNavigate();

  const [counterPartyAddress, setCounterPartyAddress] = useState("");
  const [counterPartyId, setCounterPartyId] = useState("");

  const catalog = useCatalog();
  const negotiate = useCreateNegotiation();
  const { data: trustedIssuers } = useTrustedIssuers();

  const connectorIssuers = trustedIssuers?.filter(
    (i) => i.dspEndpoint && i.participantDid
  );

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
      {connectorIssuers && connectorIssuers.length > 0 && (
        <div className="mb-4 flex flex-wrap gap-2">
          {connectorIssuers.map((issuer) => (
            <Button
              key={issuer.did}
              variant={
                counterPartyAddress === issuer.dspEndpoint &&
                counterPartyId === issuer.participantDid
                  ? "default"
                  : "outline"
              }
              size="sm"
              onClick={() => {
                setCounterPartyAddress(issuer.dspEndpoint);
                setCounterPartyId(issuer.participantDid);
              }}
            >
              {issuer.organization || issuer.name || issuer.did}
            </Button>
          ))}
        </div>
      )}

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
                placeholder="http://<remote-host>:19194/protocol"
                value={counterPartyAddress}
                onChange={(e) => setCounterPartyAddress(e.target.value)}
                required
              />
            </div>
            <div>
              <Label htmlFor="cat-id">Counter Party ID (DID)</Label>
              <Input
                id="cat-id"
                placeholder="did:web:<remote-host>%3A7093"
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
