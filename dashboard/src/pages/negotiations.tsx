import { useNavigate } from "react-router-dom";
import { useNegotiations } from "@/hooks/use-api";
import { NegotiationCard } from "@/components/negotiation-card";

export default function NegotiationsPage() {
  const { data: negotiations, isLoading, error } = useNegotiations();
  const navigate = useNavigate();

  function handleStartTransfer(contractAgreementId: string) {
    navigate(`/transfers?agreementId=${encodeURIComponent(contractAgreementId)}`);
  }

  return (
    <div>
      <h1 className="mb-6 text-2xl font-bold">Contract Negotiations</h1>
      {isLoading && <p className="text-muted-foreground">Loading...</p>}
      {error && (
        <p className="text-destructive">Error: {String(error)}</p>
      )}
      {negotiations && negotiations.length > 0 ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {negotiations.map((n) => (
            <NegotiationCard
              key={String(n["@id"])}
              negotiation={n}
              onStartTransfer={handleStartTransfer}
            />
          ))}
        </div>
      ) : (
        !isLoading && (
          <p className="text-muted-foreground">No negotiations yet.</p>
        )
      )}
    </div>
  );
}
