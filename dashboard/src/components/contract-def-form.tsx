import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { useCreateContractDef } from "@/hooks/use-api";
import { useToastContext } from "@/hooks/use-toast-context";

export function ContractDefForm() {
  const [open, setOpen] = useState(false);
  const [id, setId] = useState("");
  const [accessPolicyId, setAccessPolicyId] = useState("");
  const [contractPolicyId, setContractPolicyId] = useState("");
  const [assetId, setAssetId] = useState("");
  const create = useCreateContractDef();
  const toast = useToastContext();

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    create.mutate(
      {
        "@id": id,
        accessPolicyId,
        contractPolicyId,
        assetsSelector: {
          "@type": "CriterionDto",
          operandLeft: "https://w3id.org/edc/v0.0.1/ns/id",
          operator: "=",
          operandRight: assetId,
        },
      },
      {
        onSuccess: () => {
          toast({ title: "Contract definition created", description: id });
          setOpen(false);
          setId("");
          setAccessPolicyId("");
          setContractPolicyId("");
          setAssetId("");
        },
        onError: (err) =>
          toast({
            title: "Failed to create contract definition",
            description: String(err),
            variant: "destructive",
          }),
      }
    );
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>Create Contract Definition</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Create Contract Definition</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <Label htmlFor="cd-id">Definition ID</Label>
            <Input
              id="cd-id"
              value={id}
              onChange={(e) => setId(e.target.value)}
              required
            />
          </div>
          <div>
            <Label htmlFor="cd-access">Access Policy ID</Label>
            <Input
              id="cd-access"
              value={accessPolicyId}
              onChange={(e) => setAccessPolicyId(e.target.value)}
              required
            />
          </div>
          <div>
            <Label htmlFor="cd-contract">Contract Policy ID</Label>
            <Input
              id="cd-contract"
              value={contractPolicyId}
              onChange={(e) => setContractPolicyId(e.target.value)}
              required
            />
          </div>
          <div>
            <Label htmlFor="cd-asset">Asset ID (selector)</Label>
            <Input
              id="cd-asset"
              value={assetId}
              onChange={(e) => setAssetId(e.target.value)}
              required
            />
          </div>
          <Button type="submit" disabled={create.isPending} className="w-full">
            {create.isPending ? "Creating..." : "Create"}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}
