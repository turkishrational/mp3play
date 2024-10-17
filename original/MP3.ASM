;:----------------- Mp3 decoder
;------------------
;nocash mp3 asm decoder - started mid june 2024
;working 80x86 playback 21 jul 2024
;---
;based on minimp3 https://keyj.emphy.de/minimp3/ (c) 2007 Martin J. Fiedler
;which was itself based FFmpeg  (c) 2001, 2002 Fabrice Bellard
;intensity_stereo is based on lieff's decoder (minimp3 was rather bugged)
;------------------
  ;xxx eye: new glasses
  ;xxx speed: for rate_shift --> try to collapse synth_buf,synth_win to less entries (instead of skipping unused entries), maybe gives better caching?
  ;xxx speed: for synth_win, try 16bit mul ax,dx (but may need to pre-shift when VVRAC>15)
  ;xxx speed: synth_win contains DUPLICATED and NEGATED values - could that be used to avoid DUPLICATED multiplications?
  ;xxx accuracy: try to cripple 32bit constants to same precision as single-precision-float (or whatever the official decoder was using)
  ;xxx info: calc/display assumed duration based on filesize/bitrate (that is, filesize excluding ID3)
        SYNTH32         equ 1         ;XXX this is ALWAYS GOOD, more accurate, and smaller (and slightly faster because it can omit saturation to 16bit synth_buf, and also avoid the old synth_tmp buf in original minimp3)
        SINGLE_SAT      equ SYNTH32   ;XXXXXX only for SYNTH32 and large WFRAC (with final output multiply result in edx)
        COLL_MACRO      equ be_fast   ;\only good when BOTH are on
        HUFF_MACRO      equ be_fast   ;/
        WITHOUT_ZEROES  equ be_fast   ;XXX this is GOOD, v1.2
        UNROLL_DCT0     equ be_fast   ;XXX this is GOOD !!!! ("dec/jnz" instead "loop" does also help, but unrolling is yet faster)
        QUICK_SIGN      equ 1         ;XXX this is ALWAYS GOOD !!!! (always on, because it's fast AND small)
        FAST_SMALL      equ be_fast   ;XXX this is GOOD !!!!
        RUN_LENGTH      equ be_fast   ;XXX this is GOOD !!!!
        COARSE_END      equ be_fast   ;XXX is now faster (but exceeds 9.5Kbyte)
        ZERO_WINDOW     equ be_fast   ;XXX this is GOOD !!!  ;although formerly it was: not good... the dummy-zero-multiplies are slower than skipping
        LONG_WINDOW     equ be_fast   ;XXX this is GOOD !!! slightly faster, but slightly bigger when compressed
        MERGE_TABLE_4_3 equ 0;1       ;XXX bad, not faster, and less accurate
;---
;MP3_FRAME_SIZE           equ 1152   ;whatever (576*2)
;MP3_MAX_CODED_FRAME_SIZE equ 1792   ;whatever (700h) (maybe some compressed size?)
MP3_MAX_CHANNELS         equ 2
SBLIMIT                  equ 32
MP3_STEREO               equ 0  ;raw stereo left/right encoding     ;\
MP3_JSTEREO              equ 1  ;joint stereo mid/side or intensity ;
MP3_DUAL                 equ 2  ;raw two mono channels              ;
MP3_MONO                 equ 3  ;raw single mono channel            ;/
MODE_EXT_I_STEREO        equ 1  ;\for JSTEREO   ;intensity stereo (aka channel 0, with panning)
MODE_EXT_MS_STEREO       equ 2  ;/              ;mid/side stereo
CHILD_BITS               equ 9   ;9   ;7     ;XXX ;original in minimp3 was 7  ;PentiumIII: fastes is 9..10 (larger values get slower, maybe exceeding cache size)
;------------------
IF with_fast_option OR (prefer_dirty)
  ;default are V=15, W=14, better are V=18, W=11 (or yet better W=12, but that may overflow?)
  IF SYNTH32   ;large VFRAC only works with SYNH32 ...
   ;XXX for l3-si_huff.bit, sum of below should be 2 smaller, eg. 17+10, or 16+11, or 18+9) (... may also depend on SINGLE_SAT on/off)
   VFRAC_BITS_fast       equ (18-0) ;18 ;-default=15   ;<-- less than 10 makes evil background noise
   WFRAC_BITS_fast       equ (11-0) ;11 ;-default=14   ;<-- can be even smaller than 14 (even 4 isn't so bad, and even 1 does still produce recognizable audio)
  ELSE         ;small 16bit values (as used in original minimp3)
   VFRAC_BITS_fast       equ (15)   ;-default=15   ;<-- less than 10 makes evil background noise
   WFRAC_BITS_fast       equ (14)   ;-default=14   ;<-- can be even smaller than 14 (even 4 isn't so bad, and even 1 does still produce recognizable audio)
  ENDIF
  SUM_SHIFT_fast         equ (0)    ;0=default/fastest (bigger may avoid sum/add overflows)
  OUT_SHIFT_fast         equ (WFRAC_BITS_fast + VFRAC_BITS_fast - SUM_SHIFT_fast - 15)
ENDIF
IF with_fast_option OR (prefer_dirty EQ 0)
  VFRAC_BITS_slow        equ (22)   ;22 is good for l3-compl.bit (bigger overflows in l3-si_huff.bit)
  WFRAC_BITS_slow        equ (30)   ;30 is max (accurate is 16 or more)
  SUM_SHIFT_slow         equ (32)   ;32=default/fastest (less requires SLOW shifting, and the smaller multipliers like WFRAC_BITS=16 don't seem to speedup multiplication)
  OUT_SHIFT_slow         equ (WFRAC_BITS_slow + VFRAC_BITS_slow - SUM_SHIFT_slow - 15)
ENDIF
IF with_fast_option
  WFRAC_BITS_default    equ 16  ;full precision (but no left-shifting yet)
ELSEIF prefer_dirty
  VFRAC_BITS_default    equ VFRAC_BITS_fast
  WFRAC_BITS_default    equ WFRAC_BITS_fast
ELSEIF prefer_dirty EQ 0
  VFRAC_BITS_default    equ VFRAC_BITS_slow
  WFRAC_BITS_default    equ 16  ;full precision (but no left-shifting yet)
ENDIF
;note: OUT_SHIFT implies the fraction for final SUM additions (so it should be bigger than 0, about 6 or so)
;      (or ideally, it would be 32, when including the LSW of multipy result in sum, eg. on ARM with SMLAL opcode)
;------------------
MP3_MAX_OUTPUT_SIZE equ 2*2*18*32*2   ;=1200h = 4608 decimal = 2 channels, 2 granules, 18*32, 2 byte(16bit)
;for actual size, see [mp3_samples_output_size]
;------------------
;:----------------- Mp3 data (uninit)
;------------------
.data?
align data_align
;------------------
@@granule struc
  $mp3gr_part2_3_length          dd ?           ;int
  $mp3gr_part2_3_start           dd ?           ;int
  $mp3gr_part2_3_end             dd ?           ;int
  $mp3gr_big_values              dd ?           ;int
  $mp3gr_global_gain             dd ?           ;int
  $mp3gr_scalefac_compress       dd ?           ;int
  $mp3gr_preflag                 dd ?           ;int
  $mp3gr_short_start             dd ?           ;int
  $mp3gr_long_end                dd ?           ;int
  $mp3gr_count1table_select      dd ?           ;int
  $mp3gr_scfsi                   dd ?           ;uint8_t  ;<-- located in hdr
  $mp3gr_block_type              dd ?           ;uint8_t
  $mp3gr_switch_point            dd ?           ;uint8_t
  $mp3gr_scalefac_scale          dd ?           ;uint8_t
  $mp3gr_table_select            dd 3 dup (?)   ;int[3]
  $mp3gr_subblock_gain           dd 3 dup (?)   ;int[3]
  $mp3gr_region_size             dd 3 dup (?)   ;int[3]
  IF WITHOUT_ZEROES
   $mp3gr_num_nonzero_hybrids      dd ?
   $mp3gr_num_nonzero_hybrids_div9 dd ?
  ENDIF
  align data_align
  $mp3gr_scale_factors           db 40 dup (?)  ;uint8_t[40]
  align data_align
  $mp3gr_sb_hybrid               dd SBLIMIT*18 dup (?)  ;int32_t[SBLIMIT * 18]   ;aka 576 = 32*18
  align data_align
  $mp3gr_entrysiz                equ $
ends
;------------------
mp3_context_start:
 align data_align
 main_data_pool_size equ 1000h          ;\this should be about 4..16 Kbyte
 main_data_pool_start:                  ; (bigger hurts caching)
  db main_data_pool_size dup (?)  ;CTX  ; (smaller requires more wrapping)
 main_data_pool_end:                    ;/(and too small could crash)
 main_data_pool_wr_ptr     dd ?         ;-
 mp3_src_data_location     dd ?  ;<-- possible location of Xing etc.
 mp3_src_frame_size        dd ?   ;compressed size (in bytes)
 mp3_src_frame_end         dd ?
 mp3_hdr_32bit_header      dd ?
 mp3_hdr_flag_crc          dd ?
 mp3_hdr_flag_mpeg25       dd ?
 mp3_hdr_flag_padding      dd ?
 mp3_sample_rate           dd ?
 mp3_hdr_sample_rate_index dd ?
 mp3_bit_rate              dd ?
 mp3_src_num_channels      dd ?        ;aka nb_channels, maybe "nb" is short for "number of"? (1 or 2)
 mp3_output_num_channels   dd ?
 mp3_output_sample_rate    dd ?
 mp3_bytes_per_sample      dd ?    ;1=8bit, 2=16bit
 mp3_curr_syn_index        dd ?
 mp3_curr_syn_dst          dd ?
 mp3_nb_frames             dd ?
 mp3_hdr_mode_val          dd ?    ;aka "mode"
 mp3_hdr_mode_ext          dd ?
 mp3_hdr_flag_lsf          dd ?    ;aka "lsf"
 align data_align
 mp3_synth_filter_proc     dd ?
 align data_align
 IF SYNTH32                                             ;\  ;CTX
   mp3_synth_buf    dd (MP3_MAX_CHANNELS*400h) dup (?)  ; the 400h entries contain 200h values, plus a mirror of ALL those values
 ELSE                                                   ; (for LONG_WINDOW, 220h entries would be enough, ie. 200h+20h, aka 200h plus mirror of first some values)
   mp3_synth_buf    dw (MP3_MAX_CHANNELS*400h) dup (?)  ; (BUT: the CHANNEL need to be aligned to a power of 2, so 400h entries are needed, ie. 220h+20h+alignment) (alternately, one could interleave left/right samples)
 ENDIF                                                  ;/
 mp3_synth_index  dd (MP3_MAX_CHANNELS) dup (?)        ;aka "synth_buf_offset"
 align data_align
 mp3_sb_samples   dd (MP3_MAX_CHANNELS*36*SBLIMIT) dup (?)
 mp3_mdct_buf     dd (MP3_MAX_CHANNELS*SBLIMIT*18) dup (?)  ;CTX
 IF with_free_format
   mp3_free_format_frame_size dd ?      ;CTX
 ENDIF
;;; mp3_context_end:
;------------------
align data_align
mp3_curr_vfrac_bits     dd ?                    ;-for init function
mp3_xing_id             dd ?                    ;\
mp3_xing_flags          dd ?                    ;
mp3_xing_frames         dd ?                    ; Xing/Info
mp3_xing_filesize       dd ?                    ;
mp3_xing_toc            db 100 dup (?)          ;
mp3_xing_vbr_scale      dd ?                    ;/
mp3_file_size           dd ?                    ;\
mp3_id3_size            dd ?                    ; file and ID3/TAG sizes
mp3_tag_size            dd ?                    ;/
align data_align
mp3_num_frames_decoded  dd ?    ;\for timelog/stats
mp3_total_output_size   dd ?    ;/
mp3_samples_dst         dd ?
mp3_samples_output_size dd ?
mp3_samples_dst_step    dd ?
align data_align
mp3_curr_channel        dd ?
align data_align
mp3_curr_granule        dd ?
align data_align
mp3_curr_frame          dd ?  ;XXX maybe remove that
align data_align
mp3_bitstream_start     dd ?    ;start address of bitstream (in bytes)
mp3_src_remain          dd ?  ;aka buf_size
mp3_extra_bytes         dd ?
mp3_main_data_begin     dd ?    ;offset (in bytes) from begin of bitstream - this is a "negative" offset to lookback into "unused" data from previous frame
;mp3_private_bits        dd ?
mp3_num_compress_bits   dd ?
align data_align
mp3_nb_granules         dd ?
align data_align
mp3_granules            db 2*2*$mp3gr_entrysiz dup (?)  ;[2][2]
align data_align
mp3_exponents           dw 576 dup (?)   ;<-- XXX can be smaller for RUN_LENGTH
align data_align
;------------------
 IF 01      ;faster using a static/global buffer, without dynamic alloc
   HUFF_TREE_SIZE equ 0b800h  ;3830h (CHILD_BITS=7bit) or 72B0h (CHILD_BITS=9bit) or B448h (CHILD_BITS=10bit)
   huff_tree_buf  db HUFF_TREE_SIZE dup (?)
 ENDIF
;- - -
 align data_align
 mp3_band_index_long    dw 9*32 dup (?)
 TABLE_4_3_SIZE         equ (8191+16)*4           ;hmmm, 8191 is 1FFFh, that's odd(?) ... seems to be "correct" (although actual correct would be 2000h+15, but that's same as 1FFFh+16)
 align data_align
 mp3_table_4_3_exp      db TABLE_4_3_SIZE dup (?)             ;\XXX this could be merged into 32bit (24bitVal+8bitExp)
 align data_align                                             ;
 mp3_table_4_3_value    dd TABLE_4_3_SIZE dup (?)             ;/
 align data_align
 mp3_exp_table          dd 512 dup (?)          ;unit32
 mp3_expval_table       dd 512*16 dup (?)       ;uint32
 mp3_mdct_win           dd 8*36 dup (?)
 mp3_is_table_lsf       dd 4*40h*2 dup (?)
 mp3_synth_win          dd 512*(1+LONG_WINDOW) dup (?)  ;aka mp3_window, this could be a 16bit array for WRFAC<15, but it's easier to always use 32bit here, it contains 512 values (plus another copy for LONG_WINDOW) (far faster caching, the 32bit values are later collapsed to 16bit when using low-precision)
 align data_align
 mp3_lsf_sf_expand_exploded_table db (2*512*8) dup (?)   ;[0..3]=slen[0..3], [4]=tindex2, [5]=force_preflag, [6..7]=unused/padding
 align data_align
        mp3_context_end:        ;XXX maybe better here (include zerofill for mp3_mdct_win !!??!!)
;------------------
.code
;------------------
;:----------------- Mp3 data (const)
;------------------
.data  ;or .const
;------------------
mp3_bitrate_tab:  ;word[2][16]
 dw 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0  ;-lsf=0
 dw 0, 8 , 16, 24, 32, 40, 48, 56, 64 , 80 , 96 , 112, 128, 144, 160, 0  ;-lsf=1
;------------------
mp3_freq_tab:  ;word[3]
 dw 44100, 48000, 32000
;---
mp3_lsf_sf_expand_init_table:                                           ;\
 @@def macro div2,mod1,mod2,mod3,tindex2,pre,next                       ;
  db div2,mod1,mod2,mod3,tindex2,pre  ;[0,1,2,3,4,5]                    ;
  dw next                             ;[6]                              ;
 endm                                                                   ;
 ;- - -div2,mod123,tindex2,pre,next                                     ;
 @@def 0   ,5,4,4 ,0*3*4  ,0  ,400      ;0..399    ;\                   ;
 @@def 0   ,5,4,1 ,1*3*4  ,0  ,500      ;400..499  ; normal case        ;
 @@def 0   ,3,1,1 ,2*3*4  ,1  ,512      ;500..511  ;/                   ;
 @@def 1   ,6,6,1 ,3*3*4  ,0  ,512+360  ;0..359    ;\for 2nd channel of ;
 @@def 1   ,4,4,1 ,4*3*4  ,0  ,512+488  ;360..487  ; intensity stereo   ;
 @@def 1   ,3,1,1 ,5*3*4  ,0  ,512+512  ;488..511  ;/                   ;/
;------------------
mp3_synth_win_src:      ;aka mp3_enwindow
 ;these are for entry [1..100h], and (mostly) negated copy at [1FFh..100h],
 ;with entry [0] set to zero, and entry[100h] written twice.
 ;official values seem to be 18bit (2bit plus 16bit fraction), but
 ;minimp3 uses values/4, 16bit (2bit plus 14bit fraction, WFRAC_BITS=14).
 ;- - -
 ;values are in range -75038..+5959, that is 18bit (with 16bit fraction)
 ;below stores them with delta to squeeze them into 16bit (which is smaller
 ;by itself, and does also compress better than unfilterd values)
 @@delta = 0
 @@def macro a,b,c,d,e,f,g,h
  IRP nn,a,b,c,d,e,f,g,h
   @@val = (nn/(1 shl (16-WFRAC_BITS_default)))  ;when low precision: shift-out unused bits (for better compression)
   dw -(@@val-@@delta)
   @@delta=@@val
  ENDM
 endm
 @@def     -1,    -1,    -1,    -1,    -1,    -1,    -2,    -2     ;\
 @@def     -2,    -2,    -3,    -3,    -4,    -4,    -5,    -5     ;
 @@def     -6,    -7,    -7,    -8,    -9,   -10,   -11,   -13     ;
 @@def    -14,   -16,   -17,   -19,   -21,   -24,   -26,   -29     ;
 @@def    -31,   -35,   -38,   -41,   -45,   -49,   -53,   -58     ;
 @@def    -63,   -68,   -73,   -79,   -85,   -91,   -97,  -104     ;
 @@def   -111,  -117,  -125,  -132,  -139,  -147,  -154,  -161     ;
 @@def   -169,  -176,  -183,  -190,  -196,  -202,  -208,  -213     ;/
 @@def   +218,  +222,  +225,  +227,  +228,  +228,  +227,  +224     ;\
 @@def   +221,  +215,  +208,  +200,  +189,  +177,  +163,  +146     ;
 @@def   +127,  +106,   +83,   +57,   +29,    -2,   -36,   -72     ;
 @@def   -111,  -153,  -197,  -244,  -294,  -347,  -401,  -459     ;
 @@def   -519,  -581,  -645,  -711,  -779,  -848,  -919,  -991     ;
 @@def  -1064, -1137, -1210, -1283, -1356, -1428, -1498, -1567     ;
 @@def  -1634, -1698, -1759, -1817, -1870, -1919, -1962, -2001     ;
 @@def  -2032, -2057, -2075, -2085, -2087, -2080, -2063, -2037     ;/
 @@def  +2000, +1952, +1893, +1822, +1739, +1644, +1535, +1414     ;\
 @@def  +1280, +1131,  +970,  +794,  +605,  +402,  +185,   -45     ;
 @@def   -288,  -545,  -814, -1095, -1388, -1692, -2006, -2330     ;
 @@def  -2663, -3004, -3351, -3705, -4063, -4425, -4788, -5153     ;
 @@def  -5517, -5879, -6237, -6589, -6935, -7271, -7597, -7910     ;
 @@def  -8209, -8491, -8755, -8998, -9219, -9416, -9585, -9727     ;
 @@def  -9838, -9916, -9959, -9966, -9935, -9863, -9750, -9592     ;
 @@def  -9389, -9139, -8840, -8492, -8092, -7640, -7134, -6574     ;/
 @@def  +5959, +5288, +4561, +3776, +2935, +2037, +1082,   +70     ;\
 @@def   -998, -2122, -3300, -4533, -5818, -7154, -8540, -9975     ;
 @@def -11455,-12980,-14548,-16155,-17799,-19478,-21189,-22929     ;
 @@def -24694,-26482,-28289,-30112,-31947,-33791,-35640,-37489     ;
 @@def -39336,-41176,-43006,-44821,-46617,-48390,-50137,-51853     ;
 @@def -53534,-55178,-56778,-58333,-59838,-61289,-62684,-64019     ;
 @@def -65290,-66494,-67629,-68692,-69679,-70590,-71420,-72169     ;
 @@def -72835,-73415,-73908,-74313,-74630,-74856,-74992,-75038     ;/
;------------------
align data_align
mp3_slen_table:  ;byte[16][2]
 db 0,0,  0,1,  0,2,  0,3,  3,0,  1,1,  1,2,  1,3
 db 2,1,  2,2,  2,3,  3,1,  3,2,  3,3,  4,2,  4,3
;------------------
align data_align
mp3_lsf_nsf_table:  ;byte[6][3][4]   ;total size=48h
 db  6,  5,  5, 5,     9,  9,  9, 9,     6,  9,  9, 9
 db  6,  5,  7, 3,     9,  9, 12, 6,     6,  9, 12, 6
 db 11, 10,  0, 0,    18, 18,  0, 0,    15, 18,  0, 0
 db  7,  7,  7, 0,    12, 12, 12, 0,     6, 15, 12, 0
 db  6,  6,  6, 3,    12,  9,  9, 6,     6, 12,  9, 6
 db  8,  8,  5, 0,    15, 12,  9, 0,     6, 18,  9, 0
;------------------
;below huff data contains uncompressed data value, and number of bits per
;huffcode (the actual compressed huffcodes can be automatically enumerated).
;the data values for tree 1..15 contain two 4bit nibbles.
;the data values for tree 10h..11h contain 4 flag bits.
;---
;normally, for "orderly" hufftrees, one would only need the number of bits
;(and could then automatically enumerate them by assigning increasing values
;for the uncompressed data, and allocating huffcodes, starting with codes with
;biggest or smallest numbits) (as done in .LZH files, for example).
;however, the mp3 codes are sorted "almost" like that, but there are a lot
;of mis-sorted entries. unknown how that was generated (maybe it was manually
;assigned).
;note: the actual numbits value could be seen as 0..2 bits taller (when
;counting the signbits for nonzero nibbles) (plus yet taller for codes with
;linbits), but even when taking those extra bits into account, the trees
;aren't properly sorted.
;---
.data                           ;\
huff_tree_list_data:            ;
.const                          ;
huff_tree_list_numbits:         ;/
 @@def macro d0,b0,d1,b1,d2,b2,d3,b3,d4,b4,d5,b5,d6,b6,d7,b7
  @@item macro d,b              ;\
   IFDIFI <d>,<->               ; this stores the "d" and "b" values in
    .data                       ; separate segments, for better EXE compression
     db d       ;data           ; (saves 58 bytes when compressed via kkrunchy)
    .const                      ; (otherwise one could store "db d,b" pairs)
     db b       ;numbits        ;
   ENDIF                        ;
  endm                          ;/
  @@item d0,b0
  @@item d1,b1
  @@item d2,b2
  @@item d3,b3
  @@item d4,b4
  @@item d5,b5
  @@item d6,b6
  @@item d7,b7
 endm
 ;--- huff_tree_01h:  ;size=4 (2x2) (with data nibbles 0..1)
 @@def 011h,3  ,001h,3  ,010h,2  ,000h,1  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-
 ;--- huff_tree_02h:  ;size=9 (3x3) (with data nibbles 0..2)
 @@def 022h,6  ,002h,6  ,012h,5  ,021h,5  ,020h,5  ,011h,3  ,001h,3  ,010h,3
 @@def 000h,1  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-
 ;--- huff_tree_03h:  ;size=9 (3x3) (with data nibbles 0..2)
 @@def 022h,6  ,002h,6  ,012h,5  ,021h,5  ,020h,5  ,010h,3  ,011h,2  ,001h,2
 @@def 000h,2  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-
 ;--- huff_tree_04h:  ;size=16 (4x4) (with data nibbles 0..3)
 @@def 033h,8  ,023h,8  ,032h,7  ,031h,6  ,013h,7  ,003h,7  ,030h,7  ,022h,7
 @@def 012h,6  ,021h,6  ,002h,6  ,020h,6  ,011h,3  ,001h,3  ,010h,3  ,000h,1
 ;--- huff_tree_05h:  ;size=16 (4x4) (with data nibbles 0..3)
 @@def 033h,7  ,003h,7  ,023h,6  ,032h,6  ,030h,6  ,013h,5  ,031h,5  ,022h,5
 @@def 002h,5  ,012h,4  ,021h,4  ,020h,4  ,001h,3  ,011h,2  ,010h,3  ,000h,3
 ;--- huff_tree_06h:  ;size=36 (6x6) (with data nibbles 0..5)
 @@def 055h,10 ,045h,10 ,054h,10 ,053h,10 ,035h,9  ,044h,9  ,025h,9  ,052h,9
 @@def 015h,8  ,051h,8  ,005h,9  ,034h,9  ,050h,8  ,043h,9  ,033h,9  ,024h,8
 @@def 042h,8  ,014h,7  ,041h,7  ,040h,7  ,004h,8  ,023h,8  ,032h,8  ,003h,8
 @@def 013h,7  ,031h,7  ,030h,7  ,022h,7  ,012h,6  ,021h,5  ,002h,6  ,020h,6
 @@def 011h,4  ,001h,3  ,010h,3  ,000h,1  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-
 ;--- huff_tree_07h:  ;size=36 (6x6) (with data nibbles 0..5)
 @@def 055h,11 ,054h,11 ,045h,10 ,053h,9  ,035h,10 ,044h,10 ,025h,9  ,052h,9
 @@def 005h,9  ,015h,8  ,051h,8  ,034h,9  ,043h,9  ,050h,9  ,033h,9  ,024h,8
 @@def 042h,8  ,014h,8  ,041h,7  ,004h,8  ,040h,8  ,023h,8  ,032h,8  ,013h,8
 @@def 031h,8  ,003h,8  ,030h,8  ,022h,6  ,002h,6  ,020h,6  ,012h,4  ,021h,4
 @@def 011h,2  ,001h,3  ,010h,3  ,000h,2  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-
 ;--- huff_tree_08h:  ;size=36 (6x6) (with data nibbles 0..5)
 @@def 055h,9  ,045h,9  ,035h,8  ,053h,8  ,054h,9  ,005h,9  ,044h,8  ,025h,8
 @@def 052h,8  ,015h,8  ,051h,7  ,034h,7  ,043h,7  ,050h,8  ,004h,8  ,024h,7
 @@def 042h,7  ,033h,7  ,040h,7  ,014h,6  ,041h,6  ,023h,6  ,032h,6  ,013h,5
 @@def 031h,5  ,003h,6  ,030h,6  ,022h,5  ,002h,5  ,012h,4  ,021h,4  ,020h,4
 @@def 011h,3  ,001h,3  ,010h,3  ,000h,3  ,-   ,-  ,-   ,-  ,-   ,-  ,-   ,-
 ;--- huff_tree_09h:  ;size=64 (8x8) (with data nibbles 0..7)
 @@def 077h,11 ,067h,11 ,076h,11 ,057h,11 ,075h,11 ,066h,11 ,047h,10 ,074h,10
 @@def 056h,10 ,065h,10 ,037h,10 ,073h,10 ,046h,10 ,055h,11 ,054h,11 ,063h,10
 @@def 027h,9  ,072h,9  ,064h,10 ,007h,10 ,070h,9  ,062h,9  ,045h,10 ,035h,10
 @@def 006h,9  ,053h,10 ,044h,10 ,017h,8  ,071h,8  ,036h,9  ,026h,9  ,025h,10
 @@def 052h,10 ,015h,9  ,051h,9  ,034h,10 ,043h,10 ,016h,8  ,061h,8  ,060h,8
 @@def 005h,9  ,050h,9  ,024h,9  ,042h,9  ,033h,9  ,004h,9  ,014h,8  ,041h,8
 @@def 040h,8  ,023h,8  ,032h,8  ,003h,8  ,013h,7  ,031h,7  ,030h,7  ,022h,7
 @@def 012h,6  ,021h,6  ,002h,6  ,020h,6  ,011h,4  ,001h,3  ,010h,3  ,000h,1
 ;--- huff_tree_0Ah:  ;size=64 (8x8) (with data nibbles 0..7)
 @@def 077h,10 ,067h,10 ,076h,10 ,075h,10 ,066h,10 ,047h,10 ,074h,10 ,057h,11
 @@def 055h,11 ,056h,10 ,065h,10 ,037h,9  ,073h,9  ,046h,9  ,045h,10 ,054h,10
 @@def 035h,10 ,053h,10 ,027h,8  ,072h,8  ,064h,9  ,007h,9  ,071h,7  ,017h,8
 @@def 070h,8  ,036h,8  ,063h,8  ,060h,8  ,044h,9  ,025h,9  ,052h,9  ,005h,9
 @@def 015h,8  ,062h,7  ,026h,8  ,006h,8  ,016h,7  ,061h,7  ,051h,8  ,034h,8
 @@def 050h,8  ,043h,9  ,033h,9  ,024h,8  ,042h,8  ,014h,8  ,041h,8  ,004h,8
 @@def 040h,8  ,023h,7  ,032h,7  ,013h,6  ,031h,6  ,003h,7  ,030h,7  ,022h,6
 @@def 021h,5  ,012h,4  ,002h,5  ,020h,5  ,011h,3  ,001h,3  ,010h,3  ,000h,2
 ;--- huff_tree_0Bh:  ;size=64 (8x8) (with data nibbles 0..7)
 @@def 077h,10 ,067h,10 ,076h,9  ,057h,9  ,075h,9  ,066h,9  ,047h,9  ,074h,9
 @@def 065h,9  ,056h,8  ,037h,8  ,073h,9  ,055h,9  ,027h,8  ,072h,8  ,046h,8
 @@def 064h,8  ,017h,8  ,071h,8  ,007h,9  ,070h,9  ,036h,8  ,063h,8  ,045h,8
 @@def 054h,8  ,044h,8  ,006h,9  ,005h,9  ,026h,7  ,062h,7  ,061h,7  ,016h,8
 @@def 060h,8  ,035h,8  ,053h,8  ,025h,8  ,052h,8  ,015h,7  ,051h,7  ,034h,7
 @@def 043h,7  ,050h,8  ,004h,8  ,024h,7  ,042h,7  ,014h,7  ,033h,6  ,041h,6
 @@def 023h,6  ,032h,6  ,040h,7  ,003h,7  ,030h,6  ,013h,5  ,031h,5  ,022h,5
 @@def 012h,4  ,021h,4  ,002h,5  ,020h,5  ,000h,4  ,011h,3  ,001h,3  ,010h,3
 ;--- huff_tree_0Ch:  ;size=256 (16x16) (with data nibbles 0..F)
 @@def 0FEh,19 ,0FCh,19 ,0FDh,18 ,0EDh,17 ,0FFh,16 ,0EFh,16 ,0DFh,16 ,0EEh,16
 @@def 0CFh,16 ,0DEh,16 ,0BFh,16 ,0FBh,16 ,0CEh,16 ,0DCh,16 ,0AFh,17 ,0E9h,17
 @@def 0ECh,15 ,0DDh,15 ,0FAh,16 ,0CDh,16 ,0BEh,15 ,0EBh,15 ,09Fh,15 ,0F9h,15
 @@def 0EAh,15 ,0BDh,15 ,0DBh,15 ,08Fh,15 ,0F8h,15 ,0CCh,15 ,0AEh,16 ,09Eh,16
 @@def 08Eh,15 ,07Fh,16 ,07Eh,16 ,0F7h,14 ,0DAh,14 ,0ADh,15 ,0BCh,15 ,0CBh,15
 @@def 0F6h,15 ,06Fh,14 ,0E8h,14 ,05Fh,14 ,09Dh,14 ,0D9h,14 ,0F5h,14 ,0E7h,14
 @@def 0ACh,14 ,0BBh,14 ,04Fh,14 ,0F4h,14 ,0CAh,15 ,0E6h,15 ,0F3h,14 ,03Fh,13
 @@def 08Dh,14 ,0D8h,14 ,02Fh,13 ,0F2h,13 ,06Eh,14 ,09Ch,14 ,00Fh,13 ,0C9h,14
 @@def 05Eh,14 ,0ABh,13 ,07Dh,14 ,0D7h,14 ,04Eh,13 ,0C8h,14 ,0D6h,14 ,03Eh,13
 @@def 0B9h,13 ,09Bh,14 ,0AAh,14 ,01Fh,12 ,0F1h,12 ,0F0h,12 ,0BAh,13 ,0E5h,13
 @@def 0E4h,13 ,08Ch,13 ,06Dh,13 ,0E3h,13 ,0E2h,12 ,02Eh,13 ,00Eh,13 ,01Eh,12
 @@def 0E1h,12 ,0E0h,13 ,05Dh,13 ,0D5h,13 ,07Ch,13 ,0C7h,13 ,04Dh,13 ,08Bh,13
 @@def 0B8h,13 ,0D4h,13 ,09Ah,13 ,0A9h,13 ,06Ch,13 ,0C6h,12 ,03Dh,12 ,0D3h,13
 @@def 07Bh,13 ,02Dh,12 ,0D2h,12 ,01Dh,12 ,0B7h,12 ,05Ch,13 ,0C5h,13 ,099h,13
 @@def 07Ah,13 ,0C3h,12 ,0A7h,13 ,097h,13 ,04Bh,12 ,0D1h,11 ,00Dh,12 ,0D0h,12
 @@def 08Ah,12 ,0A8h,12 ,04Ch,12 ,0C4h,12 ,06Bh,12 ,0B6h,12 ,03Ch,11 ,02Ch,11
 @@def 0C2h,11 ,05Bh,11 ,0B5h,12 ,089h,12 ,01Ch,11 ,0C1h,11 ,098h,12 ,00Ch,12
 @@def 0C0h,11 ,0B4h,12 ,06Ah,12 ,0A6h,12 ,079h,12 ,03Bh,11 ,0B3h,11 ,088h,12
 @@def 05Ah,12 ,02Bh,11 ,0A5h,12 ,069h,12 ,0A4h,11 ,078h,12 ,087h,12 ,094h,11
 @@def 077h,12 ,076h,12 ,0B2h,10 ,01Bh,10 ,0B1h,10 ,00Bh,11 ,0B0h,11 ,096h,11
 @@def 04Ah,11 ,03Ah,11 ,0A3h,11 ,059h,11 ,095h,11 ,02Ah,10 ,0A2h,10 ,01Ah,10
 @@def 0A1h,10 ,00Ah,11 ,068h,11 ,0A0h,10 ,086h,11 ,049h,11 ,093h,10 ,039h,11
 @@def 058h,11 ,085h,11 ,067h,11 ,029h,10 ,092h,10 ,057h,11 ,075h,11 ,038h,10
 @@def 083h,10 ,066h,11 ,047h,11 ,074h,11 ,056h,11 ,065h,11 ,073h,11 ,019h,9
 @@def 091h,9  ,009h,10 ,090h,10 ,048h,10 ,084h,10 ,072h,10 ,046h,11 ,064h,11
 @@def 028h,9  ,082h,9  ,018h,9  ,037h,10 ,027h,10 ,017h,9  ,071h,9  ,055h,10
 @@def 007h,10 ,070h,10 ,036h,10 ,063h,10 ,045h,10 ,054h,10 ,026h,10 ,062h,10
 @@def 035h,10 ,081h,8  ,008h,9  ,080h,9  ,016h,9  ,061h,9  ,006h,9  ,060h,9
 @@def 053h,10 ,044h,10 ,025h,9  ,052h,9  ,005h,9  ,015h,8  ,051h,8  ,034h,9
 @@def 043h,9  ,050h,9  ,024h,9  ,042h,9  ,033h,9  ,014h,8  ,041h,7  ,004h,8
 @@def 040h,8  ,023h,8  ,032h,8  ,013h,7  ,031h,7  ,003h,7  ,030h,7  ,022h,7
 @@def 012h,6  ,021h,6  ,002h,6  ,020h,6  ,011h,4  ,001h,4  ,010h,3  ,000h,1
 ;--- huff_tree_0Dh:  ;size=256 (16x16) (with data nibbles 0..F)
 @@def 0FFh,13 ,0EFh,13 ,0FEh,13 ,0DFh,13 ,0EEh,12 ,0FDh,13 ,0CFh,13 ,0FCh,13
 @@def 0DEh,13 ,0EDh,13 ,0BFh,13 ,0FBh,12 ,0CEh,13 ,0ECh,13 ,0DDh,12 ,0AFh,12
 @@def 0FAh,12 ,0BEh,12 ,0EBh,12 ,0CDh,12 ,0DCh,12 ,09Fh,12 ,0F9h,12 ,0EAh,12
 @@def 0BDh,12 ,0DBh,12 ,08Fh,12 ,0F8h,12 ,0CCh,12 ,09Eh,12 ,0E9h,12 ,07Fh,12
 @@def 0F7h,12 ,0ADh,12 ,0DAh,12 ,0BCh,12 ,06Fh,12 ,0AEh,13 ,00Fh,13 ,0CBh,11
 @@def 0F6h,11 ,08Eh,12 ,0E8h,12 ,05Fh,12 ,09Dh,12 ,0F5h,11 ,07Eh,11 ,0E7h,11
 @@def 0ACh,11 ,0CAh,11 ,0BBh,11 ,0D9h,12 ,08Dh,12 ,04Fh,11 ,0F4h,11 ,03Fh,11
 @@def 0F3h,11 ,0D8h,11 ,0E6h,11 ,02Fh,11 ,0F2h,11 ,06Eh,12 ,0F0h,12 ,01Fh,11
 @@def 0F1h,11 ,09Ch,11 ,0C9h,11 ,05Eh,11 ,0ABh,11 ,0BAh,11 ,0E5h,11 ,07Dh,11
 @@def 0D7h,11 ,04Eh,11 ,0E4h,11 ,08Ch,11 ,0C8h,11 ,03Eh,11 ,06Dh,11 ,0D6h,11
 @@def 0E3h,11 ,09Bh,11 ,0B9h,11 ,02Eh,11 ,0AAh,11 ,0E2h,11 ,01Eh,11 ,0E1h,11
 @@def 00Eh,12 ,0E0h,12 ,05Dh,11 ,0D5h,11 ,07Ch,11 ,0C7h,11 ,04Dh,11 ,08Bh,11
 @@def 0D4h,10 ,0B8h,11 ,09Ah,11 ,0A9h,11 ,06Ch,11 ,0C6h,11 ,03Dh,11 ,0D3h,10
 @@def 0D2h,10 ,02Dh,11 ,00Dh,11 ,01Dh,10 ,07Bh,10 ,0B7h,10 ,0D1h,10 ,05Ch,11
 @@def 0D0h,11 ,0C5h,10 ,08Ah,10 ,0A8h,10 ,04Ch,10 ,0C4h,10 ,06Bh,10 ,0B6h,10
 @@def 099h,11 ,00Ch,11 ,03Ch,10 ,0C3h,10 ,07Ah,10 ,0A7h,10 ,0A6h,10 ,0C0h,11
 @@def 00Bh,11 ,0C2h,9  ,02Ch,10 ,05Bh,10 ,0B5h,10 ,01Ch,10 ,089h,10 ,098h,10
 @@def 0C1h,10 ,04Bh,10 ,0B4h,10 ,06Ah,10 ,03Bh,10 ,079h,10 ,0B3h,9  ,097h,10
 @@def 088h,10 ,02Bh,10 ,05Ah,10 ,0B2h,9  ,0A5h,10 ,01Bh,10 ,0B1h,9  ,0B0h,10
 @@def 069h,10 ,096h,10 ,04Ah,10 ,0A4h,10 ,078h,10 ,087h,10 ,03Ah,10 ,0A3h,9
 @@def 059h,9  ,095h,9  ,02Ah,9  ,0A2h,9  ,01Ah,9  ,0A1h,9  ,00Ah,10 ,0A0h,10
 @@def 068h,9  ,086h,9  ,049h,9  ,094h,9  ,039h,9  ,093h,9  ,077h,10 ,009h,10
 @@def 058h,9  ,085h,9  ,029h,9  ,067h,9  ,076h,9  ,092h,9  ,091h,8  ,019h,9
 @@def 090h,9  ,048h,9  ,084h,9  ,057h,9  ,075h,9  ,038h,9  ,083h,9  ,066h,9
 @@def 047h,9  ,028h,8  ,082h,8  ,018h,8  ,081h,8  ,074h,9  ,008h,9  ,080h,9
 @@def 056h,9  ,065h,9  ,037h,9  ,073h,9  ,046h,9  ,027h,8  ,072h,8  ,064h,8
 @@def 017h,8  ,055h,8  ,071h,8  ,007h,9  ,070h,9  ,036h,8  ,063h,8  ,045h,8
 @@def 054h,8  ,026h,8  ,062h,8  ,016h,8  ,006h,9  ,060h,9  ,035h,8  ,061h,7
 @@def 053h,8  ,044h,8  ,025h,7  ,052h,7  ,015h,7  ,051h,7  ,005h,8  ,050h,8
 @@def 034h,7  ,043h,7  ,024h,7  ,042h,7  ,033h,7  ,041h,6  ,014h,7  ,004h,7
 @@def 023h,6  ,032h,6  ,040h,7  ,003h,7  ,013h,6  ,031h,6  ,030h,6  ,022h,5
 @@def 012h,5  ,021h,5  ,002h,5  ,020h,5  ,011h,3  ,001h,4  ,010h,4  ,000h,3
 ;--- huff_tree_0Eh:  ;size=256 (16x16) (with data nibbles 0..F) (has extra linbits)
 @@def 0EFh,11 ,0FEh,11 ,0DFh,11 ,0FDh,11 ,0CFh,11 ,0FCh,11 ,0BFh,11 ,0FBh,11
 @@def 0AFh,10 ,0FAh,11 ,09Fh,11 ,0F9h,11 ,0F8h,11 ,08Fh,10 ,07Fh,10 ,0F7h,10
 @@def 06Fh,10 ,0F6h,10 ,0FFh,8  ,05Fh,10 ,0F5h,10 ,04Fh,9  ,0F4h,9  ,0F3h,9
 @@def 0F0h,9  ,03Fh,10 ,0CEh,16 ,0ECh,17 ,0DDh,17 ,0DEh,15 ,0E9h,15 ,0EAh,16
 @@def 0D9h,16 ,0EEh,14 ,0EDh,15 ,0EBh,15 ,0BEh,14 ,0CDh,14 ,0DCh,15 ,0DBh,15
 @@def 0AEh,14 ,0CCh,14 ,0ADh,15 ,0DAh,15 ,07Eh,15 ,0ACh,15 ,0CAh,14 ,0C9h,15
 @@def 07Dh,15 ,05Eh,14 ,0BDh,13 ,0F2h,8  ,02Fh,9  ,00Fh,9  ,01Fh,8  ,0F1h,8
 @@def 09Eh,13 ,0BCh,14 ,0CBh,14 ,08Eh,14 ,0E8h,14 ,09Dh,14 ,0E7h,14 ,0BBh,14
 @@def 08Dh,14 ,0D8h,14 ,06Eh,14 ,0E6h,13 ,09Ch,13 ,0ABh,14 ,0BAh,14 ,0E5h,14
 @@def 0D7h,14 ,04Eh,13 ,0E4h,14 ,08Ch,14 ,0C8h,13 ,03Eh,13 ,06Dh,13 ,0D6h,14
 @@def 09Bh,14 ,0B9h,14 ,0AAh,14 ,0E1h,13 ,0D4h,13 ,0B8h,14 ,0A9h,14 ,07Bh,13
 @@def 0B7h,14 ,0D0h,14 ,0E3h,12 ,00Eh,13 ,0E0h,13 ,05Dh,13 ,0D5h,13 ,07Ch,13
 @@def 0C7h,13 ,04Dh,13 ,08Bh,13 ,09Ah,13 ,06Ch,13 ,0C6h,13 ,03Dh,13 ,05Ch,13
 @@def 0C5h,13 ,00Dh,12 ,08Ah,13 ,0A8h,13 ,099h,13 ,04Ch,13 ,0B6h,13 ,07Ah,13
 @@def 03Ch,12 ,05Bh,13 ,089h,13 ,01Ch,12 ,0C0h,12 ,098h,13 ,079h,13 ,0E2h,11
 @@def 02Eh,12 ,01Eh,12 ,0D3h,12 ,02Dh,12 ,0D2h,12 ,0D1h,12 ,03Bh,12 ,097h,13
 @@def 088h,13 ,01Dh,11 ,0C4h,12 ,06Bh,12 ,0C3h,12 ,0A7h,12 ,02Ch,11 ,0C2h,12
 @@def 0B5h,12 ,0C1h,12 ,00Ch,12 ,04Bh,12 ,0B4h,12 ,06Ah,12 ,0A6h,12 ,0B3h,11
 @@def 05Ah,12 ,0A5h,12 ,02Bh,11 ,0B2h,11 ,01Bh,11 ,0B1h,11 ,00Bh,12 ,0B0h,12
 @@def 069h,12 ,096h,12 ,04Ah,12 ,0A4h,12 ,078h,12 ,087h,12 ,0A3h,11 ,03Ah,12
 @@def 059h,12 ,02Ah,11 ,095h,12 ,068h,12 ,0A1h,11 ,086h,12 ,077h,12 ,094h,11
 @@def 049h,12 ,057h,12 ,067h,11 ,0A2h,10 ,01Ah,10 ,00Ah,11 ,0A0h,11 ,039h,11
 @@def 093h,11 ,058h,11 ,085h,11 ,029h,10 ,092h,10 ,076h,11 ,009h,11 ,019h,10
 @@def 091h,10 ,090h,11 ,048h,11 ,084h,11 ,075h,11 ,038h,11 ,083h,11 ,066h,11
 @@def 028h,11 ,082h,10 ,047h,11 ,074h,11 ,018h,10 ,081h,10 ,080h,10 ,008h,11
 @@def 056h,11 ,037h,10 ,073h,10 ,065h,11 ,046h,11 ,027h,10 ,072h,10 ,064h,11
 @@def 055h,11 ,007h,10 ,017h,9  ,071h,9  ,070h,10 ,036h,10 ,063h,10 ,045h,10
 @@def 054h,10 ,026h,10 ,062h,9  ,016h,9  ,061h,9  ,006h,10 ,060h,10 ,053h,9
 @@def 035h,10 ,044h,10 ,025h,9  ,052h,9  ,051h,8  ,015h,9  ,005h,9  ,034h,9
 @@def 043h,9  ,050h,9  ,024h,9  ,042h,9  ,033h,9  ,014h,8  ,041h,8  ,004h,9
 @@def 040h,9  ,023h,8  ,032h,8  ,013h,7  ,031h,7  ,003h,8  ,030h,8  ,022h,7
 @@def 012h,6  ,021h,6  ,002h,6  ,020h,6  ,011h,4  ,001h,4  ,010h,3  ,000h,1
 ;--- huff_tree_0Fh:  ;size=256 (16x16) (with data nibbles 0..F) (has extra linbits)
 @@def 0EFh,8  ,0FEh,8  ,0DFh,8  ,0FDh,8  ,0CFh,8  ,0FCh,8  ,0BFh,8  ,0FBh,8
 @@def 0FAh,7  ,0AFh,8  ,09Fh,8  ,0F9h,7  ,0F8h,7  ,08Fh,8  ,07Fh,8  ,0F7h,7
 @@def 06Fh,7  ,0F6h,7  ,05Fh,7  ,0F5h,7  ,04Fh,7  ,0F4h,7  ,03Fh,7  ,0F3h,7
 @@def 02Fh,7  ,0F2h,7  ,0F1h,7  ,01Fh,8  ,0F0h,8  ,00Fh,9  ,0EEh,11 ,0DEh,11
 @@def 0EDh,11 ,0CEh,11 ,0ECh,11 ,0DDh,11 ,0BEh,11 ,0EBh,11 ,0CDh,11 ,0DCh,11
 @@def 0AEh,11 ,0EAh,11 ,0BDh,11 ,0DBh,11 ,0CCh,11 ,09Eh,11 ,0E9h,11 ,0ADh,11
 @@def 0DAh,11 ,0BCh,11 ,0CBh,11 ,08Eh,11 ,0E8h,11 ,09Dh,11 ,0D9h,11 ,07Eh,11
 @@def 0E7h,11 ,0ACh,11 ,0FFh,4  ,0CAh,11 ,0BBh,11 ,08Dh,11 ,0D8h,11 ,00Eh,12
 @@def 0E0h,12 ,00Dh,11 ,0E6h,10 ,06Eh,11 ,09Ch,11 ,0C9h,10 ,05Eh,10 ,0BAh,10
 @@def 0E5h,10 ,0ABh,11 ,07Dh,11 ,0D7h,10 ,0E4h,10 ,08Ch,10 ,0C8h,10 ,04Eh,11
 @@def 02Eh,11 ,03Eh,10 ,06Dh,10 ,0D6h,10 ,0E3h,10 ,09Bh,10 ,0B9h,10 ,0AAh,10
 @@def 0E2h,10 ,01Eh,10 ,0E1h,10 ,05Dh,10 ,0D5h,10 ,07Ch,10 ,0C7h,10 ,04Dh,10
 @@def 08Bh,10 ,0B8h,10 ,0D4h,10 ,09Ah,10 ,0A9h,10 ,06Ch,10 ,0C6h,10 ,03Dh,10
 @@def 0D3h,10 ,02Dh,10 ,0D2h,10 ,01Dh,10 ,07Bh,10 ,0B7h,10 ,0D1h,10 ,05Ch,10
 @@def 0C5h,10 ,08Ah,10 ,0A8h,10 ,099h,10 ,04Ch,10 ,0C4h,10 ,06Bh,10 ,0B6h,10
 @@def 0D0h,11 ,00Ch,11 ,03Ch,10 ,0C3h,10 ,07Ah,10 ,0A7h,10 ,02Ch,10 ,0C2h,10
 @@def 05Bh,10 ,0B5h,10 ,01Ch,10 ,089h,10 ,098h,10 ,0C1h,10 ,04Bh,10 ,0C0h,11
 @@def 00Bh,11 ,03Bh,10 ,0B0h,11 ,00Ah,11 ,01Ah,10 ,0B4h,9  ,06Ah,10 ,0A6h,10
 @@def 079h,10 ,097h,10 ,0A0h,11 ,009h,11 ,090h,10 ,0B3h,9  ,088h,9  ,02Bh,10
 @@def 05Ah,10 ,0B2h,9  ,0A5h,10 ,01Bh,10 ,0B1h,10 ,069h,10 ,096h,9  ,0A4h,9
 @@def 04Ah,10 ,078h,10 ,087h,9  ,03Ah,9  ,0A3h,9  ,059h,9  ,095h,9  ,02Ah,9
 @@def 0A2h,9  ,0A1h,9  ,068h,9  ,086h,9  ,077h,9  ,049h,9  ,094h,9  ,039h,9
 @@def 093h,9  ,058h,9  ,085h,9  ,029h,9  ,067h,9  ,076h,9  ,092h,9  ,019h,9
 @@def 091h,9  ,048h,9  ,084h,9  ,057h,9  ,075h,9  ,038h,9  ,083h,9  ,066h,9
 @@def 028h,9  ,082h,9  ,018h,9  ,047h,9  ,074h,9  ,081h,9  ,008h,10 ,080h,10
 @@def 056h,9  ,065h,9  ,017h,9  ,007h,10 ,070h,10 ,073h,8  ,037h,9  ,027h,9
 @@def 072h,8  ,046h,8  ,064h,8  ,055h,8  ,071h,8  ,036h,8  ,063h,8  ,045h,8
 @@def 054h,8  ,026h,8  ,062h,8  ,016h,8  ,061h,8  ,006h,9  ,060h,9  ,035h,8
 @@def 053h,8  ,044h,8  ,025h,8  ,052h,8  ,015h,8  ,005h,9  ,050h,9  ,051h,7
 @@def 034h,8  ,043h,8  ,024h,7  ,042h,7  ,033h,7  ,014h,7  ,041h,7  ,004h,8
 @@def 040h,8  ,023h,7  ,032h,7  ,013h,6  ,031h,6  ,003h,7  ,030h,7  ,022h,6
 @@def 012h,5  ,021h,5  ,002h,6  ,020h,6  ,011h,4  ,001h,4  ,010h,4  ,000h,4
 ;--- huff_tree_10h:  ;size=16 ("quad" code, with 4 flagbits)
 @@def 00Bh,6  ,00Fh,6  ,00Dh,6  ,00Eh,6  ,007h,6  ,005h,6  ,009h,5  ,006h,5
 @@def 003h,5  ,00Ah,5  ,00Ch,5  ,002h,4  ,001h,4  ,004h,4  ,008h,4  ,000h,1
 ;--- huff_tree_11h:  ;size=16 ("quad" code, with 4 flagbits)
 @@def 00Fh,4  ,00Eh,4  ,00Dh,4  ,00Ch,4  ,00Bh,4  ,00Ah,4  ,009h,4  ,008h,4
 @@def 007h,4  ,006h,4  ,005h,4  ,004h,4  ,003h,4  ,002h,4  ,001h,4  ,000h,4
;------------------
.data   ;or .const
align data_align
mp3_huff_data:  ;byte[32][2]    ;table,linbits
 db 0,  0  ;<-- zero
 db 1,  0
 db 2,  0
 db 3,  0
 db 0,  0  ;<-- zero, not used
 db 4,  0
 db 5,  0
 db 6,  0
 db 7,  0
 db 8,  0
 db 9,  0
 db 10, 0
 db 11, 0
 db 12, 0
 db 0,  0  ;<-- zero, not used
 db 13, 0
 db 14, 1       ;\
 db 14, 2       ;
 db 14, 3       ; tree 14, with 1..13 linbits
 db 14, 4       ;
 db 14, 6       ;
 db 14, 8       ;
 db 14, 10      ;
 db 14, 13      ;/
 db 15, 4       ;\
 db 15, 5       ;
 db 15, 6       ; tree 15, with 4..13 linbits
 db 15, 7       ;
 db 15, 8       ;
 db 15, 9       ;
 db 15, 11      ;
 db 15, 13      ;/
;------------------
align data_align
mp3_band_size_long:  ;byte[9][22]
 db 4 ,4 ,4 ,4 ,4 ,4 ,6 ,6 ,8 ,8 ,10,12,16,20,24,28,34,42,50,54,76 ,158  ;44100
 db 4 ,4 ,4 ,4 ,4 ,4 ,6 ,6 ,6 ,8 ,10,12,16,18,22,28,34,40,46,54,54 ,192  ;48000
 db 4 ,4 ,4 ,4 ,4 ,4 ,6 ,6 ,8 ,10,12,16,20,24,30,38,46,56,68,84,102,26   ;32000
 db 6 ,6 ,6 ,6 ,6 ,6 ,8 ,10,12,14,16,20,24,28,32,38,46,52,60,68,58 ,54   ;22050
 db 6 ,6 ,6 ,6 ,6 ,6 ,8 ,10,12,14,16,18,22,26,32,38,46,52,64,70,76 ,36   ;24000
 db 6 ,6 ,6 ,6 ,6 ,6 ,8 ,10,12,14,16,20,24,28,32,38,46,52,60,68,58 ,54   ;16000
 db 6 ,6 ,6 ,6 ,6 ,6 ,8 ,10,12,14,16,20,24,28,32,38,46,52,60,68,58 ,54   ;11025
 db 6 ,6 ,6 ,6 ,6 ,6 ,8 ,10,12,14,16,20,24,28,32,38,46,52,60,68,58 ,54   ;12000
 db 12,12,12,12,12,12,16,20,24,28,32,40,48,56,64,76,90,2 ,2 ,2 ,2  ,2    ;8000
;---
align data_align
mp3_band_size_short:  ;byte[9][16]
 db 4 ,4 ,4 ,4 ,6 ,8 ,10,12,14,18,22,30,56   ;44100
 db 4 ,4 ,4 ,4 ,6 ,6 ,10,12,14,16,20,26,66   ;48000
 db 4 ,4 ,4 ,4 ,6 ,8 ,12,16,20,26,34,42,12   ;32000
 db 4 ,4 ,4 ,6 ,6 ,8 ,10,14,18,26,32,42,18   ;22050
 db 4 ,4 ,4 ,6 ,8 ,10,12,14,18,24,32,44,12   ;24000
 db 4 ,4 ,4 ,6 ,8 ,10,12,14,18,24,30,40,18   ;16000
 db 4 ,4 ,4 ,6 ,8 ,10,12,14,18,24,30,40,18   ;11025
 db 4 ,4 ,4 ,6 ,8 ,10,12,14,18,24,30,40,18   ;12000
 db 8 ,8 ,8 ,12,16,20,24,28,36,2 ,2 ,2 ,26   ;8000
;------------------
align data_align
mp3_pretab:  ;byte[2][22]
 db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ;-preflag=0
 db 0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,2,2,3,3,3,2,0  ;-preflag=1
align data_align
;------------------
.code
;------------------
;:----------------- Mp3 data (integer)
;------------------
.data   ;or .const
;------------------
 @@def_csa macro nn,cs,ca                       ;\
  mp3_csa_&nn&_cs equ cs                        ;
  mp3_csa_&nn&_ca equ ca                        ; constants for
 endm                                           ; mp3_csa_table
 @@def_csa 0,36E12A03h,-20ED7F9Ah  ;-0.6     ;\ ;
 @@def_csa 1,386E75FDh,-1E30DB48h  ;-0.535   ;  ;
 @@def_csa 2,3CC6B73Eh,-140E604Fh  ;-0.33    ;  ;
 @@def_csa 3,3EEEA055h,-0BA47742h  ;-0.185   ;  ;
 @@def_csa 4,3FB6905Ch,-060D80E9h  ;-0.095   ;  ;
 @@def_csa 5,3FF23F21h,-029F2E1Bh  ;-0.041   ;  ;
 @@def_csa 6,3FFE5932h,-00E8A11Ch  ;-0.0142  ;  ;
 @@def_csa 7,3FFFE34Bh,-003C9ED1h  ;-0.0037  ;/ ;/
;---
mp3_mdct_win_src:    ;these are sine values divided by cosine values...
 dd 000421D4Bh,000DB8F02h,0019C7F16h,0029ADCC0h,004000001h,006246711h ;\
 dd 009EE0645h,012A7D60Ch,03DF40538h,0BC63D32Fh,0E7B0025Bh,0F069D222h ;
 dd 0F4337156h,0F657D867h,0F7BCFBA8h,0F8BB5952h,0F97C4965h,0FA15BB1Ch ; normal case
 dd 0FA946D93h,0FB00518Eh,0FB5EA270h,0FBB2FDEAh,0FC000000h,0FC479F38h ; (no blocksplit)
 dd 0FC8B6609h,0FCCC9898h,0FD0C4F0Bh,0FD4B895Ch,0FD8B3FCFh,0FDCC725Eh ;
 dd 0FE10392Fh,0FE57D867h,0FEA4DA7Dh,0FEF935F7h,0FF5786D9h,0FFC36AD5h ;/
 dd 000421D4Bh,000DB8F02h,0019C7F16h,0029ADCC0h,004000001h,006246711h ;\
 dd 009EE0645h,012A7D60Ch,03DF40538h,0BC63D32Fh,0E7B0025Bh,0F069D222h ;
 dd 0F4337156h,0F657D867h,0F7BCFBA8h,0F8BB5952h,0F97C4965h,0FA15BB1Ch ; blocksplit with
 dd 0FA931B29h,0FAF546B9h,0FB41DABBh,0FB7D8F97h,0FBABA162h,0FBCE4E62h ; block_type=1
 dd 0FBF01C67h,0FC45C8AFh,0FCD2D50Dh,0FD9008D0h,0FE74C032h,0FF771894h ;
 dd 000000000h,000000000h,000000000h,000000000h,000000000h,000000000h ;/
 dd 000DB8F02h,004000001h,012A7D60Ch,0E7B0025Bh,0F657D867h,0F97C4965h ;\
 dd 0FB00518Eh,0FC000000h,0FCCC9898h,0FD8B3FCFh,0FE57D867h,0FF5786D9h ;
 dd 000000000h,000000000h,000000000h,000000000h,000000000h,000000000h ; blocksplit with
 dd 000000000h,000000000h,000000000h,000000000h,000000000h,000000000h ; block_type=2
 dd 000000000h,000000000h,000000000h,000000000h,000000000h,000000000h ;
 dd 000000000h,000000000h,000000000h,000000000h,000000000h,000000000h ;/
 dd 000000000h,000000000h,000000000h,000000000h,000000000h,000000000h ;\
 dd 0026988B5h,00BBA3752h,037D3294Fh,0B73F655Bh,0E3B0025Bh,0EDAD5D13h ;
 dd 0F2B2ADA2h,0F58C28B8h,0F75657D6h,0F88E2C57h,0F96DE565h,0FA1449CDh ; blocksplit with
 dd 0FA946D93h,0FB00518Eh,0FB5EA270h,0FBB2FDEAh,0FC000000h,0FC479F38h ; block_type=3
 dd 0FC8B6609h,0FCCC9898h,0FD0C4F0Bh,0FD4B895Ch,0FD8B3FCFh,0FDCC725Eh ;
 dd 0FE10392Fh,0FE57D867h,0FEA4DA7Dh,0FEF935F7h,0FF5786D9h,0FFC36AD5h ;/
;---
;below are intensity stereo (is) tables in 32bit precision
;(for whatever reason, original minimp3 did only use 16bit precision)
;---
align data_align
mp3_is_table_normal:
 dd 00000000h,40000000h ;\
 dd 0D8658BBh,3279A746h ;
 dd 176CF5D1h,28930A30h ;
 dd 20000000h,20000000h ;
 dd 28930A30h,176CF5D1h ;
 dd 3279A746h,0D8658BBh ;
 dd 40000000h,00000000h ;/
;---
mp3_is_table_lsf_src:   ;sqrt based constants...   ;XXX somewhat same as "mp3_pow2_quarters"
 dd 40000000h*2    ;2.0     (2^1.00) aka 2
 dd 35D13F33h*2    ;1.681   (2^0.75)
 dd 2D413CCDh*2    ;1.414   (2^0.50) aka sqrt(2)
 dd 260DFC15h*2    ;1.189   (2^0.25) aka sqrt(sqrt(2))
;---
mp3_pow2_quarters:
 dd 40000000h*2  ;2^(0/4)
 dd 4C1BF829h*2  ;2^(1/4)
 dd 5A82799Ah*2  ;2^(2/4)
 dd 6BA27E66h*2  ;2^(3/4)
;------------------
.code
;------------------
;:----------------- Mp3 data (immediates)
;------------------
.data
;------------------
begin_FIXHR_list:
 FIXHR macro name,hex,val,shift
   name equ hex    ;assign as immediate (but, for whatever reason, that is slightly slower than memory operands)
 endm
 ;---
 FIXHR ISQRT2   , 5A82799Ah, 0.70710678118654752440, 1  ;div2   ;uh, elsewhere last 2-digit are 39 instead of 40 (whereas 40 seems to be more accurate for sqrt(2)/2?)
 ;---
 ;static const int icos36h[9]     ;same as "icos36", but div2/div4, and then shifted to "highbits" (for having 32bit fraction)
 FIXHR icos36h_0, 403E9590h, 0.50190991877167369479, 1  ;div2
 FIXHR icos36h_1, 4241F707h, 0.51763809020504152469, 1  ;div2
 FIXHR icos36h_2, 469DBE6Ch, 0.55168895948124587824, 1  ;div2
 FIXHR icos36h_3, 4E212BBEh, 0.61038729438072803416, 1  ;div2
 FIXHR icos36h_4, 5A82799Ah, 0.70710678118654752439, 1  ;div2
 FIXHR icos36h_5, 6F94A1DFh, 0.87172339781054900991, 1  ;div2
 FIXHR icos36h_6, 4BB7EC62h, 1.18310079157624925896, 2  ;div4
 FIXHR icos36h_7, 7BA3751Eh, 1.93185165257813657349, 2  ;div4
 FIXHR icos36h_8, 5BCA2A2Ch, 5.73685662283492756461, 4  ;div16
 icos36h_8minus0 equ icos36h_8
 icos36h_8minus1 equ icos36h_7
 icos36h_8minus2 equ icos36h_6
 icos36h_8minus3 equ icos36h_5
 shift_for_8minus0 equ 4
 shift_for_8minus1 equ 2
 shift_for_8minus2 equ 2
 shift_for_8minus3 equ 1
 ;---
 FIXHR C1       , 7E0E2E33h, 0.98480775301220805936, 1  ;div2
 FIXHR C2       , 7847D90Ah, 0.93969262078590838405, 1  ;div2
 FIXHR C3       , 6ED9EBA2h, 0.86602540378443864676, 1  ;div2
 FIXHR negC3    ,09126145Fh,-0.86602540378443864676, 1  ;div2   ;<-- as above, negated
 FIXHR negC4    ,09DF24175h,-0.76604444311897803520, 1  ;div2
 FIXHR negC5    ,0ADB922B8h,-0.64278760968653932632, 1  ;div2
;FIXHR C6       ,            0.50000000000000000000, 1  ;div2   ;<-- unused
 FIXHR negC7    ,0A8715E2Eh,-0.34202014332566873304, 0  ;div1   ;\note minimp3 used DIV2's, which are are kinda nonsense since the values are small anyways (and undone immediately upon using C7 and C8)
 FIXHR negC8    ,0D38BCB04h,-0.17364817766693034885, 0  ;div1   ;/
 ;---
 FIXHR COS0_0   , 4013C251h, 0.50060299823519630134, 1  ;div2
 FIXHR COS0_1   , 40B345BDh, 0.50547095989754365998, 1  ;div2
 FIXHR COS0_2   , 41FA2D6Eh, 0.51544730992262454697, 1  ;div2
 FIXHR COS0_3   , 43F93421h, 0.53104259108978417447, 1  ;div2
 FIXHR COS0_4   , 46CC1BC5h, 0.55310389603444452782, 1  ;div2
 FIXHR COS0_5   , 4A9D9CF1h, 0.58293496820613387367, 1  ;div2
 FIXHR COS0_6   , 4FAE3712h, 0.62250412303566481615, 1  ;div2
 FIXHR COS0_7   , 56601EA7h, 0.67480834145500574602, 1  ;div2
 FIXHR COS0_8   , 5F4CF6ECh, 0.74453627100229844977, 1  ;div2
 FIXHR COS0_9   , 6B6FCF27h, 0.83934964541552703873, 1  ;div2
 FIXHR COS0_10  , 7C7D1DB4h, 0.97256823786196069369, 1  ;div2
 FIXHR COS0_11  , 4AD81A98h, 1.16943993343288495515, 2  ;div4
 FIXHR COS0_12  , 5EFC8D97h, 1.48416461631416627724, 2  ;div4
 FIXHR COS0_13  , 41D95790h, 2.05778100995341155085, 3  ;div8
 FIXHR COS0_14  , 6D0B20D0h, 3.40760841846871878570, 3  ;div8
 FIXHR COS0_15  , 518522FBh,10.19000812354805681150, 5  ;div32
 ;---
 FIXHR COS1_0   , 404F4672h, 0.50241928618815570551, 1  ;div2
 FIXHR COS1_1   , 42E13C10h, 0.52249861493968888062, 1  ;div2
 FIXHR COS1_2   , 48919F45h, 0.56694403481635770368, 1  ;div2
 FIXHR COS1_3   , 52CB0E63h, 0.64682178335999012954, 1  ;div2
 FIXHR COS1_4   , 64E2402Eh, 0.78815462345125022473, 1  ;div2
 FIXHR COS1_5   , 43E224AAh, 1.06067768599034747134, 2  ;div4
 FIXHR COS1_6   , 6E3C92C2h, 1.72244709823833392782, 2  ;div4
 FIXHR COS1_7   , 519E4E04h, 5.10114861868916385802, 4  ;div16
 ;---
 FIXHR COS2_0   , 4140FB46h, 0.50979557910415916894, 1  ;div2
 FIXHR COS2_1   , 4CF8DE88h, 0.60134488693504528054, 1  ;div2
 FIXHR COS2_2   , 73326BBFh, 0.89997622313641570463, 1  ;div2
 FIXHR COS2_3   , 52036742h, 2.56291544774150617881, 3  ;div8
 ;---
 FIXHR COS3_0   , 4545E9F0h, 0.54119610014619698439, 1  ;div2
 FIXHR COS3_1   , 539EBA46h, 1.30656296487637652785, 2  ;div4
 ;---
 FIXHR COS4_0   , 5A82799Ah, 0.70710678118654752439, 1  ;div2
end_FIXHR_list:
;------------------
.code
;------------------
;:----------------- Mp3 data (log strings)
;------------------
.const
IF log_init
 log_init_list:
  ;__name_____________________src_____________len(y,x),type
  dd txt_synth_window   ,mp3_synth_win       ,8   ,40h ,32  ;always 32bit (although it may LATER get collapsed to 16bit)
  dd txt_band_indices   ,mp3_band_index_long ,9   ,22  ,16
  dd txt_lsf_sf_expand  ,mp3_lsf_sf_expand_exploded_table,1024,1,64
  dd txt_is_table_normal,mp3_is_table_normal ,7   ,2  ,32 ;is_normal (for stereo)
  dd txt_is_table_lsf   ,mp3_is_table_lsf    ,4*32,4  ,32 ;is_lsf (for stereo)
 ;dd txt_csa_table      ,mp3_csa_table       ,8   ,4  ,32 ;csa (for antialias)
  dd txt_table_4_3      ,0                   ,TABLE_4_3_SIZE/4,4,40
  dd txt_exponents      ,mp3_expval_table    ,200h,10h,32 ;exponent   ;XXX could also log dupes in smaller "mp3_exp_table"
  dd txt_mdct_windows   ,mp3_mdct_win        ,8   ,36 ,32
  dd 0   ;end of list
 ;---
  txt_huff_tree_size     db 'huff tree size ',0
 ;txt_fixhr              db '--- fixhr',0dh,0ah,0
  txt_synth_window       db '--- synth_window',0dh,0ah,0
  txt_band_indices       db '--- band_indices_sizes',0dh,0ah,0
  txt_lsf_sf_expand      db '--- lsf_sf_expand',0dh,0ah,0
  txt_table_4_3          db '--- table_4_3',0dh,0ah,0
  txt_exponents          db '--- exponents',0dh,0ah,0
  txt_is_table_normal    db '--- is_table_normal',0dh,0ah,0
  txt_is_table_lsf       db '--- is_table_lsf',0dh,0ah,0
 ;txt_csa_table          db '--- csa_table',0dh,0ah,0
  txt_mdct_windows       db '--- mdct_windows',0dh,0ah,0
  txt_huff_tree          db '--- huff tree',0dh,0ah,0
ENDIF
IF log_huffcodes
  txt_huff_underscore db ' huff_',0
  txt_huff_padding    db ' huff_padding ',0
  txt_lowfreq_region  db ' huff_lowfreq_region=',0
  txt_highfreq        db ' huff_highfreq',0dh,0ah,0
  txt_huff_stepback   db ' huff_stepback',0dh,0ah,0
ENDIF
IF log_scalefac
  txt_scalefacs   db 'scalefacs',0
  txt_spc_long    db ' long',0
  txt_spc_short   db ' short',0
ENDIF
IF log_fatal
  txt_fatal_too_many_scale_factors db 'fatal too many scale factors',0dh,0ah,0
  txt_fatal_append_main            db 'fatal append_main',0dh,0ah,0
ENDIF
IF log_frames
  txt_framelog_junk      db 'JUNK ',0
  txt_framelog_frame     db 'frame: ',0
  txt_framelog_offset    db 'offset=',0
  txt_framelog_channels  db 'ch=',0
  txt_framelog_rate      db 'rate=',0
  txt_framelog_bps       db 'bps=',0
  txt_framelog_hdr       db 'hdr=',0
  txt_missing_main_data  db 'WARNING: main data reference to missing frame',0dh,0ah,0
ENDIF
IF log_granules
  txt_granule            db 'granule',0
  txt_block_type         db ' type=',0
  txt_switch_point       db ' switch=',0
  txt_part2_3_length     db ' len=',0
  txt_big_values         db ' big=',0
  txt_global_gain        db ' gain=',0
  txt_scalefac_compress  db ' compr=',0
  txt_short_start        db ' start=',0
  txt_long_end           db ' end=',0
  txt_preflag            db ' preflg=',0
  txt_scfsi              db ' scfsi=',0
  txt_scalefac_scale     db ' scale=',0
  txt_count1table_select db ' c1sel=',0
  txt_region_sizes       db ' sizes=',0
ENDIF
.code
;------------------
;:----------------- Mp3 code bitstream get bitstream/huffman
;------------------
bswap_eax:
 xchg al,ah
 ror  eax,16
 xchg al,ah
 ret
;------------------
mp3_colNN equ ch   ;-byte ptr [mp3_numbits_collected]
mp3_colPP equ esi  ;-dword ptr [mp3_src]
mp3_col16 equ bp   ;\dword ptr [mp3_collected_data]
mp3_col32 equ ebp  ;/
;------------------
mp3mac_push_bitstream macro
 push ecx       ;\
 push ebp       ; save bitstream registers
 push esi       ;/
endm
;------------------
mp3mac_pop_bitstream macro
 pop  esi       ;\
 pop  ebp       ; restore bitstream registers
 pop  ecx       ;/
endm
;------------------
align code_align
mp3_recollect_bits:
 test esi,1             ;\when esi=odd --> align by fetching one leading extra byte (then fetch 16bit units)
 jnz  short @@odd       ;/(not really faster though)
 ;- - -
 mov  mp3_col16,word ptr [esi] ;dword ptr [mp3_collected_data]
 add  esi,2
 ror  mp3_col16,8              ;endianess
 shl  mp3_col32,16             ;dword ptr [mp3_collected_data]
 mov  mp3_colNN,0              ;byte ptr [mp3_numbits_collected]
 ret
;---
@@odd:
 moz  mp3_col32,byte ptr [esi] ;dword ptr [mp3_collected_data]  ;\
 inc  esi                                                       ; fetch 8bit
 shl  mp3_col32,16             ;dword ptr [mp3_collected_data]  ;/
 mov  mp3_col16,word ptr [esi] ;dword ptr [mp3_collected_data]  ;\
 add  esi,2                                                     ; fetch 16bit
 ror  mp3_col16,8              ;endianess                       ;
 shl  mp3_col32,16-8           ;dword ptr [mp3_collected_data]  ;/
 mov  mp3_colNN,0 +8           ;byte ptr [mp3_numbits_collected]
 ret
;------------------
mp3mac_bitstream_set_position macro
 mov  esi,dword ptr [mp3_bitstream_start]
 mov  cl,al
 shr  eax,3     ;div8
 and  cl,07h    ;remainder
 add  esi,eax
 call mp3_recollect_bits
 mp3mac_get_n_bits cl           ;skip/discard leading bits (when odd start)
endm
;------------------
mp3mac_get_n_bits macro num
 local @@cont
 IF 1   ;slightly faster
   mov  eax,mp3_col32  ;dword ptr [mp3_collected_data]
   shl  mp3_col32,num  ;dword ptr [mp3_collected_data]
   rol  eax,num
   xor  eax,mp3_col32
   sub  mp3_colNN,num  ;byte ptr [mp3_numbits_collected]
   jns  short @@cont
   IF COLL_MACRO
     mp3mac_collect_more
   ELSE
     call mp3_collect_more
   ENDIF
  @@cont:
 ELSE   ;slightly smaller... (saves ca 42 bytes when kkrunched)
   IFDIFI <num>,<cl>
     mov  cl,num
   ENDIF
   call mp3_get_bits
 ENDIF
endm
;------------------
mp3mac_get_bit_to_cy macro
local @@inrange
 dec  mp3_colNN
 IF QUICK_SIGN EQ 0
   jns  short @@inrange           ;\
   inc  mp3_colNN                 ; XXX this could be omitted
   call mp3_collect_more          ; (assuming that enough bits are collected for next huffcode or linbits)
   dec  mp3_colNN                 ;/
  @@inrange:
 ELSE
   ERRIF CHILD_BITS GT 12
 ENDIF
 shl  mp3_col32,1      ;cy=data
endm
;------------------
mp3mac_bitstream_get_position macro    ;out: eax=position, edx=destroyed
 ;this is some unfortunate/slow requirement for the huffman decoder
 ;  (might be faster when storing the bitstream position in memory?)
 ;  (or in a spare cpu register, when having more cpu registers).
 ;however, COARSE_END can avoid needing the exact get_position in most cases
 mov  eax,esi
 sub  eax,dword ptr [mp3_bitstream_start]
 movsx edx,mp3_colNN
 neg  edx
 lea  eax,[eax*8+edx-16]
endm
;------------------
align code_align
mp3_get_bits:    ;in: cl=numbits(max=16), out: eax
 mov  eax,mp3_col32  ;dword ptr [mp3_collected_data]
 shl  mp3_col32,cl   ;dword ptr [mp3_collected_data]
 rol  eax,cl
 xor  eax,mp3_col32
 sub  mp3_colNN,cl   ;byte ptr [mp3_numbits_collected]
 js   short mp3_collect_more
 ret
;---
mp3mac_collect_more macro
 ;that is <hopefully> fast, but pentiums can get confused when manipulating
 ;the SAME register with 16bit and 32bit operations (ie. col16 and col32)
 mov  cl,mp3_colNN   ;byte ptr [mp3_numbits_collected]
 add  mp3_colNN,16   ;byte ptr [mp3_numbits_collected]
 rol  mp3_col32,cl   ;dword ptr [mp3_collected_data]
 mov  mp3_col16,word ptr [esi]
 add  esi,2
 ror  mp3_col16,8    ;endianess
 ror  mp3_col32,cl   ;dword ptr [mp3_collected_data]
endm
;---
align code_align
mp3_collect_more:
 mp3mac_collect_more
 ret
;------------------
IF log_huffcodes OR (HUFF_MACRO EQ 0)
align code_align
mp3_get_huffcode:   ;in: edx=table, out: eax=data     ;aka get_vlc2
 IF log_huffcodes
   mov  dword ptr [@@table],edx         ;\
   mp3mac_bitstream_get_position        ; memorize table and begin
   mov  dword ptr [@@begin],eax         ;/
   mov  edx,offset txt_huff_underscore  ;\show huff
   call wrstr_edx                       ;/
   mov  eax,dword ptr [@@table]         ;\
   call wrhexal                         ; show table number
   call wrspc                           ;/
   mov  edx,dword ptr [@@table]         ;\get code
   call @@get_code                      ;/
   pusha
   call wrhexax                         ;\show huff.result
   call wrspc                           ;/
   mp3mac_bitstream_get_position        ;\
   sub  eax,dword ptr [@@begin]         ;
   mov  ebx,eax   ;len                  ;
   mov  eax,dword ptr [@@begin]         ; show huff.bits
   mp3mac_bitstream_set_position        ;
  @@bits_lop:                           ;
   mp3mac_get_n_bits 1                  ;
   call wrdigital                       ;
   dec  ebx                             ;
   jnz  short @@bits_lop                ;/
   call wrcrlf
   popa
   ret
  ;---
  .data?
   @@table dd ?
   @@begin dd ?
   align data_align
  .code
  ;---
  @@get_code:
 ENDIF
;- - -
@@get_child_lop:
 mov  cl,byte ptr [huff_tree_buf+edx*4+2]   ;bits (table size) (-7..-1)
 mov  dx,word ptr [huff_tree_buf+edx*4+0]   ;code (child table)
;add  cl,32             ;<-- not required (80x86 uses only 5bit anyways)
 mov  eax,mp3_col32     ;\peek bitstream
 shr  eax,cl            ;/
 add  edx,eax
 mov  cl,byte ptr [huff_tree_buf+edx*4+2]   ;bits (of entry)
 cmp  cl,0
 js   short @@got_child
;- - -
;@@got_data:
 moz  eax,word ptr [huff_tree_buf+edx*4+0]   ;data        ;-return data value
 shl  mp3_col32,cl      ;\discard cl bits
 sub  mp3_colNN,cl      ;/
 js         mp3_collect_more
 ret
;---
align code_align
@@got_child:
 shl  mp3_col32,CHILD_BITS ;\discard 7 bits (assuming that parents are always 7bit wide)
 sub  mp3_colNN,CHILD_BITS ;/
 jns  short @@get_child_lop
 IF COLL_MACRO
   mp3mac_collect_more
 ELSE
   call mp3_collect_more
 ENDIF
 jmp  short @@get_child_lop
ENDIF ;log_huffcodes OR (HUFF_MACRO EQ 0)
;------------------
mp3mac_get_huffcode macro
 local @@get_child_lop,@@got_child,@@got_done
 IF log_huffcodes OR (HUFF_MACRO EQ 0)
   call mp3_get_huffcode
 ELSE
  @@get_child_lop:
   mov  cl,byte ptr [huff_tree_buf+edx*4+2]   ;bits (table size) (-7..-1)
   mov  dx,word ptr [huff_tree_buf+edx*4+0]   ;code (child table)
  ;add  cl,32             ;<-- not required (80x86 uses only 5bit anyways)
   mov  eax,mp3_col32     ;\peek bitstream
   shr  eax,cl            ;/
   add  edx,eax
   mov  cl,byte ptr [huff_tree_buf+edx*4+2]   ;bits (of entry)
   cmp  cl,0
   js   short @@got_child
  ;- - -
  ;@@got_data:
   moz  eax,word ptr [huff_tree_buf+edx*4+0]   ;data        ;-return data value
   shl  mp3_col32,cl      ;\discard cl bits
   sub  mp3_colNN,cl      ;/
   jns  short @@got_done
   IF COLL_MACRO
     mp3mac_collect_more
   ELSE
     call mp3_collect_more
   ENDIF
   jmp  short @@got_done
  ;---
  align code_align
  @@got_child:
   shl  mp3_col32,CHILD_BITS ;\discard 7 bits (assuming that parents are always 7bit wide)
   sub  mp3_colNN,CHILD_BITS ;/
   jns  short @@get_child_lop
   IF COLL_MACRO
     mp3mac_collect_more
   ELSE
     call mp3_collect_more
   ENDIF
   jmp  short @@get_child_lop
  align code_align
  @@got_done:
 ENDIF
endm
;------------------
align code_align
mp3_uncollect_bits:
 sub  esi,2
 shr  mp3_colNN,3    ;div8     ;byte ptr [mp3_numbits_collected]
 moz  ecx,mp3_colNN
 sub  esi,ecx
 ret
;------------------
;:----------------- Mp3 code bitstream header 32bit
;------------------
align code_align
mp3_search_get_header:
 timelog_start rdtsc_read_header
 mov  dword ptr [mp3_extra_bytes],0
@@retry_header:
 cmp  dword ptr [mp3_src_remain],4      ;\
 jb         @@fail_no_header            ;/
;--- mp3_check_header...
 cmp  byte ptr [esi+0],0ffh             ;\sync mark MSBs
 jne  short @@bad_header                ;/
 mov  al,byte ptr [esi+1]               ;\
 and  al,0e0h+06h                       ; sync mark LSBs
 cmp  al,0e0h+02h                       ; and layer=1=MP3
 jne  short @@bad_header                ;/
 mov  al,byte ptr [esi+2] ;0xh,..,Fxh   ;\
 IF with_free_format                    ;
   cmp  al,0f0h  ;upper 4bit = bitrate  ;
 ELSE                                   ;
   sub  al,010h           ;Fxh,..,Exh   ;
   cmp  al,0e0h  ;upper 4bit = bitrate  ; bitrate index (1..14, 0=free, 15=bad)
 ENDIF                                  ;
 jae  short @@bad_header                ; and
 and  al,00ch    ;next 2bit = frequency ; frequency (0..2) (or 3=bad)
 cmp  al,00ch                           ;
;je   short @@bad_header                ;
 jne  short @@good_header               ;/
@@bad_header:
 inc  esi                           ;aka buf
 dec  dword ptr [mp3_src_remain]    ;aka buf_size
 inc  dword ptr [mp3_extra_bytes]
 mov  dword ptr [main_data_pool_wr_ptr],offset main_data_pool_start  ;assume a demaged frame, so FORCE back to pool start (any reference below there is treated as missing_main_data) (aka as reference to the damaged frame)
 jmp  short @@retry_header
;---
@@good_header:  ;decode_header...
 mov  eax,dword ptr [esi]                               ;\
 call bswap_eax                                         ; get header
 mov  dword ptr [mp3_hdr_32bit_header],eax              ;/
;mov  eax,dword ptr [mp3_hdr_32bit_header]              ;\
 mov  dword ptr [mp3_hdr_flag_lsf],0      ;\            ;
 mov  dword ptr [mp3_hdr_flag_mpeg25],0   ; mpeg1       ; lsf/mpeg25
 mov  dword ptr [mp3_nb_granules],2       ; 32..48khz   ;
 test eax,1 shl 19    ;1=normal, 0=lsf    ;             ; (low sample frequency)
 jnz  short @@lsf_this                    ;/            ;
 mov  dword ptr [mp3_hdr_flag_lsf],1      ;\            ;
 mov  dword ptr [mp3_nb_granules],1       ; mpeg2       ;
 test eax,1 shl 20    ;1=normal, 0=mpeg25 ; 16..24khz   ;
 jnz  short @@lsf_this                    ;/            ;
 mov  dword ptr [mp3_hdr_flag_mpeg25],1   ;\mpeg2.5     ;
@@lsf_this:                               ;/8..12khz    ;/
;mov  eax,dword ptr [mp3_hdr_32bit_header]              ;\
 shr  eax,10                                            ;
 and  eax,03h                                           ; sample_rate
 mov  ecx,dword ptr [mp3_hdr_flag_lsf]                  ;
 add  ecx,dword ptr [mp3_hdr_flag_mpeg25]               ;
 moz  edx,word ptr [mp3_freq_tab+eax*2]                 ;
 shr  edx,cl            ;sample_rate                    ;
 lea  ecx,[ecx*2+ecx]  ;N*3                             ;
 add  eax,ecx          ;index+N*3                       ;
 mov  dword ptr [mp3_hdr_sample_rate_index],eax         ;
 mov  dword ptr [mp3_sample_rate],edx                   ;
 IF with_rate_shift                                     ;
   mov  cl,byte ptr [option_rate_shift]                 ;
   shr  edx,cl                                          ;
 ENDIF                                                  ;
 mov  dword ptr [mp3_output_sample_rate],edx            ;/
 mov  eax,dword ptr [mp3_hdr_32bit_header]              ;\
 shr  eax,16                                            ; error_protection
 not  eax                                               ; (crc flag)
 and  eax,1                                             ;
 mov  dword ptr [mp3_hdr_flag_crc],eax                  ;/
 mov  eax,dword ptr [mp3_hdr_32bit_header]              ;\
 shr  eax,9                                             ; padding
 and  eax,1                                             ;
 mov  dword ptr [mp3_hdr_flag_padding],eax              ;/
 mov  eax,dword ptr [mp3_hdr_32bit_header]              ;\
 shr  eax,12                                            ;
 and  eax,0fh                                           ;
 IF with_free_format                                    ;
   jnz  short @@not_free_format                         ;
   call mp3_detect_free_format_block_size               ;
   jc         @@bad_header                              ;
   mov  eax,dword ptr [mp3_free_format_frame_size]      ;
   jmp  short @@this_frame_size_plus_padding            ;
  @@not_free_format:                                    ;
 ENDIF                                                  ;
 mov  edx,dword ptr [mp3_hdr_flag_lsf]  ;\              ;
 shl  edx,4                             ; add lsf*16    ;
 add  eax,edx                           ;/              ;
 moz  eax,word ptr [mp3_bitrate_tab+eax*2]  ;kbit/s     ;
 imul eax,1000    ;N*1000                   ;bit/s      ; compute bitrate
 mov  dword ptr [mp3_bit_rate],eax                      ; and frame_size
 imul eax,144     ;N*1000*144           ;144=90h=8*18   ;
 xor  edx,edx                                           ;
 div  dword ptr [mp3_sample_rate]                       ;
 mov  ecx,dword ptr [mp3_hdr_flag_lsf]                  ;
 shr  eax,cl                                            ;
@@this_frame_size_plus_padding:                         ;
 add  eax,dword ptr [mp3_hdr_flag_padding]              ;
 mov  dword ptr [mp3_src_frame_size],eax                ;
 add  eax,esi                                           ;
 mov  dword ptr [mp3_src_frame_end],eax                 ;/

 mov  eax,dword ptr [mp3_hdr_32bit_header]              ;\
 shr  eax,6                                             ;
 and  eax,03h                                           ; mode_val
 mov  dword ptr [mp3_hdr_mode_val],eax                  ;
 cmp  al,MP3_MONO                               ;\      ;
 mov  edx,1                                     ;       ;
 je   short @@this_channels                     ;       ;
 mov  edx,2                                     ;       ;
@@this_channels:                                ;       ;
 mov  dword ptr [mp3_src_num_channels],edx      ;       ;
 cmp  byte ptr [option_mono],0  ;\              ;       ;
 jz   short @@allow_stereo      ; force         ;       ;
 mov  edx,1                     ; mono          ;       ;
@@allow_stereo:                 ;/              ;       ;
 mov  dword ptr [mp3_output_num_channels],edx   ;       ;
 imul edx,dword ptr [mp3_bytes_per_sample]      ;       ;
 mov  dword ptr [mp3_samples_dst_step],edx      ;/      ;/
 mov  eax,dword ptr [mp3_hdr_32bit_header]              ;\
 shr  eax,4                                             ; mode_ext
 and  eax,03h                                           ;
 mov  dword ptr [mp3_hdr_mode_ext],eax                  ;/
 IF log_frames
   cmp  dword ptr [mp3_extra_bytes],0           ;\
   jz   short @@no_junk                         ;
   mov  edx,offset txt_framelog_junk    ;\      ;
   call wrstr_edx                       ;/      ;
   mov  eax,dword ptr [mp3_extra_bytes]         ;
   call wrhexeax                                ;
   call wrcrlf                                  ;
  @@no_junk:                                    ;/
  ;- - -
   mov  edx,offset txt_framelog_frame   ;\      ;
   call wrstr_edx                       ;/      ;
   mov  edx,offset txt_framelog_offset  ;\      ;\
   call wrstr_edx                       ;/      ;
   mov  eax,dword ptr [stream_pos]              ; offset
   sub  eax,dword ptr [stream_start]            ;
   add  eax,dword ptr [mp3_extra_bytes]         ;
   call wrhexeax                                ;
   call wrspc                                   ;/
   mov  edx,offset txt_framelog_hdr     ;\      ;\
   call wrstr_edx                       ;/      ;
   mov  eax,dword ptr [mp3_hdr_32bit_header]    ; hdr
   call wrhexeax                                ;
   call wrspc                                   ;/
   mov  edx,offset txt_framelog_channels;\      ;\
   call wrstr_edx                       ;/      ;
   mov  eax,dword ptr [mp3_src_num_channels]    ; channels
   call wr_decimal_eax                          ;
   call wrspc                                   ;/
   mov  edx,offset txt_framelog_rate    ;\      ;\
   call wrstr_edx                       ;/      ;
   mov  eax,dword ptr [mp3_sample_rate]         ; sample rate
   call wr_decimal_eax                          ;
   call wrspc                                   ;/
   mov  edx,offset txt_framelog_bps     ;\      ;\
   call wrstr_edx                       ;/      ;
   mov  eax,dword ptr [mp3_bit_rate]            ; bit rate (bit/s)
   call wr_decimal_eax                          ;
   call wrspc                                   ;/
     ;dword ptr [mp3_hdr_mode_val]
     ;dword ptr [mp3_hdr_mode_ext]
     ;dword ptr [mp3_src_frame_size]       ;compressed size (in bytes)
     ;dword ptr [mp3_samples_output_size]  ;decompressed size (in bytes)
   call wrcrlf
 ENDIF
 timelog_end rdtsc_read_header
 clc    ;okay
 ret
;---
@@fail_no_header:
 timelog_end rdtsc_read_header
 mov  dword ptr [mp3_src_frame_size],0
 stc    ;bad
 ret
;------------------
;:----------------- Mp3 code bitstream header extra
;------------------
align code_align
mp3_bitstream_read_header_extra:
 timelog_start rdtsc_read_header_extra
 cmp  dword ptr [mp3_hdr_flag_crc],0            ;\
 jz   short @@without_crc                       ; get/skip crc16 (if any)
 mp3mac_get_n_bits 16                           ;
;mov  word ptr [mp3_crc16],ax                   ;
@@without_crc:                                  ;/
;- - -
 cmp  dword ptr [mp3_hdr_flag_lsf],0                    ;\
 jz   short @@pre_lsf_zero                              ;
;@@pre_lsf_nonzero:                                     ; ;\
 mov  dword ptr [mp3_num_compress_bits],9 ;-            ; ;
 mp3mac_get_n_bits 8                      ;\main data   ; ; low sample rate
 mov  dword ptr [mp3_main_data_begin],eax ;/            ; ;
 mov  cl,byte ptr [mp3_src_num_channels]  ;\            ; ;
 mp3mac_get_n_bits cl                     ; private     ; ;
;mov  dword ptr [mp3_private_bits],eax    ;/            ; ;
 jmp        @@pre_lsf_done                              ; ;/
;---                                                    ;
@@pre_lsf_zero:                                         ; ;\
 mov  dword ptr [mp3_num_compress_bits],4 ;-            ; ;
 mp3mac_get_n_bits 9                      ;\main data   ; ; normal case
 mov  dword ptr [mp3_main_data_begin],eax ;/            ; ;
 mov  cl,byte ptr [mp3_src_num_channels]  ;\            ; ;
 shl  cl,1     ;1,2 --> 2,4               ;             ; ;
 xor  cl,7     ;    --> 5,3               ; private     ; ;
 mp3mac_get_n_bits cl                     ;             ; ;
;mov  dword ptr [mp3_private_bits],eax    ;/            ; ;
 mov  edx,dword ptr [mp3_src_num_channels];\            ; ;
 mov  ebx,offset mp3_granules             ; scfsi       ; ;
@@pre_channel_lop:                        ;             ; ;
 mov  dword ptr [ebx+$mp3gr_scfsi],0      ; ;\granule[ch][0]  ;<-- (all scale factors are transmitted)
 add  ebx,$mp3gr_entrysiz                 ; ;/          ; ;
 mp3mac_get_n_bits 4                      ; ;\          ; ;
 mov  dword ptr [ebx+$mp3gr_scfsi],eax    ; ; granule[ch][1]  ;<-- (flags indicating to copy scale factors from granule 0)
 add  ebx,$mp3gr_entrysiz                 ; ;/          ; ;
 dec  edx                                 ;             ; ;
 jnz  short @@pre_channel_lop             ;/            ; ;/
@@pre_lsf_done:                                         ;/
;- - -
 mov  eax,dword ptr [mp3_nb_granules]           ;\num_frames
 imul eax,18                                    ; (num granules*18)
 mov  dword ptr [mp3_nb_frames],eax             ;/
 mov  eax,dword ptr [mp3_nb_frames]             ;\
 imul eax,dword ptr [mp3_output_num_channels]   ; data output size (in bytes)
 imul eax,dword ptr [mp3_bytes_per_sample]      ;
 shl  eax,5   ;mul32                            ;
 IF with_rate_shift                             ;
   mov  cl,byte ptr [option_rate_shift]         ;
   shr  eax,cl                                  ;
 ENDIF                                          ;
 mov  dword ptr [mp3_samples_output_size],eax   ;/
 timelog_end rdtsc_read_header_extra
 ret
;------------------
;:----------------- Mp3 code bitstream read granules
;------------------
align code_align
mp3_bitstream_read_granules:
;- - -
.data?
 align data_align
 @@region_address0      dd ?    ;end of region 0
 @@region_address1      dd ?    ;end of region 1
 @@saved_sp             dd ?
 mp3_main_data_size     dd ?  ;size of main data in bits (0=none/silent)
.code
;- - -
 timelog_start rdtsc_read_granule
 mov  dword ptr [@@saved_sp],esp                        ;-save sp (for error/abort)
;- - -
 mov  dword ptr [mp3_main_data_size],0
 mov  dword ptr [mp3_curr_granule],0            ;\
 mov  ebx,offset mp3_granules                   ; loop granules
@@hdr_granule_lop:                              ;
 push ebx                                       ;/
 mov  dword ptr [mp3_curr_channel],0            ;\loop channels
@@hdr_channel_lop:                              ;/
 mp3mac_get_n_bits 12                                   ;\
 mov  edx,dword ptr [mp3_main_data_size]                ;
 mov  dword ptr [ebx+$mp3gr_part2_3_length],eax         ; part2_3_length
 mov  dword ptr [ebx+$mp3gr_part2_3_start],edx          ; (and implied
 add  eax,edx                                           ; start/end)
 mov  dword ptr [ebx+$mp3gr_part2_3_end],eax            ;
 mov  dword ptr [mp3_main_data_size],eax                ;/
 mp3mac_get_n_bits 9                                    ;\big_values
 mov  dword ptr [ebx+$mp3gr_big_values],eax             ;/
 mp3mac_get_n_bits 8                                    ;\
 add  eax,400-210                                       ; global gain
 cmp  dword ptr [mp3_hdr_mode_val],MP3_JSTEREO          ; ;\
 jne  short @@not_ms_stereo                             ; ; when MS_STEREO,
 test dword ptr [mp3_hdr_mode_ext],MODE_EXT_MS_STEREO   ; ; subtract 2, to
 jz   short @@not_ms_stereo                             ; ; precompute the 1/sqrt(2) renormalization factor
 sub  eax,2                                             ; ; eg. required for test45
@@not_ms_stereo:                                        ; ;/
 mov  dword ptr [ebx+$mp3gr_global_gain],eax            ;/
 mov  cl,byte ptr [mp3_num_compress_bits]   ;=4 or 9    ;\
 mp3mac_get_n_bits cl                                   ; scalefac_compress
 mov  dword ptr [ebx+$mp3gr_scalefac_compress],eax      ;/
;- - -
 mp3mac_get_bit_to_cy                                   ;\blocksplit_flag
 jnc        @@no_blocksplit                             ;/
;- - -
;@@has_blocksplit:
 mp3mac_get_n_bits 2                                    ;\
 cmp  eax,0     ;invalid block type                     ; block_type
 je         @@error                                     ;
 mov  dword ptr [ebx+$mp3gr_block_type],eax ;\          ;/
 cmp  eax,2     ;block_tyoe                 ;/          ;\
 mov  eax,36/2  ;region_size (default)                  ;
 je   short @@this_region_size   ;--> 36/2              ; region_size[0,1,2]
 cmp  dword ptr [mp3_hdr_sample_rate_index],2           ;
 jbe  short @@this_region_size   ;--> 36/2              ;
 mov  eax,54/2  ;region_size                            ;
 cmp  dword ptr [mp3_hdr_sample_rate_index],8           ;
 jne  short @@this_region_size   ;--> 54/2              ;
 mov  eax,108/2  ;region_size (for rate=8)              ;
@@this_region_size:                                     ;
 mov  dword ptr [ebx+$mp3gr_region_size+0*4],eax        ;
 mov  dword ptr [ebx+$mp3gr_region_size+1*4],576/2      ;
 mov  dword ptr [ebx+$mp3gr_region_size+2*4],576/2      ;/
 mp3mac_get_n_bits 1                                    ;\switch_point
 mov  dword ptr [ebx+$mp3gr_switch_point],eax           ;/
 IRP nn,0,1     ;only 0..1 for blocksplit               ;\
   mp3mac_get_n_bits 5                                  ; table_select[0,1]
   mov  dword ptr [ebx+$mp3gr_table_select+nn*4],eax    ;
 ENDM                                                   ;/
 IRP nn,0,1,2                                           ;\
   mp3mac_get_n_bits 3                                  ;
   shl  eax,3                                           ; subblock_gain[0,1,2]
   mov  dword ptr [ebx+$mp3gr_subblock_gain+nn*4],eax   ;
 ENDM                                                   ;/
 jmp        @@blocksplit_done
;---
@@no_blocksplit:
 mov  dword ptr [ebx+$mp3gr_block_type],0               ;-block_type
 mov  dword ptr [ebx+$mp3gr_switch_point],0             ;-switch_point
 IRP nn,0,1,2   ;range 0..2 when non-blocksplit         ;\
   mp3mac_get_n_bits 5                                  ; table_select[0,1,2]
   mov  dword ptr [ebx+$mp3gr_table_select+nn*4],eax    ;
 ENDM                                                   ;/
 mp3mac_get_n_bits 4   ;4bit                ;00h..0Fh   ;\
 inc  eax                                   ;01h..10h   ; region_address0
 mov  dword ptr [@@region_address0],eax                 ;/
 mp3mac_get_n_bits 3   ;3bit (added to above 4bit)      ;\
 inc  eax                                   ;01h..08h   ; region_address1
 add  eax,dword ptr [@@region_address0]     ;02h..18h   ;
 mov  dword ptr [@@region_address1],eax                 ;/
 mov  eax,dword ptr [mp3_hdr_sample_rate_index]         ;\
 shl  eax,5                                             ;
 add  eax,dword ptr [@@region_address0]                 ; region_size[0]
 movzx eax,word ptr [mp3_band_index_long+eax*2]         ;
 shr  eax,1                                             ;
 mov  dword ptr [ebx+$mp3gr_region_size+0*4],eax        ;/
 mov  eax,dword ptr [mp3_hdr_sample_rate_index]         ;\
 shl  eax,5                                             ;
 add  eax,dword ptr [@@region_address1]                 ; region_size[1]
 movzx eax,word ptr [mp3_band_index_long+eax*2]         ;
 shr  eax,1                                             ;
 mov  dword ptr [ebx+$mp3gr_region_size+1*4],eax        ;/
 mov  dword ptr [ebx+$mp3gr_region_size+2*4],576/2      ;-region_size[2]
;- - -
@@blocksplit_done:
 lea  edi,[ebx+$mp3gr_region_size+0]                    ;\
 xor  edx,edx  ;base                                    ;
 mov  cl,3     ;lopcount                                ;
@@trunc_region_size_lop:                                ; convert region offsets
 mov  eax,dword ptr [edi]  ;region_size[i]  ;-get       ; to region sizes
 cmp  eax,dword ptr [ebx+$mp3gr_big_values] ;\          ; and truncate size
 jbe  short @@trunc_region_size_this        ; trunc     ; to big_values
 mov  eax,dword ptr [ebx+$mp3gr_big_values] ;           ;
@@trunc_region_size_this:                   ;/          ;
 sub  eax,edx   ;sub.base                               ;
 mov  dword ptr [edi],eax  ;region_size[i]  ;-put back  ;
 add  edx,eax   ;apply new base (and undo sub.base)     ;
 add  edi,4                                             ;
 dec  cl        ;lopcount                               ;
 jnz  short @@trunc_region_size_lop                     ;/
;- - -
 mov  dword ptr [ebx+$mp3gr_short_start],13   ;\default ;\
 mov  dword ptr [ebx+$mp3gr_long_end],22      ;/        ;
 cmp  dword ptr [ebx+$mp3gr_block_type],2     ;\type    ; compute band indexes
 jne  short @@these_band_indices              ;/        ;
 mov  dword ptr [ebx+$mp3gr_short_start],0    ;\zero    ;
 mov  dword ptr [ebx+$mp3gr_long_end],0       ;/        ;
 cmp  dword ptr [ebx+$mp3gr_switch_point],0   ;\switch  ;
 jz   short @@these_band_indices              ;/        ;
 mov  dword ptr [ebx+$mp3gr_short_start],2    ;\        ; ;\
 mov  dword ptr [ebx+$mp3gr_long_end],4       ; 8000Hz  ; ; if switched mode,
 cmp  dword ptr [mp3_hdr_sample_rate_index],8 ;         ; ; handle first 36
 je   short @@these_band_indices              ;/        ; ; samples as long
 cmp  dword ptr [mp3_hdr_sample_rate_index],2 ;\        ; ; blocks.
 mov  dword ptr [ebx+$mp3gr_short_start],3    ;         ; ; For 8000Hz, handle
 mov  dword ptr [ebx+$mp3gr_long_end],8       ;         ; ; first 48 exponents
 jbe  short @@these_band_indices              ;         ; ; as long blocks (XXX: check this!)
 mov  dword ptr [ebx+$mp3gr_long_end],6       ;/        ; ;/      (XXX ...is that 36,48 related to "reorder"?)
@@these_band_indices:                                   ;/
 xor  eax,eax                                           ;\
 cmp  dword ptr [mp3_hdr_flag_lsf],0                    ;
 jnz  short @@no_preflag                                ; preflag (if any)
 mp3mac_get_n_bits 1                                    ;
@@no_preflag:                                           ;
 mov  dword ptr [ebx+$mp3gr_preflag],eax                ;/
 mp3mac_get_n_bits 1                                    ;\
 inc  eax                                               ; scalefac_scale
 mov  dword ptr [ebx+$mp3gr_scalefac_scale],eax         ;/
 mp3mac_get_n_bits 1                                    ;\
 add  eax,10h   ;table 10h..11h (quad_vlc)              ; count1table_select
 mov  dword ptr [ebx+$mp3gr_count1table_select],eax     ;/
 IF log_granules
   mov  edx,offset txt_granule                    ;\
   call wrstr_edx                                 ;/
   mov  edx,offset txt_block_type                 ;\
   call wrstr_edx                                 ; type
   mov  eax,dword ptr [ebx+$mp3gr_block_type]     ;
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_switch_point               ;\
   call wrstr_edx                                 ; switch
   mov  eax,dword ptr [ebx+$mp3gr_switch_point]   ;
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_global_gain                ;\
   call wrstr_edx                                 ; gain
   mov  eax,dword ptr [ebx+$mp3gr_global_gain]    ;
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_scalefac_compress            ;\
   call wrstr_edx                                   ;
   mov  eax,dword ptr [ebx+$mp3gr_scalefac_compress];
   call wr_decimal_eax                              ;/
   mov  edx,offset txt_short_start                ;\
   call wrstr_edx                                 ; start
   mov  eax,dword ptr [ebx+$mp3gr_short_start]    ;
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_long_end                   ;\
   call wrstr_edx                                 ; end
   mov  eax,dword ptr [ebx+$mp3gr_long_end]       ;
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_preflag                    ;\
   call wrstr_edx                                 ; preflag
   mov  eax,dword ptr [ebx+$mp3gr_preflag]        ;
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_scfsi                      ;\
   call wrstr_edx                                 ; scfsi
   mov  eax,dword ptr [ebx+$mp3gr_scfsi]          ; (from hdr)
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_scalefac_scale             ;\
   call wrstr_edx                                 ; scale
   mov  eax,dword ptr [ebx+$mp3gr_scalefac_scale] ;
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_count1table_select         ;\
   call wrstr_edx                                 ; count1
   mov  eax,dword ptr [ebx+$mp3gr_count1table_select] ;quad
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_region_sizes               ;\
   call wrstr_edx                                 ;
   mov  eax,dword ptr [ebx+$mp3gr_region_size+0]  ;
   call wr_decimal_eax                            ; regions
   call wrcomma                                   ;
   mov  eax,dword ptr [ebx+$mp3gr_region_size+4]  ;
   call wr_decimal_eax                            ;
   call wrcomma                                   ;
   mov  eax,dword ptr [ebx+$mp3gr_region_size+8]  ;
   call wr_decimal_eax                            ;/
   mov  edx,offset txt_big_values                 ;\bigval
   call wrstr_edx                                 ; aka last
   mov  eax,dword ptr [ebx+$mp3gr_big_values]     ; region
   call wr_decimal_eax                            ;/
        ;table_select[0,1,2]
        ;subblock_gain[0,1,2]
   mov  edx,offset txt_part2_3_length             ;\
   call wrstr_edx                                 ; length
   mov  eax,dword ptr [ebx+$mp3gr_part2_3_length] ;
   call wr_decimal_eax                            ;/
   call wrcrlf
 ENDIF
 add  ebx,$mp3gr_entrysiz*2                     ;\
 inc  dword ptr [mp3_curr_channel]              ;
 mov  eax,dword ptr [mp3_curr_channel]          ; next channel
 cmp  eax,dword ptr [mp3_src_num_channels]      ;
 jb         @@hdr_channel_lop                   ;/
 pop  ebx                                       ;\
 add  ebx,$mp3gr_entrysiz                       ;
 inc  dword ptr [mp3_curr_granule]              ; next granule
 mov  eax,dword ptr [mp3_curr_granule]          ;
 cmp  eax,dword ptr [mp3_nb_granules]           ;
 jb         @@hdr_granule_lop                   ;/
;- - -
 timelog_end rdtsc_read_granule
 clc    ;okay
 ret
;---
@@error:
 timelog_end rdtsc_read_granule
 mov  esp,dword ptr [@@saved_sp]
 stc    ;bad
 ret
;------------------
;:----------------- Mp3 code bitstream append to main_data_pool
;------------------
align code_align
mp3_bitstream_append_to_main_data_pool:    ;in: esi=src (byte position)
;XXX this is quite slow
;    it does usually copy about 300h bytes (less than 1Kbyte)
;    execution is about 10,000 clks (when pre-caching memory mapped file)
;    execution is about 25,000 clks (when NOT pre-caching memory mapped file)
;- - -
 timelog_start rdtsc_append_main                                ;-
;mov  esi,esi   ;byte position                  ;\calc size     ;\
 mov  ecx,dword ptr [mp3_src_frame_end]         ; of remaining  ;
 sub  ecx,esi                                   ; data          ;
 IF log_fatal
   jb         @@fatal_append_main
 ELSE
   jb         fatalunexpected                   ;/              ;
 ENDIF
 mov  edi,dword ptr [main_data_pool_wr_ptr]                     ;
 lea  eax,[edi+ecx]  ;dst_end                                   ;
 cmp  eax,offset main_data_pool_end                             ;
 jbe  short @@pool_inrange                                      ; append to main_data_pool
 push ecx                                       ;\              ;
 push esi                                       ;               ;
 lea  esi,[edi-512]                             ; move old data ;
 mov  edi,offset main_data_pool_start           ; to start of   ;
 mov  ecx,512/4                                 ; pool          ;
 rep  movsd                                     ;               ;
 pop  esi                                       ;               ;
 pop  ecx                                       ;/              ;
@@pool_inrange:                                                 ;
 mov  eax,edi     ;location of new data         ;\lookback      ;
 sub  eax,dword ptr [mp3_main_data_begin]       ;/location      ;
 rep  movsb                                     ;\append new    ;
 mov  dword ptr [main_data_pool_wr_ptr],edi     ;/data to pool  ;/
 cmp  eax,offset main_data_pool_start           ;\reject reference to missing
 js   short @@below_pool_start                  ;/frames (eg. l3-sin1k0db.bit)
;- - -
 mov  dword ptr [mp3_bitstream_start],eax       ;\
 mov  eax,0     ;origin 0                       ; start DATA bitstream
 mp3mac_bitstream_set_position                  ;/
@@done:
 timelog_end rdtsc_append_main                                  ;-
 ret
;---
@@below_pool_start:
 mov  dword ptr [mp3_samples_output_size],0     ;-force output size=0
 IF log_frames                                  ;\
   mov  edx,offset txt_missing_main_data        ; warn about reference
   call wrstr_edx                               ; to missing data
 ENDIF                                          ;/
 jmp  short @@done
;---
 IF log_fatal
  @@fatal_append_main:
   mov  edx,offset txt_fatal_append_main
   call wrstr_edx
   jmp  fatalunexpected
 ENDIF
;------------------
;:----------------- Mp3 code bitstream read scalefacs
;------------------
align code_align
mp3_bitstream_read_scalefacs:
;- - -
.data?
 align data_align
 @@scfsi                dd ?
.code
;- - -
 @@get_bl_scalefacs_with_dl_bits macro limit_max                        ;\
  local @@scalefac_get_lop,@@quickfill,@@skip_quickfill                 ;
   cmp  dl,00h  ;LSB of edx, slen[i]                                    ;
   jz   short @@quickfill                                               ;
  @@scalefac_get_lop:                           ;\                      ;
   mov  cl,dl   ;LSB of edx, slen[i]            ; get                   ;
   mp3mac_get_n_bits cl                         ;                       ;
   IF limit_max                                 ; ;\for intensity       ;
     mov  cl,dl ;numbits                        ; ; stereo, check if    ;
     mov  ah,al ;val                            ; ; max value           ;
     inc  ah    ;val+1                          ; ; (eg. for 5bit       ;
     shr  ah,cl ;bit0=is.max.value              ; ; max is 1Fh),        ;
     shl  ah,7  ;bit7=is.max.value              ; ; and set flag        ;
     or   al,ah ;apply NO_INTENSITY_FLAG        ; ;                     ; ;<-- that flag could be stored in a separate array (the downside of storing it in bit7 of the scalefac is that needs to be masked off for normal scalefac processing) (eg. lieff uses "ist_pos", and libmad "gr1 aka gr[1]")
   ENDIF                                        ; ;/                    ;
   stosb                                        ;                       ;
   dec  bl                                      ;                       ;
   jnz  short @@scalefac_get_lop                ;/                      ;
   jmp  short @@skip_quickfill                                          ;
  @@quickfill:                                  ;\                      ;
   push ecx                                     ; quickfill             ;
   moz  ecx,bl                                  ; (faster than repeated ;
   mov  al,00h+limit_max*80h ;NO_INTENSITY_FLAG ; repeated getbits(0)   ;
   rep  stosb                                   ;                       ;
   pop  ecx                                     ;/                      ;
  @@skip_quickfill:                                                     ;
 endm                                                                   ;/
;- - -
 timelog_start rdtsc_read_scalefac
 lea  edi,[ebx+$mp3gr_scale_factors]            ;-dest
 cmp  dword ptr [mp3_hdr_flag_lsf],0            ;\lsf
 jnz        @@body_lsf_nonzero                  ;/
;- - -
;@@body_lsf_zero:   ;MPEG1 scale factors...
 mov  eax,dword ptr [ebx+$mp3gr_scalefac_compress]      ;\slen[0,1]
 mov  dx,word ptr [mp3_slen_table+eax*2]  ;slen[0,1]    ;/
 cmp  dword ptr [ebx+$mp3gr_block_type],2               ;\type
 jne  short @@body_lsf_zero_non_type2                   ;/
;@@body_lsf_zero_is_type2:
 push ebx                                                       ;\
 mov  al,18   ;num factors                    ;=18      ;\      ;
 sub  al,byte ptr [ebx+$mp3gr_switch_point]   ;=17..18  ;       ;
 mov  bl,al   ;bl=numfacs    ;smashes ebx     ;=17..18  ;       ;
;mov  dl,dl   ;dl=numbits                               ;       ;
 @@get_bl_scalefacs_with_dl_bits 0      ;--->           ;/      ; type=2
 shr  edx,8   ;dl=numbits                               ;\      ;
 mov  bl,18   ;bl=numfacs                     ;=18      ;       ;
 @@get_bl_scalefacs_with_dl_bits 0      ;--->           ;/      ;
 pop  ebx                                                       ;
 jmp        @@body_lsf_zeropad                          ;-pad   ;/
;---
@@body_lsf_zero_non_type2:
 push ebx     ;--->                                             ;\
 ror  edx,8     ;\                                              ;
 mov  dh,dl     ; slen[0,1,2,3] = slen[0,0,1,1]                 ;
 rol  edx,16    ;                                               ; type<>2
 mov  dl,dh     ;/                                              ;
 mov  al,byte ptr [ebx+$mp3gr_scfsi]       ;\                   ;
 shl  al,4    ;scfsi, move to upper 4bit   ;                    ;
 mov  byte ptr [@@scfsi],al                ;/                   ;
 mov  ebx,05050506h  ;num[0..3]  ;smashes ebx                   ;
@@body_lsf_zero_non_type2_lop:   ;loop 4 times ...      ;\      ;
 shl  byte ptr [@@scfsi],1                      ;\      ;       ;
 jc   short @@body_lsf_zero_non_type2_copy      ;/      ;       ;
 @@get_bl_scalefacs_with_dl_bits 0              ;\get   ;       ;
 jmp  short @@body_lsf_zero_non_type2_next      ;/      ;       ;
@@body_lsf_zero_non_type2_copy:                         ;       ;
 push ecx       ;backup ecx                     ;\      ;       ;
 mov  eax,esi   ;backup esi                     ;       ;       ;
 moz  ecx,bl                                    ; copy  ;       ;
 lea  esi,[edi-$mp3gr_entrysiz] ;src=granule[0] ; from  ;       ;
 rep  movsb                     ;dst=granule[1] ; prev  ;       ;
 mov  esi,eax   ;restore esi                    ;       ;       ;
 pop  ecx       ;restore ecx                    ;/      ;       ;
@@body_lsf_zero_non_type2_next:                         ;       ;
 shr  edx,8   ;dl=next slen                             ;       ;
 shr  ebx,8   ;bl=next numfacs                          ;       ;
 jnz  short @@body_lsf_zero_non_type2_lop               ;/      ;
 pop  ebx     ;<---                                             ;
 mov  al,00h                                            ;\pad   ;
 stosb                                                  ;/      ;
 ;no$note: above applies 6+5+5+5+1 = 22 scale factors           ;
 ;that is, remaining 18 entries are uninitialized (?)           ;
 jmp        @@body_lsf_done                                     ;/
;--- --- ---
@@body_lsf_nonzero:    ;LSF scale factors...
 mov  edx,dword ptr [ebx+$mp3gr_scalefac_compress]              ;\
 test dword ptr [mp3_hdr_mode_ext],MODE_EXT_I_STEREO            ;
 jz   short @@normal_scalefac                                   ;
 cmp  dword ptr [mp3_curr_channel],0                            ;
 jz   short @@normal_scalefac                                   ;
 add  edx,512     ;for 2nd channel of intensity_stereo          ;
@@normal_scalefac:                                              ;/
 mov  al,byte ptr [mp3_lsf_sf_expand_exploded_table+edx*8+5]    ;\preflag
 or   byte ptr [ebx+$mp3gr_preflag],al   ;force preflag (if so) ;/
 push ebx                                                       ;\
 moz  eax,byte ptr [mp3_lsf_sf_expand_exploded_table+edx*8+4]   ;  ;-tindex2
 cmp  dword ptr [ebx+$mp3gr_block_type],2                       ;  ;\
 jne  short @@this_tindex1      ;--> index+0   (normal)         ;  ; plus
 mov  ebx,dword ptr [ebx+$mp3gr_switch_point]                   ;  ; tindex1
 lea  eax,[eax+ebx*4+4]     ;0,1 --> index+4,8 (type=2)         ;  ;
@@this_tindex1:                                                 ;  ;/
 mov  ebx,dword ptr [mp3_lsf_nsf_table+eax]  ;num[0,1,2,3]      ;  ;-numfacs[0..3]
 mov  edx,dword ptr [mp3_lsf_sf_expand_exploded_table+edx*8+0]  ;  ;-slen[0..3]
@@scalefax_outer_lop:  ;loop up to 4 times...           ;\      ;
 @@get_bl_scalefacs_with_dl_bits 1      ;--->           ;       ; scale factors
 shr  edx,8   ;dl=next slen[i]          ;\              ;       ;
 shr  ebx,8   ;bl=next numfacs[i]       ; next          ;       ;
 jnz  short @@scalefax_outer_lop        ;/              ;/      ;
 pop  ebx                                                       ;
 ;- - -                                                         ;
 ;for below, reportedly "XXX: should compute exact size"        ;
 ;(but how? are there cases with less than 40 byte needed?)     ;
 ;(maybe depending on block_type or so?)                        ;/
;- - -
@@body_lsf_zeropad:                                             ;\
 mov  edx,ecx   ;save ecx                                       ;
 lea  ecx,[ebx+$mp3gr_scale_factors+40] ;\zeropad remaining     ;
 sub  ecx,edi          ;remaining len   ; entries in 40-byte    ;
 jb   short fatal_scalefactors          ; table                 ;
 mov  al,00h                            ;                       ;
 rep  stosb                             ;/                      ;
 mov  ecx,edx   ;restore ecx                                    ;/
@@body_lsf_done:
 timelog_end rdtsc_read_scalefac
 ret
;---
fatal_scalefactors:
 IF log_fatal
   mov  edx,offset txt_fatal_too_many_scale_factors
   call wrstr_edx
   mov  eax,ecx
   call wrhexeax
   call wrcrlf
 ENDIF
 jmp  fatalunexpected
;------------------
;:----------------- Mp3 code bitstream xlat scalefacs
;------------------
align code_align
mp3_get_exponents_from_scale_factors:   ;in: ebx=granule, out: [mp3_exponents]
;- - -
.data?
 align data_align
 @@gains dd 3 dup (?)
.code
;- - -
 timelog_start rdtsc_xlat_scalefac
 mp3mac_push_bitstream  ;save bitstream registers
 IF log_scalefac
   mov  edx,offset txt_scalefacs        ;\
   call wrstr_edx                       ;/
 ENDIF
 IF RUN_LENGTH
   mov  dword ptr [@@rle_point],0
   mov  cl,byte ptr [ebx+$mp3gr_scalefac_scale]
  .data?
   align data_align
   @@rle_point dd ?
  .code
 ENDIF
 mov  edi,offset mp3_exponents  ;dst
;- - -
 xor  edx,edx                                           ;\
 cmp  edx,dword ptr [ebx+$mp3gr_long_end] ;can be 0..22 ;
 jae  short @@long_done                                 ; long ...
 IF log_scalefac                                        ;
   push edx                                             ;
   mov  edx,offset txt_spc_long         ;\              ;
   call wrstr_edx                       ;/              ;
   pop  edx                                             ;
 ENDIF                                                  ;
 mov  eax,dword ptr [mp3_hdr_sample_rate_index] ;\      ;
 imul eax,22                                    ; bstab ;
 lea  ebp,[mp3_band_size_long+eax]              ;/      ;
 mov  eax,dword ptr [ebx+$mp3gr_preflag]        ;\      ;
 imul eax,22                                    ; pretab;
 lea  esi,[mp3_pretab+eax]                      ;/      ;
@@long_lop:    ;for i=0 to long_end-1                   ; ;\
 moz  eax,byte ptr [ebx+$mp3gr_scale_factors+edx]       ; ;
 and  al,7fh    ;strip NO_INTENSITY_FLAG                ; ;
 add  al,byte ptr [esi+edx]             ;pretab[edx]    ; ;
 IF RUN_LENGTH   ;this is FASTER (storing "num,val")    ; ;
   shl  eax,cl                                            ; ;
   neg  eax                                               ; ;
   add  eax,dword ptr [ebx+$mp3gr_global_gain]            ; ;
   IF log_scalefac                                        ; ; ;
     call wrspc                           ;\              ; ; ;
     call wr_decimal_eax                  ;/              ; ; ;
   ENDIF                                                  ; ; ;
   shl  eax,16   ;msw=val
   mov  al,byte ptr [ebp+edx]            ;bstab[edx]     ; ; ;\
   add  eax,dword ptr [@@rle_point]
   mov  word ptr [@@rle_point],ax
   stosd         ;msw=val, lsw=point
 ELSE  ;this is SLOWER (filling "num" entries with "val") ; ;
   mov  cl,byte ptr [ebx+$mp3gr_scalefac_scale]           ; ;
   shl  eax,cl                                            ; ;
   neg  eax                                               ; ;
   add  eax,dword ptr [ebx+$mp3gr_global_gain]            ; ;
   moz  ecx,byte ptr [ebp+edx]            ;bstab[edx]     ; ; ;\
   IF log_scalefac                                        ; ; ;
     call wrspc                           ;\              ; ; ;
     call wr_decimal_eax                  ;/              ; ; ;
   ENDIF                                                  ; ; ;
   rep  stosw                                             ; ; ;/
 ENDIF
 inc  edx                                               ; ;
 cmp  edx,dword ptr [ebx+$mp3gr_long_end]               ; ;/
 jb   short @@long_lop                                  ;/
@@long_done:
;- - -
 mov  edx,dword ptr [ebx+$mp3gr_short_start]            ;\
 cmp  edx,13                                            ;
 jae        @@skip_shorts                               ; short ...
 IF log_scalefac                                        ;
   push edx                                             ;
   mov  edx,offset txt_spc_short        ;\              ;
   call wrstr_edx                       ;/              ;
   pop  edx                                             ;
 ENDIF                                                  ;
 mov  eax,dword ptr [mp3_hdr_sample_rate_index] ;\      ;
 imul eax,13                                    ; bstab ;
 lea  ebp,[mp3_band_size_short+eax]             ;/      ;
 mov  esi,dword ptr [ebx+$mp3gr_long_end]       ;-      ;
 IRP nn,0,1,2                                           ; ;\
   mov  eax,dword ptr [ebx+$mp3gr_global_gain]          ; ;
   sub  eax,dword ptr [ebx+$mp3gr_subblock_gain+nn*4]   ; ;
   mov  dword ptr [@@gains+nn*4],eax                    ; ;
 ENDM                                                   ; ;/
;- - -                                                  ;
@@short_lop:                                            ; ;\
 IRP nn,0,1,2                                           ; ; ;\
   moz  eax,byte ptr [ebx+$mp3gr_scale_factors+esi]     ; ; ;
   and  al,7fh   ;strip NO_INTENSITY_FLAG               ; ; ;
   inc  esi                                             ; ; ;
   IF RUN_LENGTH                                        ; ; ;
     shl  eax,cl                                        ; ; ;
     neg  eax                                           ; ; ;
     add  eax,dword ptr [@@gains+nn*4]                  ; ; ;
     IF log_scalefac                                    ; ; ;
       call wrspc                           ;\          ; ; ;
       call wr_decimal_eax                  ;/          ; ; ;
     ENDIF                                              ; ; ;
     shl  eax,16   ;msw=val                             ; ; ; ;\
     mov  al,byte ptr [ebp+edx]          ;bstab[edx]    ; ; ; ;
     add  eax,dword ptr [@@rle_point]                   ; ; ; ;
     mov  word ptr [@@rle_point],ax                     ; ; ; ;
     stosd         ;msw=val, lsw=point                  ; ; ; ;/
   ELSE                                                 ; ; ;
     mov  cl,byte ptr [ebx+$mp3gr_scalefac_scale]       ; ; ;
     shl  eax,cl                                        ; ; ;
     neg  eax                                           ; ; ;
     add  eax,dword ptr [@@gains+nn*4]                  ; ; ;
     moz  ecx,byte ptr [ebp+edx]          ;bstab[edx]   ; ; ; ;\
     IF log_scalefac                                    ; ; ; ;
       call wrspc                           ;\          ; ; ; ;
       call wr_decimal_eax                  ;/          ; ; ; ;
     ENDIF                                              ; ; ; ;
     rep  stosw                                         ; ; ; ;/
   ENDIF                                                ; ; ;
 ENDM                                                   ; ; ;/
 inc  edx                       ;\                      ; ;
 cmp  edx,13                    ;                       ; ;
 jb         @@short_lop         ;/                      ; ;/
@@skip_shorts:                                          ;/
 IF log_scalefac
   call wrcrlf
 ENDIF
 mp3mac_pop_bitstream   ;restore bitstream registers
 timelog_end rdtsc_xlat_scalefac
 ret
;------------------
;:----------------- Mp3 code bitstream huffman
;------------------
align code_align
mp3_huffman_decode:   ;in: ebx=granule, out: [sb_hybrid..]
 .data?
  align data_align
  @@III         dd ?
  align data_align
  @@JJJ         dd ?
  align data_align
  @@linbits     dd ?
  align data_align
  @@vlc_table   dd ?
 ;@@last_pos    dd ?
 .code
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  @@getexpval macro has_linbits    ;in: eax,zf
    local @@small,@@nonzero,@@get_sign,@@this_sign
     jz         @@this_sign  ;eax=0 (without sign)  ;-when x=0
     IF RUN_LENGTH
      IF has_linbits
       mov  edx,dword ptr [@@rle_val]
      ELSE
       mov  edx,dword ptr [@@rle_val_x_40h]
      ENDIF
     ELSE
       moz  edx,word ptr [mp3_exponents+edi*2]        ;-
     ENDIF
     IF has_linbits
       cmp  eax,15                                    ;\when x=1..14
       jb   short @@small                             ;/
       mov  cl,byte ptr [@@linbits]   ;=0..13         ;\when x=15, with linbits
       IF FAST_SMALL EQ 0                             ;
         cmp cl,0           ;\slightly faster         ;
         jz  short @@small  ;/                        ;
       ENDIF                                          ;
       mp3mac_get_n_bits cl  ;value   ;=0..1FFFh      ;
       mov  cl,dl     ;exponenent.lsb                 ;  ;\
       and  cl,03h    ;exponenent.lsb                 ;  ;
       shr  edx,2     ;exponenent.msb                 ;  ; mp3_l3_unscale
       lea  eax,[eax*4+15*4]         ;(value+15)*4    ;  ;
       or   al,cl     ;exponenent.lsb+(value+15)*4    ;  ;
       IF MERGE_TABLE_4_3
         mov  eax,dword ptr [mp3_table_4_3_value+eax*4] ;  ;
         mov  cl,al
       ELSE
         mov  cl,byte ptr [mp3_table_4_3_exp+eax]       ;  ;
         mov  eax,dword ptr [mp3_table_4_3_value+eax*4] ;  ;
       ENDIF
       sub  cl,dl     ;sub exponenent.msb             ;  ;
       shr  eax,cl                                    ;  ;   ;-UNSIGNED ! (though, actually it's a "signed" value in range 0..7FFFFFFFh)
       cmp  cl,31                 ;\check range       ;  ;
       jbe  short @@get_sign      ;/                  ;  ;
       xor  eax,eax               ;\                  ;  ;   ;\force zero (for CPUs that ignore MSBs of shift amounts >31)
       jmp  short @@get_sign      ;/                  ;/ ;/  ;/
      ;align code_align
      @@small:
     ENDIF
     IF has_linbits OR (RUN_LENGTH EQ 0)
      shl  edx,4+2         ;mul16*4                  ;\when x<15 aka x=1..14
     ENDIF
     mov  eax,dword ptr [mp3_expval_table+edx+eax*4];/
    @@get_sign:
     mp3mac_get_bit_to_cy                   ;\
     IF 1   ;slightly faster                ;
       sbb  edx,edx  ;cy=0,1 --> 0,FFFFFFFF ;
       xor  eax,edx  ;invert if cy was 1    ; get sign (negate if sign=1)
       sub  eax,edx  ;add 1 if cy was 1     ;
     ELSE                                   ;
       jnc  short @@this_sign               ;
       neg  eax                             ;
     ENDIF                                  ;
    @@this_sign:                            ;/
  endm
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
 timelog_start rdtsc_read_huffman
 IF COARSE_END
   mov  eax,dword ptr [ebx+$mp3gr_part2_3_end]
   shr  eax,3
   add  eax,dword ptr [mp3_bitstream_start]
   mov  dword ptr [@@coarse_end],eax
  .data?
   align data_align
   @@coarse_end dd ?
  .code
 ENDIF
;timelog_start rdtsc_huff_pairs
 xor  edi,edi        ;s_index = 0
 IF RUN_LENGTH
   @@get_runlength macro name
     cmp  edi,dword ptr [@@rle_point]
     jae        @@rle_fetch_next_&name
    @@rle_back_&name:
   endm
   @@next_runlength macro name
    align code_align
    @@rle_fetch_next_&name:
    @@rle_retry_&name:
     mov  eax,dword ptr [@@rle_ptr]
     add  dword ptr [@@rle_ptr],2+2
     mov  eax,dword ptr [eax]  ;msw=val, lsw=point
     cmp  di,ax       ;point       ;\needed if rle fetching
     jae  short @@rle_retry_&name  ;/was skipped
     mov  word ptr [@@rle_point],ax
     shr  eax,16
     mov  dword ptr [@@rle_val],eax
     IFDIFI <name>,<quads>
       shl  eax,4+2
       ;could also pre-add "offset mp3_expval_table" (but isn't faster)
       mov  dword ptr [@@rle_val_x_40h],eax
     ENDIF
     jmp  @@rle_back_&name
   endm

  .data?
   align data_align
   @@rle_point     dd ?
   @@rle_ptr       dd ?
   @@rle_val       dd ?
   @@rle_val_x_40h dd ?
  .code
   mov  dword ptr [@@rle_ptr],offset mp3_exponents
   mov  dword ptr [@@rle_point],0
 ENDIF
 mov  @@III,0        ;i=0
@@low_freq_lop_i:    ;for i=0 to 2   ;low frequencies (called big_values)...
 IF log_huffcodes
   pusha
   mov  edx,offset txt_lowfreq_region
   call wrstr_edx
   mov  eax,@@III
   call wrhexal
   call wrcrlf
   popa
 ENDIF
 mov  edx,@@III
 mov  eax,dword ptr [ebx+$mp3gr_region_size+edx*4]      ;\
 cmp  eax,0                                             ;
 jz         @@low_freq_next_i                           ;
 mov  @@JJJ,eax                                         ;/
 mov  edx,dword ptr [ebx+$mp3gr_table_select+edx*4]     ;-select vlc table
 moz  eax,byte ptr [mp3_huff_data+edx*2+0]              ;-get huff.table number
 cmp  eax,0       ;huff.table                   ;\
 jnz  short @@low_freq_nonzero                  ;
 push ecx                               ;\      ;
 push edi                               ;       ; when huff.table=0,
 lea  edi,[ebx+$mp3gr_sb_hybrid+edi*4]  ; fill  ;
 mov  ecx,@@JJJ                         ;       ; simply set NUM*2 entries
 shl  ecx,1    ;num*2                   ;       ; to zero
 xor  eax,eax                           ;       ;
 rep  stosd    ;fill                    ;       ;     XXX if these are all zeroes, could they be quick-skipped elsewhere?
 pop  edi                               ;       ;
 pop  ecx                               ;/      ;
 add  edi,@@JJJ    ;\raise index accordingly    ;
 add  edi,@@JJJ    ;/(by num*2)                 ;
 jmp        @@low_freq_next_i                   ;/
;---
@@low_freq_nonzero:
 mov  dword ptr [@@vlc_table],eax  ;=1..15      ;-
 IF FAST_SMALL
   cmp  eax,14                   ;\only table 14..15 have linbits,
   jae        @@with_linbits     ;/so table 0..13 can use faster code...
  ;- - -
  @@low_freq_lop_j_small:    ;loop @@JJJ times...
   IF COARSE_END
     cmp  esi,dword ptr [@@coarse_end]
     ja         @@small_near_end
    @@small_not_end:
   ELSE
     mp3mac_bitstream_get_position                          ;\check end
     cmp  eax,dword ptr [ebx+$mp3gr_part2_3_end]            ; XXX is that actually needed? (in clean files, the loop should end as specified in "region_size") (although, that "region_size" uses hardcoded boundaries, so some files may want to abort before reaching that boundaries)
     jae        @@low_freq_abort_lop_j                      ;/
   ENDIF
   IF RUN_LENGTH                                              ;\
     @@get_runlength small                                    :
   ENDIF                                                      ;/
   mov  edx,dword ptr [@@vlc_table]                       ;\get huffcode
   mp3mac_get_huffcode  ;in: edx=table, out: eax=data     ;/
   push eax
   shr  eax,4   ;x                                        ;\
   @@getexpval 0                                          ; x
   mov  dword ptr [ebx+$mp3gr_sb_hybrid+edi*4+0],eax      ;/
   pop  eax
   and  eax,0fh ;y                                        ;\
   @@getexpval 0                                          ; y   ;no$note: minimp3 does re-use the above exponent here (from s_index+0, instead of from s_index+1), is that really intended/good?
   mov  dword ptr [ebx+$mp3gr_sb_hybrid+edi*4+4],eax      ;/
  ;- - -
   add  edi,2                             ;\
   dec  @@JJJ                             ; next j
   jnz        @@low_freq_lop_j_small      ;/
   jmp  @@low_freq_abort_lop_j
   IF COARSE_END
    align code_align
    @@small_near_end:
      mp3mac_bitstream_get_position                          ;\check end
      cmp  eax,dword ptr [ebx+$mp3gr_part2_3_end]            ; XXX is that actually needed? (in clean files, the loop should end as specified in "region_size") (although, that "region_size" uses hardcoded boundaries, so some files may want to abort before reaching that boundaries)
      jb         @@small_not_end
      jmp        @@low_freq_abort_lop_j                      ;/
    align code_align
   ENDIF
  ;align code_align
  @@with_linbits:
 ENDIF
 moz  eax,byte ptr [mp3_huff_data+edx*2+1]      ;\
 mov  dword ptr [@@linbits],eax    ;=0..13      ;/
;- - -
@@low_freq_lop_j:    ;loop @@JJJ times...
 IF COARSE_END
   cmp  esi,dword ptr [@@coarse_end]
   ja         @@lop_j_near_end
  @@lop_j_not_end:
 ELSE
   mp3mac_bitstream_get_position                          ;\check end
   cmp  eax,dword ptr [ebx+$mp3gr_part2_3_end]            ; XXX is that actually needed? (in clean files, the loop should end as specified in "region_size") (although, that "region_size" uses hardcoded boundaries, so some files may want to abort before reaching that boundaries)
   jae        @@low_freq_abort_lop_j                      ;/
 ENDIF
 IF RUN_LENGTH                                          ;\
   @@get_runlength full                                 ;
 ENDIF                                                  ;/
 mov  edx,dword ptr [@@vlc_table]                       ;\get huffcode
 mp3mac_get_huffcode  ;in: edx=table, out: eax=data     ;/
 IF 0;1
   cmp  eax,0                                             ;\
   jnz  short @@nonzero                                   ;
   mov  dword ptr [ebx+$mp3gr_sb_hybrid+edi*4+0],eax      ; ;\both x and y
   mov  dword ptr [ebx+$mp3gr_sb_hybrid+edi*4+4],eax      ; ;/are zero
   jmp        @@low_freq_next_j                           ;   (that "speedup" isn't really faster)
  ;---                                                    ;
  @@nonzero:                                              ;/
 ENDIF
 push eax
 shr  eax,4   ;x                                        ;\
 @@getexpval 1                                          ; x
 mov  dword ptr [ebx+$mp3gr_sb_hybrid+edi*4+0],eax      ;/
 pop  eax
 and  eax,0fh ;y                                        ;\
 @@getexpval 1                                          ; y   ;no$note: minimp3 does re-use the above exponent here (from s_index+0, instead of from s_index+1), is that really intended/good?
 mov  dword ptr [ebx+$mp3gr_sb_hybrid+edi*4+4],eax      ;/
;- - -
@@low_freq_next_j:                      ;\
 add  edi,2                             ; next j
 dec  @@JJJ                             ;
 jnz        @@low_freq_lop_j            ;/
@@low_freq_abort_lop_j:
@@low_freq_next_i:                      ;\
 inc  @@III                             ; next i
 cmp  @@III,3                           ;
 jb         @@low_freq_lop_i            ;/
;timelog_end rdtsc_huff_pairs
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;timelog_start rdtsc_huff_quads
 IF log_huffcodes
   mov  edx,offset txt_highfreq
   call wrstr_edx
 ENDIF
IFDEF @@last_pos
 mov  dword ptr [@@last_pos],0  ;-initially no last pos
ENDIF
 cmp  edi,572   ;aka 576-4      ;\skip if less than 4 entries left
 ja         @@high_freq_done    ;/(dunno if that can actually happen?)
@@high_freq_lop:   ;high frequencies ...
 ;can't use COARSE_END here, because "get_pos" is needed for "@@last_pos"
 ;though, @@last_pos isn't actually needed for debug info
 ;(and for checking if stepback is possible, which could also check if edi>4)
 ;XXX so... could/should use COARSE_END here !
 ;- - -
 IF COARSE_END                                          ;\
   cmp  esi,dword ptr [@@coarse_end]                    ; check if near end
   jbe  short @@high_freq_inrange                       ; (not actually faster)
   ERRIFDEF @@last_pos  ;above doesn't update last_pos  ;
 ENDIF                                                  ;/
 mp3mac_bitstream_get_position                          ;\
 cmp  eax,dword ptr [ebx+$mp3gr_part2_3_end]            ;
 IF 0        ;without last_pos stepback                 ;
   jae        @@high_freq_abort_lop                     ; check end
 ELSE    ;XXX below should use "jae" when at/ahove end  ;
   jb   short @@high_freq_inrange     ;not yet end      ;
   je         @@high_freq_abort_lop   ;okay, exact end  ;
   ;reportedly, some encoders generate an incorrect     ;
   ;size for this part, stepback in case of overrun...  ;
   ;XXX unknown which files/encoders do need that...    ;
   IFDEF @@last_pos                                     ;
     cmp  dword ptr [@@last_pos],0                      ;
     jz   short @@high_freq_cannot_stepback             ;
     mov  eax,dword ptr [@@last_pos]    ;\src stepback  ;
     mp3mac_bitstream_set_position      ;/              ;
   ELSE                                                 ;
     cmp  edi,4                                         ;
     jb   short @@high_freq_cannot_stepback             ;
   ENDIF                                                ;
   sub  edi,4     ;stepback, s_index-4  ;-dst stepback  ;
   IF log_huffcodes                                     ;
     mov  edx,offset txt_huff_stepback                  ;
     call wrstr_edx                                     ;
   ENDIF                                                ;
  @@high_freq_cannot_stepback:                          ;
   jmp        @@high_freq_abort_lop                     ;
  align code_align                                      ;
 ENDIF                                                  ;
@@high_freq_inrange:                                    ;
 IFDEF @@last_pos                                       ;
   mov  dword ptr [@@last_pos],eax                      ;
 ENDIF                                                  ;/
 mov  edx,dword ptr [ebx+$mp3gr_count1table_select]     ;\get huffcode (quad_vlc)
 mp3mac_get_huffcode  ;in: edx=table, out: eax=data     ;/
 mov  dl,al     ;flags                                  ;\
 shl  dl,4      ;flags, to upper 4bit                   ;
 mov  dh,4      ;lopcount                               ;
@@high_freq_flag_lop:    ;loop 4 times ...              ; apply 4 values
 xor  eax,eax                             ;\            ;
 shl  dl,1      ;flags                    ; flag        ;
 jnc  short @@high_freq_flag_this         ;/            ;
 IF RUN_LENGTH                                          ;
   @@get_runlength quads                                ;
   mov  eax,dword ptr [@@rle_val]                       ;
 ELSE                                                   ;
   moz  eax,word ptr [mp3_exponents+edi*2]              ;
 ENDIF                                                  ;
 mov  eax,dword ptr [mp3_exp_table+eax*4] ;\            ;
 mp3mac_get_bit_to_cy                     ; xlat and    ;
 jnc  short @@high_freq_flag_this         ; get sign    ;
 neg  eax                                 ;/            ;
@@high_freq_flag_this:                                  ;
 mov  dword ptr [ebx+$mp3gr_sb_hybrid+edi*4+0],eax      ;
 inc  edi                                               ;
 dec  dh        ;lopcount                               ;
 jnz  short @@high_freq_flag_lop                        ;/
 cmp  edi,572   ;aka 576-4              ;\loop while space for another 4 values
 jbe        @@high_freq_lop             ;/
@@high_freq_done:
@@high_freq_abort_lop:
;timelog_end rdtsc_huff_quads
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;timelog_start rdtsc_huff_pad
 IF WITHOUT_ZEROES
   mov  dword ptr [ebx+$mp3gr_num_nonzero_hybrids],edi
   ;note: there are usually 100..200 trailing zeroes.
   ;below zeropadding could be omitted (however, stereo
   ;antialias, imdct can round-up num_nonzero, so the
   ;entries would need to be zeropadded in that places)
 ENDIF
 push ecx                                       ;\
 mov  ecx,576   ;end                            ;
 sub  ecx,edi   ;remain = end-curr              ; zeropad remaining entries
 lea  edi,[ebx+$mp3gr_sb_hybrid+edi*4]          ; (can be 0 or 2 dwords, or more
 xor  eax,eax                                   ; if above loop was aborted)
 rep  stosd                                     ;
 pop  ecx                                       ;/
;timelog_end rdtsc_huff_pad
;- - -
 IF log_huffcodes                               ;\
   mp3mac_bitstream_get_position                ;
   sub  eax,dword ptr [ebx+$mp3gr_part2_3_end]  ; show difference between
   jz   short @@exact_match_no_padding          ; position and expected end
   mov  edx,offset txt_huff_padding             ;
   call wrstr_edx                               ;
   neg  eax                                     ;
   call wrhexeax                                ;
   call wrcrlf                                  ;
  @@exact_match_no_padding:                     ;
 ENDIF                                          ;/
 IFDEF @@last_pos
   mp3mac_bitstream_get_position                  ;\
   cmp  eax,dword ptr [ebx+$mp3gr_part2_3_end]    ;
   ja   short @@error   ;overrun                  ; check end,
  ;je   short @@without_extension_padding         ; skip any padding/extension
  ;mov  eax,dword ptr [ebx+$mp3gr_part2_3_end] ;\ ;     ;\XXX not really needed (next granule will jumpt to $mp3gr_part2_3_start anyways)
  ;mp3mac_bitstream_set_position               ;/ ;     ;/
  @@without_extension_padding:                    ;/
 ENDIF
;- - -
 timelog_end rdtsc_read_huffman
 clc    ;out: cy=0=okay
 ret
;---
@@error:
 timelog_end rdtsc_read_huffman
 stc    ;out: cy=1=error
 ret
;---
IF RUN_LENGTH
 IF FAST_SMALL
  @@next_runlength small
 ENDIF
 @@next_runlength full
 @@next_runlength quads
ENDIF
;---
IF COARSE_END
 align code_align
 @@lop_j_near_end:
  mp3mac_bitstream_get_position                 ;\check end
  cmp  eax,dword ptr [ebx+$mp3gr_part2_3_end]   ; XXX is that actually needed? (in clean files, the loop should end as specified in "region_size") (although, that "region_size" uses hardcoded boundaries, so some files may want to abort before reaching that boundaries)
  jb         @@lop_j_not_end                    ;
  jmp        @@low_freq_abort_lop_j             ;/
ENDIF
;------------------
;:----------------- Mp3 code maths stereo
;------------------
align code_align
mp3_compute_stereo:   ;in: ebx=granule(s)
;--- --- ---
 cmp  dword ptr [mp3_output_num_channels],2             ;\for 2-channel only
 jne  short @@no_stereo                                 ;/
;XXX better do below for JSTEREO only? (but above check is still needed for /mono switch)
 cmp  dword ptr [mp3_hdr_mode_ext],MODE_EXT_MS_STEREO   ;\only MS stereo (most common)
 je   short mp3_compute_ms_stereo                       ;/
 test dword ptr [mp3_hdr_mode_ext],MODE_EXT_I_STEREO    ;\intensity stereo (optonally with MS stereo)
 jnz        mp3_compute_i_stereo                        ;/
 ;else: neither
@@no_stereo:
 ret
;--- --- ---
mp3_compute_ms_stereo:
 ;ms_stereo is most commonly used
 ;NOTE: the 1/sqrt(2) normalization factor is included in the global gain
 @@ch0 equ (-$mp3gr_entrysiz*2)          ;granule for channel=0
 @@ch1 equ 0                             ;granule for channel=1
 timelog_start rdtsc_ms_stereo
 lea  edi,[ebx+$mp3gr_sb_hybrid+$mp3gr_entrysiz*2]   ;for ch1 (2nd channel)
 IF WITHOUT_ZEROES
   mov  ecx,dword ptr [ebx+$mp3gr_num_nonzero_hybrids]                     ;ch0
   mov  eax,dword ptr [ebx+$mp3gr_num_nonzero_hybrids+($mp3gr_entrysiz*2)] ;ch1
   cmp  ecx,eax
   ja   short @@this_len
   mov  ecx,eax
  @@this_len:
   jcxz short @@ms_stereo_done
   mov  dword ptr [ebx+$mp3gr_num_nonzero_hybrids],ecx                     ;ch0
   mov  dword ptr [ebx+$mp3gr_num_nonzero_hybrids+($mp3gr_entrysiz*2)],ecx ;ch1
 ELSE
   mov  ecx,576
 ENDIF
@@ms_stereo_lop:                 ;for i=0 to 576-1
        ;XXX could be unrolled... perhaps calculating another pair in esi,ebp
 mov  eax,dword ptr [edi+@@ch0]  ;tmp0 = granule.ch0.sb_hybrid[i]
 mov  edx,dword ptr [edi+@@ch1]  ;tmp1 = granule.ch1.sb_hybrid[i]
 sub  eax,edx                    ;tmp0 - tmp1
 lea  edx,[eax+edx*2]            ;tmp0 + tmp1
 mov  dword ptr [edi+@@ch0],edx  ;granule.ch0.sb_hybrid[i] = tmp0 + tmp1
 stos dword ptr [edi+@@ch1]      ;granule.ch1.sb_hybrid[i] = tmp0 - tmp1
 dec  ecx                     ;\on Pentium III, the function is twice as fast
 jnz  short @@ms_stereo_lop   ;/when using "dec/jnz" instead of "loop"
@@ms_stereo_done:
 timelog_end rdtsc_ms_stereo
 ret
;------------------
mp3_compute_i_stereo:    ;from lieff's mp3 decoder (because code in original minimp3 was totally bugged)
.data?
 align data_align
 @@max_bands    db ?,?,?,?  ;three bytes, plus padding
 @@max_blocks   dd ?
 @@max_pos      dd ?
 @@sfb_array    db 40 dup (?)
 @@is_tab       dd ?
 @@n_long_sfb   dd ?
 @@n_short_sfb  dd ?
 @@n_sfb        dd ?
.const
 @@const_3      dd 3    ;XXX hsould better avoid slow div/modulo
.code
 @@right        equ $mp3gr_entrysiz*2
;- - -
 timelog_start rdtsc_i_stereo
 IF WITHOUT_ZEROES
   ;XXX for now, just force everything to be "nonzero"...
   mov  dword ptr [ebx+$mp3gr_num_nonzero_hybrids],576                     ;ch0
   mov  dword ptr [ebx+$mp3gr_num_nonzero_hybrids+($mp3gr_entrysiz*2)],576 ;ch1
 ENDIF
 mov  eax,dword ptr [ebx+$mp3gr_long_end]       ;\
 mov  dword ptr [@@n_long_sfb],eax              ;/
 mov  eax,13   ;aka 39/3                        ;\
 sub  eax,dword ptr [ebx+$mp3gr_short_start]    ;
 lea  eax,[eax*2+eax]   ;mul3                   ;
 mov  dword ptr [@@n_short_sfb],eax         ;\  ;/
 add  eax,dword ptr [@@n_long_sfb]          ;/  ;\n_sfb = gr->n_long_sfb + gr->n_short_sfb;
 mov  dword ptr [@@n_sfb],eax                   ;/
 cmp  byte ptr [@@n_short_sfb],0        ;\
 mov  eax,1                             ;
 jz   short @@without_short             ;
 mov  eax,3                             ; max_blocks = gr->n_short_sfb ? 3 : 1;
@@without_short:                        ;
 mov  dword ptr [@@max_blocks],eax      ;/   <--- IMPORTANT
;- - -
 mov  edi,offset @@sfb_array                    ;-      ;-
 mov  eax,dword ptr [mp3_hdr_sample_rate_index] ;\      ;\
 imul eax,22                                    ; bstab ;
 lea  esi,[mp3_band_size_long+eax]              ;/      ;
 mov  ecx,dword ptr [@@n_long_sfb]                      ;
 rep  movsb                                             ;/
 mov  eax,dword ptr [mp3_hdr_sample_rate_index]         ;\
 imul eax,13                                            ;
 lea  esi,[mp3_band_size_short+eax]                     ; merge lieff-style
 mov  ecx,dword ptr [@@n_short_sfb]                     ;
 jcxz short @@make_sfb_done                             ; XXX doing that here is a bit slow, it would be better to pre-compute all merged-combinations
 add  esi,dword ptr [ebx+$mp3gr_short_start]            ;
@@make_sfb_lop:                                         ;
 lodsb                                                  ;
 stosb                                                  ;
 stosb                                                  ;
 stosb                                                  ;
 sub  ecx,3                                             ;
 jnz  short @@make_sfb_lop                              ;
@@make_sfb_done:                                        ;/
;- - -
 call @@find_top_bands  ;--->  L3_stereo_top_band(left + 576, gr->sfbtab, n_sfb, max_band);
;- - -
 cmp  byte ptr [@@n_long_sfb],0         ;\
 jz   short @@without_long              ;
 mov  eax,dword ptr [@@max_bands]   ;\  ;
 cmp  ah,al                         ;   ; if (gr->n_long_sfb)
 jg   short @@not_max1              ;   ;     max_band[0] = max_band[1] = max_band[2] = MINIMP3_MAX(MINIMP3_MAX(max_band[0], max_band[1]), max_band[2]);
 mov  ah,al                         ;   ;
@@not_max1:                         ;   ;
 shr  eax,8                         ;   ;
 cmp  ah,al                         ;   ;
 jg   short @@not_max2              ;   ;
 mov  ah,al                         ;   ;
@@not_max2:                         ;   ;
 mov  al,ah                         ;   ;
 shl  eax,8                         ;   ;
 mov  al,ah                         ;   ;
 mov  dword ptr [@@max_bands],eax   ;/  ;
@@without_long:                         ;/
;- - -
 xor  ebp,ebp  ;blk
@@adjust_last_prev_lop:
 mov  edx,dword ptr [@@n_sfb]           ;\
 sub  edx,dword ptr [@@max_blocks]      ; itop = n_sfb - max_blocks + blk
 add  edx,ebp ;blk                      ;/
 mov  ecx,edx                           ;\prev = itop - max_blocks;
 sub  ecx,dword ptr [@@max_blocks]      ;/
 mov  eax,dword ptr [mp3_hdr_flag_lsf]  ;\
 lea  eax,[eax+eax*2]  ;0,1 --> 0,3     ; default_pos = HDR_TEST_MPEG1(hdr) ? 3 : 0
 xor  al,3             ;0,3 --> 3,0     ;/
 cmp  cl,byte ptr [@@max_bands+ebp]     ;\
 jle  short @@use_default_pos           ; ist_pos[itop] = max_band[blk] >= prev ? default_pos : ist_pos[prev]
 mov  al,byte ptr [ebx+@@right+$mp3gr_scale_factors+ecx]         ;
@@use_default_pos:                      ;
 mov  byte ptr [ebx+@@right+$mp3gr_scale_factors+edx],al         ;/
 inc  ebp      ;blk
 cmp  ebp,dword ptr [@@max_blocks]
 jb   short @@adjust_last_prev_lop
;- - -
 call @@apply_i_stereo  ;---> L3_stereo_process(left, ist_pos, gr->sfbtab, hdr, max_band, gr[1].scalefac_compress & 1);
 timelog_end rdtsc_i_stereo
 ret
;--- --- --- ------
@@find_top_bands:
 mov  dword ptr [@@max_bands],00ffffffh  ;set maxband[0..2]=(-1)
 lea  esi,[ebx+@@right+$mp3gr_sb_hybrid]                ;\
 xor  edx,edx   ;iii                                    ;
@@find_top_lop_iii:  ;for (i = 0; i < nbands; i++)      ;
 xor  ecx,ecx   ;kkk                                    ; ;\
@@find_top_lop_kkk:  ;for (k = 0; k < sfb[i]; k += 2)   ; ;
 mov  eax,dword ptr [esi+ecx*4+0]                       ; ;
 or   eax,dword ptr [esi+ecx*4+4]                       ; ;
 jnz  short @@found_nonzero                             ; ;
 add  ecx,2     ;kkk                                    ; ;
 cmp  cl,byte ptr [@@sfb_array+edx]                     ; ;
 jb   short @@find_top_lop_kkk                          ; ;/
 jmp  short @@find_top_next                             ;
;---                                                    ;
@@found_nonzero:                                        ;
 mov  eax,edx                                           ; ;\
 div  byte ptr [@@const_3]                              ; ; apply
 moz  eax,ah    ;remainder (mod 3)                      ; ; max_band[i % 3] = i
 mov  byte ptr [@@max_bands+eax],dl  ;max_bands[0..2]=i ; ;/
@@find_top_next:                                        ;
 moz  eax,byte ptr [@@sfb_array+edx]                    ; ;\
 lea  esi,[esi+eax*4]                                   ; ;
 inc  edx                                               ; ; next
 cmp  edx,dword ptr [@@n_sfb]                           ; ;
 jb   short @@find_top_lop_iii                          ;/;/
 ret
;--- --- --- ------
@@apply_i_stereo:
 mov  eax,offset mp3_is_table_normal            ;\      ;\
 mov  ecx,7                                     ;/      ;
 cmp  dword ptr [mp3_hdr_flag_lsf],0            ;\      ;
 jz   short @@this_lsf                          ;/      ;
 mov  eax,dword ptr [ebx+@@right+$mp3gr_scalefac_compress]
 and  eax,1     ;bit0                                   ;
 test dword ptr [mp3_hdr_mode_ext],MODE_EXT_MS_STEREO ;\;
 jz   short @@no_ms                                   ; ;
 or   eax,2     ;bit1=mul_1.414  (eg. l3-test46.bit)  ; ;
@@no_ms:                                              ;/;
 shl  eax,9     ;N*40h*2*4                              ;
 add  eax,offset mp3_is_table_lsf                       ;
 mov  ecx,64    ;max (must be below NO_INTENSITY_FLAG)  ;
@@this_lsf:                                             ;
 mov  dword ptr [@@max_pos],ecx  ;7 or 64               ;
 mov  dword ptr [@@is_tab],eax   ;table                 ;/
;- - -
 lea  esi,[ebx+$mp3gr_sb_hybrid]
 xor  ecx,ecx   ;iii                    ;\for (i = 0; sfb[i]; i++)
@@apply_lop_i:                          ;/
 moz  ebp,byte ptr [@@sfb_array+ecx]                    ;-
 mov  eax,ecx                                           ;\    if ((int)i > max_band[i % 3] && ipos < max_pos)
 div  byte ptr [@@const_3]                              ; check
 moz  eax,ah    ;remainder (mod 3)                      ; max_band[i % 3]
 cmp  cl,byte ptr [@@max_bands+eax] ;iii,max_bands[0..2];
 jle  short @@apply_ms_stereo                           ;/
 moz  edi,byte ptr [ebx+@@right+$mp3gr_scale_factors+ecx] ;\
 cmp  edi,dword ptr [@@max_pos]                           ; check ipos
 jae  short @@apply_ms_stereo                             ;/

 shl  edi,3     ;mul 2*4
 add  edi,dword ptr [@@is_tab]

@@apply_pan_lop:                                                        ;\
 mov  eax,dword ptr [esi]          ;tmp  = granule.ch0.sb_hybrid    ;\  ;
 shl  eax,2                                                         ;   ;
 imul dword ptr [edi+1*4]  ;v1                                      ;   ;
 mov  dword ptr [esi+@@right],edx  ;granule.ch1.sb_hybrid = tmp*v1  ;/  ;
 mov  eax,dword ptr [esi]          ;tmp  = granule.ch0.sb_hybrid    ;\  ;
 shl  eax,2                                                         ;   ;
 imul dword ptr [edi+0*4]  ;v0                                      ;   ;
 mov  dword ptr [esi],edx          ;granule.ch0.sb_hybrid = tmp*v0  ;/  ; <-- write this last (ir destroys the incoming "tmp" value)
 add  esi,4                                                             ;
 dec  ebp                                                               ;
 jnz  short @@apply_pan_lop                                             ;/

 jmp  short @@apply_next
;---
@@apply_ms_stereo:
 test dword ptr [mp3_hdr_mode_ext],MODE_EXT_MS_STEREO   ;\
 jz   short @@apply_none                                ;/
@@ms_stereo_lop:                                                          ;\
        ;XXX could be unrolled... perhaps calculating another pair in esi,ebp
 mov  eax,dword ptr [esi]         ;tmp0 = granule.ch0.sb_hybrid[i]        ;
 mov  edx,dword ptr [esi+@@right] ;tmp1 = granule.ch1.sb_hybrid[i]        ;
 sub  eax,edx                     ;tmp0 - tmp1                            ;
 lea  edx,[eax+edx*2]             ;tmp0 + tmp1                            ;
 mov  dword ptr [esi],edx         ;granule.ch0.sb_hybrid[i] = tmp0 + tmp1 ;
 mov  dword ptr [esi+@@right],eax ;granule.ch1.sb_hybrid[i] = tmp0 - tmp1 ;
 add  esi,4                                                               ;
 dec  ebp                     ;\on Pentium III, the function is twice as fast
 jnz  short @@ms_stereo_lop   ;/when using "dec/jnz" instead of "loop"    ;/

 jmp  short @@apply_next
;---
@@apply_none:
 lea  esi,[esi+ebp*4]   ;skip, keep unchanged
@@apply_next:
 inc  ecx       ;iii                                    ;\
 cmp  ecx,dword ptr [@@n_sfb]                           ; next
 jb         @@apply_lop_i                               ;/
 ret
;------------------
;:----------------- Mp3 code maths reorder/antialias
;------------------
align code_align
mp3_reorder_block:   ;in: ebx=granule
 ;reorder could be slow, but it happens only once and then (every some blocks),
 ;and so, doesn't take up much cpu load
 ;- - -
 timelog_start rdtsc_reorder
 cmp  byte ptr [ebx+$mp3gr_block_type],2                ;\only for type 2
 jne  short @@no_reorder                                ;/
 lea  esi,[ebx+$mp3gr_sb_hybrid]             ;ptr+0     ;\
 cmp  byte ptr [ebx+$mp3gr_switch_point],0              ;
 jz   short @@this_src                                  ; src
 add  esi,36*4                               ;ptr+36*4  ;
 cmp  dword ptr [mp3_hdr_sample_rate_index],8           ;
 jne  short @@this_src                                  ;
 add  esi,12*4  ;additionally to above 36*4  ;ptr+48*4  ;
@@this_src:                                             ;/
;- - -
 mov  edx,dword ptr [ebx+$mp3gr_short_start]  ;can be 13        ;\
 cmp  edx,13                                                    ;
 jae  short @@no_reorder                                        ;
 IF WITHOUT_ZEROES
   ;XXX for now, just force everything to be "nonzero"...
   mov  dword ptr [ebx+$mp3gr_num_nonzero_hybrids],576
 ENDIF
@@outer_lop:                                                    ;
 mov  eax,dword ptr [mp3_hdr_sample_rate_index]                 ;
 imul eax,13                                  ;X*13             ;
 movzx ecx,byte ptr [mp3_band_size_short+eax+edx] ;[X*13+Y]     ;
 mov  edi,offset @@tmp                                          ;/
 pusha                                  ;\
 mov  edx,ecx   ;step=len (4..44)       ; copy LEN*3 dwords to tmp
@@inner_lop:                            ;
 mov  eax,dword ptr [esi+0]             ; ;\
 stosd                                  ; ;
 mov  eax,dword ptr [esi+edx*4*1]       ; ; copy 3 dwords
 stosd                                  ; ;
 mov  eax,dword ptr [esi+edx*4*2]       ; ;
 stosd                                  ; ;
 add  esi,4                             ; ;/
 loop short @@inner_lop                 ;
 popa                                   ;/
 lea  ecx,[ecx*2+ecx]    ;len*3         ;\
 xchg esi,edi                           ; copy LEN*3 dwords back from tmp
 rep  movsd                             ;
 xchg esi,edi                           ;/
 inc  edx                                               ;\
 cmp  edx,13                                            ; next
 jb   short @@outer_lop                                 ;/
@@no_reorder:
 timelog_end rdtsc_reorder
 ret
;---
.data?
 align data_align
 @@tmp dd 576 dup (?)   ;XXX max 44*3 dwords
.code
;------------------
align code_align
         nop             ;\XXX somehow faster?
         align 4         ;/
mp3_compute_antialias:    ;in: ebx=granule
 timelog_start rdtsc_antialias
 IF WITHOUT_ZEROES
   mov  eax,dword ptr [ebx+$mp3gr_num_nonzero_hybrids]          ;\
   add  eax,9-1                 ;0..576+8                       ;
   xor  edx,edx                                                 ; len
   mov  ecx,9                                                   ; excluding
   div  ecx         ;(num/9)    ;0..64                          ; zeropadding
   mov  dword ptr [ebx+$mp3gr_num_nonzero_hybrids_div9],eax     ;
   shr  eax,1       ;(num/18)   ;0..32                          ;
   jz         @@no_antialias    ;0     (when num/9 = 0..1)      ;
   mov  ecx,eax                 ;1..32                          ;
   shr  eax,5                   ;0..1                           ;
   sub  ecx,eax                 ;1..31                          ;/
 ELSE
   mov  ecx,SBLIMIT-1           ;31   ;len (default)            ;-len
 ENDIF
 cmp  byte ptr [ebx+$mp3gr_block_type],2        ;\
 jne  short @@this_len                          ; antialias only "long" bands
 cmp  byte ptr [ebx+$mp3gr_switch_point],0      ;
 jz         @@no_antialias                      ;
 mov  ecx,1    ;XXX: check this for 8000Hz case ;
@@this_len:                                     ;/
 IF WITHOUT_ZEROES
   lea  eax,[ecx*2+1]                                        ;\
   cmp  dword ptr [ebx+$mp3gr_num_nonzero_hybrids_div9],eax  ; opdate highest
   ja   short @@is_bigger                                    ; (nonzero required
   mov  dword ptr [ebx+$mp3gr_num_nonzero_hybrids_div9],eax  ; for l3-si_huff.bit)
  @@is_bigger:                                               ;/
 ENDIF
 push ebx
 lea  ebx,[ebx+$mp3gr_sb_hybrid]
;- - -
@@lop:                            ;XXX could quickskip fully zero-padded regions
 add  ebx,18*4
 IRP nn,0,1,2,3,4,5,6,7   ;INT_AA(nn=0..7)
   mov  esi,dword ptr [ebx-(nn+1)*4]               ;-tmp0 = ptr[-nn-1]
   mov  edi,dword ptr [ebx+(nn)*4]                 ;-tmp1 = ptr[+nn]
   IF WITHOUT_ZEROES EQ 0  ;only if NOT already    ;\
     mov  eax,esi                                  ; quickskip when zero
     or   eax,edi                                  ; (only good if zeropadding
     jz   short @@zero_&nn                         ; wasn't already omitted)
   ENDIF                                           ;/
   shl  esi,2
   shl  edi,2
   lea  eax,[esi+edi]                              ;-tmp2 = tmp0+tmp1
   mov  ebp,mp3_csa_&nn&_cs                        ;\
   imul ebp                                        ; tmp2 = (tmp2*csa[0])
   mov  ebp,edx                                    ;/
   mov  eax,mp3_csa_&nn&_ca-mp3_csa_&nn&_cs        ;\
   imul esi                                        ; tmp0 = (tmp2+(tmp0*csa[3]))
   add  edx,ebp                                    ;
   mov  dword ptr [ebx+(nn)*4],edx                 ;/
   mov  eax,mp3_csa_&nn&_ca+mp3_csa_&nn&_cs        ;\
   imul edi                                        ; tmp1 = (tmp2-(tmp1*csa[2]))
   sub  ebp,edx                                    ;
   mov  dword ptr [ebx-(nn+1)*4],ebp               ;/
  @@zero_&nn:
 ENDM
 dec  ecx
 jnz        @@lop
 pop  ebx
@@no_antialias:
 timelog_end rdtsc_antialias
 ret
;------------------
;:----------------- Mp3 code maths imdct
;------------------
mp3_SUM macro dst,val1,op2,val2,op3,val3
  IF (.TYPE dst) AND 10h
    IFDIFI <dst>,<val1>
      mov  dst,val1       ;get val1 (from register)
      ;XXX if type(s) = registers and op(s) = add --> use lea dst,[x+y+z]
    ENDIF
    IFDIFI <op2>,<->
      op2  dst,val2       ;add/sub val2
    ENDIF
    IFDIFI <op3>,<->
      op3  dst,val3       ;add/sub val3
    ENDIF
  ELSE
    mov  eax,val1         ;get val1 (from memory to eax)
    IFDIFI <op2>,<->
      op2  eax,val2       ;add/sub val2
    ENDIF
    IFDIFI <op3>,<->
      op3  eax,val3       ;add/sub val3
    ENDIF
    mov  dst,eax
  ENDIF
endm
;---
mp3_MULH macro dst,val1,op2,val2,op3,val3,shift,fac,postadd
  mp3_SUM eax,val1,op2,val2,op3,val3     ;get to eax
  IF shift              ;\
    shl  eax,shift      ; shift
  ENDIF                 ;/
  IF (.TYPE fac) AND 10h;\
    imul fac            ;
  ELSE                  ; mul fac
    mov  edx,fac        ;        ;\could multiply directly (unless "fac" is an immediate) (and unless "fac" lacks a type definition like "dword ptr")
    imul edx            ;        ;/
  ENDIF                 ;/
  IFDIFI <postadd>,<->
    add  edx,postadd
  ENDIF
  IFDIFI <dst>,<edx>
    mov  dst,edx
  ENDIF
endm
;------------------
align code_align
mp3_imdct36:
 ;in: esi=src (sb_hybrid)
 ;in: edi=dst (sb_samples)
 ;in: ebx=buf (mdct_buf)
 ;in: ebp=win (mdct_win)
;- - -
;XXX various things could be optimized...
;- - -
 @@SUM  equ mp3_SUM
 @@MULH equ mp3_MULH
;- - -
 IF 01
   mov  eax,[esi+0*4]
  ;mov  [esi+0*4],eax      ;<-- only needed when dst<>esi
   IRP i,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17
     IF i AND 1
       mov  edx,[esi+i*4]    ;val[i]
       add  eax,edx          ;add val[i-1]
       IF i GT 1
         add  ecx,eax        ;add val[i-2]
         mov  [esi+(i)*4],ecx
       ELSE
         mov  [esi+(i)*4],eax
       ENDIF
       mov  ecx,eax          ;memorize as val[i-2]
     ELSE
       mov  eax,[esi+i*4]    ;val[i]
       add  edx,eax          ;add val[i-1]
       mov  [esi+(i)*4],edx
     ENDIF
   ENDM
 ELSE    ;same as above, but backwards, with RMW opcodes...
   IRP i,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1        ;\
    mov  eax,[esi+(i-1)*4]                                ; for i=17 downto 1 step -1,
    add  [esi+(i)*4],eax                                  ;  src[i]=src[i]+src[i-1];
   ENDM                                                   ;/
   IRP i,17,15,13,11,9,7,5,3                              ;\
    mov  eax,[esi+(i-2)*4]                                ; for i=17 downto 3 step -2,
    add  [esi+(i)*4],eax                                  ;  src[i]=src[i]+src[i-2];
   ENDM                                                   ;/
 ENDIF
 ;XXX would it be faster to write above to a small @@tmp buffer?
 ;    (so the whole stuff doesn't need to be drained from cache back to RAM)
 ;    (though that may or may not happen anyways, depending on how the cache works)
;- - -

IF 1    ;optimized for register usage (albeit looks messy)

 .data?
  align data_align
  @@s0   dd ?
  @@s2   dd ?
  @@s3   dd ?
  @@tmp  dd 18 dup (?)
  @@t0   equ ebx
  @@t1   equ ecx
  @@t2   equ edi
  @@t3   equ ebp
 .code
 ;- - -
 push ebx
 push ebp         ;XXX below could be more optimized with OPCODES instead MACROS
 push edi
 IRP j,0,1
  mov    @@t1            ,[esi+(0*2+j)*4]                                                    ;t1        = src[0*2+j]
  mov    @@t0            ,[esi+(6*2+j)*4]                                                    ;t0        = src[6*2+j]
  @@SUM  @@t2            ,[esi+(4*2+j)*4],add,[esi+(8*2+j)*4],sub,[esi+(2*2+j)*4]            ;t2        = src[4*2+j] +  src[8*2+j] - src[2*2+j]
  lea    @@t3            ,[@@t1*2+@@t0]                                                      ;t3        = src[0*2+j]*2 + (src[6*2+j])
  sar    @@t3,1                                                                              ;t3        = src[0*2+j] + (src[6*2+j]/2)
  sub    @@t1            ,@@t0                                                               ;t1        = src[0*2+j] -  src[6*2+j]
  @@SUM  [@@tmp+(16+j)*4],@@t1,add,@@t2,-,-                                                  ;tmp[16+j] = t1 + t2
  sar    @@t2,1                                                                              ;t2        = t2/2
  @@SUM  [@@tmp+(6+j)*4] ,@@t1,sub,@@t2,-,-                                                  ;tmp[ 6+j] = t1 - t2
  IF 0;1        ;XXX this isn't really faster (or even SLOWER?)
    mov    @@t1,[esi+(4*2+j)*4]
    mov    @@t2,[esi+(2*2+j)*4]
    lea    eax ,[@@t1+@@t2]
    mov    @@t0,[esi+(8*2+j)*4]
    @@MULH @@t0            ,eax            ,-  ,-              ,-  ,-              ,1,   C2,-  ;t0        = MULH(2*(src[2*2+j] + src[4*2+j]),   C2)
    @@MULH @@t1            ,@@t1           ,sub,@@t0           ,-  ,-              ,0,negC8,-  ;t1        = MULH(   src[4*2+j] - src[8*2+j] ,negC8)
    lea    eax             ,[@@t2+@@t0]
    @@MULH edx             ,eax            ,-  ,-              ,-  ,-              ,1,negC4,-  ;t2        = MULH(2*(src[2*2+j] + src[8*2+j]),negC4)
    @@SUM  [@@tmp+(2+j)*4] ,@@t3,add,@@t0,add,@@t1                                             ;tmp[ 2+j] = t3 + t0 + t1
    @@SUM  [@@tmp+(10+j)*4],@@t3,sub,@@t0,sub,edx                                              ;tmp[10+j] = t3 - t0 - t2
    @@SUM  [@@tmp+(14+j)*4],@@t3,add,edx,sub,@@t1                                              ;tmp[14+j] = t3 + t2 - t1
    mov    @@t0            ,[esi+(7*2+j)*4]
    mov    @@t1            ,[esi+(1*2+j)*4]
    mov    @@t3            ,[esi+(5*2+j)*4]
    lea    eax             ,[@@t3+@@t0]
    @@MULH [@@tmp+(4+j)*4] ,eax            ,sub,@@t1           ,-  ,-              ,1,negC3,-  ;tmp[ 4+j] = MULH(2*(src[5*2+j] + src[7*2+j] - src[1*2+j]),negC3)
    lea    eax             ,[@@t1+@@t3]
    @@MULH @@t2            ,eax            ,-  ,-              ,-  ,-              ,1,   C1,-  ;t2        = MULH(2*(src[1*2+j] + src[5*2+j])             ,   C1)
    @@MULH @@t3            ,@@t3           ,sub,@@t0           ,-  ,-              ,0,negC7,-  ;t3        = MULH(   src[5*2+j] - src[7*2+j]              ,negC7)
    lea    eax             ,[@@t1+@@t0]
    @@MULH @@t1            ,eax            ,-  ,-              ,-  ,-              ,1,negC5,-  ;t1        = MULH(2*(src[1*2+j] + src[7*2+j])             ,negC5)
    @@MULH edx             ,[esi+(3*2+j)*4],-  ,-              ,-  ,-              ,1,   C3,-  ;t0        = MULH(2* src[3*2+j]                           ,   C3)
  ELSE
    @@MULH @@t0            ,[esi+(2*2+j)*4],add,[esi+(4*2+j)*4],-  ,-              ,1,   C2,-  ;t0        = MULH(2*(src[2*2+j] + src[4*2+j]),   C2)
    @@MULH @@t1            ,[esi+(4*2+j)*4],sub,[esi+(8*2+j)*4],-  ,-              ,0,negC8,-  ;t1        = MULH(   src[4*2+j] - src[8*2+j] ,negC8)
    @@MULH edx             ,[esi+(2*2+j)*4],add,[esi+(8*2+j)*4],-  ,-              ,1,negC4,-  ;t2        = MULH(2*(src[2*2+j] + src[8*2+j]),negC4)
    @@SUM  [@@tmp+(2+j)*4] ,@@t3,add,@@t0,add,@@t1                                             ;tmp[ 2+j] = t3 + t0 + t1
    @@SUM  [@@tmp+(10+j)*4],@@t3,sub,@@t0,sub,edx                                              ;tmp[10+j] = t3 - t0 - t2
    @@SUM  [@@tmp+(14+j)*4],@@t3,add,edx,sub,@@t1                                              ;tmp[14+j] = t3 + t2 - t1
    @@MULH [@@tmp+(4+j)*4] ,[esi+(5*2+j)*4],add,[esi+(7*2+j)*4],sub,[esi+(1*2+j)*4],1,negC3,-  ;tmp[ 4+j] = MULH(2*(src[5*2+j] + src[7*2+j] - src[1*2+j]),negC3)
    @@MULH @@t2            ,[esi+(1*2+j)*4],add,[esi+(5*2+j)*4],-  ,-              ,1,   C1,-  ;t2        = MULH(2*(src[1*2+j] + src[5*2+j])             ,   C1)
    @@MULH @@t3            ,[esi+(5*2+j)*4],sub,[esi+(7*2+j)*4],-  ,-              ,0,negC7,-  ;t3        = MULH(   src[5*2+j] - src[7*2+j]              ,negC7)
    @@MULH @@t1            ,[esi+(1*2+j)*4],add,[esi+(7*2+j)*4],-  ,-              ,1,negC5,-  ;t1        = MULH(2*(src[1*2+j] + src[7*2+j])             ,negC5)
    @@MULH edx             ,[esi+(3*2+j)*4],-  ,-              ,-  ,-              ,1,   C3,-  ;t0        = MULH(2* src[3*2+j]                           ,   C3)
  ENDIF
  @@SUM  [@@tmp+(0+j)*4] ,@@t3,add,@@t2,add,edx                                              ;tmp[ 0+j] = t3 + t2 + t0
  @@SUM  [@@tmp+(8+j)*4] ,@@t3,sub,@@t1,sub,edx                                              ;tmp[ 8+j] = t3 - t1 - t0
  @@SUM  [@@tmp+(12+j)*4],@@t2,add,@@t1,sub,edx                                              ;tmp[12+j] = t2 + t1 - t0
 ENDM
 pop  edi
 pop  ebp
 pop  ebx
;- - -
 push esi
 IRP j,0,1,2,3
  mov    edx                   ,[@@tmp+(j*4+0)*4]                                            ;t0                   = tmp[j*4]
  mov    esi                   ,[@@tmp+(j*4+1)*4]                                            ;t1                   = tmp[j*4+1]
  mov    eax                   ,[@@tmp+(j*4+2)*4]                                            ;t2                   = tmp[j*4+2]
  mov    ecx                   ,[@@tmp+(j*4+3)*4]                                            ;t3                   = tmp[j*4+3]
  sub    eax,edx                                                                             ;s2                   = t2 - t0
  lea    edx,[eax+edx*2]                                                                     ;s0                   = t2 + t0
  mov    @@s2                  ,eax                                                          ;s2                   = s2
  mov    @@s0                  ,edx                                                          ;s0                   = s0
  sub    ecx,esi                                                                             ;s3                   = t3 - t1
  lea    eax,[ecx+esi*2]                                                                     ;s1                   = t3 + t1
  @@MULH esi                   ,eax ,-,-,-,-,1                 ,icos36h_&j      ,-           ;s1                   = MULH(s1*2, icos36h[j] )
  @@MULH @@s3                  ,ecx ,-,-,-,-,shift_for_8minus&j,icos36h_8minus&j,-           ;s3                   = MULL(s3,   icos36[8-j])  ;<-- "MULL" with "icos36"
  mov    ecx                   ,@@s0                                                         ;s0                   = s0
  sub    ecx,esi                                                                             ;t0                   = s0 - s1
  lea    esi,[ecx+esi*2]                                                                     ;t1                   = s0 + s1
  @@MULH [edi+(9+j)*SBLIMIT*4] ,[ebp+(9+j)*4]    ,-,-,-,-,0,ecx ,[ebx+(9+j)*4]               ;out[(9+j)*SBLIMIT]   = MULH(t0, win[9+j]     ) + buf[9+j]
  @@MULH [edi+(8-j)*SBLIMIT*4] ,[ebp+(8-j)*4]    ,-,-,-,-,0,ecx ,[ebx+(8-j)*4]               ;out[(8-j)*SBLIMIT]   = MULH(t0, win[8-j]     ) + buf[8-j]
  @@MULH [ebx+(9+j)*4]         ,[ebp+(9+j+18)*4] ,-,-,-,-,0,esi ,-                           ;buf[ 9+j]            = MULH(t1, win[9+j+18]  )
  @@MULH [ebx+(8-j)*4]         ,[ebp+(8-j+18)*4] ,-,-,-,-,0,esi ,-                           ;buf[ 8-j]            = MULH(t1, win[8-j+18]  )
  mov    ecx                   ,@@s2                                                         ;s2                   = s2
  mov    esi                   ,@@s3                                                         ;s3                   = s3
  sub    ecx,esi                                                                             ;t2                   = s2 - s3
  lea    esi,[ecx+esi*2]                                                                     ;t3                   = s2 + s3
  @@MULH [edi+(0+j)*SBLIMIT*4] ,[ebp+(0+j)*4]    ,-,-,-,-,0,ecx ,[ebx+(0+j)*4]               ;out[(0  +j)*SBLIMIT] = MULH(t2, win[0  +j]   ) + buf[0  +j]
  @@MULH [edi+(17-j)*SBLIMIT*4],[ebp+(17-j)*4]   ,-,-,-,-,0,ecx ,[ebx+(17-j)*4]              ;out[(9+8-j)*SBLIMIT] = MULH(t2, win[9+8-j]   ) + buf[9+8-j]
  @@MULH [ebx+(0+j)*4]         ,[ebp+(0+j+18)*4] ,-,-,-,-,0,esi ,-                           ;buf[ 0  +j]          = MULH(t3, win[0  +j+18])
  @@MULH [ebx+(17-j)*4]        ,[ebp+(17-j+18)*4],-,-,-,-,0,esi ,-                           ;buf[ 9+8-j]          = MULH(t3, win[9+8-j+18])
 ENDM
;- - -
 IRP j,4
  mov    ecx                   ,[@@tmp+(j*4+0)*4]                                            ;s0                       = tmp[16]
  mov    eax                   ,[@@tmp+(j*4+1)*4]                                            ;s1                       = tmp[17]
  @@MULH edx                   ,eax ,-,-,-,-,1,   icos36h_&j,-                               ;s1                       = MULH(s1*2, icos36h_4)
  sub    ecx,edx                                                                             ;t0                       = s0 - s1
  lea    esi,[ecx+edx*2]                                                                     ;t1                       = s0 + s1
  @@MULH [edi+(9+j)*SBLIMIT*4] ,[ebp+(9+j)*4]    ,-,-,-,-,0,ecx ,[ebx+(9+j)*4]               ;out[(9+4)*SBLIMIT]       = MULH(t0, win[9+4]     ) + buf[9+4]
  @@MULH [edi+(8-j)*SBLIMIT*4] ,[ebp+(8-j)*4]    ,-,-,-,-,0,ecx ,[ebx+(8-j)*4]               ;out[(8-4)*SBLIMIT]       = MULH(t0, win[8-4]     ) + buf[8-4]
  @@MULH [ebx+(9+j)*4]         ,[ebp+(9+j+18)*4] ,-,-,-,-,0,esi ,-                           ;buf[ 9+4]                = MULH(t1, win[9+4+18]  )
  @@MULH [ebx+(8-j)*4]         ,[ebp+(8-j+18)*4] ,-,-,-,-,0,esi ,-                           ;buf[ 8-4]                = MULH(t1, win[8-4+18]  )
 ENDM
 pop  esi

ELSE    ;less messy, but slower (this would work neatly on ARM, when having more spare CPU rgisters for @@t0..3 / @@s0..3

 .data?
  align data_align
  @@s0   dd ?
  @@s1   dd ?
  @@s2   dd ?
  @@s3   dd ?
  @@t0   dd ?
  @@t1   dd ?
  @@t2   dd ?
  @@t3   dd ?
  @@tmp  dd 18 dup (?)
 .code
 ;- - -
 IRP j,0,1
  @@SUM  @@t2            ,[esi+(4*2+j)*4],add,[esi+(8*2+j)*4],sub,[esi+(2*2+j)*4]            ;t2        = src[4*2+j] +  src[8*2+j] - src[2*2+j]
  @@SUM  @@t0            ,[esi+(6*2+j)*4],-,-,-,-                                            ;t0        = src[6*2+j]
  sar    @@t0,1                                                                              ;t0        = src[6*2+j]/2
  @@SUM  @@t3            ,[esi+(0*2+j)*4],add,@@t0,-,-                                       ;t3        = src[0*2+j] + (src[6*2+j]/2)
  @@SUM  @@t1            ,[esi+(0*2+j)*4],sub,[esi+(6*2+j)*4],-,-                            ;t1        = src[0*2+j] -  src[6*2+j]
  @@SUM  [@@tmp+(16+j)*4],@@t1,add,@@t2,-,-                                                  ;tmp[16+j] = t1 + t2
  sar    @@t2,1                                                                              ;t2        = t2/2
  @@SUM  [@@tmp+(6+j)*4] ,@@t1,sub,@@t2,-,-                                                  ;tmp[ 6+j] = t1 - t2
  @@MULH @@t0            ,[esi+(2*2+j)*4],add,[esi+(4*2+j)*4],-  ,-              ,1,   C2,-  ;t0        = MULH(2*(src[2*2+j] + src[4*2+j]),   C2)
  @@MULH @@t1            ,[esi+(4*2+j)*4],sub,[esi+(8*2+j)*4],-  ,-              ,0,negC8,-  ;t1        = MULH(   src[4*2+j] - src[8*2+j] ,negC8)
  @@MULH @@t2            ,[esi+(2*2+j)*4],add,[esi+(8*2+j)*4],-  ,-              ,1,negC4,-  ;t2        = MULH(2*(src[2*2+j] + src[8*2+j]),negC4)
  @@SUM  [@@tmp+(2+j)*4] ,@@t3,add,@@t0,add,@@t1                                             ;tmp[ 2+j] = t3 + t0 + t1
  @@SUM  [@@tmp+(10+j)*4],@@t3,sub,@@t0,sub,@@t2                                             ;tmp[10+j] = t3 - t0 - t2
  @@SUM  [@@tmp+(14+j)*4],@@t3,add,@@t2,sub,@@t1                                             ;tmp[14+j] = t3 + t2 - t1
  @@MULH [@@tmp+(4+j)*4] ,[esi+(5*2+j)*4],add,[esi+(7*2+j)*4],sub,[esi+(1*2+j)*4],1,negC3,-  ;tmp[ 4+j] = MULH(2*(src[5*2+j] + src[7*2+j] - src[1*2+j]),negC3)
  @@MULH @@t2            ,[esi+(1*2+j)*4],add,[esi+(5*2+j)*4],-  ,-              ,1,   C1,-  ;t2        = MULH(2*(src[1*2+j] + src[5*2+j])             ,   C1)
  @@MULH @@t3            ,[esi+(5*2+j)*4],sub,[esi+(7*2+j)*4],-  ,-              ,0,negC7,-  ;t3        = MULH(   src[5*2+j] - src[7*2+j]              ,negC7)
  @@MULH @@t0            ,[esi+(3*2+j)*4],-  ,-              ,-  ,-              ,1,   C3,-  ;t0        = MULH(2* src[3*2+j]                           ,   C3)
  @@MULH @@t1            ,[esi+(1*2+j)*4],add,[esi+(7*2+j)*4],-  ,-              ,1,negC5,-  ;t1        = MULH(2*(src[1*2+j] + src[7*2+j])             ,negC5)
  @@SUM  [@@tmp+(0+j)*4] ,@@t3,add,@@t2,add,@@t0                                             ;tmp[ 0+j] = t3 + t2 + t0
  @@SUM  [@@tmp+(8+j)*4] ,@@t3,sub,@@t1,sub,@@t0                                             ;tmp[ 8+j] = t3 - t1 - t0
  @@SUM  [@@tmp+(12+j)*4],@@t2,add,@@t1,sub,@@t0                                             ;tmp[12+j] = t2 + t1 - t0
 ENDM
;- - -
 IRP j,0,1,2,3
  @@SUM  @@t0                  ,[@@tmp+(j*4+0)*4],-,-,-,-                                    ;t0                   = tmp[j*4]
  @@SUM  @@t1                  ,[@@tmp+(j*4+1)*4],-,-,-,-                                    ;t1                   = tmp[j*4+1]
  @@SUM  @@t2                  ,[@@tmp+(j*4+2)*4],-,-,-,-                                    ;t2                   = tmp[j*4+2]
  @@SUM  @@t3                  ,[@@tmp+(j*4+3)*4],-,-,-,-                                    ;t3                   = tmp[j*4+3]
  @@SUM  @@s2                  ,@@t2,sub,@@t0,-,-                                            ;s2                   = t2 - t0
  @@SUM  @@s0                  ,@@t2,add,@@t0,-,-                                            ;s0                   = t2 + t0
  @@SUM  @@s3                  ,@@t3,sub,@@t1,-,-                                            ;s3                   = t3 - t1
  @@SUM  @@s1                  ,@@t3,add,@@t1,-,-                                            ;s1                   = t3 + t1
  @@MULH @@s1                  ,@@s1,-,-,-,-,1                 ,icos36h_&j      ,-           ;s1                   = MULH(s1*2, icos36h[j] )
  @@MULH @@s3                  ,@@s3,-,-,-,-,shift_for_8minus&j,icos36h_8minus&j,-           ;s3                   = MULL(s3,   icos36[8-j])  ;<-- "MULL" with "icos36"
  @@SUM  @@t0                  ,@@s0,sub,@@s1,-,-                                            ;t0                   = s0 - s1
  @@SUM  @@t1                  ,@@s0,add,@@s1,-,-                                            ;t1                   = s0 + s1
  @@SUM  @@t2                  ,@@s2,sub,@@s3,-,-                                            ;t2                   = s2 - s3
  @@SUM  @@t3                  ,@@s2,add,@@s3,-,-                                            ;t3                   = s2 + s3
  @@MULH [edi+(9+j)*SBLIMIT*4] ,@@t0,-,-,-,-,0,[ebp+(9+j)*4]    ,[ebx+(9+j)*4]               ;out[(9+j)*SBLIMIT]   = MULH(t0, win[9+j]     ) + buf[9+j]
  @@MULH [edi+(8-j)*SBLIMIT*4] ,@@t0,-,-,-,-,0,[ebp+(8-j)*4]    ,[ebx+(8-j)*4]               ;out[(8-j)*SBLIMIT]   = MULH(t0, win[8-j]     ) + buf[8-j]
  @@MULH [ebx+(9+j)*4]         ,@@t1,-,-,-,-,0,[ebp+(9+j+18)*4] ,-                           ;buf[ 9+j]            = MULH(t1, win[9+j+18]  )
  @@MULH [ebx+(8-j)*4]         ,@@t1,-,-,-,-,0,[ebp+(8-j+18)*4] ,-                           ;buf[ 8-j]            = MULH(t1, win[8-j+18]  )
  @@MULH [edi+(0+j)*SBLIMIT*4] ,@@t2,-,-,-,-,0,[ebp+(0+j)*4]    ,[ebx+(0+j)*4]               ;out[(0  +j)*SBLIMIT] = MULH(t2, win[0  +j]   ) + buf[0  +j]
  @@MULH [edi+(17-j)*SBLIMIT*4],@@t2,-,-,-,-,0,[ebp+(17-j)*4]   ,[ebx+(17-j)*4]              ;out[(9+8-j)*SBLIMIT] = MULH(t2, win[9+8-j]   ) + buf[9+8-j]
  @@MULH [ebx+(0+j)*4]         ,@@t3,-,-,-,-,0,[ebp+(0+j+18)*4] ,-                           ;buf[ 0  +j]          = MULH(t3, win[0  +j+18])
  @@MULH [ebx+(17-j)*4]        ,@@t3,-,-,-,-,0,[ebp+(17-j+18)*4],-                           ;buf[ 9+8-j]          = MULH(t3, win[9+8-j+18])
 ENDM
;- - -
 IRP j,4
  @@SUM  @@s0                  ,[@@tmp+(j*4+0)*4],-,-,-,-                                    ;s0                       = tmp[16]
  @@SUM  @@s1                  ,[@@tmp+(j*4+1)*4],-,-,-,-                                    ;s1                       = tmp[17]
  @@MULH @@s1                  ,@@s1,-,-,-,-,1,   icos36h_&j,-                               ;s1                       = MULH(s1*2, icos36h_4)
  @@SUM  @@t0                  ,@@s0,sub,@@s1,-,-                                            ;t0                       = s0 - s1
  @@SUM  @@t1                  ,@@s0,add,@@s1,-,-                                            ;t1                       = s0 + s1
  @@MULH [edi+(9+j)*SBLIMIT*4] ,@@t0,-,-,-,-,0,[ebp+(9+j)*4]    ,[ebx+(9+j)*4]               ;out[(9+4)*SBLIMIT]       = MULH(t0, win[9+4]     ) + buf[9+4]
  @@MULH [edi+(8-j)*SBLIMIT*4] ,@@t0,-,-,-,-,0,[ebp+(8-j)*4]    ,[ebx+(8-j)*4]               ;out[(8-4)*SBLIMIT]       = MULH(t0, win[8-4]     ) + buf[8-4]
  @@MULH [ebx+(9+j)*4]         ,@@t1,-,-,-,-,0,[ebp+(9+j+18)*4] ,-                           ;buf[ 9+4]                = MULH(t1, win[9+4+18]  )
  @@MULH [ebx+(8-j)*4]         ,@@t1,-,-,-,-,0,[ebp+(8-j+18)*4] ,-                           ;buf[ 8-4]                = MULH(t1, win[8-4+18]  )
 ENDM

ENDIF

 ret
;------------------
align code_align
mp3_imdct12:    ;in: esi=src - out: [out2_...]
 ;XXX this could be optimized:
 ;    1) data is written to a temp buffer (out2)
 ;       that's nonsense because it's immediately readback fur further
 ;       processing (after this function)
 ;       it would be better to do that processing right here, and then
 ;       write results to their final target
 ;    2) on ARM/MIPS, tmp0,tmp1,tmp2,tmp3,tmp4,tmp5 should be stored
 ;       in CPU registers, not in memory
 ;---
 .data?
  align data_align
  IRP nn,0,1,2,3,4,5   ;\
   @@tmp&nn dd ?       ; tmp0,tmp1,tmp2,tmp3,tmp4,tmp5
  ENDM                 ;/
 .code
 ;---
 @@SUM  equ mp3_SUM
 @@MULH equ mp3_MULH
 ;---
 @@CAST macro t1,t2,dst0,dst1,dst2,dst3
   sub  t1,t2                           ;t1-t2
   lea  t2,[t1+t2*2]                    ;t1+t2
   mov  dword ptr [mp3_out2_a&dst0],t1  ;t1-t2
   mov  dword ptr [mp3_out2_b&dst0],t2  ;t1+t2
 endm
 ;---
 mov  eax,dword ptr [esi+0*3*4]  ;     = src[0*3]               ;\
 mov  @@tmp0,eax                 ;tmp0 = src[0*3]               ;
 mov  edx,dword ptr [esi+1*3*4]  ;     = src[1*3]               ;
 add  eax,edx                    ;     = src[0*3]+src[1*3]      ; tmp0 = in[0*3]
 mov  @@tmp1,eax                 ;tmp1 = src[0*3]+src[1*3]      ; tmp1 = in[1*3] + in[0*3]
 mov  eax,dword ptr [esi+2*3*4]  ;     = src[2*3]               ; tmp2 = in[2*3] + in[1*3]
 add  edx,eax                    ;     = src[1*3]+src[2*3]      ; tmp3 = in[3*3] + in[2*3]
 mov  @@tmp2,edx                 ;tmp2 = src[1*3]+src[2*3]      ; tmp4 = in[4*3] + in[3*3]
 mov  edx,dword ptr [esi+3*3*4]  ;     = src[3*3]               ; tmp5 = in[5*3] + in[4*3] + tmp3
 add  eax,edx                    ;     = src[2*3]+src[3*3]      ; tmp3 = tmp3 + tmp1
 mov  @@tmp3,eax                 ;tmp3 = src[2*3]+src[3*3]      ;
 mov  eax,dword ptr [esi+4*3*4]  ;     = src[4*3]               ;
 add  edx,eax                    ;     = src[3*3]+src[4*3]      ;
 mov  @@tmp4,edx                 ;tmp4 = src[3*3]+src[4*3]      ;
 mov  edx,dword ptr [esi+5*3*4]  ;     = src[5*3]               ;
 add  eax,edx                    ;     = src[4*3]+src[5*3]      ;
 add  eax,@@tmp3                 ;     = src[4*3]+src[5*3]+tmp3 ;
 mov  @@tmp5,eax                 ;tmp5 = src[4*3]+src[5*3]+tmp3 ;
 mov  edx,@@tmp1                 ;     = tmp1                   ;
 add  @@tmp3,edx                 ;tmp3 = tmp3+tmp1              ;/
 ;---
 @@MULH @@tmp2,@@tmp2,-  ,-     ,-,-,1,C3,-         ;tmp2 = MULH(2*tmp2, C3)
 @@MULH @@tmp3,@@tmp3,-  ,-     ,-,-,2,C3,-         ;tmp3 = MULH(4*tmp3, C3)
 ;---
 @@MULH edx   ,@@tmp1,sub,@@tmp5,-,-,1,icos36h_4,-  ;t2   = MULH(2*(tmp1 - tmp5), icos36h_4)
 @@SUM  eax   ,@@tmp0,sub,@@tmp4,-,-                ;t1   = tmp0 - tmp4
 @@CAST eax,edx,1,4,7,10                            ;out2[1,4,7,10]=t1-t2,t1-t2,t1+t2,t1+t2
 ;---
 mov  eax,@@tmp4   ;tmp4
 mov  edx,@@tmp1   ;tmp1
 sar  eax,1        ;tmp4/2
 shl  edx,1        ;tmp1*2
 add  @@tmp0,eax   ;tmp0 = tmp0 + tmp4/2
 add  @@tmp5,edx   ;tmp5 = tmp5 + tmp1*2
 ;---
 @@MULH edx ,@@tmp5,add,@@tmp3,-,-,0,icos36h_1,-  ;t2 = MULH(tmp5 + tmp3, icos36h_1)
 @@SUM  eax ,@@tmp0,add,@@tmp2,-,-                ;t1 = tmp0 + tmp2
 @@CAST eax,edx,2,3,8,9                           ;out2[2,3,8,9]=t1-t2,t1-t2,t1+t2,t1+t2
 ;---
 @@MULH edx ,@@tmp5,sub,@@tmp3,-,-,1,icos36h_7,-  ;t2 = MULH(2*(tmp5 - tmp3), icos36h_7)
 @@SUM  eax ,@@tmp0,sub,@@tmp2,-,-                ;t1 = tmp0 - tmp2
 @@CAST eax,edx,0,5,6,11                          ;out2[0,5,6,11]=t1-t2,t1-t2,t1+t2,t1+t2
 ret
;------------------
align code_align
mp3_compute_imdct:      ;in: ebx=granule
;- - -
.data?
 align data_align
 mp3_out2_a0 dd ?               ;\
 mp3_out2_a1 dd ?               ;
 mp3_out2_a2 dd ?               ;
 mp3_out2_a3 equ mp3_out2_a2    ;
 mp3_out2_a4 equ mp3_out2_a1    ;
 mp3_out2_a5 equ mp3_out2_a0    ;
 mp3_out2_b0 dd ?               ;
 mp3_out2_b1 dd ?               ;
 mp3_out2_b2 dd ?               ;
 mp3_out2_b3 equ mp3_out2_b2    ;
 mp3_out2_b4 equ mp3_out2_b1    ;
 mp3_out2_b5 equ mp3_out2_b0    ;/
 align data_align
 @@JJJ                  dd ?
 @@www                  dd ?
 @@mdct_long_end        dd ?
 @@sblimit              dd ?
 @@switch_point         dd ?
.code
;- - -
 @@SUM  equ mp3_SUM
 @@MULH equ mp3_MULH
;- - -
 timelog_start rdtsc_imdct
 push ebx       ;granule
 IF WITHOUT_ZEROES                                              ;\
   ;recurse what is already known to be zero                    ;
   mov  ecx,dword ptr [ebx+$mp3gr_num_nonzero_hybrids_div9]     ;
   imul eax,ecx,9                                               ;
   lea  edi,[ebx+$mp3gr_sb_hybrid+eax*4]                        ;
   jcxz short @@breakout                                        ;
 ELSE                                                           ;
   lea  edi,[ebx+$mp3gr_sb_hybrid+576*4]                        ;
   mov  ecx,(576)/9                                             ;
 ENDIF                                                          ;
@@scan_zero_lop:                                                ;
 sub  edi,9*4           ;index-9                                ; find last
 mov  eax,dword ptr [edi+0*4]                                   ; nonzero
 or   eax,dword ptr [edi+1*4]                                   ; block
 or   eax,dword ptr [edi+2*4]                                   ;
 or   eax,dword ptr [edi+3*4]                                   ;
 or   eax,dword ptr [edi+4*4]                                   ;
 or   eax,dword ptr [edi+5*4]                                   ;
 or   eax,dword ptr [edi+6*4]                                   ;
 or   eax,dword ptr [edi+7*4]                                   ;
 or   eax,dword ptr [edi+8*4]                                   ;
 jnz  short @@breakout                                          ;
 dec  ecx                                                       ;
 jnz  short @@scan_zero_lop                                     ;
@@breakout:                                                     ;
 inc  ecx        ;div9+1                                        ;
 shr  ecx,1      ;div18                                         ;
 mov  dword ptr [@@sblimit],ecx             ;\                  ;/
;mov  ecx,ecx ;=[@@sblimit]                 ;/  ;\
 cmp  dword ptr [ebx+$mp3gr_block_type],2       ;
 jne  short @@this_long_end                     ; long_end = (0 or 2 or sblimit)
 mov  ecx,dword ptr [ebx+$mp3gr_switch_point]   ;   ;XXX: check for 8000 Hz
 shl  ecx,1   ;0,1 --> 0,2                      ;
@@this_long_end:                                ;
 mov  dword ptr [@@mdct_long_end],ecx           ;/
;- - -
 mov  eax,dword ptr [ebx+$mp3gr_switch_point]   ;\local copy (because ebx is used for other purposes below)
 mov  dword ptr [@@switch_point],eax            ;/
 mov  eax,dword ptr [ebx+$mp3gr_block_type]     ;\precalc mul,
 imul eax,1*36*4                                ; and make local copy
 mov  dword ptr [@@www],eax                     ;/
 mov  ecx,dword ptr [mp3_curr_channel]          ;\
 mov  eax,dword ptr [mp3_curr_granule]          ;
 imul ecx,36*SBLIMIT*4   ;channel=channel       ; sb_samples[ch][gr*18]
 imul eax,18*SBLIMIT*4   ;frame=granule*18      ;
 lea  edi,[mp3_sb_samples+ecx+eax]              ;/
 lea  esi,[ebx+$mp3gr_sb_hybrid]                ;-
 mov  eax,dword ptr [mp3_curr_channel]          ;\
 imul eax,SBLIMIT*18*4                          ; mdct_buf[ch]
 lea  ebx,[mp3_mdct_buf+eax]                    ;/
;- - -
 timelog_start rdtsc_imdct36
 mov  @@JJJ,0                                                                ;\
 cmp  dword ptr [@@mdct_long_end],0                                          ;
 jz   short @@imdct36_done                                                   ;
@@imdct36_lop:   ;for j=0 to mdct_long_end-1                                 ;
 mov  ebp,offset mp3_mdct_win                   ;\                           ;
 cmp  @@JJJ,2   ;cy =0,1                        ;                            ;
 sbb  eax,eax   ;eax=0,FFFFFFFFh                ; select window              ;
 and  eax,dword ptr [@@switch_point]            ;                            ;
 jnz  short @@this_window   ;force window 0     ;                            ;
 add  ebp,dword ptr [@@www]      ;mdct_win      ;                            ;
@@this_window:                                  ;/                           ;
 mov  eax,@@JJJ                                 ;\select frequency inversion ;
 shr  eax,1      ;cy =0,1                       ; (each 2nd pass, use upper  ;
 sbb  eax,eax    ;eax=0,FFFFFFFFh               ; half of window, with       ;
 and  eax,4*36*4 ;eax=0,4*36*4                  ; negated entries)           ;
 add  ebp,eax                    ;mdct_win      ;/                           ;
;mov  edi,edi  ;dst = sb_samples[ch][gr*18]+JJJ ;\                           ;
;mov  ebx,ebx               ;buf ;mdct_buf      ;                            ;
;mov  esi,esi               ;src ;sb_hybrid     ; do imdct36                 ;
;mov  ebp,ebp               ;win ;mdct_win      ;                            ;
 call mp3_imdct36                               ;/                           ;
 add  edi,1*4     ;dst                          ;\                           ;
 add  esi,18*4                   ;sb_hybrid     ;                            ;
 add  ebx,18*4                   ;mdct_buf      ; next                       ;
 inc  @@JJJ                                     ;                            ;
 mov  eax,@@JJJ                                 ;                            ;
 cmp  eax,dword ptr [@@mdct_long_end]           ;                            ;
 jb   short @@imdct36_lop                       ;/                           ;
@@imdct36_done:                                                              ;/
 timelog_end rdtsc_imdct36
;- - -
 timelog_start rdtsc_imdct12
;mov  @@JJJ,dword ptr [@@mdct_long_end]                                      ;\
 mov  eax,@@JJJ                                                              ;
 cmp  eax,dword ptr [@@sblimit]                                              ;
 jae        @@imdct12_done                                                   ;
@@imdct12_lop:   ;for j=mdct_long_end to sblimit-1                           ;
 mov  ebp,offset mp3_mdct_win+2*36*4            ;-select window[2]           ;
 mov  eax,@@JJJ                                 ;\select frequency inversion ;
 shr  eax,1      ;cy =0,1                       ; (each 2nd pass, use upper  ;
 sbb  eax,eax    ;eax=0,FFFFFFFFh               ; half of window, with       ;
 and  eax,4*36*4 ;eax=0,4*36*4                  ; negated entries)           ;
 add  ebp,eax                   ;mdct_win       ;/                           ;
 IRP i,0,1,2,3,4,5                              ;\                           ;
  @@SUM [edi+i*SBLIMIT*4],[ebx+(i+0)*4],-,-,-,- ; copy                       ;
 ENDM                                           ;                            ;
 add  edi,6*SBLIMIT*4                           ;/                           ;
;mov  esi,esi                   ;sb_hybrid      ;\imdct12                    ;
 call mp3_imdct12       ;in: esi, out: out2     ;/                           ;
 IRP i,0,1,2,3,4,5                              ;\
  @@MULH [edi+i*SBLIMIT*4],[mp3_out2_a&i],-,-,-,-,0,[ebp+(i+0)*4],[ebx+(1*6+i)*4]   ;dst[i*SBLIMIT] = MULH(out2[i],   win[i])    + buf[i+6*1]
  @@MULH [ebx+(2*6+i)*4]  ,[mp3_out2_b&i],-,-,-,-,0,[ebp+(i+6)*4],-                 ;buf[i+6*2]     = MULH(out2[i+6], win[i+6])
 ENDM                                           ;
 add  edi,6*SBLIMIT*4                           ;/                           ;
 add  esi,4                     ;sb_hybrid      ;\imdct12                    ;
 call mp3_imdct12       ;in: esi, out: out2     ;/                           ;
 IRP i,0,1,2,3,4,5                              ;\
  @@MULH [edi+i*SBLIMIT*4],[mp3_out2_a&i],-,-,-,-,0,[ebp+(i+0)*4],[ebx+(2*6+i)*4]   ;dst[i*SBLIMIT] = MULH(out2[i],   win[i])    + buf[i+6*2]
  @@MULH [ebx+(0*6+i)*4]  ,[mp3_out2_b&i],-,-,-,-,0,[ebp+(i+6)*4],-                 ;buf[i+6*0]     = MULH(out2[i+6], win[i+6])
 ENDM                                           ;/
 add  esi,4                     ;sb_hybrid      ;\imdct12                    ;
 call mp3_imdct12       ;in: esi, out: out2     ;/                           ;
 IRP i,0,1,2,3,4,5                              ;\
  @@MULH [ebx+(0*6+i)*4]  ,[mp3_out2_a&i],-,-,-,-,0,[ebp+(i+0)*4],[ebx+(0*6+i)*4]   ;buf[i+6*0]   = MULH(out2[i],   win[i])    + buf[i+6*0]
  @@MULH [ebx+(1*6+i)*4]  ,[mp3_out2_b&i],-,-,-,-,0,[ebp+(i+6)*4],-                 ;buf[i+6*1]   = MULH(out2[i+6], win[i+6])
  mov  dword ptr [ebx+(2*6+i)*4],0           ;<-- XXX is that needed? yes!          ;buf[i+6*2]   = 0
 ENDM                                           ;/
 add  edi,(1*4) - (2*6*SBLIMIT*4)  ;dst ;\                                   ;
 add  esi,18*4 - (2*4)       ;sb_hybrid ;                                    ;
 add  ebx,18*4               ;mdct_buf  ;                                    ;
 inc  @@JJJ                             ; next                               ;
 mov  eax,@@JJJ                         ;                                    ;
 cmp  eax,dword ptr [@@sblimit]         ;                                    ;
 jb         @@imdct12_lop               ;/                                   ;
@@imdct12_done:                                                              ;/
 timelog_end rdtsc_imdct12
;- - -
 timelog_start rdtsc_imdct0
;mov  @@JJJ,dword ptr [@@sblimit]                       ;\
 cmp  @@JJJ,SBLIMIT                                     ;
 jae        @@zero_outer_done                           ;
@@zero_outer_lop:                                       ; zero bands
 IF UNROLL_DCT0                                         ;
   IRP nn,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17   ;
    mov  eax,dword ptr [ebx+nn*4]                       ;
    mov  dword ptr [ebx+nn*4],0                         ;   ;<-- XXX is that needed? yes!
    mov  dword ptr [edi+nn*SBLIMIT*4],eax  ;[dst]       ;
   ENDM                                                 ;
   add  ebx,18*4                                        ;
   add  edi,(1*4)                          ;dst         ;
 ELSE                                                   ;
   mov  ecx,18                            ;\            ;
  @@zero_inner_lop:                       ;             ;
   mov  eax,dword ptr [ebx]               ;             ;
   mov  dword ptr [ebx],0                 ;             ;   ;<-- XXX is that needed? yes!
   add  ebx,4                  ;mdct_buf  ;             ;
   mov  dword ptr [edi],eax        ;[dst] ;             ;
   add  edi,SBLIMIT*4              ;dst   ;             ;
  ;loop short @@zero_inner_lop            ;  ;-SLOW     ;
   dec  ecx                               ;  ;\FASTER on;
   jnz  short @@zero_inner_lop            ;/ ;/Pentium3 ;
   add  edi,(1*4) - (18*SBLIMIT*4) ;dst                 ;
 ENDIF                                                  ;
 inc  @@JJJ                             ;\              ;
 cmp  @@JJJ,SBLIMIT                     ; next          ;
 jb         @@zero_outer_lop            ;/              ;
@@zero_outer_done:                                      ;/
 timelog_end rdtsc_imdct0
 pop  ebx       ;granule
 timelog_end rdtsc_imdct
 ret
;------------------
;:----------------- Mp3 code maths dct32
;------------------
mp3_dct32_macro macro rate_shift   ;in: esi=src/tab, edi=dst/out (both are 32bit arrays)
 ;---
 @@BF macro a, b, sign, cos, shift
   local @@need_a,@@need_b
   ;tmp0 = tab[a] + tab[b]
   ;tmp1 = tab[a] - tab[b]
   ;tab[a] = tmp0
   ;tab[b] = MULH(tmp1<<(shift), cos*sign)
   ;---
   @@need_a equ (rate_shift EQ 0) or (a LT 16)
   @@need_b equ (rate_shift EQ 0) or (b LT 16)
   ;---
   IF @@need_a AND @@need_b
     mov  eax,dword ptr [esi+a*4]
     mov  edx,dword ptr [esi+b*4]
     add  dword ptr [esi+a*4],edx
     sub  eax,edx
     shl  eax,shift    ;<-- shift (needed when COS.fraction is less than 32bit)
     mov  edx,sign&&cos         ;\
     imul edx                   ;/
     mov  dword ptr [esi+b*4],edx   ;upper 32bit of multiply result
   ELSEIF @@need_a
     mov  eax,dword ptr [esi+b*4]
     add  dword ptr [esi+a*4],eax
   ELSEIF @@need_b
     xxx (the case with only "b" doesn't exist, it's either "a or both or none")
   ENDIF
 endm
 ;---
 @@ADD macro dst,src
  IF (rate_shift EQ 0) or (dst LT 16)
   ;tab[a] += tab[b]
   mov  eax,dword ptr [esi+src*4]
   add  dword ptr [esi+dst*4],eax
  ENDIF
 endm
 ;---
 @@BF1 macro a, b, c, d
   @@BF  a, b,+,COS4_0, 1
   @@BF  c, d,-,COS4_0, 1
   @@ADD c, d
 endm
 ;---
 @@BF2 macro a, b, c, d
   @@BF  a, b,+,COS4_0, 1
   @@BF  c, d,-,COS4_0, 1
   @@ADD c, d
   @@ADD a, c
   @@ADD c, b
   @@ADD b, d
 endm
 ;---
 @@OUT macro dst,src1,src2
  IF ((dst AND ((1 SHL rate_shift)-1)) EQ 0)    ;-quickskip for low sample rates
   mov  eax,dword ptr [esi+src1*4]
   IFDIFI <src2>,<->
     add  eax,dword ptr [esi+src2*4]
   ENDIF
   IF SINGLE_SAT EQ 0                           ;\
     lea  edx,[eax+8000h]                       ;
     cmp  edx,10000h                            ; saturate
     jb   short @@inrange&&dst                  ; (only needed when using
     sar  eax,31    ;FFFFFFFFh,00000000h        ; 16bit synth_buf)
     xor  eax,7fffh ;FFFF8000h,00007FFFh        ;     XXX maybe also needed for fast
    @@inrange&&dst:                             ;     synth multiply with 32bit results, which might otherwise overflow multipy/sum,
   ENDIF                                        ;/    if so, should saturate to (+/-1 SHL VVRAC_BITS)
   IF SYNTH32                                   ;\
     mov  dword ptr [edi+dst*4],eax             ; output to synth_buf
     IF (LONG_WINDOW EQ 0)                      ;
       mov  dword ptr [edi+dst*4+512*4],eax     ;
     ENDIF                                      ;
   ELSE                                         ;
    ;ERRIF SINGLE_SAT EQ 0         ;ought to be saturated here
     mov  word ptr [edi+dst*2],ax               ;
     IF (LONG_WINDOW EQ 0)                      ;
       mov  word ptr [edi+dst*2+512*2],ax       ;
     ENDIF                                      ;
   ENDIF                                        ;/
  ENDIF
 endm
 ;---
 @@BF  0, 31,+,COS0_0 , 1     ;\pass 1
 @@BF 15, 16,+,COS0_15, 5     ;/
 @@BF  0, 15,+,COS1_0 , 1     ;\pass 2
 @@BF 16, 31,-,COS1_0 , 1     ;/        ;-for odd dest
 @@BF  7, 24,+,COS0_7 , 1     ;\pass 1
 @@BF  8, 23,+,COS0_8 , 1     ;/
 @@BF  7,  8,+,COS1_7 , 4     ;\pass 2
 @@BF 23, 24,-,COS1_7 , 4     ;/        ;-for odd dest
 @@BF  0,  7,+,COS2_0 , 1     ;\
 @@BF  8, 15,-,COS2_0 , 1     ; pass 3
 @@BF 16, 23,+,COS2_0 , 1     ;         ;\for odd dest
 @@BF 24, 31,-,COS2_0 , 1     ;/        ;/
 @@BF  3, 28,+,COS0_3 , 1     ;\pass 1
 @@BF 12, 19,+,COS0_12, 2     ;/
 @@BF  3, 12,+,COS1_3 , 1     ;\pass 2
 @@BF 19, 28,-,COS1_3 , 1     ;/        ;-for odd dest
 @@BF  4, 27,+,COS0_4 , 1     ;\pass 1
 @@BF 11, 20,+,COS0_11, 2     ;/
 @@BF  4, 11,+,COS1_4 , 1     ;\pass 2
 @@BF 20, 27,-,COS1_4 , 1     ;/        ;-for odd dest
 @@BF  3,  4,+,COS2_3 , 3     ;\
 @@BF 11, 12,-,COS2_3 , 3     ; pass 3
 @@BF 19, 20,+,COS2_3 , 3     ;         ;\for odd dest
 @@BF 27, 28,-,COS2_3 , 3     ;/        ;/
 @@BF  0,  3,+,COS3_0 , 1     ;\
 @@BF  4,  7,-,COS3_0 , 1     ;
 @@BF  8, 11,+,COS3_0 , 1     ; pass 4
 @@BF 12, 15,-,COS3_0 , 1     ;
 @@BF 16, 19,+,COS3_0 , 1     ;         ;\
 @@BF 20, 23,-,COS3_0 , 1     ;         ; for odd dest
 @@BF 24, 27,+,COS3_0 , 1     ;         ;
 @@BF 28, 31,-,COS3_0 , 1     ;/        ;/
 @@BF  1, 30,+,COS0_1 , 1     ;\pass 1
 @@BF 14, 17,+,COS0_14, 3     ;/
 @@BF  1, 14,+,COS1_1 , 1     ;\pass 2
 @@BF 17, 30,-,COS1_1 , 1     ;/        ;-for odd dest
 @@BF  6, 25,+,COS0_6 , 1     ;\pass 1
 @@BF  9, 22,+,COS0_9 , 1     ;/
 @@BF  6,  9,+,COS1_6 , 2     ;\pass 2
 @@BF 22, 25,-,COS1_6 , 2     ;/        ;-for odd dest
 @@BF  1,  6,+,COS2_1 , 1     ;\
 @@BF  9, 14,-,COS2_1 , 1     ; pass 3
 @@BF 17, 22,+,COS2_1 , 1     ;         ;\for odd dest
 @@BF 25, 30,-,COS2_1 , 1     ;/        ;/
 @@BF  2, 29,+,COS0_2 , 1     ;\pass 1
 @@BF 13, 18,+,COS0_13, 3     ;/
 @@BF  2, 13,+,COS1_2 , 1     ;\pass 2
 @@BF 18, 29,-,COS1_2 , 1     ;/        ;-for odd dest
 @@BF  5, 26,+,COS0_5 , 1     ;\pass 1
 @@BF 10, 21,+,COS0_10, 1     ;/
 @@BF  5, 10,+,COS1_5 , 2     ;\pass 2
 @@BF 21, 26,-,COS1_5 , 2     ;/        ;-for odd dest
 @@BF  2,  5,+,COS2_2 , 1     ;\
 @@BF 10, 13,-,COS2_2 , 1     ; pass 3
 @@BF 18, 21,+,COS2_2 , 1     ;         ;\for odd dest
 @@BF 26, 29,-,COS2_2 , 1     ;/        ;/
 @@BF  1,  2,+,COS3_1 , 2     ;\
 @@BF  5,  6,-,COS3_1 , 2     ;
IF rate_shift LT 2
 @@BF  9, 10,+,COS3_1 , 2     ; pass 4
 @@BF 13, 14,-,COS3_1 , 2     ;
ENDIF
 @@BF 17, 18,+,COS3_1 , 2     ;         ;\
 @@BF 21, 22,-,COS3_1 , 2     ;         ; for odd dest
 @@BF 25, 26,+,COS3_1 , 2     ;         ;
 @@BF 29, 30,-,COS3_1 , 2     ;/        ;/
;- - -
 @@BF1  0,  1,  2,  3         ;\
 @@BF2  4,  5,  6,  7         ;
IF rate_shift LT 2
 @@BF1  8,  9, 10, 11         ; pass 5
 @@BF2 12, 13, 14, 15         ;
ENDIF
 @@BF1 16, 17, 18, 19         ;         ;\
 @@BF2 20, 21, 22, 23         ;         ; for odd dest
 @@BF1 24, 25, 26, 27         ;         ;
 @@BF2 28, 29, 30, 31         ;/        ;/
 @@OUT  0,  0, -              ;\
 @@OUT 16,  1, -              ;
 @@OUT  8,  2, -              ;
 @@OUT 24,  3, -              ;
 @@OUT  4,  4, -              ;
 @@OUT 20,  5, -              ; output (even dest)
 @@OUT 12,  6, -              ;
 @@OUT 28,  7, -              ;
 @@OUT  2,  8, 12             ;   ;\
 @@OUT 18,  9, 13             ;   ;
 @@OUT 10, 10, 14             ;   ;
 @@OUT 26, 11, 15             ;   ; semi-odd dest
 @@OUT  6, 12, 10             ;   ; with pass 6 add
 @@OUT 22, 13, 11             ;   ;
 @@OUT 14, 14, 9              ;   ;
 @@OUT 30, 15, -              ;/  ;/
 @@ADD 24, 28                 ;\
 @@ADD 28, 26                 ;
 @@ADD 26, 30                 ; pass 6 (for odd dest)
 @@ADD 30, 25                 ;
 @@ADD 25, 29                 ;
 @@ADD 29, 27                 ;
 @@ADD 27, 31                 ;/
 @@OUT  1, 16, 24             ;\
 @@OUT 17, 17, 25             ;
 @@OUT  9, 18, 26             ;
 @@OUT 25, 19, 27             ;
 @@OUT  5, 20, 28             ;
 @@OUT 21, 21, 29             ; output (odd dest)
 @@OUT 13, 22, 30             ;
 @@OUT 29, 23, 31             ;
 @@OUT  3, 24, 20             ;
 @@OUT 19, 25, 21             ;
 @@OUT 11, 26, 22             ;
 @@OUT 27, 27, 23             ;
 @@OUT  7, 28, 18             ;
 @@OUT 23, 29, 19             ;
 @@OUT 15, 30, 17             ;
 @@OUT 31, 31, -              ;/
 ret
endm
;---
align code_align
mp3_dct32_shift_0:    mp3_dct32_macro 0
IF with_rate_shift
  align code_align
  mp3_dct32_shift_1:  mp3_dct32_macro 1
  align code_align
  mp3_dct32_shift_2:  mp3_dct32_macro 2
ENDIF
;------------------
;:----------------- Mp3 code maths synth
;------------------
SYNTH_MACRO macro force_8bit,rate_shift,force_fast
 timelog_start rdtsc_synth_dct
 mov  esi,offset mp3_sb_samples         ;src                    ;\
 mov  edi,dword ptr [mp3_samples_dst]   ;dst                    ;
 mov  dword ptr [mp3_curr_channel],0            ;\              ;
@@synth_channel_lop:                            ;/              ; apply the synthesis filter
 push esi       ;src                                            ;
 push edi       ;dst                                            ;
 mov  dword ptr [mp3_curr_syn_dst],edi
 mov  dword ptr [mp3_curr_frame],0              ;\              ;
@@synth_frame_lop:                              ;/              ;
 push esi       ;src  ;sb_samples[ch][i]                        ;
;- - -
 timelog_start rdtsc_dct32
;- - -
 mov  edx,dword ptr [mp3_curr_channel]          ;\
 mov  eax,dword ptr [mp3_synth_index+edx*4]     ;
 sub  dword ptr [mp3_synth_index+edx*4],32      ; base for current syn
 shl  edx,10        ;channel*1024               ; (and advance next=curr-32)
 and  eax,1ffh-1fh  ;index(0..511), align 32    ;
 or   eax,edx                                   ;
 mov  dword ptr [mp3_curr_syn_index],eax        ;/

;mov  esi,esi  ;sb_samples[ch][frame]    ;-src          ;\
 mov  edi,dword ptr [mp3_curr_syn_index] ;\             ;
 IF SYNTH32                              ;              ; dct32 (sb_samples --> synth_buf)
   lea  edi,[mp3_synth_buf+edi*4]        ; dst          ;
 ELSE                                    ;              ;
   lea  edi,[mp3_synth_buf+edi*2]        ;              ;
 ENDIF                                   ;/             ;
 call mp3_dct32_shift_&rate_shift                       ;/
 timelog_end rdtsc_dct32
;- - -
 timelog_start rdtsc_synth                                        ;\
 call mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast ; synth/output
 timelog_end rdtsc_synth                                          ;/
;- - -
 pop  esi       ;src                            ;/              ;
 mov  eax,dword ptr [mp3_samples_dst_step]      ;\              ;
 shl  eax,5             ;mul32                  ;               ;
 IF with_rate_shift                             ;               ;
   mov  cl,byte ptr [option_rate_shift]         ;               ;
   shr  eax,cl                                  ;               ;
 ENDIF                                          ;               ;
 add  dword ptr [mp3_curr_syn_dst],eax          ;               ;
 add  esi,SBLIMIT*4     ;src+32*4               ;/              ;
 inc  dword ptr [mp3_curr_frame]                ;\              ;
 mov  eax,dword ptr [mp3_curr_frame]            ; next frame    ;
 cmp  eax,dword ptr [mp3_nb_frames]             ;               ;
 jb         @@synth_frame_lop                   ;/              ;
 pop  edi       ;dst                                            ;
 pop  esi       ;src                                            ;
 add  edi,dword ptr [mp3_bytes_per_sample] ;dst ;\              ;
 add  esi,36*SBLIMIT*4  ;src                    ;/              ;
 inc  dword ptr [mp3_curr_channel]              ;\              ;
 mov  eax,dword ptr [mp3_curr_channel]          ; next channel  ;
 cmp  eax,dword ptr [mp3_output_num_channels]   ;               ;
 jb         @@synth_channel_lop                 ;/              ;/
 timelog_end rdtsc_synth_dct
 ret
;------------------
align code_align
mp3_synth_filter_this_&force_8bit&_&rate_shift&_&force_fast:   ;in: esi=src (32bit sb_samples[ch][frame]), edi=dst (16bit samples)
;aka utput_32_samples:
;- - -
  @@sum          equ ebx
  @@sum_16bit    equ bx
  @@sum_8bit     equ bl
  @@win1 equ ebp                                 ;\
  @@syn1 equ esi                                 ;
  @@syn2 equ edi                                 ;/
  @@dst  equ ecx
;- - -
 @@SUM8 macro sum,win,ww, syn
  IRP nn,0,1,2,3,4,5,6,7
    IF SYNTH32
      mov  edx,dword ptr [mp3_synth_buf+syn*4+(nn*64*4)]
    ELSE
      movsx edx,word ptr [mp3_synth_buf+syn*2+(nn*64*2)]
    ENDIF
    IF force_fast  ;for with_fast_option, or prefer_dirty
      ERRIF WFRAC_BITS_fast GT 14
      ERRIF SUM_SHIFT_fast NE 0    ;want result in LSW
      movsx eax,word ptr [mp3_synth_win+win*2+(nn*64*2)+ww*2]  ;fast 16bit read    ;this is slightly faster than 32bit mov (maybe better caching)
      imul eax,edx    ;32bit = 16bit * 16bit                   ;fast 32bit result  ;NOTE: this is MUCH faster than "imul edx" with same exactly operands (which returns same result in eax, but additionally stores MSBs of result in edx)
      add  sum,eax                                             ;sum from LSW of result
    ELSE    ;slower, but more accurate
      ERRIF WFRAC_BITS_slow LT 16   ;want full 16bit fraction
      ERRIF SUM_SHIFT_slow NE 32    ;want result in MSW
      mov  eax,dword ptr [mp3_synth_win+win*4+(nn*64*4)+ww*4]  ;slow 32bit read
      imul edx        ;64bit = 32bit * 32bit                   ;slow 64bit result
      add  sum,edx                                             ;sum from MSW of result
    ENDIF
    ;note for SUM_SHIFT other than 0 or 32, one could do...
    ;  shrd eax,edx,SUM_SHIFT      ;<-- very slow
    ;  shl  edx,(32-SUM_SHIFT)     ;\
    ;  shr  eax,SUM_SHIFT          ; even slower
    ;  or   eax,edx                ;/
    ;  pre-shifting INCOMING 32bit opereand(s) before multiply might also work
    ;note: "imul eax,edx" (32bit result) is MUCH FASTER than "imul edx"
    ;(64bit result), that, even for small operand where the exact same result
    ;would fully fit into lower 32bit.
  ENDM
 endm
;- - -
 IF LONG_WINDOW                                  ;\
   mov  eax,dword ptr [mp3_curr_syn_index]   ;-  ;
   test eax,1ffh-1fh     ;offset             ;\  ;
   jz         @@append_copy_to_window        ;   ;
   nop   ;XXX align code_align-oddity: this is faster
  @@append_copy_to_window_back:              ;/  ;
   mov  @@win1,eax                               ;
   and  @@win1,1ffh-1fh-20h                      ;
   and  eax,20h+(1 shl 10)  ;bit5, and channel   ;
   lea  @@syn1,[eax+10h]                         ;
   lea  @@syn2,[eax+30h] ;XXX that can be 20h+30h, which could exceed 1FFh when adding 7*40h, if so, that still needs a SMALL copy at end of synth_buf (but only if new data was written near boundary) (alternarely, one could probably use separate @@win1 values for @@syn1,@@syn2)
   neg  @@win1                                   ;
   and  @@win1,1ffh-1fh-20h                      ;
 ELSE                                            ;
   mov  @@win1,0   ;index in mp3_synth_win       ;
   mov  eax,dword ptr [mp3_curr_syn_index]       ;
   lea  @@syn1,[eax+16]  ;index in mp3_synth_buf ;
   lea  @@syn2,[eax+48]  ;index in mp3_synth_buf ;/
 ENDIF
;- - -
 IF force_fast
   @@out_shift equ (OUT_SHIFT_fast(8*force_8bit))
 ELSE
   @@out_shift equ (OUT_SHIFT_slow+(8*force_8bit))
 ENDIF
;- - -
 mov  @@dst,dword ptr [mp3_curr_syn_dst]
@@samples_lop:
 IF force_8bit EQ 0                                             ;\initial sum,
   mov  @@sum,(8000h SHL (@@out_shift))+(1 SHL (@@out_shift-1)) ; with unsigned
 ELSE                                                           ; bias, plus 0.5
   mov  @@sum,(80h SHL (@@out_shift))+(1 SHL (@@out_shift-1))   ; (the 0.5 fraction is important to eliminate near-zero noise when using 8bit output, eg. in leading silence in Tangoclub - Hexe)
 ENDIF                                                          ;/
 IF ZERO_WINDOW EQ 0       ;XXX or is this FASTER ? (speed seems to be about same)
   IF LONG_WINDOW
     mov  eax,@@win1      ;\
     and  eax,1fh         ;
     cmp  eax,10h         ;
     je   @@skippp        ;
   ELSE                   ;
     cmp  @@win1,16       ; XXX instead force the corresponding @@win entries to zero (and check if it's faster when doing dummy-zero-multiplications instead of skipping)
     je   @@skippp        ;/
   ENDIF
 ENDIF
 @@SUM8 @@sum,@@win1,0,  @@syn1                               ;\
         @@skippp:                                            ; calc one sample
 @@SUM8 @@sum,@@win1,32, @@syn2                               ;/

 IF force_8bit EQ 0                                             ;\
   cmp  @@sum,10000h SHL (@@out_shift)                          ;
   jae  short @@sat                                             ;
   sar  @@sum,(@@out_shift)                                     ;
   sub  @@sum,8000h  ;make 16bit signed                         ; output
  @@sat_back:                                                   ; one sample
   mov  word ptr [@@dst],@@sum_16bit                            ;
 ELSE                                                           ;
   cmp  @@sum,100h SHL (@@out_shift)                            ;
   jae  short @@sat                                             ;
   sar  @@sum,(@@out_shift)                                     ;
  ;sub  @@sum,00h    ;keep 8bit unsigned                        ;
  @@sat_back:                                                   ;
   mov  byte ptr [@@dst],@@sum_8bit                             ;
 ENDIF                                                          ;/

 add  @@dst,dword ptr [mp3_samples_dst_step]                      ;
 IF rate_shift                                                    ;
   add  @@syn1,1 shl rate_shift                                   ;
   sub  @@syn2,1 shl rate_shift                                   ;
   add  @@win1,1 shl rate_shift                                   ;
 ELSE                                                             ;
   inc  @@syn1                                                    ;
   dec  @@syn2                                                    ;
   inc  @@win1                                                    ;/
 ENDIF
                IF LONG_WINDOW
                 test @@win1,1fh   ;slower than "cmp 20h"
                 jnz        @@samples_lop
                ELSE
 cmp  @@win1,32
 jb         @@samples_lop
                ENDIF

 ret
;---
align code_align
@@sat:
 sar  @@sum,31       ;FFFFFFFFh,00000000h
 IF force_8bit EQ 0
   xor  @@sum,7fffh  ;FFFF8000h,00007FFFh (signed 16bit)
 ELSE
   not  @@sum        ;00000000h,FFFFFFFFh (unsigned 8bit)
 ENDIF
 jmp  short @@sat_back
;---
 IF LONG_WINDOW
  align code_align
  @@append_copy_to_window:  ;in: eax, out: eax=same
   IF SYNTH32
     lea  esi,[mp3_synth_buf+eax*4]
     lea  edi,[esi+512*4]
     mov  ecx,(12h*4)/4
     rep  movsd
   ELSE
     lea  esi,[mp3_synth_buf+eax*2]
     lea  edi,[esi+512*2]
     mov  ecx,(12h*2)/4
     rep  movsd
   ENDIF
   jmp        @@append_copy_to_window_back
 ENDIF
;---
endm  ;SYNTH_MACRO
;---
IF with_fast_option OR (prefer_dirty)
 align code_align
 synth_16bit_shift_0_fast:    SYNTH_MACRO 0,0,1      ;16bit, full rate
 IF with_rate_shift
   align code_align
   synth_16bit_shift_1_fast:  SYNTH_MACRO 0,1,1      ;16bit, half rate
   align code_align
   synth_16bit_shift_2_fast:  SYNTH_MACRO 0,2,1      ;16bit, quarter rate
 ENDIF
 IF with_8bit_output
   align code_align
   synth_8bit_shift_0_fast:   SYNTH_MACRO 1,0,1      ;8bit, full rate
   IF with_rate_shift
     align code_align
     synth_8bit_shift_1_fast: SYNTH_MACRO 1,1,1      ;8bit, half rate
     align code_align
     synth_8bit_shift_2_fast: SYNTH_MACRO 1,2,1      ;8bit, quarter rate
   ENDIF
 ENDIF
ENDIF
IF with_fast_option OR (prefer_dirty EQ 0)
 align code_align
 synth_16bit_shift_0_slow:    SYNTH_MACRO 0,0,0      ;16bit, full rate
 IF with_rate_shift
   align code_align
   synth_16bit_shift_1_slow:  SYNTH_MACRO 0,1,0      ;16bit, half rate
   align code_align
   synth_16bit_shift_2_slow:  SYNTH_MACRO 0,2,0      ;16bit, quarter rate
 ENDIF
 IF with_8bit_output
   align code_align
   synth_8bit_shift_0_slow:   SYNTH_MACRO 1,0,0      ;8bit, full rate
   IF with_rate_shift
     align code_align
     synth_8bit_shift_1_slow: SYNTH_MACRO 1,1,0      ;8bit, half rate
     align code_align
     synth_8bit_shift_2_slow: SYNTH_MACRO 1,2,0      ;8bit, quarter rate
   ENDIF
 ENDIF
ENDIF
;------------------
;:----------------- Mp3 code init generic
;------------------
.data?
align data_align
 mp3_huff_tmp_bits  db 100h dup (?)
 mp3_huff_tmp_codes dw 100h dup (?)  ;note: the mp3 huffcodes are up to 19bit wide (but the larger ones have leading zeroes, so they can be stored in 16bit words)
.code
;------------------
mp3_any_init_synth_window:
 xor  edx,edx     ;index (0..100h)                              ;\
 xor  ecx,ecx     ;delta.val                                    ;
 mov  dword ptr [mp3_synth_win+edx*2],ecx      ;-entry[0]=0     ;
@@synth_lop:                                                    ; synth init
 movsx ebx,word ptr [mp3_synth_win_src+edx*2]  ;-src[0..FFh]    ; "window"
 add  ecx,ebx     ;delta.val                   ;-delta          ;
mov  eax,ecx
 IF with_fast_option or (prefer_dirty EQ 1)           ;\        ;
   IF (WFRAC_BITS_fast LT WFRAC_BITS_default)         ;         ;
     IF with_fast_option                              ;         ;
       cmp  byte ptr [option_fast],0                  ;         ;
       jz   short @@not_fast                          ; fast    ;
     ENDIF                                            ;         ;
     sar  eax,(WFRAC_BITS_default-WFRAC_BITS_fast)    ;         ;
    @@not_fast:                                       ;         ;
   ENDIF                                              ;         ;
 ENDIF                                                ;/        ;
 IF with_fast_option or (prefer_dirty EQ 0)           ;\        ;
   IF (WFRAC_BITS_slow GT WFRAC_BITS_default)         ;         ;
     IF with_fast_option                              ;         ;
       cmp  byte ptr [option_fast],0                  ;         ;
       jnz  short @@not_slow                          ; slow    ;
     ENDIF                                            ;         ;
     shl  eax,(WFRAC_BITS_slow-WFRAC_BITS_default)    ;         ;
    @@not_slow:                                       ;         ;
   ENDIF                                              ;         ;
 ENDIF                                                ;/        ;
 inc  edx         ;index (1..100h)                              ;
 mov  ebx,200h                                 ;\               ;
 sub  ebx,edx    ;1FFh..100h                   ; dst[1FFh..100h];
 mov  dword ptr [mp3_synth_win+ebx*4],eax      ;/               ;
 test edx,3fh                                  ;\               ;
 jz   short @@synth_keep_sign                  ; negate         ;
 neg  eax                                      ;                ;
@@synth_keep_sign:                             ;/               ;
 mov  dword ptr [mp3_synth_win+edx*4],eax      ;-dst[1..100h]   ;
 cmp  edx,100h                                                  ;
 jb   short @@synth_lop                                         ;/
 xor  edx,edx                                                   ;\
@@synth_neg_lop:                                                ; negate some
 test edx,30h   ;skip 0..0Fh (only negate 10h..3Fh)             ; synth values
 jz   short @@synth_neg_next                                    ; (so one can
 neg  dword ptr [mp3_synth_win+edx*4]                           ; always use
@@synth_neg_next:                                               ; multiply/add
 inc  edx                                                       ; instead of
 cmp  edx,200h                                                  ; multiply/sub)
 jb   short @@synth_neg_lop                                     ;/
 xor  edx,edx                                                   ;\
@@synth_swap_lop:                                               ;
 mov  eax,edx                                                   ;
 and  eax,3fh                                                   ; swap win [(17..31)] with win[(17..31)+32)
 sub  eax,17                                                    ;
 cmp  eax,31-17                                                 ;
 ja   short @@synth_swap_next                                   ;
 mov  eax,dword ptr [mp3_synth_win+edx*4]                       ;
 xchg eax,dword ptr [mp3_synth_win+edx*4+32*4]                  ;
 mov  dword ptr [mp3_synth_win+edx*4],eax                       ;
@@synth_swap_next:                                              ;
 inc  edx                                                       ;
 cmp  edx,200h                                                  ;
 jb   short @@synth_swap_lop                                    ;/
 IF ZERO_WINDOW
   xor  edx,edx                                                   ;\
  @@synth_zero_lop:                                               ; force unused win entries to zero
   mov  dword ptr [mp3_synth_win+edx*4+10h*4],0                   ; (so one could do "dummy-zero-multiplies")
   add  edx,40h                                                   ; (or alternately one could skip them, whichever is faster)
   cmp  edx,200h                                                  ;
   jb   short @@synth_zero_lop                                    ;/
 ENDIF
 IF LONG_WINDOW
   mov  esi,offset mp3_synth_win        ;\
   lea  edi,[esi+512*4]                 ; append another copy
   mov  ecx,512                         ; (so it can wrap into copy, without needing masking)
   rep  movsd                           ;/
 ENDIF
 ret
;------------------
mp3_init_post_collapse:   ;must be done AFTER mp3_init_log_constants

        ;XXX for half/quarter sample rate --> collapse here (maybe gives faster caching?)
 ;- - -
 IF with_fast_option OR prefer_dirty    ;\
   IF with_fast_option                  ;
     cmp  byte ptr [option_fast],0      ; fast option
     jz   short @@not_fast              ;
   ENDIF                                ;
   ERRIF WFRAC_BITS_fast GT 14          ; ;\
   mov  esi,offset mp3_synth_win        ; ;
   mov  edi,esi                         ; ; when using low-resolution values,
   mov  ecx,512*(1+LONG_WINDOW)         ; ; collapse 32bit to 16bit
  @@collapse_lop:                       ; ; (that's slightly faster, probably
   lodsd                                ; ; due to better caching)
   stosw                                ; ;
   loop short @@collapse_lop            ; ;/
  @@not_fast:                           ;
 ENDIF                                  ;/
 ret
;------------------
mp3_any_init_band_indices:
 mov  esi,offset mp3_band_size_long   ;src (steps)              ;\
 mov  edi,offset mp3_band_index_long  ;dst (sums)               ;
 mov  ebx,9                                                     ; band indices
@@band_index_lop_i:                                             ; (for
 xor  eax,eax                                                   ; band sizes)
 mov  ecx,22                            ;\                      ;
@@band_index_lop_j:                     ;                       ;
 stosw                                  ; index[i][0..21]       ;
 moz  edx,byte ptr [esi]                ;                       ;
 add  eax,edx                           ;                       ;
 inc  esi                               ;                       ;
 loop short @@band_index_lop_j          ;/                      ;
;cmp  ax,240h                           ;\                      ;
;jne  fatalunexpected                   ;/                      ;
 add  ecx,10  ;add 0+10 (compresses     ;\index[i][22..31]      ;
 rep  stosw   ;   better than mov 10)   ;/                      ;
 dec  ebx                                                       ;
 jnz  short @@band_index_lop_i                                  ;/
 ret
;------------------
mp3_any_init_lsf_sf_expand:
 ;precalculate some lsf expand stuff into a huge 8 Kbyte lookup table
 ;(alternately, one could compute that stuff on the fly, as done in minimp3,
 ;which is awkward because of the slow div/mod opcodes, although not too
 ;worse because the calculations occur only a few times per sample block)
 ;- - -
 mov  esi,offset mp3_lsf_sf_expand_init_table
 mov  edi,offset mp3_lsf_sf_expand_exploded_table
 xor  edx,edx   ;curr.index
 xor  ebx,ebx   ;curr.base
@@lop:
 cmp  dx,word ptr [esi+6]  ;nextbase                            ;\
 jb   short @@inrange                                           ;
 mov  bx,word ptr [esi+6]  ;nextbase    ;apply as curr.base     ; next base
 add  esi,8                ;next entry  ;and advance to next    ;
@@inrange:                                                      ;/
 mov  eax,edx   ;curr.index             ;\                      ;\
 sub  eax,ebx   ;curr.base              ;                       ;
 mov  cl,byte ptr [esi+0]  ;div2        ; [3]=slen[3]           ;
 shr  eax,cl    ;div2 (if so)           ;                       ; lsf_sf_expand
 div  byte ptr [esi+3]     ;mod3        ;                       ;
 mov  byte ptr [edi+3],ah  ;remainder   ;/                      ;
 mov  ah,00h    ;eax=div.result         ;\                      ;
 div  byte ptr [esi+2]     ;mod2        ; [2]=slen[2]           ;
 mov  byte ptr [edi+2],ah  ;remainder   ;/                      ;
 mov  ah,00h    ;eax=div.result         ;\                      ;
 div  byte ptr [esi+1]     ;mod1        ; [1]=slen[1]           ;
 mov  word ptr [edi+0],ax  ;al,ah       ;/[0]=slen[0]           ;/
 mov  ax,word ptr [esi+4]               ;\[4]=tindex2           ;\
 mov  word ptr [edi+4],ax               ;/[5]=force_preflag     ; extra info
;mov  word ptr [edi+6],0                ;-[6..7]=unused/padding ;/
 add  edi,8                     ;\
 inc  edx       ;curr.index     ; next
 cmp  edx,512+512               ;
 jb   short @@lop               ;/
 ret
;------------------
mp3_any_init_huff_tables:
 mov  ebp,offset huff_tree_list_data                            ;\
 mov  esi,offset huff_tree_list_numbits                         ;
 mov  edx,1     ;idx (table 01h..11h)                           ;
@@huffman_table_lop:                                            ;
 xor  eax,eax                           ;\                      ; huffman
 mov  edi,offset mp3_huff_tmp_bits      ;                       ; decode
 mov  ecx,100h/4   ;100h x 8bit         ; clear tmp             ; tables
 rep  stosd                             ;                       ;
 mov  edi,offset mp3_huff_tmp_codes     ;                       ;
 mov  ecx,100h/2   ;100h x 16bit        ;                       ;
 rep  stosd                             ;/                      ;
 xor  ebx,ebx   ;huffcode                               ;\      ;
@@huff_entry_lop:                                       ;       ;
 moz  edi,byte ptr [ebp]  ;dst=data             ;\data  ;       ;
 inc  ebp                                       ;/      ;       ;
 lodsb          ;numbits                        ;\bits  ;       ;
 mov  byte ptr [mp3_huff_tmp_bits+edi*1],al     ;/      ;       ;
 mov  cl,32     ;32                             ;\      ;       ;
 sub  cl,al     ;32-numbits                     ; codes ;       ;
 shr  ebx,cl    ;shift down to LSBs             ;       ;       ;
 mov  word ptr [mp3_huff_tmp_codes+edi*2],bx    ;/      ;       ;
 inc  ebx       ;next.code                              ;       ;
 shl  ebx,cl    ;shift back to MSBs                     ;       ;
 jnz  short @@huff_entry_lop                            ;/      ;
 pusha                                           ;\             ;
 mov  eax,100h              ;nb_codes            ;              ;
 mov  ebx,offset mp3_huff_tmp_bits   ;bits       ; make table   ;
 mov  esi,offset mp3_huff_tmp_codes  ;codes      ;              ;
;mov  edx,edx   ;idx (1..15)                     ;              ;
 call mp3_build_huff_table_root                  ;              ;
 popa                                            ;/             ;
 inc  edx       ;idx                    ;\                      ;
 cmp  edx,12h                           ; next table            ;
 jnz  short @@huffman_table_lop         ;/                      ;/
;- - -
 IF log_init
   mov  edx,offset txt_huff_tree_size   ;\
   call wrstr_edx                       ;/
   mov  eax,dword ptr [mp3_huff_num_entries]
   shl  eax,2   ;mul4 (2x16bit per entry)
   call wrhexeax    ;CHILD_BITS=size: 10=B448h
   call wrcrlf
 ENDIF
 ret
;------------------
;:----------------- Mp3 code init integer (replacing old float init)
;------------------
mp3_integer_init_is_stereo_lsf:
 ;this creates 4 tables with 64 dword-pairs
 ;minimp3 did have only 16 pairs (but mp3 needs 32, and mp1/mp2 even needs 64)
 ;table 1/3 are stepping twice as fast (as selected in scalefac_compress.bit0)
 ;table 2/3 are same as table 0/1, but multiplied by 1.414 for MS_STEREO)
 ;- - -
 xor  edi,edi
@@lsf_lop:
 mov  esi,edi                           ;\
 and  esi,3fh                           ;
 inc  esi                               ;
 shr  esi,1                             ;/
 test edi,1*40h                         ;\
 jz   short @@lsf_no_shift              ;
 shl  esi,1                             ;
@@lsf_no_shift:                         ;/
 mov  edx,40000000h    ;\aka mul 1.000  ;\
 add  esi,4            ;/               ;
 test edi,2*40h                         ;
 jz   short @@no_ms_stereo              ;
 mov  edx,2D413CCDh*2  ;\aka mul 1.414  ;
 sub  esi,2            ;/               ;
@@no_ms_stereo:                         ;/
 mov  ecx,esi
 shr  ecx,2     ;msbs
 and  esi,03h   ;lsbs
 mov  eax,dword ptr [mp3_is_table_lsf_src+esi*4]
 shr  eax,cl
 test edi,1                             ;\
 jnz  short @@lsf_no_swap               ;
 xchg eax,edx                           ;
@@lsf_no_swap:                          ;/
 mov  dword ptr [mp3_is_table_lsf+edi*8+0],eax
 mov  dword ptr [mp3_is_table_lsf+edi*8+4],edx
 inc  edi
 cmp  edi,4*40h
 jb   short @@lsf_lop
 ret
;------------------
mp3_integer_init_mdct_windows:
;XXX could compute the "mp3_mdct_win_src" values as sine/cosine
;(similar as done in original floating point version, if that would be smaller)
;- - -
 mov  edi,offset mp3_mdct_win                                   ;\
 mov  esi,offset mp3_mdct_win_src                               ; block 0..3
 mov  ecx,36*4                                                  ;
 rep  movsd                                                     ;/
;- - -
 mov  esi,offset mp3_mdct_win                                   ;\
 mov  edi,offset mp3_mdct_win+4*36*4                            ;
 mov  ecx,4*36/2   ;that is, 4*36 entry pairs                   ; mdct
@@mdct_lop_dupe:                                                ; dupes,
 movsd          ;-copy normal,  [4..7][even] = +[0..3][even]    ; with each
 lodsd          ;\                                              ; 2nd entry
 neg  eax       ; copy negated, [4..7][odd]  = -[0..3][odd]     ; negated
 stosd          ;/                                              ;
 loop short @@mdct_lop_dupe                                     ;/
 ret
;------------------
mp3_integer_init_table_4_3:
 IF with_fast_option                        ;\
   cmp  byte ptr [option_fast],0            ;
   mov  al,100-6-VFRAC_BITS_slow            ;
   jz   short @@this_vfrac                  ;
   mov  al,100-6-VFRAC_BITS_fast            ;
  @@this_vfrac:                             ;
   mov  byte ptr [mp3_curr_vfrac_bits],al   ;
 ENDIF                                      ;/
;- - -
 xor  edi,edi   ;i              ;0..803Bh                       ;\
@@table_4_3_lop:   ;for i=1 to TABLE_4_3_SIZE-1                 ; compute n ^ (4/3) and store it in mantissa/exp format
 push edi
 mov  eax,edi   ;val=i          ;0..803Bh                       ;
 shr  eax,2     ;val=i/4        ;0..200Eh           ;n          ;
 mul  eax                       ;0..40380C4h        ;n^(2)      ;
 mul  eax                       ;0..101C12655C9610h ;n^(4)      ;
 xor  ebx,ebx                   ;96bit ebx:edx:eax  ;n^(4)      ;
 call cbrt96    ;out: ebx,cl    ;0..2868Ch+fraction ;n^(4/3)    ;
 IF with_fast_option
   add  cl,byte ptr [mp3_curr_vfrac_bits]
 ELSE
   add  cl,100-6-VFRAC_BITS_default    ;+4Fh
 ENDIF
 pop  edi
@@inner_lop:
 mov  eax,edi   ;exp=i          ;0..803Bh
 and  eax,3     ;exp=i AND 3    ;0..3
 mov  eax,dword ptr [mp3_pow2_quarters+eax*4]       ;2^(x/4)
 mul  ebx
 mov  ch,cl
 or   edx,edx           ;\
 jns  short @@this      ; ensure that sign bit
 shr  edx,1  ;val/2     ; isn't set
 dec  ch     ;exp-1     ;
@@this:                 ;/
 IF MERGE_TABLE_4_3
   mov  dl,ch
 ENDIF
 mov  dword ptr [mp3_table_4_3_value+edi*4],edx  ;-value
 mov  byte ptr [mp3_table_4_3_exp+edi],ch        ;-exp
 inc  edi                                                       ;
 test edi,3
 jnz  short @@inner_lop
 cmp  edi,TABLE_4_3_SIZE                                        ;
 jb   short @@table_4_3_lop                                     ;/
 ret
;------------------
mp3_integer_init_exponent:    ;requires prior "mp3_table_4_3_xxx" init!
 mov  edi,offset mp3_expval_table                               ;\
 xor  edx,edx   ;i                                              ;
@@exponent_lop:                                                 ; exponent
 mov  eax,edx   ;val=i                           ;0..1FFFh      ;
 mov  ebx,edx                                    ;0..1FFFh      ;
 mov  ecx,edx                                    ;0..1FFFh      ;
 shr  ebx,4                                                     ;
 shr  ecx,4+2                                    ;0..7Fh        ;
 and  eax,0fh   ;val=i AND 0Fh                   ;0..0Fh        ;
 and  ebx,03h                                    ;0..3          ;
 lea  ebx,[eax*4+ebx]   ;(0..0Fh)*4+(0..3)                      ;
 mov  eax,dword ptr [mp3_table_4_3_value+ebx*4]  ;-val          ;
 IF MERGE_TABLE_4_3
   and  eax,0ffffff00h
 ENDIF
 or   eax,eax           ;\ignore exponent when val=0            ;
 jz   short @@this      ;/                                      ;
 sub  cl,byte ptr [mp3_table_4_3_exp+ebx]        ;-exp          ;
 ja   short @@left_shift                                        ;
 neg  cl                                                        ;
 shr  eax,cl                                                    ;
 cmp  cl,31                                                     ;
 jbe  short @@this                                              ;
 xor  eax,eax   ;force zero (for CPUs that can't use shift>31)  ;
 jmp  short @@this                                              ;
;---                                                            ;
@@left_shift:                                                   ;
 ;left-shifting would overflow, so set some max value instead   ;
 mov  eax,7fffffffh                                             ;
@@this:                                                         ;
                IF 0;1  ;dunno, MAYBE needed to avoid overflows?
                  cmp  eax,7fffffffh/10h  ;XXX
                  jbe  short @@okk
                  mov  eax,7fffffffh/10h
                 @@okk:
                ENDIF
 stosd                                                          ;
 inc  edx       ;i                                              ;
 cmp  edx,200h*10h                                              ;
 jb         @@exponent_lop                                      ;/
 mov  esi,offset mp3_expval_table                               ;\
 mov  edi,offset mp3_exp_table                                  ;
 mov  ecx,200h                                                  ; exponent
@@exponent_dupe_lop:                                            ; dupes
 mov  eax,dword ptr [esi+4]  ;src[n][1]                         ;
 stosd                       ;dst[n]                            ;
 add  esi,4*10h                                                 ;
 loop short @@exponent_dupe_lop                                 ;/
 ret
;------------------
cbrt96:   ;cube root, val^(1/3), from https://gist.github.com/anonymous/729557
 ;in:  ebx:edx:eax = unsigned 96bit input (integer)
 ;out: ebx         = unsigned 32bit result (with fractional bits)
 ;out: cl          = number of fractional bits
 ;- - -
 sub  esp,18h   ;alloc 6 dwords
 mov  dword ptr [esp+00h],eax           ;\
 mov  dword ptr [esp+04h],edx           ;
 mov  dword ptr [esp+08h],ebx           ; init
 mov  dword ptr [esp+0ch],0             ;
 mov  dword ptr [esp+10h],0             ;
 mov  dword ptr [esp+14h],0             ;
 xor  ebx,ebx   ;result.value           ;
 mov  cl,0      ;result.fraction        ;/
 or   eax,edx   ;skip if zero           ;\
 jz   short @@pre_shift_done            ;
@@pre_shift_lop:                        ;
 test dword ptr [esp+08h],0e0000000h    ;
 jnz  short @@pre_shift_done            ; add as many fractional bits
 REPT 3                                 ; as possible
   shl  dword ptr [esp+00h],1           ;
   rcl  dword ptr [esp+04h],1           ;
   rcl  dword ptr [esp+08h],1           ;
 ENDM                                   ;
 inc  cl        ;result.fraction        ;
 jmp  short @@pre_shift_lop             ;
@@pre_shift_done:                       ;/
;- - -
 mov  ch,20h    ;lopcount
@@lop:
 add  ebx,ebx   ;result*2
 mov  eax,ebx                   ;-y
 inc  ebx       ;result+1       ;-(y+1)
 mul  ebx                       ;-y*(y+1)
 mov  esi,eax                   ;\
 mov  edi,edx                   ; y*(y+1)*1
 xor  ebp,ebp                   ;/
 stc                            ;\
 adc  esi,esi                   ; y*(y+1)*2+1
 adc  edi,edi                   ;
 adc  ebp,ebp                   ;/
 add  esi,eax                   ;\
 adc  edi,edx                   ; y*(y+1)*3+1
 adc  ebp,0                     ;/
 REPT 3                         ;\
   shl  dword ptr [esp+00h],1   ;
   rcl  dword ptr [esp+04h],1   ;
   rcl  dword ptr [esp+08h],1   ; shl 3
   rcl  dword ptr [esp+0ch],1   ;
   rcl  dword ptr [esp+10h],1   ;
   rcl  dword ptr [esp+14h],1   ;
 ENDM                           ;/
 sub  dword ptr [esp+0ch],esi   ;\
 sbb  dword ptr [esp+10h],edi   ; sub/compare
 sbb  dword ptr [esp+14h],ebp   ;
 jae  short @@next              ;/
 dec  ebx       ;result-1       ;\
 add  dword ptr [esp+0ch],esi   ; undo
 adc  dword ptr [esp+10h],edi   ;
 adc  dword ptr [esp+14h],ebp   ;/
@@next:
 dec  ch        ;lopcount
 jnz  short @@lop
 add  esp,18h   ;dealloc 6 dwords
 ret
;------------------
;:----------------- Mp3 code init log
;------------------
mp3_init_log_constants:
IF log_init EQ 0
 ret
ELSE ;................
;- - -
 mov  ebx,offset log_init_list                  ;\table list...
@@log_list_lop:                                 ;/
 mov  edx,dword ptr [ebx+0]  ;txt               ;\name
 call wrstr_edx                                 ;/
 mov  esi,dword ptr [ebx+4]  ;src               ;\
 mov  edx,dword ptr [ebx+16] ;type              ;
 mov  ecx,dword ptr [ebx+8]  ;len.y             ;\
@@log_hex_lop_y:                                ; loop y
 push ecx                                       ;/
 mov  ecx,dword ptr [ebx+12] ;len.x             ;\
@@log_hex_lop_x:                                ; lopp x
 call wrspc                                     ;/
 cmp  edx,16
 je   short @@log_16bit
 cmp  edx,32
 je   short @@log_32bit
 cmp  edx,40
 je   short @@log_40bit
 cmp  edx,64
 je   short @@log_64bit
@@log_16bit:                                    ;\
 lodsw                                          ; log 16bit
 call wrhexax                                   ;
 jmp  short @@log_next                          ;/
@@log_32bit:                                    ;\
 lodsd                                          ; log 32bit
 call wrhexeax                                  ;
 jmp  short @@log_next                          ;/
@@log_40bit:                                    ;\
 mov  al,byte ptr [mp3_table_4_3_exp+esi]       ;
 call wrhexal                                   ; log table_4_3
 call wrspc                                     ;
 mov  eax,dword ptr [mp3_table_4_3_value+esi*4] ;
 call wrhexeax                                  ;
 inc  esi                                       ;
 jmp  short @@log_next                          ;/
@@log_64bit:                                    ;\
 REPT 6                                         ;
   lodsb                                        ; log lsf_sf_expand_exploded_table
   call wrhexal                                 ;
   call wrspc                                   ;
 ENDM                                           ;
 lodsw   ;skip/unused                           ;
 jmp  short @@log_next                          ;/
@@log_next:
 dec  ecx                                       ;\next x
 jnz        @@log_hex_lop_x                     ;/
 pop  ecx                                       ;\
 call wrcrlf                                    ; next y
 dec  ecx                                       ;
 jnz        @@log_hex_lop_y                     ;/
 add  ebx,5*4                                   ;\
 cmp  dword ptr [ebx+0],0    ;txt               ; next table
 jnz        @@log_list_lop                      ;/
 ret
;------------------
log_huffman_tree:
 ;in: eax = nb_codes      (eg. 16 or 256)
 ;in: ebx = ptr to bits
 ;in: esi = ptr to codes
 ;in: edx = parent/root index
 ;---
 pusha
 push edx
 mov  edx,offset txt_huff_tree
 call wrstr_edx
 pop  edx
 mov  ebp,eax  ;nb_codes
 xor  edi,edi  ;index (aka data)
@@lop:
 cmp  byte ptr [ebx+edi],0   ;bits
 jz   short @@skip
 mov  eax,edx                   ;\tree.number
 call wrhexal                   ;/
 call wrspc
 IF 0
   mov  eax,edi                   ;\prio
   shl  eax,4                     ; ordered SOMEWHAT as so,
   shr  al,4                      ; but not exactly :/
   cmp  al,ah                     ;
   ja   short @@this_prio         ;
   xchg al,ah                     ;
  @@this_prio:                    ;
   shl  al,4                      ;
   or   al,ah                     ;
   call wrhexal                   ;/
   call wrspc
 ENDIF
 moz  eax,byte ptr [ebx+edi]    ;\num-bits, not including 0..2 sign bit(s)
 call wrhexal                   ;/
 call wrspc
 mov  eax,edi                   ;\index (aka data)
 call wrhexal                   ;/
 call wrspc
 moz  ecx,byte ptr [ebx+edi]    ;\
 moz  eax,word ptr [esi+edi*2]  ; huffcode
 ror  eax,cl                    ;
@@digit_lop:                    ;
 mov  al,00h                    ;
 rol  eax,1                     ;
 call wrdigital                 ;
 loop short @@digit_lop         ;/
 call wrcrlf
@@skip:
 inc  edi      ;index
 cmp  edi,ebp  ;index,nb_codes
 jb   short @@lop
 popa
 ret
ENDIF ;log_init
;------------------
;:----------------- Mp3 code init huffman
;------------------
mp3_build_huff_table_root:      ;"init_vlc"
 ;in: eax = nb_codes      (eg. 16 or 256)
 ;in: ebx = ptr to bits
 ;in: esi = ptr to codes
 ;in: edx = parent/root index
 ;out: eax = base index of new table
 ;---
 .data
  mp3_initialized       dd 0  ;initially 0
  mp3_huff_num_entries  dd 12h  ;initially 12h (with reserved/pre-alloc: 0=unused, 01h..0Fh=table[1..15], 10h..11h=quad[0..1])
 .code
 ;---
 .data?
  @@table_nb_bits    dd ?
  @@nb_codes         dd ?
  @@prefix_numbits   dd ?
  @@prefix_pattern   dd ?
  @@curr_table_size  dd ?
  @@curr_table_mask  dd ?
  @@curr_table_index dd ?
 .code
 ;---
 IF log_init
   call log_huffman_tree
 ENDIF
 mov  dword ptr [@@nb_codes],eax
 mov  dword ptr [@@prefix_numbits],0   ;"n_prefix"     ;\zero for root
 mov  dword ptr [@@prefix_pattern],0   ;"code_prefix"  ;/
 pusha                                  ;\
 mov  ecx,eax    ;num_codes             ;
 xor  eax,eax                           ; make root table as small as possible
@@prescan_lop:                          ; (this allows better/faster caching)
 cmp  al,byte ptr [ebx]                 ; (original minimp3 didn't do that, and
 ja   short @@prescan_next              ; did instead force CHILD_BITS=7 for
 mov  al,byte ptr [ebx]                 ; most root tables)
@@prescan_next:                         ;
 inc  ebx                               ;
 loop short @@prescan_lop               ;
 cmp  al,CHILD_BITS                     ;
 jb   short @@prescan_this_limit        ;
 mov  al,CHILD_BITS                     ;
@@prescan_this_limit:                   ;
 mov  dword ptr [@@table_nb_bits],eax   ;
 popa                                   ;/
;- - - - - - ------
@@mp3_build_huff_table_recursive_child:
 mov  ecx,dword ptr [@@table_nb_bits]                                    ;\
 mov  eax,1                                                              ;
 shl  eax,cl                                                             ; size
 mov  dword ptr [@@curr_table_size],eax                                  ;
 dec  eax                                                                ;
 mov  dword ptr [@@curr_table_mask],eax                                  ;/
 pusha                                                                   ;\
 mov  ebx,dword ptr [mp3_huff_num_entries]                               ;
 mov  dword ptr [@@curr_table_index],ebx   ;<-- base index for new block ; grow
 add  ebx,dword ptr [@@curr_table_size]    ;<-- add size of new block    ; and throw error
 mov  dword ptr [mp3_huff_num_entries],ebx                               ; when exceeding the pre-allocated buf size
 cmp  dword ptr [mp3_huff_num_entries],HUFF_TREE_SIZE/4  ;\              ;
 ja   fatalunexpected                                    ;/              ;
 popa                                                                    ;/
;---
 mov  edi,offset huff_tree_buf                          ;\
;mov  edx,edx   ;parent index                           ; let parent/root index
 mov  eax,dword ptr [@@curr_table_index]                ; point to new table
 mov  word ptr [edi+edx*4+0],ax     ;table[i].codes     ;
 mov  eax,dword ptr [@@table_nb_bits]                   ;  ;<-- even so when less needed for small tables?
 neg  eax   ;make negative (indicate this is a parent)  ;
 mov  word ptr [edi+edx*4+2],ax     ;table[i].bits      ;/
;---
 mov  edi,offset huff_tree_buf                          ;\
 mov  edx,dword ptr [@@curr_table_index]                ;
 mov  ecx,dword ptr [@@curr_table_size]                 ; initially mark all
@@clear_table_lop:                                      ; new table entries as
 mov  word ptr [edi+edx*4+0],-1     ;table[i].codes     ; unused
 mov  word ptr [edi+edx*4+2],0      ;table[i].bits      ;
 inc  edx                                               ;
 loop short @@clear_table_lop                           ;/
;---
 push ebx       ;bits                                   ;\
 push esi       ;codes                                  ;
 xor  edx,edx   ;aka 16bit dx                           ;
@@make_table_lop:                                       ;
 moz  ecx,byte ptr [ebx]   ;n    = bits[i]   ;8bit      ;
 moz  eax,word ptr [esi]   ;code = codes[i]  ;16bit     ;
 sub  ecx,dword ptr [@@prefix_numbits]  ;n -= n_prefix  ; ;\
 jle  short @@make_table_lop_next                       ; ; check if desired
 shr  eax,cl    ;code SHR n                             ; ; child (or root)
 cmp  eax,dword ptr [@@prefix_pattern]                  ; ;
 jne  short @@make_table_lop_next                       ; ;/
 mov  edi,offset huff_tree_buf                          ; ;\
 moz  eax,word ptr [esi]   ;code = codes[i]  ;16bit     ; ;/
 sub  ecx,dword ptr [@@table_nb_bits]                   ; ;\check if data/child
 ja   short @@create_child_table                        ; ;/
 neg  ecx                                               ; ;\
 shl  eax,cl                                            ; ;
 and  eax,dword ptr [@@curr_table_mask]                 ; ; cast data entry
 add  eax,dword ptr [@@curr_table_index]                ; ; (or multiple
 lea  edi,[edi+eax*4]                                   ; ; mirrors for
 mov  eax,1                                             ; ; short huffcodes)
 shl  eax,cl                                            ; ;
 mov  ecx,eax                                           ; ;
 moz  eax,byte ptr [ebx]   ;n    = bits[i]   ;8bit      ; ;
 sub  eax,dword ptr [@@prefix_numbits]  ;n -= n_prefix  ; ;
@@make_rept_lop:                                        ; ; ;\
 cmp  word ptr [edi+2],0      ;table[i].bits            ; ; ;
 jnz  fatalunexpected  ;oops, already used              ; ; ;
 mov  word ptr [edi+0],dx     ;table[i].codes (aka DATA); ; ;
 mov  word ptr [edi+2],ax     ;table[i].bits            ; ; ;
 add  edi,4                                             ; ; ;
 loop short @@make_rept_lop                             ; ; ;/
 jmp  short @@make_table_lop_next                       ; ;/
;---
@@create_child_table:                                   ; ;\
 shr  eax,cl                                            ; ;
 and  eax,dword ptr [@@curr_table_mask]                 ; ; mark as child table
 add  eax,dword ptr [@@curr_table_index]                ; ; (with "-numbits")
 neg  ecx   ;negative numbits (indicate child)          ; ; (unless already
 cmp  word ptr [edi+eax*4+2],cx     ;table[i].bits      ; ; marked with taller
 jl   short @@already_more_negative   ;already taller   ; ; "-numbits")
 mov  word ptr [edi+eax*4+2],cx     ;table[i].bits      ; ;
@@already_more_negative:                                ; ;/
;- - -                                                  ;
@@make_table_lop_next:                                  ;
 add  esi,2     ;codes                                  ;
 inc  ebx       ;bits                                   ;
 inc  edx       ;index                                  ;
 cmp  edx,dword ptr [@@nb_codes]                        ;
 jb         @@make_table_lop                            ;
 pop  esi       ;codes                                  ;
 pop  ebx       ;bits                                   ;/
;---
 mov  ecx,dword ptr [@@curr_table_size]                 ;\
 mov  edx,dword ptr [@@curr_table_index]                ;
@@make_child_tables_lop:                                ;
 mov  edi,offset huff_tree_buf
 movsx eax,word ptr [edi+edx*4+2]   ;table[i].bits
 cmp  eax,0                                     ;\check if this is a new child
 jns  short @@make_child_tables_lop_next        ;/(with numbits=negative)
 neg  eax  ;make positive (if it was negative)  ;-
 cmp  eax,dword ptr [@@table_nb_bits]   ;\
 jbe  short @@make_child_tables_this    ; limit
 mov  eax,dword ptr [@@table_nb_bits]   ; (usually max 7) (CHILD_BITS)
@@make_child_tables_this:               ;/
 push ecx                               ;\
 push edx                               ;
 push dword ptr [@@curr_table_index]    ;
 push dword ptr [@@table_nb_bits]       ;
 push dword ptr [@@prefix_numbits]      ;
 push dword ptr [@@prefix_pattern]      ;/
 mov  ecx,dword ptr [@@table_nb_bits]                                   ;\
 mov  dword ptr [@@table_nb_bits],eax            ;-                     ;
 add  dword ptr [@@prefix_numbits],ecx           ;-                     ;
 shl  dword ptr [@@prefix_pattern],cl            ;\                     ; build_table
 mov  eax,edx                                    ;                      ;
 sub  eax,dword ptr [@@curr_table_index]         ;                      ;
 or   dword ptr [@@prefix_pattern],eax           ;/                     ; (child)
 call @@mp3_build_huff_table_recursive_child      ;--> ax (child index) ;/
 pop  dword ptr [@@prefix_pattern]      ;\
 pop  dword ptr [@@prefix_numbits]      ;
 pop  dword ptr [@@table_nb_bits]       ;
 pop  dword ptr [@@curr_table_index]    ;
 pop  edx                               ;
 pop  ecx                               ;/
@@make_child_tables_lop_next:                           ;
 inc  edx               ;index                          ;
 loop short @@make_child_tables_lop                     ;/
;- - -
 ret
;------------------
;:----------------- Mp3 code extras (id3,tag,xing,free format)
;------------------
xlat_4x7bit_to_28bit macro
 xchg al,ah     ;\
 shl  al,1      ;
 shl  ax,1      ; repair endianess,
 shr  ax,2      ; and convert 4x7bit
 ror  eax,16    ; to 28bit
 xchg al,ah     ;
 shl  al,1      ;
 shl  ax,1      ;
 shr  eax,2     ;/
endm
;------------------
mp3_exclude_id3_and_tag:   ;io: [stream_pos],[bytes_left]
;exclude ID3 and/or TAG from bitstream.
;alternately they may be automatically excluded when searching for sync marks,
;but that can fail if ID3 contains binary data.
;for example, the ID3 part in my "Infant Sanchos - Der Kaiset" file contains a
;huge 1.1Mbyte PNG with several sync-like FFh,Fxh byte sequences.
;- - -
 mov  esi,dword ptr [stream_pos]                ;\get addr,len
 mov  ecx,dword ptr [bytes_left]                ;/
;- - -
 cmp  ecx,10                            ;\ID3 min size
 jb   short @@no_id3                    ;/
 mov  eax,dword ptr [esi+00h]           ;\
 and  eax,0ffffffh                      ; ID3 identifier
 cmp  eax,'3DI'   ;"ID3"                ;
 jne  short @@no_id3                    ;/
 mov  eax,dword ptr [esi+06h]           ;\
 test eax,80808080h                     ;
 jnz  short @@no_id3                    ; get size, big-endian, 4x7bit
 xlat_4x7bit_to_28bit                   ;
 add  eax,10    ;-add ID3 header size   ;
 cmp  ecx,eax                           ;
 jb   short @@no_id3                    ;/
 add  esi,eax   ;raise addr             ;\skip ID3 stuff
 sub  ecx,eax   ;decrease size          ;/
 IF log_file_info
   mov  dword ptr [mp3_id3_size],eax
 ENDIF
@@no_id3:
;- - -
 IF with_all_footer_tags
  @@footer_tag_retry_lop:
   mov  edx,80h                         ;\
   cmp  ecx,edx                         ;
   jb   short @@no_tag_or_ext           ; "TAG" or "EXT"
   mov  eax,dword ptr [esi+ecx-80h]     ; (80h bytes each)
   and  eax,0ffffffh                    ;
   cmp  eax,'GAT'   ;"TAG"          ;\  ;
   je         @@got_tag_size_edx    ;/  ;
   cmp  eax,'TXE'   ;"EXT"          ;\  ;
   je         @@got_tag_size_edx    ;/  ;
  @@no_tag_or_ext:                      ;/
  ;- - -
   mov  edx,0e3h                        ;\
   cmp  ecx,edx                         ;
   jb   short @@no_tagplus              ; "TAG+"
   cmp  dword ptr [esi+ecx-0e3h],'+GAT' ; (E3h bytes)
   je         @@got_tag_size_edx        ;
  @@no_tagplus:                         ;/
  ;- - -
   mov  edx,10+10                       ;\
   cmp  ecx,edx                         ;
   jb   short @@no_3di                  ; "3DI",04h
   cmp  dword ptr [esi+ecx-10],'ID3'+4000000h
   jne  short @@no_3di                  ;
   test byte ptr [esi+ecx-5],10h  ;bit4 ;
   jz   short @@no_3di                  ;
   mov  eax,dword ptr [esi+ecx-4]       ;
   test eax,80808080h                   ;
   jnz  short @@no_3di                  ;
   xlat_4x7bit_to_28bit                 ;
   lea  edx,[eax+10+10] ;hdr+footer siz ;
   jmp        @@got_tag_size_edx        ;
  @@no_3di:                             ;/
  ;- - -
   cmp  dword ptr [esi+ecx-32+0],'TEPA'     ;\
   jne  short @@no_ape                      ; check "APETAGEX"
   cmp  dword ptr [esi+ecx-32+4],'XEGA'     ;
   jne  short @@no_ape                      ;/
   mov  edx,dword ptr [esi+ecx-32+0ch]      ;-get size
   test dword ptr [esi+ecx-32+14h],1 shl 31 ;\
   jz   short @@no_ape_header               ; test has-hdr-flag
   add  edx,20h   ;hdr.size                 ; and add hdrsiz, if any
  @@no_ape_header:                          ;/
   jmp        @@got_tag_size_edx            ;-
  @@no_ape:
  ;- - -
   mov  edx,11+9                        ;\
   cmp  ecx,edx                         ;
   jb   short @@no_lyrics               ; "LYRICSEND" or "LYRICS200"
   cmp  dword ptr [esi+ecx-9+0],'IRYL'  ; (11+N+9 bytes each)
   jne  short @@no_lyrics               ;
   cmp  byte ptr [esi+ecx-9+4],'C'      ;
   jne  short @@no_lyrics               ;
   cmp  dword ptr [esi+ecx-9+5],'DNES'  ;
   je   short @@lyrics3_v1              ;
   cmp  dword ptr [esi+ecx-9+5],'002S'  ;
   je   short @@lyrics3_v2              ;
   jne  short @@no_lyrics               ;
  ;---                                  ;
  @@lyrics3_v1:                         ;  ;\
   mov  edx,11+9                        ;  ;
  @@lyrics3_v1_size_lop:                ;  ;
   lea  eax,[esi+ecx]                   ;  ; lyrics3 v1
   sub  eax,edx                         ;  ;
   cmp  dword ptr [eax+0],'IRYL'        ;  ;
   jne  short @@lyrics3_v1_size_next    ;  ;
   cmp  dword ptr [eax+4],'EBSC'        ;  ;
   jne  short @@lyrics3_v1_size_next    ;  ;
   cmp  dword ptr [eax+7],'NIGE'        ;  ;
  ;jne  short @@lyrics3_v1_size_next    ;  ;
   je   short short @@got_tag_size_edx  ;  ;
  @@lyrics3_v1_size_next:               ;  ;
   inc  edx                             ;  ;
   cmp  edx,5120                        ;  ;
   ja   short @@no_lyrics               ;  ;
   cmp  edx,ecx                         ;  ;
   jbe  short @@lyrics3_v1_size_lop     ;  ;/
   jmp  short @@no_lyrics               ;
  ;---                                  ;
  @@lyrics3_v2:                         ;  ;\
   push ecx                             ;  ;
   push esi                             ;  ;
   lea  esi,[esi+ecx-6-9]               ;  ;
   mov  ecx,6                           ;  ;  lyrics3 v2
   xor  edx,edx                         ;  ;
  @@lyrics3_v2_size_lop:                ;  ;
   imul edx,10                          ;  ;
   moz  eax,byte ptr [esi]              ;  ;
   inc  esi                             ;  ;
   sub  al,30h                          ;  ;
   add  edx,eax                         ;  ;
   loop short @@lyrics3_v2_size_lop     ;  ;
   pop  esi                             ;  ;
   pop  ecx                             ;  ;
   add  edx,6+9                         ;  ;
   jmp  short short @@got_tag_size_edx  ;  ;/
  @@no_lyrics:                          ;/
   jmp  short @@footer_tag_all_done
  ;---
  @@got_tag_size_edx:
       IF 1
        mov  eax,edx
        call wr_decimal_eax
        call wrcrlf
       ENDIF
   sub  ecx,edx   ;decrease size          ;-exclude TAG stuff
   jb   fatalunexpected
   IF log_file_info
     add  dword ptr [mp3_tag_size],edx
   ENDIF
   jmp  @@footer_tag_retry_lop
  @@footer_tag_all_done:
 ENDIF
;- - -
 IF with_all_footer_tags EQ 0   ;cut-down variant (only check for TAG)
   cmp  ecx,80h                           ;\TAG size
   jb   short @@no_tag                    ;/
   mov  eax,dword ptr [esi+ecx-80h]       ;\
   and  eax,0ffffffh                      ; TAG identifier
   cmp  eax,'GAT'   ;"TAG"                ;
   jne  short @@no_tag                    ;/
   sub  ecx,80h   ;decrease size          ;-exclude TAG stuff
   IF log_file_info
     mov  dword ptr [mp3_tag_size],80h
   ENDIF
  @@no_tag:
 ENDIF
;- - -
 mov  dword ptr [stream_pos],esi                ;\update addr,len
 mov  dword ptr [bytes_left],ecx                ;/
 ret
;------------------
IF with_free_format
  mp3_detect_free_format_block_size:   ;rarely used, eg. for l3-he_free.bit
   cmp  dword ptr [mp3_free_format_frame_size],0
   jnz        @@already_detected
   xor  edx,edx
  @@find_distance_lop:
   cmp  edx,dword ptr [mp3_src_remain]              ;\
   je   short @@match_eof                           ;/
   lea  eax,[edx+4]     ;min size (next hdr size)   ;\
   cmp  eax,dword ptr [mp3_src_remain]              ;
   ja   short @@find_distance_failed                ;/
   mov  eax,dword ptr [esi+edx]                     ;\
   call bswap_eax                                   ;
   xor  eax,dword ptr [mp3_hdr_32bit_header]        ;
   and  eax,0fffe0c00h  ;XXX plus bitrate=0=0=free  ;
   je   short @@try_confirm_match                   ;/
  @@find_distance_next:
   inc  edx
   cmp  edx,1000h  ;XXX whatever max block size
   jbe  short @@find_distance_lop
  @@find_distance_failed:
   stc     ;bad
   ret
  ;---
  @@match_eof:
  @@try_confirm_match:
   mov  eax,edx                                         ;\
   sub  eax,dword ptr [mp3_hdr_flag_padding]            ;
   cmp  eax,4           ;minimum distance (hdr size)    ;
   jb   short @@confirm_distance_bad                    ;
   mov  dword ptr [mp3_free_format_frame_size],eax      ;/
   xor  ebx,ebx
  @@confirm_distance_lop:
   mov  eax,dword ptr [esi+ebx]                     ;\
   call bswap_eax                                   ;
   shr  eax,9+1    ;padding.flag.bit9 to cy         ;
   adc  ebx,dword ptr [mp3_free_format_frame_size]  ;/
   cmp  ebx,dword ptr [mp3_src_remain]              ;\
   je   short @@confirm_distance_match_eof          ;/
   lea  eax,[ebx+4]     ;min size (next hdr size)   ;\
   cmp  eax,dword ptr [mp3_src_remain]              ;
   ja   short @@confirm_distance_bad                ;/
   mov  eax,dword ptr [esi+ebx]                     ;\
   call bswap_eax                                   ;
   xor  eax,dword ptr [mp3_hdr_32bit_header]        ;
   and  eax,0fffe0c00h  ;XXX plus bitrate=0=0=free  ;
   jnz  short @@confirm_distance_bad                ;/
                ;XXX limit to max 10 frames or so
   jmp  short @@confirm_distance_lop
  ;- - -
  @@confirm_distance_match_eof:
   IF log_file_info
     mov  eax,dword ptr [mp3_free_format_frame_size]    ;\
     shl  eax,3  ;mul8 (bits per byte)                  ;
     mul  dword ptr [mp3_sample_rate]                   ; average bitrate
     mov  ecx,dword ptr [mp3_nb_granules]               ;
     imul ecx,18*32                                     ;
     div  ecx                                           ;
     mov  dword ptr [mp3_bit_rate],eax                  ;/
     ;for example, l3-he_free.bit can be computed by filesize and duration:
     ;   (filesize*8/duration = bitrate)
     ;   (26645 bytes, 1802 ms, 118 kbit/s = 26645*8/1802)
     ;alternately (as done above), compute by blocksize and samplerate:
     ;   blocksize*8 * samplerate / (samples/block)
     ;   (391 bytes, 44100hz, (18*32*granules) = 119kbit/s = 391*8*44100/18/32/2)
     ;XXX should recurse AVERAGE blocksize WITH padding_bit=0..1
   ENDIF
  @@already_detected:
   clc     ;okay
   ret
  ;---
  @@confirm_distance_bad equ @@find_distance_next
ENDIF
;------------------
IF log_file_info
  mp3_check_xing_info:
   ;http://web.archive.org/web/20210126021629/http://www.mp3-tech.org/programmer/sources/vbrheadersdk.zip - xing specs, source code, and sample .mp3 file
   mov  dword ptr [mp3_xing_id],0
   mov  dword ptr [mp3_xing_frames],0
   mov  dword ptr [mp3_xing_filesize],0
   mov  esi,dword ptr [mp3_src_data_location]
   lodsd
   cmp  eax,'gniX'        ;"Xing" (VBR Variable BitRate info, by Xing and LAME encoders)
   je   short @@xing
  ;cmp  eax,'IRBV'        ;"VBRI" (VBR Variable BitRate info, by Fraunhofer encoder) (rarely used)
  ;je   short @@vbri
  ;cmp  eax,'ofnI'        ;"Info" (CBR Constant BitRate info) (same format as xing, but unknown what that's good for)
  ;je   short @@info
  ;cmp  eax,'EMAL'        ;"LAME" (version string and/or other stuff)
  ;je   short @@lame
  ;cmp  eax,'cvaL'        ;"Lavc" (version string and/or other stuff)
  ;je   short @@lame
  ;cmp  eax,'....'        ;"here are the ancillary-data !",0Dh,0Ah (in 0Eh-byte snippets) (*.bit sample files) (eg. l3-sin1k0db.bit)
  ;je   short @@lame
   ret
  ;---
  @@xing:
  @@info:
   mov  dword ptr [mp3_xing_id],eax   ;"Xing" or "Info"   ;-ID
   lodsd                                                  ;\
   call bswap_eax                                         ; flags
   mov  dword ptr [mp3_xing_flags],eax                    ;
   mov  edx,eax   ;flags                                  ;/
   test edx,1 shl 0                                       ;\
   jz   short @@no_xing_frames                            ;
   lodsd                                                  ; frames
   call bswap_eax                                         ;
   mov  dword ptr [mp3_xing_frames],eax                   ;
  @@no_xing_frames:                                       ;/
   test edx,1 shl 1                                       ;\
   jz   short @@no_xing_filesize                          ;
   lodsd                                                  ; filesize
   call bswap_eax                                         ;
   mov  dword ptr [mp3_xing_filesize],eax                 ;
  @@no_xing_filesize:                                     ;/
   test edx,1 shl 2                                       ;\
   jz   short @@no_xing_toc                               ;
   mov  ecx,100                                           ; toc
   mov  edi,offset mp3_xing_toc                           ;
   rep  movsb                                             ;
  @@no_xing_toc:                                          ;/
   test edx,1 shl 3                                       ;\
   jz   short @@no_xing_vbr_scale                         ;
   lodsd                                                  ; vbr scale
   call bswap_eax                                         ; (unknown purpose, xing stores something there, other encoders tend to set this to 0 or 64h)
   mov  dword ptr [mp3_xing_vbr_scale],eax                ;
  @@no_xing_vbr_scale:                                    ;/
  ;- - -
   mov  dword ptr [mp3_bit_rate],0                        ;\
   mov  eax,dword ptr [mp3_sample_rate]                   ;
   shl  eax,3   ;mul8 (bits)                              ; calc bits per second
   mul  dword ptr [mp3_xing_filesize]                     ;
   mov  ecx,dword ptr [mp3_xing_frames]                   ; filesize*8*samplerate / (frames*18*32*granules)
   imul ecx,dword ptr [mp3_nb_granules]                   ;
   imul ecx,18*32                                         ;
   cmp  edx,ecx                                           ;
   jae  short @@overflow                                  ;
   div  ecx                                               ;
   mov  dword ptr [mp3_bit_rate],eax                      ;
  @@overflow:                                             ;/
   ret
ENDIF
;------------------
;:----------------- Mp3 code decode frame
;------------------
align code_align
mp3_decode_frame:       ;in: esi=src, edi=dst, ecx=src_siz
;- - -
.data?
 align data_align
 @@granule_addr         dd ?   ;addr of ch0 of current granule
.code
;- - -
;mov  esi,esi                           ;src
 mov  dword ptr [mp3_src_remain],ecx    ;src_siz
 mov  dword ptr [mp3_samples_dst],edi   ;dst (0=none, examine hdr only)
;- - -
 call xmit_force_highest_priority
 timelog_start rdtsc_total
;- - -
 call mp3_search_get_header                     ;\header
 jc         @@error                             ;/
 mov  eax,dword ptr [mp3_src_frame_size]        ;\
 cmp  eax,0                                     ;
 jle        @@error  ;oops                      ; check buf size
 cmp  eax,dword ptr [mp3_src_remain]            ;
 ja         @@error  ;exceeds EOF               ;/
;- - -
 mov  dword ptr [mp3_bitstream_start],esi       ;\
 mov  eax,32    ;origin (after 32bit header)    ; start bitstream
 mp3mac_bitstream_set_position                  ;/
;- - -
 call mp3_bitstream_read_header_extra           ;-
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
 call mp3_bitstream_read_granules                       ;\
 jc         @@error                                     ;/
 call mp3_uncollect_bits   ;out: esi
 mov  dword ptr [mp3_src_data_location],esi  ;<-- possible location of Xing etc.
 cmp  dword ptr [mp3_samples_dst],0             ;\when dst=0, return only header
 jz         @@skip_decoding                     ;/info, without decoding data
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
 call mp3_bitstream_append_to_main_data_pool            ;-now main data ...
 cmp  dword ptr [mp3_samples_output_size],0     ;\skip if missing_main_data
 jz         @@skip_decoding                     ;/ (eg. l3-sin1k0db.bit)
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
 mov  dword ptr [mp3_curr_granule],0            ;\
 mov  ebx,offset mp3_granules                   ; loop granules
@@body_granule_lop:                             ;
 mov  dword ptr [@@granule_addr],ebx            ;/
 mov  dword ptr [mp3_curr_channel],0            ;\loop channels         ;\
@@body_channel_lop:                             ;/                      ;
        ;XXX should skip below when $mp3gr_part2_3_length = 0 (and then somehow replace all output by zeroes?)
        ;cmp  dword ptr [ebx+$mp3gr_part2_3_length],0
        ;jz   short @@body_channel_next
 mov  eax,dword ptr [ebx+$mp3gr_part2_3_start]  ;\                      ; read
 mp3mac_bitstream_set_position                  ;/                      ;
 call mp3_bitstream_read_scalefacs      ;-->    ;-read scale factors    ;
 call mp3_get_exponents_from_scale_factors ;in: ebx     ;-exponents     ;
 ;below reads up to $mp3gr_part2_3_end          ;\                      ;
 call mp3_huffman_decode  ;in: ebx      ;-->    ; read huffman coded residue
 jc         @@error                             ;/                      ;
;- - -                                                                  ;
        @@body_channel_next:
 add  ebx,$mp3gr_entrysiz*2                     ;\                      ;
 inc  dword ptr [mp3_curr_channel]              ;                       ;
 mov  eax,dword ptr [mp3_curr_channel]          ; next channel          ;
 cmp  eax,dword ptr [mp3_output_num_channels]   ;                       ;
 jb         @@body_channel_lop                  ;/                      ;/
;- - -
 mov  ebx,dword ptr [@@granule_addr]
 mp3mac_push_bitstream                                                  ;\
 call mp3_compute_stereo    ;in: ebx    ;-->    ;-stereo (if any)       ;
 mov  dword ptr [mp3_curr_channel],0            ;\loop channels         ; maths
@@cast_channel_lop:                             ;/                      ;
 call mp3_reorder_block     ;in: ebx    ;-->    ;-reorder               ;
 call mp3_compute_antialias ;in: ebx    ;-->    ;-antialias             ;
 call mp3_compute_imdct     ;in: ebx    ;-->    ;-imdct                 ;
 add  ebx,$mp3gr_entrysiz*2                     ;\                      ;
 inc  dword ptr [mp3_curr_channel]              ;                       ;
 mov  eax,dword ptr [mp3_curr_channel]          ; next channel          ;
 cmp  eax,dword ptr [mp3_output_num_channels]   ;                       ;
 jb   short @@cast_channel_lop                  ;/                      ;
 mp3mac_pop_bitstream                                                   ;/
;- - -
 mov  ebx,dword ptr [@@granule_addr]            ;\
 add  ebx,$mp3gr_entrysiz                       ;
 inc  dword ptr [mp3_curr_granule]              ; next granule
 mov  eax,dword ptr [mp3_curr_granule]          ;
 cmp  eax,dword ptr [mp3_nb_granules]           ;
 jb         @@body_granule_lop                  ;/
;- - -
 call mp3_uncollect_bits   ;out: esi    ;-->    ;\
 cmp  esi,dword ptr [main_data_pool_wr_ptr]     ; check that esi didn't exceed dword ptr [main_data_pool_wr_ptr]
 ja   short @@error                             ;/
;- - -
 call dword ptr [mp3_synth_filter_proc] ;-->    ;-synth maths           ;-output
;- - -
@@skip_decoding:
;- - -
 mov  eax,dword ptr [mp3_extra_bytes]           ;\add leading junk
 add  dword ptr [mp3_src_frame_size],eax        ;/to frame size
 mov  eax,dword ptr [mp3_samples_output_size]   ;\
 add  dword ptr [mp3_total_output_size],eax     ; for timelog/stats
 inc  dword ptr [mp3_num_frames_decoded]        ;/
;- - -
 ;out: dword ptr [mp3_output_num_channels]  ;num channels (1 or 2)
 ;out: dword ptr [mp3_src_num_channels]     ;num channels (1 or 2)
 ;out: dword ptr [mp3_src_frame_size]       ;compressed size (in bytes)
 ;out: dword ptr [mp3_samples_output_size]  ;decompressed size (in bytes)
 ;out: dword ptr [mp3_sample_rate]          ;sample rate (8000..48000 Hz)
;- - -
 timelog_end rdtsc_total
 call xmit_resume_normal_priority
 clc    ;okay
 ret
;---
@@error:
 timelog_end rdtsc_total
 call xmit_resume_normal_priority
 mov  eax,dword ptr [mp3_extra_bytes]           ;\add leading junk
 add  dword ptr [mp3_src_frame_size],eax        ;/to frame size
 stc    ;bad
 ret
;------------------
;:----------------- Mp3 code main
;------------------
mp3_init:
 mov  edi,offset mp3_context_start              ;\
 @@len equ (mp3_context_end-mp3_context_start)  ;
 ERRIF @@len AND 03h                            ; clear context
 mov  ecx,@@len/4                               ;
 xor  eax,eax                                   ;
 rep  stosd                                     ;/
 mov  dword ptr [main_data_pool_wr_ptr],offset main_data_pool_start  ;-intial pool start (any reference below there is treated as missing_main_data)
;- - -
 cmp  dword ptr [mp3_initialized],0             ;\
 jnz  @@already_initialized                     ;/
;call mp3_float_init_is_stereo_normal ;\small tables
;call mp3_float_init_csa_antialias    ;/  (XXX these could be computed as in old float version, maybe that could be smaller than the current pre-defined tables)
 call mp3_integer_init_is_stereo_lsf  ;\medium size
 call mp3_integer_init_mdct_windows   ;/
 call mp3_integer_init_table_4_3      ;\huge tables
 call mp3_integer_init_exponent       ;/
 call mp3_any_init_synth_window
 call mp3_any_init_band_indices
 call mp3_any_init_lsf_sf_expand
 call mp3_any_init_huff_tables
 call mp3_init_log_constants                    ;-show table contents
 call mp3_init_post_collapse                    ;-mzst be AFTER above init_log
 mov  dword ptr [mp3_initialized],1             ;-done
@@already_initialized:
 IF with_fast_option                        ;\          ;\
   moz  eax,byte ptr [option_fast]          ;           ;
 ELSE                                       ; fast      ; synth proc
   xor  eax,eax                             ;           ; options
 ENDIF                                      ;/          ;   accurate/fast
 mov  dword ptr [mp3_bytes_per_sample],2    ;\          ;   16bit/8bit
 IF with_8bit_output                        ;           ;   rate full half/quarter
   shl  eax,1                               ;           ;
   add  al,byte ptr [option_8bit]           ; 8bit      ;
   test al,1                                ;           ;
   jz   short @@not_8bit                    ;           ;
   mov  dword ptr [mp3_bytes_per_sample],1  ;           ;
  @@not_8bit:                               ;           ;
 ENDIF                                      ;/          ;
 IF with_rate_shift                         ;\          ;
   imul eax,3                               ; rate      ;
   add  al,byte ptr [option_rate_shift]     ;           ;
 ENDIF                                      ;/          ;
 mov  eax,dword ptr [mp3_synth_filter_procs+eax*4]      ;
 mov  dword ptr [mp3_synth_filter_proc],eax              ;/
 ret
;---
.const
mp3_synth_filter_procs:
 IF with_fast_option OR (prefer_dirty EQ 0)
  dd synth_16bit_shift_0_slow    ;16bit, full rate
  IF with_rate_shift
    dd synth_16bit_shift_1_slow  ;16bit, half rate
    dd synth_16bit_shift_2_slow  ;16bit, quarter rate
  ENDIF
  IF with_8bit_output
    dd synth_8bit_shift_0_slow    ;8bit, full rate
    IF with_rate_shift
      dd synth_8bit_shift_1_slow  ;8bit, half rate
      dd synth_8bit_shift_2_slow  ;8bit, quarter rate
    ENDIF
  ENDIF
 ENDIF
 IF with_fast_option OR (prefer_dirty)
  dd synth_16bit_shift_0_fast    ;16bit, full rate
  IF with_rate_shift
    dd synth_16bit_shift_1_fast  ;16bit, half rate
    dd synth_16bit_shift_2_fast  ;16bit, quarter rate
  ENDIF
  IF with_8bit_output
    dd synth_8bit_shift_0_fast    ;8bit, full rate
    IF with_rate_shift
      dd synth_8bit_shift_1_fast  ;8bit, half rate
      dd synth_8bit_shift_2_fast  ;8bit, quarter rate
    ENDIF
  ENDIF
 ENDIF
.code
;------------------
mp3_check_1st_frame:    ;io: [stream_pos],[bytes_left]
 call mp3_exclude_id3_and_tag           ;-
 mov  esi,dword ptr [stream_pos] ;src   ;\
 mov  ecx,dword ptr [bytes_left] ;siz   ;
 xor  edi,edi                    ;dst=0 ; decode frame header, get sample rate
 xor  ebp,ebp                    ;vals  ; (no data decode since dst=0)
 call mp3_decode_frame                  ;
 jc         @@error                     ;/
 IF log_file_info
   call mp3_check_xing_info             ;-check variable bitrate xing info
   mov  edx,offset txt_file_size                ;\      ;\
   call wrstr_edx                               ;/      ;
   mov  eax,dword ptr [mp3_file_size]           ;\      ;
   call wr_decimal_eax_with_thousands_seperator ;/      ; file and ID3/TAG sizes
   mov  edx,offset txt_id3_size                 ;\      ;
   call wrstr_edx                               ;/      ;
   mov  eax,dword ptr [mp3_id3_size]            ;\      ; ;<-- this may be up to 1.46 Mbyte in vandalized mp3 files (with hires lossless png bitmaps)
   call wr_decimal_eax_with_thousands_seperator ;/      ;
   mov  edx,offset txt_tag_size                 ;\      ;
   call wrstr_edx                               ;/      ;
   mov  eax,dword ptr [mp3_tag_size]            ;\      ;
   call wr_decimal_eax_with_thousands_seperator ;/      ;
   call wrcrlf                                          ;/
   mov  edx,offset txt_input                    ;\      ;\
   call wrstr_edx                               ;/      ;
   mov  eax,dword ptr [mp3_sample_rate]         ;\      ;
   call wr_decimal_eax                          ;       ; input
   mov  edx,offset txt_hz                       ;       ;
   call wrstr_edx                               ;/      ;
   mov  eax,dword ptr [mp3_src_num_channels]    ;\      ;
   call wr_decimal_eax                          ;       ;
   mov  edx,offset txt_channels                 ;       ;
   call wrstr_edx                               ;/      ;
   mov  eax,dword ptr [mp3_bit_rate]            ;\      ;
   xor  edx,edx                                 ;       ;
   mov  ecx,1000                                ;       ;
   div  ecx                                     ;       ;
   call wr_decimal_eax                          ;       ;
   mov  edx,offset txt_kbit_s                   ;       ;
   call wrstr_edx                               ;/      ;
   call wrcrlf                                          ;/
   mov  edx,offset txt_output                   ;\      ;\
   call wrstr_edx                               ;/      ;
   mov  eax,dword ptr [mp3_output_sample_rate]  ;\      ;
   call wr_decimal_eax                          ;       ; output
   mov  edx,offset txt_hz                       ;       ;
   call wrstr_edx                               ;/      ;
   mov  eax,dword ptr [mp3_output_num_channels] ;\      ;
   call wr_decimal_eax                          ;       ;
   mov  edx,offset txt_channels                 ;       ;
   call wrstr_edx                               ;/      ;
   mov  eax,dword ptr [mp3_bytes_per_sample]    ;\      ;
   shl  eax,3   ;mul8                           ;       ;
   call wr_decimal_eax                          ;       ;
   mov  edx,offset txt_bit                      ;       ;
   call wrstr_edx                               ;/      ;
   call wrcrlf                                          ;/
 ENDIF
 clc    ;okay
 ret
;---
@@error:
 stc    ;bad
 ret
;------------------
;note: the main public functons are:
;  mp3_init            ;to be called once
;  mp3_check_1st_frame ;to be called before playback
;  mp3_decode_frame    ;to be called each frame
;------------------
;:----------------- Mp3 end
;------------------
