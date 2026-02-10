import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

interface CatalogViewerProps {
  catalog: Record<string, unknown>;
  onNegotiate: (offer: {
    offerId: string;
    assetId: string;
    counterPartyAddress: string;
    counterPartyId: string;
  }) => void;
  counterPartyAddress: string;
  counterPartyId: string;
}

export function CatalogViewer({
  catalog,
  onNegotiate,
  counterPartyAddress,
  counterPartyId,
}: CatalogViewerProps) {
  const rawDatasets = (catalog as Record<string, unknown>)["dcat:dataset"];
  const datasets: Record<string, unknown>[] = Array.isArray(rawDatasets)
    ? rawDatasets
    : rawDatasets
      ? [rawDatasets as Record<string, unknown>]
      : [];

  if (datasets.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        No datasets found in catalog.
      </p>
    );
  }

  return (
    <div className="grid gap-4 sm:grid-cols-2">
      {datasets.map((ds, i) => {
        const dsId = String(
          (ds as Record<string, unknown>)["@id"] ?? `dataset-${i}`
        );
        const rawPolicies = (ds as Record<string, unknown>)["odrl:hasPolicy"];
        const policies: Record<string, unknown>[] = Array.isArray(rawPolicies)
          ? rawPolicies
          : rawPolicies
            ? [rawPolicies as Record<string, unknown>]
            : [];

        return (
          <Card key={dsId}>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">{dsId}</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {policies.map((policy, j) => {
                const offerId = String(
                  (policy as Record<string, unknown>)["@id"] ?? `offer-${j}`
                );
                return (
                  <div
                    key={offerId}
                    className="flex items-center justify-between rounded border p-2"
                  >
                    <Badge variant="secondary" className="truncate max-w-[200px]">
                      {offerId}
                    </Badge>
                    <Button
                      size="sm"
                      onClick={() =>
                        onNegotiate({
                          offerId,
                          assetId: dsId,
                          counterPartyAddress,
                          counterPartyId,
                        })
                      }
                    >
                      Negotiate
                    </Button>
                  </div>
                );
              })}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
