# File Uploads & Storage

Handle file uploads securely with S3, Cloudflare R2, presigned URLs, and multipart uploads.

- Never trust client-provided file types; always validate by checking magic bytes on the server
- Always set upload size restrictions to prevent abuse and resource exhaustion
- Sanitize filenames to prevent path traversal attacks from user-controlled input
- Prefer presigned URLs over server proxying to reduce server load and bandwidth costs
- Control presigned URL distribution: set short expiration, restrict to specific operations
- Use multipart uploads for large files to enable resumable uploads and avoid timeouts
- Handle upload failures gracefully with retry logic and progress tracking
- Store files with generated unique keys, not user-provided filenames
