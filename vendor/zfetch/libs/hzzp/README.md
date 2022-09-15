# hzzp

[![Linux Workflow Status](https://img.shields.io/github/workflow/status/truemedian/hzzp/Linux?label=Linux&style=for-the-badge)](https://github.com/truemedian/hzzp/actions/workflows/linux.yml)
[![Windows Workflow Status](https://img.shields.io/github/workflow/status/truemedian/hzzp/Windows?label=Windows&style=for-the-badge)](https://github.com/truemedian/hzzp/actions/workflows/windows.yml)
[![MacOS Workflow Status](https://img.shields.io/github/workflow/status/truemedian/hzzp/MacOS?label=MacOS&style=for-the-badge)](https://github.com/truemedian/hzzp/actions/workflows/macos.yml)

A I/O agnostic HTTP/1.1 parser and encoder for Zig.

## Features

* Performs no allocations during parsing or encoding, uses a single buffer for all parsing.
* Relatively simple to use.
* Works with any Reader and Writer.

## Notes

* hzzp does **not** buffer either reads or writes, if you prefer the performance boost such buffering provides, you must
  provide your own buffered Reader and Writers.

## Examples

**Coming Soon...**
