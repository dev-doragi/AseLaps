# AseLaps 2.3.0-rc.1

Source-only development candidate for Aseprite 1.3.18.6+ on Windows (existing API gate retained). This is not a verified public release. No FFmpeg executable, DLL, or external binary is bundled.

## Apply to an existing installation

1. Close Aseprite; back up the existing AseLaps extension directory and recording data.
2. Copy the contents of `extension/` over the existing AseLaps package directory. Do not delete existing files or replace the whole folder: retain the local FFmpeg binary and any companion DLLs, settings, and session data.
3. Reopen Aseprite and run AseLaps from File → AseLaps. Test first with a disposable artwork.

FFmpeg resolution order: `extension/ffmpeg.exe`, `extension/bin/ffmpeg.exe`, `extension/ffmpeg/bin/ffmpeg.exe`, then the previously configured absolute path. `extension/` means the installed package root, not necessarily the directory name in this source tree. Package-local binaries take precedence. The fallback path is retained in preferences. A successful check is cached for the current process, and Settings can force a recheck. The build script intentionally does not bundle FFmpeg; Codex should implement the user's local package/update strategy separately. Do not redistribute third-party binaries before reviewing their licenses.

## User-facing changes

- Resizable compact recorder window; restore previous bounds; one contextual Record/Pause/Resume button. Closing the recorder keeps recording. Record creates a session automatically in the configured recording root.
- Auto Record starts on the first edit, including on an unsaved canvas. The first save links that recording to the artwork path. Reopening the same artwork resumes an active recording on its first edit. Pause and Stop require manual action to record again. Both automatic behaviors can be disabled in Settings.
- Capture policies for new sessions are Balanced (interval), Every edit (change event), Low impact (2 seconds), and Smart Sampling (0.5–2 seconds based on edit events). Sampling does not guarantee one capture per stroke.
- Recording Library discovers sessions under the configured root plus remembered paths, previews the selected session, and opens Studio or resumes the matching artwork. Import supports old session files.
- Studio includes on-demand preview, playback, range sliders/marking, exclusion/restoration, undo of the last edit operation, 15/30/60-second sampling presets and Custom interval; MP4/GIF/PNG output; exact 1080p landscape, vertical, square, portrait presets with integer pixel scaling. Short recordings may produce a shorter duration than the selected target. MP4 uses the existing opaque background requirement.
- Existing history, edited-animation export, crop, resize alignment, and legacy conversion tools remain available. Studio can stay open while recording. Use Refresh preview to include new captures. Editing requires a pause. V4 sessions can export while recording using a fixed frame list and canvas geometry. The optional Smart camera crops every output frame to the final artwork with padding.

## Performance changes

- Existing V4 pack format unchanged. Skip equal 64-byte blocks when finding changed bounds; split distant changed spans only when the resulting representation is smaller. Full/ref and delta selection retained; decoding remains lossless.
- Reopening/resuming a V4 session compares against the previous recorded native frame to avoid an unchanged duplicate capture.
- Preview decodes only nearby frames, does not prebuild a full thumbnail list, and caps preview presentation to at most about 12 updates/sec. Output FPS is unchanged. Very large canvases skip neighboring thumbnails.
- Native V4 GUI video export writes an index and launches the existing C# helper. It reads compressed packs and streams RGBA to FFmpeg through stdin; uses reusable native/output buffers and preserves resize/crop offsets and frame order. No complete RGBA temp file is created on this path. V1–V3 and V4 selections containing edited PNG replacements retain the existing RAW staging path for compatibility. Synchronous command-line export retains its existing pipe path.
- Encoder progress polling reads only a changed file's last 4 KiB. Added no-progress and cancellation deadlines. Existing append-only journal and output commit/rollback protections retained.
- No code obfuscation/minification, new package dependencies, or destructive recompression of existing sessions.

## Verification

Executed here: all Lua files parsed using Lua 5.4; `tests/codec_pure.lua` passed (300 deterministic lossless frames including resize, random seeks, sparse span encoding, sampling, 1080p layout, offset cache). In one deliberately sparse 512-pixel row with two distant changes, the original delta was 2,050 bytes and the revised delta 28 bytes. This is a focused synthetic fixture, not a real-world average. Actual capture P95, disk use, GUI frame rate, and video export performance remain unmeasured.

Not executed here: Windows PowerShell/C# compilation, Aseprite UI, real FFmpeg output and cancellation. Run `tests/native_worker.ps1` and `tests/run.ps1` on Windows before distribution.

See LICENSE for the project license.
