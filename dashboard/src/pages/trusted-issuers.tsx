import { useState } from "react";
import {
  useTrustedIssuers,
  useAddTrustedIssuer,
  useUpdateTrustedIssuer,
  useDeleteTrustedIssuer,
  type TrustedIssuer,
} from "@/hooks/use-api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useToastContext } from "@/hooks/use-toast-context";
import { Pencil, Trash2 } from "lucide-react";

export default function TrustedIssuersPage() {
  const { data: issuers, isLoading, error } = useTrustedIssuers();
  const addIssuer = useAddTrustedIssuer();
  const updateIssuer = useUpdateTrustedIssuer();
  const deleteIssuer = useDeleteTrustedIssuer();
  const toast = useToastContext();

  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<TrustedIssuer | null>(null);
  const [did, setDid] = useState("");
  const [name, setName] = useState("");
  const [organization, setOrganization] = useState("");
  const [email, setEmail] = useState("");
  const [dspEndpoint, setDspEndpoint] = useState("");
  const [participantDid, setParticipantDid] = useState("");

  function openAdd() {
    setEditing(null);
    setDid("");
    setName("");
    setOrganization("");
    setEmail("");
    setDspEndpoint("");
    setParticipantDid("");
    setOpen(true);
  }

  function openEdit(issuer: TrustedIssuer) {
    setEditing(issuer);
    setDid(issuer.did);
    setName(issuer.name || "");
    setOrganization(issuer.organization || "");
    setEmail(issuer.email || "");
    setDspEndpoint(issuer.dspEndpoint || "");
    setParticipantDid(issuer.participantDid || "");
    setOpen(true);
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!did.trim()) return;

    const params = {
      did: did.trim(),
      name: name.trim() || undefined,
      organization: organization.trim() || undefined,
      email: email.trim() || undefined,
      dspEndpoint: dspEndpoint.trim() || undefined,
      participantDid: participantDid.trim() || undefined,
    };

    const mutation = editing ? updateIssuer : addIssuer;
    const action = editing ? "updated" : "added";

    mutation.mutate(params, {
      onSuccess: () => {
        toast({ title: `Issuer ${action}`, description: did.trim() });
        setOpen(false);
      },
      onError: (err) =>
        toast({
          title: `Failed to ${editing ? "update" : "add"} issuer`,
          description: String(err),
          variant: "destructive",
        }),
    });
  }

  function handleDelete(issuerDid: string) {
    deleteIssuer.mutate(issuerDid, {
      onSuccess: () =>
        toast({ title: "Issuer removed", description: issuerDid }),
      onError: (err) =>
        toast({
          title: "Failed to remove issuer",
          description: String(err),
          variant: "destructive",
        }),
    });
  }

  const isPending = addIssuer.isPending || updateIssuer.isPending;

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold">Trusted Issuers</h1>
        <Button onClick={openAdd}>Add Issuer</Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editing ? "Edit Trusted Issuer" : "Add Trusted Issuer"}</DialogTitle>
          </DialogHeader>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <Label htmlFor="issuer-did">DID</Label>
              <Input
                id="issuer-did"
                value={did}
                onChange={(e) => setDid(e.target.value)}
                placeholder="did:web:example.com"
                required
                disabled={!!editing}
              />
            </div>
            <div>
              <Label htmlFor="issuer-name">Name</Label>
              <Input
                id="issuer-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Issuer display name"
              />
            </div>
            <div>
              <Label htmlFor="issuer-org">Organization</Label>
              <Input
                id="issuer-org"
                value={organization}
                onChange={(e) => setOrganization(e.target.value)}
                placeholder="Organization name"
              />
            </div>
            <div>
              <Label htmlFor="issuer-email">Email</Label>
              <Input
                id="issuer-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="contact@example.com"
              />
            </div>
            <div>
              <Label htmlFor="issuer-dsp">DSP Endpoint</Label>
              <Input
                id="issuer-dsp"
                value={dspEndpoint}
                onChange={(e) => setDspEndpoint(e.target.value)}
                placeholder="http://<host>:19194/protocol"
              />
            </div>
            <div>
              <Label htmlFor="issuer-participant-did">Participant DID</Label>
              <Input
                id="issuer-participant-did"
                value={participantDid}
                onChange={(e) => setParticipantDid(e.target.value)}
                placeholder="did:web:<host>%3A7093"
              />
            </div>
            <Button type="submit" disabled={isPending} className="w-full">
              {isPending ? (editing ? "Saving..." : "Adding...") : (editing ? "Save Changes" : "Add Issuer")}
            </Button>
          </form>
        </DialogContent>
      </Dialog>

      {isLoading && <p className="text-muted-foreground">Loading...</p>}
      {error && (
        <p className="text-destructive">Error: {String(error)}</p>
      )}
      {issuers && issuers.length > 0 && (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>DID</TableHead>
              <TableHead>Name</TableHead>
              <TableHead>Organization</TableHead>
              <TableHead>Email</TableHead>
              <TableHead>Credential Types</TableHead>
              <TableHead className="w-24" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {issuers.map((issuer) => (
              <TableRow key={issuer.did}>
                <TableCell className="font-mono text-sm">
                  {issuer.did}
                </TableCell>
                <TableCell className="text-sm">
                  {issuer.name || "-"}
                </TableCell>
                <TableCell className="text-sm">
                  {issuer.organization || "-"}
                </TableCell>
                <TableCell className="text-sm">
                  {issuer.email || "-"}
                </TableCell>
                <TableCell className="text-sm">
                  {issuer.credentialTypes.join(", ") || "*"}
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => openEdit(issuer)}
                    >
                      <Pencil className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleDelete(issuer.did)}
                      disabled={deleteIssuer.isPending}
                    >
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
      {issuers && issuers.length === 0 && (
        <p className="text-muted-foreground">No trusted issuers configured.</p>
      )}
    </div>
  );
}
