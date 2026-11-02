# Custom animation research

Reviewed on 2026-11-02 for HyperX Mars `0951:16c6` and Redragon M711
`04d9:fc30`. The earlier statement that custom animations are impossible was too
absolute. The implemented native compositions are customizable; arbitrary host
frames require a transport whose persistence and timing are understood.

## HyperX Mars

[NeoGenesis's current protocol investigation](https://github.com/lexmarcos/NeoGenesis/blob/main/PROTOCOL.md#volatile-write-ram-sought-and-not-found)
reports that observed Genesis lighting updates use a complete onboard profile
transaction. Its capture and reconnect experiments found no temporary lighting
path. The author explicitly limits this conclusion to the commands observed in
the manufacturer software; an undocumented firmware command is not ruled out.
The `04 E0` query maintains multicolor breathing, but carries no pixel colors.

The [OpenRGB Mars request](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/656)
and [Artemis Mars request](https://github.com/Artemis-RGB/Artemis/issues/410)
do not supply a proven direct-mode protocol. Support for other HyperX models
does not establish support for this USB model.

Two leads remain:

- **Stock firmware analysis:** identify a documented RAM command in an actual
  firmware image or additional vendor software. A missing command in one app is
  not proof that the firmware lacks one. Its existence remains unverified.
- **A firmware port:** [SonixQMK](https://sonixqmk.github.io/SonixDocs/compatible_kb/)
  supports specific compatible MCU/board combinations, and says unlisted boards
  can potentially be ported. Mars is not listed. A Sonix-named vendor DLL is only
  a lead about the controller family; identifying the actual MCU, PCB, LED driver
  and recovery method is needed before evaluating a port. There is no established
  drop-in Mars image in the sources checked.

There is also a narrower software experiment: **beat-gating the existing
multicolor breathing engine with E0 query timing**. This is an inference from its
reported dependence on polling, not a demonstrated audio visualizer. It might
affect whole-board animation pacing without repeated profile writes. Visual
observation is needed to learn whether polling controls useful beat timing or
merely a watchdog. It would not provide arbitrary per-key spectrum bars.

## Redragon M711

The [Redragon RGB SDK](https://github.com/D4rkTT/Redragon-RGB-SDK) offers arbitrary
RGB updates for this mouse. Its
[actual implementation](https://github.com/D4rkTT/Redragon-RGB-SDK/blob/master/Redragon%20RGB%20SDK/Source.cpp)
writes a color with `F3`, then sends `F1 02 04` to apply it on every call. That
matches the write/apply sequence used by
[OpenRGB's controller](https://github.com/CalcProgrammer1/OpenRGB/blob/master/Controllers/RedragonController/RedragonMouseController.cpp).
OpenRGB labels its modes as automatically saved. The SDK therefore demonstrates
programmable color changes, but does not establish a separate RAM streaming mode.
The exact physical persistence cost of each mouse command is not measured here.

[hidproto's M711 adapter](https://github.com/Chocapikk/hidproto/blob/master/protocols/redragon/m711.py)
also uses write/apply commands and cites OpenRGB. It does not add evidence of a
temporary transport. An app advertised as an audio visualizer can use the saved
configuration path; its existence alone does not settle update persistence.

The next useful mouse investigation is to distinguish staging from persistence
using documented commands, source analysis and a controlled observation of the
actual device. No verified persistent-write-free frame path was found in these
sources. Voluta continues to use native effects rather than treating configuration
writes as an animation stream.
