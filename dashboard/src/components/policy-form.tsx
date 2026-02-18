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
import { useCreatePolicy } from "@/hooks/use-api";
import { useToastContext } from "@/hooks/use-toast-context";

export function PolicyForm() {
  const [open, setOpen] = useState(false);
  const [id, setId] = useState("");
  const create = useCreatePolicy();
  const toast = useToastContext();

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    create.mutate(
      {
        "@id": id,
        policy: {
          "@context": "http://www.w3.org/ns/odrl.jsonld",
          "@type": "Set",
          permission: [],
          prohibition: [],
          obligation: [],
        },
      },
      {
        onSuccess: () => {
          toast({ title: "Policy created", description: id });
          setOpen(false);
          setId("");
        },
        onError: (err) =>
          toast({
            title: "Failed to create policy",
            description: String(err),
            variant: "destructive",
          }),
      }
    );
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>Create Policy</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Create Policy (Open)</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <Label htmlFor="policy-id">Policy ID</Label>
            <Input
              id="policy-id"
              value={id}
              onChange={(e) => setId(e.target.value)}
              required
            />
          </div>
          <p className="text-sm text-muted-foreground">
            Creates an open policy with no constraints (permits all).
          </p>
          <Button type="submit" disabled={create.isPending} className="w-full">
            {create.isPending ? "Creating..." : "Create"}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}
