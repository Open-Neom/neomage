# XLSX Spreadsheet Creation & Analysis

Create, edit, and analyze Excel spreadsheets with proper formulas, formatting, and data analysis.

- Always use Excel formulas instead of hardcoding Python-calculated values; spreadsheets must remain dynamic
- Library selection: pandas for data analysis and bulk operations; openpyxl for formulas, formatting, and Excel features
- Financial color coding: blue text for inputs, black for formulas, green for cross-sheet links, yellow background for key assumptions
- Number formatting: currency as $#,##0, zeros as "-", percentages as 0.0%, negatives in parentheses, years as text
- Place all assumptions in separate cells; reference them in formulas instead of embedding magic numbers
- After creating/modifying formulas, always recalculate with recalc.py (LibreOffice-based) and fix any errors
- Common errors to check: #REF! (invalid references), #DIV/0! (division by zero), #VALUE! (wrong types), #NAME? (unknown formula)
- Cell indices in openpyxl are 1-based; opening with data_only=True and saving will permanently replace formulas with values
- Document sources for all hardcoded data: "Source: [System], [Date], [Reference], [URL]"
- Verify formulas on 2-3 sample cells before applying broadly; test with edge cases (zero, negative, large values)
