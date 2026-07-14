# Swerve

## Run the backend

The iOS app uses the API in `backend/`. From the repository root:

```bash
npm run dev
```

This delegates to `backend/npm run dev` and starts the API at
`http://localhost:3000`. Ensure `backend/.env.local` contains the required
Google Maps API key.

If port 3000 is already in use, either stop the existing development server
with `Ctrl+C` in its terminal, or use another port:

```bash
PORT=3001 npm run dev
```
