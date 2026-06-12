// smpKey v1.0 - nb player 4 sample instruments - @sonoCircuit

NB_smpKey {

	classvar <skGroup, <skVoices, <skBuffers, <skNoz;
	classvar <loadQueue, <loadingSamples = false;

	*addPlayer {

		if (skGroup.isNil) {

			var s = Server.default;

			Routine.new({

				skGroup = Group.new(s);
				skNoz = Buffer.alloc(s, s.sampleRate * 6);
				s.sync;

				SynthDef(\smpKey_mono, {
					arg outBus, sendABus, sendBBus, sBuf, nBuf,
					vel = 1, amp = 1, pan = 0, spread = 0, drive = 0, noiseAmp = 0, sendA = 0, sendB = 0,
					gate = 1, atkA = 0.001, decA = 0.6, susA = 0.2, relA = 2, atkF = 0.001, decF = 0.6, susF = 0.2, relF = 2,
					pitch = 0, tune = 0, rePitch = 0, startPos = 0, loopIn = 0.1, loopLen = 0.15, fadeRel = 0.6,
					hpfHz = 20, lpfHz = 20000, hpfRz = 0, lpfRz = 0, lpfEnv = 0, hpfEnv = 0, bndAmt = 12, bndDepth = 0,
					modDepth = 0, lpfMod = 0, hpfMod = 0, driveMod = 0, noiseMod = 0, sendAMod = 0, sendBMod = 0;

					var envA, envF, rate, noz, snd, sndA, sndB, phaseA, phaseB;
					var loopTrig, loopDur, loopInit, fadeTime;
					var gain, attn, hpfRq, lpfRq;

					var aOrB = 0, xFade = 1, rateSlew = 0.4;
					var numFrames = BufFrames.ir(sBuf);
					var sR = BufSampleRate.ir(sBuf);

					// scale, remap, math ////////////////////////////////////////////////////////////////////

					// levels
					amp = Lag.kr(amp);
					pan = Lag.kr(pan);
					sendA = Lag.kr(sendA + (sendAMod * modDepth)).clip(0, 1);
					sendB = Lag.kr(sendB + (sendBMod * modDepth)).clip(0, 1);
					noiseAmp = Lag.kr(noiseAmp + (noiseMod * modDepth)).clip(0, 1);

					drive = Lag.kr(drive + (driveMod * modDepth)).clip(0, 1);
					gain = drive.linlin(0, 1, 12, 36).dbamp;
					attn = drive.linlin(0, 1, 0, -16).dbamp;

					// filters
					lpfRq = Lag.kr(lpfRz.linlin(0, 1, 1, 0.12));
					hpfRq = Lag.kr(hpfRz.linlin(0, 1, 1, 0.12));

					// convert pos to frames
					startPos = startPos * sR; // ms > frames
					loopIn = (loopIn * numFrames) + startPos; // frame pos
					loopLen = (loopLen * numFrames).clip(480, (numFrames - loopIn)); // clamp loop frames

					// playback rate
					rate = (pitch + tune + rePitch).midiratio * BufRateScale.kr(sBuf);

					// convert to sec 4 trig timer
					loopInit = (loopIn + loopLen) / (sR * rate);
					loopDur = loopLen / (sR * rate);
					fadeTime = loopDur * fadeRel;
					// bend post sec conversion >> avoid clicks
					rate = Lag.kr(rate * (bndAmt * bndDepth).midiratio, rateSlew);

					// synthesis ///////////////////////////////////////////////////////////////////////////////

					// envelope
					envA = EnvGen.kr(Env.adsr(atkA, decA, susA, relA), gate, doneAction: 2);
					envF = EnvGen.kr(Env.adsr(atkF, decF, susF, relF), gate);

					// trig timer and toggle for looping
					loopTrig = TDuty.kr(Dseq([loopInit, Dseq([loopDur], inf)]), gapFirst:1) * gate;
					aOrB = ToggleFF.kr(loopTrig);

					// phasors. reset at loopIn
					phaseA = Phasor.ar(aOrB, rate, startPos, inf, loopIn);
					phaseB = Phasor.ar((1 - aOrB), rate, startPos, inf, loopIn);

					// buffer read
					sndA = BufRd.ar(1, sBuf, phaseA, 0, 4);
					sndB = BufRd.ar(1, sBuf, phaseB, 0, 4);
					noz = PlayBuf.ar(1, nBuf, startPos: IRand(0, 6 * 48000), loop: 1);


					// xfade
					xFade = VarLag.ar(K2A.ar(aOrB) + Trig.kr(gate), fadeTime, warp: \sine) * 2 - 1; // Trig.kr(gate) used to init Varlag
					snd = XFade2.ar(sndA, sndB, xFade);
					noz = noz * Amplitude.kr(snd, 0.1, 0.6, noiseAmp);
					snd = (snd + noz);

					// filters
					lpfHz = Lag.kr(lpfHz.explin(20, 20000, 0, 1) + (lpfEnv * envF) + (lpfMod * modDepth)).linexp(0, 1, 20, 20000);
					hpfHz = Lag.kr(hpfHz.explin(20, 20000, 0, 1) + (hpfEnv * envF) + (hpfMod * modDepth)).linexp(0, 1, 20, 20000);
					snd = RHPF.ar(snd, hpfHz, hpfRq);
					snd = RLPF.ar(snd, lpfHz, lpfRq);

					// drive/dynamics
					snd = XFade2.ar(snd, (snd * gain).tanh * attn, drive * 2 - 1);
					snd = snd * vel * envA;

					// stereo image
					snd = Pan2.ar(snd, pan, amp);

					Out.ar(outBus, snd);
					Out.ar(sendABus, snd * sendA);
					Out.ar(sendBBus, snd * sendB);
				}).add;

				SynthDef(\smpKey_stereo, {
					arg outBus, sendABus, sendBBus, sBuf, nBuf,
					vel = 1, amp = 1, pan = 0, spread = 0, drive = 0, noiseAmp = 0, sendA = 0, sendB = 0,
					gate = 1, atkA = 0.001, decA = 0.6, susA = 0.2, relA = 2, atkF = 0.001, decF = 0.6, susF = 0.2, relF = 2,
					pitch = 0, tune = 0, rePitch = 0, startPos = 0, loopIn = 0.1, loopLen = 0.15, fadeRel = 0.6,
					hpfHz = 20, lpfHz = 20000, hpfRz = 0, lpfRz = 0, lpfEnv = 0, hpfEnv = 0, bndAmt = 12, bndDepth = 0,
					modDepth = 0, lpfMod = 0, hpfMod = 0, driveMod = 0, noiseMod = 0, sendAMod = 0, sendBMod = 0;

					var envA, envF, rate, noz, snd, sndA, sndB, phaseA, phaseB;
					var loopTrig, loopDur, loopInit, fadeTime;
					var gain, attn, hpfRq, lpfRq;

					var aOrB = 0, xFade = 1, rateSlew = 0.4;
					var numFrames = BufFrames.ir(sBuf);
					var sR = BufSampleRate.ir(sBuf);

					// scale, remap, math ////////////////////////////////////////////////////////////////////

					// levels
					amp = Lag.kr(amp);
					pan = Lag.kr(pan);
					sendA = Lag.kr(sendA + (sendAMod * modDepth)).clip(0, 1);
					sendB = Lag.kr(sendB + (sendBMod * modDepth)).clip(0, 1);
					noiseAmp = Lag.kr(noiseAmp + (noiseMod * modDepth)).clip(0, 1);

					drive = Lag.kr(drive + (driveMod * modDepth)).clip(0, 1);
					gain = drive.linlin(0, 1, 12, 36).dbamp;
					attn = drive.linlin(0, 1, 0, -16).dbamp;

					// filters
					lpfRq = Lag.kr(lpfRz.linlin(0, 1, 1, 0.12));
					hpfRq = Lag.kr(hpfRz.linlin(0, 1, 1, 0.12));

					// convert pos to frames
					startPos = startPos * sR; // ms > frames
					loopIn = (loopIn * numFrames) + startPos; // frame pos
					loopLen = (loopLen * numFrames).clip(480, (numFrames - loopIn)); // clamp loop frames

					// playback rate
					rate = (pitch + tune + rePitch).midiratio * BufRateScale.kr(sBuf);

					// convert to sec 4 trig timer
					loopInit = (loopIn + loopLen) / (sR * rate);
					loopDur = loopLen / (sR * rate);
					fadeTime = loopDur * fadeRel;
					// bend post sec conversion >> avoid clicks
					rate = Lag.kr(rate * (bndAmt * bndDepth).midiratio, rateSlew);

					// synthesis ///////////////////////////////////////////////////////////////////////////////

					// envelope
					envA = EnvGen.kr(Env.adsr(atkA, decA, susA, relA), gate, doneAction: 2);
					envF = EnvGen.kr(Env.adsr(atkF, decF, susF, relF), gate);

					// trig timer and toggle for looping
					loopTrig = TDuty.kr(Dseq([loopInit, Dseq([loopDur], inf)]), gapFirst:1) * gate;
					aOrB = ToggleFF.kr(loopTrig);

					// phasors. reset at loopIn
					phaseA = Phasor.ar(aOrB, rate, startPos, inf, loopIn);
					phaseB = Phasor.ar((1 - aOrB), rate, startPos, inf, loopIn);

					// buffer read
					sndA = BufRd.ar(2, sBuf, phaseA, 0, 4);
					sndB = BufRd.ar(2, sBuf, phaseB, 0, 4);
					noz = PlayBuf.ar(1, nBuf, startPos: IRand(0, 6 * 48000), loop: 1);

					// xfade
					xFade = VarLag.ar(K2A.ar(aOrB) + Trig.kr(gate), fadeTime, warp: \sine) * 2 - 1; // Trig.kr(gate) used to init Varlag
					snd = XFade2.ar(sndA, sndB, xFade);
					noz = noz * Amplitude.kr(snd, 0.1, 0.6, noiseAmp);
					snd = (snd + noz);

					// filters
					lpfHz = Lag.kr(lpfHz.explin(20, 20000, 0, 1) + (lpfEnv * envF) + (lpfMod * modDepth)).linexp(0, 1, 20, 20000);
					hpfHz = Lag.kr(hpfHz.explin(20, 20000, 0, 1) + (hpfEnv * envF) + (hpfMod * modDepth)).linexp(0, 1, 20, 20000);
					snd = RHPF.ar(snd, hpfHz, hpfRq);
					snd = RLPF.ar(snd, lpfHz, lpfRq);

					// drive/dynamics
					snd = XFade2.ar(snd, (snd * gain).tanh * attn, drive * 2 - 1);
					snd = snd * vel * envA;

					// stereo image
					snd = Splay.ar(snd, spread, amp, pan);

					Out.ar(outBus, snd);
					Out.ar(sendABus, snd * sendA);
					Out.ar(sendBBus, snd * sendB);
				}).add;

				s.sync;

				SynthDef(\renderDustNoise, { |buf|
					var sig = Mix.new([PinkNoise.ar(0.5), Dust.ar(5, 1)]);
					sig = HPF.ar(sig, 1800);
					sig = (sig * 36).tanh;
					RecordBuf.ar(sig, buf, loop: 0, doneAction: 2);
				}).play(args: [\buf, skNoz]);

			}).play;

		}

	}

	*queueLoadSample { arg vox, path;
		var t = (vox: vox, path: path);
		loadQueue = loadQueue.addFirst(t);
		if (loadingSamples.not) { NB_smpKey.loadSample() };
	}

	*clearSample { arg vox;
		if (skGroup.notNil) {
			if (skVoices[vox].notNil) { skVoices[vox].set(\gate, -1) };
		};
		if (skBuffers[vox].notNil) {
			if (skBuffers[vox].bufnum.notNil) { skBuffers[vox].free };
			skBuffers[vox] = nil;
		};
	}

	*loadSample {
		var t;
		if (loadQueue.notEmpty) {
			t = loadQueue.pop;
			loadingSamples = true;
			("loading..." + t.vox + t.path).postln;
			NB_smpKey.clearSample(t.vox);
			skBuffers[t.vox] = Buffer.read(Server.default, t.path, action: { NB_smpKey.loadSample() });
		}{
			loadingSamples = false;
		};
	}

	*initClass {

		var voiceParams, numVoices = 8, numBuffers = 36;

		StartUp.add {

			voiceParams = Dictionary.newFrom([
				\amp, 0.8,
				\pan, 0,
				\spread, 0,
				\drive, 0,
				\noiseAmp, 0,
				\sendA, 0,
				\sendB, 0,
				\pitch, 0,
				\tune, 0,
				\startPos, 0,
				\loopIn, 0,
				\loopLen, 1,
				\fadeRel,
				\atkA, 0.01,
				\decA, 0.2,
				\susA, 0.5,
				\relA, 1.2,
				\atkF, 0.01,
				\decF, 0.2,
				\susF, 0.5,
				\relF, 1.2,
				\lpfHz, 20000,
				\lpfEnv, 0,
				\lpfRz, 0,
				\hpfHz, 20,
				\hpfEnv, 0,
				\hpfRz, 0,
				\bndAmt, 1,
				\bndDepth, 0,
				\modDepth, 0,
				\lpfMod, 0,
				\hpfMod, 0,
				\noiseMod, 0,
				\driveMod, 0,
				\sendAMod, 0,
				\sendBMod, 0
			]);

			skVoices = Array.newClear(numVoices);
			skBuffers = Array.newClear(numBuffers);
			loadQueue = Array.new(numBuffers);

			// osc functions
			OSCFunc.new({ |msg|
				if (skGroup.isNil) {
					NB_smpKey.addPlayer();
					"smpKey initialzed".postln;
				};
			}, "/nb_smpkey/init");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				var buf = msg[2].asInteger;
				var rpt = msg[3].asInteger;
				var vel = msg[4].asFloat;
				var syn;
				if (skBuffers[buf].notNil) {
					var def = if (skBuffers[buf].numChannels > 1) {\smpKey_stereo} {\smpKey_mono};
					if (skVoices[vox].notNil) { skVoices[vox].set(\gate, -1.05) };
					syn = Synth.new(def,
						[
							\sBuf, skBuffers[buf],
							\nBuf, skNoz,
							\rePitch, rpt,
							\vel, vel,
							\outBus, Server.default.outputBus,
							\sendABus, ~sendA ? Server.default.outputBus,
							\sendBBus, ~sendB ? Server.default.outputBus,
						] ++ voiceParams.getPairs, target: skGroup
					);
					skVoices[vox] = syn;
					syn.onFree({ if (skVoices[vox] === syn) {skVoices[vox] = nil} });
				};
			}, "/nb_smpkey/play");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				if (skVoices[vox].notNil) { skVoices[vox].set(\gate, 0) }
			}, "/nb_smpkey/stop");

			OSCFunc.new({ |msg|
				if (skGroup.notNil) { skGroup.set(\gate, -1.05) }
			}, "/nb_smpkey/panic");

			OSCFunc.new({ |msg|
				var key = msg[1].asSymbol;
				var val = msg[2].asFloat;
				if (skGroup.notNil) {
					skGroup.set(key, val);
				};
				voiceParams[key] = val;
			}, "/nb_smpkey/set_param");

			OSCFunc.new({ |msg|
				loadQueue = Array.new(numVoices);
				loadingSamples = false;
			}, "/nb_smpkey/reset_loadqueue");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				var path = msg[2].asString;
				NB_smpKey.queueLoadSample(vox, path)
			}, "/nb_smpkey/load_sample");

			OSCFunc.new({ |msg|
				numVoices.do({ |vox|
					NB_smpKey.clearSample(vox)
				});
				"smpkey buffers freed".postln;
			}, "/nb_smpkey/clear_buffer");

			OSCFunc.new({ |msg|
				numVoices.do({ |vox|
					NB_smpKey.clearSample(vox)
				});
				skGroup.free;
				"smpkey removed".postln;
			}, "/nb_smpkey/free_all");

		}
	}
}
