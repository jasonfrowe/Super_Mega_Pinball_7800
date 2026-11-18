; ===========================================================================
; SUPER MEGA PINBALL 7800
;
; A 48K cart (linear, $4000-$FFFF) for the Atari 7800 with the AstroCart
; math unit ($0420-$043F) and two POKEYs ($0450, $0440).
;
;   $4000-$8FFF  table graphics (tools/table.py)
;   $9000-$9FFF  code: display engine, physics       (a DMA hole: no graphics)
;   $A000-$AFFF  sprites and the HUD font            (tools/sprites.py)
;   $B000-$BFFF  code: game rules                    (hole)
;   $C000-$CFFF  sprites
;   $D000-$DFFF  code: sound, music                  (hole)
;   $E000-$EFFF  table graphics
;   $F000-$FFFF  code: start, main loop, NMI, tables (hole)
;
; Holey DMA (16 lines) is on for the playfield: a sprite strip drawn across
; two zones reads zeros from the hole below its block.
; ===========================================================================

    processor 6502

; --- TIA / MARIA / RIOT ----------------------------------------------------
INPTCTRL = $01
INPT0    = $08
INPT1    = $09
INPT4    = $0C
AUDC0    = $15
AUDC1    = $16
AUDF0    = $17
AUDF1    = $18
AUDV0    = $19
AUDV1    = $1A
BACKGRND = $20
P0C1     = $21
WSYNC    = $24
MSTAT    = $28
DPPH     = $2C
DPPL     = $30
CHARBASE = $34
OFFSET   = $38
CTRL     = $3C
SWCHA    = $280
CTLSWA   = $281
SWCHB    = $282
CTLSWB   = $283
INTIM    = $284

; --- AstroCart math unit (docs/MATHUNIT.md) --------------------------------
M_X     = $0420     ; write X / read XR
M_Y     = $0422     ; write Y / read YR
M_T     = $0424     ; write T / read ANG
M_LEN   = $0426
M_A     = $0430     ; write A / read P0-15
M_B     = $0432     ; write B / read P16-31
M_P     = $0430
M_N     = $0434
M_Q     = $0434
M_D     = $0438
M_CTRL  = $043A
M_S     = $043A
M_CMD   = $043B
M_RND   = $043E
M_ID    = $043F

; --- POKEYs ----------------------------------------------------------------
PKA     = $0450
PKB     = $0440

; --- Zero page --------------------------------------------------------------
; $40-$5F engine, $60-$8F physics, $90-$AF game, $B0-$BF NMI/sound
pfs         = $40   ; fine scroll f (0-15) of the frame being built
pfshift     = $41   ; 15-f
pfp         = $42   ; pointer
pfq         = $44   ; pointer
sp_lo       = $46   ; pf_plot: graphics address
sp_hi       = $47
sp_pw       = $48   ;   palette<<5 | (-width & 31)
sp_x        = $49   ;   x (160A pixel)
sp_y        = $4A   ;   screen y + 32
sp_h        = $4B   ;   lines used in the strip
pft1        = $4C
pft2        = $4D
pft3        = $4E
pft4        = $4F
pfrow       = $50   ; row being built
pft5        = $51
frame       = $52   ; frames drawn (NMI)
frame_ready = $53   ; main loop -> NMI: the frame is built, commit it
nmi_phase   = $54
tick        = $55   ; game steps
mframe      = $2120 ; frame when the main loop last started
mcatch      = $2121

; --- RAM --------------------------------------------------------------------
DLL         = $1800 ; display list list (~60 bytes)
HUDDL       = $1840 ; the HUD's display list: one 20-character object
EMPTYDL     = $1848 ; two zeros
hudtext     = $1850 ; [20] font indices shown in the HUD
hudpal      = $1864 ; [3] HUD palette 7 colors
slot_row    = $1870 ; [16] map row held by each slot ($FF none)
slot_bg     = $1880 ; [16] background bytes in each slot
oldend      = $1890 ; [18] objects in each buffer as last terminated
zonelo      = $18A2 ; [15] DL of zone k, k = 1..14
zonehi      = $18B1 ; [15]
zonebuf     = $18C0 ; [15] buffer (slot 0-15, 16-17 zone 14) zone k uses
zoneold     = $18CF ; [15]
dlend       = $18DE ; [15]
dlendsave   = $18ED ; [15]
pfz14back   = $18FC ; zone 14 buffer being built
cam_lo      = $18FD ; camera: world line at the top of the playfield (0..271)
cam_hi      = $18FE
pfnodraw    = $18FF

SLOTBASE    = $1900 ; 16 slots of BUFSIZE: $1900-$1FFF
BUFSIZE     = 112
PFCAP       = BUFSIZE-6
Z14BASE     = $2200 ; 2 zone-14 buffers: $2200-$22DF
DLLZ1       = DLL+3*3   ; the first playfield zone's DLL entry

lamp_state  = $2000 ; [64] 0 off, 1 on, 2 slow flash, 3 fast flash
pfpal_shadow = $2100 ; [24] playfield palettes 0-7
z14_row     = $2118 ; [2] row each zone-14 buffer was built from ($FF none)
z14_f       = $211A ; [2] at this fine scroll
z14_bg      = $211C ; [2] its background bytes
z14_cur     = $211E ; the row zone 14 shows
lamp_dirty  = $211F

; game, physics, sound RAM: $22E0-$27FF (see each file)

; ===========================================================================
    SEG ROM
    ORG $4000
    INCBIN "gen/bg0.bin"            ; $4000-$8FFF

    ORG $9000
    include "engine.asm"
    include "physics.asm"
    if . > $A000
        echo "code at $9000 overflows by", [. - $A000]d
        err
    endif

    ORG $A000
    INCBIN "gen/spr0.bin"

    ORG $B000
    include "game.asm"
    include "gen/sprites.asm"
    if . > $C000
        echo "code at $B000 overflows by", [. - $C000]d
        err
    endif

    ORG $C000
    INCBIN "gen/spr1.bin"

    ORG $D000
    include "sound.asm"
    include "gen/music.asm"
    include "gen/rows.asm"          ; (only the row pointers: the rows are in the $C000 block)
    if . > $E000
        echo "code at $D000 overflows by", [. - $E000]d
        err
    endif

    ORG $E000
    INCBIN "gen/bg1.bin"

    ORG $F000
    include "gen/colliders.asm"
    include "physics2.asm"

; ---------------------------------------------------------------------------
START
    sei
    cld
    lda #$07
    sta INPTCTRL            ; lock into 7800 mode
    lda #$7F
    sta CTRL                ; DMA off
    lda #0
    sta OFFSET
    sta INPTCTRL
    sta BACKGRND
    ldx #$FF
    txs

    ; clear $1800-$27FF and zero page $40-$FF
    lda #0
    tay
    sta $80
    ldx #$18
.clr
    stx $81
.clr1
    sta ($80),y
    iny
    bne .clr1
    inx
    cpx #$28
    bne .clr
    ldx #$40
.clrzp
    sta $00,x
    inx
    bne .clrzp

    ; two-button joysticks
    lda #$14
    sta CTLSWB
    lda #0
    sta SWCHB

    ; math unit: signed
    lda #1
    sta M_CTRL

    jsr snd_init
    jsr pf_init
    jsr game_init

    ; turn the display on in vblank
.wv1
    bit MSTAT
    bmi .wv1
.wv2
    bit MSTAT
    bpl .wv2
    lda #0
    sta nmi_phase
    lda #>DLL
    sta DPPH
    lda #<DLL
    sta DPPL
    lda #FONT_PAGE
    sta CHARBASE
    lda #$50                ; DMA on, 2-byte characters, 160A
    sta CTRL

; ---------------------------------------------------------------------------
; Main loop: one game step and one frame built per pass. The NMI at the
; bottom of the screen commits the frame (DLL, display list ends) in vblank.
    SUBROUTINE
main_loop
    ; frames shown since the last pass: if the last pass ran late (heavy
    ; multiball), run the missed game steps too (without drawing them), so
    ; the game keeps its speed and only the frame rate drops
    lda frame
    sec
    sbc mframe
    tax
    lda frame
    sta mframe
    dex
    beq .one
    bmi .one
    cpx #3
    bcc .catch
    ldx #2                  ; at most two steps behind
.catch
    stx mcatch
.c1
    jsr game_step
    inc tick
    dec mcatch
    bne .c1
.one
    jsr game_step           ; input, physics, rules, camera, sound cues
    jsr pf_frame            ; map rows to zones for the camera, reset sprites
    jsr game_draw           ; sprites, lamps, HUD
    lda #1
    sta frame_ready
.wait
    lda frame_ready
    bne .wait
    inc tick
    jmp main_loop

; ---------------------------------------------------------------------------
; NMI: two display list interrupts a frame.
;   phase 0: end of the HUD -> the playfield's palette 7
;   phase 1: bottom of the screen (vblank) -> commit the frame, the HUD's
;            palette 7, music
    SUBROUTINE
NMI
    pha
    cld
    txa
    pha
    tya
    pha
    lda nmi_phase
    bne .nmi_bottom
    lda #1
    sta nmi_phase
    lda pal7+0
    sta P0C1+28
    lda pal7+1
    sta P0C1+29
    lda pal7+2
    sta P0C1+30
    jmp .nmi_out
.nmi_bottom
    lda #0
    sta nmi_phase
    lda hudpal+0
    sta P0C1+28
    lda hudpal+1
    sta P0C1+29
    lda hudpal+2
    sta P0C1+30
    inc frame
    lda frame_ready
    beq .nmi_snd
    jsr pf_terminate
    jsr pf_commit
    lda #0
    sta frame_ready
.nmi_snd
    jsr snd_tick
.nmi_out
    pla
    tay
    pla
    tax
    pla
IRQ
    rti

    if . > $FF7A
        echo "code at $F000 overflows by", [. - $FF7A]d
        err
    endif

    ORG $FF7A
    .byte 0,0,0,0,0,0           ; (signature area follows)
    ORG $FFF8
    .byte $FF                   ; all regions
    .byte $F7                   ; hash from $F000
    .word NMI
    .word START
    .word IRQ
