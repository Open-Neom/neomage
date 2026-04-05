# Twilio Communications

Build communication features with Twilio: SMS, voice calls, WhatsApp, and phone verification (2FA).

- Phone numbers must be in E.164 format (+1234567890); validate before sending
- SMS messages over 160 characters are split into segments (each costs separately)
- Default SMS rate limit: 80 messages per second; implement app-level rate limiting too
- Use Twilio Verify for 2FA/OTP instead of DIY: manages code generation, expiration, and fraud prevention
- Twilio Verify supports multiple channels: SMS, voice, email, WhatsApp, push
- For IVR systems, use TwiML (XML): key verbs are Say, Play, Gather, Dial, Record, Redirect
- Always validate webhook signatures with RequestValidator to prevent spoofed requests
- Register for A2P 10DLC for US SMS (compliance requirement); track opt-out status in your database
- Track WhatsApp session windows per user (24-hour messaging window rule)
- Never hardcode credentials; use environment variables for account SID, auth token, and phone numbers
