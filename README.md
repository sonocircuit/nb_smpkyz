# smpKyz

a six voice polyphonic looping sample nb-player with seamless xfades.

load up to 36 samples with the following requirements:

- .wav
- file name needs to start with the corresponding midi note number (e.g. `48_mysample` or `48.mysample` or `48-mysample` etc.)
- note range 12-104

smpKyz automatically detects which samples have been loaded and calculates the re-pitching for all notes that don't have a sample assigned to. if a folder contains duplicate entries (e.g. multiple dynamic levels like mx.samples) the first file is used and the others ignored. the file can be any sample rate and mono or stereo.

_**under construction - expect changes**_
