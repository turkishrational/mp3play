;:----------------- MP3 player
;------------------
IFNDEF TINY
 with_standard_features equ 1   ;standard version with all commandline switches
 be_fast                equ 1   ;want fast code
 prefer_dirty           equ 0   ;this is don't care here (if with_fast_option is enabled)
ELSE
 with_standard_features equ 0   ;tiny version (for 9.5 Kbyte EXE packed with kkrunchy)
 be_fast                equ 0   ;want smaller (and slightly slower) code
 prefer_dirty           equ 1   ;want smaller (but less accurate) code (smaller because the smaller synth_win constants do copress better)
ENDIF
;------------------
 ENQUEUE_DUMB     equ 01  ;callback enqueue only NEW frames         ;\
 ENQUEUE_FROM_WOM equ 0   ;callback enqueue ALL frames              ; enable ONE
 ENQUEUE_DUAL_INC equ 0   ;main program with TWO counters           ; of these
 ENQUEUE_LOCK     equ 0   ;main program with dual-core LOCK counter ;/
;------------------
with_output_to_speaker  equ 1                         ;\
with_output_to_wav_file equ with_standard_features    ; enable at least one of these
with_verify_to_pcm_file equ with_standard_features    ;
with_raw_testing        equ with_standard_features    ;/
with_8bit_output        equ with_standard_features    ;\
with_rate_shift         equ with_standard_features    ; extra options
with_fast_option        equ with_standard_features    ;/
with_free_format        equ 1                         ;-obscure feature
with_all_footer_tags    equ with_standard_features    ;-good to have (but eats up 175 bytes when compressed)
;------------------
log_file_info           equ with_standard_features
log_waveout_errors      equ with_standard_features
log_timing              equ with_raw_testing
log_init                equ 0;1         ;\
log_frames              equ 0;1         ; should be 0
log_granules            equ 0;1         ; (except for debugging)
log_huffcodes           equ 0;1         ;   ;\these output a LOT of data
log_scalefac            equ 0;1         ;   ;/
log_waveout_status      equ 0;1         ;
log_fatal               equ 0;1         ;
wav_file_block_marker   equ 0           ;/
;------------------
code_align equ (1+be_fast*15)   ;1=none/small, 16=fast/bigger
data_align equ (4+be_fast*12)   ;4=dword/small, 16=fast/bigger
;------------------
;assemble via TASM 5.0 or similar
;MCOM32.BAT
; @ echo off
; tasm32 /ml /m5 %1 %2 %3 %4 %5
; IF exist %1.EXE    del %1.EXE
; IF exist %1.RC     brcc32 %1 %2 %3 %4 %5
; IF exist %1.RC     tlink32 %1,%1,,,,%1 -x -Tpe -ap -V4.0
; IF NOT exist %1.RC tlink32 %1,%1,,,,   -x -Tpe -ap -V4.0
; IF exist %1.OBJ    del %1.OBJ
;---
;for the tiny version
;MCOM32KK.BAT
; @ echo off
; tasm32 /ml /m5 %1 %2 %3 %4 %5 /dTINY=1
; IF exist %1.EXE    del %1.EXE
; IF exist %1.RC     brcc32 %1 %2 %3 %4 %5
; IF exist %1.RC     tlink32 %1,%1,,,,%1 -x -Tpe -ap -V4.0 -B:800000h
; IF NOT exist %1.RC tlink32 %1,%1,,,,   -x -Tpe -ap -V4.0 -B:800000h
; IF exist %1.OBJ    del %1.OBJ
; IF exist %1.EXE    kkrunchy %1.exe --refsize 10
;note: there are currently two kkrunchy versions:
; kkrunchy.exe    --> FAST decompression and BETTER compression ratio
; kkrunchy_k7.exe --> ULTRASLOW decompression and WORSE compression ratio
;------------------
.386
;---
 ;below does override .model flat's alignment for .code/.data/.data?
 ;(default is 4-byte, but PARA (16-byte) is faster on Pentium III
 _TEXT SEGMENT PUBLIC PARA 'CODE' USE32           ;\for .code
 ends                                             ;/
 _DATA SEGMENT PUBLIC PARA 'DATA' USE32           ;\for .data
 ends                                             ;/
 _BSS  SEGMENT PUBLIC PARA 'BSS'  USE32 ;UNINIT   ;\for .data?
  ;note: adding "UNINIT" in above line causes     ;
  ;lots of warning on "align" inside .data?       ;
  ;(that could be perhaps disabled via NOWARN UNI);
  ;(anyways it works fine with "UNINIT")          ;
 ends                                             ;/
;CONST SEGMENT PUBLIC PARA 'CONST' USE32 READONLY ;\for .const
; ;hmm, causes "illegally redefined" - why ???    ;
;ends                                             ;/
;---
 .model flat,STDCALL
.code
locals
includelib \talky\tasm32\import32.lib
;---
loop equ loopd      ;XXX is that required/working? and if so also for loopz etc.
moz  equ movzx
vals equ ebp    ;XXX not actually used
jcxz macro dist,adr    ;\IMPORTANT!!!
  jecxz dist adr       ; unlike rep/popa, this isn't automatically 32bit!
endm                   ;/(must be a macro, equ would be ignored!)
;---
extrn GetStdHandle              :proc
extrn CreateFileA               :proc
extrn SetFilePointer            :proc
extrn ReadFile                  :proc
extrn WriteFile                 :proc
extrn CloseHandle               :proc
extrn GetFileSize               :proc
extrn CreateFileMappingA        :proc
extrn MapViewOfFile             :proc
extrn waveOutUnprepareHeader    :proc
extrn waveOutPrepareHeader      :proc
extrn waveOutWrite              :proc
extrn waveOutOpen               :proc
extrn waveOutReset              :proc
extrn waveOutClose              :proc
extrn waveOutPause              :proc
extrn waveOutRestart            :proc
extrn GetTickCount              :proc
extrn GetCommandLineA           :proc
extrn Sleep                     :proc
extrn ExitProcess               :proc
;---
FALSE                   equ 0
TRUE                    equ 1
INVALID_HANDLE_VALUE    equ -1
STD_INPUT_HANDLE        equ -10
STD_OUTPUT_HANDLE       equ -11
NULL                    equ 0
CREATE_ALWAYS           equ 2
OPEN_EXISTING           equ 3
GENERIC_READ            equ 80000000h
GENERIC_WRITE           equ 40000000h
FILE_SHARE_READ         equ 1h
FILE_SHARE_WRITE        equ 2h
FILE_ATTRIBUTE_NORMAL   equ 80h
FILE_BEGIN              equ 0
CALLBACK_FUNCTION       equ 30000h
MMSYSERR_NOERROR        equ 0
SECTION_MAP_READ        equ 4h
FILE_MAP_READ           equ SECTION_MAP_READ
PAGE_READONLY           equ 2
WAVE_MAPPER             equ -1
MM_WOM_OPEN             equ 3BBh
MM_WOM_CLOSE            equ 3BCh
MM_WOM_DONE             equ 3BDh
WOM_OPEN                equ MM_WOM_OPEN
WOM_CLOSE               equ MM_WOM_CLOSE
WOM_DONE                equ MM_WOM_DONE
;------------------
.data
align data_align
option_test       dd 0
option_mono       dd 0
option_8bit       dd 0
option_rate_shift dd 0
option_fast       dd 0
align data_align
.code
;------------------
;:----------------- Timelog
;------------------
IF log_timing EQ 0
 timelog_start macro
 endm
 timelog_end macro
 endm
 timelog_display_results macro
 endm
 align code_align
 xmit_force_highest_priority: ret
 align code_align
 xmit_resume_normal_priority: ret
ELSE
 ;------------------
 cpuid$ macro    ;tasm 1.0 cannot assemble 'cpuid'
  db 0fh,0a2h    ;tasm 4.0 claims cpuid is a reserved word
 endm            ;so we use cpuid$
 ;------------------
 detect_cpu_386_and_up:  ;io=same - fatal/errmess if unsupported
  mov  byte ptr [detected_cpu],3   ;-assume min 386 (as this is a 32bit program)
 ;---386 / 486+ separation (taken from code by dave navarro jr)
  mov  ebx,esp           ;\save old sp and zero lower 2 bits
  and  esp,not 3         ;/of (e)sp to avoid AC fault on 486
  pushfd                 ;\
  pop  eax               ; read eflags to eax (and backup in ecx)
  mov  ecx,eax           ;/
  xor  eax,40000h        ;\
  push eax               ; toggle AC bit (bit 18) in eflags
  popfd                  ;/
  pushfd                 ;\
  pop  eax               ; read new value of eflags and XOR with old value
  xor  eax,ecx           ;/
  push ecx               ;\
  popfd                  ; restore old eflags and old sp
  mov  esp,ebx           ;/
  test eax,40000h        ;-test bit 18 in eax (must be 0 if old val was same)
  jz   short @@no_id     ;-yes, it's a 386
  inc  byte ptr [detected_cpu]   ;-inc to 486, and continue with pentium check
 ;---486 / pentium separation via "cpuid" (ralf brown package)
  ;below @@get_id_flag works ONLY on 486 and above (so 386 may NOT execute it)
  call @@get_id_flag     ;\try to set bit 21 of eflags (identification flag)
  jnz  short @@yep_id    ;/continue with cpuid if available
  IF 0     ;not sure, maybe better avoid below I/O under windows
    cli                    ;\
    mov  al,0c3h           ;
    out  22h,al            ;
    in   al,23h            ;
    or   al,10h            ; enable cpuid function on stupid cyrix processors
    out  23h,al            ;
    mov  al,0e8h           ;
    out  22h,al            ;
    in   al,23h            ;
    or   al,80h            ;
    out  23h,al            ;
    sti                    ;/
  ENDIF
  call @@get_id_flag     ;\try to set bit 21 of eflags (identification flag)
  jz   short @@no_id     ;/continue with cpuid if available
 @@yep_id:
  mov  eax,1     ;\out: eax,ebx,ecx,edx  ;\
  cpuid$         ;/                      ;
  and  ah,0fh    ;ah.lo=family (3=386, 4=486, 5=P$$$, 6=P$$$pro)
  mov  byte ptr [detected_cpu],ah        ;/
  mov  byte ptr [cpuid_exists],1
  mov  dword ptr [cpuid_flags],edx   ;flags (mmx, etc.)
 ;- - -
 @@no_id:
  ret
 ;--- --- ---
 @@get_id_flag:  ;out: zf
  pushfd                 ;\
  pop  eax               ;
  or   eax,1 shl 21      ;
  push eax               ; try to set bit 21 of eflags (identification flag)
  popfd                  ; out: zf
  pushfd                 ;
  pop  eax               ;
  test eax,1 shl 21      ;
  ret                    ;/
 ;---
 .data
  align 4
  cpuid_flags  dd 00000000h
   ;cpuid_flags.0  floating-point-unit on-chip (if zero, there still MIGHT be an external fpu)
   ;cpuid_flags.4  supports RDTSC opcode
   ;cpuid_flags.8  supports CMPXCHG8B opcode
   ;cpuid_flags.15 supports CMOV opcode
   ;cpuid_flags.23 supports MMX opcodes
   ;cpuid_flags.24 supports FXSAVE/FXRSTOR opcodes
   ;cpuid_flags.25 supports SSE opcodes
  cpuid_exists db 0
  detected_cpu db 0
  align 4
 .code
 ;--- --- ---
 timelog_start macro ttt
  local @@no_rdtsc_supported
   test byte ptr [cpuid_flags],1 shl 4           ;\XXX just doing this test can take up 60000 clks per second !!?!!
   jz   short @@no_rdtsc_supported               ;/    (though only in stereo mode, not so in mono mode?) (maybe caused by some alignment issue)
   dw   0310fh  ;opcode "rdtsc"  ;-read timestamp counter (to edx:eax)
   sub  dword ptr [ttt+0],eax    ;\exclude origin from time
   sbb  dword ptr [ttt+4],edx    ;/
  @@no_rdtsc_supported:
 endm
 ;--- --- ---
 timelog_end macro ttt
  local @@no_rdtsc_supported
   test byte ptr [cpuid_flags],1 shl 4           ;\XXX just doing this test can take up 60000 clks per second !!?!!
   jz   short @@no_rdtsc_supported               ;/    (though only in stereo mode, not so in mono mode?) (maybe caused by some alignment issue)
   dw   0310fh  ;opcode "rdtsc"  ;-read timestamp counter (to edx:eax)
   add  dword ptr [ttt+0],eax    ;\raise time
   adc  dword ptr [ttt+4],edx    ;/(with origin excluded above)
  @@no_rdtsc_supported:
 endm
 ;--- --- ---
 timelog_display_results macro
  call GetTickCount                             ;\get end time
  add  dword ptr [millisecond_count],eax        ;/
  mov  edx,offset txt_decode_timing1            ;\
  call wrstr_edx                                ;/
  mov  eax,dword ptr [mp3_total_output_size]    ;\
  mov  edx,1000 ;\mul 1000                      ;
  mul  edx      ;/                              ;
  div  dword ptr [mp3_output_sample_rate]       ;
  xor  edx,edx                                  ; duration in milliseconds
  div  dword ptr [mp3_output_num_channels]      ;
  xor  edx,edx                                  ;
  div  dword ptr [mp3_bytes_per_sample]         ;
  mov  dword ptr [mp3_output_milliseconds],eax  ;
  call wr_decimal_eax_with_thousands_seperator  ;/
  mov  edx,offset txt_decode_timing2            ;\
  call wrstr_edx                                ;/
  mov  eax,dword ptr [millisecond_count]        ;\decoding time in milliseconds
  call wr_decimal_eax_with_thousands_seperator  ;/
  mov  edx,offset txt_decode_timing3            ;\
  call wrstr_edx                                ;/
 ;- - -
  mov  edx,offset txt_clks_per_second   ;\
  call wrstr_edx                        ;/
  mov  esi,offset rdtsc_list_start
 @@timelog_lop:
  call wrspc
  lea  edx,[esi+8]
  call wrstr_edx
  ;mov  eax,dword ptr [esi+4]   ;\
  ;call wrhexeax                ;
  ;mov  eax,dword ptr [esi+0]   ;
  ;call wrhexeax                ;/
  call wrspc
  mov  eax,dword ptr [esi+0]
  mov  ebx,dword ptr [esi+4]
  mov  edx,1000  ;\
  imul ebx,edx   ; mul 1000
  mul  edx       ;
  add  edx,ebx   ;/
  cmp  edx,dword ptr [mp3_output_milliseconds]
  jae  short @@timelog_oops  ;avoid div overkill
 ;div  dword ptr [mp3_num_frames_decoded]       ;<-- cycles/frame
  div  dword ptr [mp3_output_milliseconds]      ;<-- cycles/second
  call wr_decimal_eax_with_thousands_seperator
 @@timelog_oops:
  call wrcrlf
  add  esi,8+16
  cmp  esi,offset rdtsc_list_end
  jne  short @@timelog_lop
 endm
 ;--- --- ---
 .data
  align 4
  mp3_output_milliseconds dd 0  ;song duration
  millisecond_count dd 0        ;decoding time
  xmit_curr_process dd 0
  xmit_curr_thread  dd 0
  xmit_process_prio dd 0
  xmit_thread_prio  dd 0
  ;---
  align data_align
  rdtsc_list_start:                                             ;\
  def_timelog macro name                                        ;
    dd 0,0                                                      ;
    db name                                                     ;
  endm                                                          ;
  rdtsc_read_header      : def_timelog <'read header    ',0>    ;
  rdtsc_read_header_extra: def_timelog <'read extra     ',0>    ;
  rdtsc_read_granule     : def_timelog <'read granule   ',0>    ;
  rdtsc_append_main      : def_timelog <'append main    ',0>    ;
  rdtsc_read_scalefac    : def_timelog <'read scalefac  ',0>    ;
  rdtsc_xlat_scalefac    : def_timelog <'xlat scalefac  ',0>    ;
  rdtsc_read_huffman     : def_timelog <'read huffman   ',0>    ;
 ;rdtsc_huff_pairs       : def_timelog <' huff pairs    ',0>    ;
 ;rdtsc_huff_quads       : def_timelog <' huff quads    ',0>    ;
 ;rdtsc_huff_pad         : def_timelog <' huff pad      ',0>    ;
  rdtsc_ms_stereo        : def_timelog <'ms stereo      ',0>    ;
  rdtsc_i_stereo         : def_timelog <'i stereo       ',0>    ;
  rdtsc_reorder          : def_timelog <'reorder        ',0>    ;
  rdtsc_antialias        : def_timelog <'antialias      ',0>    ;
  rdtsc_imdct            : def_timelog <'imdct          ',0>    ;
  rdtsc_imdct36          : def_timelog <' imdct36       ',0>    ;
  rdtsc_imdct12          : def_timelog <' imdct12       ',0>    ;
  rdtsc_imdct0           : def_timelog <' imdct0        ',0>    ;
  rdtsc_synth_dct        : def_timelog <'synth/dct      ',0>    ;
  rdtsc_dct32            : def_timelog <' synth.dct32   ',0>    ;
  rdtsc_synth            : def_timelog <' synth.output  ',0>    ;
  rdtsc_total            : def_timelog <'total          ',0>    ;
  rdtsc_list_end:                                               ;/
  ;---
 .const
  txt_decode_timing1  db 'audio duration ',0
  txt_decode_timing2  db ' milliseconds, decoded in ',0
  txt_decode_timing3  db ' milliseconds',0dh,0ah,0
  txt_clks_per_second db ' clock cycles per second:',0dh,0ah,0
 .code
 ;------------------
 extrn GetCurrentProcess :proc
 extrn GetCurrentThread  :proc
 extrn GetPriorityClass  :proc
 extrn GetThreadPriority :proc
 extrn SetPriorityClass  :proc
 extrn SetThreadPriority :proc
 ;------------------
 NORMAL_PRIORITY_CLASS                equ 20h
 IDLE_PRIORITY_CLASS                  equ 40h
 HIGH_PRIORITY_CLASS                  equ 80h
 REALTIME_PRIORITY_CLASS              equ 100h
 THREAD_BASE_PRIORITY_MIN             equ -2
 THREAD_BASE_PRIORITY_MAX             equ 2
 THREAD_BASE_PRIORITY_LOWRT           equ 15
 THREAD_BASE_PRIORITY_IDLE            equ -15
 THREAD_PRIORITY_LOWEST               equ THREAD_BASE_PRIORITY_MIN
 THREAD_PRIORITY_BELOW_NORMAL         equ THREAD_PRIORITY_LOWEST + 1
 THREAD_PRIORITY_NORMAL               equ 0
 THREAD_PRIORITY_HIGHEST              equ THREAD_BASE_PRIORITY_MAX
 THREAD_PRIORITY_ABOVE_NORMAL         equ THREAD_PRIORITY_HIGHEST - 1
 THREAD_PRIORITY_ERROR_RETURN         equ MAXLONG
 THREAD_PRIORITY_TIME_CRITICAL        equ THREAD_BASE_PRIORITY_LOWRT
 THREAD_PRIORITY_IDLE                 equ THREAD_BASE_PRIORITY_IDLE
 ;------------------
 xmit_get_priority_defaults:
  pusha
  call GetCurrentProcess                 ;\
  mov  dword ptr [xmit_curr_process],eax ;/
  call GetCurrentThread                  ;\
  mov  dword ptr [xmit_curr_thread],eax  ;/
  push dword ptr [xmit_curr_process]     ;\
  call GetPriorityClass                  ;
  mov  dword ptr [xmit_process_prio],eax ;/
  push dword ptr [xmit_curr_thread]      ;\
  call GetThreadPriority                 ;
  mov  dword ptr [xmit_thread_prio],eax  ;/
  popa
  ret
 ;------------------
 align code_align
 xmit_resume_normal_priority:
  ;XXX doing this inside of the AudioCallback doesn't specifically restore
  ;    the callback thread's defaults (but it seems to work somehow)
  ;    (and the /test benchmarks don't occur in AudioCallback anyways)
  pusha
  push dword ptr [xmit_process_prio]     ;\
  push dword ptr [xmit_curr_process]     ;
  call SetPriorityClass                  ;/
  push dword ptr [xmit_thread_prio]      ;\
  push dword ptr [xmit_curr_thread]      ;
  call SetThreadPriority                 ;/
 ;cmp  byte ptr [windows_nt_flag],0      ;\re-enable interrupts (if allowed)
 ;jnz  short @@skip_sti                  ; win98: works, win7: crashes
 ;sti                                    ;
 @@skip_sti:                             ;/
 ; push 0           ;\more multi tasking friendly
 ;extrn Sleep :proc ;
 ; call Sleep       ;/
  popa
  ret
 ;------------------
 align code_align
 xmit_force_highest_priority:     ;for getting more accurate "rdtsc" results
  ;this forces "highest" process/thread priority
  ;it does freeze any other processes (eg. another emulator will freeze)
  ;it does freeze certain mouse actions (eg. moving a window via mouse dragging)
  ;it does NOT freeze the actual mouse arrow (the arrow can be still around)
  ;it does NOT prevent ctrl+alt+del key combo (still asks for close program)
  ;---
  pusha
  push REALTIME_PRIORITY_CLASS           ;\
  push dword ptr [xmit_curr_process]     ;
  call SetPriorityClass                  ;
  cmp  eax,TRUE                          ;
  jne  short @@error                     ;/
  push THREAD_PRIORITY_TIME_CRITICAL     ;\
  push dword ptr [xmit_curr_thread]      ;
  call SetThreadPriority                 ;
  cmp  eax,TRUE                          ;
  jne  short @@error                     ;/
 ;cmp  byte ptr [windows_nt_flag],0      ;\try to disable interrupts (if allowed)
 ;jnz  short @@skip_cli                  ; win98: works, win7: crashes
 ;cli                                    ;
 @@skip_cli:                             ;/
  popa
  ret
 ;---
 @@error: jmp fatalunexpected
ENDIF
;------------------
;:----------------- Include mp3 decoder
;------------------
include mp3.asm
;------------------
;:----------------- Text output
;------------------
.const
 txt_hello db 'nocash mp3 decoder v1.4, 2024 martin korth, press ctrl+c to quit, BDS now',0dh,0ah,0
.data
 wrchr_buf      db 0
;log_xloc       dd 0
align 4
.code
;------------------
wrchr:
 pusha
 IF 0   ;compresses worse (but a little more stable when simultaneously called inside callback and main program, which could otherwise output twice the same char)
  lea  eax,[esp+7*4]   ;-get ptr to char (within 8 words from  pusha)
  push 0                    ;set to 0 in most cases              ;\
  push offset diskresult    ;pointer to number of read bytes     ;
  push 1                         ;length                         ;
  push eax                       ;source                         ;
  push dword ptr [std_out]       ;handle                         ;
  call WriteFile                                                 ;/
 ELSE
  mov  byte ptr [wrchr_buf],al
  push 0                    ;set to 0 in most cases              ;\
  push offset diskresult    ;pointer to number of read bytes     ;
  push 1                         ;length                         ;
  push offset wrchr_buf          ;source                         ;
  push dword ptr [std_out]       ;handle                         ;
  call WriteFile                                                 ;/
 ENDIF
;inc  dword ptr [log_xloc]
;cmp  byte ptr [wrchr_buf],20h
;jae  short @@not_crlf
;mov  dword ptr [log_xloc],0
@@not_crlf:
 popa
 ret
;------------------
wrstr_edx:
 push eax
@@lop:
 mov  al,byte ptr [edx]
 inc  edx
 cmp  al,00h
 jz   short @@done
 call wrchr
 jmp  short @@lop
@@done:
 pop  eax
 ret
;------------------
IF log_init+log_fatal+log_frames+log_granules+log_huffcodes+log_scalefac+log_timing+log_file_info
;------------------
wrcrlf:
 push eax
 mov  al,0dh
 call wrchr
 mov  al,0ah
 call wrchr
 pop  eax
 ret
;------------------
wrspc:
 push eax
 mov  al,20h
 call wrchr
 pop  eax
 ret
;------------------
wrcomma:
 push eax
 mov  al,','
 call wrchr
 pop  eax
 ret
;------------------
wr_decimal_eax_with_thousands_seperator:  ;in: eax
 push ecx
 mov  cx,0002h ;ch=leadflag(none), cl=thousands(yes, starting before 2nd digit)
 jmp  short wr_decimal_eax_inj
;------------------
wr_decimal_eax:
 push ecx
 xor  ecx,ecx ;ch=leadflag(none), cl=thousands(none)
wr_decimal_eax_inj: ;in: eax,cx (and, stack ecx pushed)
 push eax
 push ebx
 push edx
 mov  ebx,1000000000  ;nine zeroes (32bit max 4.294.967.296)
@@dezlop:
 dec  cl                        ;\
 jnz  short @@no_thousands      ;
 mov  cl,3                      ;
 cmp  ch,0                      ;
 jz   short @@no_thousands      ;
 call wrcomma                   ;
@@no_thousands:                 ;/
 xor  edx,edx
 div  ebx
 cmp  ebx,1
 je   short @@force_last_zero
 or   ch,al
 jz   short @@skip_lead_zero
@@force_last_zero:
 add  al,30h
 call wrchr
@@skip_lead_zero:
 push edx
 mov  eax,ebx
 mov  ebx,10
 xor  edx,edx
 div  ebx
 cmp  eax,0
 mov  ebx,eax
 pop  eax
 jnz  short @@dezlop
 pop  edx
 pop  ebx
 pop  eax
 pop  ecx
 ret
;------------------
wrdigital:
 push eax
 and  al,0fh
 cmp  al,09h
 jbe  short @@this
 add  al,07h
@@this:
 add  al,30h
 call wrchr
 pop  eax
 ret
;------------------
wrhexal:
 ror  al,4
 call wrdigital
 ror  al,4
 jmp  wrdigital
;------------------
wrhexax:
 ror  ax,8
 call wrhexal
 ror  ax,8
 jmp  wrhexal
;------------------
wrhexeax:
 ror  eax,16
 call wrhexax
 ror  eax,16
 jmp  wrhexax
;------------------
ENDIF ;log_init+etc.
;------------------
;:----------------- load source file
;------------------
BUFFER_COUNT equ 8
;------------------
.data
 mp3_src_fname  dd 0
 mp3_dst_fname  dd 0
 mp3_pcm_fname  dd 0
;---
.const
 IF log_file_info
  txt_file      db 'file: ',0
  txt_file_size db 'file size: ',0
  txt_id3_size  db ', id3 size: ',0
  txt_tag_size  db ', tag size: ',0
  txt_input     db 'input: ',0
  txt_output    db 'output: ',0
  txt_hz        db ' hz, ',0
  txt_channels  db ' channels, ',0
  txt_bit       db ' bit',0
  txt_kbit_s    db ' kbit/s',0
 ENDIF
 txt_not_found  db 'cannot open source file',0dh,0ah,0
 ;- - -
 txt_help:                                              ;\
  db 'usage: '                                          ;
  db 'mp3play input.mp3'                                ;
  IF with_output_to_wav_file                            ;
    db ' [output.wav]'                                  ;
  ENDIF                                                 ;
  IF with_verify_to_pcm_file                            ;
    db ' [verify.pcm]'                                  ;
  ENDIF                                                 ;
  IF with_raw_testing                                   ;
    db ' [/test]'                                       ;
  ENDIF                                                 ;
  IF 1                                                  ;
    db ' [/mono]'                                       ;
  ENDIF                                                 ;
  IF with_8bit_output                                   ;
    db ' [/8bit]'                                       ;
  ENDIF                                                 ;
  IF with_fast_option                                   ;
    db ' [/fast]'                                       ;
  ENDIF                                                 ;
  IF with_rate_shift                                    ;
    db ' [/half|/quarter]'                              ;
  ENDIF                                                 ;
  db 0dh,0ah,0                                          ;/
;---
.data?
 hFile          dd ?  ;file handle
 hMap           dd ?  ;filemapping handle
 stream_start   dd ?
 stream_pos     dd ?
 bytes_left     dd ?
 align data_align
 sample_buffer  db BUFFER_COUNT*MP3_MAX_OUTPUT_SIZE dup (?)
 diskresult     dd ?
 std_out        dd ?
 cmdline_max    equ 1024
 cmdline_buf    db cmdline_max dup (?)
align 4
.code
;------------------
get_commandline:
 call GetCommandLineA           ;\
 mov  esi,eax                   ;
 mov  edi,offset cmdline_buf    ; get commandline, format:"quoted progname" params
 mov  ecx,cmdline_max           ;
@@get_cmdline_lop:              ;
 lodsb                          ;
 cmp  al,00h                    ;
 stosb                          ;
 loopnz short @@get_cmdline_lop ;
 mov  byte ptr [edi-1],00h      ;/
 ;- - -
 mov  esi,offset cmdline_buf
 mov  edi,offset cmdline_buf
 call @@get_item        ;-get/skip name of the executable itself
@@get_items_lop:                        ;\
 call @@get_item                        ;
 mov  al,byte ptr [ebx]                 ;
 cmp  al,00h                            ;
 jz         @@done                      ;
 cmp  al,'/'                            ;
 jz   short @@switch                    ;
 cmp  al,'-'                            ;
 jz   short @@switch                    ;
 IF with_output_to_wav_file          ;\ ;
   mov  eax,dword ptr [edi-5]     ;\ ;  ;
   or   eax,20202000h             ;  ;  ;
   cmp  eax,'vaw.'   ;".wav"      ;  ;  ;
   jne  short @@not_wav_name      ;/ ;  ;
   mov  dword ptr [mp3_dst_fname],ebx;  ;
   jmp  short @@get_items_lop        ;  ;
  @@not_wav_name:                    ;  ;
 ENDIF                               ;/ ;
 IF with_verify_to_pcm_file          ;\ ;
   mov  eax,dword ptr [edi-5]     ;\ ;  ;
   or   eax,20202000h             ;  ;  ;
   cmp  eax,'mcp.'   ;".pcm"      ;  ;  ;
   jne  short @@not_pcm_name      ;/ ;  ;
   mov  dword ptr [mp3_pcm_fname],ebx;  ;
   jmp  short @@get_items_lop        ;  ;
  @@not_pcm_name:                    ;  ;
 ENDIF                               ;/ ;
                                        ;
 mov  dword ptr [mp3_src_fname],ebx     ;
 jmp  short @@get_items_lop             ;/

;---
@@switch:
 cmp  dword ptr [ebx+1],'onom'  ;"mono" ;\
 jne  short @@not_switch_mono           ;
 mov  byte ptr [option_mono],1          ; force mono
 jmp  short @@get_items_lop             ;
@@not_switch_mono:                      ;/
 IF with_fast_option
   cmp  dword ptr [ebx+1],'tsaf'  ;"fast" ;\
   jne  short @@not_fast_option           ;
   mov  byte ptr [option_fast],1          ; fast option (lower accuracy)
   jmp  short @@get_items_lop             ;
  @@not_fast_option:                      ;/
 ENDIF
 IF with_8bit_output
   cmp  dword ptr [ebx+1],'tib8'  ;"8bit" ;\
   jne  short @@not_switch_8bit           ;
   mov  byte ptr [option_8bit],1          ; 8bit output (for old hardware)
   jmp        @@get_items_lop             ;
  @@not_switch_8bit:                      ;/
 ENDIF
 IF with_rate_shift
   cmp  dword ptr [ebx+1],'flah'  ;"half" ;\
   jne  short @@not_switch_half           ; half sample rate output (speedup)
   mov  byte ptr [option_rate_shift],1    ; (faster, and still quite good)
   jmp        @@get_items_lop             ;
  @@not_switch_half:                      ;/
   cmp  dword ptr [ebx+1],'rauq'  ;"quar" ;\
   jne  short @@not_switch_quarter        ; quarter sample rate output (speedup)
   mov  byte ptr [option_rate_shift],2    ; (not much faster, and poor quality)
   jmp        @@get_items_lop             ;
  @@not_switch_quarter:                   ;/
 ENDIF
 IF with_raw_testing
   cmp  dword ptr [ebx+1],'tset'  ;"test" ;\
   jne  short @@not_switch_test           ;
   mov  byte ptr [option_test],1          ; test timings/benchmarks
   jmp        @@get_items_lop             ;
  @@not_switch_test:                      ;/
 ENDIF
 jmp  short @@help                      ;-oops, other
;---
@@done:
 cmp  dword ptr [mp3_src_fname],0       ;\check if filename specified
 jz   short @@help                      ;/
 IF log_file_info
   mov  edx,offset txt_file               ;\
   call wrstr_edx                         ;
   mov  edx,dword ptr [mp3_src_fname]     ; show filename
   call wrstr_edx                         ;
   call wrcrlf                            ;/
 ENDIF
 clc    ;okay
 ret
;---
@@help:
 mov  edx,offset txt_help
 call wrstr_edx
 stc    ;fail/exit
 ret
;--- --- ---
@@get_item:     ;out: esi=src.next, ebx=item.start, edi=item.end
@@skip_spc_lop:                         ;\
 lodsb                                  ;
 dec  al        ;01h..20h --> 00h..1Fh  ; skip space or tab chars
 cmp  al,20h-1  ;00h..1Fh               ;
 jbe  short @@skip_spc_lop              ;
 dec  esi   ;stepback onto non-space    ;/
 ;- - -
 mov  ebx,edi           ;-address of current item
 mov  ah,0              ;-flag initially not quoted
@@char_lop:             ;\
 lodsb                  ;
 cmp  al,'"'            ;
 jne  short @@no_quote  ;
 xor  ah,1  ;toggle     ;
 jmp  short @@char_lop  ;
@@no_quote:             ;
 stosb                  ;
 cmp  al,00h            ;
 jz   short @@src_end   ;
 cmp  al,20h            ;
 ja   short @@char_lop  ;/
 cmp  ah,0              ;\ignore spaces if inside "quoted area" 11/00
 jnz  short @@char_lop  ;/
 mov  byte ptr [edi-1],0;-eol (replace space by 00h)
 ret
;---
@@src_end:
 dec  esi               ;-back onto ending zero!
 ret
;---
.data
;input_file_name db 'd:\zsp.mp3',0
;input_file_name db 'D:\AnnaMp3\Newer\Tango Club & the Sunshine Babies - DemoTape - 05 Hexe.mp3',0
;input_file_name db 'D:\AnnaMp3\Newer\Altan Urag - 1-8.mp3',0
;input_file_name db 'D:\AnnaMp3\Newer\Infant Sanchos - šbersprungsger„usche.mp3',0
;input_file_name db 'D:\AnnaMp3\Newer\Infant Sanchos - Der Kaiser.mp3',0   ;<-- did crash on PNG in ID3 (fixed by mp3_exclude_id3_and_tag)  ;<-- is 48kHz
;input_file_name db 'D:\AnnaMp3\Newer\Der Moderne Man - Blaue Matrosen.mp3',0
;input_file_name db 'D:\AnnaMp3\Newer\Nova Twins - Cleopatra.mp3',0      ;48kHz
;input_file_name db 'D:\psx-homebrew\mp3-1kHz_44100Hz_16bit_05sec.mp3',0   ;MONO
;input_file_name db 'D:\psx-homebrew\mp3-100Hz_44100Hz_16bit_05sec.mp3',0  ;MONO
;input_file_name db 'D:\psx-homebrew\mp3-250Hz_44100Hz_16bit_05sec.mp3',0  ;MONO
;align 4
.code
;------------------
open_and_mmap_the_file:
 push NULL                              ;\
 push 0     ;file attribute             ;
 push OPEN_EXISTING                     ;
 push NULL  ;no security attributes     ; open file
 push FILE_SHARE_READ                   ;
 push GENERIC_READ                      ;
 push dword ptr [mp3_src_fname]         ;
 call CreateFileA                       ;
 mov  dword ptr [hFile],eax             ;
 cmp  eax,INVALID_HANDLE_VALUE          ;
 je   short @@not_found                 ;/
 push NULL                              ;\
 push dword ptr [hFile]                 ; get filesize
 call GetFileSize                       ;
 mov  dword ptr [mp3_file_size],eax     ;
 mov  dword ptr [bytes_left],eax        ;/
 push NULL                              ;\
 push 0                                 ;
 push 0                                 ;
 push PAGE_READONLY                     ; map file
 push NULL                              ;
 push dword ptr [hFile]                 ;
 call CreateFileMappingA                ;
 mov  dword ptr [hMap],eax              ;/
 push 0                                 ;\
 push 0                                 ;
 push 0                                 ;
 push FILE_MAP_READ                     ; get ptr to memory mapped file
 push dword ptr [hMap]                  ;
 call MapViewOfFile                     ;
 mov  dword ptr [stream_start],eax      ;
 mov  dword ptr [stream_pos],eax        ;/
        IF log_timing   ;pre-cache memory mapped file (for better rdtsc results, undisturbed by on-the-fly file loading)
          mov  esi,dword ptr [stream_start]
          mov  ecx,dword ptr [bytes_left]
         @@lll:
          lodsb
          loop short @@lll
        ENDIF
 clc    ;okay
 ret
;---
@@not_found:
 mov  edx,offset txt_not_found
 call wrstr_edx
 stc    ;bad
 ret
;------------------
;:----------------- Output none, plain test
;------------------
IF with_raw_testing
;------------------
align code_align
mp3_plain_test_without_output:
@@lop:                                          ;-loop ...
 pusha                                          ;\
 mov  esi,dword ptr [stream_pos]          ;src  ;
 mov  ecx,dword ptr [bytes_left]          ;siz  ;
 mov  edi,offset sample_buffer            ;dst  ; decode frame
 xor  ebp,ebp                             ;vals ;
 call mp3_decode_frame                          ;
 popa                                           ;
 jc   short @@exit                              ;/
 mov  eax,dword ptr [mp3_src_frame_size]        ;\
 cmp  eax,0                                     ;
 jz   short @@exit                              ; src stream
 add  dword ptr [stream_pos],eax                ;
 sub  dword ptr [bytes_left],eax                ;/
 jmp  short @@lop                               ;-next
@@exit:
 ret
;------------------
ENDIF ;with_raw_testing
;------------------
;:----------------- Output to wav file
;------------------
IF with_output_to_wav_file
;------------------
.data
mp3_wav_header:  ;(2Ch bytes)
 db 'RIFF'               ;00h   0    ID
 dd 0+24h  ;VAR siz+24h  ;04h   4    chunksize
 db 'WAVE'               ;08h   8    ID
 db 'fmt '               ;0Ch  12    ID
 dd 16                   ;10h  16    chunksize
 dw 1                    ;14h  20    wFormatTag = 1 (PCM)
 dw 2      ;VAR chn      ;16h  22    nChannels = 2
 dd 0*1    ;VAR rate     ;18h  24    nSamplesPerSec
 dd 0*4    ;VAR rate*4   ;1Ch  28    nAvgBytesPerSec
 dw 4      ;VAR          ;20h  32    nBlockAlign    (1..4)
 dw 16     ;VAR          ;22h  34    wBitsPerSample (8 or 16)
 db 'data'               ;24h  36    ID
 dd 0+0    ;VAR siz+0    ;28h  40    chunksize
;---
 align 4
.code
;------------------
.data?
 mp3_wav_handle dd ?
.code
;------------------
align code_align
mp3_cast_to_wav_file:
 call mp3_create_wav_file                       ;-create wav file
@@lop:                                          ;-loop ...
 pusha                                          ;\
 mov  esi,dword ptr [stream_pos]          ;src  ;
 mov  ecx,dword ptr [bytes_left]          ;siz  ;
 mov  edi,offset sample_buffer            ;dst  ; decode frame
 xor  ebp,ebp                             ;vals ;
 call mp3_decode_frame                          ;
 popa                                           ;
 jc   short @@exit                              ;/
 mov  eax,dword ptr [mp3_src_frame_size]        ;\
 cmp  eax,0                                     ;
 jz   short @@exit                              ; src stream
 add  dword ptr [stream_pos],eax                ;
 sub  dword ptr [bytes_left],eax                ;/
 IF wav_file_block_marker                       ;\
   mov  dword ptr [sample_buffer+0],80007fffh   ; block start marker
   mov  dword ptr [sample_buffer+4],80007fffh   ; (for waveform viewers)
 ENDIF                                          ;/
 push 0 ;set to 0 in most cases                 ;\
 push offset diskresult          ;ptr to result ;
 push dword ptr [mp3_samples_output_size]  ;len ; write sample block
 push offset sample_buffer                 ;src ;
 push dword ptr [mp3_wav_handle]                ;
 call WriteFile                                 ;/
 mov  eax,dword ptr [mp3_samples_output_size]   ;\raise size in
 add  dword ptr [mp3_wav_header+04h],eax        ; .wav file header
 add  dword ptr [mp3_wav_header+28h],eax        ;/
 jmp  short @@lop                               ;-next
@@exit:
 call mp3_close_wav_file                        ;-close wav file
 ret
;------------------
mp3_create_wav_file:
 mov  eax,dword ptr [mp3_output_sample_rate]    ;\
 mov  ecx,dword ptr [mp3_output_num_channels]   ;
 mov  edx,dword ptr [mp3_bytes_per_sample]      ; apply sample rate to header
 mov  word ptr [mp3_wav_header+16h],cx          ; and num channels, bits/sample
 mov  dword ptr [mp3_wav_header+18h],eax        ;
 imul ecx,edx  ;NumChannels*BytesPerSample      ;
 imul eax,ecx  ;mul SamplesPerSec               ;
 shl  edx,3    ;bits/sample = bytes*8           ;
 mov  dword ptr [mp3_wav_header+1ch],eax        ;
 mov  word ptr [mp3_wav_header+20h],cx          ;
 mov  word ptr [mp3_wav_header+22h],dx          ;/
 push 0       ;for Win95 always 0       ;\
 push FILE_ATTRIBUTE_NORMAL             ;
 push CREATE_ALWAYS ;overwrite existing ;
 push 0        ;no Security-attributes  ; create
 push 0        ;disable Share-Mode      ;
 push GENERIC_READ + GENERIC_WRITE      ;
 push dword ptr [mp3_dst_fname]         ;
 call CreateFileA                       ;
 mov  dword ptr [mp3_wav_handle],eax    ;/
 call mp3_write_wav_header              ;-write header
 ret
;------------------
mp3_write_wav_header:
 push 0 ;set to 0 in most cases         ;\
 push offset diskresult  ;ptr to result ;
 push 2ch     ;wav hdrsiz          ;len ; write header
 push offset mp3_wav_header        ;src ;
 push dword ptr [mp3_wav_handle]        ;
 call WriteFile                         ;/
 ret
;------------------
mp3_close_wav_file:
 push FILE_BEGIN ;-method (from begin of file)          ;\
 push 0          ;-ptr to fpos upper 32bit (0=none)     ;
 push 0          ;-fpos lower 32bit                     ; seek 0
 push dword ptr [mp3_wav_handle]                        ;
 call SetFilePointer                                    ;/
 call mp3_write_wav_header                              ;-rewrite header
 push dword ptr [mp3_wav_handle]                        ;\close file
 call CloseHandle                                       ;/
 ret
;------------------
ENDIF ;with_output_to_wav_file
;------------------
;:----------------- Verify to pcm file
;------------------
IF with_verify_to_pcm_file
;------------------
;this is for comparing the output against .pcm files in lieff's minimp3 package
;------------------
.data?
 mp3_pcm_handle  dd ?
.code
;------------------
mp3_verify_pcm_file:
 .data?
  @@max_diff      dd ?
  @@avg_diff      dd ?,?
  @@pcm_filepos   dd ?
  @@mono_convert  dd ?
  @@pcm_steps     dw ?,?
  @@worst_pcm_filepos dd ?
  @@worst_mp3_filepos dd ?
 .code
 ;---
 .const
  @@txt_verify1         db 'verify max difference = ',0
  @@txt_verify1_at_mp3  db ' at mp3:',0
  @@txt_verify2         db ', average difference = ',0
 .code
 ;- - -
 call mp3_open_pcm_file                         ;-open pcm file
 mov  dword ptr [@@max_diff],0                  ;\
 mov  dword ptr [@@avg_diff+0],0                ;
 mov  dword ptr [@@avg_diff+4],0                ;
 mov  dword ptr [@@pcm_filepos],0               ;/
@@lop:                                          ;-loop ...
 pusha                                          ;\
 mov  esi,dword ptr [stream_pos]          ;src  ;
 mov  ecx,dword ptr [bytes_left]          ;siz  ;
 mov  edi,offset sample_buffer            ;dst  ; decode frame
 xor  ebp,ebp                             ;vals ;
 call mp3_decode_frame                          ;
 popa                                           ;
 jc         @@exit                              ;/
 mov  eax,dword ptr [mp3_src_frame_size]        ;\
 cmp  eax,0                                     ; src stream
 jz         @@exit                              ;/
 xor  eax,eax                                   ;\
 cmp  dword ptr [mp3_output_num_channels],2     ; determine if mono conversion
 jb   short @@this_mono_convert                 ; only if file is STEREO,
 moz  eax,byte ptr [option_mono]                ; and only if MONO option
@@this_mono_convert:                            ;
 mov  dword ptr [@@mono_convert],eax            ;/
 mov  cl,byte ptr [option_rate_shift]           ;\
 mov  eax,2    ;1x16bit                         ;
 shl  eax,cl                                    ; determine stepping for
 mov  word ptr [@@pcm_steps+0],ax               ; rate_shift versus stereo
 mov  word ptr [@@pcm_steps+2],ax               ;
 cmp  dword ptr [mp3_output_num_channels],2     ;
 jb   short @@these_steps                       ;
 mov  word ptr [@@pcm_steps+0],2   ;16bit       ;
 lea  eax,[eax*2-2]                             ;
 mov  word ptr [@@pcm_steps+2],ax  ;Nx16bit     ;
@@these_steps:                                  ;/
 ;- - -
 mov  eax,dword ptr [mp3_samples_output_size]   ;\
 mov  cl,byte ptr [option_rate_shift]           ;
 add  cl,byte ptr [option_8bit]                 ; len
 add  cl,byte ptr [@@mono_convert]              ;
 shl  eax,cl                                    ;/
 push 0 ;set to 0 in most cases                 ;\
 push offset diskresult          ;ptr to result ;
 push eax                                  ;len ; read sample block
 push offset sample_buffer+MP3_MAX_OUTPUT_SIZE  ;
 push dword ptr [mp3_pcm_handle]                ;
 call ReadFile                                  ;/
 ;- - -
 mov  ecx,dword ptr [mp3_samples_output_size]
 shr  ecx,1     ;for 16bit (XXX other for 8bit)
 jz         @@compare_done  ;for incomplete/bad frames (eg. l3-sin1k0db.bit)
 mov  esi,offset sample_buffer                      ;-decoded .mp3
 mov  edi,offset sample_buffer+MP3_MAX_OUTPUT_SIZE  ;-loaded .pcm
@@compare_lop:
 movsx edx,word ptr [edi+0]                     ;\
 cmp  dword ptr [@@mono_convert],0 ;\           ;
 jz   short @@no_mono_convert      ;/           ; from .pcm
 movsx eax,word ptr [edi+2]        ;\           ;     ;XXX /mono goes wrong...
 add  edx,eax                      ; merge mono ;     ;    maybe bugs on i_stereo, or left/right encoding?
 sar  edx,1                        ;/           ;/    ;    ms_szereo should hopefully work
@@no_mono_convert:                              ;     ;XXX also recurse @@pcm_steps vs option_option
 cmp  byte ptr [option_8bit],0                  ;\
 jnz  short @@compare_8bit                      ;
 movsx eax,word ptr [esi+0]     ;\get 16bit     ; from decoded .mp3
 add  esi,2                     ;/signed        ;
 jmp  short @@compare_this                      ;
@@compare_8bit:                                 ;
 movzx eax,byte ptr [esi+0]     ;\get 8bit      ;
 inc  esi                       ;/unsigned      ;
 add  edx,8000h ;make unsigned  ;\              ;
 sar  edx,8     ;div 100h       ; convert .pcm  ;
 adc  dl,0      ;round up       ;/              ;
 sbb  dl,0      ;undo on unsigned overflow      ;
@@compare_this:                                 ;/
 sub  eax,edx                                   ;\
 jns  short @@compare_abs                       ; calc difference
 neg  eax                                       ;
@@compare_abs:                                  ;/
 add  dword ptr [@@avg_diff+0],eax              ;\raise average diff
 adc  dword ptr [@@avg_diff+4],0                ;/
 cmp  eax,dword ptr [@@max_diff]                ;\check if max diff
 jb   short @@not_max                           ;/
 mov  dword ptr [@@max_diff],eax                ;-apply max diff
 mov  edx,dword ptr [@@pcm_filepos]             ;\apply max diff pcm filepos
 mov  dword ptr [@@worst_pcm_filepos],edx       ;/
 mov  edx,dword ptr [stream_pos]                ;\
 sub  edx,dword ptr [stream_start]              ; apply max diff mp3 filepos
 mov  dword ptr [@@worst_mp3_filepos],edx       ;/
@@not_max:
 movzx eax,word ptr [@@pcm_steps+0]             ;\
 ror  dword ptr [@@pcm_steps],16   ;swap steps  ; next .pcm addr
 add  edi,eax                                   ; (when rate_shift, with alternating left/right steps)
 add  dword ptr [@@pcm_filepos],eax             ;/
 dec  ecx
 jnz        @@compare_lop
@@compare_done:
 mov  eax,dword ptr [mp3_src_frame_size]        ;\
 add  dword ptr [stream_pos],eax                ; src stream
 sub  dword ptr [bytes_left],eax                ;/
 jmp        @@lop                               ;-next
;---
@@exit:
 call mp3_close_pcm_file                        ;-close pcm file
        ;XXX warn if wrong filesize
 mov  edx,offset @@txt_verify1
 call wrstr_edx
 mov  eax,dword ptr [@@max_diff]                ;\max diff
 call wr_decimal_eax                            ;/
 mov  edx,offset @@txt_verify1_at_mp3
 call wrstr_edx
 mov  eax,dword ptr [@@worst_mp3_filepos]       ;\worst mp3 filepos
 call wrhexeax                                  ;/
        ;XXX show @@worst_pcm_filepos
 mov  edx,offset @@txt_verify2
 call wrstr_edx
 mov  eax,dword ptr [@@avg_diff+0]              ;\
 mov  edx,dword ptr [@@avg_diff+4]              ; average diff
 mov  ecx,dword ptr [mp3_total_output_size]     ;
 shr  ecx,1     ;for 16bit                      ;
 div  ecx                                       ;
 call wr_decimal_eax                            ;/
        mov  al,'.'
        call wrchr
        mov  eax,10
        mul  edx        ;fraction*10
        div  ecx                                       ;
        call wrdigital ;show fraction of average difference
 call wrcrlf
 ret
;------------------
mp3_open_pcm_file:
 push 0       ;for Win95 always 0       ;\
 push FILE_ATTRIBUTE_NORMAL             ;
 push OPEN_EXISTING                     ;
 push 0        ;no Security-attributes  ; create
 push 0        ;disable Share-Mode      ;
 push GENERIC_READ                      ;
 push dword ptr [mp3_pcm_fname]         ;
 call CreateFileA                       ;
 mov  dword ptr [mp3_pcm_handle],eax    ;/
 ret
;------------------
mp3_close_pcm_file:
 push dword ptr [mp3_pcm_handle]                        ;\close file
 call CloseHandle                                       ;/
 ret
;------------------
ENDIF ;with_verify_to_pcm_file
;------------------
;:----------------- Output to speaker
;------------------
IF with_output_to_speaker
;------------------
warn_error_eax macro txt
local @@no_error,@@txt
 IF log_waveout_errors
  ;this was added in v1.4, giving more straight-in-the-face error messages,
  ;hoping that possible errors won't go unnoticed and unreported.
  ;as an extra warning, the "destroyer" function is artifically distorting
  ;the audio output (even in case of minor errors that had occurred only
  ;in a single frame, which might go unnoticed without the "destroyer").
  ;- - -
   cmp  eax,0                     ;\
   jz   short @@no_error          ;/
   pusha
   mov  edx,offset txt_waveout_error1   ;\
   call wrstr_edx                       ;/
   call wr_decimal_eax                  ;-
   mov  edx,offset txt_waveout_error2   ;\
   call wrstr_edx                       ;/
   mov  edx,offset @@txt                ;\
   call wrstr_edx                       ;/
   mov  edx,offset txt_waveout_error3   ;\
   call wrstr_edx                       ;/
   mov  dword ptr [have_wave_error],1
   popa
  ;- - -
  @@no_error:
   .const
    @@txt db txt,0
   .code
 ENDIF
endm
;---
warn_error_destroyer_wavehdr_ebx macro
 IF log_waveout_errors
   cmp  dword ptr [have_wave_error],0
   jz   short @@no_destroyer
   pusha
   IF 0
     mov  edi,dword ptr [ebx+00h]  ;buf           ;\
     mov  ecx,dword ptr [ebx+04h]  ;bufsize       ;
     lea  esi,[edi+ecx]                           ; output the whole block
    @@reverser_lop:                               ; in reverse
     sub  esi,2                                   ; hmmm, sounds a bit distored,
     mov  ax,word ptr [esi]                       ; but lyrics are still intact,
     xchg ax,word ptr [edi]                       ; maybe the frames are so small
     mov  word ptr [esi],ax                       ; that one can't hear the
     add  edi,2                                   ; typical reverse-play effect
     cmp  esi,edi                                 ;
     ja   short @@reverser_lop                    ;/
   ENDIF
   mov  edi,dword ptr [ebx+00h]  ;buf           ;\
   test word ptr [edi],0103h                    ;
   jnz  short @@scratch_skip                    ; cause really nasty
   mov  ecx,dword ptr [ebx+04h]  ;bufsize       ; scritch/scratch sounds
   shr  ecx,3   ;div 8 (aka 4 words)            ; every some frames on random
   mov  ax,5234h                                ;
  @@scratch_lop:                                ; impossible that this
   ror  ax,1                                    ; could go unnoticed
   add  word ptr [edi+0],ax                     ;
   add  word ptr [edi+2],ax                     ;
   add  word ptr [edi+4],ax                     ;
   add  word ptr [edi+6],ax                     ;
   add  edi,8                                   ;
   loop short @@scratch_lop                     ;
  @@scratch_skip:                               ;/
   and  eax,07h                                 ;\
   add  eax,4                                   ;
   mov  ecx,eax                                 ; and additionally, display
  @@random_chr_lop:                             ; random random chars and ERROR
   or   al,20h                                  ;
   call wrchr                                   ;
   add  al,53h                                  ;
   loop short @@random_chr_lop                  ;
   mov  edx,offset txt_ERROR                    ;
   call wrstr_edx                               ;
   popa                                         ;/
  @@no_destroyer:
 ENDIF
endm
;---
warn_error_crash macro
 IF log_waveout_errors
   cmp  dword ptr [have_wave_error],0           ;\final extra warning (in case
   jz   short @@no_crash                        ; destroyer went unnoticed, eg.
   xor  ecx,ecx       ;\trigger div0 exception  ; if error occured at end of
   div  ecx           ;/                        ; song, or in final waveout
  @@no_crash:                                   ;/reset/close cleanup)
 ENDIF
endm
;---
IF log_waveout_errors
.data
 have_wave_error    dd 0
.const
 txt_waveout_error1 db 0dh,0ah,'   *** ERROR number ',0
 txt_waveout_error2 db ' in function ',0
 txt_waveout_error3 db 0dh,0ah,'    ... bugdefect.@@@+critical\&&&-kaputt_###~F:A:I:L:U:R:E',0dh,0ah,0dh,0ah,0
 txt_ERROR          db 'ERROR',0
.code
ENDIF
;------------------
logg macro txt
 local @@txt
 IF log_waveout_status
   ;this was used in v1.3 log*.exe, but nobody bothered to send log files,
   ;probably it's just not a good user experience to display lots of status
   ;info, especially if the user can't easily see if there are actual ERRORs
   ;hidden in that status info.
   ;- - -
   mov  edx,offset @@txt
   call wrstr_edx
   call wr_decimal_eax
   call wrcomma
   ;- - -
   .const
    @@txt db txt,0
   .code
 ENDIF
endm
;------------------
.const
txt_waveopen_failed db '  ERROR: cannot open wave output!',0dh,0ah,0

.data
align 4
;------------------
num_enqueued_frames  dd 0
IF ENQUEUE_DUAL_INC
 num_finished_frames dd 0
ENDIF
mp3_waveout_handle   dd 0
;------------------
mp3_wf:  ;static WAVEFORMATEX (12h bytes)
 dw   1  ;00h wFormatTag (1=WAVE_FORMAT_PCM)                             ;1
 dw   2  ;02h nChannels         ;<-- VAR                                 ;1..4
 dd   0  ;04h nSamplesPerSec    ;<-- VAR                                 ;eg. 44100
 dd   0  ;08h nAvgBytesPerSec   ;<-- VAR   ;SamplesPerSec*BlockAlign     ;eg. 44100*(1..4)
 dw   4  ;0Ch nBlockAlign       ;<-- VAR   ;NumChannels*BitsPerSample/8  ;1..4
 dw   16 ;0Eh wBitsPerSample    ;<-- VAR                                 ;8 or 16
 dw   0  ;10h cbSize (0=no extra data) ;BUG: was set to "sizeof(WAVEFORMATEX)" ;0
align 4
;------------------
align data_align
mp3_wave_headers db BUFFER_COUNT*20h dup (0)  ;array of WAVEHDR's (20h bytes each)
 ;00h lpData (ptr to sample data)
 ;04h dwBufferLength (VAR, depends on num channels/granules, max MP3_MAX_OUTPUT_SIZE)
 ;08h dwBytesRecorded
 ;0Ch dwUser
 ;10h dwFlags
 ;14h dwLoops        ;???  number of loops
 ;18h lpNext
 ;1Ch reserved
sizeof_WAVEHDR equ 20h
.code
;------------------
prepare_wave_headers:   ;in: esi=wavehandle
 mov  ebx,offset mp3_wave_headers  ;hdr         ;-
 mov  edi,ebx   ;hdr                            ;\
 mov  ecx,BUFFER_COUNT*20h/4                    ; initially zerofill
 xor  eax,eax                                   ; all wavehdr's
 rep  stosd                                     ;/
 mov  edi,offset sample_buffer     ;buf         ;\loop...
@@prepare_lop:                                  ;/
 mov  dword ptr [ebx+00h],edi ;ptr to buf       ;\
 mov  dword ptr [ebx+04h],MP3_MAX_OUTPUT_SIZE   ;/
@@retry_prepare_lop:
 push sizeof_WAVEHDR                          ;\;\
 push ebx   ;wavehdr                          ; ; prepare
 push esi   ;wave_out_handle                  ; ;
 call waveOutPrepareHeader                    ; ;/
 IF log_waveout_status                        ;
   logg <'pr'>                         ;-PREPARE
 ENDIF                                        ;
 IF ENQUEUE_FROM_WOM                          ;
   cmp  eax,5   ;5 = MMSYSERR_INVALHANDLE     ; ;\weirdly, first call fails with invalid handle, despite of WOM_OPEN providing a valid handle.
   je   short @@retry_prepare                 ; ;/apparently waveOutOpen hasn't finished when issuing WOM_OPEN. as workaround: simply retry (or do a Sleep at begin of WOM_OPEN).
   cmp  eax,12  ;12 = MMSYSERR_HANDLEBUSY     ; ;\as above, for newer windows versions
   je   short @@retry_prepare                 ; ;/(win98 returns 5, nower windows returns 12)
   jmp  short @@no_retry_needed               ;
  @@retry_prepare:                            ;
   push 0                                     ; ;\sleep before retry
   call Sleep                                 ; ; win98 would succeed on 1st retry (without sleep)
   jmp  short @@retry_prepare_lop             ; ;/but, without sleep, newer window versions do reportedly fail on at least 8 retries
  @@no_retry_needed:                          ;
 ENDIF                                        ;
 warn_error_eax <'waveOutPrepareHeader'>      ;/
 add  edi,MP3_MAX_OUTPUT_SIZE        ;buf               ;\
 add  ebx,20h                        ;hdr               ; next
 cmp  ebx,offset mp3_wave_headers+BUFFER_COUNT*20h      ;
 jb   short @@prepare_lop                               ;/
 ret
;------------------
unprepare_wave_headers:
 mov  ebx,offset mp3_wave_headers
@@unprepare_lop:
 push sizeof_WAVEHDR                          ;\;\
 push ebx       ;wavehdr                      ; ; unprepare
 push dword ptr [mp3_waveout_handle]          ; ; (note: this is allowed even if the header wasn't prepared)
 call waveOutUnprepareHeader                  ; ;/
 IF log_waveout_status                        ;
   logg <'un'>                         ;-UNPREPARE
 ENDIF                                        ;
 warn_error_eax <'waveOutUnprepareHeader'>    ;/
 add  ebx,20h                        ;hdr               ;\
 cmp  ebx,offset mp3_wave_headers+BUFFER_COUNT*20h      ; next
 jb   short @@unprepare_lop                             ;/
 ret
;------------------
try_enqueue_esi_ebx:
@@enqueue_retry:
 cmp  dword ptr [bytes_left],0                          ;\
 jle        @@enqueue_done                              ;/
 pusha                                          ;\
 mov  esi,dword ptr [stream_pos]          ;src  ;
 mov  ecx,dword ptr [bytes_left]          ;siz  ;
 mov  edi,dword ptr [ebx+00h]  ;hdr[00h]  ;dst  ; decode frame
 xor  ebp,ebp                             ;vals ;
 call mp3_decode_frame                          ;
 popa                                           ;
 jc         @@enqueue_done                      ;/
 mov  eax,dword ptr [mp3_src_frame_size]        ;\
 cmp  eax,0                                     ;
 jz         @@enqueue_done                      ; src stream
 add  dword ptr [stream_pos],eax                ;
 sub  dword ptr [bytes_left],eax                ;/
 mov  eax,dword ptr [mp3_samples_output_size]   ;\apply output size
 cmp  eax,0                 ;\skip if empty     ; (or getnext if bad/empty,
 jz   short @@enqueue_retry ;/                  ; eg. for l3-sin1k0db.bit)
 mov  dword ptr [ebx+04h],eax  ;hdr[04h]  ;siz  ;/
 warn_error_destroyer_wavehdr_ebx
 push sizeof_WAVEHDR                            ;\
 push ebx   ;wavehdr                            ; send to sound hardware
 push esi   ;waveout_handle                     ;
 call waveOutWrite                              ;/
 warn_error_eax <'waveOutWrite'>
 IF log_waveout_status
   logg <'wr'>                          ;-WRITE
 ENDIF
 IF ENQUEUE_LOCK
 lock
 ENDIF
 inc  dword ptr [num_enqueued_frames]           ;-
 IF log_waveout_status
   mov  eax,dword ptr [num_enqueued_frames]
   logg <'en'>                          ;-ENQUEUED
 ENDIF
 ret
;---
@@enqueue_done:
 mov  dword ptr [bytes_left],0          ;-force end (for @@playback_wait_lop)
 ret
;------------------
IF ENQUEUE_FROM_WOM or ENQUEUE_DUMB
try_enqueue_esi_all_blocks:
 mov  ebx,offset mp3_wave_headers    ;hdr               ;\
@@enqueue_initial_lop:                                  ;
 call try_enqueue_esi_ebx                               ; enqueue buffers
 add  ebx,20h                        ;hdr               ;
 cmp  ebx,offset mp3_wave_headers+BUFFER_COUNT*20h      ;
 jb   short @@enqueue_initial_lop                       ;/
 ret
ENDIF
;------------------
AudioCallback:
 push ebp
 mov  ebp,esp
@@waveout_handle equ dword ptr ss:[ebp+8]   ;waveout handle
@@uMsg           equ dword ptr ss:[ebp+12]  ;wave message (WOM_OPEN,WOM_CLOSE,WOM_DONE)
@@userdat        equ dword ptr ss:[ebp+16]  ;instance?
@@param1         equ dword ptr ss:[ebp+20]  ;ptr to wavehdr (when WOM_DONE)
@@param2         equ dword ptr ss:[ebp+24]  ;zero
@@wave_header    equ @@param1
 IF log_waveout_status
   call wrcrlf                                  ;-
   mov  eax,@@uMsg                              ;\
   sub  eax,955                                 ; MSG
   logg <'msg'>                                 ;/
   mov  eax,@@waveout_handle                    ;\
   sub  eax,dword ptr [mp3_waveout_handle]      ; HANDLE
   logg <'h'>                                   ;/
 ENDIF
 IF ENQUEUE_FROM_WOM
   cmp  @@uMsg,WOM_OPEN
   jne  short @@not_wom_open
   pusha
   mov  esi,@@waveout_handle                    ;\prepare all buffers
   call prepare_wave_headers                    ;/
   call try_enqueue_esi_all_blocks              ;-enqueue all buffers
   popa
   jmp  short @@exit
  @@not_wom_open:
 ENDIF

 cmp  @@uMsg,WOM_DONE                   ;\BUG: this wasn't checked in HLL code
 jne  short @@exit                      ;/
 IF log_waveout_status
   mov  eax,@@wave_header               ;\
   sub  eax,offset mp3_wave_headers     ; HDR
   ror  eax,5                           ;
   logg <'hdr'>                         ;/
 ENDIF
 IF ENQUEUE_DUAL_INC
   inc  dword ptr [num_finished_frames]   ;-
   IF log_waveout_status
     mov  eax,dword ptr [num_finished_frames]
     logg <'fin'>                        ;-FINISHED
   ENDIF
 ELSEIF ENQUEUE_FROM_WOM or ENQUEUE_DUMB
   pusha
   mov  esi,@@waveout_handle
   mov  ebx,@@wave_header
   call try_enqueue_esi_ebx
   popa
   dec  dword ptr [num_enqueued_frames]   ;-
 ELSE
   IF ENQUEUE_LOCK
   lock
   ENDIF
   dec  dword ptr [num_enqueued_frames]   ;-
 ENDIF
@@exit:    ;no return value
 leave
 ret  5*4  ;remove five dwords on stack
;------------------
mp3_cast_to_speaker:
 mov  eax,dword ptr [mp3_output_sample_rate]    ;\
 mov  ecx,dword ptr [mp3_output_num_channels]   ;
 mov  edx,dword ptr [mp3_bytes_per_sample]      ; apply sample rate
 mov  word ptr [mp3_wf+02h],cx   ;NumChannels   ; and num channels
 mov  dword ptr [mp3_wf+04h],eax ;SamplesPerSec ; and bits/sample
 imul ecx,edx  ;NumChannels*BytesPerSample      ;
 imul eax,ecx  ;mul SamplesPerSec               ;
 shl  edx,3    ;bits/sample = bytes*8           ;
 mov  dword ptr [mp3_wf+08h],eax ;BytesPerSec   ;
 mov  word ptr [mp3_wf+0ch],cx   ;BlockAlign    ;
 mov  word ptr [mp3_wf+0eh],dx   ;BitsPerSample ;/
 push CALLBACK_FUNCTION                         ;\
 push NULL            ;user_data                ;
 push offset AudioCallback                      ;
 push offset mp3_wf   ;wave_format              ; set up wave output
 push WAVE_MAPPER                               ;
 push offset mp3_waveout_handle ;dst for handle ;   <-- this seems to be applied AFTER WOM_OPEN (don't use inside WOM_OPEN)
 call waveOutOpen                               ;
 cmp  eax,MMSYSERR_NOERROR              ;\      ;
 je   short @@wave_open_okay            ;       ;
 mov  edx,offset txt_waveopen_failed    ; error ;
 call wrstr_edx                         ;       ;
 jmp        @@done_quit                 ;       ;
@@wave_open_okay:                       ;/      ;
 warn_error_eax <'waveOutOpen'>                 ;
 IF log_waveout_status                          ;
   logg <'open'>                           ;-   ;
   mov  eax,dword ptr [mp3_waveout_handle] ;\   ;
   logg <'handle'>                         ;/   ;
   call wrcrlf                             ;-   ;
 ENDIF                                          ;/
;- - -
IF ENQUEUE_FROM_WOM or ENQUEUE_DUMB
 ;this is sorts of most elegant (sending blocks right in the WOM_xxx callback),
 ;BUT, microsoft states that one shouldn't call other functions (with a few
 ;exceptions) from inside of the callback, and it works only with some weird
 ;retry-trick in 1st call to waveOutPrepareHeader.
 IF ENQUEUE_DUMB
   ;this does enqueue all frames in advance (before starting playback)
   ; - disadvantage: may take 200ms (for 8 buffers, on a slow PC) before playback starts. on a faster PC with 1GHz it's probably only 2ms (except, those numbers would go up when using more than 8 buffers, eg. to enqueue several seconds in advance)
   ; - advantage: prefilling all buffers reduces risk of gaps when other tasks get busy
   mov  esi,dword ptr [mp3_waveout_handle]              ;\
   call prepare_wave_headers                            ;/
   push dword ptr [mp3_waveout_handle]                  ;\pause (to prevent nested-callback-crashes while enqueuing first some blocks)
   call waveOutPause                                    ;
   warn_error_eax <'waveOutPause'>                      ;/
   call try_enqueue_esi_all_blocks                      ;-
   push dword ptr [mp3_waveout_handle]                  ;\undo pause
   call waveOutRestart                                  ;
   warn_error_eax <'waveOutRestart'>                    ;/
 ENDIF
@@playback_wait_lop:
 ;max rate is 38.3 blocks/second (26 ms/block)  ;\
 mov  eax,dword ptr [num_enqueued_frames]       ;
 imul eax,10                ;wait 10ms/block    ; sleep
 push eax                   ;wait 10ms/block    ;
 call Sleep                                     ;/
 mov  eax,dword ptr [num_enqueued_frames]       ;\
 or   eax,dword ptr [bytes_left]                ; until all done
 jnz  short @@playback_wait_lop                 ;/

ELSE ;--- --- --- ---
 mov  esi,dword ptr [mp3_waveout_handle]                ;\
 call prepare_wave_headers                              ;/
 mov  ebx,offset mp3_wave_headers     ;wavehdr          ;-
@@enqueue_lop:          ;loop until done, or Ctrl+C pressed
 cmp  dword ptr [bytes_left],0                          ;\
 jle        @@enqueue_done                              ;/
 IF ENQUEUE_DUAL_INC
   mov  eax,dword ptr [num_enqueued_frames]
   sub  eax,dword ptr [num_finished_frames]
   cmp  eax,BUFFER_COUNT
   jae        @@buffer_full_sleep
 ELSE
   cmp  dword ptr [num_enqueued_frames],BUFFER_COUNT      ;\
   jae        @@buffer_full_sleep                         ;/
 ENDIF
 mov  esi,dword ptr [mp3_waveout_handle]                ;\
;mov  ebx,ebx   ;wavehdr                                ; enqueue
 call try_enqueue_esi_ebx                               ;/
 add  ebx,20h                    ;wavehdr               ;\
 cmp  ebx,offset mp3_wave_headers+BUFFER_COUNT*20h      ;
 jb         @@enqueue_lop                               ; next
 sub  ebx,20h*BUFFER_COUNT                              ;
 jmp        @@enqueue_lop                               ;/
;---
@@buffer_full_sleep:
 ;max rate is 38.3 blocks/second (26 ms/block)  ;\
;;; mov  eax,dword ptr [num_enqueued_frames]       ;
;;; sub  eax,dword ptr [num_finished_frames]       ;
;;; imul eax,10                ;wait 10ms/block    ; sleep
;;; push eax                   ;wait 10ms/block    ;
 push BUFFER_COUNT*10       ;wait 10ms/block    ; sleep
 call Sleep                                     ;/
 jmp        @@enqueue_lop
;---
@@enqueue_done:
@@wait_completion:                              ;\
 push 10                    ;wait 10ms          ; wait until remaining
 call Sleep                                     ; playback has completed
 IF ENQUEUE_DUAL_INC
   mov  eax,dword ptr [num_enqueued_frames]
   sub  eax,dword ptr [num_finished_frames]
 ELSE
   cmp  dword ptr [num_enqueued_frames],0         ;
 ENDIF
 jnz  short @@wait_completion                   ;/

ENDIF

;- - -
 push dword ptr [mp3_waveout_handle]            ;\
 call waveOutReset                              ;
 warn_error_eax <'waveOutReset'>                ;/
 call unprepare_wave_headers                    ;-
 push dword ptr [mp3_waveout_handle]            ;\
 call waveOutClose                              ;
 warn_error_eax <'waveOutClose'>                ;/
 warn_error_crash                               ;-do final crash on error
@@done_quit:
 ret
;------------------
ENDIF ;with_output_to_speaker
;------------------
;:----------------- xxx
;------------------
fatalunexpected:
 div  @@zero    ;throw div0 error
 jmp  short $
.data
@@zero dd 0
.code
;------------------
;:----------------- main
;------------------
entrypoint:
;pusha
 push STD_OUTPUT_HANDLE         ;\
 call GetStdHandle              ; get std_out
 mov  dword ptr [std_out],eax   ;/
 mov  edx,offset txt_hello      ;\hello
 call wrstr_edx                 ;/
 call get_commandline           ;\get commandline
 jc         @@exit              ;/
 xor  ebp,ebp   ;vals           ;\init mp3 decoder
 call mp3_init                  ;/
 call open_and_mmap_the_file    ;\load src file
 jc         @@exit              ;/
;- - -
 IF log_timing
   call detect_cpu_386_and_up
   call xmit_get_priority_defaults
   call GetTickCount                            ;\
   neg  eax                                     ;
   mov  dword ptr [millisecond_count],eax       ;/
 ENDIF
;- - -
 call mp3_check_1st_frame                       ;\
 jc         @@exit  ;error                      ;/
;- - -
 IF with_raw_testing
   cmp  byte ptr [option_test],0
   jz   short @@no_benchmark_test
   call mp3_plain_test_without_output           ;---------->
   jmp  short @@decode_done
  @@no_benchmark_test:
 ENDIF
 IF with_verify_to_pcm_file
   cmp  dword ptr [mp3_pcm_fname],0
   jz   short @@no_pcm_verify
   call mp3_verify_pcm_file                     ;---------->
   jmp        @@exit  ;without timing stats
  @@no_pcm_verify:
 ENDIF
 IF with_output_to_wav_file
   cmp  dword ptr [mp3_dst_fname],0
   jz   short @@no_wav_output
   call mp3_cast_to_wav_file                    ;---------->
   jmp  short @@decode_done
  @@no_wav_output:
 ENDIF
 IF with_output_to_speaker
   call mp3_cast_to_speaker                     ;---------->
 ENDIF
@@decode_done:
 timelog_display_results
@@exit:
 push 0                  ;\exit (weirdly, "ret" doesn't work if waveOut was used)
 call ExitProcess        ;/
;popa
;ret    ;ret works only if registers were pushed, and only if waveOut wasn't used
;------------------
end entrypoint

