# Copilot Instructions

## Project Guidelines
- For the SQL-free Music Store variant on modernized.cached, use a singleton InMemoryDataStore, following the approach used on the Legacy branch.
- Prefer a reusable parameterized PowerShell script beside the Dockerfile for Azure Container Registry managed builds and pushes, supporting -NoWait, rather than a lengthy interactive build/deployment workflow.