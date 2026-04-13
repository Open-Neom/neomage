# Audio Transcriber

Transform audio recordings into structured Markdown documentation with speaker identification, timestamps, and intelligent summaries.

- Auto-detect transcription engines: prefer Faster-Whisper (4-5x faster), fall back to OpenAI Whisper
- Supported formats: MP3, WAV, M4A, OGG, FLAC, WEBM; use ffmpeg for format conversion if needed
- Validate audio file: check existence, extract metadata (duration, size, format) via ffprobe
- Warn on large files (>25MB) that processing may take several minutes
- Output structured Markdown with: metadata table, full transcription with timestamps, meeting minutes
- Meeting minutes extract: topics discussed, decisions made, and action items with assignees
- Speaker diarization identifies individual speakers in multi-person recordings
- Generate executive summaries using LLM integration for long audio content
- Supports batch processing of multiple audio files in a directory
- Output files use timestamps in names to avoid overwriting previous transcriptions
