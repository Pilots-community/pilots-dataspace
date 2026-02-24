# EDC Management UI

A modern web-based frontend for managing your Eclipse Dataspace Components (EDC) connectors.

## Features

- ✅ Switch between Provider and Consumer connectors
- 📦 View, create, and manage Assets
- 📋 Manage Policy Definitions
- 📝 Create and view Contract Definitions
- 🔍 Request Provider Catalog (Consumer mode)
- 📊 Real-time statistics dashboard
- 🎨 Clean, modern UI with responsive design

## Quick Start

1. Start the web server:
   ```powershell
   .\start-server.ps1
   ```

2. Open your browser to: `http://localhost:8080`

3. Use the UI to manage your connectors!

## Configuration

The frontend is intentionally **not** committed with any real endpoint or API key.

- **Base URL** defaults to `window.location.origin` (same-origin)
- **API Key** defaults to empty

To change these settings, edit the `CONFIG` object in `app.js`, or pass query params:

- `?baseUrl=http://your-host&apiKey=YOUR_KEY`

Example:

`http://localhost:8080/?baseUrl=http://localhost:19193&apiKey=REPLACE_ME`

`CONFIG`:
```javascript
const CONFIG = {
    baseUrl: window.location.origin,
    apiKey: '',
    currentConnector: 'provider'
};
```

## Usage

### Provider Mode
- Create assets that you want to share
- Define policies for access control
- Create contract definitions linking assets to policies

### Consumer Mode
- Request the provider's catalog to see available datasets (via the consumer management API; the browser should not call provider `/protocol` directly)
- Browse available offerings
- Initiate contract negotiations (coming soon)

## Notes

- The server runs on port 8080 by default
- Press Ctrl+C to stop the server
- All API calls are made directly to your Kubernetes cluster's external endpoint
