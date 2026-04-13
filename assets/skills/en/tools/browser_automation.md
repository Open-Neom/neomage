# Browser Automation

Reliable browser automation using Playwright (preferred) and Puppeteer for testing, scraping, and agentic control.

- Playwright is the recommended framework unless you need Puppeteer's stealth ecosystem or Chrome-only support
- Most automation failures come from three sources: bad selectors, missing waits, and detection systems
- Use user-facing locators (text, role, label) instead of CSS/XPath selectors
- Let Playwright's auto-wait handle timing; never add manual `waitForTimeout` calls
- Each test must run in complete isolation with fresh browser context and state
- For scraping: add delays between requests, use stealth plugins, rotate user agents
- Enable traces for failure debugging rather than relying on screenshots alone
- Set consistent viewport sizes to avoid layout-dependent test flakiness
- Wait for popups/dialogs before triggering the action that opens them
