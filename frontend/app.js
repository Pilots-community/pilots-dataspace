// Configuration
// Defaults to same-origin (works when served through the Kubernetes ingress).
// Override via query params: ?baseUrl=http://host&apiKey=... (URL-encoded)
const CONFIG = {
    baseUrl: window.location.origin,
    apiKey: '',
    currentConnector: 'provider'
};

try {
    const params = new URLSearchParams(window.location.search);
    const baseUrl = params.get('baseUrl');
    const apiKey = params.get('apiKey');
    if (baseUrl) CONFIG.baseUrl = baseUrl;
    if (apiKey) CONFIG.apiKey = apiKey;
} catch {
    // ignore URL parsing errors
}

// API Helper
async function apiCall(endpoint, method = 'GET', body = null, isProtocol = false) {
    const basePath = isProtocol ? `/${CONFIG.currentConnector}/protocol` : `/${CONFIG.currentConnector}/management`;
    const url = `${CONFIG.baseUrl}${basePath}${endpoint}`;
    
    const options = {
        method,
        headers: {
            'Content-Type': 'application/json',
            'X-Api-Key': CONFIG.apiKey
        }
    };

    if (body) {
        options.body = JSON.stringify(body);
    }

    try {
        const response = await fetch(url, options);
        if (!response.ok) {
            let details = '';
            try {
                const text = await response.text();
                if (text) {
                    try {
                        details = ' - ' + JSON.stringify(JSON.parse(text));
                    } catch {
                        details = ' - ' + text;
                    }
                }
            } catch {
                // ignore body read errors
            }
            throw new Error(`HTTP ${response.status}: ${response.statusText}${details}`);
        }
        return await response.json();
    } catch (error) {
        console.error('API Error:', error);
        showNotification('Error: ' + error.message, 'error');
        throw error;
    }
}

// Switch Connector
function switchConnector(connector) {
    CONFIG.currentConnector = connector;
    
    // Update tabs
    document.querySelectorAll('.tab').forEach(tab => {
        tab.classList.remove('active');
    });
    event.target.classList.add('active');

    // Show/hide consumer-specific sections
    const consumerCatalog = document.getElementById('consumer-catalog');
    if (connector === 'consumer') {
        consumerCatalog.style.display = 'block';
    } else {
        consumerCatalog.style.display = 'none';
    }

    // Clear data
    clearAllData();
    
    showNotification(`Switched to ${connector} connector`, 'success');
}

function clearAllData() {
    document.getElementById('assets-container').innerHTML = '<div class="empty-state">Click "Refresh Assets" to load assets</div>';
    document.getElementById('policies-container').innerHTML = '<div class="empty-state">Click "Refresh Policies" to load policies</div>';
    document.getElementById('contracts-container').innerHTML = '<div class="empty-state">Click "Refresh Contracts" to load contract definitions</div>';
    document.getElementById('stats').innerHTML = '';
}

// Load Assets
async function loadAssets() {
    const btn = document.getElementById('assets-btn-text');
    const container = document.getElementById('assets-container');
    
    btn.innerHTML = 'Loading... <span class="loading"></span>';
    
    try {
        const assets = await apiCall('/v3/assets/request', 'POST', {
            "@context": {
                "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
            },
            "@type": "QuerySpec",
            "offset": 0,
            "limit": 50
        });

        if (assets.length === 0) {
            container.innerHTML = '<div class="empty-state">No assets found</div>';
        } else {
            let html = '<table class="data-table"><thead><tr><th>ID</th><th>Name</th><th>Description</th><th>Type</th><th>Actions</th></tr></thead><tbody>';
            
            assets.forEach(asset => {
                const name = asset.properties?.name || asset['@id'];
                const description = asset.properties?.description || 'N/A';
                const type = asset.dataAddress?.type || 'N/A';
                
                html += `
                    <tr>
                        <td><strong>${asset['@id']}</strong></td>
                        <td>${name}</td>
                        <td>${description}</td>
                        <td><span class="badge badge-info">${type}</span></td>
                        <td>
                            <button class="btn" style="padding: 0.5rem 1rem; font-size: 0.85rem;" onclick='viewAssetDetails(${JSON.stringify(asset)})'>View</button>
                        </td>
                    </tr>
                `;
            });
            
            html += '</tbody></table>';
            container.innerHTML = html;
        }

        updateStats('assets', assets.length);
    } catch (error) {
        container.innerHTML = '<div class="empty-state">Error loading assets</div>';
    } finally {
        btn.textContent = 'Refresh Assets';
    }
}

// Load Policies
async function loadPolicies() {
    const btn = document.getElementById('policies-btn-text');
    const container = document.getElementById('policies-container');
    
    btn.innerHTML = 'Loading... <span class="loading"></span>';
    
    try {
        const policies = await apiCall('/v3/policydefinitions/request', 'POST', {
            "@context": {
                "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
            },
            "@type": "QuerySpec",
            "offset": 0,
            "limit": 50
        });

        if (policies.length === 0) {
            container.innerHTML = '<div class="empty-state">No policies found</div>';
        } else {
            let html = '<table class="data-table"><thead><tr><th>ID</th><th>Type</th><th>Actions</th></tr></thead><tbody>';
            
            policies.forEach(policy => {
                html += `
                    <tr>
                        <td><strong>${policy['@id']}</strong></td>
                        <td><span class="badge badge-success">${policy['@type'] || 'PolicyDefinition'}</span></td>
                        <td>
                            <button class="btn" style="padding: 0.5rem 1rem; font-size: 0.85rem;" onclick='viewPolicyDetails(${JSON.stringify(policy)})'>View</button>
                        </td>
                    </tr>
                `;
            });
            
            html += '</tbody></table>';
            container.innerHTML = html;
        }

        updateStats('policies', policies.length);
    } catch (error) {
        container.innerHTML = '<div class="empty-state">Error loading policies</div>';
    } finally {
        btn.textContent = 'Refresh Policies';
    }
}

// Load Contract Definitions
async function loadContractDefinitions() {
    const btn = document.getElementById('contracts-btn-text');
    const container = document.getElementById('contracts-container');
    
    btn.innerHTML = 'Loading... <span class="loading"></span>';
    
    try {
        const contracts = await apiCall('/v3/contractdefinitions/request', 'POST', {
            "@context": {
                "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
            },
            "@type": "QuerySpec",
            "offset": 0,
            "limit": 50
        });

        if (contracts.length === 0) {
            container.innerHTML = '<div class="empty-state">No contract definitions found</div>';
        } else {
            let html = '<table class="data-table"><thead><tr><th>ID</th><th>Access Policy</th><th>Contract Policy</th><th>Actions</th></tr></thead><tbody>';
            
            contracts.forEach(contract => {
                const accessPolicy = contract.accessPolicyId || 'N/A';
                const contractPolicy = contract.contractPolicyId || 'N/A';
                
                html += `
                    <tr>
                        <td><strong>${contract['@id']}</strong></td>
                        <td>${accessPolicy}</td>
                        <td>${contractPolicy}</td>
                        <td>
                            <button class="btn" style="padding: 0.5rem 1rem; font-size: 0.85rem;" onclick='viewContractDetails(${JSON.stringify(contract)})'>View</button>
                        </td>
                    </tr>
                `;
            });
            
            html += '</tbody></table>';
            container.innerHTML = html;
        }

        updateStats('contracts', contracts.length);
    } catch (error) {
        container.innerHTML = '<div class="empty-state">Error loading contract definitions</div>';
    } finally {
        btn.textContent = 'Refresh Contracts';
    }
}

// Request Catalog (Consumer only)
async function requestCatalog() {
    const btn = document.getElementById('catalog-btn-text');
    const container = document.getElementById('catalog-container');
    
    btn.innerHTML = 'Loading... <span class="loading"></span>';
    
    try {
        // IMPORTANT:
        // Do NOT call the provider DSP endpoint directly from the browser.
        // The provider's /protocol endpoints are secured via DCP (Bearer tokens).
        // Instead, call the *consumer* management API. The consumer connector will
        // perform the authenticated DSP call to the provider.

        const providerDspAddress = `${CONFIG.baseUrl}/provider/protocol`;

        const catalog = await apiCall('/v3/catalog/request', 'POST', {
            "@context": {
                "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
            },
            "@type": "CatalogRequest",
            "counterPartyAddress": providerDspAddress,
            "protocol": "dataspace-protocol-http"
        });

        const datasets = catalog?.['dcat:dataset'] ?? catalog?.datasets;

        if (!datasets || datasets.length === 0) {
            container.innerHTML = '<div class="empty-state">No datasets found in provider catalog</div>';
        } else {
            container.innerHTML = `<div class="json-viewer">${JSON.stringify(catalog, null, 2)}</div>`;
        }
    } catch (error) {
        console.error('Catalog error:', error);
        showNotification('Error: ' + error.message, 'error');
        container.innerHTML = '<div class="empty-state">Error requesting catalog</div>';
    } finally {
        btn.textContent = 'Request Catalog from Provider';
    }
}

// View Details Functions
function viewAssetDetails(asset) {
    alert('Asset Details:\n\n' + JSON.stringify(asset, null, 2));
}

function viewPolicyDetails(policy) {
    alert('Policy Details:\n\n' + JSON.stringify(policy, null, 2));
}

function viewContractDetails(contract) {
    alert('Contract Details:\n\n' + JSON.stringify(contract, null, 2));
}

// Create Asset
function showCreateAssetModal() {
    document.getElementById('create-asset-modal').classList.add('active');
}

async function createAsset() {
    const id = document.getElementById('asset-id').value;
    const name = document.getElementById('asset-name').value;
    const description = document.getElementById('asset-description').value;
    const url = document.getElementById('asset-url').value;

    if (!id || !name || !url) {
        showNotification('Please fill in all required fields', 'error');
        return;
    }

    const asset = {
        "@context": {
            "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
        },
        "@id": id,
        "properties": {
            "name": name,
            "description": description
        },
        "dataAddress": {
            "@type": "DataAddress",
            "type": "HttpData",
            "baseUrl": url
        }
    };

    try {
        await apiCall('/v3/assets', 'POST', asset);
        showNotification('Asset created successfully!', 'success');
        closeModal('create-asset-modal');
        loadAssets();
        
        // Clear form
        document.getElementById('asset-id').value = '';
        document.getElementById('asset-name').value = '';
        document.getElementById('asset-description').value = '';
        document.getElementById('asset-url').value = '';
    } catch (error) {
        // Error already shown in apiCall
    }
}

// Create Policy
function showCreatePolicyModal() {
    document.getElementById('create-policy-modal').classList.add('active');
    
    // Set default policy template
    const defaultPolicy = {
        "@context": {
            "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
            "odrl": "http://www.w3.org/ns/odrl/2/"
        },
        "@id": "allow-all-policy",
        "@type": "PolicyDefinition",
        "policy": {
            "@type": "Policy",
            "odrl:permission": [{
                "odrl:action": "USE",
                "odrl:constraint": []
            }]
        }
    };
    
    document.getElementById('policy-json').value = JSON.stringify(defaultPolicy, null, 2);
}

async function createPolicy() {
    const id = document.getElementById('policy-id').value;
    const jsonText = document.getElementById('policy-json').value;

    if (!id || !jsonText) {
        showNotification('Please fill in all fields', 'error');
        return;
    }

    try {
        const policy = JSON.parse(jsonText);
        policy['@id'] = id;
        
        await apiCall('/v3/policydefinitions', 'POST', policy);
        showNotification('Policy created successfully!', 'success');
        closeModal('create-policy-modal');
        loadPolicies();
        
        document.getElementById('policy-id').value = '';
    } catch (error) {
        if (error instanceof SyntaxError) {
            showNotification('Invalid JSON format', 'error');
        }
    }
}

// Create Contract
function showCreateContractModal() {
    document.getElementById('create-contract-modal').classList.add('active');
}

async function createContract() {
    const id = document.getElementById('contract-id').value;
    const assetId = document.getElementById('contract-asset-id').value;
    const policyId = document.getElementById('contract-policy-id').value;

    if (!id || !assetId || !policyId) {
        showNotification('Please fill in all fields', 'error');
        return;
    }

    const contract = {
        "@context": {
            "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
        },
        "@id": id,
        "@type": "ContractDefinition",
        "accessPolicyId": policyId,
        "contractPolicyId": policyId,
        "assetsSelector": {
            "@type": "CriterionDto",
            "operandLeft": "https://w3id.org/edc/v0.0.1/ns/id",
            "operator": "=",
            "operandRight": assetId
        }
    };

    try {
        await apiCall('/v3/contractdefinitions', 'POST', contract);
        showNotification('Contract definition created successfully!', 'success');
        closeModal('create-contract-modal');
        loadContractDefinitions();
        
        document.getElementById('contract-id').value = '';
        document.getElementById('contract-asset-id').value = '';
        document.getElementById('contract-policy-id').value = '';
    } catch (error) {
        // Error already shown in apiCall
    }
}

// Modal Functions
function closeModal(modalId) {
    document.getElementById(modalId).classList.remove('active');
}

// Notification
function showNotification(message, type = 'success') {
    const notification = document.getElementById('notification');
    notification.textContent = message;
    notification.className = `notification ${type} show`;
    
    setTimeout(() => {
        notification.classList.remove('show');
    }, 3000);
}

// Update Stats
function updateStats(type, count) {
    const stats = document.getElementById('stats');
    const existing = document.querySelector(`[data-stat="${type}"]`);
    
    const statCard = `
        <div class="stat-card" data-stat="${type}">
            <h3>${count}</h3>
            <p>${type.charAt(0).toUpperCase() + type.slice(1)}</p>
        </div>
    `;
    
    if (existing) {
        existing.outerHTML = statCard;
    } else {
        stats.insertAdjacentHTML('beforeend', statCard);
    }
}

// Initialize
window.addEventListener('DOMContentLoaded', () => {
    showNotification('EDC Management UI loaded. Select a connector to start.', 'success');
});
