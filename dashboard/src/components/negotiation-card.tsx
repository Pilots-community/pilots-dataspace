import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

const stateVariant: Record<
  string,
  "default" | "info" | "warning" | "success" | "destructive" | "secondary"
> = {
  INITIAL: "secondary",
  REQUESTING: "info",
  REQUESTED: "info",
  OFFERING: "info",
  OFFERED: "info",
  ACCEPTING: "warning",
  ACCEPTED: "warning",
  AGREEING: "warning",
  AGREED: "warning",
  VERIFYING: "warning",
  VERIFIED: "warning",
  FINALIZING: "warning",
  FINALIZED: "success",
  TERMINATING: "destructive",
  TERMINATED: "destructive",
};

interface NegotiationCardProps {
  negotiation: Record<string, unknown>;
  onStartTransfer?: (contractAgreementId: string) => void;
}

export function NegotiationCard({
  negotiation,
  onStartTransfer,
}: NegotiationCardProps) {
  const id = String(negotiation["@id"] ?? "");
  const state = String(negotiation["state"] ?? "UNKNOWN");
  const agreementId = negotiation["contractAgreementId"] as string | undefined;

  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between">
          <CardTitle className="text-sm font-mono truncate max-w-[300px]">
            {id}
          </CardTitle>
          <Badge variant={stateVariant[state] ?? "secondary"}>{state}</Badge>
        </div>
      </CardHeader>
      <CardContent className="space-y-2">
        {agreementId && (
          <p className="text-xs text-muted-foreground truncate">
            Agreement: <span className="font-mono">{agreementId}</span>
          </p>
        )}
        {state === "FINALIZED" && agreementId && onStartTransfer && (
          <Button
            size="sm"
            onClick={() => onStartTransfer(agreementId)}
          >
            Start Transfer
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
