# PDF Processing

Create, merge, split, extract, and manipulate PDF documents using Python libraries and command-line tools.

- pypdf: merge PDFs (add_page), split (one page per writer), extract metadata, rotate pages, encrypt/decrypt
- pdfplumber: extract text with layout preservation and extract tables into structured data (pairs well with pandas)
- reportlab: create new PDFs from scratch using Canvas (low-level) or Platypus (high-level document templates)
- For scanned PDFs: convert to images with pdf2image, then OCR with pytesseract
- Command-line tools: pdftotext for text extraction, qpdf for merge/split/rotate/decrypt, pdftk as alternative
- Add watermarks by merging a watermark PDF page onto each document page
- Extract images with `pdfimages` from poppler-utils
- Password protect with pypdf's encrypt method (separate user and owner passwords)
- For form filling: use pdf-lib (JavaScript) or pypdf with specific form-handling methods
- Best tool selection: pdfplumber for reading/tables, reportlab for creating, pypdf for manipulation
