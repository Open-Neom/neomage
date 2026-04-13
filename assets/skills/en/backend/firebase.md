# Firebase
Build with Firebase (Auth, Firestore, Functions, Storage, Hosting) while avoiding its sharp edges.
- Firebase is optimized for read-heavy, denormalized data -- do NOT design Firestore like SQL
- CRITICAL: write security rules from day one; skipping rules leads to data breaches
- CRITICAL: never attach listeners to large collections; this causes runaway costs
- Design Firestore data structure around query patterns, not normalized relations
- Use modular SDK imports for smaller bundles; import only what you need
- Admin operations belong in Cloud Functions (server-side), never on the client
- Use Firebase emulators for local development and testing before hitting production
- Firestore queries are limited: no arbitrary JOINs, no full-text search, no inequality on multiple fields
- Plan for cost: reads, writes, and bandwidth all cost money; denormalize to reduce reads
- Works well with: Next.js, React patterns, OAuth authentication, Stripe
