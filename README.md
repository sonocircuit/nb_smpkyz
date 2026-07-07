# smpKyz

a six voice polyphonic looping sample nb-player with seamless xfades.

load up to 36 samples with the following requirements:

- .wav format
- file name needs to start with the corresponding midi note number (e.g. `48_mysample.wav` or `48.mysample.wav` or `48-mysample.wav` etc.)
- midi note range 12-104

smpKyz automatically detects which samples have been loaded and calculates the re-pitching for all notes that don't have a sample assigned to. if a folder contains duplicate entries (e.g. multiple dynamic levels like mx.samples) the first file is used and the others ignored. the file can be any sample rate and either mono or stereo. whenever possible samples are pitched down (because it sounds better imo) and only pitched up if the played note exceeds the highest available sample.
