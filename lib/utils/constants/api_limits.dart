// Anthropic API Limits — ported from OpenClaude src/constants/apiLimits.ts.

// ── Image Limits ──

/// Maximum base64-encoded image size (API enforced). 5 MB.
const int apiImageMaxBase64Size = 5 * 1024 * 1024;

/// Target raw image size to stay under base64 limit after encoding. ~3.75 MB.
const int imageTargetRawSize = (apiImageMaxBase64Size * 3) ~/ 4;

/// Client-side maximum width for image resizing.
const int imageMaxWidth = 2000;

/// Client-side maximum height for image resizing.
const int imageMaxHeight = 2000;

// ── PDF Limits ──

/// Maximum raw PDF file size. 20 MB.
const int pdfTargetRawSize = 20 * 1024 * 1024;

/// Maximum number of pages in a PDF accepted by the API.
const int apiPdfMaxPages = 100;

/// Size threshold above which PDFs are extracted into page images. 3 MB.
const int pdfExtractSizeThreshold = 3 * 1024 * 1024;

/// Maximum PDF file size for the page extraction path. 100 MB.
const int pdfMaxExtractSize = 100 * 1024 * 1024;

/// Max pages the Read tool will extract in a single call.
const int pdfMaxPagesPerRead = 20;

/// PDFs with more pages than this get reference treatment on @ mention.
const int pdfAtMentionInlineThreshold = 10;

// ── Media Limits ──

/// Maximum number of media items (images + PDFs) per API request.
const int apiMaxMediaPerRequest = 100;
