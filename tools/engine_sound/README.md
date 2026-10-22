# Engine sounds

The car engines are rendered with [Engine Simulator](https://github.com/ange-yaghi/engine-sim) by AngeTheGreat
(MIT licence), built for Linux without its Windows interface:

- `build.sh` compiles the simulator core; piranha (its scripting language) is compiled with `scanner_hand.cpp`,
  a hand-written replacement for its flex scanner (`FlexLexer.h` is the matching minimal base class), with
  boost::filesystem swapped for std::filesystem and a few MSVC-only constructs made standard.
- `recorder.cpp` loads an engine script, starts the engine, holds it on the dynamometer at given RPMs with the
  throttle open and closed, and writes each to a WAV (fixed gain, no automatic levelling).
- `record_all.sh`, `record_b.sh` record the engines used in the game (seven speeds each).
- `make_loops.py` cuts each recording into a seamless loop of whole engine cycles, narrows the loudness gap and
  encodes Ogg (`assets/sfx/eng_<engine>_<rpm>_<on|off>.ogg`, `eng_<engine>_idle.ogg`).
- `demo.py` is an offline copy of the in-game engine model (scripts/core/sfx.gd) that renders a run to MP3.
