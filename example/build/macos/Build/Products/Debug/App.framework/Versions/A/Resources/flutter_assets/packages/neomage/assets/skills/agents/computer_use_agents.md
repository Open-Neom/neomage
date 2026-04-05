# Computer Use Agents

Build AI agents that interact with computers via screen vision, mouse, keyboard, and shell commands.

- Perception-Reasoning-Action loop: screenshot capture -> vision-language model analysis -> execute mouse/keyboard action -> observe result -> repeat
- Agents pause 1-5 seconds during "thinking" phase, creating a detectable pattern between actions
- ALWAYS sandbox: run in Docker containers with virtual desktops (Xvfb + VNC), never on host system directly
- Sandbox requirements: restrict network, read-only filesystem, no host credentials, filter syscalls, limit CPU/memory/time
- Anthropic Computer Use tools: screenshot, mouse (click/move/drag), keyboard (type/press), bash, text_editor
- Resize screenshots to 1280x800 for good balance between token efficiency and detail
- Set max_steps limit (e.g., 50) to prevent runaway loops; add action delays between steps
- Tricky UI elements: dropdowns, scrollbars, and dynamic content may require keyboard alternatives
- Use keyboard shortcuts when possible -- they are more reliable than vision-based clicking
- Cost and latency are high (vision model calls per step); monitor and limit both aggressively
