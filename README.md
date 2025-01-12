### MP3 PLAYER (for Windows console & TRDOS386) & ASM Source Code (FASM) ###

This repository contains MP3PLAYER/MP3DECODER source code and samples and variants which are written in ASSEMBLY Language (syntax of FASM, NASM and TASM).

I was searching MP3 player source code which is/are written in Assembly language, to port/adapt it/them to TRDOS 386 operating system.

(I could not used any mp3 decoder/player source code which is written in C/C++ because -currently- it is not possible to compile it/them for TRDOS 386 operating system.

So, if I could find an ASM example -of MP3 decoder/player-, I would change/modify it's syntax to FASM -has TRDOS 386 adaptation- and NASM with OS specific function modifications. Till October 2024, I could not find an example.)

About 1 week ago, I saw Martin Korth's program on his web site (https://problemkaputt.de/mp3.htm).

NOCASH (nickname) MP3 decoder/player file: MP3PLAY.EXE v1.4 (a windows console application).
I tried it on a Windows 7 desktop (I am using this desktop computer for program development). And I have confirmed it is succesful, plays my mp3 files correctly.

(Specially I have tested it with 'yillar.mp3' file. 'Yillar Sonra' Anatolian Rock/Pop song by Kirac in Turkish. Timing/Speed and sound quality is good/normal when it is played by MP3PLAY.EXE. The CPU is AMD Athlon Dual Core, 2.2 GHz.)

Martin Korth's MP3 player/decoder uses fixed point arithmetics (by using 32 bit fractions) instead of FPU instructions.
He and others say fixed point arithmetic based MP3 player is more proper for old (hardware) computers. Like as computers which have Pentium series and 486 CPUs.

The original NOCASH MP3PLAYER source code is in TASM syntax/format and it has more and more (repetition) macros in the two files (mp3play.asm and mp3.asm).
It is very complex for me. Also i have could not assemble it by using TASM assembler (5.0) on my computer.

So, i have decided to disassemble mp3play.exe (v1.4, 20/09/2024) by using HEX-RAYS IDA Pro disassembler. Writing labels and explanations/comments on the disassembled code took about 2-3 days, then, I have completed disassembling of the 44KB EXE file.
But another difficulty is to convert disassembled ASM code to FASM or NASM syntax. (I have preferred FASM because of direct assemble/link ability for Windows PE files.
I have decided to write the Windows version of the modified (nocash) mp3 player before the TRDOS 386 adaption/version of it.
After a searching phase, by help of FASM examples, I have converted Windows kernel/dll function calls to proper forms of FASM '.idata' section for PE format.
(Succesful finish: at the end of 17/10/2024. My MP3 player source code needs to be more edited, still it is as disassembled -semi raw- source code. 

But this source code (view) modifications/fixes would not affect EXE file. (Except any possible bugfixes and optimizations.) 

Perhaps I can modify and optimize source code in near future for increasing speed and decreasing file size. This will be depended on TRDOS 386 adaptation of the nocash MP3 player.)

NOTE: TRDOS 386 adaptation/port of this MP3 player is not ready yet. (18/10/2024)

      **** TRDOS386 port/adaptaiton of NOCASH MP3 PLAYER is READY! (12/01/2025) ***** here.. in this repository.

(In near future, I also think to develop a compressed audio file format for 16 bit DOS and 32 bit TRDOS. Instead of MP3.
I think to use/develop 'wave peak points' based frame compression. Decompressed frame will be about 32KB. This buffer size is proper for 16 bit DOS .COM files.
As I have already got big/huge WAV file players (.COM files) for DOS and (.PRG files) TRDOS 386, I think to use same audio buffering and playing logic. So, I see that a new type frame compression -5 to 10 times lossy or 3 to 5 times lossless compression of wav files- will be good for me.)
       
Erdogan Tan - 18/10/2024

MP3PLAYER demo (youtube): https://youtu.be/kQc7F5pgiYs?si=6p9wkdjeV0P3MyMm (10/01/2025)

NOTE: Try TRDOS 386 MP3 PLAYERs which last modification date is shown as 12/01/2025 or later. You can test them via QEMU package in this repository.
      Start TRDOS 386 on QEMU and change directory to mp3 and then use/run programs just as how MSDOS and Windows console programs are used.
       
