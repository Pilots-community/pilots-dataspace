package org.eclipse.edc.demo.dcp.issuer;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class TrustedIssuerRecord {

    private final String did;
    private final String name;
    private final String organization;
    private final String email;
    private final String dspEndpoint;
    private final String participantDid;
    private final Set<String> credentialTypes;

    public TrustedIssuerRecord(String did, String name, String organization, String email, String dspEndpoint, String participantDid) {
        this.did = did;
        this.name = name;
        this.organization = organization;
        this.email = email;
        this.dspEndpoint = dspEndpoint;
        this.participantDid = participantDid;
        this.credentialTypes = ConcurrentHashMap.newKeySet();
    }

    public String getDid() {
        return did;
    }

    public String getName() {
        return name;
    }

    public String getOrganization() {
        return organization;
    }

    public String getEmail() {
        return email;
    }

    public String getDspEndpoint() {
        return dspEndpoint;
    }

    public String getParticipantDid() {
        return participantDid;
    }

    public Set<String> getCredentialTypes() {
        return credentialTypes;
    }
}
