QEMU package here is compressed by using 7zip v24 (2024)

extract zip file to a directory/folder (for example: TRDOS386)
and run trdos386cboot_mp3.cmd for ac97 test
        trdos386cboot2_mp3.cmd for sb16 test

after c:/> prompt appears, write 'cd mp3' then
'dir' to see mp3 files and program files.

(Use '?' to see valid -trdos command interpreter- commands.
TRDOS 386 console/mainprog commands are similar to MSDOS command.com
commands.)
Note: Directory separator is '/' in TRDOS just as in unix/linux.

MP3PTEST.PRG is a test (a bit modified MP3PLAY3.PRG) program
to check/test interpolation quality of the program
for non-VRA AC97 codecs.

(Emulator's virtual AC97 hardware has VRA feature and this test
program overwrites vra parameter for using interpolation procedures.)

Non-VRA codecs only play 48kHZ mp3/wav files at normal speed.
MY "Interpolated sample rate playing method" converts
samples/waves to 48 kHZ, 16bit, stereo samples/waves by inserting
proper count of interpolated (before-interpolated-next) 
additional samples between original mp3/wav audio samples without
a significant sound wave deformation.

MP3PLAY0.PRG (fasm) & MP3PLAY2.PRG (nasm)
	: mp3player program without interpolation procedures
          and with indicator digits for buffer/interrupt events

MP3PLAY1.PRG: 
	: without interpolation and without indicator

MP3PLAY3.PRG:
	: with interpolation and with buffer/interrupt indicator
	  (will play -44 kHZ and other freqs- mp3 files at normal speed)
	  proper to use on real computer in addition to emulators
	  -remember: some AC97 audio systems play at 48 kHZ only-	 	

MP3PTEST.PRG:
	: Modified MP3PLAY3.PRG to test Interpolation quality
          for running on QEMU and VirtualBOX etc. emulators
	  (disables detected VRA feature to force interpolation and
	  setting AC97 audio play frequency to 48 kHZ.) -trick-

All of above programs has Sound Blaster 16 support.
Even if SB16 can not play 48 kHZ audio files (limit is 44.1 kHZ).
I have seen QEMU's virtual SB16 hardware can play 48 kHZ audio.

I will write FASM variant of MP3PLAY3.PRG (source code: NASM)
and MP3PLAY0.PRG will be equilavent of MP3PLAY3.PRG
(currently it is same with MP3PLAY2.PRG)

In fact.. original and these Nocash MP3PLAYERs are not a player only..
          they are mp3 decoder, mp3 to wav converter
	  and frequency converted playback programs.
	  	 
MP3PLAY4.PRG and successors will be different (will go to different way).
-I will focus on playing in text mode and VGA and VESA VBE mode with
wave lighting graphics like as my playwav programs-

My current mp3 player programs also have decoder
and wav converter feature and performance test parameters
just as Martin Korth's Nocash MP3 Player (for dos/windows) has them.
(I have used/adapted his source code.)

Erdogan Tan - 15/01/2025
