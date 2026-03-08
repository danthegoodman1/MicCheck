# MicCheck

`MicCheck` is a minimal macOS CLI that reports whether any microphone input is currently active.

It uses CoreAudio process objects first, then falls back to device state if process-level detection is unavailable. The default output is script-friendly `0` or `1`, and `--detailed` emits a single JSON object to `stdout`.

## Requirements

- macOS 15+
- Swift 6.2 toolchain or newer

No Xcode project is required. Everything builds with Swift Package Manager from the terminal.

## Quickstart

```sh
make test
make release
make run
make detailed
```

## Build

```sh
swift build -c release
make release
```

The binary will be available at:

```sh
./.build/release/MicCheck
```

If you want a small wrapper around the common commands, the included `Makefile` provides:

- `make build`
- `make release`
- `make test`
- `make run`
- `make detailed`
- `make debug`
- `make clean`

## Usage

```sh
MicCheck
MicCheck --detailed
MicCheck --detailed --debug
make run
make detailed
make debug
```

### Default output

Prints `1` if any process on the system currently has an active input stream, otherwise `0`.

Example:

```sh
$ MicCheck
0
```

### Detailed output

Prints one JSON object with:

- `active`
- `activeProcessCount`
- `activeDeviceCount`
- `device`

The `device` object includes:

- `id`
- `name`
- `uid`
- `manufacturer`
- `sampleRate`
- `inputChannelCount`
- `transportType`
- `isAlive`
- `isRunningSomewhere`
- `isDefaultInput`

Example:

```json
{"active":false,"activeDeviceCount":0,"activeProcessCount":0,"device":null}
```

### Debug logging

`--debug` writes diagnostic logs to `stderr`. Structured output remains on `stdout`.

The debug output includes:

- the detected default input device ID
- the number of CoreAudio process objects inspected
- any active process-to-device matches
- which detection path produced the final snapshot

## How detection works

1. Query `kAudioHardwarePropertyProcessObjectList`.
2. Inspect each process object’s `kAudioProcessPropertyIsRunningInput`.
3. Collect active input device IDs from `kAudioProcessPropertyDevices`.
4. If process-based detection fails, fall back to checking input-capable devices with `kAudioDevicePropertyDeviceIsRunningSomewhere`.

This is a one-shot snapshot tool. It does not poll or install listeners.

## Testing

Run the automated tests:

```sh
swift test
make test
```

Run the release binary:

```sh
./.build/release/MicCheck
./.build/release/MicCheck --detailed
make run
make detailed
```

If you want to force microphone activity from the terminal, one option is to briefly record from AVFoundation:

```sh
ffmpeg -f avfoundation -list_devices true -i ""
ffmpeg -f avfoundation -i ":<audio-index>" -t 5 /tmp/miccheck-test.wav
```

Or with SoX:

```sh
rec /tmp/miccheck-test.wav trim 0 5
```

While that recording is running, `MicCheck` should report active input.

Note: the first attempt may trigger the macOS microphone permission prompt for Terminal or the shell-hosting app.

## Distribution

This project is intended to stay small and terminal-first. If you later want to distribute the binary outside local use, signing can be handled with CLI tooling such as `codesign` without introducing an Xcode project.

For a local release flow:

```sh
make release
codesign -s - ./.build/release/MicCheck
```
