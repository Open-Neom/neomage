# PPTX Presentation Creation & Editing

Create, edit, and analyze PowerPoint presentations using HTML-to-PPTX workflows and OOXML manipulation.

- Reading content: use `markitdown` for text extraction, unpack to XML for comments, notes, layouts, and animations
- Creating without template: use html2pptx workflow (HTML slides converted to PPTX with accurate positioning)
- Design principles: choose colors matching subject matter, use web-safe fonts only, ensure strong contrast and readability
- Build color palettes of 3-5 colors (dominant + supporting + accent) that reflect the topic and audience
- Layout rules: prefer two-column or full-slide layouts for charts/tables; never vertically stack content below text
- Editing existing: unpack OOXML, edit XML directly, validate after each edit, repack
- Template-based creation: extract text, create visual thumbnail grid, analyze inventory, map content to template slides
- Use rearrange.py to duplicate/reorder template slides, inventory.py to extract shapes, replace.py to apply new content
- Visual validation: generate thumbnail grids to catch text cutoff, overlap, positioning, and contrast issues
- Key OOXML paths: ppt/slides/slideN.xml (content), ppt/notesSlides/ (notes), ppt/theme/ (styling)
