# Agent Memory MCP

Persistent, searchable memory bank for AI agents running as an MCP server, syncing with project documentation.

- Runs as an MCP server exposing four tools: memory_search, memory_write, memory_read, memory_stats
- memory_write stores knowledge with key, type (pattern/decision/architecture), content, and tags
- memory_search finds memories by query string, type filter, or tag matching
- memory_read retrieves specific memory content by key for direct access
- memory_stats provides analytics on memory usage across the project
- Memories are project-scoped: start the server with a project_id and workspace path
- Automatically syncs with project documentation for persistent knowledge management
- Includes a standalone dashboard (port 3333) for visualizing memory usage
- Node.js v18+ required; compile with npm run compile before first use
