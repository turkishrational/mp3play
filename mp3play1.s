; ****************************************************************************
; MP3PLAY.PRG - MP3 DECODER/PLAYER 1.0 for TRDOS 386 Operating System
; ----------------------------------------------------------------------------
; Based on 
; NOCASH MP3PLAY.EXE 1.4 (Windows) ASM source code (Martin Korth, 20/09/2024)
;
; FASM Source Code: Erdogan Tan - 19/10/2024 - 22/10/2024
; NASM Source Code: Erdogan Tan - 09/01/2025
;
; [ Last Modification: 12/01/2025 ]
;
; ----------------------------------------------------------------------------
; Modified from on MP3PLAY.ASM (for Windows console) source code - 17/10/2024
; ****************************************************************************
; Modified from Martin Korth's 'mp3play.asm' (TASM32) source code... (v1.4)
; Applied development method:
;         Disassembling 'mp3play.exe' v1.4 by using HEX-RAYS disassembler;
;         then... converting disassembled code to FASM syntax,
;                 adding '.idata' code (by help of FASM examples) to the raw
;                        asm file. Converting 'proc' procedures to labels.
;               and Finally: assembling mp3play.asm (single) file by using
;                           'fasm mp3play.asm' command.
;
; NOTE:
; Martin Korth's MP3PLAY.EXE (v1.4, 20/09/2024) file size is 45056 bytes.
; (This) modified MP3PLAY.EXE (v1.4.0, 17/10/2024) is 37888 bytes.
;
; ---------------------------------------------------------------------------
; nasm mp3play.s -l mp3play.txt -o MP3PLAY.PRG -Z error.txt


; ===========================================================================
; CODE
; ===========================================================================

		[BITS 32] ; 32-bit intructions

		[ORG 0]

; ===========================================================================

		; 20/10/2024
start:
		; 21/10/2024
		call	set_break	; set and clear bss section
					; also set stream_start position

                ;mov    edx, txt_hello  ; "nocash mp3 decoder v1.4, 2024" ...
                ;call   wrstr_edx
		mov	ebx, txt_hello
		call	print_msg

                call    get_commandline
                jc      .exit

                xor     ebp, ebp
                call    mp3_init
                call    open_and_mmap_the_file
                jc      .exit
                call    detect_cpu_386_and_up
                call    GetTickCount
                neg     eax
                mov     [millisecond_count], eax

		;;;
		; 11/01/2025
		call	detect_enable_audio_device
		jc	.exit
		;;;

                call    mp3_check_1st_frame
                jc      .exit
                cmp     byte [option_test], 0
                jz      short .no_benchmark_test
                call    mp3_plain_test_without_output
                jmp     short .decode_done

.no_benchmark_test:
                cmp     dword [mp3_pcm_fname], 0
                jz      short .no_pcm_verify
                call    mp3_verify_pcm_file
                jmp     .exit

.no_pcm_verify:
                cmp     dword [mp3_dst_fname], 0
                jz      short .no_wav_output
                call    mp3_cast_to_wav_file
                jmp     short .decode_done

.no_wav_output:
		;;; 
		; 20/10/2024
		;call	detect_enable_audio_device
		;jc	.exit
		call	audio_system_init
		jc	.exit
		;;;

                call    mp3_cast_to_speaker

.decode_done:
                call    GetTickCount
                add     [millisecond_count], eax
                mov     edx, txt_decode_timing1 ; "audio duration "
                call    wrstr_edx
                mov     eax, [mp3_total_output_size]
                mov     edx, 1000
                mul     edx
                div     dword [mp3_output_sample_rate]
                xor     edx, edx
                div     dword [mp3_output_num_channels]
                xor     edx, edx
                div     dword [mp3_bytes_per_sample]
                mov     [mp3_output_milliseconds], eax
                call    wr_decimal_eax_with_thousands_seperator
                mov     edx, txt_decode_timing2 ; " milliseconds, decoded in "
                call    wrstr_edx
                mov     eax, [millisecond_count]
                call    wr_decimal_eax_with_thousands_seperator
                mov     edx, txt_decode_timing3 ; " milliseconds\r\n"
                call    wrstr_edx
                mov     edx, txt_clks_per_second ; " clock cycles per second:\r\n"
                call    wrstr_edx
                mov     esi, ttt ; rdtsc_list_start

.timelog_lop:
                call    wrspc
                lea     edx, [esi+8]
                call    wrstr_edx
                call    wrspc
                mov     eax, [esi]
                mov     ebx, [esi+4]
                mov     edx, 1000
                imul    ebx, edx
                mul     edx
                add     edx, ebx
                cmp     edx, [mp3_output_milliseconds]
                jnb     short .timelog_oops
                div     dword [mp3_output_milliseconds]
                call    wr_decimal_eax_with_thousands_seperator

.timelog_oops:
                call    wrcrlf
                add     esi, 24
                cmp     esi, mp3_bitrate_tab
                jnz     short .timelog_lop

.exit:
		;push   0               ; uExitCode
                ;call   ExitProcess
		jmp	ExitProcess


; =============== S U B R O U T I N E =======================================


detect_cpu_386_and_up:
                mov     byte [detected_cpu], 3
                mov     ebx, esp
                and     esp, ~3 ; not 3
                pushf
                pop     eax
                mov     ecx, eax
                xor     eax, 40000h
                push    eax
                popf
                pushf
                pop     eax
                xor     eax, ecx
                push    ecx
                popf
                mov     esp, ebx
                test    eax, 40000h
                jz      short .no_id
                inc	byte [detected_cpu]
                call    @@get_id_flag
                jnz     short .yep_id
                call    @@get_id_flag
                jz      short .no_id

.yep_id:
                mov     eax, 1
                cpuid
                and     ah, 0Fh
                mov     [detected_cpu], ah
                mov	byte [cpuid_exists], 1
                mov     [cpuid_flags], edx

.no_id:
                retn

; =============== S U B R O U T I N E =======================================


@@get_id_flag:
                pushf
                pop     eax
                or      eax, 200000h
                push    eax
                popf
                pushf
                pop     eax
                test    eax, 200000h
                retn

; =============== S U B R O U T I N E =======================================

bswap_eax:
                xchg    al, ah
                ror     eax, 10h
                xchg    al, ah
                retn

; =============== S U B R O U T I N E =======================================

mp3_recollect_bits:
                test    esi, 1
                jnz     short .odd
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                shl     ebp, 16
                mov     ch, 0
                retn

.odd:
                movzx   ebp, byte [esi]
                inc     esi
                shl     ebp, 16
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                shl     ebp, 8
                mov     ch, 8
                retn

; =============== S U B R O U T I N E =======================================


mp3_get_bits:
                mov     eax, ebp
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                js      short mp3_collect_more
                retn

mp3_collect_more:
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl
                retn

; =============== S U B R O U T I N E =======================================


mp3_uncollect_bits:
                sub     esi, 2
                shr     ch, 3
                movzx   ecx, ch
                sub     esi, ecx
                retn

; =============== S U B R O U T I N E =======================================


mp3_search_get_header:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [ttt], eax
                sbb     [ttt+4], edx

.no_rdtsc_supported:
                mov	dword [mp3_extra_bytes], 0

.retry_header:
                cmp	dword [mp3_src_remain], 4
                jb      .fail_no_header
                cmp     byte [esi], 0FFh
                jnz     short .bad_header
                mov     al, [esi+1]
                and     al, 0E6h
                cmp     al, 0E2h
                jnz     short .bad_header
                mov     al, [esi+2]
                cmp     al, 0F0h
                jnb     short .bad_header
                and     al, 0Ch
                cmp     al, 0Ch
                jnz     short .good_header

.bad_header:
                inc	esi
                dec	dword [mp3_src_remain]
                inc	dword [mp3_extra_bytes]
                mov	dword [main_data_pool_wr_ptr], main_data_pool_start
                jmp	short .retry_header

.good_header:
                mov	eax, [esi]
                call	bswap_eax
                mov	[mp3_hdr_32bit_header], eax
                mov	dword [mp3_hdr_flag_lsf], 0
                mov	dword [mp3_hdr_flag_mpeg25], 0
                mov	dword [mp3_nb_granules], 2
                test	eax, 80000h
                jnz	short .lsf_this
                mov	dword [mp3_hdr_flag_lsf], 1
                mov	dword [mp3_nb_granules], 1
                test	eax, 100000h
                jnz	short .lsf_this
                mov	dword [mp3_hdr_flag_mpeg25], 1

.lsf_this:
                shr     eax, 10
                and     eax, 3
                mov     ecx, [mp3_hdr_flag_lsf]
                add     ecx, [mp3_hdr_flag_mpeg25]
                movzx   edx, word [mp3_freq_tab+eax*2]
                shr     edx, cl
                lea     ecx, [ecx+ecx*2]
                add     eax, ecx
                mov     [mp3_hdr_sample_rate_index], eax
                mov     [mp3_sample_rate], edx

                mov     cl, [option_rate_shift]
                shr     edx, cl

                mov     [mp3_output_sample_rate], edx
                mov     eax, [mp3_hdr_32bit_header]
                shr     eax, 10h
                not     eax
                and     eax, 1
                mov     [mp3_hdr_flag_crc], eax
                mov     eax, [mp3_hdr_32bit_header]
                shr     eax, 9
                and     eax, 1
                mov     [mp3_hdr_flag_padding], eax
                mov     eax, [mp3_hdr_32bit_header]
                shr     eax, 12
                and     eax, 0Fh
                jnz     short .not_free_format
                call    mp3_detect_free_format_block_size
                jb      .bad_header
                mov     eax, [mp3_free_format_frame_size]
                jmp     short .this_frame_size_plus_padding

.not_free_format:
                mov     edx, [mp3_hdr_flag_lsf]
                shl     edx, 4
                add     eax, edx
                movzx   eax, word [mp3_bitrate_tab+eax*2] ; kbit/s
                imul    eax, 1000       ; bit/s
                mov     [mp3_bit_rate], eax
                imul    eax, 144        ; 144=90h=8*18
                xor     edx, edx
                div     dword [mp3_sample_rate]
                mov     ecx, [mp3_hdr_flag_lsf]
                shr     eax, cl

.this_frame_size_plus_padding:
                add     eax, [mp3_hdr_flag_padding]
                mov     [mp3_src_frame_size], eax
                add     eax, esi
                mov     [mp3_src_frame_end], eax
                mov     eax, [mp3_hdr_32bit_header]
                shr     eax, 6
                and     eax, 3
                mov     [mp3_hdr_mode_val], eax
                mov     edx, 1

		cmp     al, 3
                jz      short .this_channels

                ;mov    edx, 2
		; 10/01/2025
		inc	edx
.this_channels:
                mov	[mp3_src_num_channels], edx
                cmp	byte [option_mono], 0
                jz	short .allow_stereo
                mov	edx, 1
.allow_stereo:
                mov     [mp3_output_num_channels], edx
                imul    edx, [mp3_bytes_per_sample]
                mov     [mp3_samples_dst_step], edx
                mov     eax, [mp3_hdr_32bit_header]
                shr     eax, 4
                and     eax, 3
                mov     [mp3_hdr_mode_ext], eax
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                add     [ttt], eax
                adc     [ttt+4], edx

.no_rdtsc_supported@:
                clc
                retn

.fail_no_header:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [ttt], eax
                adc     [ttt+4], edx

.no_rdtsc_supported@@:
                mov     dword [mp3_src_frame_size], 0
                stc
                retn


; =============== S U B R O U T I N E =======================================


mp3_bitstream_read_header_extra:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_read_header_extra], eax
                sbb     [rdtsc_read_header_extra+4], edx

.no_rdtsc_supported:
                cmp     dword [mp3_hdr_flag_crc], 0
                jz      short .without_crc
                mov     eax, ebp        ; mp3mac_get_n_bits 16
                shl     ebp, 10h
                rol     eax, 10h
                xor     eax, ebp
                sub     ch, 10h
                jns     short .without_crc
                mov     cl, ch          ; mp3mac_collect_more
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc:
                cmp     dword [mp3_hdr_flag_lsf], 0
                jz      short .pre_lsf_zero
                mov     dword [mp3_num_compress_bits], 9
                mov     eax, ebp        ; mp3mac_get_n_bits 8
                shl     ebp, 8
                rol     eax, 8
                xor     eax, ebp
                sub     ch, 8
                jns     short .without_crc@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@:
                mov     [mp3_main_data_begin], eax
                mov     cl, byte [mp3_src_num_channels]
                mov     eax, ebp        ; mp3mac_get_n_bits cl
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .without_crc@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@@:
                jmp     .pre_lsf_done

.pre_lsf_zero:
                mov     dword [mp3_num_compress_bits], 4
                mov     eax, ebp        ; mp3mac_get_n_bits 9
                shl     ebp, 9
                rol     eax, 9
                xor     eax, ebp
                sub     ch, 9
                jns     short .without_crc@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@@@:
                mov     [mp3_main_data_begin], eax
                mov     cl, byte [mp3_src_num_channels]
                shl     cl, 1           ; 1,2 --> 2,4
                xor     cl, 7           ;     --> 5,3
                mov     eax, ebp        ; mp3mac_get_n_bits cl
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .without_crc@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@@@@:
                mov     edx, [mp3_src_num_channels]
                mov     ebx, mp3_granules

.pre_channel_lop:
                mov     dword [ebx+40], 0 ; [ebx+$mp3gr_scfsi]
                add     ebx, 2464       ; $mp3gr_entrysiz
                mov     eax, ebp        ; mp3mac_get_n_bits 4
                shl     ebp, 4
                rol     eax, 4
                xor     eax, ebp
                sub     ch, 4
                jns     short .without_crc@@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@@@@@:
                mov     [ebx+28h], eax  ; [ebx+$mp3gr_scfsi]
                add     ebx, 2464       ; $mp3gr_entrysiz
                dec     edx
                jnz     short .pre_channel_lop

.pre_lsf_done:
                mov     eax, [mp3_nb_granules]
                imul    eax, 12h
                mov     [mp3_nb_frames], eax
                mov     eax, [mp3_nb_frames]
                imul    eax, [mp3_output_num_channels]
                imul    eax, [mp3_bytes_per_sample]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                mov     [mp3_samples_output_size], eax
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_read_header_extra
                jz      short .no_rdtsc_supported@
                rdtsc
                add     [rdtsc_read_header_extra], eax
                adc     [rdtsc_read_header_extra+4], edx

.no_rdtsc_supported@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_bitstream_read_granules:
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_read_granule
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_read_granule], eax
                sbb     [rdtsc_read_granule+4], edx

.no_rdtsc_supported:
                mov	[_@@saved_sp], esp
                mov	dword [mp3_main_data_siz], 0
                mov	dword [mp3_curr_granule], 0
                mov	ebx, mp3_granules

.hdr_granule_lop:
                push    ebx
                mov     dword [mp3_curr_channel], 0

.hdr_channel_lop:
                mov     eax, ebp        ; mp3mac_get_n_bits 12
                shl     ebp, 12
                rol     eax, 12
                xor     eax, ebp
                sub     ch, 12
                jns     short .without_crc
                mov     cl, ch
                add     ch, 16
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc:
                mov     edx, [mp3_main_data_siz]
                mov     [ebx], eax
                mov     [ebx+4], edx
                add     eax, edx
                mov     [ebx+8], eax
                mov     [mp3_main_data_siz], eax
                mov     eax, ebp        ; mp3mac_get_n_bits 9
                shl     ebp, 9
                rol     eax, 9
                xor     eax, ebp
                sub     ch, 9
                jns     short .without_crc@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@:
                mov     [ebx+12], eax   ; [ebx+$mp3gr_big_values]
                mov     eax, ebp        ; mp3mac_get_n_bits 8
                shl     ebp, 8
                rol     eax, 8
                xor     eax, ebp
                sub     ch, 8
                jns     short .without_crc@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@@:
                add	eax, 190        ; 400-210
                cmp	dword [mp3_hdr_mode_val], 1
                jnz	short .not_ms_stereo
                test	dword [mp3_hdr_mode_ext], 2
                jz	short .not_ms_stereo
                sub	eax, 2

.not_ms_stereo:
                mov     [ebx+16], eax   ; [ebx+$mp3gr_global_gain]
                mov     cl, byte [mp3_num_compress_bits]
                mov     eax, ebp        ; mp3mac_get_n_bits cl
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .without_crc@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@@@:
                mov     [ebx+20], eax   ; [ebx+$mp3gr_scalefac_compress]
                dec     ch              ; mp3mac_get_bit_to_cy
                                        ; dec mp3_colNN
                shl     ebp, 1          ; shl mp3_col32,1 ; cy=data
                jnb     .no_blocksplit
                mov     eax, ebp        ; mp3mac_get_n_bits 2
                shl     ebp, 2
                rol     eax, 2
                xor     eax, ebp
                sub     ch, 2
                jns     short .without_crc@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@@@@:
                cmp     eax, 0
                jz      .error
                mov     [ebx+44], eax   ; [ebx+$mp3gr_block_type]
                cmp     eax, 2
                mov     eax, 18         ; 36/2 ; region_size (default)
                jz      short .this_region_size
                cmp     dword [mp3_hdr_sample_rate_index], 2
                jbe     short .this_region_size
                mov     eax, 27         ; 54/2 ; region_size
                cmp     dword [mp3_hdr_sample_rate_index], 8
                jnz     short .this_region_size
                mov     eax, 54         ; 108/2 ; region_size (for rate=8)

.this_region_size:
                mov     [ebx+80], eax   ; [ebx+$mp3gr_region_size+0*4]
                mov     dword [ebx+84], 288 ; [ebx+$mp3gr_region_size+1*4],576/2
                mov     dword [ebx+88], 288 ; [ebx+$mp3gr_region_size+2*4],576/2
                mov     eax, ebp        ; mp3mac_get_n_bits 1
                shl     ebp, 1
                rol     eax, 1
                xor     eax, ebp
                sub     ch, 1
                jns     short .without_crc@@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@@@@@:
                mov     [ebx+48], eax   ; [ebx+$mp3gr_switch_point]
                mov     eax, ebp        ; IRP nn,0,1 ; only 0..1 for blocksplit
                shl     ebp, 5          ; mp3mac_get_n_bits 5
                rol     eax, 5
                xor     eax, ebp
                sub     ch, 5
                jns     short .without_crc@@@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc@@@@@@:
                mov     [ebx+56], eax   ; [ebx+$mp3gr_table_select+nn*4] ; nn=0
                mov     eax, ebp        ; mp3mac_get_n_bits 5
                shl     ebp, 5
                rol     eax, 5
                xor     eax, ebp
                sub     ch, 5
                jns     short .without_crc_@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc_@@@@:
                mov     [ebx+60], eax   ; [ebx+$mp3gr_table_select+nn*4] ; nn=1
                mov     eax, ebp        ; mp3mac_get_n_bits 5
                shl     ebp, 3          ; IRP nn,0,1,2
                rol     eax, 3          ; mp3mac_get_n_bits 3
                xor     eax, ebp
                sub     ch, 3
                jns     short .without_crc_@@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc_@@@@@:
                shl     eax, 3
                mov     [ebx+68], eax   ; [ebx+$mp3gr_subblock_gain+nn*4] ; nn=0
                mov     eax, ebp
                shl     ebp, 3
                rol     eax, 3
                xor     eax, ebp
                sub     ch, 3
                jns     short .without_crc_@@@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc_@@@@@@:
                shl     eax, 3
                mov     [ebx+72], eax   ; [ebx+$mp3gr_subblock_gain+nn*4] ; nn=1
                mov     eax, ebp
                shl     ebp, 3
                rol     eax, 3
                xor     eax, ebp
                sub     ch, 3
                jns     short .without_crc_@@@@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.without_crc_@@@@@@@:
                shl     eax, 3
                mov     [ebx+76], eax   ; [ebx+$mp3gr_subblock_gain+nn*4] ; nn=2
                jmp     .blocksplit_done

.no_blocksplit:                       
                mov     dword [ebx+44], 0 ; [ebx+$mp3gr_block_type]
                mov     dword [ebx+48], 0 ; [ebx+$mp3gr_switch_point]
                mov     eax, ebp        ; IRP nn,0,1,2 ; range 0..2 when non-blocksplit
                shl     ebp, 5          ; mp3mac_get_n_bits 5
                rol     eax, 5
                xor     eax, ebp
                sub     ch, 5
                jns     short .@_without_crc
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.@_without_crc:
                mov     [ebx+56], eax   ; [ebx+$mp3gr_table_select+nn*4] ; nn=0
                mov     eax, ebp
                shl     ebp, 5
                rol     eax, 5
                xor     eax, ebp
                sub     ch, 5
                jns     short .@_without_crc_@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.@_without_crc_@:
                mov     [ebx+60], eax   ; [ebx+$mp3gr_table_select+nn*4] ; nn=1
                mov     eax, ebp
                shl     ebp, 5
                rol     eax, 5
                xor     eax, ebp
                sub     ch, 5
                jns     short .@_without_crc_@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.@_without_crc_@@:
                mov     [ebx+64], eax   ; [ebx+$mp3gr_table_select+nn*4] ; nn=2
                mov     eax, ebp
                shl     ebp, 4
                rol     eax, 4
                xor     eax, ebp
                sub     ch, 4
                jns     short .@_without_crc@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.@_without_crc@@@:
                inc     eax
                mov     [_@@region_address0], eax
                mov     eax, ebp        ; mp3mac_get_n_bits 3
                shl     ebp, 3
                rol     eax, 3
                xor     eax, ebp
                sub     ch, 3
                jns     short .@_without_crc@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.@_without_crc@@@@:
                inc     eax
                add     eax, [_@@region_address0]
                mov     [_@@region_address1], eax
                mov     eax, [mp3_hdr_sample_rate_index]
                shl     eax, 5
                add     eax, [_@@region_address0]
                movzx   eax, word [mp3_band_index_long+eax*2]
                shr     eax, 1
                mov     [ebx+80], eax   ; [ebx+$mp3gr_region_size+0*4]
                mov     eax, [mp3_hdr_sample_rate_index]
                shl     eax, 5
                add     eax, [_@@region_address1]
                movzx   eax, word [mp3_band_index_long+eax*2]
                shr     eax, 1
                mov     [ebx+84], eax   ; [ebx+$mp3gr_region_size+1*4]
                mov     dword [ebx+88], 288 ; [ebx+$mp3gr_region_size+2*4],576/2

.blocksplit_done:
                lea     edi, [ebx+80]   ; [ebx+$mp3gr_region_size+0]
                xor     edx, edx
                mov     cl, 3

.trunc_region_size_lop:
                mov     eax, [edi]
                cmp     eax, [ebx+12]   ; [ebx+$mp3gr_big_values]
                jbe     short .trunc_region_size_this
                mov     eax, [ebx+12]

.trunc_region_size_this:
                sub     eax, edx
                mov     [edi], eax
                add     edx, eax
                add     edi, 4
                dec     cl
                jnz     short .trunc_region_size_lop
                mov     dword [ebx+28], 13 ; [ebx+$mp3gr_short_start]
                mov     dword [ebx+32], 22 ; [ebx+$mp3gr_long_end]
                cmp     dword [ebx+44], 2 ; [ebx+$mp3gr_block_type]
                jnz     short .these_band_indices
                mov     dword [ebx+28], 0 ; [ebx+$mp3gr_short_start]
                mov     dword [ebx+32], 0 ; [ebx+$mp3gr_long_end]
                cmp     dword [ebx+48], 0 ; [ebx+$mp3gr_switch_point]
                jz      short .these_band_indices
                mov     dword [ebx+28], 2 ; [ebx+$mp3gr_short_start]
                mov     dword [ebx+32], 4 ; [ebx+$mp3gr_long_end]
                cmp     dword [mp3_hdr_sample_rate_index], 8
                jz      short .these_band_indices
                cmp     dword [mp3_hdr_sample_rate_index], 2
                mov     dword [ebx+28], 3 ; [ebx+$mp3gr_short_start]
                mov     dword [ebx+32], 8 ; [ebx+$mp3gr_long_end]
                jbe     short .these_band_indices
                mov     dword [ebx+32], 6 ; [ebx+$mp3gr_long_end]

.these_band_indices:
                xor     eax, eax
                cmp     dword [mp3_hdr_flag_lsf], 0
                jnz     short .no_preflag
                mov     eax, ebp        ; mp3mac_get_n_bits 1
                shl     ebp, 1
                rol     eax, 1
                xor     eax, ebp
                sub     ch, 1
                jns     short .no_preflag
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.no_preflag:
                mov     [ebx+24], eax   ; [ebx+$mp3gr_preflag]
                mov     eax, ebp        ; mp3mac_get_n_bits 1
                shl     ebp, 1
                rol     eax, 1
                xor     eax, ebp
                sub     ch, 1
                jns     short .@_without_crc@@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.@_without_crc@@@@@:
                inc     eax
                mov     [ebx+52], eax   ; [ebx+$mp3gr_scalefac_scale]
                mov     eax, ebp        ; mp3mac_get_n_bits 1
                shl     ebp, 1
                rol     eax, 1
                xor     eax, ebp
                sub     ch, 1
                jns     short .@_without_crc@@@@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.@_without_crc@@@@@@: 
                add     eax, 10h        ; table 10h..11h (quad_vlc)
                mov     [ebx+36], eax   ; [ebx+$mp3gr_count1table_select]
                add     ebx, 4928       ; $mp3gr_entrysiz*2
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_src_num_channels]
                jb      .hdr_channel_lop
                pop     ebx
                add     ebx, 2464       ; $mp3gr_entrysiz
                inc     dword [mp3_curr_granule]
                mov     eax, [mp3_curr_granule]
                cmp     eax, [mp3_nb_granules]
                jb      .hdr_granule_lop
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_read_granule
                jz      short .no_rdtsc_supported@
                rdtsc
                add     [rdtsc_read_granule], eax
                adc     [rdtsc_read_granule+4], edx

.no_rdtsc_supported@:
                clc
                retn

.error:
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_read_granule
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_read_granule], eax
                adc     [rdtsc_read_granule+4], edx

.no_rdtsc_supported@@:
                mov     esp, [_@@saved_sp]
                stc
                retn


; =============== S U B R O U T I N E =======================================


mp3_bitstream_append_to_main_data_pool:
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_append_main
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_append_main], eax
                sbb     [rdtsc_append_main+4], edx

.no_rdtsc_supported:
                mov     ecx, [mp3_src_frame_end]
                sub     ecx, esi
                jb      fatalunexpected
                mov     edi, [main_data_pool_wr_ptr]
                lea     eax, [edi+ecx]
                cmp     eax, main_data_pool_wr_ptr
                jbe     short .pool_inrange
                push    ecx
                push    esi
                lea     esi, [edi-200h]
                mov     edi, main_data_pool_start
                mov     ecx, 128
                rep movsd
                pop     esi
                pop     ecx

.pool_inrange:
                mov     eax, edi
                sub     eax, [mp3_main_data_begin]
                rep movsb
                mov     [main_data_pool_wr_ptr], edi
                cmp     eax, main_data_pool_start
                js      short .below_pool_start
                mov     [mp3_bitstream_start], eax
                ; 22/10/2024
		;mov    eax, 0
                mov     esi, [mp3_bitstream_start] ; mp3mac_bitstream_set_position
                ;mov    cl, al
                ;shr    eax, 3
                ;and    cl, 7
                ;add    esi, eax
                call    mp3_recollect_bits
                ;mov    eax, ebp        ; mp3mac_get_n_bits cl
                ;shl    ebp, cl
                ;rol    eax, cl
                ;xor    eax, ebp
                ;sub    ch, cl
                ;jns    short .cont
                ;mov    cl, ch          ; mp3mac_collect_more
                ;add    ch, 10h
                ;rol    ebp, cl
                ;mov    bp, [esi]
                ;add    esi, 2
                ;ror    bp, 8
                ;ror    ebp, cl

.cont:
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_append_main
                jz      short .no_rdtsc_supported@
                rdtsc
                add     [rdtsc_append_main], eax
                adc     [rdtsc_append_main+4], edx

.no_rdtsc_supported@:
                retn

.below_pool_start:
                mov     dword [mp3_samples_output_size], 0
                jmp     short .cont


; =============== S U B R O U T I N E =======================================


mp3_bitstream_read_scalefacs:
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_read_scalefac
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_read_scalefac], eax
                sbb     [rdtsc_read_scalefac+4], edx

.no_rdtsc_supported:
                lea     edi, [ebx+112]  ; [ebx+$mp3gr_scale_factors]
                cmp     dword [mp3_hdr_flag_lsf], 0
                jnz     .body_lsf_nonzero
                mov     eax, [ebx+20]   ; [ebx+$mp3gr_scalefac_compress]
                mov     dx, [mp3_slen_table+eax*2] ; slen[0,1]
                cmp     dword [ebx+44], 2 ; [ebx+$mp3gr_block_type]
                jnz     short .body_lsf_zero_non_type2
                push    ebx
                mov     al, 18
                sub     al, [ebx+48]    ; [ebx+$mp3gr_switch_point]
                mov     bl, al          ; @@get_bl_scalefacs_with_dl_bits 0
                cmp     dl, 0
                jz      short .quickfill

.scalefac_get_lop:
                mov     cl, dl          ; LSB of edx, slen[i]
                mov     eax, ebp        ; mp3mac_get_n_bits cl
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .cont@
                mov     cl, ch          ; mp3mac_collect_more
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.cont@:
                stosb
                dec     bl
                jnz     short .scalefac_get_lop
                jmp     short .skip_quickfill

.quickfill:
                push    ecx
                movzx   ecx, bl
                mov     al, 0           ; NO_INTENSITY_FLAG
                rep stosb
                pop     ecx

.skip_quickfill:
                shr     edx, 8
                mov     bl, 18
                cmp     dl, 0           ; @@get_bl_scalefacs_with_dl_bits 0
                jz      short .quickfill@

.scalefac_get_lop@:
                mov     cl, dl
                mov     eax, ebp        ; mp3mac_get_n_bits cl
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .cont@@
                mov     cl, ch          ; mp3mac_collect_more
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.cont@@:
                stosb
                dec     bl
                jnz     short .scalefac_get_lop@
                jmp     short .skip_quickfill@

.quickfill@:
                push    ecx
                movzx   ecx, bl
                mov     al, 0
                rep stosb
                pop     ecx

.skip_quickfill@:
                pop     ebx
                jmp     .body_lsf_zeropad

.body_lsf_zero_non_type2:
                push    ebx
                ror     edx, 8
                mov     dh, dl          ; slen[0,1,2,3] = slen[0,0,1,1]
                rol     edx, 16
                mov     dl, dh
                mov     al, [ebx+40]    ; [ebx+$mp3gr_scfsi]
                shl     al, 4           ; move to upper 4bit
                mov     byte [_@@scfsi], al
                mov     ebx, 5050506h   ; num[0..3]

.body_lsf_zero_non_type2_lop:
                shl     byte [_@@scfsi], 1
                jb      short .body_lsf_zero_non_type2_copy
                cmp     dl, 0           ; @@get_bl_scalefacs_with_dl_bits 0
                jz      short .quickfill@@

.scalefac_get_lop@@:
                mov     cl, dl
                mov     eax, ebp
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .cont@@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.cont@@@:
                stosb
                dec     bl
                jnz     short .scalefac_get_lop@@
                jmp     short .skip_quickfill@@

.quickfill@@:
                push    ecx
                movzx   ecx, bl
                mov     al, 0
                rep stosb
                pop     ecx

.skip_quickfill@@:
                jmp     short .body_lsf_zero_non_type2_next

.body_lsf_zero_non_type2_copy:
                push    ecx
                mov     eax, esi
                movzx   ecx, bl         ; copy
                lea     esi, [edi-2464] ; [edi-$mp3gr_entrysiz] ; src=granule[0] ; from
                rep movsb               ; prev
                mov     esi, eax
                pop     ecx

.body_lsf_zero_non_type2_next:
                shr     edx, 8          ; dl=next slen
                shr     ebx, 8          ; bl=next numfacs
                jnz     short .body_lsf_zero_non_type2_lop
                pop     ebx
                mov     al, 0
                stosb
                jmp     .body_lsf_done

.body_lsf_nonzero:
                mov     edx, [ebx+14h]  ; [ebx+$mp3gr_scalefac_compress]
                test    dword [mp3_hdr_mode_ext], 1 ; MODE_EXT_I_STEREO
                jz      short .normal_scalefac
                cmp     dword [mp3_curr_channel], 0
                jz      short .normal_scalefac
                add     edx, 512        ; for 2nd channel of intensity_stereo

.normal_scalefac:
                mov     al, [(mp3_lsf_sf_expand_exploded_table+5)+edx*8]
                or      [ebx+24], al    ; [ebx+$mp3gr_preflag]
                push    ebx
                movzx   eax, byte [(mp3_lsf_sf_expand_exploded_table+4)+edx*8]
                cmp     dword [ebx+44], 2 ;  [ebx+$mp3gr_block_type]
                jnz     short .this_tindex1
                mov     ebx, [ebx+48]   ; [ebx+$mp3gr_switch_point]
                lea     eax, [eax+ebx*4+4]

.this_tindex1:
                mov     ebx, [mp3_lsf_nsf_table+eax]
                mov     edx, dword [mp3_lsf_sf_expand_exploded_table+edx*8]

.scalefax_outer_lop:
                cmp     dl, 0           ; @@get_bl_scalefacs_with_dl_bits 1
                jz      short .@quickfil

.@scalefac_get_lop:
                mov     cl, dl
                mov     eax, ebp        ; mp3mac_get_n_bits cl
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .cont
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.cont:
                mov     cl, dl          ; numbits
                mov     ah, al
                inc     ah              ; val+1
                shr     ah, cl          ; bit0=is.max.value
                shl     ah, 7           ; bit7=is.max.value
                or      al, ah          ; apply NO_INTENSITY_FLAG
                stosb
                dec     bl
                jnz     short .@scalefac_get_lop
                jmp     short .@skip_quickfill

.@quickfil:
                push    ecx
                movzx   ecx, bl
                mov     al, 80h
                rep stosb
                pop     ecx

.@skip_quickfill:
                shr     edx, 8
                shr     ebx, 8
                jnz     short .scalefax_outer_lop
                pop     ebx

.body_lsf_zeropad:
                mov     edx, ecx
                lea     ecx, [ebx+152]  ; [ebx+$mp3gr_scale_factors+40]
                sub     ecx, edi
                ;jb     short fatal_scalefactors
		; 21/10/2024
		jb	short fatalunexpected
                mov     al, 0
                rep stosb
                mov     ecx, edx

.body_lsf_done:
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_read_scalefac
                jz      short .no_rdtsc_supported@@@
                rdtsc
                add     [rdtsc_read_scalefac], eax
                adc     [rdtsc_read_scalefac+4], edx

.no_rdtsc_supported@@@:
                retn

		; 21/10/2024
;fatal_scalefactors:
                ;jmp    fatalunexpected

; ---------------------------------------------------------------------------

		; 21/10/2024
fatalunexpected:                       
                div	dword [zero]
hang:
                jmp     short hang


; =============== S U B R O U T I N E =======================================


mp3_get_exponents_from_scale_factors:
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_xlat_scalefac
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_xlat_scalefac], eax
                sbb     [rdtsc_xlat_scalefac+4], edx

.no_rdtsc_supported:
                push    ecx             ; mp3mac_push_bitstream
                push    ebp
                push    esi
                mov     dword [_@@rle_point], 0
                mov     cl, [ebx+52]    ; [ebx+$mp3gr_scalefac_scale]
                mov     edi, mp3_exponents
                xor     edx, edx
                cmp     edx, [ebx+32]   ; [ebx+$mp3gr_long_end]
                jnb     short .long_done
                mov     eax, [mp3_hdr_sample_rate_index]
                imul    eax, 22
                lea     ebp, [mp3_band_size_long+eax]
                mov     eax, [ebx+24]   ; [ebx+$mp3gr_preflag]
                imul    eax, 22
                lea     esi, [mp3_pretab+eax]

.long_lop:
                movzx   eax, byte [ebx+edx+112] ; [ebx+$mp3gr_scale_factors+edx]
                and     al, 7Fh         ; strip NO_INTENSITY_FLAG
                add     al, [esi+edx]
                shl     eax, cl
                neg     eax
                add     eax, [ebx+16]   ; [ebx+$mp3gr_global_gain]
                shl     eax, 16
                mov     al, [ebp+edx+0]
                add     eax, [_@@rle_point]
                mov     word [_@@rle_point], ax
                stosd
                inc     edx
                cmp     edx, [ebx+32]   ; [ebx+$mp3gr_long_end]
                jb      short .long_lop

.long_done:
                mov     edx, [ebx+28]   ; [ebx+$mp3gr_short_start]
                cmp     edx, 13
                jnb     .skip_shorts
                mov     eax, [mp3_hdr_sample_rate_index]
                imul    eax, 13
                lea     ebp, [mp3_band_size_short+eax]
                mov     esi, [ebx+32]   ; [ebx+$mp3gr_long_end]
                mov     eax, [ebx+16]   ; [ebx+$mp3gr_global_gain]
                                        ; IRP nn,0,1,2
                sub     eax, [ebx+68]   ; [ebx+$mp3gr_subblock_gain+nn*4]
                mov     [_@@gains], eax ; [@@gains+nn*4]
                mov     eax, [ebx+16]
                sub     eax, [ebx+72]
                mov     [_@@gains+4], eax ; [@@gains+nn*4]
                mov     eax, [ebx+16]
                sub     eax, [ebx+76]   ; [ebx+$mp3gr_subblock_gain+nn*4]
                mov     [_@@gains+8], eax ; [@@gains+nn*4]

.short_lop:
                movzx   eax, byte [ebx+esi+112] ; [ebx+$mp3gr_scale_factors+esi]
                                        ; IRP nn,0,1,2
                and     al, 7Fh         ; strip NO_INTENSITY_FLAG
                inc     esi
                shl     eax, cl
                neg     eax
                add     eax, [_@@gains] ; [@@gains+nn*4] ; nn=0
                shl     eax, 16
                mov     al, [ebp+edx+0] ; bstab[edx]
                add     eax, [_@@rle_point]
                mov     word [_@@rle_point], ax
                stosd                   ; msw=val, lsw=point
                movzx   eax, byte [ebx+esi+112] ; [ebx+$mp3gr_scalefac_scale]
                and     al, 7Fh
                inc     esi
                shl     eax, cl
                neg     eax
                add     eax, [_@@gains+4] ; [@@gains+nn*4] ; nn = 1
                shl     eax, 16
                mov     al, [ebp+edx+0]
                add     eax, [_@@rle_point]
                mov     word [_@@rle_point], ax
                stosd
                movzx   eax, byte [ebx+esi+70h]
                and     al, 7Fh
                inc     esi
                shl     eax, cl
                neg     eax
                add     eax, [_@@gains+8] ; [@@gains+nn*4] ; nn=2
                shl     eax, 10h
                mov     al, [ebp+edx+0]
                add     eax, [_@@rle_point]
                mov     word [_@@rle_point], ax
                stosd
                inc     edx
                cmp     edx, 13
                jb      short .short_lop

.skip_shorts:
                pop     esi             ; mp3mac_pop_bitstream
                pop     ebp
                pop     ecx
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_xlat_scalefac
                jz      short .no_rdtsc_supported@
                rdtsc
                add     [rdtsc_xlat_scalefac], eax
                adc     [rdtsc_xlat_scalefac+4], edx

.no_rdtsc_supported@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_huffman_decode:
                test    byte [cpuid_flags], 10h ; in: ebx=granule, out: [sb_hybrid..]
                                        ; timelog_start rdtsc_read_huffman
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_read_huffman], eax
                sbb     [rdtsc_read_huffman+4], edx

.no_rdtsc_supported:
                mov	eax, [ebx+8]    ; [ebx+$mp3gr_part2_3_end]
                shr	eax, 3
                add	eax, [mp3_bitstream_start]
                mov	[_@@coarse_end], eax
                xor	edi, edi
                mov	dword [_@@rle_ptr], mp3_exponents
                mov	dword [_@rle_point], 0
                mov	dword [_@@III], 0  ; i=0

.low_freq_lop_i:
                mov     edx, [_@@III] ; for i=0 to 2
                                        ; low frequencies (called big_values)...
                mov     eax, [ebx+edx*4+80] ; [ebx+$mp3gr_region_size+edx*4]
                cmp     eax, 0
                jz      .low_freq_next_i
                mov     [_@@JJJ], eax
                mov     edx, [ebx+edx*4+56] ; [ebx+$mp3gr_table_select+edx*4]
                                        ; select vlc table
                movzx   eax, byte [mp3_huff_data+edx*2] ; get huff.table number
                cmp     eax, 0          ; huff.table
                jnz     short .low_freq_nonzero
                push    ecx
                push    edi
                lea     edi, [ebx+edi*4+160] ; [ebx+$mp3gr_sb_hybrid+edi*4]
                mov     ecx, [_@@JJJ]
                shl     ecx, 1
                xor     eax, eax        ; when huff.table=0,
                                        ; simply set NUM*2 entries to zero
                rep stosd
                pop     edi
                pop     ecx
                add     edi, [_@@JJJ] ; raise index accordingly (by num*2)
                add     edi, [_@@JJJ]
                jmp     .low_freq_next_i

.low_freq_nonzero:
                mov     [_@@vlc_table], eax ; =1..15
                cmp     eax, 14         ; only table 14..15 have linbits
                jnb     .with_linbits  ; so table 0..13 can use faster code...

.low_freq_lop_j_small:
                cmp     esi, [_@@coarse_end] ; loop @@JJJ times..
                ja      .small_near_end

.small_not_end:
                cmp     edi, [_@rle_point] ; @@get_runlength small
                jnb     .rle_fetch_next_small

.rle_back_small:
                mov     edx, [_@@vlc_table] ; get huffcode

.get_child_lop:
                mov     cl, [(huff_tree_buf+2)+edx*4] ; mp3mac_get_huffcode
                                        ; in: edx=table, out: eax=data
                                        ; bits (table size) (-7..-1)
                mov     dx, word [huff_tree_buf+edx*4] ; code (child table)
                mov     eax, ebp        ; mov eax,mp3_col32 ; peek bitstream
                shr     eax, cl
                add     edx, eax
                mov     cl, [(huff_tree_buf+2)+edx*4] ; bits (of entry)
                cmp     cl, 0
                js      short .got_child
                movzx   eax, word [huff_tree_buf+edx*4] ; return data value
                shl     ebp, cl         ; shl mp3_col32,cl ; discard cl bits
                sub     ch, cl          ; sub mp3_colNN,cl
                jns     short .got_done
                mov     cl, ch          ; mp3mac_collect_more
                                        ; mov cl,mp3_colNN ; byte ptr [mp3_numbits_collected]
                add     ch, 16          ; byte ptr [mp3_numbits_collected]
                rol     ebp, cl         ; dword ptr [mp3_collected_data]
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8           ; ror mp3_col16,8 ; endianess
                ror     ebp, cl         ; ror mp3_col32,cl ; dword ptr [mp3_collected_data]
                jmp     short .got_done

.got_child:
                shl     ebp, 9          ; shl mp3_col32,CHILD_BITS
                                        ; discard 7 bits
                                        ; (assuming that parents are always 7bit wide)
                sub     ch, 9
                jns     short .get_child_lop
                mov     cl, ch          ; mp3mac_collect_more
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl
                jmp     short .get_child_lop

.got_done:
                push    eax
                shr     eax, 4          ; x
                jz      short .this_sign ; @@getexpval 0 ; @@getexpval macro has_linbits
                                        ; eax=0 (without sign) ; when x=0
                mov     edx, [_@@rle_val_x_40h]
                mov     eax, [mp3_expval_table+edx+eax*4]
                dec     ch              ; mp3mac_get_bit_to_cy
                                        ; ;jnc short @@this_sign
                                        ; ;neg  eax
                shl     ebp, 1          ; dec mp3_colNN ; shl mp3_col32,1 ; cy=data
                sbb     edx, edx        ; cy=0,1 --> 0,FFFFFFFF
                xor     eax, edx        ; invert if cy was 1 ; get sign (negate if sign=1)
                sub     eax, edx        ; add 1 if cy was 1

.this_sign:
                mov     [ebx+edi*4+160], eax ; [ebx+$mp3gr_sb_hybrid+edi*4+0]
                pop     eax
                and     eax, 0Fh        ; y
                jz      short .this_sign@ ; @@getexpval 0
                mov     edx, [_@@rle_val_x_40h]
                mov     eax, [mp3_expval_table+edx+eax*4]
                dec     ch
                shl     ebp, 1
                sbb     edx, edx
                xor     eax, edx
                sub     eax, edx

.this_sign@:
                mov     [ebx+edi*4+164], eax ; [ebx+$mp3gr_sb_hybrid+edi*4+4]
                add     edi, 2
                dec     dword [_@@JJJ]
                jnz     .low_freq_lop_j_small
                jmp     .low_freq_next_i

.small_near_end:
                mov     eax, esi        ; mp3mac_bitstream_get_position
                sub     eax, [mp3_bitstream_start]
                movsx   edx, ch         ; mp3_colNN
                neg     edx
                lea     eax, [edx+eax*8-16]
                cmp     eax, [ebx+8]    ; [ebx+$mp3gr_part2_3_end]
                jb      .small_not_end
                jmp     .low_freq_next_i

.with_linbits:
                movzx   eax, byte [(mp3_huff_data+1)+edx*2]
                mov     [_@@linbits], eax

.low_freq_lop_j:
                cmp     esi, [_@@coarse_end] ; mp3mac_bitstream_get_position
                                        ; loop @@JJJ times...
                ja      .lop_j_near_end

.small_not_end@:
                cmp     edi, [_@rle_point] ; @@get_runlength small
                jnb     .rle_fetch_next_full

.rle_back_full:
                mov     edx, [_@@vlc_table] ; get huffcode

.get_child_lop@:
                mov     cl, [(huff_tree_buf+2)+edx*4] ; mp3mac_get_huffcode
                                        ; in: edx=table, out: eax=data
                                        ; bits (table size) (-7..-1)
                mov     dx, word [huff_tree_buf+edx*4] ; code (child table)
                mov     eax, ebp
                shr     eax, cl
                add     edx, eax
                mov     cl, [(huff_tree_buf+2)+edx*4] ; bits (of entry)
                cmp     cl, 0
                js      short .got_child@
                movzx   eax, word [huff_tree_buf+edx*4] ; return data value
                shl     ebp, cl         ; discard cl bits
                sub     ch, cl
                jns     short .got_done@
                mov     cl, ch          ; mp3mac_collect_more
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl
                jmp     short .got_done@

.got_child@:
                shl     ebp, 9
                sub     ch, 9
                jns     short .get_child_lop@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl
                jmp     short .get_child_lop@

.got_done@:
                push    eax
                shr     eax, 4          ; x
                jz      short .@this_sign ; @@getexpval 1
                mov     edx, [_@@rle_val]
                cmp     eax, 15
                jb      short .small    ; when x=1..14
                mov     cl, byte [_@@linbits] ; =0..13 ; when x=15, with linbits
                mov     eax, ebp        ; mp3mac_get_n_bits cl ; value = 0..1FFFh
                shl     ebp, cl         ; mp3mac_collect_more
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .cont
                mov     cl, ch          ; mp3mac_collect_more
                add     ch, 16
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.cont:
                mov     cl, dl          ; exponent.lsb
                and     cl, 3           ; exponent.lsb
                shr     edx, 2          ; exponent.msb
                lea     eax, [eax*4+60] ; (value+15)*4
                or      al, cl          ; exponent.lsb+(value+15)*4
                mov     cl, [mp3_table_4_3_exp+eax]
                mov     eax, [mp3_table_4_3_value+eax*4]
                sub     cl, dl          ; sub exponent.msb
                shr     eax, cl
                cmp     cl, 31
                jbe     short .get_sign
                xor     eax, eax
                jmp     short .get_sign

.small:
                shl     edx, 6          ; shl edx,4+2 ; mul16*4 ; when x<15 aka x=1..14
                mov     eax, [mp3_expval_table+edx+eax*4]

.get_sign:
                dec     ch              ; mp3mac_get_bit_to_cy
                shl     ebp, 1
                sbb     edx, edx        ; get sign (negate if sign=1)
                xor     eax, edx
                sub     eax, edx

.@this_sign:
                mov     [ebx+edi*4+160], eax ; [ebx+$mp3gr_sb_hybrid+edi*4+0]
                pop     eax
                and     eax, 0Fh        ; y
                jz      short .@this_sign@ ; @@getexpval 1
                mov     edx, [_@@rle_val]
                cmp     eax, 0Fh
                jb      short .small@
                mov     cl, byte [_@@linbits]
                mov     eax, ebp        ; mp3mac_get_n_bits cl
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .cont@
                mov     cl, ch          ; mp3mac_collect_more
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.cont@:
                mov     cl, dl
                and     cl, 3
                shr     edx, 2
                lea     eax, [eax*4+60]
                or      al, cl
                mov     cl, [mp3_table_4_3_exp+eax]
                mov     eax, [mp3_table_4_3_value+eax*4]
                sub     cl, dl
                shr     eax, cl
                cmp     cl, 31
                jbe     short .get_sign@
                xor     eax, eax
                jmp     short .get_sign@

.small@:
                shl     edx, 6
                mov     eax, [mp3_expval_table+edx+eax*4]

.get_sign@:                           
                dec     ch              ; dec mp3_colNN
                shl     ebp, 1          ; shl mp3_col32,1 ; cy=data
                sbb     edx, edx        ; cy=0,1 --> 0,FFFFFFFF
                xor     eax, edx        ; invert if cy was 1
                sub     eax, edx        ; add 1 if cy was 1

.@this_sign@:
                mov	[ebx+edi*4+164], eax ; [ebx+$mp3gr_sb_hybrid+edi*4+4]
                add	edi, 2          ; next j
                dec	dword [_@@JJJ]
                jnz	.low_freq_lop_j

.low_freq_next_i:
                inc	dword [_@@III]	; next i
                cmp	dword [_@@III], 3
                jb	.low_freq_lop_i
                cmp	edi, 572	; aka 576-4 ; skip if less than 4 entries left
                ja	.high_freq_done

.high_freq_lop:
                cmp     esi, [_@@coarse_end]
                jbe     short .high_freq_inrange
                mov     eax, esi        ; mp3mac_bitstream_get_position
                sub     eax, [mp3_bitstream_start]
                movsx   edx, ch         ; mp3_colNN
                neg     edx
                lea     eax, [edx+eax*8-16]
                cmp     eax, [ebx+8]    ; [ebx+$mp3gr_part2_3_end] ; check end
                jb      short .high_freq_inrange ; not yet end
                jz      .high_freq_done ; okay, exact end
                cmp     edi, 4
                jb      short .high_freq_cannot_stepback
                sub     edi, 4          ; stepback, s_index-4 ; dst stepback

.high_freq_cannot_stepback:
                jmp     .high_freq_done

.high_freq_inrange:
                mov     edx, [ebx+24h]  ; [ebx+$mp3gr_count1table_select]
                                        ; get huffcode (quad_vlc)

.get_child_lop@@:
                mov     cl, [(huff_tree_buf+2)+edx*4] ; mp3mac_get_huffcode
                mov     dx, word [huff_tree_buf+edx*4]
                mov     eax, ebp
                shr     eax, cl
                add     edx, eax
                mov     cl, [(huff_tree_buf+2)+edx*4]
                cmp     cl, 0
                js      short .got_child@@
                movzx   eax, word [huff_tree_buf+edx*4]
                shl     ebp, cl
                sub     ch, cl
                jns     short .got_done@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl
                jmp     short .got_done@@

.got_child@@:
                shl     ebp, 9
                sub     ch, 9
                jns     short .get_child_lop@@
                mov     cl, ch
                add     ch, 10h
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl
                jmp     short .get_child_lop@@

.got_done@@:
                mov     dl, al          ; flags
                shl     dl, 4           ; flags, to upper 4bit
                mov     dh, 4           ; lopcount

.high_freq_flag_lop:
                xor     eax, eax
                shl     dl, 1           ; flag
                jnb     short .high_freq_flag_this
                cmp     edi, [_@rle_point] ; @@get_runlength quads
                jnb     .rle_fetch_next_quads

.rle_back_quads:
                mov     eax, [_@@rle_val]
                mov     eax, [mp3_exp_table+eax*4] ; xlat and get sign
                dec     ch              ; mp3mac_get_bit_to_cy
                shl     ebp, 1
                jnb     short .high_freq_flag_this ;
                                        ; sbb edx, edx ; cy=0,1 --> 0,FFFFFFFF
                                        ; xor eax, edx ; invert if cy was 1
                                        ; sub eax, edx ; add 1 if cy was 1
                neg     eax

.high_freq_flag_this:
                mov     [ebx+edi*4+160], eax ; [ebx+$mp3gr_sb_hybrid+edi*4+0]
                inc     edi
                dec     dh
                jnz     short .high_freq_flag_lop
                cmp     edi, 572        ; aka 576-4 ; loop while space for another 4 values
                jbe     .high_freq_lop

.high_freq_done:
                mov     [ebx+92], edi   ; [ebx+$mp3gr_num_nonzero_hybrids]
                push    ecx
                mov     ecx, 576        ; end
                sub     ecx, edi        ; remain = end-curr
                                        ; zeropad remaining entries (can be 0 or 2 dwords,
                                        ; or more. If above loop was aborted)
                lea     edi, [ebx+edi*4+160] ; [ebx+$mp3gr_sb_hybrid+edi*4]
                xor     eax, eax
                rep stosd
                pop     ecx
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_read_huffman
                jz      short .no_rdtsc_supported@
                rdtsc
                add     [rdtsc_read_huffman], eax
                adc     [rdtsc_read_huffman+4], edx

.no_rdtsc_supported@:
                clc                     ; out: cy=0=okay
                retn

.rle_fetch_next_small:
                mov     eax, [_@@rle_ptr] ; @@next_runlength small
                add     dword [_@@rle_ptr], 4
                mov     eax, [eax]
                cmp     di, ax
                jnb     short .rle_fetch_next_small
                mov     word [_@rle_point], ax
                shr     eax, 16
                mov     [_@@rle_val], eax
                shl     eax, 6
                mov     [_@@rle_val_x_40h], eax
                jmp     .rle_back_small

.rle_fetch_next_full:
                mov     eax, [_@@rle_ptr] ; @@next_runlength full
                add	dword [_@@rle_ptr], 4
                mov     eax, [eax]
                cmp     di, ax
                jnb     short .rle_fetch_next_full
                mov     word [_@rle_point], ax
                shr     eax, 16
                mov     [_@@rle_val], eax
                shl     eax, 6
                mov     [_@@rle_val_x_40h], eax
                jmp     .rle_back_full

.rle_fetch_next_quads:
                mov	eax, [_@@rle_ptr] ; msw=val, lsw=point
                add	dword [_@@rle_ptr], 4 ; 2+2
                mov	eax, [eax]
                cmp	di, ax          ; needed if rle fetching was skipped
                jnb	short .rle_fetch_next_quads
                mov	word [_@rle_point], ax
                shr	eax, 16
                mov	[_@@rle_val], eax
                jmp	.rle_back_quads

.lop_j_near_end:
                mov     eax, esi
                sub     eax, [mp3_bitstream_start]
                movsx   edx, ch
                neg     edx
                lea     eax, [edx+eax*8-16]
                cmp     eax, [ebx+8]
                jb      .small_not_end@
                jmp     .low_freq_next_i


; =============== S U B R O U T I N E =======================================


mp3_compute_stereo:
                cmp	dword [mp3_output_num_channels], 2 ; in: ebx=granule(s)
                jnz	short .no_stereo
                cmp	dword [mp3_hdr_mode_ext], 2 ; MODE_EXT_MS_STEREO
                                        ; only MS stereo
                jz	short mp3_compute_ms_stereo
                test	dword [mp3_hdr_mode_ext], 1 ; MODE_EXT_I_STEREO
                                        ; intensity stereo (optionally with MS stereo)
                jnz	short mp3_compute_i_stereo

.no_stereo:
                retn

mp3_compute_ms_stereo:
                test    byte [cpuid_flags], 10h ; ms_stereo is most commonly used
                                        ; the 1/sqrt(2) normalization factor is included
                                        ; in the global gain
                jz      short .no_rdtsc_supported ; timelog_start rdtsc_ms_stereo
                rdtsc
                sub     [rdtsc_ms_stereo], eax
                sbb     [rdtsc_ms_stereo+4], edx

.no_rdtsc_supported:
                lea     edi, [ebx+5088] ; [ebx+$mp3gr_sb_hybrid+$mp3gr_entrysiz*2]
                                        ; for ch1 (2nd channel)
                mov     ecx, [ebx+92]   ; [ebx+$mp3gr_num_nonzero_hybrids] ; ch0
                mov     eax, [ebx+5020] ; [ebx+$mp3gr_num_nonzero_hybrids+($mp3gr_entrysiz*2)] ; ch1
                cmp     ecx, eax
                ja      short .this_len
                mov     ecx, eax

.this_len:
                jecxz   .ms_stereo_done
                mov     [ebx+92], ecx   ; [ebx+$mp3gr_num_nonzero_hybrids] ; ch0
                mov     [ebx+5020], ecx ; [ebx+$mp3gr_num_nonzero_hybrids+($mp3gr_entrysiz*2)] ; ch1

.ms_stereo_lop:
                mov     eax, [edi-4928] ; for i=0 to 576-1
                                        ; [edi+@@ch0]
                                        ; @@ch0 equ (-$mp3gr_entrysiz*2) ; granule for channel=0
                                        ; tmp0 = granule.ch0.sb_hybrid[i]
                mov     edx, [edi]      ; @@ch1 equ 0 ; granule for channel=1
                                        ; [edi+@@ch1]
                                        ; tmp1 = granule.ch1.sb_hybrid[i]
                sub     eax, edx        ; tmp0 - tmp1
                lea     edx, [eax+edx*2] ; tmp0 + tmp1
                mov     [edi-4928], edx ; [edi+@@ch0]
                                        ; granule.ch0.sb_hybrid[i] = tmp0 + tmp1
                stosd                   ; [edi+@@ch1]
                                        ; granule.ch1.sb_hybrid[i] = tmp0 - tmp1
                dec     ecx
                jnz     short .ms_stereo_lop

.ms_stereo_done:
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_ms_stereo
                jz      short .no_rdtsc_supported@
                rdtsc
                add     [rdtsc_ms_stereo], eax
                adc     [rdtsc_ms_stereo+4], edx

.no_rdtsc_supported@:
                retn

mp3_compute_i_stereo:
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_i_stereo
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_i_stereo], eax
                sbb     [rdtsc_i_stereo+4], edx

.no_rdtsc_supported@@@:
                mov     dword [ebx+92], 576 ; ch0
                                        ; [ebx+$mp3gr_num_nonzero_hybrids]
                mov     dword [ebx+5020], 576 ; ch1
                                        ; [ebx+$mp3gr_num_nonzero_hybrids+($mp3gr_entrysiz*2)]
                mov     eax, [ebx+32]   ; [ebx+$mp3gr_long_end]
                mov     [_@@n_long_sfb], eax
                mov     eax, 13         ; 39/3
                sub     eax, [ebx+28]   ; [ebx+$mp3gr_short_start]
                lea     eax, [eax+eax*2] ; mul3
                mov     [_@@n_short_sfb], eax
                add     eax, [_@@n_long_sfb]
                mov     [_@@n_sfb], eax ;
                                        ; n_sfb = gr->n_long_sfb + gr->n_short_sfb;
                cmp     byte [_@@n_short_sfb], 0
                mov     eax, 1
                jz      short .without_short
                mov     eax, 3          ; max_blocks = gr->n_short_sfb ? 3 : 1;

.without_short:
                mov     [_@@max_blocks], eax
                mov     edi, _@@sfb_array
                mov     eax, [mp3_hdr_sample_rate_index] ; bstab
                imul    eax, 22
                lea     esi, [mp3_band_size_long+eax]
                mov     ecx, [_@@n_long_sfb]
                rep movsb
                mov     eax, [mp3_hdr_sample_rate_index]
                imul    eax, 13
                lea     esi, [mp3_band_size_short+eax] ; merge lieff-style
                mov     ecx, [_@@n_short_sfb]
                jecxz   .make_sfb_done ; doing that here is a bit slow,
                                        ; it would be better to pre-compute
                                        ; all merged-combinations
                add     esi, [ebx+28]   ; [ebx+$mp3gr_short_start]

.make_sfb_lop:
                lodsb
                stosb
                stosb
                stosb
                sub     ecx, 3
                jnz     short .make_sfb_lop

.make_sfb_done:
                call    _@@find_top_bands ;
                                        ; L3_stereo_top_band(left+576,gr->sfbtab,n_sfb,max_band);
                cmp     byte [_@@n_long_sfb], 0
                jz      short .without_long
                mov     eax, dword [_@@max_bands]
                cmp     ah, al          ; if (gr->n_long_sfb)
                jg      short .not_max1 ; max_band[0] = max_band[1] = max_band[2] = MINIMP3_MAX
                                        ; (MINIMP3_MAX(max_band[0], max_band[1]), max_band[2]);
                mov     ah, al

.not_max1:
                shr     eax, 8
                cmp     ah, al
                jg      short .not_max2
                mov     ah, al

.not_max2:
                mov     al, ah
                shl     eax, 8
                mov     al, ah
                mov     dword [_@@max_bands], eax

.without_long:
                xor     ebp, ebp        ; blk

.adjust_last_prev_lop:
                mov     edx, [_@@n_sfb]
                sub     edx, [_@@max_blocks] ; itop = n_sfb - max_blocks + blk
                add     edx, ebp
                mov     ecx, edx
                sub     ecx, [_@@max_blocks] ; prev = itop - max_blocks;
                mov     eax, [mp3_hdr_flag_lsf]
                lea     eax, [eax+eax*2] ; 0,1 --> 0,3
                                        ; default_pos = HDR_TEST_MPEG1(hdr) ? 3
                xor     al, 3           ; 0,3 --> 3,0
                cmp     cl, [ss:_@@max_bands+ebp]
                jle     short .use_default_pos ; ist_pos[itop] = max_band[blk] >=
                                        ; prev ? default_pos : ist_pos[prev]
                mov     al, [ebx+ecx+5040] ; [ebx+@@right+$mp3gr_scale_factors+ecx]

.use_default_pos:
                mov     [ebx+edx+5040], al ; [ebx+@@right+$mp3gr_scale_factors+edx]
                inc     ebp             ; blk
                cmp     ebp, [_@@max_blocks]
                jb      short .adjust_last_prev_lop
                call    _@@apply_i_stereo
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_i_stereo
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_i_stereo], eax
                adc     [rdtsc_i_stereo+4], edx

.no_rdtsc_supported@@@@:
                retn


; =============== S U B R O U T I N E =======================================


_@@find_top_bands:
                mov     dword [_@@max_bands], 0FFFFFFh ; set maxband[0..2]=(-1)
                lea     esi, [ebx+5088] ; [ebx+@@right+$mp3gr_sb_hybrid]
                xor     edx, edx

.find_top_lop_iii:                    
                xor     ecx, ecx        ; for (i = 0; i < nbands; i++)

.find_top_lop_kkk:                    
                mov     eax, [esi+ecx*4] ; for (k = 0; k < sfb[i]; k += 2)
                or      eax, [esi+ecx*4+4]
                jnz     short .found_nonzero
                add     ecx, 2
                cmp     cl, [_@@sfb_array+edx]
                jb      short .find_top_lop_kkk
                jmp     short .find_top_next

.found_nonzero:
                mov     eax, edx
                div     byte [_@@const_3]
                movzx   eax, ah         ; remainder (mod 3)
                mov     [_@@max_bands+eax], dl ; max_bands[0..2]=i

.find_top_next:
                movzx   eax, byte [_@@sfb_array+edx]
                lea     esi, [esi+eax*4]
                inc     edx             ; next
                cmp     edx, [_@@n_sfb]
                jb      short .find_top_lop_iii
                retn

; =============== S U B R O U T I N E =======================================


_@@apply_i_stereo:
                mov     eax, mp3_is_table_normal
                mov     ecx, 7
                cmp     dword [mp3_hdr_flag_lsf], 0
                jz      short .this_lsf
                mov     eax, [ebx+4948] ; [ebx+@@right+$mp3gr_scalefac_compress]
                and     eax, 1          ; bit0
                test    dword [mp3_hdr_mode_ext], 2 ; MODE_EXT_MS_STEREO
                jz      short .no_ms
                or      eax, 2          ; bit1=mul_1.414

.no_ms:
                shl     eax, 9          ; N*40h*2*4
                add     eax, mp3_is_table_lsf
                mov     ecx, 64         ; max (must be below NO_INTENSITY_FLAG)

.this_lsf:
                mov     [_@@max_pos], ecx ; 7 or 64
                mov     [_@@is_tab], eax ; table
                lea     esi, [ebx+160]  ; [ebx+$mp3gr_sb_hybrid]
                xor     ecx, ecx        ; iii ; for (i = 0; sfb[i]; i++)

.apply_lop_i:
                movzx   ebp, byte [_@@sfb_array+ecx] ; if ((int)i > max_band[i % 3]
                                        ; && ipos < max_pos)
                mov     eax, ecx
                div     byte [_@@const_3] ; max_band[i % 3]
                movzx   eax, ah         ; remainder (mod 3)
                cmp     cl, [_@@max_bands+eax] ; iii,max_bands[0..2];
                jle     short .apply_ms_stereo
                movzx   edi, byte [ebx+ecx+5040] ; [ebx+@@right+$mp3gr_scale_factors+ecx]
                                        ; @@right = $mp3gr_entrysiz*2 = 4928
                                        ; $mp3gr_scale_factors = 112
                cmp     edi, [_@@max_pos] ; check ipos
                jnb     short .apply_ms_stereo
                shl     edi, 3          ; mul 2*4
                add     edi, [_@@is_tab]

.apply_pan_lop:
                mov     eax, [esi]      ; tmp = granule.ch0.sb_hybrid
                shl     eax, 2
                imul    dword [edi+4] ; v1
                mov     [esi+4928], edx ; [esi+@@right]
                                        ; granule.ch1.sb_hybrid = tmp*v1
                mov     eax, [esi]      ; tmp = granule.ch0.sb_hybrid
                shl     eax, 2
                imul    dword [edi] ; v0
                mov     [esi], edx      ; granule.ch0.sb_hybrid = tmp*v0
                add     esi, 4
                dec     ebp
                jnz     short .apply_pan_lop
                jmp     short .apply_next

.apply_ms_stereo:
                test	dword [mp3_hdr_mode_ext], 2 ; MODE_EXT_MS_STEREO
                jz	short .apply_none

.ms_stereo_lop:
                mov     eax, [esi]      ; tmp0 = granule.ch0.sb_hybrid[i]
                mov     edx, [esi+4928] ; [esi+@@right]
                                        ; tmp1 = granule.ch1.sb_hybrid[i]
                sub     eax, edx        ; tmp0 - tmp1
                lea     edx, [eax+edx*2] ; tmp0 + tmp1
                mov     [esi], edx      ; granule.ch0.sb_hybrid[i] = tmp0 + tmp1
                mov     [esi+4928], eax ; [esi+@@right]
                                        ; granule.ch1.sb_hybrid[i] = tmp0 - tmp1
                add     esi, 4
                dec     ebp
                jnz     short .ms_stereo_lop
                jmp     short .apply_next

.apply_none:
                lea     esi, [esi+ebp*4] ; skip, keep unchanged

.apply_next:
                inc     ecx             ; iii
                cmp     ecx, [_@@n_sfb]
                jb      .apply_lop_i   ; next
                retn

; =============== S U B R O U T I N E =======================================


mp3_reorder_block:
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_reorder
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_reorder], eax
                sbb     [rdtsc_reorder+4], edx

.no_rdtsc_supported:
                cmp	byte [ebx+44], 2 ; ebx+$mp3gr_block_type] ; only for type 2
                jnz	short .no_reorder
                lea	esi, [ebx+160]  ; [ebx+$mp3gr_sb_hybrid] ; ptr+0
                cmp	byte [ebx+48], 0 ; [ebx+$mp3gr_switch_point]
                jz	short .this_src
                add	esi, 144        ; 36*4 ; ptr+36*4
                cmp	dword [mp3_hdr_sample_rate_index], 8
                jnz	short .this_src
                add	esi, 48         ; 12*4 ; additionally to above 36*4 ; ptr+48*4

.this_src:
                mov     edx, [ebx+28]   ; [ebx+$mp3gr_short_start] ; can be 13
                cmp     edx, 13
                jnb     short .no_reorder
                mov     dword [ebx+92], 576 ; [ebx+$mp3gr_num_nonzero_hybrids]

.outer_lop:
                mov     eax, [mp3_hdr_sample_rate_index]
                imul    eax, 13         ; X*13
                movzx   ecx, byte [mp3_band_size_short+eax+edx] ; [X*13+Y]
                mov     edi, _@@tmp
                pusha
                mov     edx, ecx        ; step=len (4..44) ; copy LEN*3 dwords to tmp

.inner_lop:
                mov     eax, [esi]
                stosd
                mov     eax, [esi+edx*4] ; copy 3 dwords
                stosd
                mov     eax, [esi+edx*8]
                stosd
                add     esi, 4
                loop    .inner_lop
                popa
                lea     ecx, [ecx+ecx*2] ; len*3
                xchg    esi, edi        ; copy LEN*3 dwords back from tmp
                rep movsd
                xchg    esi, edi
                inc     edx
                cmp     edx, 13
                jb      short .outer_lop ; next

.no_reorder:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@ ; timelog_end rdtsc_reorder
                rdtsc
                add     [rdtsc_reorder], eax
                adc     [rdtsc_reorder+4], edx

.no_rdtsc_supported@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_compute_antialias:
                test    byte [cpuid_flags], 10h ; in: ebx=granule
                jz      short .no_rdtsc_supported ; timelog_start rdtsc_antialias
                rdtsc
                sub     [rdtsc_antialias], eax
                sbb     [rdtsc_antialias+4], edx

.no_rdtsc_supported:
                mov     eax, [ebx+92]   ; [ebx+$mp3gr_num_nonzero_hybrids]
                add     eax, 8          ; 9-1 ; 0..576+8
                xor     edx, edx
                mov     ecx, 9
                div     ecx             ; (num/9) ; 0..64
                mov     [ebx+60h], eax
                shr     eax, 1          ; (num/18) ; 0..32
                jz      .no_antialias  ; 0 (when num/9 = 0..1)
                mov     ecx, eax        ; 1..32
                shr     eax, 5          ; 0..1
                sub     ecx, eax        ; 1..31 ; len excluding zeropadding
                cmp     byte [ebx+44], 2 ; [ebx+$mp3gr_block_type]
                jnz     short .this_len ; antialias only "long" bands
                cmp     byte [ebx+48], 0 ; [ebx+$mp3gr_switch_point]
                jz      .no_antialias
                mov     ecx, 1          ; check this for 8000Hz case

.this_len:
                lea     eax, [1+ecx*2]
                cmp     [ebx+96], eax   ; [ebx+$mp3gr_num_nonzero_hybrids_div9]
                ja      short .is_bigger
                mov     [ebx+96], eax   ; opdate highest
                                        ; (nonzero required for l3-si_huff.bit)

.is_bigger:
                push    ebx
                lea     ebx, [ebx+160]  ; [ebx+$mp3gr_sb_hybrid]

.lop:
                add     ebx, 72         ; 18*4
                mov     esi, [ebx-4]    ; IRP nn,0,1,2,3,4,5,6,7 ; INT_AA(nn=0..7)
                mov     edi, [ebx]      ; @@def_csa macro nn,cs,ca
                                        ;   mp3_csa_&nn&_cs equ cs
                                        ;   mp3_csa_&nn&_ca equ ca
                                        ;  endm
                                        ; constants for mp3_csa_table
                shl     esi, 2          ; tmp0 = ptr[-nn-1]*4
                shl     edi, 2          ; tmp1 = ptr[+nn]*4
                lea     eax, [esi+edi]  ; tmp2 = tmp0+tmp1
                mov     ebp, 36E12A03h  ; @@def_csa 0,36E12A03h,-20ED7F9Ah  ;-0.6
                                        ; mp3_csa_&nn&_cs
                imul    ebp             ; tmp2 = (tmp2*csa[0])
                mov     ebp, edx
                mov     eax, -57CEA99Dh ; mp3_csa_&nn&_ca-mp3_csa_&nn&_cs
                imul    esi             ; tmp0 = (tmp2+(tmp0*csa[3]))
                add     edx, ebp
                mov     [ebx], edx      ; [ebx+(nn)*4]
                mov     eax, 15F3AA69h  ; mp3_csa_&nn&_ca+mp3_csa_&nn&_cs
                imul    edi             ; tmp1 = (tmp2-(tmp1*csa[2]))
                sub     ebp, edx
                mov     [ebx-4], ebp    ; [ebx-(nn+1)*4]
                mov     esi, [ebx-8]
                mov     edi, [ebx+4]
                shl     esi, 2
                shl     edi, 2
                lea     eax, [esi+edi]
                mov     ebp, 386E75FDh  ; @@def_csa 1,386E75FDh,-1E30DB48h  ;-0.535
                imul    ebp
                mov     ebp, edx
                mov     eax, -569F5145h
                imul    esi
                add     edx, ebp
                mov     [ebx+4], edx    ; [ebx+(nn)*4]
                mov     eax, 1A3D9AB5h
                imul    edi
                sub     ebp, edx
                mov     [ebx-8], ebp    ; [ebx-(nn+1)*4]
                mov     esi, [ebx-12]
                mov     edi, [ebx+8]
                shl     esi, 2
                shl     edi, 2
                lea     eax, [esi+edi]
                mov     ebp, 3CC6B73Eh  ;  @@def_csa 2,3CC6B73Eh,-140E604Fh  ;-0.33
                imul    ebp
                mov     ebp, edx
                mov     eax, -50D5178Dh
                imul    esi
                add     edx, ebp
                mov     [ebx+8], edx    ; [ebx+(nn)*4]
                mov     eax, 28B856EFh
                imul    edi
                sub     ebp, edx
                mov     [ebx-12], ebp   ; [ebx-(nn+1)*4]
                mov     esi, [ebx-16]
                mov     edi, [ebx+12]
                shl     esi, 2
                shl     edi, 2
                lea     eax, [esi+edi]
                mov     ebp, 3EEEA055h  ; @@def_csa 3,3EEEA055h,-0BA47742h  ;-0.185
                imul    ebp
                mov     ebp, edx
                mov     eax, -4A931797h
                imul    esi
                add     edx, ebp
                mov     [ebx+12], edx   ; [ebx+(nn)*4]
                mov     eax, 334A2913h
                imul    edi
                sub     ebp, edx
                mov     [ebx-16], ebp   ; [ebx-(nn+1)*4]
                mov     esi, [ebx-20]   ; ebx-(nn+1)*4] ; tmp0 = ptr[-nn-1]
                mov     edi, [ebx+16]   ; [ebx+(nn)*4] ; tmp1 = ptr[+nn]
                shl     esi, 2
                shl     edi, 2
                lea     eax, [esi+edi]  ; tmp2 = tmp0+tmp1
                mov     ebp, 3FB6905Ch  ; @@def_csa 4,3FB6905Ch,-060D80E9h  ;-0.095
                imul    ebp             ; tmp2 = (tmp2*csa[0])
                mov     ebp, edx
                mov     eax, -45C41145h
                imul    esi             ; tmp0 = (tmp2+(tmp0*csa[3]))
                add     edx, ebp
                mov     [ebx+16], edx   ; [ebx+(nn)*4]
                mov     eax, 39A90F73h
                imul    edi             ; tmp1 = (tmp2-(tmp1*csa[2]))
                sub     ebp, edx
                mov     [ebx-20], ebp   ; [ebx-(nn+1)*4]
                mov     esi, [ebx-24]
                mov     edi, [ebx+20]
                shl     esi, 2
                shl     edi, 2
                lea     eax, [esi+edi]
                mov     ebp, 3FF23F21h  ; @@def_csa 5,3FF23F21h,-029F2E1Bh  ;-0.041
                imul    ebp
                mov     ebp, edx
                mov     eax, -42916D3Ch
                imul    esi
                add     edx, ebp
                mov     [ebx+20], edx   ; [ebx+(nn)*4]
                mov     eax, 3D531106h
                imul    edi
                sub     ebp, edx
                mov     [ebx-24], ebp   ; [ebx-(nn+1)*4]
                mov     esi, [ebx-28]
                mov     edi, [ebx+24]
                shl     esi, 2
                shl     edi, 2
                lea     eax, [esi+edi]
                mov     ebp, 3FFE5932h  ; @@def_csa 6,3FFE5932h,-00E8A11Ch  ;-0.0142
                imul    ebp
                mov     ebp, edx
                mov     eax, -40E6FA4Eh
                imul    esi
                add     edx, ebp
                mov     [ebx+24], edx   ; [ebx+(nn)*4]
                mov     eax, 3F15B816h
                imul    edi
                sub     ebp, edx
                mov     [ebx-28], ebp   ; [ebx-(nn+1)*4]
                mov     esi, [ebx-32]
                mov     edi, [ebx+28]
                shl     esi, 2
                shl     edi, 2
                lea     eax, [esi+edi]
                mov     ebp, 3FFFE34Bh  ; @@def_csa 7,3FFFE34Bh,-003C9ED1h  ;-0.0037
                imul    ebp
                mov     ebp, edx
                mov     eax, -403C821Ch
                imul    esi
                add     edx, ebp
                mov     [ebx+28], edx   ; [ebx+(nn)*4]
                mov     eax, 3FC3447Ah
                imul    edi
                sub     ebp, edx
                mov     [ebx-32], ebp   ; [ebx-(nn+1)*4]
                dec     ecx
                jnz     .lop
                pop     ebx

.no_antialias:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                add     [rdtsc_antialias], eax
                adc     [rdtsc_antialias+4], edx

.no_rdtsc_supported@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_imdct36:
                mov     eax, [esi]      ; in: esi=src (sb_hybrid)
                                        ; in: edi=dst (sb_samples)
                                        ; in: ebx=buf (mdct_buf)
                                        ; in: ebp=win (mdct_win)
                                        ;
                                        ; [esi+0*4]
                mov     edx, [esi+4]    ; IRP i,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17
                add     eax, edx        ; IF i AND 1 (*) ; mov edx,[esi+i*4] ; val[i]
                                        ;  add val[i-1]
                mov     [esi+4], eax    ;  IF i GT 1
                                        ;   add  ecx,eax ; add val[i-2]
                                        ;   mov  [esi+(i)*4],ecx
                                        ;  ELSE
                                        ;   mov  [esi+(i)*4],eax
                mov     ecx, eax        ;  memorize as val[i-2]
                mov     eax, [esi+8]    ; ELSE (*) ; [esi+i*4] ; val[i]
                add     edx, eax        ;  add val[i-1]
                mov     [esi+8], edx    ; [esi+(i)*4
                mov     edx, [esi+12]
                add     eax, edx
                add     ecx, eax
                mov     [esi+12], ecx
                mov     ecx, eax
                mov     eax, [esi+16]
                add     edx, eax
                mov     [esi+16], edx
                mov     edx, [esi+20]
                add     eax, edx
                add     ecx, eax
                mov     [esi+20], ecx
                mov     ecx, eax
                mov     eax, [esi+24]
                add     edx, eax
                mov     [esi+24], edx
                mov     edx, [esi+28]
                add     eax, edx
                add     ecx, eax
                mov     [esi+28], ecx
                mov     ecx, eax
                mov     eax, [esi+32]
                add     edx, eax
                mov     [esi+32], edx
                mov     edx, [esi+36]
                add     eax, edx
                add     ecx, eax
                mov     [esi+36], ecx
                mov     ecx, eax
                mov     eax, [esi+40]
                add     edx, eax
                mov     [esi+40], edx
                mov     edx, [esi+44]
                add     eax, edx
                add     ecx, eax
                mov     [esi+44], ecx
                mov     ecx, eax
                mov     eax, [esi+48]
                add     edx, eax
                mov     [esi+48], edx
                mov     edx, [esi+52]
                add     eax, edx
                add     ecx, eax
                mov     [esi+52], ecx
                mov     ecx, eax
                mov     eax, [esi+56]
                add     edx, eax
                mov     [esi+56], edx
                mov     edx, [esi+60]
                add     eax, edx
                add     ecx, eax
                mov     [esi+60], ecx
                mov     ecx, eax
                mov     eax, [esi+64]
                add     edx, eax
                mov     [esi+64], edx
                mov     edx, [esi+68]
                add     eax, edx
                add     ecx, eax
                mov     [esi+68], ecx
                mov     ecx, eax
                push    ebx
                push    ebp
                push    edi
                mov     ecx, [esi]      ; IRP j,0,1
                mov     ebx, [esi+48]   ; t1 = [esi+(0*2+j)*4], t0 = [esi+(6*2+j)*4]
                mov     edi, [esi+32]   ; t2 = [esi+(4*2+j)*4]
                add     edi, [esi+64]   ; + [esi+(8*2+j)*4]
                sub     edi, [esi+16]   ; - [esi+(2*2+j)*4]
                lea     ebp, [ebx+ecx*2] ; t2 = src[4*2+j] + src[8*2+j] - src[2*2+j]
                                        ; t3 = [t1*2+t0]
                sar     ebp, 1          ; sar @@t3,1
                sub     ecx, ebx        ; sub @@t1,@@t0
                mov     eax, ecx        ; @@SUM [@@tmp+(16+j)*4],@@t1,add,@@t2
                add     eax, edi
                mov     [_@@@tmp+40h], eax ; [@@tmp+(16+j)*4]
                sar     edi, 1          ; sar @@t2,1
                mov     eax, ecx        ; @@SUM [@@tmp+(6+j)*4],@@t1,sub,@@t2
                sub     eax, edi
                mov     [_@@@tmp+18h], eax ; [@@tmp+(6+j)*4]
                mov     eax, [esi+16]   ; [esi+(4*2+j)*4]
                add     eax, [esi+32]   ; [esi+(2*2+j)*4]
                shl     eax, 1
                mov     edx, 7847D90Ah  ; C2
                imul    edx
                mov     ebx, edx
                mov     eax, [esi+32]
                sub     eax, [esi+64]
                mov     edx, 0D38BCB04h ; negC8
                imul    edx
                mov     ecx, edx
                mov     eax, [esi+16]
                add     eax, [esi+64]
                shl     eax, 1
                mov     edx, 9DF24175h  ; negC4
                imul    edx
                mov     eax, ebp
                add     eax, ebx
                add     eax, ecx
                mov     [_@@@tmp+8], eax
                mov     eax, ebp
                sub     eax, ebx
                sub     eax, edx
                mov     [_@@@tmp+28h], eax
                mov     eax, ebp
                add     eax, edx
                sub     eax, ecx
                mov     [_@@@tmp+38h], eax
                mov     eax, [esi+40]
                add     eax, [esi+56]
                sub     eax, [esi+8]
                shl     eax, 1
                mov     edx, 9126145Fh  ; negC3
                imul    edx
                mov     [_@@@tmp+10h], edx
                mov     eax, [esi+8]
                add     eax, [esi+40]
                shl     eax, 1
                mov     edx, 7E0E2E33h  ; C1
                imul    edx
                mov     edi, edx
                mov     eax, [esi+40]
                sub     eax, [esi+56]
                mov     edx, 0A8715E2Eh ; negC7
                imul    edx
                mov     ebp, edx
                mov     eax, [esi+8]
                add     eax, [esi+56]
                shl     eax, 1
                mov     edx, 0ADB922B8h ; negC5
                imul    edx
                mov     ecx, edx
                mov     eax, [esi+24]
                shl     eax, 1
                mov     edx, 6ED9EBA2h  ; C3
                imul    edx
                mov     eax, ebp
                add     eax, edi
                add     eax, edx
                mov     [_@@@tmp], eax
                mov     eax, ebp
                sub     eax, ecx
                sub     eax, edx
                mov     [_@@@tmp+20h], eax
                mov     eax, edi
                add     eax, ecx
                sub     eax, edx
                mov     [_@@@tmp+30h], eax
                mov     ecx, [esi+4]
                mov     ebx, [esi+52]
                mov     edi, [esi+36]
                add     edi, [esi+68]
                sub     edi, [esi+20]
                lea     ebp, [ebx+ecx*2]
                sar     ebp, 1
                sub     ecx, ebx
                mov     eax, ecx
                add     eax, edi
                mov     [_@@@tmp+44h], eax
                sar     edi, 1
                mov     eax, ecx
                sub     eax, edi
                mov     [_@@@tmp+1Ch], eax
                mov     eax, [esi+20]   ; t0 = MULH(2*(src[2*2+j]+src[4*2+j]),C2)
                add     eax, [esi+36]
                shl     eax, 1
                mov     edx, 7847D90Ah  ; C2
                imul    edx
                mov     ebx, edx
                mov     eax, [esi+36]   ; t1 = MULH(src[4*2+j]-src[8*2+j],negC8)
                sub     eax, [esi+68]
                mov     edx, 0D38BCB04h ; negC8
                imul    edx
                mov     ecx, edx
                mov     eax, [esi+20]   ; t2 = MULH(2*(src[2*2+j]+src[8*2+j]),negC4)
                add     eax, [esi+68]
                shl     eax, 1
                mov     edx, 9DF24175h  ; negC4
                imul    edx
                mov     eax, ebp        ; tmp[2+j] = t3+t0+t1
                add     eax, ebx
                add     eax, ecx
                mov     [_@@@tmp+0Ch], eax
                mov     eax, ebp        ; tmp[10+j] = t3-t0-t2
                sub     eax, ebx
                sub     eax, edx
                mov     [_@@@tmp+2Ch], eax
                mov     eax, ebp        ; tmp[14+j] = t3+t2-t1
                add     eax, edx
                sub     eax, ecx
                mov     [_@@@tmp+3Ch], eax
                mov     eax, [esi+44]   ; tmp[4+j] = MULH(2*(src[5*2+j]+src[7*2+j]-src[1*2+j]),negC3)
                add     eax, [esi+60]
                sub     eax, [esi+12]
                shl     eax, 1
                mov     edx, 9126145Fh  ; negC3
                imul    edx
                mov     [_@@@tmp+14h], edx
                mov     eax, [esi+12]   ; @@MULH @@t2,[esi+(1*2+j)*4],add,[esi+(5*2+j)*4],-,-              ,1,C1,-
                                        ; t2 = MULH(2*(src[1*2+j],add,src[5*2+j]),-,-,1,C1)
                add     eax, [esi+44]
                shl     eax, 1
                mov     edx, 7E0E2E33h  ; C1
                imul    edx
                mov     edi, edx
                mov     eax, [esi+44]   ; @@MULH @@t3,[esi+(5*2+j)*4],sub,[esi+(7*2+j)*4],-,-,
                                        ; ,0,negC7,-
                                        ;
                                        ; t3 = MULH( src[5*2+j],sub,src[7*2+j],-,-,0,negC7)
                sub     eax, [esi+60]
                mov     edx, 0A8715E2Eh ; negC7
                imul    edx
                mov     ebp, edx
                mov     eax, [esi+12]   ; t1 = MULH(2*(src[1*2+j],add,src[7*2+j]),-,-,1,negC5)
                add     eax, [esi+60]
                shl     eax, 1          ; shift = 1
                mov     edx, 0ADB922B8h ; negC5
                imul    edx
                mov     ecx, edx
                mov     eax, [esi+28]   ; t0 = MULH(2*src[3*2+j],-,-,-,-,1,C3)
                shl     eax, 1
                mov     edx, 6ED9EBA2h  ; C3
                imul    edx
                mov     eax, ebp
                add     eax, edi
                add     eax, edx
                mov     [_@@@tmp+4], eax
                mov     eax, ebp
                sub     eax, ecx
                sub     eax, edx
                mov     [_@@@tmp+24h], eax
                mov     eax, edi        ; @@SUM [@@tmp+(12+j)*4],@@t2,add,@@t1,sub,edx
                add     eax, ecx
                sub     eax, edx
                mov     [_@@@tmp+34h], eax
                pop     edi
                pop     ebp
                pop     ebx
                push    esi             ; IRP j,0,1,2,3 ; j = 0
                mov     edx, [_@@@tmp] ; t0 = [@@tmp+(j*4+0)*4]
                mov     esi, [_@@@tmp+4] ; t1 = [@@tmp+(j*4+1)*4]
                mov     eax, [_@@@tmp+8] ; t2 = [@@tmp+(j*4+2)*4]
                mov     ecx, [_@@@tmp+0Ch] ; t2 = [@@tmp+(j*4+3)*4]
                sub     eax, edx        ; s2 = t2 - t0
                lea     edx, [eax+edx*2] ; s0 = t2 + t0
                mov     [_@@s2], eax ; @@MULH esi,eax ,-,-,-,-,1,icos36h_&j,-
                                        ; s2 = MULH(s2*2, icos36h[j])
                mov     [_@@s0], edx
                sub     ecx, esi
                lea     eax, [ecx+esi*2]
                shl     eax, 1
                mov     edx, 403E9590h  ; icos36h_0
                imul    edx
                mov     esi, edx
                mov     eax, ecx        ; @@MULH @@s3,ecx,-,-,-,-,shift_for_8minus&j,icos36h_8minus&j,-
                                        ; s3 = MULL(s3,icos36[8-j]) ; <-- "MULL" with "icos36"
                shl     eax, 4
                mov     edx, 5BCA2A2Ch  ; icos36h_8 (8-0)
                imul    edx
                mov     [_@@s3], edx
                mov     ecx, [_@@s0]
                sub     ecx, esi
                lea     esi, [ecx+esi*2]
                mov     eax, [ebp+36]   ; @@MULH [edi+(9+j)*SBLIMIT*4],[ebp+(9+j)*4],
                                        ; -,-,-,-,0,ecx,[ebx+(9+j)*4]
                                        ; out[(9+j)*SBLIMIT] = MULH(t0, win[9+j])+buf[9+j]
                imul    ecx
                add     edx, [ebx+36]   ; [ebx+(9+j)*4]
                mov     [edi+1152], edx ; SBLIMIT=32 ; 9*SBLIMIT*4 = 1152
                mov     eax, [ebp+32]   ; @@MULH [edi+(8-j)*SBLIMIT*4],[ebp+(8-j)*4]
                                        ; ,-,-,-,-,0,ecx,[ebx+(8-j)*4]
                imul    ecx
                add     edx, [ebx+32]
                mov     [edi+1024], edx ; SBLIMIT=32 ; 8*SBLIMIT*4 = 1024
                mov     eax, [ebp+108]
                imul    esi
                mov     [ebx+36], edx
                mov     eax, [ebp+104]  ; @@MULH [ebx+(8-j)*4],[ebp+(8-j+18)*4],-,-,-,-,0,esi,-
                imul    esi
                mov     [ebx+32], edx
                mov     ecx, [_@@s2]
                mov     esi, [_@@s3]
                sub     ecx, esi        ; t2 = s2 - s3
                lea     esi, [ecx+esi*2] ; t3 = s2 + s3
                mov     eax, [ebp+0]    ; @@MULH [edi+(0+j)*SBLIMIT*4],[ebp+(0+j)*4],
                                        ; -,-,-,-,0,ecx,[ebx+(0+j)*4]
                imul    ecx
                add     edx, [ebx]
                mov     [edi], edx
                mov     eax, [ebp+68]   ; @@MULH [edi+(17-j)*SBLIMIT*4],[ebp+(17-j)*4]
                                        ; ,-,-,-,-,0,ecx,[ebx+(17-j)*4]
                imul    ecx
                add     edx, [ebx+68]
                mov     [edi+2176], edx ; 17*SBLIMIT*4 = 2176
                mov     eax, [ebp+72]   ; @@MULH [ebx+(0+j)*4],[ebp+(0+j+18)*4],-,-,-,-,0,esi,-
                imul    esi
                mov     [ebx], edx
                mov     eax, [ebp+140]  ; @@MULH [ebx+(17-j)*4],[ebp+(17-j+18)*4],-,-,-,-,0,esi,-
                imul    esi
                mov     [ebx+68], edx
                mov     edx, [_@@@tmp+10h] ; IRP j,0,1,2,3 ; j = 1
                mov     esi, [_@@@tmp+14h]
                mov     eax, [_@@@tmp+18h]
                mov     ecx, [_@@@tmp+1Ch]
                sub     eax, edx
                lea     edx, [eax+edx*2]
                mov     [_@@s2], eax
                mov     [_@@s0], edx
                sub     ecx, esi
                lea     eax, [ecx+esi*2]
                shl     eax, 1
                mov     edx, 4241F707h  ; icos36h_1
                imul    edx
                mov     esi, edx
                mov     eax, ecx
                shl     eax, 2
                mov     edx, 7BA3751Eh  ; icos36h_7 (8-1)
                imul    edx
                mov     [_@@s3], edx
                mov     ecx, [_@@s0]
                sub     ecx, esi
                lea     esi, [ecx+esi*2]
                mov     eax, [ebp+40]
                imul    ecx
                add     edx, [ebx+40]
                mov     [edi+1280], edx
                mov     eax, [ebp+28]
                imul    ecx
                add     edx, [ebx+28]
                mov     [edi+896], edx
                mov     eax, [ebp+112]
                imul    esi
                mov     [ebx+40], edx
                mov     eax, [ebp+100]
                imul    esi
                mov     [ebx+28], edx
                mov     ecx, [_@@s2]
                mov     esi, [_@@s3]
                sub     ecx, esi
                lea     esi, [ecx+esi*2]
                mov     eax, [ebp+4]
                imul    ecx
                add     edx, [ebx+4]
                mov     [edi+128], edx
                mov     eax, [ebp+64]
                imul    ecx
                add     edx, [ebx+64]
                mov     [edi+2048], edx
                mov     eax, [ebp+76]
                imul    esi
                mov     [ebx+4], edx
                mov     eax, [ebp+136]
                imul    esi
                mov     [ebx+64], edx
                mov     edx, [_@@@tmp+20h] ; IRP j,0,1,2,3 ; j = 2
                mov     esi, [_@@@tmp+24h]
                mov     eax, [_@@@tmp+28h]
                mov     ecx, [_@@@tmp+2Ch]
                sub     eax, edx
                lea     edx, [eax+edx*2]
                mov     [_@@s2], eax
                mov     [_@@s0], edx
                sub     ecx, esi
                lea     eax, [ecx+esi*2]
                shl     eax, 1
                mov     edx, 469DBE6Ch  ; icos36h_2
                imul    edx
                mov     esi, edx
                mov     eax, ecx
                shl     eax, 2
                mov     edx, 4BB7EC62h  ; icos36h_6 (8-2)
                imul    edx
                mov     [_@@s3], edx
                mov     ecx, [_@@s0]
                sub     ecx, esi
                lea     esi, [ecx+esi*2]
                mov     eax, [ebp+44]
                imul    ecx
                add     edx, [ebx+44]
                mov     [edi+1408], edx
                mov     eax, [ebp+24]
                imul    ecx
                add     edx, [ebx+24]
                mov     [edi+768], edx
                mov     eax, [ebp+116]
                imul    esi
                mov     [ebx+44], edx
                mov     eax, [ebp+96]
                imul    esi
                mov     [ebx+24], edx
                mov     ecx, [_@@s2]
                mov     esi, [_@@s3]
                sub     ecx, esi
                lea     esi, [ecx+esi*2]
                mov     eax, [ebp+8]
                imul    ecx
                add     edx, [ebx+8]
                mov     [edi+256], edx
                mov     eax, [ebp+60]
                imul    ecx
                add     edx, [ebx+60]
                mov     [edi+1920], edx
                mov     eax, [ebp+80]
                imul    esi
                mov     [ebx+8], edx
                mov     eax, [ebp+132]
                imul    esi
                mov     [ebx+60], edx
                mov     edx, [_@@@tmp+30h] ; IRP j,0,1,2,3 ; j = 3
                mov     esi, [_@@@tmp+34h]
                mov     eax, [_@@@tmp+38h]
                mov     ecx, [_@@@tmp+3Ch]
                sub     eax, edx
                lea     edx, [eax+edx*2]
                mov     [_@@s2], eax
                mov     [_@@s0], edx
                sub     ecx, esi
                lea     eax, [ecx+esi*2]
                shl     eax, 1
                mov     edx, 4E212BBEh  ; icos36h_3
                imul    edx
                mov     esi, edx
                mov     eax, ecx
                shl     eax, 1
                mov     edx, 6F94A1DFh  ; icos36h_5 (8-3)
                imul    edx
                mov     [_@@s3], edx
                mov     ecx, [_@@s0]
                sub     ecx, esi
                lea     esi, [ecx+esi*2]
                mov     eax, [ebp+48]
                imul    ecx
                add     edx, [ebx+48]
                mov     [edi+1536], edx
                mov     eax, [ebp+20]
                imul    ecx
                add     edx, [ebx+20]
                mov     [edi+640], edx
                mov     eax, [ebp+120]
                imul    esi
                mov     [ebx+30h], edx
                mov     eax, [ebp+92]
                imul    esi
                mov     [ebx+20], edx
                mov     ecx, [_@@s2]
                mov     esi, [_@@s3]
                sub     ecx, esi
                lea     esi, [ecx+esi*2]
                mov     eax, [ebp+12]
                imul    ecx
                add     edx, [ebx+12]
                mov     [edi+384], edx
                mov     eax, [ebp+56]
                imul    ecx
                add     edx, [ebx+56]
                mov     [edi+1792], edx
                mov     eax, [ebp+84]
                imul    esi
                mov     [ebx+12], edx
                mov     eax, [ebp+128]
                imul    esi
                mov     [ebx+56], edx
                mov     ecx, [_@@@tmp+40h] ; IRP j,4
                                        ; [@@tmp+(j*4+0)*4]
                mov     eax, [_@@@tmp+44h] ; [@@tmp+(j*4+1)*4]
                shl     eax, 1
                mov     edx, 5A82799Ah  ; icos36h_4 (8-4)
                imul    edx
                sub     ecx, edx
                lea     esi, [ecx+edx*2]
                mov     eax, [ebp+52]   ; @@MULH [edi+(9+j)*SBLIMIT*4],[ebp+(9+j)*4],
                                        ; -,-,-,-,0,ecx,[ebx+(9+j)*4]
                                        ; out[(9+4)*SBLIMIT] = MULH(t0,win[9+4])+buf[9+4]
                imul    ecx
                add     edx, [ebx+52]
                mov     [edi+1664], edx ; 13*SBLIMIT*4 = 1664
                mov     eax, [ebp+16]   ; @MULH [edi+(8-j)*SBLIMIT*4],[ebp+(8-j)*4],
                                        ; -,-,-,-,0,ecx,[ebx+(8-j)*4]
                imul    ecx
                add     edx, [ebx+16]
                mov     [edi+512], edx
                mov     eax, [ebp+124]  ; @@MULH [ebx+(9+j)*4],[ebp+(9+j+18)*4] ,-,-,-,-,0,esi,-
                imul    esi
                mov     [ebx+52], edx
                mov     eax, [ebp+88]   ; @@MULH [ebx+(8-j)*4],[ebp+(8-j+18)*4],-,-,-,-,0,esi,-
                imul    esi
                mov     [ebx+16], edx
                pop     esi
                retn


; =============== S U B R O U T I N E =======================================


mp3_imdct12:
                mov     eax, [esi]      ; in: esi=src - out: [out2_...]
                mov     [_@@tmp0], eax  ; IRP nn,0,1,2,3,4,5
                                        ;  @@tmp&nn rd 1
                                        ; ENDM
                                        ; mov  eax,[esi+0*3*4] ; = src[0*3]
                mov     edx, [esi+12]   ; [esi+1*3*4] ; = src[1*3]
                add     eax, edx        ; = src[0*3]+src[1*3]
                mov     [_@@tmp1], eax
                mov     eax, [esi+24]
                add     edx, eax
                mov     [_@@tmp2], edx
                mov     edx, [esi+36]   ; [esi+3*3*4]
                add     eax, edx
                mov     [_@@tmp3], eax
                mov     eax, [esi+48]
                add     edx, eax
                mov     [_@@tmp4], edx
                mov     edx, [esi+60]   ; [esi+5*3*4]
                add     eax, edx        ; = src[4*3]+src[5*3]
                add     eax, [_@@tmp3]
                mov     [_@@tmp5], eax  ; tmp5 = src[4*3]+src[5*3]+tmp3
                mov     edx, [_@@tmp1]
                add     [_@@tmp3], edx
                mov     eax, [_@@tmp2]  ; @@MULH @@tmp2,@@tmp2,-,-,-,-,1,C3,-
                                        ; tmp2 = MULH(2*tmp2,C3)
                shl     eax, 1
                mov     edx, 6ED9EBA2h  ; C3
                imul    edx
                mov     [_@@tmp2], edx
                mov     eax, [_@@tmp3]  ; @@MULH @@tmp3,@@tmp3,-,-,-,-,2,C3,-
                                        ; tmp3 = MULH(4*tmp3,C3)
                shl     eax, 2
                mov     edx, 6ED9EBA2h  ; C3
                imul    edx
                mov     [_@@tmp3], edx
                mov     eax, [_@@tmp1]  ; @@MULH edx,@@tmp1,sub,@@tmp5,-,-,1,icos36h_4,-
                sub     eax, [_@@tmp5]  ; t2 = MULH(2*(tmp1-tmp5),icos36h_4)
                shl     eax, 1
                mov     edx, 5A82799Ah  ; icos36h_4
                imul    edx
                mov     eax, [_@@tmp0]  ; @@SUM eax,@@tmp0,sub,@@tmp4,-,-
                sub     eax, [_@@tmp4]  ; t1 = tmp0 - tmp4
                sub     eax, edx        ; @@CAST macro t1,t2,dst0,dst1,dst2,dst3
                                        ;   sub  t1,t2                           ;t1-t2
                                        ;   lea  t2,[t1+t2*2]                    ;t1+t2
                                        ;   mov  dword ptr [mp3_out2_a&dst0],t1  ;t1-t2
                                        ;   mov  dword ptr [mp3_out2_b&dst0],t2  ;t1+t2
                                        ; endm
                lea     edx, [eax+edx*2] ; @@CAST eax,edx,1,4,7,10
                                        ; out2[1,4,7,10]=t1-t2,t1-t2,t1+t2,t1+t2
                mov     [mp3_out2_a1], eax
                mov     [mp3_out2_b1], edx
                mov     eax, [_@@tmp4]
                mov     edx, [_@@tmp1]
                sar     eax, 1
                shl     edx, 1
                add     [_@@tmp0], eax  ; tmp0 = tmp0 + tmp4/2
                add     [_@@tmp5], edx  ; tmp5 = tmp5 + tmp1*2
                mov     eax, [_@@tmp5]  ; @@MULH edx,@@tmp5,add,@@tmp3,-,-,0,icos36h_1,-
                add     eax, [_@@tmp3]
                mov     edx, 4241F707h  ; icos36h_1
                imul    edx
                mov     eax, [_@@tmp0]  ; @@SUM eax,@@tmp0,add,@@tmp2,-,-
                add     eax, [_@@tmp2]
                sub     eax, edx        ; @@CAST eax,edx,2,3,8,9
                lea     edx, [eax+edx*2]
                mov     [mp3_out2_a2], eax
                mov     [mp3_out2_b2], edx
                mov     eax, [_@@tmp5]  ; @@MULH edx,@@tmp5,sub,@@tmp3,-,-,1,icos36h_7,-
                sub     eax, [_@@tmp3]
                shl     eax, 1
                mov     edx, 7BA3751Eh  ; icos36h_7
                imul    edx
                mov     eax, [_@@tmp0]  ; @@SUM eax,@@tmp0,sub,@@tmp2,-,-
                sub     eax, [_@@tmp2]
                sub     eax, edx        ; @@CAST eax,edx,0,5,6,11
                lea     edx, [eax+edx*2]
                mov     [mp3_out2_a0], eax
                mov     [mp3_out2_b0], edx
                retn


; =============== S U B R O U T I N E =======================================


mp3_compute_imdct:
                test    byte [cpuid_flags], 10h ; in: ebx=granule
                jz      short .no_rdtsc_supported ; timelog_start rdtsc_imdct
                rdtsc
                sub     [rdtsc_imdct], eax
                sbb     [rdtsc_imdct+4], edx

.no_rdtsc_supported:
                push    ebx
                mov     ecx, [ebx+96]   ; [ebx+$mp3gr_num_nonzero_hybrids_div9]
                imul    eax, ecx, 9
                lea     edi, [ebx+eax*4+160] ; [ebx+$mp3gr_sb_hybrid+eax*4]
                jecxz   .breakout

.scan_zero_lop:
                sub     edi, 36         ; index-9
                mov     eax, [edi]      ; [edi+0*4]
                or      eax, [edi+4]
                or      eax, [edi+8]
                or      eax, [edi+12]
                or      eax, [edi+16]
                or      eax, [edi+20]
                or      eax, [edi+24]
                or      eax, [edi+28]
                or      eax, [edi+32]   ; [edi+8*4]
                jnz     short .breakout
                dec     ecx
                jnz     short .scan_zero_lop

.breakout:
                inc     ecx             ; div9+1
                shr     ecx, 1          ; div18
                mov     [_@@sblimit], ecx
                cmp     dword [ebx+44], 2 ; [ebx+$mp3gr_block_type]
                jnz     short .this_long_end
                mov     ecx, [ebx+48]   ; [ebx+$mp3gr_switch_point]
                shl     ecx, 1          ; 0,1 --> 0,2

.this_long_end:
                mov     [_@@mdct_long_end], ecx
                mov     eax, [ebx+48]   ; [ebx+$mp3gr_switch_point]
                mov     [_@@switch_point], eax
                mov     eax, [ebx+44]   ; [ebx+$mp3gr_block_type]
                imul    eax, 144        ; 1*36*4
                mov     [_@@www], eax
                mov     ecx, [mp3_curr_channel]
                mov     eax, [mp3_curr_granule]
                imul    ecx, 4608       ; 36*SBLIMIT*4 ; channel ; sb_samples[ch][gr*18]
                imul    eax, 2304       ; 18*SBLIMIT*4 ; frame=granule*18
                lea     edi, [mp3_sb_samples+ecx+eax]
                lea     esi, [ebx+160]  ; [ebx+$mp3gr_sb_hybrid]
                mov     eax, [mp3_curr_channel]
                imul    eax, 2304       ; SBLIMIT*18*4
                lea     ebx, [mp3_mdct_buf+eax]
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@ ; timelog_start rdtsc_imdct36
                rdtsc
                sub     [rdtsc_imdct36], eax
                sbb     [rdtsc_imdct36+4], edx

.no_rdtsc_supported@:
                mov	dword [_@@@JJJ], 0
                cmp	dword [_@@mdct_long_end], 0
                jz      short .imdct36_done

.imdct36_lop:
                mov	ebp, mp3_mdct_win ; for j=0 to mdct_long_end-1
                cmp	dword [_@@@JJJ], 2
                sbb	eax, eax
                and	eax, [_@@switch_point]
                jnz	short .this_window ; force window 0
                add	ebp, [_@@www] ; mdct_win

.this_window:
                mov	eax, [_@@@JJJ]
                shr	eax, 1          ; cy=0,1
                sbb	eax, eax        ; eax=0,FFFFFFFFh
                and	eax, 576        ; 4*36*4
                add	ebp, eax
                call	mp3_imdct36
                add	edi, 4          ; 1*4 ; dst
                add	esi, 72         ; 18*4 ; sb_hybrid
                add	ebx, 72         ; mdct_buf ; next
                inc	dword [_@@@JJJ]
                mov	eax, [_@@@JJJ]
                cmp	eax, [_@@mdct_long_end]
                jb	short .imdct36_lop

.imdct36_done:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@ ; timelog_end rdtsc_imdct36
                rdtsc
                add     [rdtsc_imdct36], eax
                adc     [rdtsc_imdct36+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_imdct12
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_imdct12], eax
                sbb     [rdtsc_imdct12+4], edx

.no_rdtsc_supported@@@:
                mov     eax, [_@@@JJJ]
                cmp     eax, [_@@sblimit]
                jnb     .imdct12_done

.imdct12_lop:
                mov     ebp, (mp3_mdct_win+120h) ; for j=mdct_long_end to sblimit-1
                mov     eax, [_@@@JJJ]
                shr     eax, 1          ; cy=0,1
                sbb     eax, eax        ; eax=0,FFFFFFFFh
                and     eax, 576        ; 4*36*4
                add     ebp, eax        ; mdct_win
                mov     eax, [ebx]      ; IRP i,0,1,2,3,4,5
                mov     [edi], eax      ; @@SUM [edi+i*SBLIMIT*4],[ebx+(i+0)*4],-,-,-,-
                mov     eax, [ebx+4]
                mov     [edi+128], eax
                mov     eax, [ebx+8]
                mov     [edi+256], eax
                mov     eax, [ebx+12]
                mov     [edi+384], eax
                mov     eax, [ebx+16]
                mov     [edi+512], eax
                mov     eax, [ebx+20]
                mov     [edi+640], eax  ; ENDM
                add     edi, 768        ; 6*SBLIMIT*4
                call    mp3_imdct12
                mov     eax, [mp3_out2_a0] ; IRP i,0,1,2,3,4,5
                mov     edx, [ebp+0]    ; @@MULH [edi+i*SBLIMIT*4],[mp3_out2_a&i],
                                        ; -,-,-,-,0,[ebp+(i+0)*4],[ebx+(1*6+i)*4]
                imul    edx
                add     edx, [ebx+24]
                mov     [edi], edx
                mov     eax, [mp3_out2_b0] ; @@MULH [ebx+(2*6+i)*4],[mp3_out2_b&i],
                                        ; -,-,-,-,0,[ebp+(i+6)*4],-
                mov     edx, [ebp+24]
                imul    edx
                mov     [ebx+48], edx
                mov     eax, [mp3_out2_a1] ; i = 1
                mov     edx, [ebp+4]
                imul    edx
                add     edx, [ebx+28]
                mov     [edi+128], edx
                mov     eax, [mp3_out2_b1]
                mov     edx, [ebp+28]
                imul    edx
                mov     [ebx+52], edx
                mov     eax, [mp3_out2_a2] ; i = 2
                mov     edx, [ebp+8]
                imul    edx
                add     edx, [ebx+32]
                mov     [edi+256], edx
                mov     eax, [mp3_out2_b2]
                mov     edx, [ebp+32]
                imul    edx
                mov     [ebx+56], edx
                mov     eax, [mp3_out2_a2] ; i = 3 ; mp3_out2_a3 equ mp3_out2_a2
                mov     edx, [ebp+12]
                imul    edx
                add     edx, [ebx+36]
                mov     [edi+384], edx
                mov     eax, [mp3_out2_b2] ; mp3_out2_b3 equ mp3_out2_b2
                mov     edx, [ebp+36]
                imul    edx
                mov     [ebx+60], edx
                mov     eax, [mp3_out2_a1] ; i = 4 ; mp3_out2_a4 equ mp3_out2_a1
                mov     edx, [ebp+16]
                imul    edx
                add     edx, [ebx+40]
                mov     [edi+512], edx
                mov     eax, [mp3_out2_b1] ; mp3_out2_b4 equ mp3_out2_b1
                mov     edx, [ebp+40]
                imul    edx
                mov     [ebx+64], edx
                mov     eax, [mp3_out2_a0] ; i = 5 ; mp3_out2_a5 equ mp3_out2_a0
                mov     edx, [ebp+20]
                imul    edx
                add     edx, [ebx+44]
                mov     [edi+640], edx
                mov     eax, [mp3_out2_b0] ; mp3_out2_b5 equ mp3_out2_b0
                mov     edx, [ebp+44]
                imul    edx
                mov     [ebx+68], edx   ; ENDM
                add     edi, 768        ; 6*SBLIMIT*4
                add     esi, 4          ; sb_hybrid
                call    mp3_imdct12
                mov     eax, [mp3_out2_a0] ; IRP i,0,1,2,3,4,5
                mov     edx, [ebp+0]    ; @@MULH [edi+i*SBLIMIT*4],[mp3_out2_a&i],
                                        ; -,-,-,-,0,[ebp+(i+0)*4],[ebx+(2*6+i)*4]
                imul    edx             ; @@MULH [ebx+(0*6+i)*4],[mp3_out2_b&i],
                                        ; -,-,-,-,0,[ebp+(i+6)*4],-
                add     edx, [ebx+48]
                mov     [edi], edx
                mov     eax, [mp3_out2_b0]
                mov     edx, [ebp+18h]
                imul    edx
                mov     [ebx], edx
                mov     eax, [mp3_out2_a1] ; i = 1
                mov     edx, [ebp+4]
                imul    edx
                add     edx, [ebx+52]
                mov     [edi+128], edx
                mov     eax, [mp3_out2_b1]
                mov     edx, [ebp+28]
                imul    edx
                mov     [ebx+4], edx
                mov     eax, [mp3_out2_a2] ; i = 2
                mov     edx, [ebp+8]
                imul    edx
                add     edx, [ebx+56]
                mov     [edi+256], edx
                mov     eax, [mp3_out2_b2]
                mov     edx, [ebp+32]
                imul    edx
                mov     [ebx+8], edx
                mov     eax, [mp3_out2_a2] ; i = 3
                mov     edx, [ebp+12]
                imul    edx
                add     edx, [ebx+60]
                mov     [edi+384], edx
                mov     eax, [mp3_out2_b2]
                mov     edx, [ebp+36]
                imul    edx
                mov     [ebx+12], edx
                mov     eax, [mp3_out2_a1] ; i = 4
                mov     edx, [ebp+16]
                imul    edx
                add     edx, [ebx+64]
                mov     [edi+512], edx
                mov     eax, [mp3_out2_b1]
                mov     edx, [ebp+40]
                imul    edx
                mov     [ebx+16], edx
                mov     eax, [mp3_out2_a0] ; i = 5
                mov     edx, [ebp+20]
                imul    edx
                add     edx, [ebx+68]
                mov     [edi+640], edx
                mov     eax, [mp3_out2_b0]
                mov     edx, [ebp+44]
                imul    edx
                mov     [ebx+20], edx   ; ENDM
                add     esi, 4
                call    mp3_imdct12
                mov     eax, [mp3_out2_a0] ; IRP i,0,1,2,3,4,5
                mov     edx, [ebp+0]    ; @@MULH [ebx+(0*6+i)*4],[mp3_out2_a&i],
                                        ; -,-,-,-,0,[ebp+(i+0)*4],[ebx+(0*6+i)*4]
                imul    edx
                add     edx, [ebx]
                mov     [ebx], edx
                mov     eax, [mp3_out2_b0] ; @@MULH [ebx+(1*6+i)*4],[mp3_out2_b&i],
                                        ; -,-,-,-,0,[ebp+(i+6)*4],-
                mov     edx, [ebp+24]
                imul    edx
                mov     [ebx+24], edx
                mov     dword [ebx+48], 0 ; [ebx+(2*6+i)*4]
                mov     eax, [mp3_out2_a1] ; i = 1
                mov     edx, [ebp+4]
                imul    edx
                add     edx, [ebx+4]
                mov     [ebx+4], edx
                mov     eax, [mp3_out2_b1]
                mov     edx, [ebp+28]
                imul    edx
                mov     [ebx+28], edx
                mov     dword [ebx+52], 0 ; [ebx+(2*6+i)*4]
                mov     eax, [mp3_out2_a2] ; i = 2
                mov     edx, [ebp+8]
                imul    edx
                add     edx, [ebx+8]
                mov     [ebx+8], edx
                mov     eax, [mp3_out2_b2]
                mov     edx, [ebp+32]
                imul    edx
                mov     [ebx+32], edx
                mov     dword [ebx+56], 0
                mov     eax, [mp3_out2_a2] ; i = 3
                mov     edx, [ebp+12]
                imul    edx
                add     edx, [ebx+0Ch]
                mov     [ebx+12], edx
                mov     eax, [mp3_out2_b2]
                mov     edx, [ebp+36]
                imul    edx
                mov     [ebx+36], edx
                mov     dword [ebx+60], 0 ; [ebx+(2*6+i)*4]
                mov     eax, [mp3_out2_a1] ; i = 4
                mov     edx, [ebp+16]
                imul    edx
                add     edx, [ebx+16]
                mov     [ebx+16], edx
                mov     eax, [mp3_out2_b1]
                mov     edx, [ebp+40]
                imul    edx
                mov     [ebx+40], edx
                mov     dword [ebx+64], 0
                mov     eax, [mp3_out2_a0] ; i = 5
                mov     edx, [ebp+20]
                imul    edx
                add     edx, [ebx+20]
                mov     [ebx+20], edx
                mov     eax, [mp3_out2_b0]
                mov     edx, [ebp+44]
                imul    edx
                mov     [ebx+44], edx
                mov     dword [ebx+68], 0 ; [ebx+(2*6+i)*4]
                add     edi, -1532      ; (1*4) - (2*6*SBLIMIT*4) ; dst
                add     esi, 64         ; 18*4 - (2*4) ; sb_hybrid
                add     ebx, 72         ; 18*4 ; mdct_buf
                inc     dword [_@@@JJJ]	; next
                mov     eax, [_@@@JJJ]
                cmp     eax, [_@@sblimit]
                jb      .imdct12_lop

.imdct12_done:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@ ; timelog_end rdtsc_imdct12
                rdtsc
                add     [rdtsc_imdct12], eax
                adc     [rdtsc_imdct12+4], edx

.no_rdtsc_supported@@@@:
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_imdct0
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                sub     [rdtsc_imdct0], eax
                sbb     [rdtsc_imdct0+4], edx

.no_rdtsc_supported@@@@@:
                cmp     dword [_@@@JJJ], 32 ; SBLIMIT
                jnb     .zero_outer_done

.zero_outer_lop:
                mov     eax, [ebx]      ; zero bands
                                        ; IRP nn,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17
                                        ;  mov  eax,dword ptr [ebx+nn*4]
                                        ;  mov  dword ptr [ebx+nn*4],0
                                        ;  mov  dword ptr [edi+nn*SBLIMIT*4],eax ; [dst]
                                        ; ENDM
                mov     dword [ebx], 0 ; nn = 0
                mov     [edi], eax
                mov     eax, [ebx+4]    ; nn = 1
                mov     dword [ebx+4], 0
                mov     [edi+128], eax
                mov     eax, [ebx+8]
                mov     dword [ebx+8], 0
                mov     [edi+256], eax
                mov     eax, [ebx+12]
                mov     dword [ebx+12], 0
                mov     [edi+384], eax
                mov     eax, [ebx+16]   ; nn = 4
                mov     dword [ebx+16], 0
                mov     [edi+512], eax
                mov     eax, [ebx+20]
                mov     dword [ebx+20], 0
                mov     [edi+640], eax  ; [edi+5*SBLIMIT*4]
                mov     eax, [ebx+24]
                mov     dword [ebx+24], 0
                mov     [edi+768], eax
                mov     eax, [ebx+28]   ; nn = 7
                mov     dword [ebx+28], 0
                mov     [edi+896], eax
                mov     eax, [ebx+32]
                mov     dword [ebx+32], 0
                mov     [edi+1024], eax ; [edi+8*SBLIMIT*4]
                mov     eax, [ebx+36]
                mov     dword [ebx+36], 0
                mov     [edi+1152], eax
                mov     eax, [ebx+40]
                mov     dword [ebx+40], 0
                mov     [edi+1280], eax
                mov     eax, [ebx+44]
                mov     dword [ebx+44], 0
                mov     [edi+1408], eax
                mov     eax, [ebx+48]
                mov     dword [ebx+48], 0
                mov     [edi+1536], eax
                mov     eax, [ebx+52]
                mov     dword [ebx+52], 0
                mov     [edi+1664], eax
                mov     eax, [ebx+56]
                mov     dword [ebx+56], 0
                mov     [edi+1792], eax
                mov     eax, [ebx+60]
                mov     dword [ebx+60], 0
                mov     [edi+1920], eax
                mov     eax, [ebx+64]
                mov     dword [ebx+64], 0 ; [edi+16*SBLIMIT*4]
                mov     [edi+2048], eax
                mov     eax, [ebx+68]   ; nn = 17
                mov     dword [ebx+68], 0
                mov     [edi+2176], eax ; ENDM
                add     ebx, 72         ; 18*4
                add     edi, 4
                inc     dword [_@@@JJJ]
                cmp     dword [_@@@JJJ], 32
                jb      .zero_outer_lop

.zero_outer_done:
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_imdct0
                jz      short .no_rdtsc_supported@@@@@@
                rdtsc
                add     [rdtsc_imdct0], eax
                adc     [rdtsc_imdct0+4], edx

.no_rdtsc_supported@@@@@@:
                pop     ebx
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_imdct
                jz      short .no_rdtsc_supported@@@@@@@
                rdtsc
                add     [rdtsc_imdct], eax
                adc     [rdtsc_imdct+4], edx

.no_rdtsc_supported@@@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_dct32_shift_0:
                mov     eax, [esi]      ; mp3_dct32_macro macro rate_shift ; rate_shift = 0
                mov     edx, [esi+124]  ; @@BF macro a,b,sign,cos,shift
                                        ; @@BF 0,31,+,COS0_0,1
                                        ; @@need_a equ (rate_shift EQ 0) or (a LT 16) ; a = 0
                                        ; @@need_b equ (rate_shift EQ 0) or (b LT 16) ; b = 31
                                        ; IF @@need_a AND @@need_b ; rate_shift = 0
                                        ;    mov eax,dword ptr [esi+a*4]
                                        ;    mov edx,dword ptr [esi+b*4]
                                        ;    add dword ptr [esi+a*4],edx
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1          ; shl  eax,shift
                                        ; (needed when COS.fraction is less than 32bit)
                mov     edx, 4013C251h  ; sign&&cos ; +COS0_0 = 4013C251h
                imul    edx
                mov     [esi+124], edx  ; [esi+b*4] ; upper 32bit of multiply result
                mov     eax, [esi+60]   ; @@BF 15,16,+,COS0_15,5
                                        ; [esi+a*4]
                mov     edx, [esi+64]   ; [esi+b*4]
                add     [esi+60], edx   ; [esi+a*4]
                sub     eax, edx
                shl     eax, 5          ; shl eax,shift
                mov     edx, 518522FBh  ; sign&&cos ; +COS0_15 = 518522FBh
                imul    edx
                mov     [esi+64], edx   ; [esi+b*4]
                mov     eax, [esi]      ; @@BF 0,15,+,COS1_0,1
                mov     edx, [esi+60]
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 404F4672h  ; +COS1_0
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+64]   ; @@BF 16,31,-,COS1_0,1
                mov     edx, [esi+124]
                add     [esi+64], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BFB0B98Eh ; -COS1_0
                imul    edx
                mov     [esi+124], edx
                mov     eax, [esi+28]   ; @@BF 7,24,+,COS0_7,1
                mov     edx, [esi+96]
                add     [esi+28], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 56601EA7h
                imul    edx
                mov     [esi+96], edx
                mov     eax, [esi+32]   ; @@BF 8,23,+,COS0_8,1
                mov     edx, [esi+92]
                add     [esi+32], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5F4CF6ECh
                imul    edx
                mov     [esi+92], edx
                mov     eax, [esi+28]   ; @@BF 7,8,+,COS1_7,4
                mov     edx, [esi+32]
                add     [esi+28], edx
                sub     eax, edx
                shl     eax, 4
                mov     edx, 519E4E04h
                imul    edx
                mov     [esi+32], edx
                mov     eax, [esi+92]   ; @@BF 23,24,-,COS1_7,4
                mov     edx, [esi+96]
                add     [esi+92], edx
                sub     eax, edx
                shl     eax, 4
                mov     edx, 0AE61B1FCh
                imul    edx
                mov     [esi+96], edx
                mov     eax, [esi]      ; @@BF 0,7,+,COS2_0,1
                mov     edx, [esi+28]
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4140FB46h
                imul    edx
                mov     [esi+28], edx
                mov     eax, [esi+32]   ; @@BF 8,15,-,COS2_0,1
                mov     edx, [esi+60]
                add     [esi+32], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BEBF04BAh
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+64]   ; @@BF 16,23,+,COS2_0,1
                mov     edx, [esi+92]
                add     [esi+40h], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4140FB46h
                imul    edx
                mov     [esi+92], edx
                mov     eax, [esi+96]   ; @@BF 24,31,-,COS2_0,1
                mov     edx, [esi+124]
                add     [esi+96], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BEBF04BAh
                imul    edx
                mov     [esi+124], edx
                mov     eax, [esi+12]   ; @@BF 3,28,+,COS0_3,1
                mov     edx, [esi+112]
                add     [esi+12], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 43F93421h
                imul    edx
                mov     [esi+112], edx
                mov     eax, [esi+48]   ; @@BF 12,19,+,COS0_12,2
                mov     edx, [esi+76]
                add     [esi+48], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 5EFC8D97h
                imul    edx
                mov     [esi+76], edx
                mov     eax, [esi+12]   ; @@BF 3,12,+,COS1_3,1
                mov     edx, [esi+48]
                add     [esi+12], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 52CB0E63h
                imul    edx
                mov     [esi+48], edx
                mov     eax, [esi+76]   ; @@BF 19,28,-,COS1_3,1
                mov     edx, [esi+112]
                add     [esi+76], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0AD34F19Dh
                imul    edx
                mov     [esi+112], edx
                mov     eax, [esi+16]   ; @@BF 4,27,+,COS0_4,1
                mov     edx, [esi+108]
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 46CC1BC5h
                imul    edx
                mov     [esi+108], edx
                mov     eax, [esi+44]   ; @@BF 11,20,+,COS0_11,2
                mov     edx, [esi+80]
                add     [esi+44], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 4AD81A98h
                imul    edx
                mov     [esi+80], edx
                mov     eax, [esi+16]   ; @@BF 4,11,+,COS1_4,1
                mov     edx, [esi+44]
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 64E2402Eh
                imul    edx
                mov     [esi+44], edx
                mov     eax, [esi+80]   ; @@BF 20,27,-,COS1_4,1
                mov     edx, [esi+108]
                add     [esi+80], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 9B1DBFD2h
                imul    edx
                mov     [esi+108], edx
                mov     eax, [esi+12]   ; @@BF 3,4,+,COS2_3,3
                mov     edx, [esi+16]
                add     [esi+12], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 52036742h
                imul    edx
                mov     [esi+16], edx
                mov     eax, [esi+44]   ; @@BF 11,12,-,COS2_3,3
                mov     edx, [esi+48]
                add     [esi+44], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 0ADFC98BEh ; -COS2_3
                imul    edx
                mov     [esi+48], edx
                mov     eax, [esi+76]   ; @@BF 19,20,+,COS2_3,3
                mov     edx, [esi+80]
                add     [esi+4Ch], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 52036742h  ; +COS2_3
                imul    edx
                mov     [esi+80], edx
                mov     eax, [esi+108]  ; @@BF 27,28,-,COS2_3,3
                mov     edx, [esi+112]
                add     [esi+108], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 0ADFC98BEh
                imul    edx
                mov     [esi+112], edx
                mov     eax, [esi]      ; @@BF 0,3,+,COS3_0,1
                mov     edx, [esi+12]
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4545E9F0h
                imul    edx
                mov     [esi+12], edx
                mov     eax, [esi+16]   ; @@BF 4,7,-,COS3_0,1
                mov     edx, [esi+28]
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BABA1610h
                imul    edx
                mov     [esi+28], edx
                mov     eax, [esi+32]   ; @@BF 8,11,+,COS3_0,1
                mov     edx, [esi+44]
                add     [esi+32], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4545E9F0h
                imul    edx
                mov     [esi+44], edx
                mov     eax, [esi+48]   ; @@BF 12,15,-,COS3_0,1
                mov     edx, [esi+60]
                add     [esi+48], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BABA1610h
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+64]   ; @@BF 16,19,+,COS3_0,1
                mov     edx, [esi+76]
                add     [esi+64], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4545E9F0h
                imul    edx
                mov     [esi+76], edx
                mov     eax, [esi+80]   ; @@BF 20,23,-,COS3_0,1
                mov     edx, [esi+92]
                add     [esi+80], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BABA1610h ; -COS3_0
                imul    edx
                mov     [esi+92], edx
                mov     eax, [esi+96]   ; @@BF 24,27,+,COS3_0,1
                mov     edx, [esi+108]
                add     [esi+96], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4545E9F0h  ; +COS3_0
                imul    edx
                mov     [esi+108], edx
                mov     eax, [esi+112]  ; @@BF 28,31,-,COS3_0,1
                mov     edx, [esi+124]
                add     [esi+112], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BABA1610h
                imul    edx
                mov     [esi+124], edx
                mov     eax, [esi+4]    ; @@BF 1,30,+,COS0_1,1
                mov     edx, [esi+120]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 40B345BDh
                imul    edx
                mov     [esi+120], edx
                mov     eax, [esi+56]   ; @@BF 14,17,+,COS0_14,3
                mov     edx, [esi+68]
                add     [esi+56], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 6D0B20D0h
                imul    edx
                mov     [esi+68], edx
                mov     eax, [esi+4]    ; @@BF 1,14,+,COS1_1,1
                mov     edx, [esi+56]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 42E13C10h
                imul    edx
                mov     [esi+56], edx
                mov     eax, [esi+68]   ; @@BF 17,30,-,COS1_1,1
                mov     edx, [esi+120]
                add     [esi+68], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BD1EC3F0h
                imul    edx
                mov     [esi+120], edx
                mov     eax, [esi+24]   ; @@BF 6,25,+,COS0_6,1
                mov     edx, [esi+100]
                add     [esi+24], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4FAE3712h
                imul    edx
                mov     [esi+100], edx
                mov     eax, [esi+36]   ; @@BF 9,22,+,COS0_9,1
                mov     edx, [esi+88]
                add     [esi+36], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 6B6FCF27h
                imul    edx
                mov     [esi+88], edx
                mov     eax, [esi+24]   ; @@BF 6, 9,+,COS1_6,2
                mov     edx, [esi+36]
                add     [esi+24], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 6E3C92C2h
                imul    edx
                mov     [esi+36], edx
                mov     eax, [esi+88]   ; @@BF 22,25,-,COS1_6,2
                mov     edx, [esi+100]
                add     [esi+88], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 91C36D3Eh
                imul    edx
                mov     [esi+100], edx
                mov     eax, [esi+4]    ; @@BF 1, 6,+,COS2_1,1
                mov     edx, [esi+24]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4CF8DE88h
                imul    edx
                mov     [esi+24], edx
                mov     eax, [esi+36]   ; @@BF 9,14,-,COS2_1,1
                mov     edx, [esi+56]
                add     [esi+36], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0B3072178h
                imul    edx
                mov     [esi+56], edx
                mov     eax, [esi+68]   ; @@BF 17,22,+,COS2_1,1
                mov     edx, [esi+88]
                add     [esi+68], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4CF8DE88h
                imul    edx
                mov     [esi+88], edx
                mov     eax, [esi+100]  ; @@BF 25,30,-,COS2_1,1
                mov     edx, [esi+120]
                add     [esi+100], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0B3072178h
                imul    edx
                mov     [esi+120], edx
                mov     eax, [esi+8]    ; @@BF 2,29,+,COS0_2,1
                mov     edx, [esi+116]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 41FA2D6Eh
                imul    edx
                mov     [esi+116], edx
                mov     eax, [esi+52]   ; @@BF 13,18,+,COS0_13,3
                mov     edx, [esi+72]
                add     [esi+52], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 41D95790h
                imul    edx
                mov     [esi+72], edx
                mov     eax, [esi+8]    ; @@BF 2,13,+,COS1_2,1
                mov     edx, [esi+52]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 48919F45h
                imul    edx
                mov     [esi+52], edx
                mov     eax, [esi+72]   ; @@BF 18,29,-,COS1_2,1
                mov     edx, [esi+116]
                add     [esi+72], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0B76E60BBh
                imul    edx
                mov     [esi+116], edx
                mov     eax, [esi+20]   ; @@BF 5,26,+,COS0_5,1
                mov     edx, [esi+104]
                add     [esi+20], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4A9D9CF1h
                imul    edx
                mov     [esi+104], edx
                mov     eax, [esi+40]   ; @@BF 10,21,+,COS0_10,1
                mov     edx, [esi+84]
                add     [esi+40], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 7C7D1DB4h
                imul    edx
                mov     [esi+84], edx
                mov     eax, [esi+20]   ; @@BF 5,10,+,COS1_5,2
                mov     edx, [esi+40]
                add     [esi+20], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 43E224AAh
                imul    edx
                mov     [esi+40], edx
                mov     eax, [esi+84]   ; @@BF 21,26,-,COS1_5,2
                mov     edx, [esi+104]
                add     [esi+84], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 0BC1DDB56h
                imul    edx
                mov     [esi+104], edx
                mov     eax, [esi+8]    ; @@BF 2,5,+,COS2_2,1
                mov     edx, [esi+20]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 73326BBFh  ; +COS2_2
                imul    edx
                mov     [esi+20], edx
                mov     eax, [esi+40]   ; @@BF 10,13,-,COS2_2,1
                mov     edx, [esi+52]
                add     [esi+40], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 8CCD9441h  ; -COS2_2
                imul    edx
                mov     [esi+52], edx
                mov     eax, [esi+72]   ; @@BF 18,21,+,COS2_2,1
                mov     edx, [esi+84]
                add     [esi+72], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 73326BBFh
                imul    edx
                mov     [esi+84], edx
                mov     eax, [esi+104]  ; @@BF 26,29,-,COS2_2,1
                mov     edx, [esi+116]
                add     [esi+104], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 8CCD9441h
                imul    edx
                mov     [esi+116], edx
                mov     eax, [esi+4]    ; @@BF 1,2,+,COS3_1,2
                mov     edx, [esi+8]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 539EBA46h
                imul    edx
                mov     [esi+8], edx
                mov     eax, [esi+20]   ; @@BF 5,6,-,COS3_1,2
                mov     edx, [esi+24]
                add     [esi+20], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 0AC6145BAh
                imul    edx
                mov     [esi+24], edx
                mov     eax, [esi+36]   ; IF rate_shift LT 2
                                        ; @@BF 9,10,+,COS3_1,2
                mov     edx, [esi+40]
                add     [esi+36], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 539EBA46h
                imul    edx
                mov     [esi+40], edx
                mov     eax, [esi+52]   ; @@BF 13,14,-,COS3_1,2
                mov     edx, [esi+56]
                add     [esi+52], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 0AC6145BAh
                imul    edx
                mov     [esi+56], edx   ; ENDIF
                mov     eax, [esi+68]   ; @@BF 17,18,+,COS3_1,2
                mov     edx, [esi+72]
                add     [esi+68], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 539EBA46h
                imul    edx
                mov     [esi+72], edx
                mov     eax, [esi+84]   ; @@BF 21,22,-,COS3_1,2
                mov     edx, [esi+88]
                add     [esi+84], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 0AC6145BAh
                imul    edx
                mov     [esi+88], edx
                mov     eax, [esi+100]  ; @@BF 25,26,+,COS3_1,2
                mov     edx, [esi+104]
                add     [esi+100], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 539EBA46h
                imul    edx
                mov     [esi+104], edx
                mov     eax, [esi+116]  ; @@BF 29,30,-,COS3_1,2
                mov     edx, [esi+120]
                add     [esi+116], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 0AC6145BAh
                imul    edx
                mov     [esi+120], edx
                mov     eax, [esi]      ; @@BF1 macro a, b, c, d
                                        ;   @@BF  a, b,+,COS4_0, 1
                                        ;   @@BF  c, d,-,COS4_0, 1
                                        ;   @@ADD c, d
                                        ;  endm
                                        ; @@BF1 0,1,2,3
                mov     edx, [esi+4]    ; @@BF 0,1,+,COS4_0,1
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah  ; +COS4_0
                imul    edx
                mov     [esi+4], edx
                mov     eax, [esi+8]    ; @@BF 2,3,-,COS4_0,1
                mov     edx, [esi+12]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h ; -COS4_0
                imul    edx
                mov     [esi+12], edx
                mov     eax, [esi+12]   ; @@ADD 2,3
                add     [esi+8], eax
                mov     eax, [esi+16]   ; @@BF2 macro a, b, c, d
                                        ;   @@BF  a, b,+,COS4_0, 1
                                        ;   @@BF  c, d,-,COS4_0, 1
                                        ;   @@ADD c, d
                                        ;   @@ADD a, c
                                        ;   @@ADD c, b
                                        ;   @@ADD b, d
                                        ;  endm
                                        ; @@BF2 4,5,6,7
                mov     edx, [esi+20]   ; @@BF 4,5,+,COS4_0,1
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+20], edx
                mov     eax, [esi+24]   ; @@BF 6,7,-,COS4_0,1
                mov     edx, [esi+28]
                add     [esi+24], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+28], edx
                mov     eax, [esi+28]   ; @@ADD macro dst,src
                                        ;   IF (rate_shift EQ 0) or (dst LT 16)
                                        ;    ;tab[a] += tab[b]
                                        ;    mov  eax,dword ptr [esi+src*4]
                                        ;    add  dword ptr [esi+dst*4],eax
                                        ;   ENDIF
                                        ;  endm
                                        ; @@ADD 6,7
                add     [esi+24], eax
                mov     eax, [esi+24]   ; @@ADD 4,6
                add     [esi+16], eax
                mov     eax, [esi+20]   ; @@ADD 6,5
                add     [esi+24], eax
                mov     eax, [esi+28]   ; @@ADD 5,7
                add     [esi+20], eax
                mov     eax, [esi+32]   ; IF rate_shift LT 2
                                        ; @@BF1 8,9,10,11
                mov     edx, [esi+36]   ; @@BF 8,9,+,COS4_0,1
                add     [esi+32], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+36], edx
                mov     eax, [esi+40]   ; @@BF 10,11,-,COS4_0,1
                mov     edx, [esi+44]
                add     [esi+40], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+44], edx
                mov     eax, [esi+44]   ; @@ADD 10,11
                add     [esi+40], eax
                mov     eax, [esi+48]   ; @@BF2 12,13,14,15
                mov     edx, [esi+52]   ; @@BF 12,13,+,COS4_0,1
                add     [esi+48], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+52], edx
                mov     eax, [esi+56]   ; @@BF 14,15,-,COS4_0,1
                mov     edx, [esi+60]
                add     [esi+56], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+60]   ; @@ADD 14,15
                add     [esi+56], eax
                mov     eax, [esi+56]   ; @@ADD 12,14
                add     [esi+48], eax
                mov     eax, [esi+52]   ; @@ADD 14,13
                add     [esi+56], eax
                mov     eax, [esi+60]   ; @@ADD 13,15
                add     [esi+52], eax   ; ENDIF
                mov     eax, [esi+64]   ; @@BF1 16,17,18,19
                mov     edx, [esi+68]
                add     [esi+64], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah  ; +COS4_0
                imul    edx
                mov     [esi+68], edx
                mov     eax, [esi+72]
                mov     edx, [esi+76]
                add     [esi+72], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h ; -COS4_0
                imul    edx
                mov     [esi+76], edx
                mov     eax, [esi+76]   ; @@ADD 18,19
                add     [esi+72], eax
                mov     eax, [esi+80]   ; @@BF2 20,21,22,23
                mov     edx, [esi+84]
                add     [esi+80], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+84], edx
                mov     eax, [esi+88]
                mov     edx, [esi+92]
                add     [esi+88], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+92], edx
                mov     eax, [esi+92]   ; @@ADD 22,23
                add     [esi+88], eax
                mov     eax, [esi+88]   ; @@ADD 20,22
                add     [esi+80], eax
                mov     eax, [esi+84]
                add     [esi+88], eax
                mov     eax, [esi+92]
                add     [esi+84], eax
                mov     eax, [esi+96]   ; @@BF1 24,25,26,27
                mov     edx, [esi+100]
                add     [esi+96], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+100], edx
                mov     eax, [esi+104]
                mov     edx, [esi+108]
                add     [esi+104], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+108], edx
                mov     eax, [esi+108]
                add     [esi+104], eax
                mov     eax, [esi+112]  ; @@BF2 28,29,30,31
                mov     edx, [esi+116]
                add     [esi+112], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+116], edx
                mov     eax, [esi+120]
                mov     edx, [esi+124]
                add     [esi+120], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+124], edx
                mov     eax, [esi+124]
                add     [esi+120], eax
                mov     eax, [esi+120]
                add     [esi+112], eax
                mov     eax, [esi+116]
                add     [esi+120], eax
                mov     eax, [esi+124]
                add     [esi+116], eax
                mov     eax, [esi]      ; @@OUT macro dst,src1,src2
                                        ; IF ((dst AND ((1 SHL rate_shift)-1)) EQ 0)
                                        ;    mov eax,dword ptr [esi+src1*4]
                                        ;    IFDIFI <src2>,<->
                                        ;      add eax,dword ptr [esi+src2*4]
                                        ;    ENDIF
                                        ;    IF SYNTH32
                                        ;       mov dword ptr [edi+dst*4],eax
                                        ;       IF (LONG_WINDOW EQ 0)
                                        ;          mov dword ptr [edi+dst*4+512*4],eax
                                        ;       ENDIF
                                        ;    ELSE
                                        ;        ......
                                        ;    ENDIF
                                        ; @@OUT 0,0,-
                mov     [edi], eax      ; mov dword ptr [edi+dst*4],eax
                mov     eax, [esi+4]    ; @@OUT 16,1, -
                                        ; mov eax,dword ptr [esi+src1*4]
                mov     [edi+64], eax   ; mov dword ptr [edi+dst*4],eax
                mov     eax, [esi+8]    ; @@OUT 8,2,-
                mov     [edi+32], eax
                mov     eax, [esi+12]   ; @@OUT 24,3,-
                mov     [edi+96], eax
                mov     eax, [esi+16]   ; @@OUT 4,4,-
                mov     [edi+16], eax
                mov     eax, [esi+20]   ; @@OUT 20,5,-
                mov     [edi+80], eax
                mov     eax, [esi+24]   ; @@OUT 12,6,-
                mov     [edi+48], eax
                mov     eax, [esi+28]   ; @@OUT 28,7,-
                mov     [edi+112], eax
                mov     eax, [esi+32]   ; @@OUT 2,8,12
                add     eax, [esi+48]   ; add eax,dword ptr [esi+src2*4]
                mov     [edi+8], eax
                mov     eax, [esi+36]   ; @@OUT 18,9,13
                add     eax, [esi+52]   ; add eax,dword ptr [esi+src2*4]
                mov     [edi+72], eax
                mov     eax, [esi+40]   ; @@OUT 10,10,14
                add     eax, [esi+56]
                mov     [edi+40], eax
                mov     eax, [esi+44]   ; @@OUT 26,11,15
                add     eax, [esi+60]
                mov     [edi+104], eax
                mov     eax, [esi+48]   ; @@OUT 6,12,10
                add     eax, [esi+40]
                mov     [edi+24], eax
                mov     eax, [esi+52]   ; @@OUT 22,13,11
                add     eax, [esi+44]
                mov     [edi+88], eax
                mov     eax, [esi+56]   ; @@OUT 14,14,9
                add     eax, [esi+36]
                mov     [edi+56], eax
                mov     eax, [esi+60]   ; @@OUT 30,15,-
                mov     [edi+120], eax
                mov     eax, [esi+112]  ; @@ADD 24,28
                add     [esi+96], eax
                mov     eax, [esi+104]  ; @@ADD 28,26
                add     [esi+112], eax
                mov     eax, [esi+120]  ; @@ADD 26,30
                add     [esi+104], eax
                mov     eax, [esi+100]  ; @@ADD 30,25
                add     [esi+120], eax
                mov     eax, [esi+116]  ; @@ADD 25,29
                add     [esi+100], eax
                mov     eax, [esi+108]  ; @@ADD 29,27
                add     [esi+116], eax
                mov     eax, [esi+124]  ; @@ADD 27,31
                add     [esi+108], eax
                mov     eax, [esi+64]   ; @@OUT 1,16,24
                add     eax, [esi+96]
                mov     [edi+4], eax
                mov     eax, [esi+68]   ; @@OUT 17,17,25
                add     eax, [esi+100]
                mov     [edi+68], eax
                mov     eax, [esi+72]   ; @@OUT 9,18,26
                add     eax, [esi+104]
                mov     [edi+36], eax
                mov     eax, [esi+76]   ; @@OUT 25,19,27
                add     eax, [esi+108]
                mov     [edi+100], eax
                mov     eax, [esi+80]   ; @@OUT 5,20,28
                add     eax, [esi+112]
                mov     [edi+20], eax
                mov     eax, [esi+84]   ; @@OUT 21,21,29
                add     eax, [esi+116]
                mov     [edi+84], eax
                mov     eax, [esi+88]   ; @@OUT 13,22,30
                add     eax, [esi+120]
                mov     [edi+52], eax
                mov     eax, [esi+92]   ; @@OUT 29,23,31
                add     eax, [esi+124]
                mov     [edi+116], eax
                mov     eax, [esi+96]   ; @@OUT 3,24,20
                add     eax, [esi+80]
                mov     [edi+12], eax
                mov     eax, [esi+100]  ; @@OUT 19,25,21
                add     eax, [esi+84]
                mov     [edi+76], eax
                mov     eax, [esi+104]  ; @@OUT 11,26,22
                add     eax, [esi+88]
                mov     [edi+44], eax
                mov     eax, [esi+108]  ; @@OUT 27,27,23
                add     eax, [esi+92]
                mov     [edi+108], eax
                mov     eax, [esi+112]  ; @@OUT 7,28,18
                add     eax, [esi+72]
                mov     [edi+28], eax
                mov     eax, [esi+116]  ; @@OUT 23,29,19
                add     eax, [esi+76]
                mov     [edi+92], eax
                mov     eax, [esi+120]  ; @@OUT 15,30,17
                add     eax, [esi+68]
                mov     [edi+60], eax
                mov     eax, [esi+124]  ; @@OUT 31,31,-
                mov     [edi+124], eax
                retn


; =============== S U B R O U T I N E =======================================


mp3_dct32_shift_1:
                mov     eax, [esi+124]  ; mp3_dct32_macro macro rate_shift ; rate_shift = 1
                add     [esi], eax      ; @@BF macro a,b,sign,cos,shift
                                        ; @@need_a equ (rate_shift EQ 0) or (a LT 16) ; a = 0
                                        ; @@need_b equ (rate_shift EQ 0) or (b LT 16) ; b = 31
                                        ; IF @@need_a AND @@need_b ; rate_shift = 0
                                        ;    mov eax,dword ptr [esi+a*4]
                                        ;    mov edx,dword ptr [esi+b*4]
                                        ;    add dword ptr [esi+a*4],edx
                                        ; ELSEIF @@need_a
                                        ;    mov eax,dword ptr [esi+b*4]
                                        ;    add dword ptr [esi+a*4],eax
                                        ;
                                        ; @@BF 0,31,+,COS0_0,1
                mov     eax, [esi+64]   ; @@BF 15,16,+,COS0_15,5
                add     [esi+60], eax
                mov     eax, [esi]      ; @@BF 0,15,+,COS1_0,1
                mov     edx, [esi+60]
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 404F4672h  ; COS1_0
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+96]   ; skip @@BF 16,31,-,COS1_0,1
                                        ; @@BF 7,24,+,COS0_7,1
                add     [esi+28], eax
                mov     eax, [esi+92]   ; @@BF 8,23,+,COS0_8,1
                add     [esi+32], eax
                mov     eax, [esi+28]   ; @@BF 7,8,+,COS1_7,4
                mov     edx, [esi+32]
                add     [esi+28], edx
                sub     eax, edx
                shl     eax, 4
                mov     edx, 519E4E04h  ; COS1_7
                imul    edx
                mov     [esi+32], edx
                mov     eax, [esi]      ; skip @@BF 23,24,-,COS1_7,4
                                        ; @@BF 0,7,+,COS2_0,1
                mov     edx, [esi+28]
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4140FB46h  ; COS2_0
                imul    edx
                mov     [esi+28], edx
                mov     eax, [esi+32]   ; @@BF 8,15,-,COS2_0,1
                mov     edx, [esi+60]
                add     [esi+32], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BEBF04BAh ; -COS2_0
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+112]  ; skip @@BF 16,23,+,COS2_0,1
                                        ;      @@BF 24,31,-,COS2_0,1
                                        ; @@BF 3,28,+,COS0_3,1
                add     [esi+12], eax
                mov     eax, [esi+76]   ; @@BF 12,19,+,COS0_12,2
                add     [esi+48], eax
                mov     eax, [esi+12]   ; @@BF 3,12,+,COS1_3,1
                mov     edx, [esi+48]
                add     [esi+12], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 52CB0E63h
                imul    edx
                mov     [esi+48], edx
                mov     eax, [esi+108]  ; @@BF 4,27,+,COS0_4,1
                add     [esi+16], eax
                mov     eax, [esi+80]   ; @@BF 11,20,+,COS0_11,2
                add     [esi+44], eax
                mov     eax, [esi+16]   ; @@BF 4,11,+,COS1_4,1
                mov     edx, [esi+44]
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 64E2402Eh  ; COS1_4
                imul    edx
                mov     [esi+44], edx
                mov     eax, [esi+12]   ; @@BF 3,4,+,COS2_3,3
                mov     edx, [esi+16]
                add     [esi+12], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 52036742h
                imul    edx
                mov     [esi+16], edx
                mov     eax, [esi+44]   ; @@BF 11,12,-,COS2_3,3
                mov     edx, [esi+48]
                add     [esi+44], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 0ADFC98BEh ; -COS2_3
                imul    edx
                mov     [esi+48], edx
                mov     eax, [esi]      ; @@BF 0,3,+,COS3_0,1
                mov     edx, [esi+12]
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4545E9F0h
                imul    edx
                mov     [esi+12], edx
                mov     eax, [esi+16]   ; @@BF 4,7,-,COS3_0,1
                mov     edx, [esi+28]
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BABA1610h
                imul    edx
                mov     [esi+28], edx
                mov     eax, [esi+32]   ; @@BF 8,11,+,COS3_0,1
                mov     edx, [esi+44]
                add     [esi+32], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4545E9F0h
                imul    edx
                mov     [esi+44], edx
                mov     eax, [esi+48]   ; @@BF 12,15,-,COS3_0,1
                mov     edx, [esi+60]
                add     [esi+48], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BABA1610h ; -COS3_0
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+120]  ; @@BF 1,30,+,COS0_1,1
                add     [esi+4], eax
                mov     eax, [esi+68]   ; @@BF 14,17,+,COS0_14,3
                add     [esi+56], eax
                mov     eax, [esi+4]    ; @@BF 1,14,+,COS1_1,1
                mov     edx, [esi+56]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 42E13C10h
                imul    edx
                mov     [esi+56], edx
                mov     eax, [esi+100]  ; @@BF 6,25,+,COS0_6,1
                add     [esi+24], eax
                mov     eax, [esi+88]   ; @@BF 9,22,+,COS0_9,1
                add     [esi+36], eax
                mov     eax, [esi+24]   ; @@BF 6,9,+,COS1_6,2
                mov     edx, [esi+36]
                add     [esi+24], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 6E3C92C2h  ; +COS1_6
                imul    edx
                mov     [esi+36], edx
                mov     eax, [esi+4]    ; @@BF 1,6,+,COS2_1,1
                mov     edx, [esi+24]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4CF8DE88h
                imul    edx
                mov     [esi+24], edx
                mov     eax, [esi+36]   ; @@BF 9,14,-,COS2_1,1
                mov     edx, [esi+56]
                add     [esi+36], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0B3072178h ; -COS2_1
                imul    edx
                mov     [esi+56], edx
                mov     eax, [esi+116]  ; @@BF 2,29,+,COS0_2,1
                add     [esi+8], eax
                mov     eax, [esi+72]   ; @@BF 13,18,+,COS0_13,3
                add     [esi+52], eax
                mov     eax, [esi+8]    ; @@BF 2,13,+,COS1_2,1
                mov     edx, [esi+52]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 48919F45h
                imul    edx
                mov     [esi+52], edx
                mov     eax, [esi+104]  ; @@BF 5,26,+,COS0_5,1
                add     [esi+20], eax
                mov     eax, [esi+84]   ; @@BF 10,21,+,COS0_10,1
                add     [esi+40], eax
                mov     eax, [esi+20]   ; @@BF 5,10,+,COS1_5,2
                mov     edx, [esi+40]
                add     [esi+20], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 43E224AAh
                imul    edx
                mov     [esi+40], edx
                mov     eax, [esi+8]    ; @@BF 2,5,+,COS2_2,1
                mov     edx, [esi+20]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 73326BBFh  ; COS2_2
                imul    edx
                mov     [esi+20], edx
                mov     eax, [esi+40]   ; @@BF 10,13,-,COS2_2,1
                mov     edx, [esi+52]
                add     [esi+40], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 8CCD9441h  ; -COS2_2
                imul    edx
                mov     [esi+52], edx
                mov     eax, [esi+4]    ; @@BF 1,2,+,COS3_1,2
                mov     edx, [esi+8]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 539EBA46h
                imul    edx
                mov     [esi+8], edx
                mov     eax, [esi+20]   ; @@BF 5,6,-,COS3_1,2
                mov     edx, [esi+24]
                add     [esi+20], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 0AC6145BAh
                imul    edx
                mov     [esi+24], edx
                mov     eax, [esi+36]   ; IF rate_shift LT 2
                                        ; @@BF 9,10,+,COS3_1,2
                mov     edx, [esi+40]
                add     [esi+36], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 539EBA46h  ; +COS3_1
                imul    edx
                mov     [esi+40], edx
                mov     eax, [esi+52]   ; @@BF 13,14,-,COS3_1,2
                mov     edx, [esi+56]
                add     [esi+52], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 0AC6145BAh ; -COS3_1
                imul    edx
                mov     [esi+56], edx   ; ENDIF
                mov     eax, [esi]      ; @@BF1 macro a, b, c, d
                                        ;   @@BF  a, b,+,COS4_0, 1
                                        ;   @@BF  c, d,-,COS4_0, 1
                                        ;   @@ADD c, d
                                        ;  endm
                                        ; @@BF1 0,1,2,3
                mov     edx, [esi+4]    ; @@BF 0,1,+,COS4_0,1
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+4], edx
                mov     eax, [esi+8]    ; @@BF 2,3,+,COS4_0,1
                mov     edx, [esi+12]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+12], edx
                mov     eax, [esi+12]   ; @@ADD 2,3
                add     [esi+8], eax
                mov     eax, [esi+16]   ; @@BF2 macro a, b, c, d
                                        ;   @@BF  a, b,+,COS4_0, 1
                                        ;   @@BF  c, d,-,COS4_0, 1
                                        ;   @@ADD c, d
                                        ;   @@ADD a, c
                                        ;   @@ADD c, b
                                        ;   @@ADD b, d
                                        ;  endm
                                        ; @@BF2 4,5,6,7
                mov     edx, [esi+20]   ; @@BF 4,5,+,COS4_0,1
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah  ; +COS4_0
                imul    edx
                mov     [esi+20], edx
                mov     eax, [esi+24]   ; @@BF 6,7,-,COS4_0,1
                mov     edx, [esi+28]
                add     [esi+24], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h ; -COS4_0
                imul    edx
                mov     [esi+28], edx
                mov     eax, [esi+28]   ; @@ADD macro dst,src
                                        ;   IF (rate_shift EQ 0) or (dst LT 16)
                                        ;    ;tab[a] += tab[b]
                                        ;    mov  eax,dword ptr [esi+src*4]
                                        ;    add  dword ptr [esi+dst*4],eax
                                        ;   ENDIF
                                        ;  endm
                                        ; @@ADD 6,7
                add     [esi+24], eax
                mov     eax, [esi+24]   ; @@ADD 4,6
                add     [esi+16], eax
                mov     eax, [esi+20]   ; @@ADD 6,5
                add     [esi+24], eax
                mov     eax, [esi+28]   ; @@ADD 5,7
                add     [esi+20], eax
                mov     eax, [esi+32]   ; IF rate_shift LT 2
                                        ; @@BF1 8,9,10,11
                mov     edx, [esi+36]
                add     [esi+32], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+36], edx
                mov     eax, [esi+40]
                mov     edx, [esi+44]
                add     [esi+40], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+44], edx
                mov     eax, [esi+44]
                add     [esi+40], eax
                mov     eax, [esi+48]   ; @@BF2 12,13,14,15
                mov     edx, [esi+52]
                add     [esi+48], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+52], edx
                mov     eax, [esi+56]
                mov     edx, [esi+60]
                add     [esi+56], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+60]
                add     [esi+56], eax
                mov     eax, [esi+56]
                add     [esi+48], eax
                mov     eax, [esi+52]
                add     [esi+56], eax
                mov     eax, [esi+60]
                add     [esi+52], eax
                mov     eax, [esi]      ; @@OUT macro dst,src1,src2
                                        ; IF ((dst AND ((1 SHL rate_shift)-1)) EQ 0)
                                        ;    mov eax,dword ptr [esi+src1*4]
                                        ;    IFDIFI <src2>,<->
                                        ;      add eax,dword ptr [esi+src2*4]
                                        ;    ENDIF
                                        ;    IF SYNTH32
                                        ;       mov dword ptr [edi+dst*4],eax
                                        ;       IF (LONG_WINDOW EQ 0)
                                        ;          mov dword ptr [edi+dst*4+512*4],eax
                                        ;       ENDIF
                                        ;    ELSE
                                        ;        ......
                                        ;    ENDIF
                                        ; @@OUT 0,0,-
                mov     [edi], eax
                mov     eax, [esi+4]    ; @@OUT 16,1,-
                mov     [edi+64], eax
                mov     eax, [esi+8]    ; @@OUT 8,2,-
                mov     [edi+32], eax
                mov     eax, [esi+12]   ; @@OUT 24,3,-
                mov     [edi+96], eax
                mov     eax, [esi+16]   ; @@OUT 4,4,-
                mov     [edi+16], eax
                mov     eax, [esi+20]   ; @@OUT 20,5,-
                mov     [edi+80], eax
                mov     eax, [esi+24]   ; @@OUT 12,6,-
                mov     [edi+48], eax
                mov     eax, [esi+28]   ; @@OUT 28,7,-
                mov     [edi+112], eax
                mov     eax, [esi+32]   ; @@OUT 2,8,12
                add     eax, [esi+48]
                mov     [edi+8], eax
                mov     eax, [esi+36]   ; @@OUT 18,9,13
                add     eax, [esi+52]
                mov     [edi+72], eax
                mov     eax, [esi+40]   ; @@OUT 10,10,14
                add     eax, [esi+56]
                mov     [edi+40], eax
                mov     eax, [esi+44]   ; @@OUT 26,11,15
                add     eax, [esi+60]
                mov     [edi+104], eax
                mov     eax, [esi+48]   ; @@OUT 6,12,10
                add     eax, [esi+40]
                mov     [edi+24], eax
                mov     eax, [esi+52]   ; @@OUT 22,13,11
                add     eax, [esi+44]
                mov     [edi+88], eax
                mov     eax, [esi+56]   ; @@OUT 14,14,9
                add     eax, [esi+36]
                mov     [edi+56], eax
                mov     eax, [esi+60]   ; @@OUT 30,15,-
                mov     [edi+120], eax
                retn


; =============== S U B R O U T I N E =======================================


mp3_dct32_shift_2:
                mov     eax, [esi+124]  ; mp3_dct32_macro macro rate_shift ; rate_shift = 2
                add     [esi], eax      ; @@BF macro a,b,sign,cos,shift
                                        ; @@need_a equ (rate_shift EQ 0) or (a LT 16) ; a = 0
                                        ; @@need_b equ (rate_shift EQ 0) or (b LT 16) ; b = 31
                                        ; IF @@need_a AND @@need_b ; rate_shift = 0
                                        ;    mov eax,dword ptr [esi+a*4]
                                        ;    mov edx,dword ptr [esi+b*4]
                                        ;    add dword ptr [esi+a*4],edx
                                        ; ELSEIF @@need_a
                                        ;    mov eax,dword ptr [esi+b*4]
                                        ;    add dword ptr [esi+a*4],eax
                                        ;
                                        ; @@BF 0,31,+,COS0_0,1
                mov     eax, [esi+64]   ; @@BF 15,16,+,COS0_15,5
                add     [esi+60], eax
                mov     eax, [esi]      ; @@BF 0,15,+,COS1_0,1
                mov     edx, [esi+60]
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 404F4672h  ; COS1_0
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+96]   ; @@BF 7,24,+,COS0_7,1
                add     [esi+28], eax
                mov     eax, [esi+92]   ; @@BF 8,23,+,COS0_8,1
                add     [esi+32], eax
                mov     eax, [esi+28]   ; @@BF 7,8,+,COS1_7,4
                mov     edx, [esi+32]
                add     [esi+28], edx
                sub     eax, edx
                shl     eax, 4
                mov     edx, 519E4E04h  ; COS1_7
                imul    edx
                mov     [esi+32], edx
                mov     eax, [esi]      ; @@BF 0,7,+,COS2_0,1
                mov     edx, [esi+28]
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4140FB46h  ; COS2_0
                imul    edx
                mov     [esi+28], edx
                mov     eax, [esi+32]   ; @@BF 8,15,-,COS2_0,1
                mov     edx, [esi+60]
                add     [esi+32], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BEBF04BAh
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+112]  ; @@BF 3,28,+,COS0_3,1
                add     [esi+12], eax
                mov     eax, [esi+76]   ; @@BF 12,19,+,COS0_12,2
                add     [esi+48], eax
                mov     eax, [esi+12]   ; @@BF 3,12,+,COS1_3,1
                mov     edx, [esi+48]
                add     [esi+12], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 52CB0E63h  ; COS1_3
                imul    edx
                mov     [esi+48], edx
                mov     eax, [esi+108]  ; @@BF 4,27,+,COS0_4,1
                add     [esi+16], eax
                mov     eax, [esi+80]   ; @@BF 11,20,+,COS0_11,2
                add     [esi+44], eax
                mov     eax, [esi+16]   ; @@BF 4,11,+,COS1_4,1
                mov     edx, [esi+44]
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 64E2402Eh
                imul    edx
                mov     [esi+44], edx
                mov     eax, [esi+12]   ; @@BF 3,4,+,COS2_3,3
                mov     edx, [esi+16]
                add     [esi+12], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 52036742h
                imul    edx
                mov     [esi+16], edx
                mov     eax, [esi+44]   ; @@BF 11,12,-,COS2_3,3
                mov     edx, [esi+48]
                add     [esi+44], edx
                sub     eax, edx
                shl     eax, 3
                mov     edx, 0ADFC98BEh ; -COS2_3
                imul    edx
                mov     [esi+48], edx
                mov     eax, [esi]      ; @@BF 0,3,+,COS3_0,1
                mov     edx, [esi+12]
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4545E9F0h
                imul    edx
                mov     [esi+12], edx
                mov     eax, [esi+16]   ; @@BF 4,7,-,COS3_0,1
                mov     edx, [esi+28]
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BABA1610h
                imul    edx
                mov     [esi+28], edx
                mov     eax, [esi+32]   ; @@BF 8,11,+,COS3_0,1
                mov     edx, [esi+44]
                add     [esi+32], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4545E9F0h
                imul    edx
                mov     [esi+44], edx
                mov     eax, [esi+48]   ; @@BF 12,15,-,COS3_0,1
                mov     edx, [esi+60]
                add     [esi+48], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0BABA1610h
                imul    edx
                mov     [esi+60], edx
                mov     eax, [esi+120]  ; @@BF 1,30,+,COS0_1,1
                add     [esi+4], eax
                mov     eax, [esi+68]   ; @@BF 14,17,+,COS0_14,3
                add     [esi+56], eax
                mov     eax, [esi+4]    ; @@BF 1,14,+,COS1_1,1
                mov     edx, [esi+56]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 42E13C10h  ; COS1_1
                imul    edx
                mov     [esi+56], edx
                mov     eax, [esi+100]  ; @@BF 6,25,+,COS0_6,1
                add     [esi+24], eax
                mov     eax, [esi+88]   ; @@BF 9,22,+,COS0_9,1
                add     [esi+36], eax
                mov     eax, [esi+24]   ; @@BF 6,9,+,COS1_6,2
                mov     edx, [esi+36]
                add     [esi+24], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 6E3C92C2h
                imul    edx
                mov     [esi+36], edx
                mov     eax, [esi+4]    ; @@BF 1,6,+,COS2_1,1
                mov     edx, [esi+24]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 4CF8DE88h  ; COS2_1
                imul    edx
                mov     [esi+24], edx
                mov     eax, [esi+36]   ; @@BF 9,14,-,COS2_1,1
                mov     edx, [esi+56]
                add     [esi+36], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0B3072178h ; -COS2_1
                imul    edx
                mov     [esi+56], edx
                mov     eax, [esi+116]  ; @@BF 2,29,+,COS0_2,1
                add     [esi+8], eax
                mov     eax, [esi+72]   ; @@BF 13,18,+,COS0_13,3
                add     [esi+52], eax
                mov     eax, [esi+8]    ; @@BF 2,13,+,COS1_2,1
                mov     edx, [esi+52]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 48919F45h
                imul    edx
                mov     [esi+52], edx
                mov     eax, [esi+104]  ; @@BF 5,26,+,COS0_5,1
                add     [esi+20], eax
                mov     eax, [esi+84]   ; @@BF 10,21,+,COS0_10,1
                add     [esi+40], eax
                mov     eax, [esi+20]   ; @@BF 5,10,+,COS1_5,2
                mov     edx, [esi+40]
                add     [esi+20], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 43E224AAh
                imul    edx
                mov     [esi+40], edx
                mov     eax, [esi+8]    ; @@BF 2,5,+,COS2_2,1
                mov     edx, [esi+20]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 73326BBFh  ; COS2_2
                imul    edx
                mov     [esi+20], edx
                mov     eax, [esi+40]   ; @@BF 10,13,-,COS2_2,1
                mov     edx, [esi+52]
                add     [esi+40], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 8CCD9441h  ; -COS2_2
                imul    edx
                mov     [esi+52], edx
                mov     eax, [esi+4]    ; @@BF 1,2,+,COS3_1,2
                mov     edx, [esi+8]
                add     [esi+4], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 539EBA46h  ; COS3_1
                imul    edx
                mov     [esi+8], edx
                mov     eax, [esi+20]   ; @@BF 5,6,-,COS3_1,2
                mov     edx, [esi+24]
                add     [esi+14h], edx
                sub     eax, edx
                shl     eax, 2
                mov     edx, 0AC6145BAh ; -COS3_1
                imul    edx
                mov     [esi+24], edx
                mov     eax, [esi]      ; @@BF1 macro a, b, c, d
                                        ;   @@BF  a, b,+,COS4_0, 1
                                        ;   @@BF  c, d,-,COS4_0, 1
                                        ;   @@ADD c, d
                                        ;  endm
                                        ; @@BF1 0,1,2,3
                mov     edx, [esi+4]    ; @@BF 0,1,+,COS4_0,1
                add     [esi], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah
                imul    edx
                mov     [esi+4], edx
                mov     eax, [esi+8]    ; @@BF 2,3,-,COS4_0,1
                mov     edx, [esi+12]
                add     [esi+8], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h
                imul    edx
                mov     [esi+12], edx
                mov     eax, [esi+12]   ; @@ADD 2,3
                add     [esi+8], eax
                mov     eax, [esi+16]   ; @@BF2 macro a, b, c, d
                                        ;   @@BF  a, b,+,COS4_0, 1
                                        ;   @@BF  c, d,-,COS4_0, 1
                                        ;   @@ADD c, d
                                        ;   @@ADD a, c
                                        ;   @@ADD c, b
                                        ;   @@ADD b, d
                                        ;  endm
                                        ; @@BF2 4,5,6,7
                mov     edx, [esi+20]   ; @@BF 4,5,+,COS4_0,1
                add     [esi+16], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 5A82799Ah  ; COS4_0
                imul    edx
                mov     [esi+20], edx
                mov     eax, [esi+24]   ; @@BF 6,7,-,COS4_0,1
                mov     edx, [esi+28]
                add     [esi+18h], edx
                sub     eax, edx
                shl     eax, 1
                mov     edx, 0A57D8666h ; -COS4_0
                imul    edx
                mov     [esi+28], edx
                mov     eax, [esi+28]   ; @@ADD 6,7
                add     [esi+24], eax
                mov     eax, [esi+24]   ; @@ADD 4,6
                add     [esi+16], eax
                mov     eax, [esi+20]   ; @@ADD 6,5
                add     [esi+24], eax
                mov     eax, [esi+28]   ; @@ADD 5,7
                add     [esi+20], eax
                mov     eax, [esi]      ; @@OUT macro dst,src1,src2
                                        ; IF ((dst AND ((1 SHL rate_shift)-1)) EQ 0)
                                        ;    mov eax,dword ptr [esi+src1*4]
                                        ;    IFDIFI <src2>,<->
                                        ;      add eax,dword ptr [esi+src2*4]
                                        ;    ENDIF
                                        ;    IF SYNTH32
                                        ;       mov dword ptr [edi+dst*4],eax
                                        ;       IF (LONG_WINDOW EQ 0)
                                        ;          mov dword ptr [edi+dst*4+512*4],eax
                                        ;       ENDIF
                                        ;    ELSE
                                        ;        ......
                                        ;    ENDIF
                                        ; @@OUT 0,0,-
                mov     [edi], eax
                mov     eax, [esi+4]    ; @@OUT 16,1,-
                mov     [edi+64], eax
                mov     eax, [esi+8]    ; @@OUT 8,2,-
                mov     [edi+32], eax
                mov     eax, [esi+12]   ; @@OUT 24,3,-
                mov     [edi+96], eax
                mov     eax, [esi+16]   ; @@OUT 4,4,-
                mov     [edi+16], eax
                mov     eax, [esi+20]   ; @@OUT 20,5,-
                mov     [edi+80], eax
                mov     eax, [esi+24]   ; @@OUT 12,6,-
                mov     [edi+48], eax
                mov     eax, [esi+28]   ; @@OUT 28,7,-
                mov     [edi+112], eax
                retn


; =============== S U B R O U T I N E =======================================


synth_16bit_shift_0_fast:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 0,0,1
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_0
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_16bit_shift_0_fast ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_16bit_shift_0_fast:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h       ; 1FFh-1Fh
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h       ; @win1,1FFh-1Fh-20h
                and     eax, 420h       ; and eax,20h+(1 shl 10) ; bit5 and channel
                lea     esi, [eax+10h]  ; @@syn1,[eax+10h]
                lea     edi, [eax+30h]  ; @@syn2,[eax+30h]
                neg     ebp
                and     ebp, 1C0h       ; @win1,1FFh-1Fh-20h
                mov     ecx, [mp3_curr_syn_dst] ; @@dst,dword ptr [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 20002000h  ; mov @@sum,(8000h SHL (@@out_shift))+(1 SHL (@@out_shift-1))
                                        ; @@out_shift equ (OUT_SHIFT_fast+(8*force_8bit))
                                        ; out_shift = 14
                mov     edx, [mp3_synth_buf+esi*4] ; @@SUM8 macro sum,win,ww,syn
                                        ; @@SUM8 @@sum,@@win1,0,@@syn1
                                        ; IRP nn,0,1,2,3,4,5,6,7
                                        ; mov edx,dword ptr [mp3_synth_buf+syn*4+(nn*64*4)]
                                        ; movsx eax,word ptr [mp3_synth_win+win*2+(nn*64*2)+ww*2]
                                        ; imul eax,edx
                                        ; add sum,eax
                movsx   eax, word [mp3_synth_win+ebp*2] ; nn=0, ww=0
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+esi*4]
                movsx   eax, word [(mp3_synth_win+80h)+ebp*2] ; nn=1, ww=0
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                movsx   eax, word [(mp3_synth_win+100h)+ebp*2] ; nn=2
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                movsx   eax, word [(mp3_synth_win+180h)+ebp*2] ; nn=3
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                movsx   eax, word [(mp3_synth_win+200h)+ebp*2] ; nn=4
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                movsx   eax, word [(mp3_synth_win+280h)+ebp*2] ; nn=5
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                movsx   eax, word [(mp3_synth_win+300h)+ebp*2] ; nn=6
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                movsx   eax, word [(mp3_synth_win+380h)+ebp*2] ; nn=7
                imul    eax, edx
                add     ebx, eax
                mov     edx, [mp3_synth_buf+edi*4] ; @@SUM8 @@sum,@@win1,32, @@syn2
                movsx   eax, word [(mp3_synth_win+40h)+ebp*2] ; nn=0, ww=32
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                movsx   eax, word [(mp3_synth_win+0C0h)+ebp*2] ; nn=1, ww=32
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                movsx   eax, word [(mp3_synth_win+140h)+ebp*2] ; nn=2
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                movsx   eax, word [(mp3_synth_win+1C0h)+ebp*2] ; nn=3
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                movsx   eax, word [(mp3_synth_win+240h)+ebp*2] ; nn=4
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                movsx   eax, word [(mp3_synth_win+2C0h)+ebp*2] ; nn=5
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                movsx   eax, word [(mp3_synth_win+340h)+ebp*2] ; nn=6
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                movsx   eax, word [(mp3_synth_win+3C0h)+ebp*2] ; nn=7
                imul    eax, edx
                add     ebx, eax
                cmp     ebx, 40000000h  ; cmp @@sum,10000h SHL (@@out_shift) ; out_shift = 14
                jnb     short .sat
                sar     ebx, 14         ; sar @@sum,(@@out_shift)
                sub     ebx, 8000h      ; sub @@sum,8000h ; make 16bit signed

.sat_back:
                mov     [ecx], bx       ; mov word ptr [@@dst],@@sum_16bit
                add     ecx, [mp3_samples_dst_step]
                inc     esi             ; inc @@syn1
                dec     edi             ; dec @@syn2
                inc     ebp             ; inc @@win1
                test    ebp, 1Fh        ; IF LONG_WINDOW
                jnz     .samples_lop   ; test @@win1,1Fh
                retn

.sat:
                sar     ebx, 31         ; sar @@sum,31 ; FFFFFFFFh,00000000h
                xor     ebx, 7FFFh      ; xor @@sum,7fffh ; FFFF8000h,00007FFFh (signed 16bit)
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4] ; IF SYNTH32
                lea     edi, [esi+2048] ; [esi+512*4]
                mov     ecx, 18         ; (12h*4)/4
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_16bit_shift_1_fast:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 0,1,1
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub	dword [mp3_synth_index+edx*4], 32
                shl     edx, 10
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_1 ; mp3_dct32_shift_&rate_shift
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_16bit_shift_1_fast ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_16bit_shift_1_fast:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h       ; 1FFh-1Fh
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h
                and     eax, 420h
                lea     esi, [eax+10h]
                lea     edi, [eax+30h]
                neg     ebp
                and     ebp, 1C0h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 20002000h  ; mov @@sum,(8000h SHL (@@out_shift))+(1 SHL (@@out_shift-1))
                                        ; @@out_shift equ (OUT_SHIFT_fast+(8*force_8bit))
                                        ; out_shift = 14
                mov     edx, [mp3_synth_buf+esi*4] ; @@SUM8 macro sum,win,ww,syn
                                        ; @@SUM8 @@sum,@@win1,0,@@syn1
                                        ; IRP nn,0,1,2,3,4,5,6,7
                                        ; mov edx,dword ptr [mp3_synth_buf+syn*4+(nn*64*4)]
                                        ; movsx eax,word ptr [mp3_synth_win+win*2+(nn*64*2)+ww*2]
                                        ; imul eax,edx
                                        ; add sum,eax
                movsx   eax, word [mp3_synth_win+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+esi*4] ; nn=1
                movsx   eax, word [(mp3_synth_win+80h)+ebp*2] ; ww=0
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                movsx   eax, word [(mp3_synth_win+100h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                movsx   eax, word [(mp3_synth_win+180h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+esi*4] ; nn=4
                movsx   eax, word [(mp3_synth_win+200h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                movsx   eax, word [(mp3_synth_win+280h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                movsx   eax, word [(mp3_synth_win+300h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+esi*4] ; nn=7
                movsx   eax, word [(mp3_synth_win+380h)+ebp*2] ; ww=0
                imul    eax, edx
                add     ebx, eax
                mov     edx, [mp3_synth_buf+edi*4]
                movsx   eax, word [(mp3_synth_win+40h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                movsx   eax, word [(mp3_synth_win+0C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+edi*4] ; nn=2, ww=32
                movsx   eax, word [(mp3_synth_win+140h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                movsx   eax, word [(mp3_synth_win+1C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                movsx   eax, word [(mp3_synth_win+240h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                movsx   eax, word [(mp3_synth_win+2C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+edi*4] ; nn=6, ww=32
                movsx   eax, word [(mp3_synth_win+340h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                movsx   eax, word [(mp3_synth_win+3C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                cmp     ebx, 40000000h  ; cmp  @@sum,10000h SHL (@@out_shift)
                jnb     short .sat
                sar     ebx, 14         ; sar @@sum,(@@out_shift)
                sub     ebx, 8000h      ; make 16bit signed

.sat_back:
                mov     [ecx], bx
                add     ecx, [mp3_samples_dst_step]
                add     esi, 2          ; IF rate_shift
                                        ; add  @@syn1,1 shl rate_shift
                sub     edi, 2          ; sub @@syn2,1 shl rate_shift
                add     ebp, 2          ; add @@win1,1 shl rate_shift
                test    ebp, 1Fh        ; IF LONG_WINDOW
                jnz     .samples_lop   ; test @@win1,1fh
                retn

.sat:
                sar     ebx, 31         ; sar @@sum,31 ; FFFFFFFFh,00000000h
                xor     ebx, 7FFFh      ; xor @@sum,7fffh ; FFFF8000h,00007FFFh (signed 16bit)
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048] ; [esi+512*4]
                mov     ecx, 18         ; (12h*4)/4
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_16bit_shift_2_fast:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 0,2,1
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_2 ; mp3_dct32_shift_&rate_shift
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_16bit_shift_2_fast ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fas
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_16bit_shift_2_fast:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h       ; 1FFh-1Fh
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h       ; 1FFh-1Fh-20h
                and     eax, 420h       ; 20h+(1 shl 10)
                lea     esi, [eax+10h]
                lea     edi, [eax+30h]
                neg     ebp
                and     ebp, 1C0h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 20002000h  ; mov @@sum,(8000h SHL (@@out_shift))+(1 SHL (@@out_shift-1))
                                        ; @@out_shift equ (OUT_SHIFT_fast+(8*force_8bit))
                                        ; out_shift = 14
                mov     edx, [mp3_synth_buf+esi*4]
                movsx   eax, word [mp3_synth_win+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+esi*4]
                movsx   eax, word [(mp3_synth_win+80h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                movsx   eax, word [(mp3_synth_win+100h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                movsx   eax, word [(mp3_synth_win+180h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                movsx   eax, word [(mp3_synth_win+200h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                movsx   eax, word [(mp3_synth_win+280h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                movsx   eax, word [(mp3_synth_win+300h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                movsx   eax, word [(mp3_synth_win+380h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [mp3_synth_buf+edi*4]
                movsx   eax, word [(mp3_synth_win+40h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                movsx   eax, word [(mp3_synth_win+0C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                movsx   eax, word [(mp3_synth_win+140h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                movsx   eax, word [(mp3_synth_win+1C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                movsx   eax, word [(mp3_synth_win+240h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                movsx   eax, word [(mp3_synth_win+2C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                movsx   eax, word [(mp3_synth_win+340h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                movsx   eax, word [(mp3_synth_win+3C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                cmp     ebx, 40000000h
                jnb     short .sat
                sar     ebx, 14
                sub     ebx, 8000h      ; make 16bit signed

.sat_back:
                mov     [ecx], bx
                add     ecx, [mp3_samples_dst_step]
                add     esi, 4
                sub     edi, 4
                add     ebp, 4
                test    ebp, 1Fh
                jnz     .samples_lop
                retn

.sat:
                sar     ebx, 31
                xor     ebx, 7FFFh
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048]
                mov     ecx, 18
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_8bit_shift_0_fast:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 1,0,1
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_0 ; mp3_dct32_shift_&rate_shift
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_8bit_shift_0_fast ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_8bit_shift_0_fast:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h       ; 1FFh-1Fh
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h       ; 1FFh-1Fh-20h
                and     eax, 420h       ; 20h+(1 shl 10)
                lea     esi, [eax+10h]
                lea     edi, [eax+30h]
                neg     ebp
                and     ebp, 1C0h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 20200000h  ; mov @@sum,(80h SHL (@@out_shift))+(1 SHL (@@out_shift-1))
                                        ; @@out_shift equ (OUT_SHIFT_fast(8*force_8bit))
                                        ; @@out_shift = 22
                mov     edx, [mp3_synth_buf+esi*4] ; @@SUM8 macro sum,win,ww,syn
                                        ; @@SUM8 @@sum,@@win1,0,@@syn1
                                        ; IRP nn,0,1,2,3,4,5,6,7
                                        ; mov edx,dword ptr [mp3_synth_buf+syn*4+(nn*64*4)]
                                        ; movsx eax,word ptr [mp3_synth_win+win*2+(nn*64*2)+ww*2]
                                        ; imul eax,edx
                                        ; add sum,eax
                movsx   eax, word [mp3_synth_win+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+esi*4] ; nn=1
                movsx   eax, word [(mp3_synth_win+80h)+ebp*2] ; ww=0
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                movsx   eax, word [(mp3_synth_win+100h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                movsx   eax, word [(mp3_synth_win+180h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                movsx   eax, word [(mp3_synth_win+200h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                movsx   eax, word [(mp3_synth_win+280h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                movsx   eax, word [(mp3_synth_win+300h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                movsx   eax, word [(mp3_synth_win+380h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [mp3_synth_buf+edi*4]
                movsx   eax, word [(mp3_synth_win+40h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                movsx   eax, word [(mp3_synth_win+0C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+edi*4] ; nn=2
                movsx   eax, word [(mp3_synth_win+140h)+ebp*2] ; ww=32
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                movsx   eax, word [(mp3_synth_win+1C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                movsx   eax, word [(mp3_synth_win+240h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                movsx   eax, word [(mp3_synth_win+2C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                movsx   eax, word [(mp3_synth_win+340h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                movsx   eax, word [(mp3_synth_win+3C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                cmp     ebx, 40000000h  ; cmp  @@sum,100h SHL (@@out_shift)
                jnb     short .sat
                sar     ebx, 22         ; sar @@sum,(@@out_shift)

.sat_back:
                mov     [ecx], bl       ; mov byte ptr [@@dst],@@sum_8bit
                add     ecx, [mp3_samples_dst_step]
                inc     esi             ; inc @@syn1
                dec     edi             ; dec @@syn2
                inc     ebp             ; inc @@win1
                test    ebp, 1Fh        ; IF LONG_WINDOW
                                        ; test @@win1,1fh
                jnz     .samples_lop
                retn

.sat:                                 
                sar     ebx, 31         ; sar @@sum,31 ; FFFFFFFFh,00000000h
                not     ebx             ; IF force_8bit
                                        ; not @@sum ; 00000000h,FFFFFFFFh (unsigned 8bit)
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048] ; [esi+512*4]
                mov     ecx, 18         ; (12h*4)/4
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_8bit_shift_1_fast:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 1,1,1
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_1 ; mp3_dct32_shift_&rate_shift
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_8bit_shift_1_fast ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_8bit_shift_1_fast:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h
                and     eax, 420h
                lea     esi, [eax+10h]
                lea     edi, [eax+30h]
                neg     ebp
                and     ebp, 1C0h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 20200000h
                mov     edx, [mp3_synth_buf+esi*4]
                movsx   eax, word [mp3_synth_win+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+esi*4]
                movsx   eax, word [(mp3_synth_win+80h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                movsx   eax, word [(mp3_synth_win+100h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                movsx   eax, word [(mp3_synth_win+180h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                movsx   eax, word [(mp3_synth_win+200h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                movsx   eax, word [(mp3_synth_win+280h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                movsx   eax, word [(mp3_synth_win+300h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                movsx   eax, word [(mp3_synth_win+380h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [mp3_synth_buf+edi*4]
                movsx   eax, word [(mp3_synth_win+40h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                movsx   eax, word [(mp3_synth_win+0C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                movsx   eax, word [(mp3_synth_win+140h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                movsx   eax, word [(mp3_synth_win+1C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                movsx   eax, word [(mp3_synth_win+240h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                movsx   eax, word [(mp3_synth_win+2C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                movsx   eax, word [(mp3_synth_win+340h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                movsx   eax, word [(mp3_synth_win+3C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                cmp     ebx, 40000000h
                jnb     short .sat
                sar     ebx, 22

.sat_back:
                mov     [ecx], bl
                add     ecx, [mp3_samples_dst_step]
                add     esi, 2
                sub     edi, 2
                add     ebp, 2
                test    ebp, 1Fh
                jnz     .samples_lop
                retn

.sat:
                sar     ebx, 31
                not     ebx
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048]
                mov     ecx, 18
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_8bit_shift_2_fast:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 1,2,1
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_2 ; mp3_dct32_shift_&rate_shift
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_8bit_shift_2_fast ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_8bit_shift_2_fast:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h
                and     eax, 420h
                lea     esi, [eax+10h]
                lea     edi, [eax+30h]
                neg     ebp
                and     ebp, 1C0h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 20200000h
                mov     edx, [mp3_synth_buf+esi*4]
                movsx   eax, word [mp3_synth_win+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+esi*4]
                movsx   eax, word [(mp3_synth_win+80h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                movsx   eax, word [(mp3_synth_win+100h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                movsx   eax, word [(mp3_synth_win+180h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                movsx   eax, word [(mp3_synth_win+200h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                movsx   eax, word [(mp3_synth_win+280h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                movsx   eax, word [(mp3_synth_win+300h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                movsx   eax, word [(mp3_synth_win+380h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [mp3_synth_buf+edi*4]
                movsx   eax, word [(mp3_synth_win+40h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                movsx   eax, word [(mp3_synth_win+0C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                movsx   eax, word [(mp3_synth_win+140h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                movsx   eax, word [(mp3_synth_win+1C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                movsx   eax, word [(mp3_synth_win+240h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                movsx   eax, word [(mp3_synth_win+2C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                movsx   eax, word [(mp3_synth_win+340h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                movsx   eax, word [(mp3_synth_win+3C0h)+ebp*2]
                imul    eax, edx
                add     ebx, eax
                cmp     ebx, 40000000h
                jnb     short .sat
                sar     ebx, 22

.sat_back:
                mov     [ecx], bl
                add     ecx, [mp3_samples_dst_step]
                add     esi, 4
                sub     edi, 4
                add     ebp, 4
                test    ebp, 1Fh
                jnz     .samples_lop
                retn

.sat:
                sar     ebx, 31
                not     ebx
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048]
                mov     ecx, 18
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_16bit_shift_0_slow:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10         ; channel*1024
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_0 ; mp3_dct32_shift_&rate_shift
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_dct32
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_synth
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_16bit_shift_0_slow
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_synth
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_synth_dct
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_16bit_shift_0_slow:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h       ; 1FFh-1Fh
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax        ; mov @@win1,eax
                and     ebp, 1C0h       ; and @@win1,1FFh-1Fh-20h
                and     eax, 420h       ; and eax,20h+(1 shl 10) ; bit5, and channel
                lea     esi, [eax+10h]  ; lea @@syn1,[eax+10h]
                lea     edi, [eax+30h]  ; lea @@syn2,[eax+30h]
                neg     ebp
                and     ebp, 1C0h       ; and @@win1,1FFh-1Fh-20h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 100010h    ; mov @@sum,(8000h SHL (@@out_shift))+(1 SHL (@@out_shift-1))
                                        ; @@out_shift = 5

.SUM8_@:                                ; @@SUM8 macro sum,win,ww,syn
                mov     edx, [mp3_synth_buf+esi*4] ; IRP nn,0,1,2,3,4,5,6,7
                                        ; @@SUM8 @@sum,@@win1,0, @@syn1
                mov     eax, [mp3_synth_win+ebp*4] ; [mp3_synth_buf+syn*4+(nn*64*4)]
                imul    edx             ; [mp3_synth_win+win*4+(nn*64*4)+ww*4]
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+esi*4]
                mov     eax, [(mp3_synth_win+100h)+ebp*4]
                imul    edx
                add     ebx, edx        ; add sum,edx
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                mov     eax, [(mp3_synth_win+200h)+ebp*4] ; [mp3_synth_win+win*4+(nn*64*4)+ww*4]
                imul    edx             ; 64bit = 32bit * 32bit
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                mov     eax, [(mp3_synth_win+300h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                mov     eax, [(mp3_synth_win+400h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                mov     eax, [(mp3_synth_win+500h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                mov     eax, [(mp3_synth_win+600h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                mov     eax, [(mp3_synth_win+700h)+ebp*4]
                imul    edx
                add     ebx, edx

.skippp:                               ; @@SUM8 macro sum,win,ww,syn
                mov     edx, [mp3_synth_buf+edi*4] ; @@SUM8 @@sum,@@win1,32,@@syn2
                                        ; [mp3_synth_buf+syn*4+(nn*64*4)]
                mov     eax, [(mp3_synth_win+80h)+ebp*4] ; [mp3_synth_win+win*4+(nn*64*4)+ww*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                mov     eax, [(mp3_synth_win+180h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                mov     eax, [(mp3_synth_win+280h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                mov     eax, [(mp3_synth_win+380h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                mov     eax, [(mp3_synth_win+480h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                mov     eax, [(mp3_synth_win+580h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                mov     eax, [(mp3_synth_win+680h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                mov     eax, [(mp3_synth_win+780h)+ebp*4]
                imul    edx
                add     ebx, edx
                cmp     ebx, 200000h    ; cmp @@sum,10000h SHL (@@out_shift)
                jnb     short .sat
                sar     ebx, 5          ; sar @@sum,(@@out_shift)
                sub     ebx, 8000h      ; make 16bit signed

.sat_back:
                mov     [ecx], bx
                add     ecx, [mp3_samples_dst_step]
                inc     esi             ; inc @@syn1
                dec     edi             ; dec @@syn2
                inc     ebp             ; inc @@win1
                test    ebp, 1Fh        ; test @@win1,1Fh
                jnz     .samples_lop
                retn

.sat:
                sar     ebx, 31         ; FFFFFFFFh,00000000h
                xor     ebx, 7FFFh      ; FFFF8000h,00007FFFh (signed 16bit)
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048] ; [esi+512*4]
                mov     ecx, 18         ; (12h*4)/4
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_16bit_shift_1_slow:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 0,1,0
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10         ; channel*1024
                and     eax, 1E0h       ; 1FFh-1Fh ; index(0..511), align 32
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_1 ; call mp3_dct32_shift_&rate_shift
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_16bit_shift_1_slow ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift] ; IF with_rate_shift
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4  ; src+32*4
                inc	dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4 ; src
                inc	dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_16bit_shift_1_slow:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h
                and     eax, 420h
                lea     esi, [eax+10h]
                lea     edi, [eax+30h]
                neg     ebp
                and     ebp, 1C0h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 100010h
                mov     edx, [mp3_synth_buf+esi*4]
                mov     eax, [mp3_synth_win+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+esi*4]
                mov     eax, [(mp3_synth_win+100h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                mov     eax, [(mp3_synth_win+200h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                mov     eax, [(mp3_synth_win+300h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                mov     eax, [(mp3_synth_win+400h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                mov     eax, [(mp3_synth_win+500h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                mov     eax, [(mp3_synth_win+600h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                mov     eax, [(mp3_synth_win+700h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [mp3_synth_buf+edi*4]
                mov     eax, [(mp3_synth_win+80h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                mov     eax, [(mp3_synth_win+180h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                mov     eax, [(mp3_synth_win+280h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                mov     eax, [(mp3_synth_win+380h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                mov     eax, [(mp3_synth_win+480h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                mov     eax, [(mp3_synth_win+580h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                mov     eax, [(mp3_synth_win+680h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                mov     eax, [(mp3_synth_win+780h)+ebp*4]
                imul    edx
                add     ebx, edx
                cmp     ebx, 200000h
                jnb     short .sat
                sar     ebx, 5
                sub     ebx, 8000h

.sat_back:
                mov     [ecx], bx
                add     ecx, [mp3_samples_dst_step]
                add     esi, 2
                sub     edi, 2
                add     ebp, 2
                test    ebp, 1Fh
                jnz     .samples_lop
                retn

.sat:
                sar     ebx, 31
                xor     ebx, 7FFFh
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048]
                mov     ecx, 18
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_16bit_shift_2_slow:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 0,2,0
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_2 ; call mp3_dct32_shift_&rate_shift
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_16bit_shift_2_slow ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_16bit_shift_2_slow:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h
                and     eax, 420h
                lea     esi, [eax+10h]
                lea     edi, [eax+30h]
                neg     ebp
                and     ebp, 1C0h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 100010h
                mov     edx, [mp3_synth_buf+esi*4]
                mov     eax, [mp3_synth_win+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+esi*4]
                mov     eax, [(mp3_synth_win+100h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                mov     eax, [(mp3_synth_win+200h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                mov     eax, [(mp3_synth_win+300h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                mov     eax, [(mp3_synth_win+400h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                mov     eax, [(mp3_synth_win+500h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                mov     eax, [(mp3_synth_win+600h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                mov     eax, [(mp3_synth_win+700h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [mp3_synth_buf+edi*4]
                mov     eax, [(mp3_synth_win+80h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                mov     eax, [(mp3_synth_win+180h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                mov     eax, [(mp3_synth_win+280h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                mov     eax, [(mp3_synth_win+380h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                mov     eax, [(mp3_synth_win+480h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                mov     eax, [(mp3_synth_win+580h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                mov     eax, [(mp3_synth_win+680h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                mov     eax, [(mp3_synth_win+780h)+ebp*4]
                imul    edx
                add     ebx, edx
                cmp     ebx, 200000h
                jnb     short .sat
                sar     ebx, 5
                sub     ebx, 8000h

.sat_back:
                mov     [ecx], bx
                add     ecx, [mp3_samples_dst_step]
                add     esi, 4
                sub     edi, 4
                add     ebp, 4
                test    ebp, 1Fh
                jnz     .samples_lop
                retn

.sat:
                sar     ebx, 31
                xor     ebx, 7FFFh
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048]
                mov     ecx, 18
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_8bit_shift_0_slow:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 1,0,0
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_0
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_8bit_shift_0_slow ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_8bit_shift_0_slow:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h
                and     eax, 420h
                lea     esi, [eax+10h]
                lea     edi, [eax+30h]
                neg     ebp
                and     ebp, 1C0h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 101000h
                mov     edx, [mp3_synth_buf+esi*4]
                mov     eax, [mp3_synth_win+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+esi*4]
                mov     eax, [(mp3_synth_win+100h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                mov     eax, [(mp3_synth_win+200h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                mov     eax, [(mp3_synth_win+300h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                mov     eax, [(mp3_synth_win+400h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                mov     eax, [(mp3_synth_win+500h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                mov     eax, [(mp3_synth_win+600h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                mov     eax, [(mp3_synth_win+700h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [mp3_synth_buf+edi*4]
                mov     eax, [(mp3_synth_win+80h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                mov     eax, [(mp3_synth_win+180h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                mov     eax, [(mp3_synth_win+280h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                mov     eax, [(mp3_synth_win+380h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                mov     eax, [(mp3_synth_win+480h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                mov     eax, [(mp3_synth_win+580h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                mov     eax, [(mp3_synth_win+680h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                mov     eax, [(mp3_synth_win+780h)+ebp*4]
                imul    edx
                add     ebx, edx
                cmp     ebx, 200000h
                jnb     short .sat
                sar     ebx, 13

.sat_back:
                mov     [ecx], bl
                add     ecx, [mp3_samples_dst_step]
                inc     esi
                dec     edi
                inc     ebp
                test    ebp, 1Fh
                jnz     .samples_lop
                retn

.sat:
                sar     ebx, 31
                not     ebx
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048]
                mov     ecx, 18
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_8bit_shift_1_slow:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 1,1,0
                                        ; force_8bit, rate_shift=1, force_fast=0
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10
                and     eax, 1E0h       ; 1FFh-1Fh
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4]
                call    mp3_dct32_shift_1 ; mp3_dct32_shift_&rate_shift ; rate_shift = 1
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_8bit_shift_1_slow ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5          ; mul32
                mov     cl, [option_rate_shift]
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4
                inc	dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4
                inc	dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn


; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_8bit_shift_1_slow:
                mov     eax, [mp3_curr_syn_index] ; IF LONG_WINDOW
                test    eax, 1E0h       ; 1FFh-1Fh
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax
                and     ebp, 1C0h       ; 1FFh-1Fh-20h
                and     eax, 420h       ; 20h+(1 shl 10)
                lea     esi, [eax+10h]
                lea     edi, [eax+30h]
                neg     ebp
                and     ebp, 1C0h
                mov     ecx, [mp3_curr_syn_dst]

.samples_lop:
                mov     ebx, 101000h    ; mov @@sum,(8000h SHL (@@out_shift))+(1 SHL (@@out_shift-1))
                                        ; @@out_shift equ (OUT_SHIFT_slow+(8*force_8bit))
                                        ; OUT_SHIFT_slow = 5 ; @@out_shift = 13
                mov     edx, [mp3_synth_buf+esi*4] ; @@SUM8 @@sum,@@win1,0,@@syn1
                                        ; @@SUM8 macro sum,win,ww,syn
                                        ;   IRP nn,0,1,2,3,4,5,6,7
                mov     eax, [mp3_synth_win+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+esi*4] ; @@syn1 equ esi
                mov     eax, [(mp3_synth_win+100h)+ebp*4] ; @@win1 equ ebp
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                mov     eax, [(mp3_synth_win+200h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                mov     eax, [(mp3_synth_win+300h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+esi*4]
                mov     eax, [(mp3_synth_win+400h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                mov     eax, [(mp3_synth_win+500h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                mov     eax, [(mp3_synth_win+600h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                mov     eax, [(mp3_synth_win+700h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [mp3_synth_buf+edi*4]
                mov     eax, [(mp3_synth_win+80h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+edi*4] ; @@SUM8 @@sum,@@win1,32,@@syn2
                                        ; @@syn2 equ edi
                                        ; @@win1 equ ebp
                mov     eax, [(mp3_synth_win+180h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                mov     eax, [(mp3_synth_win+280h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                mov     eax, [(mp3_synth_win+380h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                mov     eax, [(mp3_synth_win+480h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                mov     eax, [(mp3_synth_win+580h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                mov     eax, [(mp3_synth_win+680h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                mov     eax, [(mp3_synth_win+780h)+ebp*4]
                imul    edx
                add     ebx, edx
                cmp     ebx, 200000h    ; cmp @@sum,100h SHL (@@out_shift)
                jnb     short .sat
                sar     ebx, 13         ; sar @@sum,(@@out_shift)

.sat_back:
                mov     [ecx], bl
                add     ecx, [mp3_samples_dst_step]
                add     esi, 2
                sub     edi, 2
                add     ebp, 2
                test    ebp, 1Fh
                jnz     .samples_lop
                retn

.sat:
                sar     ebx, 31         ; sar @@sum,31 ; FFFFFFFFh,00000000h
                not     ebx
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4]
                lea     edi, [esi+2048]
                mov     ecx, 18
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


synth_8bit_shift_2_slow:
                test    byte [cpuid_flags], 10h ; SYNTH_MACRO 1,2,0 ; 8bit, quarter rate
                                        ; force_8bit, rate_shift=2, force_fast=0
                jz      short .no_rdtsc_supported ; timelog_start rdtsc_synth_dct
                rdtsc
                sub     [rdtsc_synth_dct], eax
                sbb     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported:
                mov	esi, mp3_sb_samples
                mov	edi, [mp3_samples_dst]
                mov	dword [mp3_curr_channel], 0

.synth_channel_lop:
                push	esi
                push	edi
                mov	[mp3_curr_syn_dst], edi
                mov	dword [mp3_curr_frame], 0

.synth_frame_lop:
                push    esi             ; sb_samples[ch][i]
                test    byte [cpuid_flags], 10h ; timelog_start rdtsc_dct32
                jz      short .no_rdtsc_supported@
                rdtsc
                sub     [rdtsc_dct32], eax
                sbb     [rdtsc_dct32+4], edx

.no_rdtsc_supported@:
                mov     edx, [mp3_curr_channel]
                mov     eax, [mp3_synth_index+edx*4]
                sub     dword [mp3_synth_index+edx*4], 32
                shl     edx, 10         ; channel*1024
                and     eax, 1E0h       ; 1FFh-1Fh ; index(0..511), align 32
                or      eax, edx
                mov     [mp3_curr_syn_index], eax
                mov     edi, [mp3_curr_syn_index]
                lea     edi, [mp3_synth_buf+edi*4] ; IF SYNTH32
                call    mp3_dct32_shift_2 ; mp3_dct32_shift_&rate_shift ; rate_shift=2
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@ ; timelog_end rdtsc_dct32
                rdtsc
                add     [rdtsc_dct32], eax
                adc     [rdtsc_dct32+4], edx

.no_rdtsc_supported@@:
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@ ; timelog_start rdtsc_synth
                rdtsc
                sub     [rdtsc_synth], eax
                sbb     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@:
                call    mp3_synth_filter_this_8bit_shift_2_slow ;
                                        ; mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_synth
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                add     [rdtsc_synth], eax
                adc     [rdtsc_synth+4], edx

.no_rdtsc_supported@@@@:
                pop     esi             ; src
                mov     eax, [mp3_samples_dst_step]
                shl     eax, 5          ; mul32
                mov     cl, [option_rate_shift] ; IF with_rate_shift
                shr     eax, cl
                add     [mp3_curr_syn_dst], eax
                add     esi, 128        ; SBLIMIT*4 ; src+32*4
                inc     dword [mp3_curr_frame]
                mov     eax, [mp3_curr_frame]
                cmp     eax, [mp3_nb_frames]
                jb      .synth_frame_lop
                pop     edi
                pop     esi
                add     edi, [mp3_bytes_per_sample]
                add     esi, 4608       ; 36*SBLIMIT*4 ; src
                inc     dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jb      .synth_channel_lop
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_synth_dct
                jz      short .no_rdtsc_supported@@@@@
                rdtsc
                add     [rdtsc_synth_dct], eax
                adc     [rdtsc_synth_dct+4], edx

.no_rdtsc_supported@@@@@:
                retn

; =============== S U B R O U T I N E =======================================


mp3_synth_filter_this_8bit_shift_2_slow:
                mov     eax, [mp3_curr_syn_index]
                test    eax, 1E0h       ; 1FFh-1Fh ; offset
                jz      .append_copy_to_window
                nop

.append_copy_to_window_back:
                mov     ebp, eax        ; @@win1
                and     ebp, 1C0h       ; 1FFh-1Fh-20h
                and     eax, 420h       ; 20h+(1 shl 10) ; bit5 and channel
                lea     esi, [eax+10h]  ; @@syn1
                lea     edi, [eax+30h]  ; @@syn2
                neg     ebp
                and     ebp, 1C0h       ; 1FFh-1Fh-20h
                mov     ecx, [mp3_curr_syn_dst] ; @@dst

.samples_lop:
                mov     ebx, 101000h    ; mov @@sum,(80h SHL (@@out_shift))+(1 SHL (@@out_shift-1))
                                        ; @@out_shift equ (OUT_SHIFT_slow+(8*force_8bit))
                                        ; @@out_shift = 13 ; OUT_SHIFT_slow = 5
                mov     edx, [mp3_synth_buf+esi*4] ; @@SUM8 @@sum,@@win1,0,@@syn1
                                        ; @@SUM8 macro sum,win,ww, syn
                                        ; IRP nn,0,1,2,3,4,5,6,7
                                        ; [mp3_synth_buf+syn*4+(nn*64*4)]
                mov     eax, [mp3_synth_win+ebp*4] ; [mp3_synth_win+win*4+(nn*64*4)+ww*4]
                imul    edx             ; 64bit = 32bit * 32bit
                add     ebx, edx        ; add sum,edx ; sum from MSW of result
                mov     edx, [(mp3_synth_buf+100h)+esi*4] ;
                                        ; [mp3_synth_buf+syn*4+(nn*64*4)] ; nn=1
                mov     eax, [(mp3_synth_win+100h)+ebp*4] ;
                                        ; [mp3_synth_win+win*4+(nn*64*4)+ww*4] ; nn=1
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+esi*4]
                mov     eax, [(mp3_synth_win+200h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+esi*4]
                mov     eax, [(mp3_synth_win+300h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+esi*4] ;
                                        ; [mp3_synth_buf+syn*4+(nn*64*4)] ; nn=4
                mov     eax, [(mp3_synth_win+400h)+ebp*4] ;
                                        ; [mp3_synth_win+win*4+(nn*64*4)+ww*4] ; nn=4
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+esi*4]
                mov     eax, [(mp3_synth_win+500h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+esi*4]
                mov     eax, [(mp3_synth_win+600h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+esi*4]
                mov     eax, [(mp3_synth_win+700h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [mp3_synth_buf+edi*4] ; @@SUM8 @@sum,@@win1,32,@@syn2
                mov     eax, [(mp3_synth_win+80h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+100h)+edi*4]
                mov     eax, [(mp3_synth_win+180h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+200h)+edi*4]
                mov     eax, [(mp3_synth_win+280h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+300h)+edi*4]
                mov     eax, [(mp3_synth_win+380h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+400h)+edi*4]
                mov     eax, [(mp3_synth_win+480h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+500h)+edi*4]
                mov     eax, [(mp3_synth_win+580h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+600h)+edi*4]
                mov     eax, [(mp3_synth_win+680h)+ebp*4]
                imul    edx
                add     ebx, edx
                mov     edx, [(mp3_synth_buf+700h)+edi*4]
                                        ; [mp3_synth_buf+syn*4+(nn*64*4)] ; nn=7
                mov     eax, [(mp3_synth_win+780h)+ebp*4]
                                        ; [mp3_synth_win+win*4+(nn*64*4)+ww*4] ; nn=7
                imul    edx
                add     ebx, edx
                cmp     ebx, 200000h    ; cmp @@sum,100h SHL (@@out_shift) ; out_shift=13
                jnb     short .sat
                sar     ebx, 13         ; sar @@sum,(@@out_shift)

.sat_back:
                mov     [ecx], bl       ; mov byte ptr [@@dst],@@sum_8bit
                add     ecx, [mp3_samples_dst_step]
                add     esi, 4          ; add @@syn1,1 shl rate_shift ; rate_shift=2
                sub     edi, 4          ; add @@syn2,1 shl rate_shift
                add     ebp, 4          ; add @@win1,1 shl rate_shift
                test    ebp, 1Fh        ; test @@win1,1Fh
                jnz     .samples_lop
                retn

.sat:
                sar     ebx, 31         ; sar  @@sum,31 ; FFFFFFFFh,00000000h
                not     ebx
                jmp     short .sat_back

.append_copy_to_window:
                lea     esi, [mp3_synth_buf+eax*4] ; IF SYNTH32
                lea     edi, [esi+2048] ; [esi+512*4]
                mov     ecx, 18         ; (12h*4)/4
                rep movsd
                jmp     .append_copy_to_window_back


; =============== S U B R O U T I N E =======================================


mp3_any_init_synth_window:
                xor     edx, edx        ; index (0..100h)
                xor     ecx, ecx        ; delta.val
                mov     [mp3_synth_win+edx*2], ecx

.synth_lop:
                movsx   ebx, word [mp3_synth_win_src+edx*2]
                add     ecx, ebx
                mov     eax, ecx
                cmp     byte [option_fast], 0
                jz      short .not_fast
                sar     eax, 5

.not_fast:
                cmp	byte [option_fast], 0
                jnz	short .not_slow
                shl	eax, 14         ; (WFRAC_BITS_slow-WFRAC_BITS_default)

.not_slow:
                inc     edx             ; index (1..100h)
                mov     ebx, 200h
                sub     ebx, edx        ; 1FFh..100h
                mov     [mp3_synth_win+ebx*4], eax
                test    edx, 3Fh
                jz      short .synth_keep_sign
                neg     eax

.synth_keep_sign:
                mov     [mp3_synth_win+edx*4], eax
                cmp     edx, 100h
                jb      short .synth_lop
                xor     edx, edx

.synth_neg_lop:
                test    edx, 30h        ; skip 0..0Fh (only negate 10h..3Fh)
                jz      short .synth_neg_next
                neg     dword [mp3_synth_win+edx*4]

.synth_neg_next:
                inc     edx
                cmp     edx, 200h
                jb      short .synth_neg_lop
                xor     edx, edx

.synth_swap_lop:
                mov     eax, edx
                and     eax, 3Fh
                sub     eax, 17         ; swap win [(17..31)] with win[(17..31)+32)
                cmp     eax, 14         ; 31-17
                ja      short .synth_swap_next
                mov     eax, [mp3_synth_win+edx*4]
                xchg    eax, [(mp3_synth_win+80h)+edx*4]
                mov     [mp3_synth_win+edx*4], eax

.synth_swap_next:
                inc     edx
                cmp     edx, 200h
                jb      short .synth_swap_lop
                xor     edx, edx

.synth_zero_lop:
                mov	dword [(mp3_synth_win+40h)+edx*4], 0
                add	edx, 40h
                cmp	edx, 200h
                jb	short .synth_zero_lop
                mov	esi, mp3_synth_win
                lea	edi, [esi+2048] ; [esi+512*4]
                mov	ecx, 512        ; append another copy
                rep movsd
                retn


; =============== S U B R O U T I N E =======================================


mp3_init_post_collapse:
                cmp	byte [option_fast], 0
                jz	short .not_fast
                mov	esi, mp3_synth_win
                mov	edi, esi
                mov	ecx, 1024       ; 512*(1+LONG_WINDOW)

.collapse_lop:
                lodsd                   ; collapse 32bit to 16bit
                                        ; (that's slightly faster due to better caching)
                stosw
                loop    .collapse_lop

.not_fast:
                retn


; =============== S U B R O U T I N E =======================================


mp3_any_init_band_indices:
                mov     esi, mp3_band_size_long
                mov     edi, mp3_band_index_long
                mov     ebx, 9

.band_index_lop_i:
                xor     eax, eax
                mov     ecx, 22

.band_index_lop_j:
                stosw
                movzx   edx, byte [esi]
                add     eax, edx
                inc     esi
                loop    .band_index_lop_j
                add     ecx, 10
                rep stosw
                dec     ebx
                jnz     short .band_index_lop_i
                retn


; =============== S U B R O U T I N E =======================================


mp3_any_init_lsf_sf_expand:
                mov     esi, mp3_lsf_sf_expand_init_table
                mov     edi, mp3_lsf_sf_expand_exploded_table
                xor     edx, edx        ; curr.index
                xor     ebx, ebx        ; curr.base

.lop:
                cmp     dx, [esi+6]     ; nextbase
                jb      short .inrange
                mov     bx, [esi+6]
                add     esi, 8          ; next entry

.inrange:
                mov     eax, edx
                sub     eax, ebx
                mov     cl, [esi]
                shr     eax, cl         ; div2
                div     byte [esi+3] ; mod3 ; [2]=slen[3]
                mov     [edi+3], ah
                mov     ah, 0           ; eax=div.result
                div     byte [esi+2] ; mod2 ; [2]=slen[2]
                mov     [edi+2], ah     ; remainder
                mov     ah, 0
                div     byte [esi+1] ; mod1 ; [1]=slen[1]
                mov     [edi], ax       ; [0]=slen[0]
                mov     ax, [esi+4]     ; [4]=tindex2
                mov     [edi+4], ax     ; [5]=force_preflag
                add     edi, 8
                inc     edx             ; curr.index ; next
                cmp     edx, 1024       ; 512+512
                jb      short .lop
                retn


; =============== S U B R O U T I N E =======================================


mp3_any_init_huff_tables:
                mov     ebp, huff_tree_list_data
                mov     esi, huff_tree_list_numbits
                mov     edx, 1          ; idx (table 01h..11h)

.huffman_table_lop:
                xor     eax, eax
                mov     edi, mp3_huff_tmp_bits
                mov     ecx, 40h        ; 100h/4 ; 100h x 8bit
                rep stosd
                mov     edi, mp3_huff_tmp_codes
                mov     ecx, 80h        ; 100h/2 ; 100h x 16bit
                rep stosd
                xor     ebx, ebx

.huff_entry_lop:
                movzx   edi, byte [ebp+0]
                inc     ebp             ; dst=data
                lodsb                   ; numbits
                mov     [mp3_huff_tmp_bits+edi], al
                mov     cl, 32
                sub     cl, al          ; 32-numbits
                shr     ebx, cl
                mov     word [mp3_huff_tmp_codes+edi*2], bx
                inc     ebx             ; next.code
                shl     ebx, cl         ; shift back to MSBs
                jnz     short .huff_entry_lop
                pusha
                mov     eax, 100h       ; nb_codes
                mov     ebx, mp3_huff_tmp_bits ; bits
                mov     esi, mp3_huff_tmp_codes ; codes
                call    mp3_build_huff_table_root ; make table
                popa
                inc     edx             ; idx
                cmp     edx, 12h
                jnz     short .huffman_table_lop ; next table
                retn


; =============== S U B R O U T I N E =======================================


mp3_integer_init_is_stereo_lsf:
                xor     edi, edi

.lsf_lop:
                mov     esi, edi
                and     esi, 3Fh
                inc     esi
                shr     esi, 1
                test    edi, 40h
                jz      short .lsf_no_shift
                shl     esi, 1

.lsf_no_shift:
                mov     edx, 40000000h  ; aka mul 1.000
                add     esi, 4
                test    edi, 80h        ; 2*40h
                jz      short .no_ms_stereo
                mov     edx, 5A82799Ah  ; 2D413CCDh*2 ; aka mul 1.414
                sub     esi, 2

.no_ms_stereo:
                mov     ecx, esi
                shr     ecx, 2          ; msbs
                and     esi, 3          ; lsbs
                mov     eax, [mp3_is_table_lsf_src+esi*4]
                shr     eax, cl
                test    edi, 1
                jnz     short .lsf_no_swap
                xchg    eax, edx

.lsf_no_swap:
                mov     [mp3_is_table_lsf+edi*8], eax
                mov     [(mp3_is_table_lsf+4)+edi*8], edx
                inc     edi
                cmp     edi, 100h
                jb      short .lsf_lop
                retn


; =============== S U B R O U T I N E =======================================


mp3_integer_init_mdct_windows:
                mov     edi, mp3_mdct_win
                mov     esi, mp3_mdct_win_src
                mov     ecx, 144        ; 36*4
                rep movsd
                mov     esi, mp3_mdct_win
                mov     edi, (mp3_mdct_win+240h)
                mov     ecx, 72         ; 4*36/2 ; that is, 4*36 entry pairs

.mdct_lop_dupe:                       
                movsd                   ; copy normal, [4..7][even] = +[0..3][even
                lodsd
                neg     eax             ; copy negated, [4..7][odd] = -[0..3][odd]
                stosd
                loop    .mdct_lop_dupe
                retn


; =============== S U B R O U T I N E =======================================


mp3_integer_init_table_4_3:
                cmp	byte [option_fast], 0
                mov	al, 72          ; 100-6-VFRAC_BITS_slow
                jz	short .this_vfrac
                mov	al, 76          ; 100-6-VFRAC_BITS_fast

.this_vfrac:
                mov     [mp3_curr_vfrac_bits], al
                xor     edi, edi

.table_4_3_lop:
                push    edi             ; for i=1 to TABLE_4_3_SIZE-1
                mov     eax, edi
                shr     eax, 2
                mul     eax
                mul     eax
                xor     ebx, ebx
                call    cbrt96
                add     cl, [mp3_curr_vfrac_bits]
                pop     edi

.inner_lop:
                mov     eax, edi
                and     eax, 3
                mov     eax, [mp3_pow2_quarters+eax*4]
                mul     ebx
                mov     ch, cl
                or      edx, edx
                jns     short .this
                shr     edx, 1
                dec     ch

.this:
                mov     [mp3_table_4_3_value+edi*4], edx
                mov     [mp3_table_4_3_exp+edi], ch
                inc     edi
                test    edi, 3
                jnz     short .inner_lop
                cmp     edi, 803Ch
                jb      short .table_4_3_lop
                retn


; =============== S U B R O U T I N E =======================================


mp3_integer_init_exponent:
                mov     edi, mp3_expval_table
                xor     edx, edx

.exponent_lop:
                mov     eax, edx        ; val=i
                mov     ebx, edx
                mov     ecx, edx
                shr     ebx, 4
                shr     ecx, 6          ; 4+2
                and     eax, 0Fh        ; val=i AND 0Fh
                and     ebx, 3
                lea     ebx, [ebx+eax*4] ; (0..0Fh)*4+(0..3)
                mov     eax, [mp3_table_4_3_value+ebx*4]
                or      eax, eax
                jz      short .this
                sub     cl, [mp3_table_4_3_exp+ebx]
                ja      short .left_shift
                neg     cl
                shr     eax, cl
                cmp     cl, 1Fh
                jbe     short .this
                xor     eax, eax
                jmp     short .this

.left_shift:
                mov     eax, 7FFFFFFFh

.this:
                stosd
                inc     edx
                cmp     edx, 2000h
                jb      short .exponent_lop
                mov     esi, mp3_expval_table
                mov     edi, mp3_exp_table
                mov     ecx, 200h

.exponent_dupe_lop:
                mov     eax, [esi+4]
                stosd
                add     esi, 40h
                loop    .exponent_dupe_lop
                retn


; =============== S U B R O U T I N E =======================================


cbrt96:
                sub     esp, 18h        ; cube root, val^(1/3), from https://gist.github.com/anonymous/729557
                                        ; in:  ebx:edx:eax = unsigned 96bit input (integer)
                                        ; out: ebx         = unsigned 32bit result (with fractional bits)
                                        ; out: cl          = number of fractional bits
                mov     [esp], eax
                mov     [esp+4], edx
                mov     [esp+8], ebx
                mov     dword [esp+0Ch], 0
                mov     dword [esp+10h], 0
                mov     dword [esp+14h], 0
                xor     ebx, ebx        ; result.value
                mov     cl, 0           ; result.fraction
                or      eax, edx        ; skip if zero
                jz      short .pre_shift_done

.pre_shift_lop:
                test    dword [esp+8], 0E0000000h
                jnz     short .pre_shift_done
                shl     dword [esp], 1
                rcl     dword [esp+4], 1
                rcl     dword [esp+8], 1
                shl     dword [esp], 1
                rcl     dword [esp+4], 1
                rcl     dword [esp+8], 1
                shl     dword [esp], 1
                rcl     dword [esp+4], 1
                rcl     dword [esp+8], 1
                inc     cl
                jmp     short .pre_shift_lop

.pre_shift_done:
                mov     ch, 20h         ; loopcount

.lop:
                add     ebx, ebx        ; result*2
                mov     eax, ebx        ; y
                inc     ebx             ; result+1
                mul     ebx             ; y*(y+1)
                mov     esi, eax
                mov     edi, edx
                xor     ebp, ebp
                stc
                adc     esi, esi        ; y*(y+1)*2+1
                adc     edi, edi
                adc     ebp, ebp
                add     esi, eax
                adc     edi, edx        ; y*(y+1)*3+1
                adc     ebp, 0
                shl     dword [esp], 1
                rcl     dword [esp+4], 1
                rcl     dword [esp+8], 1 ; shl 3
                rcl     dword [esp+0Ch], 1
                rcl     dword [esp+10h], 1
                rcl     dword [esp+14h], 1
                shl     dword [esp], 1
                rcl     dword [esp+4], 1
                rcl     dword [esp+8], 1
                rcl     dword [esp+0Ch], 1
                rcl     dword [esp+10h], 1
                rcl     dword [esp+14h], 1
                shl     dword [esp], 1
                rcl     dword [esp+4], 1
                rcl     dword [esp+8], 1
                rcl     dword [esp+0Ch], 1
                rcl     dword [esp+10h], 1
                rcl     dword [esp+14h], 1
                sub     [esp+0Ch], esi
                sbb     [esp+10h], edi  ; sub/compare
                sbb     [esp+14h], ebp
                jnb     short .next
                dec     ebx
                add     [esp+0Ch], esi
                adc     [esp+10h], edi  ; undo
                adc     [esp+14h], ebp

.next:
                dec     ch
                jnz     short .lop
                add     esp, 18h
mp3_init_log_constants:
                retn

;mp3_init_log_constants:
;                retn

; =============== S U B R O U T I N E =======================================


mp3_build_huff_table_root:
                mov     [_@@nb_codes], eax ; "init_vlc"
                mov     dword [_@@prefix_numbits], 0
                mov     dword [_@@prefix_pattern], 0
                pusha
                mov     ecx, eax
                xor     eax, eax

.prescan_lop:
                cmp     al, [ebx]
                ja      short .prescan_next
                mov     al, [ebx]

.prescan_next:
                inc     ebx
                loop    .prescan_lop
                cmp     al, 9           ; CHILD_BITS
                jb      short .prescan_this_limit
                mov     al, 9

.prescan_this_limit:
                mov     [_@@table_nb_bits], eax
                popa

mp3_build_huff_table_recursive_child:
                mov     ecx, [_@@table_nb_bits]
                mov     eax, 1
                shl     eax, cl
                mov     [_@@curr_table_size], eax
                dec     eax
                mov     [_@@curr_table_mask], eax
                pusha
                mov     ebx, [mp3_huff_num_entries]
                mov     [_@@curr_table_index], ebx
                add     ebx, [_@@curr_table_size]
                mov     [mp3_huff_num_entries], ebx
                cmp     dword [mp3_huff_num_entries], 11776 ; HUFF_TREE_SIZE/4
                ja      fatalunexpected
                popa
                mov     edi, huff_tree_buf
                mov     eax, [_@@curr_table_index]
                mov     [edi+edx*4], ax
                mov     eax, [_@@table_nb_bits]
                neg     eax
                mov     [edi+edx*4+2], ax
                mov     edi, huff_tree_buf
                mov     edx, [_@@curr_table_index]
                mov     ecx, [_@@curr_table_size]

.clear_table_lop:
                mov     word [edi+edx*4], 0FFFFh
                mov     word [edi+edx*4+2], 0
                inc     edx
                loop    .clear_table_lop
                push    ebx
                push    esi
                xor     edx, edx

.make_table_lop:
                movzx   ecx, byte [ebx]
                movzx   eax, word [esi]
                sub     ecx, [_@@prefix_numbits]
                jle     short .make_table_lop_next
                shr     eax, cl
                cmp     eax, [_@@prefix_pattern]
                jnz     short .make_table_lop_next
                mov     edi, huff_tree_buf
                movzx   eax, word [esi]
                sub     ecx, [_@@table_nb_bits]
                ja      short .create_child_table
                neg     ecx
                shl     eax, cl
                and     eax, [_@@curr_table_mask]
                add     eax, [_@@curr_table_index]
                lea     edi, [edi+eax*4]
                mov     eax, 1
                shl     eax, cl
                mov     ecx, eax
                movzx   eax, byte [ebx]
                sub     eax, [_@@prefix_numbits]

.make_rept_lop:
                cmp     word [edi+2], 0
                jnz     fatalunexpected
                mov     [edi], dx
                mov     [edi+2], ax
                add     edi, 4
                loop    .make_rept_lop
                jmp     short .make_table_lop_next

.create_child_table:
                shr     eax, cl
                and     eax, [_@@curr_table_mask]
                add     eax, [_@@curr_table_index]
                neg     ecx
                cmp     [edi+eax*4+2], cx
                jl      short .make_table_lop_next
                mov     [edi+eax*4+2], cx

.make_table_lop_next:
                add     esi, 2
                inc     ebx
                inc     edx
                cmp     edx, [_@@nb_codes]
                jb      .make_table_lop
                pop     esi
                pop     ebx
                mov     ecx, [_@@curr_table_size]
                mov     edx, [_@@curr_table_index]

.make_child_tables_lop:
                mov     edi, huff_tree_buf
                movsx   eax, word [edi+edx*4+2]
                cmp     eax, 0
                jns     short .make_child_tables_lop_next
                neg     eax
                cmp     eax, [_@@table_nb_bits]
                jbe     short .make_child_tables_this
                mov     eax, [_@@table_nb_bits]

.make_child_tables_this:
                push	ecx
                push	edx
                push	dword [_@@curr_table_index]
                push	dword [_@@table_nb_bits]
                push	dword [_@@prefix_numbits]
                push	dword [_@@prefix_pattern]
                mov	ecx, [_@@table_nb_bits]
                mov	[_@@table_nb_bits], eax
                add	[_@@prefix_numbits], ecx
                shl	dword [_@@prefix_pattern], cl
                mov	eax, edx
                sub	eax, [_@@curr_table_index]
                or	[_@@prefix_pattern], eax
                call	mp3_build_huff_table_recursive_child
                pop	dword [_@@prefix_pattern]
                pop	dword [_@@prefix_numbits]
                pop	dword [_@@table_nb_bits]
                pop	dword [_@@curr_table_index]
                pop	edx
                pop	ecx

.make_child_tables_lop_next:
                inc	edx
                loop	.make_child_tables_lop
                retn


; =============== S U B R O U T I N E =======================================


mp3_exclude_id3_and_tag:
                mov     esi, [stream_pos]
                mov     ecx, [bytes_left]
                cmp     ecx, 10
                jb      short .no_id3
                mov     eax, [esi]
                and     eax, 0FFFFFFh
                ;cmp    eax, '3DI'     ; "ID3"
                ; 20/10/2024 
                cmp     eax, 'ID3'     ; FASM & NASM syntax
                jnz     short .no_id3
                mov     eax, [esi+6]
                test    eax, 80808080h
                jnz     short .no_id3

.xlat_4x7bit_to_28bit:
                xchg    al, ah
                shl     al, 1
                shl     ax, 1
                shr     ax, 2
                ror     eax, 16
                xchg    al, ah
                shl     al, 1
                shl     ax, 1
                shr     eax, 2
                add     eax, 10
                cmp     ecx, eax
                jb      short .no_id3
                add     esi, eax
                sub     ecx, eax
                mov     [mp3_id3_size], eax

.no_id3:
                mov     edx, 80h
                cmp     ecx, edx
                jb      short .no_tag_or_ext
                mov     eax, [esi+ecx-80h]
                and     eax, 0FFFFFFh
                ;cmp    eax, 'GAT'     ; "TAG"
                ; 20/10/2024
                cmp     eax, 'TAG'     ; FASM & NASM syntax
                jz      .got_tag_size_edx
                ;cmp    eax, 'TXE'
                cmp     eax, 'EXT'
                jz      .got_tag_size_edx

.no_tag_or_ext:
                mov     edx, 0E3h
                cmp     ecx, edx
                jb      short .no_tagplus
                ;cmp    dword [esi+ecx-0E3h], '+GAT' ; "TAG+"
                ; 20/10/2024
                cmp     dword [esi+ecx-0E3h], 'TAG+'
                jz      .got_tag_size_edx

.no_tagplus:
                mov     edx, 20        ; 10+10
                cmp     ecx, edx
                jb      short .no_3di  ; "3DI",04h
                cmp     dword [esi+ecx-10], 4494433h ; 'ID3'+04000000h
                jnz     short .no_3di
                test    byte [esi+ecx-5], 10h ; bit 4
                jz      short .no_3di
                mov     eax, [esi+ecx-4]
                test    eax, 80808080h
                jnz     short .no_3di

.@xlat_4x7bit_to_28bit:
                xchg    al, ah
                shl     al, 1
                shl     ax, 1
                shr     ax, 2
                ror     eax, 10h
                xchg    al, ah
                shl     al, 1
                shl     ax, 1
                shr     eax, 2
                lea     edx, [eax+20]  ; [eax+10+10] ; hdr+footer siz
                jmp     .got_tag_size_edx

.no_3di:
                ;cmp    dword [esi+ecx-32], 'TEPA' ; [esi+ecx-32+0]
                ; 20/10/2024
                cmp     dword [esi+ecx-32], 'APET'
                                       ; check "APETAGEX"
                jnz     short .no_ape
                ;cmp    dword [esi+ecx-28], 'XEGA' ; [esi+ecx-32+4]
                cmp     dword [esi+ecx-28], 'AGEX'
                jnz     short .no_ape
                mov     edx, [esi+ecx-20] ; [esi+ecx-32+12] ; get size
                test    dword [esi+ecx-12], 80000000h ; [esi+ecx-32+20],1 shl 31
                jz      short .no_ape_header
                add     edx, 32        ; hdr.size

.no_ape_header: 
                jmp     .got_tag_size_edx

.no_ape:
                mov     edx, 20        ; 11+9
                cmp     ecx, edx       ; "LYRICSEND" or "LYRICS200"
                                       ; (11+N+9 bytes each)
                jb      short .no_lyrics
                ;cmp    dword [esi+ecx-9], 'IRYL'
                ; 20/10/2024
                cmp     dword [esi+ecx-9], 'LYRI' ; FASM & NASM syntax
                jnz     short .no_lyrics
                cmp     byte [esi+ecx-5], 'C'
                jnz     short .no_lyrics
                ;cmp    dword [esi+ecx-4], 'DNES'
                cmp     dword [esi+ecx-4], 'SEND'
                jz      short .lyrics3_v1
                ;cmp    dword [esi+ecx-4], '002S'
                cmp     dword [esi+ecx-4], 'S200'
                jz      short .lyrics3_v2
                jnz     short .no_lyrics

.lyrics3_v1:
                mov     edx, 20        ; 11+9

.lyrics3_v1_size_lop:
                lea     eax, [esi+ecx]
                sub     eax, edx
                ;cmp    dword [eax], 'IRYL' ; "LYRICSBEGIN"
                ; 20/10/2024
                cmp     dword [eax], 'LYRI'
                jnz     short .lyrics3_v1_size_next
                ;cmp    dword [eax+4], 'EBSC'
                cmp     dword [eax+4], 'CSBE'
                jnz     short .lyrics3_v1_size_next
                ;cmp    dword [eax+7], 'NIGE'
                cmp     dword [eax+7], 'EGIN'
                jz      short .got_tag_size_edx

.lyrics3_v1_size_next:
                inc     edx
                cmp     edx, 5120
                ja      short .no_lyrics
                cmp     edx, ecx
                jbe     short .lyrics3_v1_size_lop
                ;jmp     short .no_lyrics

.no_lyrics:
                ;jmp    short .footer_tag_all_done
		; 22/10/2024
.footer_tag_all_done:
                mov     [stream_pos], esi
                mov     [bytes_left], ecx
                retn

.lyrics3_v2:
                push    ecx
                push    esi
                lea     esi, [esi+ecx-15] ; [esi+ecx-6-9]
                mov     ecx, 6
                xor     edx, edx

.lyrics3_v2_size_lop:
                imul    edx, 10
                movzx   eax, byte [esi]
                inc     esi
                sub     al, 30h
                add     edx, eax
                loop    .lyrics3_v2_size_lop
                pop     esi
                pop     ecx
                add     edx, 0Fh       ; 6+9
                ;jmp    short .got_tag_size_edx

.got_tag_size_edx:
		;;;
		; 22/10/2024
                sub    ecx, edx
                jnb    short .cont
		;;;
                mov     eax, edx
                call    wr_decimal_eax
                call    wrcrlf
                ;;;
		;sub    ecx, edx
                ;jb     fatalunexpected
		jmp	fatalunexpected
.cont:
		;;;
                add     [mp3_tag_size], edx
                jmp     .no_id3


; =============== S U B R O U T I N E =======================================


mp3_detect_free_format_block_size:
                cmp     dword [mp3_free_format_frame_size], 0
                jnz     .already_detected
                xor     edx, edx

.find_distance_lop:
                cmp     edx, [mp3_src_remain]
                jz      short .match_eof
                lea     eax, [edx+4]
                cmp     eax, [mp3_src_remain]
                ja      short .find_distance_failed
                mov     eax, [esi+edx]
                call    bswap_eax
                xor     eax, [mp3_hdr_32bit_header]
                and     eax, 0FFFE0C00h
                jz      short .match_eof

.find_distance_next:
                inc     edx
                cmp     edx, 1000h
                jbe     short .find_distance_lop

.find_distance_failed:
                stc
                retn

.match_eof:
                mov     eax, edx
                sub     eax, [mp3_hdr_flag_padding]
                cmp     eax, 4
                jb      short .find_distance_next
                mov     [mp3_free_format_frame_size], eax
                xor     ebx, ebx

.confirm_distance_lop:
                mov     eax, [esi+ebx]
                call    bswap_eax
                shr     eax, 10         ; 9+1
                adc     ebx, [mp3_free_format_frame_size]
                cmp     ebx, [mp3_src_remain]
                jz      short .confirm_distance_match_eof
                lea     eax, [ebx+4]
                cmp     eax, [mp3_src_remain]
                ja      short .find_distance_next
                mov     eax, [esi+ebx]
                call    bswap_eax
                xor     eax, [mp3_hdr_32bit_header]
                and     eax, 0FFFE0C00h
                jnz     short .find_distance_next
                jmp     short .confirm_distance_lop

.confirm_distance_match_eof:
                mov     eax, [mp3_free_format_frame_size]
                shl     eax, 3
                mul     dword [mp3_sample_rate]
                mov     ecx, [mp3_nb_granules]
                imul    ecx, 240h
                div     ecx
                mov     [mp3_bit_rate], eax

.already_detected:
                clc
                retn


; =============== S U B R O U T I N E =======================================


mp3_check_xing_info:
                mov     dword [mp3_xing_id], 0
                mov     dword [mp3_xing_frames], 0
                mov     dword [mp3_xing_filesize], 0
                mov     esi, [mp3_src_data_location]
                lodsd
                ;cmp    eax, 'gniX'
		; 20/10/2024
		cmp	eax, 'Xing'     ; FASM & NASM syntax
                jz      short .xing
                retn

.xing:
                mov     [mp3_xing_id], eax
                lodsd
                call    bswap_eax
                mov     [mp3_xing_flags], eax
                mov     edx, eax
                test    edx, 1
                jz      short .no_xing_frames
                lodsd
                call    bswap_eax
                mov     [mp3_xing_frames], eax

.no_xing_frames:
                test    edx, 2          ; 1 shl 1
                jz      short .no_xing_filesize
                lodsd
                call    bswap_eax
                mov     [mp3_xing_filesize], eax

.no_xing_filesize:
                test    edx, 4          ; 1 shl 2
                jz      short .no_xing_toc
                mov     ecx, 100
                mov     edi, mp3_xing_toc
                rep movsb

.no_xing_toc:
                test    edx, 8          ; 1 shl 3
                jz      short .no_xing_vbr_scale
                lodsd
                call    bswap_eax
                mov     [mp3_xing_vbr_scale], eax

.no_xing_vbr_scale:
                mov	dword [mp3_bit_rate], 0
                mov	eax, [mp3_sample_rate]
                shl	eax, 3
                mul	dword [mp3_xing_filesize]
                mov	ecx, [mp3_xing_frames]
                imul	ecx, [mp3_nb_granules]
                imul	ecx, 576        ; 18*32
                cmp	edx, ecx
                jnb	short .overflow
                div	ecx
                mov	[mp3_bit_rate], eax

.overflow:
                retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
mp3_decode_frame:
                mov     [mp3_src_remain], ecx
                mov     [mp3_samples_dst], edi
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported@@@@
                rdtsc
                sub     [rdtsc_total], eax
                sbb     [rdtsc_total+4], edx

.no_rdtsc_supported@@@@:
                call    mp3_search_get_header
                jc      .error
                mov     eax, [mp3_src_frame_size]
                cmp     eax, 0
                jle     .error
                cmp     eax, [mp3_src_remain]
                ja      .error
                mov     [mp3_bitstream_start], esi
		; 11/01/2025
		;mov	eax, 32

.mp3mac_bitstream_set_position:
		; 22/10/2024
                ;mov    esi, [mp3_bitstream_start]
                ;mov    cl, al
                ;shr    eax, 3
                ;and    cl, 7
                ;mov	eax, 4
                ;add    esi, eax
                add     esi, 4
                call    mp3_recollect_bits

.mp3mac_get_n_bits:
                ;mov    eax, ebp        ; mp3_col32
                ;shl    ebp, cl
                ;rol    eax, cl
                ;xor    eax, ebp        ; mp3_col32
                ;sub    ch, cl          ; sub mp3_colNN,num
                ;jns    short .cont
                ;mov    cl, ch          ; mov cl,mp3_colNN
                ;add    ch, 16
                ;rol    ebp, cl         ; rol mp3_col32,cl
                ;mov    bp, [esi]       ; mov mp3_col16,word ptr [esi]
                ;add    esi, 2
                ;ror    bp, 8           ; endianess
                ;ror    ebp, cl         ; ror mp3_col32,cl

.cont:
                call	mp3_bitstream_read_header_extra
                call	mp3_bitstream_read_granules
                jc	.error
                call	mp3_uncollect_bits
                mov	[mp3_src_data_location], esi
                cmp	dword [mp3_samples_dst], 0
                jz	.skip_decoding
                call	mp3_bitstream_append_to_main_data_pool
                cmp	dword [mp3_samples_output_size], 0
                jz	.skip_decoding

                mov	dword [mp3_curr_granule], 0
                mov	ebx, mp3_granules

.body_granule_lop:
                mov	[_@@granule_addr], ebx
                mov	dword [mp3_curr_channel], 0

.body_channel_lop:
                mov     eax, [ebx+4]    ; [ebx+$mp3gr_part2_3_start]
                mov     esi, [mp3_bitstream_start]
                mov     cl, al          ; mp3mac_bitstream_set_position
                shr     eax, 3
                and     cl, 7
                add     esi, eax
                call    mp3_recollect_bits
                mov     eax, ebp        ; mp3mac_get_n_bits cl
                shl     ebp, cl
                rol     eax, cl
                xor     eax, ebp
                sub     ch, cl
                jns     short .cont@
                mov     cl, ch          ; mp3mac_collect_more
                add     ch, 16
                rol     ebp, cl
                mov     bp, [esi]
                add     esi, 2
                ror     bp, 8
                ror     ebp, cl

.cont@:
                call    mp3_bitstream_read_scalefacs
                call    mp3_get_exponents_from_scale_factors
                call    mp3_huffman_decode ; reads up to $mp3gr_part2_3_end
                jc      .error

.body_channel_next:
                add	ebx, 4928       ; $mp3gr_entrysiz*2
                inc	dword [mp3_curr_channel]
                mov	eax, [mp3_curr_channel]
                cmp	eax, [mp3_output_num_channels]
                jb	short .body_channel_lop
                mov	ebx, [_@@granule_addr]

.mp3mac_push_bitstream:
                push	ecx
                push	ebp
                push	esi
                call	mp3_compute_stereo
                mov	dword [mp3_curr_channel], 0

.cast_channel_lop:
                call    mp3_reorder_block
                call    mp3_compute_antialias
                call    mp3_compute_imdct
                add     ebx, 4928       ; $mp3gr_entrysiz*2
                inc	dword [mp3_curr_channel]
                mov     eax, [mp3_curr_channel]
                cmp     eax, [mp3_output_num_channels]
                jc      short .cast_channel_lop

.mp3mac_pop_bitstream:
                pop	esi
                pop	ebp
                pop	ecx
                mov	ebx, [_@@granule_addr]
                add	ebx, 2464       ; $mp3gr_entrysiz
                inc	dword [mp3_curr_granule]
                mov	eax, [mp3_curr_granule]
                cmp	eax, [mp3_nb_granules]
                jc	.body_granule_lop
                call	mp3_uncollect_bits
                cmp	esi, [main_data_pool_wr_ptr]
                ja	short .error
                call	dword [mp3_synth_filter_proc] ; synth maths

.skip_decoding:
                mov     eax, [mp3_extra_bytes]
                add     [mp3_src_frame_size], eax
                mov     eax, [mp3_samples_output_size]
                add     [mp3_total_output_size], eax
                inc     dword [mp3_num_frames_decoded]

.timelog_end:                            ; timelog_end macro ttt
                test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported
                rdtsc                   ; read timestamp counter
                add     [rdtsc_total], eax
                adc     [rdtsc_total+4], edx
		; 22/10/2024
		clc	
		; 20/10/2024
.no_rdtsc_supported:
                ;clc
                retn

.error:
                test    byte [cpuid_flags], 10h ; timelog_end rdtsc_total
                jz      short .no_rdtsc_supported@
                rdtsc
                add     [rdtsc_total], eax
                adc     [rdtsc_total+4], edx

		; 20/10/2024
.no_rdtsc_supported@:
                mov     eax, [mp3_extra_bytes]
                add     [mp3_src_frame_size], eax
                stc
                retn


; =============== S U B R O U T I N E =======================================


mp3_init:
                mov     edi, main_data_pool_start ; = mp3_context_start
                ;mov    ecx, 74916      ; (mp3_context_end-mp3_context_start)/4
                mov     ecx, (mp3_context_end-mp3_context_start)/4
                xor     eax, eax        ; ERRIF @@len AND 03h
                rep stosd               ; clear context
                mov	dword [main_data_pool_wr_ptr], main_data_pool_start
                cmp     dword [mp3_initialized], 0
                jnz     short .already_initialized
                call    mp3_integer_init_is_stereo_lsf
                call    mp3_integer_init_mdct_windows
                call    mp3_integer_init_table_4_3
                call    mp3_integer_init_exponent
                call    mp3_any_init_synth_window
                call    mp3_any_init_band_indices
                call    mp3_any_init_lsf_sf_expand
                call    mp3_any_init_huff_tables
                call    mp3_init_log_constants
                call    mp3_init_post_collapse
                mov     dword [mp3_initialized], 1

.already_initialized:
                movzx   eax, byte [option_fast]
                mov     dword [mp3_bytes_per_sample], 2
                shl     eax, 1
                add     al, [option_8bit]
                test    al, 1
                jz      short .not_8bit
                mov     dword [mp3_bytes_per_sample], 1
.not_8bit:
                imul    eax, 3
                add     al, [option_rate_shift]
                mov     eax, [mp3_synth_filter_procs+eax*4]
                mov     [mp3_synth_filter_proc], eax
                retn


; =============== S U B R O U T I N E =======================================


mp3_check_1st_frame:
                call    mp3_exclude_id3_and_tag
                mov     esi, [stream_pos]
                mov     ecx, [bytes_left]
                xor     edi, edi
                xor     ebp, ebp
                call    mp3_decode_frame
                jc     .error
                call    mp3_check_xing_info
                mov     edx, txt_file_size ; "file size: "
                call    wrstr_edx
                mov     eax, [mp3_file_size]
                call    wr_decimal_eax_with_thousands_seperator
                mov     edx, txt_id3_size ; ", id3 size: "
                call    wrstr_edx
                mov     eax, [mp3_id3_size]
                call    wr_decimal_eax_with_thousands_seperator
                mov     edx, txt_tag_size ; ", tag size: "
                call    wrstr_edx
                mov     eax, [mp3_tag_size]
                call    wr_decimal_eax_with_thousands_seperator
                call    wrcrlf
                mov     edx, txt_input ; "input: "
                call    wrstr_edx
                mov     eax, [mp3_sample_rate]
                call    wr_decimal_eax
                mov     edx, txt_hz ; " hz, "
                call    wrstr_edx
                mov     eax, [mp3_src_num_channels]
                call    wr_decimal_eax
                mov     edx, txt_channels ; " channels, "
                call    wrstr_edx
                mov     eax, [mp3_bit_rate]
                xor     edx, edx
                mov     ecx, 1000
                div     ecx
                call    wr_decimal_eax
                mov     edx, txt_kbit_s ; " kbit/s"
                call    wrstr_edx
                call    wrcrlf
                mov     edx, txt_output ; "output: "
                call    wrstr_edx
                mov     eax, [mp3_output_sample_rate]
                call    wr_decimal_eax
                mov     edx, txt_hz ; " hz, "
                call    wrstr_edx
                mov     eax, [mp3_output_num_channels]
                call    wr_decimal_eax
                mov     edx, txt_channels ; " channels, "
                call    wrstr_edx
                mov     eax, [mp3_bytes_per_sample]
                shl     eax, 3
                call    wr_decimal_eax
                mov     edx, txt_bit ; " bit"
                call    wrstr_edx
                call    wrcrlf
                clc
.error:
                retn

;.error:
                ;stc
                ;retn


; =============== S U B R O U T I N E =======================================

;wrchr:
                ;pusha
                ;mov     [wrchr_buf], al
                ;push    0            ; lpOverlapped
                ;push    diskresult   ; lpNumberOfBytesWritten
                ;push    1            ; nNumberOfBytesToWrite
                ;push    wrchr_buf    ; lpBuffer
                ;push    [std_out]    ; hFile
                ;call    [WriteFile]
                ;popa
                ;retn


; =============== S U B R O U T I N E =======================================


wrstr_edx:
                push    eax
.lop:
                mov     al, [edx]
                inc     edx
                cmp     al, 0
                jz      short .done
                call    wrchr
                jmp     short .lop
.done:
                pop     eax
                retn

; =============== S U B R O U T I N E =======================================


wrcrlf:
                push    eax
                mov     al, 0Dh
                call    wrchr
                mov     al, 0Ah
                call    wrchr
                pop     eax
                retn

; =============== S U B R O U T I N E =======================================


wrspc:
                push    eax
                mov     al, 20h
                call    wrchr
                pop     eax
                retn

; =============== S U B R O U T I N E =======================================


wrcomma:
                push    eax
                mov     al, ','
                call    wrchr
                pop     eax
                retn

; =============== S U B R O U T I N E =======================================


wr_decimal_eax_with_thousands_seperator:
                push    ecx
                mov     cx, 2
                jmp     short wr_decimal_eax_inj

; =============== S U B R O U T I N E =======================================


wr_decimal_eax:
                push    ecx
                xor     ecx, ecx

wr_decimal_eax_inj:
                push    eax
                push    ebx
                push    edx
                mov     ebx, 1000000000 ; nine zeroes (32bit max 4.294.967.296)

.dezlop:
                dec     cl
                jnz     short .no_thousands
                mov     cl, 3
                cmp     ch, 0
                jz      short .no_thousands
                call    wrcomma

.no_thousands:
                xor     edx, edx
                div     ebx
                cmp     ebx, 1
                jz      short .force_last_zero
                or      ch, al
                jz      short .skip_lead_zero

.force_last_zero:
                add     al, 30h
                call    wrchr

.skip_lead_zero:
                push    edx
                mov     eax, ebx
                mov     ebx, 10
                xor     edx, edx
                div     ebx
                cmp     eax, 0
                mov     ebx, eax
                pop     eax
                jnz     short .dezlop
                pop     edx
                pop     ebx
                pop     eax
                pop     ecx
                retn

; =============== S U B R O U T I N E =======================================


wrdigital:
                push    eax
                and     al, 0Fh
                cmp     al, 9
                jbe     short .this
                add     al, 7

.this:
                add     al, 30h
                call    wrchr
                pop     eax
                retn

; =============== S U B R O U T I N E =======================================


wrhexal:
                ror     al, 4
                call    wrdigital
                ror     al, 4
                jmp     short wrdigital

; =============== S U B R O U T I N E =======================================


wrhexax:
                ror     ax, 8
                call    wrhexal
                ror     ax, 8
                jmp     short wrhexal

; =============== S U B R O U T I N E =======================================


wrhexeax:
                ror     eax, 10h
                call    wrhexax
                ror     eax, 10h
                jmp     short wrhexax

; =============== S U B R O U T I N E =======================================

%if 0

get_commandline:
                call    [GetCommandLineA]
                mov     esi, eax
                mov     edi, cmdline_buf
                mov     ecx, 1024       ; cmdline_max

.get_cmdline_lop:
                lodsb
                cmp     al, 0
                stosb
                loopne  .get_cmdline_lop
                mov     byte [edi-1], 0
                mov     esi, cmdline_buf
                mov     edi, cmdline_buf
                call    _@@get_item     ; get/skip name of the executable itself

.get_items_lop:
                call    _@@get_item
                mov     al, [ebx]
                cmp     al, 0
                jz      .done
                cmp     al, '/'
                jz      short .switch
                cmp     al, '-'
                jz      short .switch
                mov     eax, [edi-5]
                or      eax, 20202000h
                ;cmp    eax, 'vaw.'     ; ".wav"
                cmp     eax, '.wav'     ; FASM & NASM syntax
                jnz     short .not_wav_name
                mov     [mp3_dst_fname], ebx
                jmp     short .get_items_lop

.not_wav_name:
                mov     eax, [edi-5]
                or      eax, 20202000h
                ;cmp    eax, 'mcp.'     ; ".pcm"
                cmp     eax, '.pcm'     ; FASM & NASM syntax
                jnz     short .not_pcm_name
                mov     [mp3_pcm_fname], ebx
                jmp     short .get_items_lop

.not_pcm_name:
                mov     [mp3_src_fname], ebx
                jmp     short .get_items_lop

.switch:
                ;cmp	dword [ebx+1], 'onom' ; "mono"
                cmp	dword [ebx+1], 'mono'
                jnz     short .not_switch_mono
                mov	byte [option_mono], 1
                jmp	short .get_items_lop

.not_switch_mono:
                ;cmp	dword [ebx+1], 'tsaf' ; "fast"
                cmp	dword [ebx+1], 'fast' ; FASM & NASM syntax
                jnz	short .not_fast_option
                mov	byte [option_fast], 1
                jmp	short .get_items_lop

.not_fast_option:
                ;cmp    dword [ebx+1], 'tib8' ; "8bit"
                cmp     dword [ebx+1], '8bit'
                jnz     short .not_switch_8bit
                mov     [option_8bit], 1
                jmp     .get_items_lop

.not_switch_8bit:
                ;cmp    dword [ebx+1], 'flah' ; "half"
                cmp     dword [ebx+1], 'half'
                jnz     short .not_switch_half
                mov     [option_rate_shift], 1
                jmp     .get_items_lop

.not_switch_half:
                ;cmp    dword [ebx+1], 'rauq' ; "quar"
                cmp     dword [ebx+1], 'quar'
                jnz     short .not_switch_quarter
                mov     [option_rate_shift], 2
                jmp     .get_items_lop

.not_switch_quarter:
                ;cmp    dword [ebx+1], 'tset' ; "test"
                cmp     dword [ebx+1], 'test'
                jnz     short .not_switch_test
                mov     byte [option_test], 1
                jmp     .get_items_lop

.not_switch_test:
                jmp     short .help

.done:
                cmp	dword [mp3_src_fname], 0
                jz      short .help
                ;;; Erdogan Tan - 17/10/2024
                mov     edx, txt_ctrlc
                call    wrstr_edx
                ;;;
                mov     edx, txt_file ; "file: "
                call    wrstr_edx
                mov     edx, [mp3_src_fname]
                call    wrstr_edx
                call    wrcrlf
                clc
                retn

.help:
                ;;; Erdogan Tan - 17/10/2024
                mov     edx, txt_about
                call    wrstr_edx
                ;;;
                mov     edx, txt_help ; "usage: mp3play input.mp3 [output.wav] ["...
                call    wrstr_edx
                stc
                retn

%endif

; =============== S U B R O U T I N E =======================================

%if 0

_@@get_item:
                lodsb
                dec     al
                cmp     al, 1Fh         ; 20-1
                jbe     short _@@get_item ; _@@skip_spc_lop
                dec     esi
                mov     ebx, edi
                mov     ah, 0           ; flag initially not quoted

.char_lop:
                lodsb
                cmp     al, '"'
                jnz     short .no_quote
                xor     ah, 1
                jmp     short .char_lop

.no_quote:
                stosb
                cmp     al, 0
                jz      short .src_end
                cmp     al, 20h
                ja      short .char_lop
                cmp     ah, 0           ; ignore spaces if inside "quoted area"
                jnz     short .char_lop
                mov     byte [edi-1], 0 ; eol (replace space by 00h)
                retn

.src_end:
                dec     esi
                retn

%endif

; =============== S U B R O U T I N E =======================================


%if 0

open_and_mmap_the_file:
                push    0               ; hTemplateFile
                push    0               ; dwFlagsAndAttributes
                push    3               ; dwCreationDisposition
                push    0               ; lpSecurityAttributes
                push    1               ; dwShareMode
                push    80000000h       ; dwDesiredAccess
                push    [mp3_src_fname] ; lpFileName
                call    [CreateFileA]
                mov     [hFile], eax
                cmp     eax, 0FFFFFFFFh ; INVALID_HANDLE_VALUE
                jz      short .not_found
                push    0               ; lpFileSizeHigh
                push    [hFile]      ; hFile
                call    [GetFileSize]
                mov     [mp3_file_size], eax
                mov     [bytes_left], eax
                push    0               ; lpName
                push    0               ; dwMaximumSizeLow
                push    0               ; dwMaximumSizeHigh
                push    2               ; flProtect
                push    0               ; lpFileMappingAttributes
                push    [hFile]      ; hFile
                call    [CreateFileMappingA]
                mov     [hMap], eax
                push    0               ; dwNumberOfBytesToMap
                push    0               ; dwFileOffsetLow
                push    0               ; dwFileOffsetHigh
                push    4               ; dwDesiredAccess
                push    [hMap]       ; hFileMappingObject
                call    [MapViewOfFile]
                mov     [stream_start], eax
                mov     [stream_pos], eax
                mov     esi, [stream_start]
                mov     ecx, [bytes_left]

.lll:
                lodsb
                loop    .lll
                clc
                retn

.not_found:
                mov     edx, txt_not_found ; "cannot open source file\r\n"
                call    wrstr_edx
                stc
                retn

%endif


; =============== S U B R O U T I N E =======================================


mp3_plain_test_without_output:
                pusha
                mov     esi, [stream_pos]
                mov     ecx, [bytes_left]
                mov     edi, sample_buffer
                xor     ebp, ebp
                call    mp3_decode_frame
                popa
                jc      short .exit
                mov     eax, [mp3_src_frame_size]
                cmp     eax, 0
                jz      short .exit
                add     [stream_pos], eax
                sub     [bytes_left], eax
                jmp     short mp3_plain_test_without_output

.exit:
                retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
mp3_cast_to_wav_file:
                call	mp3_create_wav_file
		; 20/10/2024
		jnc	short .lop
		mov	ebx, -1
		jmp	ExitProcess
.lop:
                pusha
                mov	esi, [stream_pos]
                mov	ecx, [bytes_left]
                mov	edi, sample_buffer
                xor	ebp, ebp
                call	mp3_decode_frame
                popa
                jc	short .exit
                mov	eax, [mp3_src_frame_size]
                cmp	eax, 0
                jz	short .exit
                add	[stream_pos], eax
                sub	[bytes_left], eax
                ;push	0          ; lpOverlapped
                ;push	diskresult ; lpNumberOfBytesWritten
                push	dword [mp3_samples_output_size] ; nNumberOfBytesToWrite
                push	sample_buffer ; lpBuffer
                push	dword [mp3_wav_handle] ; hFile
                ;call	[WriteFile]
		;;;
		; 20/10/2024
		call	WriteFile
		jc	short .exit
		;;;
                mov	eax, [mp3_samples_output_size]
                add	dword [mp3_wav_header+4], eax
                add	dword [mp3_wav_header+28h], eax
                jmp	short .lop

.exit:
                call	mp3_close_wav_file
                retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024

mp3_create_wav_file:
                mov     eax, [mp3_output_sample_rate]
                mov     ecx, [mp3_output_num_channels]
                mov     edx, [mp3_bytes_per_sample]
                mov     word [mp3_wav_header+16h], cx
                mov     dword [mp3_wav_header+18h], eax
                imul    ecx, edx
                imul    eax, ecx
                shl     edx, 3
                mov     dword [mp3_wav_header+1Ch], eax
                mov     word [mp3_wav_header+20h], cx
                mov     word [mp3_wav_header+22h], dx
                ;push   0               ; hTemplateFile
                ;push   80h             ; dwFlagsAndAttributes
                ;push   2               ; dwCreationDisposition
                ;push   0               ; lpSecurityAttributes
                ;push   0               ; dwShareMode
                ;push   0C0000000h      ; dwDesiredAccess
                push    dword [mp3_dst_fname] ; lpFileName
                ;call   [CreateFileA]
		;;;
		; 20/10/2024
		call	CreateFile
		jnc	short .ok
		retn
.ok:
		;;;
                mov     [mp3_wav_handle], eax
                ; 20/10/2024
		;call   mp3_write_wav_header
                ;retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
mp3_write_wav_header:
                ;push	0               ; lpOverlapped
                ;push	diskresult      ; lpNumberOfBytesWritten
                push	44 ; 2Ch        ; nNumberOfBytesToWrite
                push	mp3_wav_header  ; lpBuffer
                push	dword [mp3_wav_handle] ; hFile
                ;call	[WriteFile]
                ;;;
		; 20/10/2024
                call	WriteFile
                ;;;
		retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
mp3_close_wav_file:
                push	0               ; dwMoveMethod
                ;push	0               ; lpDistanceToMoveHigh
                push	0               ; lDistanceToMove
                push	dword [mp3_wav_handle] ; hFile
                ;call	[SetFilePointer]
		;;;
		; 20/10/2024
		call	SetFilePointer
		;;;
                call	mp3_write_wav_header
                push	dword [mp3_wav_handle] ; hObject
                ;call	[CloseHandle]
		;;;
		; 20/10/2024
		call	CloseFile
		;;;
                retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
mp3_verify_pcm_file:
                call    mp3_open_pcm_file
		;;;
		; 20/10/2024
		jnc	short .verify
		retn	; nothing to do (return without error msg)
.verify:
		;;;
                mov	dword [_@@max_diff], 0
                mov	dword [_@@avg_diff], 0
                mov	dword [_@@avg_diff+4], 0
                mov	dword [pcm_filepos], 0

.lop:
                pusha
                mov     esi, [stream_pos]
                mov     ecx, [bytes_left]
                mov     edi, sample_buffer
                xor     ebp, ebp
                call    mp3_decode_frame
                popa
                jb      .exit
                mov     eax, [mp3_src_frame_size]
                cmp     eax, 0
                jz      .exit
                xor     eax, eax
                cmp     dword [mp3_output_num_channels], 2
                jb      short .this_mono_convert
                movzx   eax, byte [option_mono]

.this_mono_convert:
                mov	[_@@mono_convert], eax
                mov	cl, [option_rate_shift]
                mov	eax, 2
                shl	eax, cl
                mov	[_@@pcm_steps], ax
                mov	[_@@pcm_steps+2], ax
                cmp	dword [mp3_output_num_channels], 2
                jb	short .these_steps
                mov	word [_@@pcm_steps], 2
                lea     eax, [eax*2-2] ; [0FFFFFFFEh+eax*2]
                mov     [_@@pcm_steps+2], ax

.these_steps:
                mov     eax, [mp3_samples_output_size]
                mov     cl, [option_rate_shift]
                add     cl, [option_8bit]
                add     cl, byte [_@@mono_convert]
                shl     eax, cl
                ;push   0               ; lpOverlapped
                ;push   diskresult      ; lpNumberOfBytesRead
                push    eax             ; nNumberOfBytesToRead
                push    (sample_buffer+1200h) ; sample_buffer+MP3_MAX_OUTPUT_SIZE
                push    dword [mp3_pcm_handle] ; hFile
                ;call   [ReadFile]
                ;;;
		; 20/10/2024
		call	ReadFile
		jnc	short .pcm_read_ok
		; Note: File read error msg has been displayed
		call	mp3_close_pcm_file
		retn
.pcm_read_ok:
		;;;
		mov     ecx, [mp3_samples_output_size]
                shr     ecx, 1
                jz      .compare_done
                mov     esi, sample_buffer ; decoded .mp3
                mov     edi, (sample_buffer+1200h) ; loaded .pcm

.compare_lop:
                movsx   edx, word [edi]
                cmp     dword [_@@mono_convert], 0
                jz      short .no_mono_convert
                movsx   eax, word [edi+2]
                add     edx, eax
                sar     edx, 1

.no_mono_convert:
                cmp	byte [option_8bit], 0
                jnz	short .compare_8bit
                movsx	eax, word [esi] ; get 16bit from decoded .mp3
                add	esi, 2
                jmp	short .compare_this

.compare_8bit:
                movzx   eax, byte [esi]
                inc     esi             ; convert .pcm
                add     edx, 8000h      ; make unsigned
                sar     edx, 8          ; div 100h
                adc     dl, 0           ; round up
                sbb     dl, 0           ; undo on unsigned overflow

.compare_this:
                sub     eax, edx
                jns     short .compare_abs ; calc difference
                neg     eax

.compare_abs:
                add     [_@@avg_diff], eax
                adc     dword [_@@avg_diff+4], 0
                cmp     eax, [_@@max_diff]
                jb      short .not_max
                mov     [_@@max_diff], eax
                mov     edx, [pcm_filepos]
                mov     [_@@worst_pcm_filepos], edx
                mov     edx, [stream_pos]
                sub     edx, [stream_start]
                mov     [_@@worst_mp3_filepos], edx

.not_max:
                movzx   eax, word [_@@pcm_steps]
                ror     dword [_@@pcm_steps], 16 ; next .pcm addr
                add     edi, eax
                add     [pcm_filepos], eax
                dec     ecx
                jnz    .compare_lop

.compare_done:
                mov     eax, [mp3_src_frame_size]
                add     [stream_pos], eax
                sub     [bytes_left], eax
                jmp     .lop

.exit:
                call    mp3_close_pcm_file
                mov     edx, _@@txt_verify1 ; "verify max difference = "
                call    wrstr_edx
                mov     eax, [_@@max_diff]
                call    wr_decimal_eax
                mov     edx, _@@txt_verify1_at_mp3 ; " at mp3:"
                call    wrstr_edx
                mov     eax, [_@@worst_mp3_filepos]
                call    wrhexeax
                mov     edx, _@@txt_verify2 ; ", average difference = "
                call    wrstr_edx
                mov     eax, [_@@avg_diff]
                mov     edx, [_@@avg_diff+4]
                mov     ecx, [mp3_total_output_size]
                shr     ecx, 1
                div     ecx
                call    wr_decimal_eax
                mov     al, '.'
                call    wrchr
                mov     eax, 10
                mul     edx             ; fraction*10
                div     ecx
                call    wrdigital       ; show fraction of average difference
                call    wrcrlf
                retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
mp3_open_pcm_file:
                ;push	0               ; hTemplateFile
                ;push	80h             ; dwFlagsAndAttributes
                ;push	3               ; dwCreationDisposition
                ;push	0               ; lpSecurityAttributes
                ;push	0               ; dwShareMode
                ;push	80000000h       ; dwDesiredAccess
                push	dword [mp3_pcm_fname] ; lpFileName
                ;call	[CreateFileA]
		;;;
		; 20/10/2024
		call	OpenFile
		;jc	short .return
		;;;
                mov	[mp3_pcm_handle], eax
;.return:
                retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
mp3_close_pcm_file:
                push	dword [mp3_pcm_handle] ; hObject
                ;call	[CloseHandle]
                ;retn
		;;;
		; 20/10/2024
		call	CloseFile
		;;;
		retn


; ===========================================================================
;  TRDOS 386 Operating System Specific Procedures - Erdogan Tan - 20/10/2024
; ===========================================================================

; 20/10/2024
; 20/08/2024 ; TRDOS 386 v2.0.9
; TRDOS 386 system calls
_ver 	equ 0
_exit 	equ 1
_fork 	equ 2
_read 	equ 3
_write	equ 4
_open	equ 5
_close 	equ 6
_wait 	equ 7
_creat 	equ 8
_rename equ 9
_delete equ 10
_exec	equ 11
_chdir	equ 12
_time 	equ 13
_mkdir 	equ 14
_chmod	equ 15
_rmdir	equ 16
_break	equ 17
_drive	equ 18
_seek	equ 19
_tell 	equ 20
_mem	equ 21
_prompt	equ 22
_path	equ 23
_env	equ 24
_stime	equ 25
_quit	equ 26
_intr	equ 27
_dir	equ 28
_emt 	equ 29
_ldvrt 	equ 30
_video 	equ 31
_audio	equ 32
_timer	equ 33
_sleep	equ 34
_msg    equ 35
_geterr	equ 36
_fpsave	equ 37
_pri	equ 38
_rele	equ 39
_fff	equ 40
_fnf	equ 41
_alloc	equ 42
_dalloc equ 43
_calbac equ 44
_dma	equ 45
_stdio  equ 46	;  TRDOS 386 v2.0.9

; ---------------------------------------------------------------------------
; 'sys' macro in FASM format
; ---------------------------------------------------------------------------

%if 0
macro sys op1,op2,op3,op4
{
    if op4 eq 
    else
        mov edx, op4
    end if
    if op3 eq
    else
        mov ecx, op3
    end if
    if op2 eq
    else
        mov ebx, op2
    end if
    mov eax, op1
    int 40h
}
%endif

; ---------------------------------------------------------------------------
; 'sys' macro in NASM format
; ---------------------------------------------------------------------------
; 09/01/2025

%macro sys 1-4
    ; 29/04/2016 - TRDOS 386 (TRDOS v2.0)
    ; 03/09/2015
    ; 13/04/2015
    ; Retro UNIX 386 v1 system call.
    %if %0 >= 2
        mov ebx, %2
        %if %0 >= 3
            mov ecx, %3
            %if %0 = 4
               mov edx, %4
            %endif
        %endif
    %endif
    mov eax, %1
    ;int 30h
    int 40h ; TRDOS 386 (TRDOS v2.0)
%endmacro

; ---------------------------------------------------------------------------

; =============== S U B R O U T I N E =======================================

		; 20/10/2024
wrchr:
		; TRDOS 386 System Call
		; ebx = 2 -> write character onto STDOUT
		;push	ebx
		;push	ecx
		;push	eax
		pusha
		;;mov	dword [diskresult], 0
		sys	_stdio, 2, eax
		;jnc	short .ok ; if EOF, eax = 0
		;xor	eax, eax ; 0
;.ok:
		;mov	[diskresult], eax ; written byte count
		popa
		;pop	eax
		;pop	ecx
		;pop	ebx
		retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
get_commandline:
		; 21/10/2024
		pop	ebp ; near call return address
               	; esp = command line start address
		;mov	[command_line],esp
		pop	ecx	; argc  ; number of arguments
		; esp = pointer to argument 1 ; argv[0]
		dec	ecx
		jz	.help
		pop	eax ; argument 1 (PRG file name)
		pop	esi ; argument 2 (must be input file name)
		mov     edi, cmdline_buf
.get_item:
		mov	ebx, edi
.char_lop:
                lodsb
		stosb
                cmp     al, 0
                jnz 	short .char_lop
		
                mov     al, [ebx]
                cmp     al, '/'
                jz      short .switch
                cmp     al, '-'
                jz      short .switch
                mov     eax, [edi-5]
                or      eax, 20202000h
                cmp     eax, '.wav'     ; FASM & NASM syntax
                jnz     short .not_wav_name
                mov     [mp3_dst_fname], ebx
.get_items_lop:
		dec	ecx
		jz	.done
		pop	esi   ; next argument
		jmp     short .get_item

.not_wav_name:
                mov     eax, [edi-5]
                or      eax, 20202000h
                cmp     eax, '.pcm'     ; FASM & NASM syntax
                jnz     short .not_pcm_name
                mov     [mp3_pcm_fname], ebx
                jmp     short .get_items_lop

.not_pcm_name:
                mov     [mp3_src_fname], ebx
                jmp     short .get_items_lop

.switch:
                cmp	dword [ebx+1], 'mono'
                jnz	short .not_switch_mono
                mov	byte [option_mono], 1
                jmp	short .get_items_lop

.not_switch_mono:
                cmp	dword [ebx+1], 'fast' ; FASM & NASM syntax
                jnz	short .not_fast_option
                mov	byte [option_fast], 1
                jmp	short .get_items_lop

.not_fast_option:
                cmp	dword [ebx+1], '8bit'
                jnz	short .not_switch_8bit
                mov	byte [option_8bit], 1
                jmp	short .get_items_lop

.not_switch_8bit:
                cmp	dword [ebx+1], 'half'
                jnz	short .not_switch_half
                mov	byte [option_rate_shift], 1
                jmp	short .get_items_lop

.not_switch_half:
                cmp	dword [ebx+1], 'quar'
                jnz	short .not_switch_quarter
                mov	byte [option_rate_shift], 2
                jmp	.get_items_lop

.not_switch_quarter:
                cmp	dword [ebx+1], 'test'
                jnz	short .not_switch_test
                mov	byte [option_test], 1
                jmp	.get_items_lop

.done:
                cmp	dword [mp3_src_fname], 0
                jz	short .help
                ;;; Erdogan Tan - 17/10/2024
                ;mov	edx, txt_ctrlc
                ;call	wrstr_edx
		; 20/10/2024
		sys	_msg, txt_ctrlc, txt_ctrlc_size, 0Fh ; white
                ;;;
                mov	edx, txt_file ; "file: "
                call	wrstr_edx
                mov	edx, [mp3_src_fname]
                call	wrstr_edx
                call	wrcrlf
                clc
		push	ebp	; return address
                retn

.not_switch_test:
.help:
                ;;; Erdogan Tan - 17/10/2024
                mov	edx, txt_about
                call	wrstr_edx
                ;;;
                mov	edx, txt_help ; "usage: mp3play input.mp3 [output.wav] ["...
                call	wrstr_edx
                stc
		push	ebp	; return address
                retn

; =============== S U B R O U T I N E =======================================

		; 21/10/2024
set_break:
		; set [u.break] -end of bss- address to
		; end_of_bss at first (mp3 file will be loaded
		; at the end of bss)
		; ([u.break] initially points to the end of PRG file
		; -code and data- except BSS section)
		;
		; TRDOS 386 system call
		; Set break address
		; ebx = new [u.break]
		sys	_break, end_of_bss
		; eax = new break address (dword aligned)

                mov	[stream_start], eax
                mov	[stream_pos], eax

		retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024

open_and_mmap_the_file:
		; 21/10/2024
		; TRDOS 386 system call
		; Open File
		; ebx = pointer to filename
		; ecx = open mode, 0 = read
             	sys	_open, [mp3_src_fname], 0
		jc	short .not_found

                mov     [hFile], eax

               	; get file size by using systell system call
 		; (not applicable for TRDOS 386 Kernel v2.0.9 and earlier)
		; TRDOS 386 system call
		; Get current file (offset) pointer
		; ebx = file handle (file descriptor)
		; ecx = 0, offset
		; edx = 2, from the end of file
		;sys	_tell, eax, 0, 2
                ;mov     [mp3_file_size], eax

		; *** get file size ***
		; TRDOS 386 system call
		; Set file (offset) pointer to file size 
		; (needed for TRDOS kernel v2.0.9 and earlier)
		; ebx = file handle (file descriptor)
		; ecx = 0, offset
		; edx = 2, from the end of file
		sys	_seek, eax, 0, 2
		; TRDOS 386 system call
		; Get current file (offset) pointer
		; (needed for TRDOS 386 kernel version 2.0.9 and earlier)
		xor	edx, edx ; 0
		; ecx = 0
		; ebx = file handle
		sys	_tell
		mov     [mp3_file_size], eax

		; *** set file offset pointer to 0 again ***
		; TRDOS 386 system call
		; Set file (offset) pointer
		; ebx = file handle (file descriptor)
		; ecx = 0, offset
		; edx = 0, from the beginning/start of file
		push	eax
		sys	_seek
		pop	eax

		; now, set [u.break] address to the end of mp3 file
		; at memory -in BSS section-
		; (not necessary for TRDOS 386 PRG files)
		; (this system call will allocate user memory pages
		;  before sysread system call.. early)
		add	eax, end_of_bss
		; TRDOS 386 system call
		; Set break address
		; ebx = new [u.break]
		sys	_break, eax

		; TRDOS 386 system call
		; Read file
		; ebx = file handle (file descriptor)
		; ecx = buffer address
		; edx = byte count
		sys	_read, [hFile], [stream_start], [mp3_file_size]
		jc	short .read_error
		cmp	eax, edx
		jnb	short .ok
		;or	eax, eax
		;jnz	short .ok
.read_error:		
		; TRDOS 386 system call
		; Close file
		; ebx = file handle (file descriptor)
		;sys	_close, [hFile]
 		sys	_close

		mov	edx, txt_read_err
		jmp	short .r_err_msg
.ok:
                mov     [bytes_left], eax ; read count
		retn
.not_found:
                mov     edx, txt_not_found ; "cannot open source file\r\n"
.r_err_msg:
                call    wrstr_edx
                stc
                retn

;txt_read_err	db 'File read error!',0Dh,0Ah,0


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
print_msg:
		; TRDOS 386 system call
		; write/display message on screen
		; ebx = ASCIIZ message (text) address
		; ecx = max. message length (stop count before char zero)
		; edx = character color (CGA)
		mov	ecx, 255
		mov	edx, 0Bh ; DL ; cyan
		sys	_msg
		retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
GetTickCount:
		; TRDOS 386 system call
		; get current time, get tick count
		; ebx = 4 -> get count of system timer ticks
		sys	_time, 4
		; eax = system timer ticks (18.2 ticks per second)
		mov	edx, 549254165	; 10^10/18.2
		mul	edx
		; edx:eax = milliseconds * 10^7
		mov	ebx, 10000000
		div	ebx		; 10^7
		; eax = milliseconds
		cmp	edx, 5000000	; 10^7/2
		jb	short .ok
		inc	eax		; round up
.ok:
		retn


; =============== E X I T ===================================================

		; 20/10/2024
ExitProcess:
		xor	ebx, ebx  ; mov ebx, 0  ; exit code
		sys	_exit
;hang:
		;jmp	short hang


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
WriteFile:
		pop	eax ; near call return address
		pop	ebx
		pop	ecx
		pop	edx
		push	eax
		; TRDOS 386 system call
		; Write file
		; ebx = file handle (file descriptor)
		; ecx = buffer address
		; edx = byte count
		sys	_write
		jnc	short .ok
		cmp	eax, edx
		jnb	short .ok
		;or	eax, eax
		;jnz	short .ok

		mov	edx, txt_write_err
                call    wrstr_edx
                stc
.ok:
                retn

txt_write_err	db 'File write error!',0Dh,0Ah,0


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
CreateFile:
		pop	eax ; near call return address
		pop	ebx
		push	eax
		; TRDOS 386 system call
		; Create file
		; ebx = (ASCIIZ) file name address
		; ecx = mode
		xor	ecx, ecx ; CL ; mov ecx, 0 ; ordinary file
		sys	_creat
		jnc	short .ok ; eax = file handle

		mov	edx, txt_create_err
                call    wrstr_edx
                stc
.ok:
		retn

txt_create_err	db 'File create error!',0Dh,0Ah,0


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
OpenFile:
		pop	eax ; near call return address
		pop	ebx
		push	eax
		; TRDOS 386 system call
		; Open file
		; ebx = (ASCIIZ) file name address
		; ecx = mode
		xor	ecx, ecx ; CL ; mov ecx, 0 ; ordinary file
		sys	_open
		;jnc	short .ok ; eax = file handle
		;
		;mov	edx, txt_open_err
                ;call   wrstr_edx
                ;stc
;.ok:
		retn

;txt_open_err	db 'File not found!',0Dh,0Ah,0
		;db 'File open error!',ODh,0Ah,0
	 

; =============== S U B R O U T I N E =======================================

		; 20/10/2024
SetFilePointer:
		pop	eax ; near call return address
		pop	ebx
		pop	ecx
		pop	edx
		push	eax
		; TRDOS 386 system call
		; Set file offset pointer  ; sysseek
		; ebx = file handle (file descriptor)
		; ecx = offset
		; edx = switch, DL = 0 = from the start of file
		;		     1 = from the current offset
		;		     2 = from the end of file
		sys	_seek
		; eax = (value of) new offset pointer

		retn


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
ReadFile:
		pop	eax ; near call return address
		pop	ebx
		pop	ecx
		pop	edx
		push	eax
		; TRDOS 386 system call
		; Read file
		; ebx = file handle (file descriptor)
		; ecx = buffer address
		; edx = byte count
		sys	_read
		jnc	short .ok
		cmp	eax, edx
		jnb	short .ok
		;or	eax, eax
		;jnz	short .ok

		mov	edx, txt_read_err
                call    wrstr_edx
                stc
.ok:
                retn

txt_read_err	db 'File read error!',0Dh,0Ah,0


; =============== S U B R O U T I N E =======================================

		; 20/10/2024
CloseFile:
		pop	eax ; near call return address
		pop	ebx
		push	eax
		; TRDOS 386 system call
		; Close file
		; ebx = file handle (file descriptor)
		sys	_close

		retn


; ---------------------------------------------------------------------------
; TRDOS 386 Audio System Functions
; ---------------------------------------------------------------------------

; =============== S U B R O U T I N E =======================================

		; 10/01/2025
		; 20/10/2024
detect_enable_audio_device:
		mov	word [max_frequency], 48000
		; 10/01/2025
		;mov	byte [blocks], 8

		; check AC'97 hardware at first
		; (48kHz support)
		; TRDOS 386 system call
		; sysaudio
		; Detect (BH=1) AC'97 (BL=2) Audio Device
.ac97:
        	sys	_audio, 0102h
		jc	short .sb16
		mov	byte [audio_hardware], 2 ; AC97
		; TRDOS 386 system call
		; sysaudio
		; Get AC'97 Codec info
		; (Function 14, sub function 1)
		sys	_audio, 0E01h
		; Save Variable Rate Audio support bit
		and	al, 1
		mov	[vra], al
		retn
.sb16:
		; check Sound Blaster 16 card at second
		; (44100Hz support, but 24kHz will be used)
		; TRDOS 386 system call
		; sysaudio
		; Detect (BH=1) SB16 (BL=1) Audio Card
        	sys	_audio, 0101h
		jc	short .vt8233
		mov	byte [audio_hardware], 1 ; SB16
		mov	word [max_frequency], 44100
		; 10/01/2025
		;;mov	byte [blocks], 7
		;dec	byte [blocks]
		retn
.vt8233:
		; check VIA VT3237R (VT8233) hardware at third
		; (48kHz support)
		; TRDOS 386 system call
		; sysaudio
		; Detect (BH=1) VT8237R (BL=3) Audio Device
		sys	_audio, 0103h
		jc	short .hda
		mov	byte [audio_hardware], 3 ; VT8237R
		retn
.hda:	
		; check Intel HDA hardware at last
		; (48kHz support)
		; TRDOS 386 system call
		; sysaudio
		; Detect (BH=1) Intel HDA (BL=4) Audio Device
		sys	_audio, 0104h
		jc	short .err
		mov	byte [audio_hardware], 4 ; HDA
		retn
.err:
		mov	edx, txt_audio_nf_err
                call    wrstr_edx
                stc
		retn

txt_audio_nf_err: db 'Proper audio hardware not found!',0Dh,0Ah,0


; =============== CONSTANT ==================================================

		; 21/10/2024
MP3_MAX_OUTPUT_SIZE equ 2*2*18*32*2
    ; = 1200h = 4608 decimal = 2 channels, 2 granules, 18*32, 2 byte(16bit)


; =============== S U B R O U T I N E =======================================


audio_system_init:
		;mov	eax, sample_buffer_size
		; 10/01/2025
		;mov	byte [blocks], 16
		; 12/01/2025
		mov	byte [blocks], 8
		mov	eax, [mp3_samples_output_size]
		shl	eax, 3 ; * 8
		;shl	eax, 4 ; * 16
.asi@:		
		; 12/01/2025
		;cmp	eax, 65536
		;jna	short .asi@@
		;sub	eax, [mp3_samples_output_size]
		;dec	byte [blocks]
		;;;
		; 11/01/2025
		;test	byte [blocks], 1
		;jz	short .asi@
		;dec	byte [blocks] ; even number
		;sub	eax, [mp3_samples_output_size]
		;;;
		;jmp	short .asi@
.asi@@:
		cmp	byte [audio_hardware], 1 ; SB16
		jne	short .bufaloc
.asi@@@:
		; 10/01/2025
		cmp	eax, 32768
		jna	short .bufaloc
		; sample_buffer_size = 36864 bytes ; 8 blocks
		;sub	eax, MP3_MAX_OUTPUT_SIZE
		; eax = 32256 ; 7 blocks
		; 10/01/2025
		sub	eax, [mp3_samples_output_size]
		dec	byte [blocks]
		;;;
		; 11/01/2025
		;test	byte [blocks], 1
		;jz	short .asi@@@
		;dec	byte [blocks] ; even number
		;sub	eax, [mp3_samples_output_size]
		;;;
		jmp	short .asi@@@
.bufaloc:
		; TRDOS 386 system call
		; sysaudio
		; Allocate audio buffer (for user)
		; ebx = 0200h (BH=2)
		; ecx = buffer size (in bytes)
		; edx = buffer address (virtual)
		mov	[buffer_size], eax
		sys	_audio, 0200h, eax, sample_buffer
		jc	short .init_err

		; 12/01/2025
		; clear audio buffer (before playback)
		mov	edi, sample_buffer
		; ecx = buffer size in bytes
		shr	ecx, 2 ; double word
		xor	eax, eax
		rep	stosd

		; TRDOS 386 system call
		; sysaudio
		; Initialize audio device (bh = 3)
		; bl = 01h -> CallBack method
		; edx = Callback service address (virtual)
		; ecx = 0 ; CL = srb value ; not used
		;sys	_audio, 0301h, 0, audio_callback
		; 12/01/2025
		; SRB method (faster than callback method)
		; bl = 0 -> Signal Response Byte method
		; cl = 1 -> SRB set value 
		;     (will be set by audio IRQ service of the kernel)
		; edx = SRB address -one byte data-
		sys	_audio, 0300h, 1, srb	
		jc	short .init_err
		retn
.init_err:
		mov	edx, txt_audio_init_err
                call    wrstr_edx
                stc
		retn

txt_audio_init_err: db 'Audio hardware initialization error!',0Dh,0Ah,0


; =============== S U B R O U T I N E =======================================

; 12/01/2025
%if 0
		; 21/10/2024
audio_callback:
		; Operating system has directed CPU here because of
		; user (2nd) stage of the audio hardware interrupt service.
		; This procedure must be short and return to operating
		; system again via sysrelease system call
		; (or any system call here will be handled as sysrelease).

		mov	byte [srb], 1

		sys	_rele ; return from callback service 
		
		; we must not come here !
		mov	ebx, -1
		sys	_exit
		;jmp	short audio_callback
%endif

; =============== S U B R O U T I N E =======================================

		; 10/01/2025
		; 21/10/2024
mp3_cast_to_speaker:
		;call	try_enqueue_all_blocks

		;cmp	dword [bytes_left],0
		;jz	short .playback

		; 12/01/2025
		; (here audio buffer -sample_buffer- is empty)
		; (clear dma half buffer 1)
		sys	_audio, 1001h
		; (clear dma half buffer 2)
		;sys	_audio, 1002h

		; TRDOS 386 system call
		; sysaudio
		; bh = 16 : update (current, first) dma half buffer
		; bl = 0  : then switch to the next (second) half buffer
		sys	_audio, 1000h

		; 22/10/2024
		;call	try_enqueue_all_blocks
.playback:
		; TRDOS 386 system call
		; sysaudio
		; Set Master Volume Level (BL=0 or 80h)
		; 	for next playing (BL>=80h)
		;sys	_audio, 0B80h, 1D1Dh
		sys	_audio, 0B00h, 1D1Dh

		;mov	byte [volume_level], 1Dh
		mov	[volume_level], cl

		; Start	to play
		mov	eax, [mp3_bytes_per_sample]
		;shr	al, 1 ; 8 -> 0, 16 -> 1
		;shl	al, 1 ; 16 -> 2, 8 -> 0
		and	al, 2 ; 22/10/2024
		mov	ebx, [mp3_output_num_channels]
		dec	ebx
		or	bl, al
		mov	ecx, [mp3_output_sample_rate]
		mov	bh, 4 ; start to play

		; TRDOS 386 system call
		; sysaudio
		; bh = 4 -> start to play
		; bl = mode -> bit 0, 1 = stereo, 0 = mono
		;	       bit 1, 1 = 16 bit, 0 = 8 bit
		; cx = sample rate (hertz)
		sys	_audio

		; 12/01/2025
		mov	byte [srb], 0
		;;;

.playback_lop:
		xor	eax, eax
		cmp	[bytes_left], eax ; 0
		jnz	short .playback_next
.pb@@@:
		; 22/10/2024
		cmp	byte [num_enqueued_frames], al ; 0
                jz	short .playback_end
.playback_next:
		mov	[num_enqueued_frames], al ; 0
		cmp	byte [srb], 1	; audio interrupt status
		jb	short .getchar
		;mov	byte [srb], 0	; reset
		mov	[srb], al ; 0
		call	try_enqueue_all_blocks
		jmp	short .playback_lop
.playback_end:
		; TRDOS 386 system call
		; sysaudio
		; Stop playing
		sys	_audio, 0700h
		; Cancel callback service (for user)
		sys	_audio, 0900h
		; Deallocate audio buffer (for user)
		sys	_audio, 0A00h
		; Disable audio device
		sys	_audio, 0C00h
		retn

.getchar:
		; TRDOS 386 system call
		; sysstdio
		; BL = 1 -> read a character on stdin (no wait)
		;sys	_stdio, 1
		;and	eax, eax
		;jz	short .playback_next

		; 11/01/2025
		mov	ah, 1
		int	32h	;  (TRDOS 386 keyboard interrupt)
		jz	short .playback_next
		xor	ah, ah
		int	32h	; (TRDOS 386 keyboard interrupt)

		cmp	al, '+' ; increase sound volume
		je	short .inc_volume
		cmp	al, '-'
		je	short .dec_volume

		;;;
		; 10/01/2025
		;cmp	ah, 01h
		cmp	al, 1Bh	; ESC
		je	short .playback_end
		;cmp	ax, 2E03h
		cmp	al, 03h	; CTRL+C
		je	short .playback_end
		;;;
.inc_volume:
		mov	cl, [volume_level]
		cmp	cl, 1Fh ; 31
		jnb	.playback_next
		inc	cl
.chg_volume:
		mov	[volume_level], cl
		mov	ch, cl
		; TRDOS 386 system call
		; sysstdio
		; Set master volume level
		; bh = 11
		; cl = left channel volume (0 to 31 max)
		; ch = right channel volume (0 to 31 max)
		sys	_audio, 0B00h
		jmp	.playback_next
.dec_volume:
		mov	cl, [volume_level]
		cmp	cl, 1 ; 1
		jna	.playback_next
		dec	cl
		jmp	short .chg_volume


; =============== S U B R O U T I N E =======================================

		; 09/01/2025
		; 21/10/2024
try_enqueue_all_blocks:
		mov	edi, sample_buffer
		; 12/01/2025
		;mov	edi, decoding_buffer
		; 11/01/2025
		;cmp	dword [bytes_left], 0
		;jna	short .enqueue_done
		; 10/01/2025
		jmp	short .first_block
.next_block:
		cmp	dword [bytes_left], 0
		jle	short .enqueue_done
		;
		mov	edi, [mp3_samples_dst]
		add	edi, [mp3_samples_output_size]
.first_block:
		;pusha
		mov	esi, [stream_pos]
		mov	ecx, [bytes_left]
		xor	ebp, ebp
		call	mp3_decode_frame
		;popa
		jc	short .enqueue_done

		mov	eax, [mp3_src_frame_size]
		cmp	eax, 0
 		jz	short .enqueue_done
		add	[stream_pos], eax
		sub	[bytes_left], eax

		mov	eax, [mp3_samples_output_size]
		cmp	eax, 0
		jz	short .next_block
.no_error:
		inc	byte [num_enqueued_frames]
		
		mov	al, [num_enqueued_frames]
		cmp	al, [blocks]
		jb	short .next_block
		retn
.enqueue_done:
		mov	dword [bytes_left], 0
		retn


; ===========================================================================
; end of TRDOS 386 specific procedures.
; ---------------------------------------------------------------------------

; ===========================================================================
; Initialized DATA
; ===========================================================================

option_test     db 0                   
option_mono     db 0                   
option_8bit     db 0                   
option_rate_shift db 0                 
option_fast     db 0                   
                align 4
cpuid_flags     dd 0                   
cpuid_exists    db 0                   
detected_cpu    db 0                   
                align 4
mp3_output_milliseconds dd 0           
millisecond_count dd 0

; 20/10/2024                 
; HANDLE hProcess
;hProcess       dd 0                   
; HANDLE hThread
;hThread        dd 0                   
; DWORD dwPriorityClass
;dwPriorityClass dd 0                   
; int nPriority
;nPriority      dd 0
                   
ttt             dd 2 dup(0)            
rdtsc_read_header db 'read header    ',0
rdtsc_read_header_extra dd  0, 0       
                db 'read extra     ',0
rdtsc_read_granule dd 0, 0             
                db 'read granule   ',0
rdtsc_append_main dd 2 dup(0)          
                db 'append main    ',0
rdtsc_read_scalefac dd 2 dup(0)        
                db 'read scalefac  ',0
rdtsc_xlat_scalefac dd 2 dup(0)        
                db 'xlat scalefac  ',0
rdtsc_read_huffman dd 2 dup(0)         
                db 'read huffman   ',0
rdtsc_ms_stereo dd 2 dup(0)            
                db 'ms stereo      ',0
rdtsc_i_stereo  dd 2 dup(0)            
                db 'i stereo       ',0
rdtsc_reorder   dd 2 dup(0)            
                db 'reorder        ',0
rdtsc_antialias dd 2 dup(0)            
                db 'antialias      ',0
rdtsc_imdct     dd 2 dup(0)            
                db 'imdct          ',0
rdtsc_imdct36   dd 2 dup(0)            
                db ' imdct36       ',0
rdtsc_imdct12   dd 2 dup(0)            
                db ' imdct12       ',0
rdtsc_imdct0    dd 2 dup(0)            
                db ' imdct0        ',0
rdtsc_synth_dct dd 2 dup(0)            
                db 'synth/dct      ',0
rdtsc_dct32     dd 2 dup(0)            
                db ' synth.dct32   ',0
rdtsc_synth     dd 2 dup(0)            
                db ' synth.output  ',0
rdtsc_total     dd 2 dup(0)            
                db 'total          ',0
mp3_bitrate_tab dw  0,32,40,48,56,64,80,96,112,128,160,192,224,256,320, 0
                dw  0, 8,16,24,32,40,48,56,64,80,96,112,128,144,160, 0
mp3_freq_tab    dw 44100,48000,32000   
mp3_lsf_sf_expand_init_table db 0, 5, 4, 4, 0, 0
                dw 400                  ; 0..399 ; normal case
                db 0, 5, 4, 1, 0Ch, 0
                dw 500                  ; 400..499
                db 0, 3, 1, 1, 18h, 1
                dw 512                  ; 500..511
                db 1, 6, 6, 1, 24h, 0
                dw 872                  ; 512+360 ; 0..359 for 2nd channel of intensity stereo
                db 1, 4, 4, 1, 30h, 0
                dw 1000                 ; 512+488 ; 360..487
                db 1, 3, 1, 1, 3Ch, 0
                dw 1024                 ; 512+512 ; 488..511
mp3_synth_win_src dw      1,     0,     0,     0,     0,     0,     1,     0
                dw      0,     0,     1,     0,     1,     0,     1,     0
                dw      1,     1,     0,     1,     1,     1,     1,     2
                dw      1,     2,     1,     2,     2,     3,     2,     3
                dw      2,     4,     3,     3,     4,     4,     4,     5
                dw      5,     5,     5,     6,     6,     6,     6,     7
                dw      7,     6,     8,     7,     7,     8,     7,     7
                dw      8,     7,     7,     7,     6,     6,     6,     5
                dw 0FE51h,0FFFCh,0FFFDh,0FFFEh,0FFFFh,     0,     1,     3
                dw      3,     6,     7,     8,   0Bh,   0Ch,   0Eh,   11h
                dw    13h,   15h,   17h,   1Ah,   1Ch,   1Fh,   22h,   24h
                dw    27h,   2Ah,   2Ch,   2Fh,   32h,   35h,   36h,   3Ah
                dw    3Ch,   3Eh,   40h,   42h,   44h,   45h,   47h,   48h
                dw    49h,   49h,   49h,   49h,   49h,   48h,   46h,   45h
                dw    43h,   40h,   3Dh,   3Ah,   35h,   31h,   2Bh,   27h
                dw    1Fh,   19h,   12h,   0Ah,     2,0FFF9h,0FFEFh,0FFE6h
                dw 0F03Bh,   30h,   3Bh,   47h,   53h,   5Fh,   6Dh,   79h
                dw    86h,   95h,  0A1h,  0B0h,  0BDh,  0CBh,  0D9h,  0E6h
                dw   0F3h,  101h,  10Dh,  119h,  125h,  130h,  13Ah,  144h
                dw   14Dh,  155h,  15Bh,  162h,  166h,  16Ah,  16Bh,  16Dh
                dw   16Ch,  16Ah,  166h,  160h,  15Ah,  150h,  146h,  139h
                dw   12Bh,  11Ah,  108h,  0F3h,  0DDh,  0C5h,  0A9h,   8Eh
                dw    6Fh,   4Eh,   2Bh,     7,0FFE1h,0FFB8h,0FF8Fh,0FF62h
                dw 0FF35h,0FF06h,0FED5h,0FEA4h,0FE70h,0FE3Ch,0FE06h,0FDD0h
                dw 0CF0Bh,  29Fh,  2D7h,  311h,  349h,  382h,  3BBh,  3F4h
                dw   42Ch,  464h,  49Ah,  4D1h,  505h,  538h,  56Ah,  59Bh
                dw   5C8h,  5F5h,  620h,  647h,  66Ch,  68Fh,  6AFh,  6CCh
                dw   6E5h,  6FCh,  70Fh,  71Fh,  72Bh,  734h,  739h,  739h
                dw   737h,  730h,  726h,  717h,  704h,  6EDh,  6D3h,  6B4h
                dw   691h,  66Ch,  640h,  613h,  5E1h,  5ABh,  573h,  537h
                dw   4F7h,  4B4h,  46Fh,  427h,  3DBh,  38Fh,  33Eh,  2EDh
                dw   29Ah,  244h,  1EDh,  195h,  13Dh,  0E2h,   88h,   2Eh
                db    0
                db    0
mp3_slen_table  dw  0000h, 0100h, 0200h, 0300h, 0003h, 0101h, 0201h, 0301h
                dw  0102h, 0202h, 0302h, 0103h, 0203h, 0303h, 0204h, 0304h
mp3_lsf_nsf_table dd  05050506h, 09090909h, 09090906h
                dd  03070506h, 060C0909h, 060C0906h
                dd  00000A0Bh, 00001212h, 0000120Fh
                dd  00070707h, 000C0C0Ch, 000C0F06h
                dd  03060606h, 0609090Ch, 06090C06h
                dd  00050808h, 00090C0Fh, 00091206h
huff_tree_list_data db  11h,   1, 10h,   0, 22h,   2, 12h, 21h
                db  20h, 11h,   1, 10h,   0, 22h,   2, 12h
                db  21h, 20h, 10h, 11h,   1,   0, 33h, 23h
                db  32h, 31h, 13h,   3, 30h, 22h, 12h, 21h
                db    2, 20h, 11h,   1, 10h,   0, 33h,   3
                db  23h, 32h, 30h, 13h, 31h, 22h,   2, 12h
                db  21h, 20h,   1, 11h, 10h,   0, 55h, 45h
                db  54h, 53h, 35h, 44h, 25h, 52h, 15h, 51h
                db    5, 34h, 50h, 43h, 33h, 24h, 42h, 14h
                db  41h, 40h,   4, 23h, 32h,   3, 13h, 31h
                db  30h, 22h, 12h, 21h,   2, 20h, 11h,   1
                db  10h,   0, 55h, 54h, 45h, 53h, 35h, 44h
                db  25h, 52h,   5, 15h, 51h, 34h, 43h, 50h
                db  33h, 24h, 42h, 14h, 41h,   4, 40h, 23h
                db  32h, 13h, 31h,   3, 30h, 22h,   2, 20h
                db  12h, 21h, 11h,   1, 10h,   0, 55h, 45h
                db  35h, 53h, 54h,   5, 44h, 25h, 52h, 15h
                db  51h, 34h, 43h, 50h,   4, 24h, 42h, 33h
                db  40h, 14h, 41h, 23h, 32h, 13h, 31h,   3
                db  30h, 22h,   2, 12h, 21h, 20h, 11h,   1
                db  10h,   0, 77h, 67h, 76h, 57h, 75h, 66h
                db  47h, 74h, 56h, 65h, 37h, 73h, 46h, 55h
                db  54h, 63h, 27h, 72h, 64h,   7, 70h, 62h
                db  45h, 35h,   6, 53h, 44h, 17h, 71h, 36h
                db  26h, 25h, 52h, 15h, 51h, 34h, 43h, 16h
                db  61h, 60h,   5, 50h, 24h, 42h, 33h,   4
                db  14h, 41h, 40h, 23h, 32h,   3, 13h, 31h
                db  30h, 22h, 12h, 21h,   2, 20h, 11h,   1
                db  10h,   0, 77h, 67h, 76h, 75h, 66h, 47h
                db  74h, 57h, 55h, 56h, 65h, 37h, 73h, 46h
                db  45h, 54h, 35h, 53h, 27h, 72h, 64h,   7
                db  71h, 17h, 70h, 36h, 63h, 60h, 44h, 25h
                db  52h,   5, 15h, 62h, 26h,   6, 16h, 61h
                db  51h, 34h, 50h, 43h, 33h, 24h, 42h, 14h
                db  41h,   4, 40h, 23h, 32h, 13h, 31h,   3
                db  30h, 22h, 21h, 12h,   2, 20h, 11h,   1
                db  10h,   0, 77h, 67h, 76h, 57h, 75h, 66h
                db  47h, 74h, 65h, 56h, 37h, 73h, 55h, 27h
                db  72h, 46h, 64h, 17h, 71h,   7, 70h, 36h
                db  63h, 45h, 54h, 44h,   6,   5, 26h, 62h
                db  61h, 16h, 60h, 35h, 53h, 25h, 52h, 15h
                db  51h, 34h, 43h, 50h,   4, 24h, 42h, 14h
                db  33h, 41h, 23h, 32h, 40h,   3, 30h, 13h
                db  31h, 22h, 12h, 21h,   2, 20h,   0, 11h
                db    1, 10h,0FEh,0FCh,0FDh,0EDh,0FFh,0EFh
                db 0DFh,0EEh,0CFh,0DEh,0BFh,0FBh,0CEh,0DCh
                db 0AFh,0E9h,0ECh,0DDh,0FAh,0CDh,0BEh,0EBh
                db  9Fh,0F9h,0EAh,0BDh,0DBh, 8Fh,0F8h,0CCh
                db 0AEh, 9Eh, 8Eh, 7Fh, 7Eh,0F7h,0DAh,0ADh
                db 0BCh,0CBh,0F6h, 6Fh,0E8h, 5Fh, 9Dh,0D9h
                db 0F5h,0E7h,0ACh,0BBh, 4Fh,0F4h,0CAh,0E6h
                db 0F3h, 3Fh, 8Dh,0D8h, 2Fh,0F2h, 6Eh, 9Ch
                db  0Fh,0C9h, 5Eh,0ABh, 7Dh,0D7h, 4Eh,0C8h
                db 0D6h, 3Eh,0B9h, 9Bh,0AAh, 1Fh,0F1h,0F0h
                db 0BAh,0E5h,0E4h, 8Ch, 6Dh,0E3h,0E2h, 2Eh
                db  0Eh, 1Eh,0E1h,0E0h, 5Dh,0D5h, 7Ch,0C7h
                db  4Dh, 8Bh,0B8h,0D4h, 9Ah,0A9h, 6Ch,0C6h
                db  3Dh,0D3h, 7Bh, 2Dh,0D2h, 1Dh,0B7h, 5Ch
                db 0C5h, 99h, 7Ah,0C3h,0A7h, 97h, 4Bh,0D1h
                db  0Dh,0D0h, 8Ah,0A8h, 4Ch,0C4h, 6Bh,0B6h
                db  3Ch, 2Ch,0C2h, 5Bh,0B5h, 89h, 1Ch,0C1h
                db  98h, 0Ch,0C0h,0B4h, 6Ah,0A6h, 79h, 3Bh
                db 0B3h, 88h, 5Ah, 2Bh,0A5h, 69h,0A4h, 78h
                db  87h, 94h, 77h, 76h,0B2h, 1Bh,0B1h, 0Bh
                db 0B0h, 96h, 4Ah, 3Ah,0A3h, 59h, 95h, 2Ah
                db 0A2h, 1Ah,0A1h, 0Ah, 68h,0A0h, 86h, 49h
                db  93h, 39h, 58h, 85h, 67h, 29h, 92h, 57h
                db  75h, 38h, 83h, 66h, 47h, 74h, 56h, 65h
                db  73h, 19h, 91h,   9, 90h, 48h, 84h, 72h
                db  46h, 64h, 28h, 82h, 18h, 37h, 27h, 17h
                db  71h, 55h,   7, 70h, 36h, 63h, 45h, 54h
                db  26h, 62h, 35h, 81h,   8, 80h, 16h, 61h
                db    6, 60h, 53h, 44h, 25h, 52h,   5, 15h
                db  51h, 34h, 43h, 50h, 24h, 42h, 33h, 14h
                db  41h,   4, 40h, 23h, 32h, 13h, 31h,   3
                db  30h, 22h, 12h, 21h,   2, 20h, 11h,   1
                db  10h,   0,0FFh,0EFh,0FEh,0DFh,0EEh,0FDh
                db 0CFh,0FCh,0DEh,0EDh,0BFh,0FBh,0CEh,0ECh
                db 0DDh,0AFh,0FAh,0BEh,0EBh,0CDh,0DCh, 9Fh
                db 0F9h,0EAh,0BDh,0DBh, 8Fh,0F8h,0CCh, 9Eh
                db 0E9h, 7Fh,0F7h,0ADh,0DAh,0BCh, 6Fh,0AEh
                db  0Fh,0CBh,0F6h, 8Eh,0E8h, 5Fh, 9Dh,0F5h
                db  7Eh,0E7h,0ACh,0CAh,0BBh,0D9h, 8Dh, 4Fh
                db 0F4h, 3Fh,0F3h,0D8h,0E6h, 2Fh,0F2h, 6Eh
                db 0F0h, 1Fh,0F1h, 9Ch,0C9h, 5Eh,0ABh,0BAh
                db 0E5h, 7Dh,0D7h, 4Eh,0E4h, 8Ch,0C8h, 3Eh
                db  6Dh,0D6h,0E3h, 9Bh,0B9h, 2Eh,0AAh,0E2h
                db  1Eh,0E1h, 0Eh,0E0h, 5Dh,0D5h, 7Ch,0C7h
                db  4Dh, 8Bh,0D4h,0B8h, 9Ah,0A9h, 6Ch,0C6h
                db  3Dh,0D3h,0D2h, 2Dh, 0Dh, 1Dh, 7Bh,0B7h
                db 0D1h, 5Ch,0D0h,0C5h, 8Ah,0A8h, 4Ch,0C4h
                db  6Bh,0B6h, 99h, 0Ch, 3Ch,0C3h, 7Ah,0A7h
                db 0A6h,0C0h, 0Bh,0C2h, 2Ch, 5Bh,0B5h, 1Ch
                db  89h, 98h,0C1h, 4Bh,0B4h, 6Ah, 3Bh, 79h
                db 0B3h, 97h, 88h, 2Bh, 5Ah,0B2h,0A5h, 1Bh
                db 0B1h,0B0h, 69h, 96h, 4Ah,0A4h, 78h, 87h
                db  3Ah,0A3h, 59h, 95h, 2Ah,0A2h, 1Ah,0A1h
                db  0Ah,0A0h, 68h, 86h, 49h, 94h, 39h, 93h
                db  77h,   9, 58h, 85h, 29h, 67h, 76h, 92h
                db  91h, 19h, 90h, 48h, 84h, 57h, 75h, 38h
                db  83h, 66h, 47h, 28h, 82h, 18h, 81h, 74h
                db    8, 80h, 56h, 65h, 37h, 73h, 46h, 27h
                db  72h, 64h, 17h, 55h, 71h,   7, 70h, 36h
                db  63h, 45h, 54h, 26h, 62h, 16h,   6, 60h
                db  35h, 61h, 53h, 44h, 25h, 52h, 15h, 51h
                db    5, 50h, 34h, 43h, 24h, 42h, 33h, 41h
                db  14h,   4, 23h, 32h, 40h,   3, 13h, 31h
                db  30h, 22h, 12h, 21h,   2, 20h, 11h,   1
                db  10h,   0,0EFh,0FEh,0DFh,0FDh,0CFh,0FCh
                db 0BFh,0FBh,0AFh,0FAh, 9Fh,0F9h,0F8h, 8Fh
                db  7Fh,0F7h, 6Fh,0F6h,0FFh, 5Fh,0F5h, 4Fh
                db 0F4h,0F3h,0F0h, 3Fh,0CEh,0ECh,0DDh,0DEh
                db 0E9h,0EAh,0D9h,0EEh,0EDh,0EBh,0BEh,0CDh
                db 0DCh,0DBh,0AEh,0CCh,0ADh,0DAh, 7Eh,0ACh
                db 0CAh,0C9h, 7Dh, 5Eh,0BDh,0F2h, 2Fh, 0Fh
                db  1Fh,0F1h, 9Eh,0BCh,0CBh, 8Eh,0E8h, 9Dh
                db 0E7h,0BBh, 8Dh,0D8h, 6Eh,0E6h, 9Ch,0ABh
                db 0BAh,0E5h,0D7h, 4Eh,0E4h, 8Ch,0C8h, 3Eh
                db  6Dh,0D6h, 9Bh,0B9h,0AAh,0E1h,0D4h,0B8h
                db 0A9h, 7Bh,0B7h,0D0h,0E3h, 0Eh,0E0h, 5Dh
                db 0D5h, 7Ch,0C7h, 4Dh, 8Bh, 9Ah, 6Ch,0C6h
                db  3Dh, 5Ch,0C5h, 0Dh, 8Ah,0A8h, 99h, 4Ch
                db 0B6h, 7Ah, 3Ch, 5Bh, 89h, 1Ch,0C0h, 98h
                db  79h,0E2h, 2Eh, 1Eh,0D3h, 2Dh,0D2h,0D1h
                db  3Bh, 97h, 88h, 1Dh,0C4h, 6Bh,0C3h,0A7h
                db  2Ch,0C2h,0B5h,0C1h, 0Ch, 4Bh,0B4h, 6Ah
                db 0A6h,0B3h, 5Ah,0A5h, 2Bh,0B2h, 1Bh,0B1h
                db  0Bh,0B0h, 69h, 96h, 4Ah,0A4h, 78h, 87h
                db 0A3h, 3Ah, 59h, 2Ah, 95h, 68h,0A1h, 86h
                db  77h, 94h, 49h, 57h, 67h,0A2h, 1Ah, 0Ah
                db 0A0h, 39h, 93h, 58h, 85h, 29h, 92h, 76h
                db    9, 19h, 91h, 90h, 48h, 84h, 75h, 38h
                db  83h, 66h, 28h, 82h, 47h, 74h, 18h, 81h
                db  80h,   8, 56h, 37h, 73h, 65h, 46h, 27h
                db  72h, 64h, 55h,   7, 17h, 71h, 70h, 36h
                db  63h, 45h, 54h, 26h, 62h, 16h, 61h,   6
                db  60h, 53h, 35h, 44h, 25h, 52h, 51h, 15h
                db    5, 34h, 43h, 50h, 24h, 42h, 33h, 14h
                db  41h,   4, 40h, 23h, 32h, 13h, 31h,   3
                db  30h, 22h, 12h, 21h,   2, 20h, 11h,   1
                db  10h,   0,0EFh,0FEh,0DFh,0FDh,0CFh,0FCh
                db 0BFh,0FBh,0FAh,0AFh, 9Fh,0F9h,0F8h, 8Fh
                db  7Fh,0F7h, 6Fh,0F6h, 5Fh,0F5h, 4Fh,0F4h
                db  3Fh,0F3h, 2Fh,0F2h,0F1h, 1Fh,0F0h, 0Fh
                db 0EEh,0DEh,0EDh,0CEh,0ECh,0DDh,0BEh,0EBh
                db 0CDh,0DCh,0AEh,0EAh,0BDh,0DBh,0CCh, 9Eh
                db 0E9h,0ADh,0DAh,0BCh,0CBh, 8Eh,0E8h, 9Dh
                db 0D9h, 7Eh,0E7h,0ACh,0FFh,0CAh,0BBh, 8Dh
                db 0D8h, 0Eh,0E0h, 0Dh,0E6h, 6Eh, 9Ch,0C9h
                db  5Eh,0BAh,0E5h,0ABh, 7Dh,0D7h,0E4h, 8Ch
                db 0C8h, 4Eh, 2Eh, 3Eh, 6Dh,0D6h,0E3h, 9Bh
                db 0B9h,0AAh,0E2h, 1Eh,0E1h, 5Dh,0D5h, 7Ch
                db 0C7h, 4Dh, 8Bh,0B8h,0D4h, 9Ah,0A9h, 6Ch
                db 0C6h, 3Dh,0D3h, 2Dh,0D2h, 1Dh, 7Bh,0B7h
                db 0D1h, 5Ch,0C5h, 8Ah,0A8h, 99h, 4Ch,0C4h
                db  6Bh,0B6h,0D0h, 0Ch, 3Ch,0C3h, 7Ah,0A7h
                db  2Ch,0C2h, 5Bh,0B5h, 1Ch, 89h, 98h,0C1h
                db  4Bh,0C0h, 0Bh, 3Bh,0B0h, 0Ah, 1Ah,0B4h
                db  6Ah,0A6h, 79h, 97h,0A0h,   9, 90h,0B3h
                db  88h, 2Bh, 5Ah,0B2h,0A5h, 1Bh,0B1h, 69h
                db  96h,0A4h, 4Ah, 78h, 87h, 3Ah,0A3h, 59h
                db  95h, 2Ah,0A2h,0A1h, 68h, 86h, 77h, 49h
                db  94h, 39h, 93h, 58h, 85h, 29h, 67h, 76h
                db  92h, 19h, 91h, 48h, 84h, 57h, 75h, 38h
                db  83h, 66h, 28h, 82h, 18h, 47h, 74h, 81h
                db    8, 80h, 56h, 65h, 17h,   7, 70h, 73h
                db  37h, 27h, 72h, 46h, 64h, 55h, 71h, 36h
                db  63h, 45h, 54h, 26h, 62h, 16h, 61h,   6
                db  60h, 35h, 53h, 44h, 25h, 52h, 15h,   5
                db  50h, 51h, 34h, 43h, 24h, 42h, 33h, 14h
                db  41h,   4, 40h, 23h, 32h, 13h, 31h,   3
                db  30h, 22h, 12h, 21h,   2, 20h, 11h,   1
                db  10h,   0, 0Bh, 0Fh, 0Dh, 0Eh,   7,   5
                db    9,   6,   3, 0Ah, 0Ch,   2,   1,   4
                db    8,   0, 0Fh, 0Eh, 0Dh, 0Ch, 0Bh, 0Ah
                db    9,   8,   7,   6,   5,   4,   3,   2
                db    1,   0
                db 6 dup(0)
mp3_huff_data   db   0,  0             
                db   1,  0              ; byte[32][2] ; table,linbits
                db   2,  0
                db   3,  0
                db   0,  0
                db   4,  0
                db   5,  0
                db   6,  0
                db   7,  0
                db   8,  0
                db   9,  0
                db  10,  0
                db  11,  0
                db  12,  0
                db   0,  0
                db  13,  0
                db  14,  1
                db  14,  2
                db  14,  3
                db  14,  4
                db  14,  6
                db  14,  8
                db  14, 10
                db  14, 13
                db  15,  4
                db  15,  5
                db  15,  6
                db  15,  7
                db  15,  8
                db  15,  9
                db  15, 11
                db  15, 13
mp3_band_size_long db    4,   4,   4,   4,   4,   4,   6,   6,   8,   8, 0Ah
                db  0Ch, 10h, 14h, 18h, 1Ch, 22h, 2Ah, 32h, 36h, 4Ch, 9Eh ; byte[9][22]
                db    4,   4,   4,   4,   4,   4,   6,   6,   6,   8, 0Ah
                db  0Ch, 10h, 12h, 16h, 1Ch, 22h, 28h, 2Eh, 36h, 36h,0C0h
                db    4,   4,   4,   4,   4,   4,   6,   6,   8, 0Ah, 0Ch
                db  10h, 14h, 18h, 1Eh, 26h, 2Eh, 38h, 44h, 54h, 66h, 1Ah
                db    6,   6,   6,   6,   6,   6,   8, 0Ah, 0Ch, 0Eh, 10h
                db  14h, 18h, 1Ch, 20h, 26h, 2Eh, 34h, 3Ch, 44h, 3Ah, 36h
                db    6,   6,   6,   6,   6,   6,   8, 0Ah, 0Ch, 0Eh, 10h
                db  12h, 16h, 1Ah, 20h, 26h, 2Eh, 34h, 40h, 46h, 4Ch, 24h
                db    6,   6,   6,   6,   6,   6,   8, 0Ah, 0Ch, 0Eh, 10h
                db  14h, 18h, 1Ch, 20h, 26h, 2Eh, 34h, 3Ch, 44h, 3Ah, 36h
                db    6,   6,   6,   6,   6,   6,   8, 0Ah, 0Ch, 0Eh, 10h
                db  14h, 18h, 1Ch, 20h, 26h, 2Eh, 34h, 3Ch, 44h, 3Ah, 36h
                db    6,   6,   6,   6,   6,   6,   8, 0Ah, 0Ch, 0Eh, 10h
                db  14h, 18h, 1Ch, 20h, 26h, 2Eh, 34h, 3Ch, 44h, 3Ah, 36h
                db  0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 10h, 14h, 18h, 1Ch, 20h
                db  28h, 30h, 38h, 40h, 4Ch, 5Ah,   2,   2,   2,   2,   2
                db 10 dup(0)            ; data align
mp3_band_size_short db    4,   4,   4,   4,   6,   8, 0Ah, 0Ch, 0Eh, 12h, 16h, 1Eh, 38h
                db    4,   4,   4,   4,   6,   6, 0Ah, 0Ch, 0Eh, 10h, 14h, 1Ah, 42h ; byte[9][16] ? ; byte [9][13]
                db    4,   4,   4,   4,   6,   8, 0Ch, 10h, 14h, 1Ah, 22h, 2Ah, 0Ch
                db    4,   4,   4,   6,   6,   8, 0Ah, 0Eh, 12h, 1Ah, 20h, 2Ah, 12h
                db    4,   4,   4,   6,   8, 0Ah, 0Ch, 0Eh, 12h, 18h, 20h, 2Ch, 0Ch
                db    4,   4,   4,   6,   8, 0Ah, 0Ch, 0Eh, 12h, 18h, 1Eh, 28h, 12h
                db    4,   4,   4,   6,   8, 0Ah, 0Ch, 0Eh, 12h, 18h, 1Eh, 28h, 12h
                db    4,   4,   4,   6,   8, 0Ah, 0Ch, 0Eh, 12h, 18h, 1Eh, 28h, 12h
                db    8,   8,   8, 0Ch, 10h, 14h, 18h, 1Ch, 24h,   2,   2,   2, 1Ah
                db 11 dup(0)            ; data align
mp3_pretab      db    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0
                db    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0
                db    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0
                db    1,   1,   1,   1,   2,   2,   3,   3,   3,   2,   0
                db 4 dup(0)             ; data align
mp3_mdct_win_src dd  00421D4Bh, 00DB8F02h, 019C7F16h, 029ADCC0h, 04000001h, 06246711h
                dd  09EE0645h, 12A7D60Ch, 3DF40538h,0BC63D32Fh,0E7B0025Bh,0F069D222h ; these are sine values divided by cosine values...
                dd 0F4337156h,0F657D867h,0F7BCFBA8h,0F8BB5952h,0F97C4965h,0FA15BB1Ch
                dd 0FA946D93h,0FB00518Eh,0FB5EA270h,0FBB2FDEAh,0FC000000h,0FC479F38h
                dd 0FC8B6609h,0FCCC9898h,0FD0C4F0Bh,0FD4B895Ch,0FD8B3FCFh,0FDCC725Eh
                dd 0FE10392Fh,0FE57D867h,0FEA4DA7Dh,0FEF935F7h,0FF5786D9h,0FFC36AD5h
                dd  00421D4Bh, 00DB8F02h, 019C7F16h, 029ADCC0h, 04000001h, 06246711h
                dd  09EE0645h, 12A7D60Ch, 3DF40538h,0BC63D32Fh,0E7B0025Bh,0F069D222h
                dd 0F4337156h,0F657D867h,0F7BCFBA8h,0F8BB5952h,0F97C4965h,0FA15BB1Ch
                dd 0FA931B29h,0FAF546B9h,0FB41DABBh,0FB7D8F97h,0FBABA162h,0FBCE4E62h
                dd 0FBF01C67h,0FC45C8AFh,0FCD2D50Dh,0FD9008D0h,0FE74C032h,0FF771894h
                dd  00000000h, 00000000h, 00000000h, 00000000h, 00000000h, 00000000h
                dd  00DB8F02h, 04000001h, 12A7D60Ch,0E7B0025Bh,0F657D867h,0F97C4965h
                dd 0FB00518Eh,0FC000000h,0FCCC9898h,0FD8B3FCFh,0FE57D867h,0FF5786D9h
                dd  00000000h, 00000000h, 00000000h, 00000000h, 00000000h, 00000000h
                dd  00000000h, 00000000h, 00000000h, 00000000h, 00000000h, 00000000h
                dd  00000000h, 00000000h, 00000000h, 00000000h, 00000000h, 00000000h
                dd  00000000h, 00000000h, 00000000h, 00000000h, 00000000h, 00000000h
                dd  00000000h, 00000000h, 00000000h, 00000000h, 00000000h, 00000000h
                dd  026988B5h, 0BBA3752h, 37D3294Fh,0B73F655Bh,0E3B0025Bh,0EDAD5D13h
                dd 0F2B2ADA2h,0F58C28B8h,0F75657D6h,0F88E2C57h,0F96DE565h,0FA1449CDh
                dd 0FA946D93h,0FB00518Eh,0FB5EA270h,0FBB2FDEAh,0FC000000h,0FC479F38h
                dd 0FC8B6609h,0FCCC9898h,0FD0C4F0Bh,0FD4B895Ch,0FD8B3FCFh,0FDCC725Eh
                dd 0FE10392Fh,0FE57D867h,0FEA4DA7Dh,0FEF935F7h,0FF5786D9h,0FFC36AD5h
mp3_is_table_normal dd  00000000h, 40000000h
                dd  0D8658BBh, 3279A746h
                dd  176CF5D1h, 28930A30h
                dd  20000000h, 20000000h
                dd  28930A30h, 176CF5D1h
                dd  3279A746h, 0D8658BBh
                dd  40000000h, 00000000h
mp3_is_table_lsf_src dd 80000000h      
                                        ; sqrt based constants...
                                        ; 40000000h*2 ; 2.0  (2^1.00) aka 2
                dd 6BA27E66h            ; 35D13F33h*2 ; 1.681 (2^0.75)
                dd 5A82799Ah            ; 2D413CCDh*2 ; 1.414 (2^0.50) aka sqrt(2)
                dd 4C1BF82Ah            ; 260DFC15h*2 ; 1.189 (2^0.25) aka sqrt(sqrt(2))
mp3_pow2_quarters dd 80000000h         
                                        ; 40000000h*2 ; 2^(0/4)
                dd 9837F052h            ; 4C1BF829h*2 ; 2^(1/4)
                dd 0B504F334h           ; 5A82799Ah*2 ; 2^(2/4)
                dd 0D744FCCCh           ; 6BA27E66h*2 ; 2^(3/4)
mp3_initialized dd 0                   
mp3_huff_num_entries dd 12h            
wrchr_buf       db 0                   
                align 4
; LPCSTR mp3_src_fname
mp3_src_fname   dd 0                   
; LPCSTR mp3_dst_fname
mp3_dst_fname   dd 0                   
; LPCSTR mp3_pcm_fname
mp3_pcm_fname   dd 0                   
mp3_wav_header  db 'RIFF$',0,0,0,'WAVEfmt ',10h,0,0,0,1,0,2,0,0,0,0,0,0,0,0,0,4,0,10h,0,'data',0,0,0,0
; 21/10/2024                   
zero		dd 0  
num_enqueued_frames db 0
txt_decode_timing1 db 'audio duration ',0
txt_decode_timing2 db ' milliseconds, decoded in ',0
txt_decode_timing3 db ' milliseconds',0Dh,0Ah,0
txt_clks_per_second db ' clock cycles per second:',0Dh,0Ah,0
huff_tree_list_numbits db    3,   3,   2,   1,   6,   6,   5,   5
                db    5,   3,   3,   3,   1,   6,   6,   5
                db    5,   5,   3,   2,   2,   2,   8,   8
                db    7,   6,   7,   7,   7,   7,   6,   6
                db    6,   6,   3,   3,   3,   1,   7,   7
                db    6,   6,   6,   5,   5,   5,   5,   4
                db    4,   4,   3,   2,   3,   3, 0Ah, 0Ah
                db  0Ah, 0Ah,   9,   9,   9,   9,   8,   8
                db    9,   9,   8,   9,   9,   8,   8,   7
                db    7,   7,   8,   8,   8,   8,   7,   7
                db    7,   7,   6,   5,   6,   6,   4,   3
                db    3,   1, 0Bh, 0Bh, 0Ah,   9, 0Ah, 0Ah
                db    9,   9,   9,   8,   8,   9,   9,   9
                db    9,   8,   8,   8,   7,   8,   8,   8
                db    8,   8,   8,   8,   8,   6,   6,   6
                db    4,   4,   2,   3,   3,   2,   9,   9
                db    8,   8,   9,   9,   8,   8,   8,   8
                db    7,   7,   7,   8,   8,   7,   7,   7
                db    7,   6,   6,   6,   6,   5,   5,   6
                db    6,   5,   5,   4,   4,   4,   3,   3
                db    3,   3, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Bh
                db  0Bh, 0Ah,   9,   9, 0Ah, 0Ah,   9,   9
                db  0Ah, 0Ah,   9, 0Ah, 0Ah,   8,   8,   9
                db    9, 0Ah, 0Ah,   9,   9, 0Ah, 0Ah,   8
                db    8,   8,   9,   9,   9,   9,   9,   9
                db    8,   8,   8,   8,   8,   8,   7,   7
                db    7,   7,   6,   6,   6,   6,   4,   3
                db    3,   1, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Bh, 0Bh, 0Ah, 0Ah,   9,   9,   9
                db  0Ah, 0Ah, 0Ah, 0Ah,   8,   8,   9,   9
                db    7,   8,   8,   8,   8,   8,   9,   9
                db    9,   9,   8,   7,   8,   8,   7,   7
                db    8,   8,   8,   9,   9,   8,   8,   8
                db    8,   8,   8,   7,   7,   6,   6,   7
                db    7,   6,   5,   4,   5,   5,   3,   3
                db    3,   2, 0Ah, 0Ah,   9,   9,   9,   9
                db    9,   9,   9,   8,   8,   9,   9,   8
                db    8,   8,   8,   8,   8,   9,   9,   8
                db    8,   8,   8,   8,   9,   9,   7,   7
                db    7,   8,   8,   8,   8,   8,   8,   7
                db    7,   7,   7,   8,   8,   7,   7,   7
                db    6,   6,   6,   6,   7,   7,   6,   5
                db    5,   5,   4,   4,   5,   5,   4,   3
                db    3,   3, 13h, 13h, 12h, 11h, 10h, 10h
                db  10h, 10h, 10h, 10h, 10h, 10h, 10h, 10h
                db  11h, 11h, 0Fh, 0Fh, 10h, 10h, 0Fh, 0Fh
                db  0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh
                db  10h, 10h, 0Fh, 10h, 10h, 0Eh, 0Eh, 0Fh
                db  0Fh, 0Fh, 0Fh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh
                db  0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Fh, 0Fh
                db  0Eh, 0Dh, 0Eh, 0Eh, 0Dh, 0Dh, 0Eh, 0Eh
                db  0Dh, 0Eh, 0Eh, 0Dh, 0Eh, 0Eh, 0Dh, 0Eh
                db  0Eh, 0Dh, 0Dh, 0Eh, 0Eh, 0Ch, 0Ch, 0Ch
                db  0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Ch, 0Dh
                db  0Dh, 0Ch, 0Ch, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh
                db  0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Ch
                db  0Ch, 0Dh, 0Dh, 0Ch, 0Ch, 0Ch, 0Ch, 0Dh
                db  0Dh, 0Dh, 0Dh, 0Ch, 0Dh, 0Dh, 0Ch, 0Bh
                db  0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Ch, 0Ch, 0Bh, 0Bh
                db  0Ch, 0Ch, 0Bh, 0Ch, 0Ch, 0Ch, 0Ch, 0Bh
                db  0Bh, 0Ch, 0Ch, 0Bh, 0Ch, 0Ch, 0Bh, 0Ch
                db  0Ch, 0Bh, 0Ch, 0Ch, 0Ah, 0Ah, 0Ah, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Bh, 0Bh, 0Ah, 0Bh, 0Bh
                db  0Ah, 0Bh, 0Bh, 0Bh, 0Bh, 0Ah, 0Ah, 0Bh
                db  0Bh, 0Ah, 0Ah, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh,   9,   9, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Bh, 0Bh,   9,   9,   9, 0Ah, 0Ah,   9
                db    9, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Ah,   8,   9,   9,   9,   9
                db    9,   9, 0Ah, 0Ah,   9,   9,   9,   8
                db    8,   9,   9,   9,   9,   9,   9,   8
                db    7,   8,   8,   8,   8,   7,   7,   7
                db    7,   7,   6,   6,   6,   6,   4,   4
                db    3,   1, 0Dh, 0Dh, 0Dh, 0Dh, 0Ch, 0Dh
                db  0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Ch, 0Dh, 0Dh
                db  0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch
                db  0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch
                db  0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Dh
                db  0Dh, 0Bh, 0Bh, 0Ch, 0Ch, 0Ch, 0Ch, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Ch, 0Ch, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Ch
                db  0Ch, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Bh, 0Ch, 0Ch, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Bh, 0Ah, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Ah, 0Ah, 0Bh, 0Bh, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Bh, 0Bh, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Bh, 0Bh, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Bh, 0Bh,   9, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db    9, 0Ah, 0Ah, 0Ah, 0Ah,   9, 0Ah, 0Ah
                db    9, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah,   9,   9,   9,   9,   9,   9,   9
                db  0Ah, 0Ah,   9,   9,   9,   9,   9,   9
                db  0Ah, 0Ah,   9,   9,   9,   9,   9,   9
                db    8,   9,   9,   9,   9,   9,   9,   9
                db    9,   9,   9,   8,   8,   8,   8,   9
                db    9,   9,   9,   9,   9,   9,   9,   8
                db    8,   8,   8,   8,   8,   9,   9,   8
                db    8,   8,   8,   8,   8,   8,   9,   9
                db    8,   7,   8,   8,   7,   7,   7,   7
                db    8,   8,   7,   7,   7,   7,   7,   6
                db    7,   7,   6,   6,   7,   7,   6,   6
                db    6,   5,   5,   5,   5,   5,   3,   4
                db    4,   3, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Bh, 0Ah, 0Bh, 0Bh, 0Bh, 0Bh, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Ah,   8, 0Ah, 0Ah,   9
                db    9,   9,   9, 0Ah, 10h, 11h, 11h, 0Fh
                db  0Fh, 10h, 10h, 0Eh, 0Fh, 0Fh, 0Eh, 0Eh
                db  0Fh, 0Fh, 0Eh, 0Eh, 0Fh, 0Fh, 0Fh, 0Fh
                db  0Eh, 0Fh, 0Fh, 0Eh, 0Dh,   8,   9,   9
                db    8,   8, 0Dh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh
                db  0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Dh, 0Dh, 0Eh
                db  0Eh, 0Eh, 0Eh, 0Dh, 0Eh, 0Eh, 0Dh, 0Dh
                db  0Dh, 0Eh, 0Eh, 0Eh, 0Eh, 0Dh, 0Dh, 0Eh
                db  0Eh, 0Dh, 0Eh, 0Eh, 0Ch, 0Dh, 0Dh, 0Dh
                db  0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh
                db  0Dh, 0Dh, 0Dh, 0Ch, 0Dh, 0Dh, 0Dh, 0Dh
                db  0Dh, 0Dh, 0Ch, 0Dh, 0Dh, 0Ch, 0Ch, 0Dh
                db  0Dh, 0Bh, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch
                db  0Ch, 0Dh, 0Dh, 0Bh, 0Ch, 0Ch, 0Ch, 0Ch
                db  0Bh, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch
                db  0Ch, 0Bh, 0Ch, 0Ch, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch
                db  0Bh, 0Ch, 0Ch, 0Bh, 0Ch, 0Ch, 0Bh, 0Ch
                db  0Ch, 0Bh, 0Ch, 0Ch, 0Bh, 0Ah, 0Ah, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Ah, 0Ah, 0Bh
                db  0Bh, 0Ah, 0Ah, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Ah, 0Bh, 0Bh, 0Ah, 0Ah
                db  0Ah, 0Bh, 0Bh, 0Ah, 0Ah, 0Bh, 0Bh, 0Ah
                db  0Ah, 0Bh, 0Bh, 0Ah,   9,   9, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Ah,   9,   9,   9, 0Ah
                db  0Ah,   9, 0Ah, 0Ah,   9,   9,   8,   9
                db    9,   9,   9,   9,   9,   9,   9,   8
                db    8,   9,   9,   8,   8,   7,   7,   8
                db    8,   7,   6,   6,   6,   6,   4,   4
                db    3,   1,   8,   8,   8,   8,   8,   8
                db    8,   8,   7,   8,   8,   7,   7,   8
                db    8,   7,   7,   7,   7,   7,   7,   7
                db    7,   7,   7,   7,   7,   8,   8,   9
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Bh, 0Bh, 0Bh,   4, 0Bh, 0Bh, 0Bh
                db  0Bh, 0Ch, 0Ch, 0Bh, 0Ah, 0Bh, 0Bh, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Bh, 0Bh, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Bh, 0Bh, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Bh, 0Bh, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db  0Ah, 0Bh, 0Bh, 0Ah, 0Bh, 0Bh, 0Ah,   9
                db  0Ah, 0Ah, 0Ah, 0Ah, 0Bh, 0Bh, 0Ah,   9
                db    9, 0Ah, 0Ah,   9, 0Ah, 0Ah, 0Ah, 0Ah
                db    9,   9, 0Ah, 0Ah,   9,   9,   9,   9
                db    9,   9,   9,   9,   9,   9,   9,   9
                db    9,   9,   9,   9,   9,   9,   9,   9
                db    9,   9,   9,   9,   9,   9,   9,   9
                db    9,   9,   9,   9,   9,   9,   9,   9
                db  0Ah, 0Ah,   9,   9,   9, 0Ah, 0Ah,   8
                db    9,   9,   8,   8,   8,   8,   8,   8
                db    8,   8,   8,   8,   8,   8,   8,   9
                db    9,   8,   8,   8,   8,   8,   8,   9
                db    9,   7,   8,   8,   7,   7,   7,   7
                db    7,   8,   8,   7,   7,   6,   6,   7
                db    7,   6,   5,   5,   6,   6,   4,   4
                db    4,   4,   6,   6,   6,   6,   6,   6
                db    5,   5,   5,   5,   5,   4,   4,   4
                db    4,   1,   4,   4,   4,   4,   4,   4
                db    4,   4,   4,   4,   4,   4,   4,   4
                db    4,   4
_@@const_3      db 3                   
                db 3 dup(0)
mp3_synth_filter_procs dd synth_16bit_shift_0_slow ; SYNTH_MACRO 0,0,0
                dd synth_16bit_shift_1_slow ; SYNTH_MACRO 0,1,0
                dd synth_16bit_shift_2_slow ; SYNTH_MACRO 0,2,0
                dd synth_8bit_shift_0_slow ; SYNTH_MACRO 1,0,0
                dd synth_8bit_shift_1_slow ; SYNTH_MACRO 1,1,0
                dd synth_8bit_shift_2_slow ; SYNTH_MACRO 1,2,0
                dd synth_16bit_shift_0_fast ; SYNTH_MACRO 0,0,1
                dd synth_16bit_shift_1_fast ; SYNTH_MACRO 0,1,1
                dd synth_16bit_shift_2_fast ; SYNTH_MACRO 0,2,1
                dd synth_8bit_shift_0_fast ; SYNTH_MACRO 1,0,1
                dd synth_8bit_shift_1_fast ; SYNTH_MACRO 1,1,1
                dd synth_8bit_shift_2_fast ; SYNTH_MACRO 1,2,1
;txt_hello      db 'nocash mp3 decoder v1.4, 2024 martin korth, press ctrl+c to quit,'
;               db ' BDS now',0Dh,0Ah,0
; Erdogan Tan - 17/10/2024
txt_hello       db 13,10
		;db 'NOCASH MP3 PLAYER v1.4 for Windows ',0
		; 09/01/2025
		db 'NOCASH MP3 PLAYER v1.0 for TRDOS386 ',0
		 
txt_file        db 'file: ',0          
txt_file_size   db 'file size: ',0     
txt_id3_size    db ', id3 size: ',0    
txt_tag_size    db ', tag size: ',0    
txt_input       db 'input: ',0         
txt_output      db 'output: ',0        
txt_hz          db ' hz, ',0           
txt_channels    db ' channels, ',0     
txt_bit         db ' bit',0            
txt_kbit_s      db ' kbit/s',0         
txt_not_found   db 'cannot open source file',0Dh,0Ah,0
txt_help        db 'usage: mp3play input.mp3 [output.wav] [verify.pcm] [/test]', 0Dh,0Ah
                db '                         [/mono] [/8bit] [/fast] [/half|/quarter]',0Dh,0Ah,0
_@@txt_verify1  db 'verify max difference = ',0
_@@txt_verify1_at_mp3 db ' at mp3:',0  
_@@txt_verify2  db ', average difference = ',0

; Erdogan Tan - 17/10/2024
               ;db 'NOCASH MP3 PLAYER v1.4 for Windows ',0
txt_ctrlc       db '(press CTRL+C to quit)', 13,10,0
txt_ctrlc_size equ $ - txt_ctrlc
txt_about       db 13,10
                ;db '----------------------------------',13,10
                db '-----------------------------------',13,10
                db 'Erdogan Tan - 12/01/2025 (Assembler: NASM)', 13,10
                db 'Original code: MP3PLAYER.EXE v1.4 (20/09/2024)', 13,10
                db '               by Martin Korth (TASM source code)'
                db 13,10,13,10,0
                db 'v1.4.0',0

; ===========================================================================
; Uninitialized DATA (BSS)
; ===========================================================================

align 4

bss_start:

; 10/01/2025
ABSOLUTE bss_start

alignb 4
		resw 1	; 09/01/2025
;;;
; 20/10/2024 (TRDOS 386 specific parameters)
audio_hardware	resb 1
vra		resb 1
max_frequency	resw 1
srb		resb 1
volume_level	resb 1
blocks		resb 1
		resb 1
buffer_size	resd 1
;;;	

mp3_context_start:
main_data_pool_start	resb 4096
main_data_pool_wr_ptr	resd 1
mp3_src_data_location	resd 1
mp3_src_frame_size	resd 1
mp3_src_frame_end	resd 1
mp3_hdr_32bit_header	resd 1
mp3_hdr_flag_crc	resd 1
mp3_hdr_flag_mpeg25	resd 1
mp3_hdr_flag_padding	resd 1
mp3_sample_rate		resd 1
mp3_hdr_sample_rate_index resd 1
mp3_bit_rate		resd 1
mp3_src_num_channels	resd 1
mp3_output_num_channels resd 1
mp3_output_sample_rate	resd 1
mp3_bytes_per_sample	resd 1
mp3_curr_syn_index	resd 1
mp3_curr_syn_dst	resd 1
mp3_nb_frames		resd 1
mp3_hdr_mode_val	resd 1
mp3_hdr_mode_ext	resd 1
mp3_hdr_flag_lsf	resd 1
mp3_synth_filter_proc	resd 1

mp3_synth_buf   resd 2048
mp3_synth_index resd 2
mp3_sb_samples  resd 2304
	                           ; MP3_MAX_CHANNELS*36*SBLIMIT
mp3_mdct_buf    resd 1152
                                   ; MP3_MAX_CHANNELS*SBLIMIT*18
mp3_free_format_frame_size resd 1

mp3_curr_vfrac_bits resb 1

alignb 4

mp3_xing_id     resd 1
mp3_xing_flags  resd 1
mp3_xing_frames resd 1
mp3_xing_filesize resd 1
mp3_xing_toc    resb 100
mp3_xing_vbr_scale resd 1
mp3_file_size   resd 1
mp3_id3_size    resd 1
mp3_tag_size    resd 1

mp3_num_frames_decoded	resd 1
mp3_total_output_size	resd 1
mp3_samples_dst		resd 1
; DWORD mp3_samples_output_size
mp3_samples_output_size	resd 1
mp3_samples_dst_step	resd 1

mp3_curr_channel	resd 1
mp3_curr_granule	resd 1
mp3_curr_frame		resd 1

mp3_bitstream_start	resd 1
mp3_src_remain		resd 1
mp3_extra_bytes		resd 1
mp3_main_data_begin	resd 1
mp3_num_compress_bits	resd 1

mp3_nb_granules resd 1

mp3_granules		resb 9856
mp3_exponents		resw 576
huff_tree_buf		resb 0B800h
mp3_band_index_long	resw 288
mp3_table_4_3_exp	resb 32828

mp3_table_4_3_value	resd 32828
mp3_exp_table		resd 512
mp3_expval_table	resd 8192
mp3_mdct_win		resd 288
mp3_is_table_lsf	resd 512
mp3_synth_win		resd 1024
mp3_lsf_sf_expand_exploded_table resb 8192
mp3_context_end:
_@@region_address0	resd 1
_@@region_address1	resd 1
_@@saved_sp		resd 1
mp3_main_data_siz	resd 1
_@@scfsi        resd 1
_@@gains        resd 3
_@@rle_point    resd 1
_@@III          resd 1
_@@JJJ          resd 1
_@@linbits      resd 1
_@@vlc_table    resd 1
_@@coarse_end   resd 1

_@rle_point     resd 1
_@@rle_ptr      resd 1
_@@rle_val      resd 1
_@@rle_val_x_40h resd 1
_@@max_bands    resb 4
_@@max_blocks   resd 1
_@@max_pos      resd 1
_@@sfb_array    resb 40
_@@is_tab       resd 1
_@@n_long_sfb   resd 1
_@@n_short_sfb  resd 1
_@@n_sfb        resd 1
_@@tmp          resb 2304
_@@s0           resd 1
_@@s2           resd 1
_@@s3           resd 1

_@@@tmp         resd 18 ; resb 72
_@@tmp0         resd 1
_@@tmp1         resd 1
_@@tmp2         resd 1
_@@tmp3         resd 1
_@@tmp4         resd 1
_@@tmp5         resd 1
mp3_out2_a0     resd 1
mp3_out2_a1     resd 1
mp3_out2_a2     resd 1
mp3_out2_b0     resd 1
mp3_out2_b1     resd 1
mp3_out2_b2     resd 1
                resd 1
                resd 1
_@@@JJJ         resd 1
_@@www          resd 1
_@@mdct_long_end resd 1
_@@sblimit      resd 1
_@@switch_point resd 1
mp3_huff_tmp_bits	resb 256
mp3_huff_tmp_codes	resb 512
_@@table_nb_bits	resd 1
_@@nb_codes		resd 1
_@@prefix_numbits	resd 1
_@@prefix_pattern	resd 1
_@@curr_table_size	resd 1
_@@curr_table_mask	resd 1
_@@curr_table_index	resd 1
_@@granule_addr		resd 1
; HANDLE hFile
hFile           resd 1
; HANDLE hMap
;hMap           resd 1
stream_start    resd 1
stream_pos      resd 1
bytes_left      resd 1

; 20/10/2024
; DWORD diskresult
;diskresult     resd 1
; HANDLE std_out
;std_out        resd 1
;cmdline_buf    resb 1024
cmdline_buf	resb 128
; HANDLE mp3_wav_handle
mp3_wav_handle  resd 1
; HANDLE mp3_pcm_handle
mp3_pcm_handle  resd 1
_@@max_diff     resd 1
_@@avg_diff     resd 2
pcm_filepos     resd 1
_@@mono_convert resd 1
_@@pcm_steps    resw 2
_@@worst_pcm_filepos resd 1
_@@worst_mp3_filepos resd 1
		resd 1
;alignb 4

; 10/01/2025
alignb 4096

; 09/01/2025
;sample_buffer  resb 36864
;sample_buffer	resb 8*MP3_MAX_OUTPUT_SIZE
;sample_buffer_size equ $-sample_buffer

; 10/01/2025
sample_buffer	resb 65536 ; max. 64512 bytes ; 11/01/2025

end_of_bss:

; ===========================================================================
; end