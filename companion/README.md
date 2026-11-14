# CasaPlay ↔ NihonSub (Mac companion)

Makes English, Hindi or Hinglish subtitles for Japanese video, from inside CasaPlay.

NihonSub only accepts uploaded files, and an Apple TV shouldn't upload a whole film. So a small
bridge runs next to NihonSub on your Mac:

1. CasaPlay sends the stream's link to the bridge.
2. The bridge reads only the audio from that link with FFmpeg.
3. NihonSub (Groq Whisper + an LLM) transcribes and translates it.
4. CasaPlay downloads the finished SRT and shows it in the player.

Works with streams that have a web link (HTTPS add-on streams, your own server). Streams that
play straight from a torrent on the Apple TV have no link the Mac can read.

## Setup

```
bash companion/setup.sh     # once: gets NihonSub, installs it, saves your Groq key
bash companion/start.sh     # every time: starts NihonSub and the bridge
```

`start.sh` prints an address and a token. Enter both in CasaPlay › Profile › Online services ›
NihonSub, then press **Test keys**.

## Notes

- NihonSub runs on this Mac only. Only the bridge is reachable from other devices, and it needs the
  token. The token is in `companion/.bridge-token` (created on first run, private to you).
- NihonSub is MIT licensed (github.com/Abhishantpadam/NihonSub). `setup.sh` uses the version this
  bridge was checked against.
- The audio and the transcript are sent to Groq (and OpenRouter if you configure it in NihonSub),
  the same as using NihonSub directly. Only use video you're allowed to process.
- Tests: `node --test companion/test/bridge.test.mjs`
