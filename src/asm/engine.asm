; ===========================================================================
; Super Mega Pinball 7800 - Bidirectional Smooth Vertical Scrolling Engine
; Adapted from AtariGammaForce's 160A Display List Engine (docs/ENGINE.md):
;
;   zone 0       Fixed top DMD/LED Scoreboard HUD (7 active lines, low DMA)
;   zones 1-13   Playfield (16-s lines at zone 1, 12*16 lines in zones 2-13)
;   zone 14      Bottom partial playfield row (1+s lines, direct-mode tiles)
;
; All 20 rows (320 scanlines) of the Pinball table background live in 20
; dedicated 80-byte buffers in RAM ($1900-$1F3F), built once at init.
; Any camera position cam_y (0..111, where 0 = top of table, 111 = bottom)
; maps zones 1..13 directly to row buffers (pfrow14+13 .. pfrow14+1) and
; zone 14 to pfrow14, giving instantaneous 1-scanline smooth vertical
; scrolling both UP and DOWN at 60 Hz!
; ===========================================================================

pfs         = $A5   ; fine scroll s (0-15) for the frame being built
pfshift     = $A6   ; 15-s, the page shift for zone 14
pfp         = $A7   ; pointer, 2 bytes
pfq         = $A9   ; pointer, 2 bytes
sp_lo       = $AB   ; pf_plot arguments: graphics address,
sp_hi       = $AC
sp_pw       = $AD   ;   palette<<5 | (-width & 31),
sp_x        = $AE   ;   x,
sp_y        = $AF   ;   playfield y + 32
pft1        = $B0   ; scratch
pft2        = $B1
pft3        = $B2
pft4        = $B3
pft5        = $C5

; Engine RAM ($2200-$22FF)
zonelo      = $2200 ; [15] DL address of zone k, k = 1..14
zonehi      = $2210 ; [15]
bgsize      = $2220 ; [20] background bytes at the start of row buffer 0..19 ($2220-$2233)
spos_lo     = $2234 ; scroll position from bottom (111 - cam_y, 0..111)
pfrow14     = $2235 ; map row shown in zone 14 (0..6)
pfz14back   = $2236 ; zone 14 buffer (0/1) being built this frame
pfz14row    = $2237 ; [2] row each zone 14 buffer holds ($FF: none)
pfz14bg     = $2239 ; [2] background bytes in each zone 14 buffer
cam_y       = $223B ; camera top Y in world coordinates (0 = top, 111 = bottom)
cam_target  = $223C ; target camera Y following active ball(s)
tzone       = $223D ; zone (1-13) for pf_text
tpal        = $223E ; palette for pf_text
pfnodraw    = $223F ; 0 = normal draw

hudtext     = $2240 ; [20] HUD characters, shown live in zone 0 ($2240-$2253)

zonebuf     = $2254 ; [15] which buffer index (0..21) zone k uses ($2254-$2262)
zoneold     = $2263 ; [15] oldend of the buffer each zone uses this frame ($2263-$2271)
txtnow      = $2272 ; [15] where each zone's text is this frame ($2272-$2280)
oldend      = $2282 ; [22] each buffer's object count as last terminated ($2282-$2297)
txtold      = $2298 ; [22] where each buffer's text was as last terminated ($2298-$22AD)

pimg        = $22AE ; pf_drawimg arguments: sprite image ID
pframe      = $22AF ;   animation frame
px          = $22B0 ;   screen X
py          = $22B1 ;   playfield screen Y + 32
ppal        = $22B2 ;   palette (0..7)
sp_h        = $22B3 ;   height in scanlines

RINGN       = 20
RINGBASE    = $1900
BUFSIZE     = 80
PFCAP       = BUFSIZE-6
Z14BASE     = RINGBASE+RINGN*BUFSIZE ; $1F40
Z14SIZE     = 96
Z14CAP      = Z14SIZE-6
DLLZONE1    = DLLMEM+18
DLLNONVIS   = DLLZONE1+42

ZONE1ADDRESS  = RINGBASE+0*BUFSIZE
ZONE2ADDRESS  = RINGBASE+1*BUFSIZE
ZONE3ADDRESS  = RINGBASE+2*BUFSIZE
ZONE4ADDRESS  = RINGBASE+3*BUFSIZE
ZONE5ADDRESS  = RINGBASE+4*BUFSIZE
ZONE6ADDRESS  = RINGBASE+5*BUFSIZE
ZONE7ADDRESS  = RINGBASE+6*BUFSIZE
ZONE8ADDRESS  = RINGBASE+7*BUFSIZE
ZONE9ADDRESS  = RINGBASE+8*BUFSIZE
ZONE10ADDRESS = RINGBASE+9*BUFSIZE
ZONE11ADDRESS = RINGBASE+10*BUFSIZE

    if Z14BASE+2*Z14SIZE > $2000
        echo "ERROR: engine DL buffers overflow $1FFF"
        err
    endif

; ---------------------------------------------------------------------------
; pf_init: Initialize palettes, Zone 0 HUD, DLL, and build all 20 table rows.
; ---------------------------------------------------------------------------
pf_init
    jsr pf_palettes

    ; HUD: one 20-character object in zone 0, reading hudtext live
    ldx #19
pf_init_hud
    lda hudinit,x
    sta hudtext,x
    dex
    bpl pf_init_hud
    ldx #4
pf_init_hudobj
    lda pfhudobj,x
    sta ZONE0ADDRESS,x
    dex
    bpl pf_init_hudobj
    lda #5
    sta dlend
    sta dlendsave

    ; Setup DLL for 14 scrolling playfield zones below the 7-line HUD zone
    jsr waitforvblankstart
    ldx #14
pf_init_dll
    lda DLLMEM+[DLLLUTNONVISSTART-DLLLUT],x
    sta DLLNONVIS,x
    dex
    bpl pf_init_dll

    ldx #8
pf_init_hud2
    lda pfhuddll,x
    sta DLLMEM+9,x
    dex
    bpl pf_init_hud2

    dec DLLMEM
    lda #(DLLNONVIS-DLLMEM)
    sta overscanDLLstart
    lda #0
    sta pfnodraw
    sta pfz14back
    lda #111
    sta cam_y
    sta cam_target

    ; Clear oldend and txtold for all 22 buffers (0..19 row buffers + 20..21 zone 14)
    ldx #21
pf_init_clr
    lda #0
    sta oldend,x
    lda #$FF
    sta txtold,x
    dex
    bpl pf_init_clr

    ; Build all 20 Pinball table rows into RAM buffers 0..19 once
    ldx #0
pf_init_rows
    stx pft4
    txa
    tay
    jsr pf_buildrow
    ldx pft4
    lda bgsize,x
    sta oldend,x
    inx
    cpx #RINGN
    bne pf_init_rows

    lda #$FF
    sta pfz14row
    sta pfz14row+1

    jsr pf_frame
    jsr waitforvblankstart
    jsr pf_terminate
    jmp pf_commit

pfhudobj
    .byte <hudtext, $60, >hudtext, (0<<5)|((-20)&31), 0
pfhuddll
    .byte 2, >pfnodl, <pfnodl
    .byte 6, >ZONE0ADDRESS, <ZONE0ADDRESS
    .byte $80|5, >pfnodl, <pfnodl
pfnodl
    .byte 0, 0

; ---------------------------------------------------------------------------
; pf_palettes: Load all 8 hardware 160A palettes (P0..P7) and background $00
; ---------------------------------------------------------------------------
pf_palettes
    ldx #0
    ldy #0
pf_palettes_loop
    lda palettedata,x
    sta P0C1,y
    inx
    iny
    tya
    and #3
    cmp #3
    bne pf_palettes_next
    iny
pf_palettes_next
    cpx #24
    bne pf_palettes_loop
    lda #BGCOLOR
    sta BACKGRND
    lda #>charset
    sta sCHARBASE
    rts

; ---------------------------------------------------------------------------
; pf_buildrow: Copy map row Y's background objects into row buffer X (0..19)
; ---------------------------------------------------------------------------
pf_buildrow
    lda stg_rowlo,y
    sta pfp
    lda stg_rowhi,y
    sta pfp+1
    lda ringlo,x
    sta pfq
    lda ringhi,x
    sta pfq+1
    lda #$FF
    sta txtold,x
    ldy #0
    lda (pfp),y
    sta bgsize,x
    tay
    beq pf_buildrow_done
pf_buildrow_copy
    lda (pfp),y
    dey
    sta (pfq),y
    bne pf_buildrow_copy
pf_buildrow_done
    rts

; ---------------------------------------------------------------------------
; pf_frame: Update zone mapping for current cam_y (0..111) and reset sprites
; ---------------------------------------------------------------------------
pf_frame
    ; Clamp cam_y to 0..111 and compute spos_lo = 111 - cam_y
    lda cam_y
    bpl .cam_pos
    lda #0
    sta cam_y
.cam_pos
    cmp #112
    bcc .cam_ok
    lda #111
    sta cam_y
.cam_ok
    lda #111
    sec
    sbc cam_y
    sta spos_lo

    lsr
    lsr
    lsr
    lsr
    sta pfrow14             ; pfrow14 = spos_lo >> 4 (0..6)

    lda spos_lo
    and #15
    sta pfshift             ; pfshift = spos_lo & 15
    eor #15
    sta pfs                 ; pfs = 15 - pfshift

    ; Map zones x = 1..13 to row buffer y = pfrow14 + 14 - x
    lda pfrow14
    clc
    adc #13
    tay                     ; zone 1 gets row pfrow14 + 13
    ldx #1
pf_mapzones_loop
    lda ringlo,y
    sta zonelo,x
    lda ringhi,y
    sta zonehi,x
    lda bgsize,y
    sta dlendsave,x
    tya
    sta zonebuf,x
    dey
    inx
    cpx #14
    bne pf_mapzones_loop

    jsr pf_zone14

    ldx #14
pf_frame_old
    ldy zonebuf,x
    lda txtold,y
    cmp #$FF
    bne pf_frame_oldset
    lda oldend,y
pf_frame_oldset
    sta zoneold,x
    dex
    bne pf_frame_old

pf_restore
    ldx #14
pf_restore_loop
    lda dlendsave,x
    sta dlend,x
    lda #$FF
    sta txtnow,x
    dex
    bne pf_restore_loop
    rts

; ---------------------------------------------------------------------------
; pf_zone14: Build/update Zone 14's direct-mode tiles for row pfrow14
; ---------------------------------------------------------------------------
pf_zone14
    ldx pfz14back
    txa
    clc
    adc #20                 ; buffer indices 20 and 21
    sta zonebuf+14
    lda z14lo,x
    sta pfq
    sta zonelo+14
    lda z14hi,x
    sta pfq+1
    sta zonehi+14
    lda pfz14row,x
    cmp pfrow14
    bne pf_zone14_new
    jmp pf_zone14_hi
pf_zone14_new
    lda pfrow14
    sta pfz14row,x
    tay
    lda stg_rowlo,y
    sta pfp
    lda stg_rowhi,y
    sta pfp+1
    ldy #0
    lda (pfp),y
    sta pft4
    lda #0
    sta pft3
    ldy #1
pf_zone14_obj
    sty sp_y
    lda pft4
    cmp sp_y
    bcc pf_zone14_end
    lda (pfp),y
    sta sp_lo
    iny
    iny
    lda (pfp),y
    sta sp_hi
    iny
    lda (pfp),y
    pha
    and #$E0
    ora #(-2)&31
    sta sp_pw
    pla
    eor #$FF
    clc
    adc #1
    and #31
    sta sp_h
    iny
    lda (pfp),y
    sta sp_x
    iny
    sty sp_y
    ldy #0
pf_zone14_tile
    sty pft1
    lda (sp_lo),y
    ldy pft3
    sta (pfq),y
    iny
    lda sp_pw
    sta (pfq),y
    iny
    iny
    lda sp_x
    sta (pfq),y
    clc
    adc #8
    sta sp_x
    iny
    sty pft3
    ldy pft1
    iny
    cpy sp_h
    bcc pf_zone14_tile
    ldy sp_y
    jmp pf_zone14_obj
pf_zone14_end
    ldx pfz14back
    lda pft3
    sta pfz14bg,x
pf_zone14_hi
    ldx pfz14back
    lda pfz14bg,x
    sta dlendsave+14
    beq pf_zone14_done
    sta pft3
    lda #>charset
    clc
    adc pfshift
    ldy #2
pf_zone14_hiloop
    sta (pfq),y
    iny
    iny
    iny
    iny
    cpy pft3
    bcc pf_zone14_hiloop
pf_zone14_done
    rts

z14lo .byte <Z14BASE, <(Z14BASE+Z14SIZE)
z14hi .byte >Z14BASE, >(Z14BASE+Z14SIZE)

; ---------------------------------------------------------------------------
; pf_drawimg: Draw sprite pimg, frame pframe, at (px, py - 32) in palette ppal
; ---------------------------------------------------------------------------
pf_drawimg
    ldx pimg
    lda imgw,x
    sta pft1
    lda #0
    sec
    sbc pft1
    and #31
    sta pft2
    lda ppal
    asl
    asl
    asl
    asl
    asl
    ora pft2
    sta sp_pw
    lda #0
    ldy pframe
    beq pf_drawimg_f1
pf_drawimg_f0
    clc
    adc pft1
    dey
    bne pf_drawimg_f0
pf_drawimg_f1
    clc
    adc imglo,x
    sta sp_lo
    lda imghi,x
    sta sp_hi
    lda px
    sta sp_x
    lda py
    sta sp_y
    lda imgh,x
    sta sp_h

; ---------------------------------------------------------------------------
; pf_plot: Plot one 16-line strip at (sp_x, sp_y = screen_y + 32)
; ---------------------------------------------------------------------------
pf_plot
    lda pfnodraw
    bne pf_plot_out
    clc
    lda sp_y
    adc pfs
    bcs pf_plot_out
    sbc #15
    bcc pf_plot_out
    sta pft1
    and #15
    sta pft2
    lda pft1
    lsr
    lsr
    lsr
    lsr
    tax
    beq pf_plot_lower
    cpx #15
    bcs pf_plot_out
    lda sp_hi
    ora pft2
    jsr pf_object
pf_plot_lower
    lda pft2
    clc
    adc sp_h
    cmp #16
    bcc pf_plot_out
    inx
    cpx #15
    bcs pf_plot_out
    lda sp_hi
    ora pft2
    sec
    sbc #16
    jmp pf_object
pf_plot_out
    rts

pf_object
    cpx #14
    bne pf_object_ptr
    clc
    adc pfshift
pf_object_ptr
    sta pft3
    ldy dlend,x
    tya
    cmp zonecap,x
    bcs pf_object_full
    adc #4
    sta dlend,x
    tya
    clc
    adc zonelo,x
    sta pfp
    lda zonehi,x
    adc #0
    sta pfp+1
    tya
    cmp zoneold,x
    bcc pf_object_over
    ldy #1
    lda #0
    sta (pfp),y
    ldy #5
    sta (pfp),y
    ldy #3
    lda sp_x
    sta (pfp),y
    dey
    lda pft3
    sta (pfp),y
    ldy #0
    lda sp_lo
    sta (pfp),y
    iny
    lda sp_pw
    sta (pfp),y
    rts
pf_object_over
    ldy #0
    lda (pfp),y
    cmp sp_lo
    bne pf_object_new
    iny
    lda (pfp),y
    eor sp_pw
    and #$1F
    bne pf_object_new
    lda sp_pw
    sta (pfp),y
    iny
    lda pft3
    sta (pfp),y
    iny
    lda sp_x
    sta (pfp),y
    rts
pf_object_new
    ldy #3
    lda #160
    sta (pfp),y
    dey
    lda pft3
    sta (pfp),y
    ldy #0
    lda sp_lo
    sta (pfp),y
    iny
    lda sp_pw
    sta (pfp),y
    ldy #3
    lda sp_x
    sta (pfp),y
pf_object_full
    rts

zonecap
    .byte 0
    REPEAT 13
    .byte PFCAP
    REPEND
    .byte Z14CAP

; ---------------------------------------------------------------------------
; pf_text: Draw centered text string A (TXT_*) in zone tzone (1..13), palette tpal
; ---------------------------------------------------------------------------
pf_text
    tay
    ldx tzone
    lda zonelo,x
    sta pfp
    lda zonehi,x
    sta pfp+1
    lda txtlen,y
    sta pft1
    asl
    asl
    sta pft2
    lda #80
    sec
    sbc pft2
    sta pft2
    bit tpal
    bpl pf_text_shown
    lda #160
    sta pft2
pf_text_shown
    lda txtlo,y
    sta pft3
    lda txthi,y
    sta pft4
    lda tpal
    asl
    asl
    asl
    asl
    asl
    sta pft5
    lda #0
    sec
    sbc pft1
    and #31
    ora pft5
    sta pft5
    ldy zonebuf,x
    lda txtold,y
    sta pft1
    cmp #$FF
    beq pf_text_slot
pf_text_pad
    lda dlend,x
    cmp pft1
    bcs pf_text_slot
    clc
    adc #3
    tay
    lda #160
    sta (pfp),y
    iny
    sty dlend,x
    bne pf_text_pad
pf_text_slot
    lda dlend,x
    cmp #PFCAP-1
    bcs pf_text_full
    sta txtnow,x
    clc
    adc pfp
    sta pfp
    bcc pf_text_same
    inc pfp+1
pf_text_same
    ldy #1
    lda (pfp),y
    cmp #$60
    bne pf_text_new
    dey
    lda (pfp),y
    cmp pft3
    bne pf_text_new
    ldy #2
    lda (pfp),y
    cmp pft4
    bne pf_text_new
    iny
    lda (pfp),y
    cmp pft5
    bne pf_text_new
    iny
    lda (pfp),y
    cmp pft2
    beq pf_text_done
pf_text_new
    ldy #1
    lda #0
    sta (pfp),y
    ldy #6
    sta (pfp),y
    dey
    dey
    lda pft2
    sta (pfp),y
    dey
    lda pft5
    sta (pfp),y
    dey
    lda pft4
    sta (pfp),y
    dey
    dey
    lda pft3
    sta (pfp),y
    iny
    lda #$60
    sta (pfp),y
pf_text_done
    lda dlend,x
    clc
    adc #5
    sta dlend,x
pf_text_full
    rts

; ---------------------------------------------------------------------------
; pf_drawscreen: Wait for vblank, terminate DLs, and commit DLL
; ---------------------------------------------------------------------------
pf_drawscreen
    ifconst interrupthold
        lda #$FF
        sta interrupthold
    endif
    jsr waitforvblankstart
    lda #3
    sta interruptindex
    lda #0
    sta visibleover
    lda sCTRL
    sta CTRL
    lda sCHARBASE
    sta CHARBASE
    jsr terminatedisplaylist
    jsr pf_terminate
    jsr pf_commit
    dec frameslost
    rts

pf_terminate
    ldx #14
pf_terminate_loop
    lda zonelo,x
    sta pfp
    lda zonehi,x
    sta pfp+1
    ldy zonebuf,x
    lda txtnow,x
    sta txtold,y
    lda dlend,x
    sta oldend,y
    tay
    iny
    lda #0
    sta (pfp),y
    dex
    bne pf_terminate_loop
    rts

pf_commit
    ldx #1
    ldy #0
pf_commit_loop
    lda #$4F
    sta DLLZONE1,y
    lda zonehi,x
    sta DLLZONE1+1,y
    lda zonelo,x
    sta DLLZONE1+2,y
    iny
    iny
    iny
    inx
    cpx #15
    bne pf_commit_loop
    lda #$4F
    sec
    sbc pfs
    sta DLLZONE1
    lda pfs
    ora #$40
    sta DLLZONE1+3*13
    lda pfz14back
    eor #1
    sta pfz14back
    rts

ringlo
RINGI SET 0
    REPEAT RINGN
    .byte <(RINGBASE+RINGI*BUFSIZE)
RINGI SET RINGI+1
    REPEND
ringhi
RINGI SET 0
    REPEAT RINGN
    .byte >(RINGBASE+RINGI*BUFSIZE)
RINGI SET RINGI+1
    REPEND
