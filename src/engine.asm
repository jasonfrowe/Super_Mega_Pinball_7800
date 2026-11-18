; ===========================================================================
; Display engine: a vertically scrolling 160A playfield under a HUD.
;
; Screen (243 lines): 8 blank, the HUD (16, a DLI at its end), 2 blank,
; the playfield (209), 8 blank (a DLI: vblank work).
;
; Playfield zones: zone 1 is 16-f lines (the bottom of map row R0), zones
; 2-13 rows R0+1..R0+12, zone 14 the top f+1 lines of row R0+13, where the
; camera's top line is cam = 16*R0 + f. MARIA counts a zone's lines down to
; 0, so zone 1 shows the bottom of its row as it is; zone 14's objects point
; 15-f pages higher to show the top of theirs.
;
; Each map row lives in one of 16 slots, slot = row & 15, a display list in
; RAM holding the row's background objects (copied from ROM) followed by
; this frame's sprites. The 13 rows on screen never share a slot, and a row
; scrolling in takes a slot that was not on screen last frame, so filling
; it never races MARIA. Zone 14 has two buffers of its own, swapped in
; vblank; one is rebuilt only when its row or the fine scroll changed.
;
; Lamps: some background objects are inserts; their palette (or, for drop
; targets, their x) follows lamp_state, applied to the rows on screen.
; ===========================================================================

; ---------------------------------------------------------------------------
    SUBROUTINE
pf_init
    ldx #23
.pal
    lda palettes,x
    sta pfpal_shadow,x
    dex
    bpl .pal
    jsr pf_palettes
    ldx #2
.hp
    lda hud_p7,x
    sta hudpal,x
    dex
    bpl .hp

    ; DLL
    ldx #0
.dll
    lda dll_init,x
    sta DLL,x
    inx
    cpx #DLL_INIT_LEN
    bne .dll
    ; HUD DL: one indirect object, 20 characters
    ldx #6
.hud
    lda hud_dl,x
    sta HUDDL,x
    dex
    bpl .hud
    lda #0
    sta EMPTYDL
    sta EMPTYDL+1
    ldx #19
    lda #0
.hudc
    sta hudtext,x
    dex
    bpl .hudc

    ldx #15
    lda #$FF
.slots
    sta slot_row,x
    dex
    bpl .slots
    sta z14_row
    sta z14_row+1
    lda #0
    sta pfnodraw
    sta pfz14back
    sta cam_lo
    sta cam_hi
    jsr pf_frame
    jsr pf_terminate
    jmp pf_commit

hud_dl
    .byte <hudtext, $60, >hudtext, (7<<5)|((-20)&31), 0, 0, 0

dll_init
    .byte $07, >EMPTYDL, <EMPTYDL           ; 8 blank lines
    .byte $8F, >HUDDL, <HUDDL               ; HUD, 16 lines, DLI at its end
    .byte $01, >EMPTYDL, <EMPTYDL           ; 2 blank
    REPEAT 14
    .byte $4F, >EMPTYDL, <EMPTYDL           ; playfield zones (set each frame)
    REPEND
    .byte $87, >EMPTYDL, <EMPTYDL           ; 8 blank, DLI: vblank work
    .byte $0F, >EMPTYDL, <EMPTYDL           ; past the bottom
    .byte $0F, >EMPTYDL, <EMPTYDL
DLL_INIT_LEN = . - dll_init

    SUBROUTINE
pf_palettes
    ldx #0
    ldy #0
.pp
    lda pfpal_shadow,y
    sta P0C1,x
    iny
    inx
    txa
    and #3
    cmp #3
    bne .pp1
    inx
.pp1
    cpy #21                 ; palettes 0-6 (7 is the NMI's)
    bne .pp
    lda #BGCOLOR
    sta BACKGRND
    rts

; ---------------------------------------------------------------------------
; pf_frame: zones for the camera; empty last frame's sprites
    SUBROUTINE
pf_frame
    ; clamp the camera to 0..MAXCAM
    lda cam_hi
    bpl .c1
    lda #0
    sta cam_lo
    sta cam_hi
.c1
    lda cam_lo
    cmp #<MAXCAM
    lda cam_hi
    sbc #>MAXCAM
    bcc .c2
    lda #<MAXCAM
    sta cam_lo
    lda #>MAXCAM
    sta cam_hi
.c2
    lda cam_lo
    and #15
    sta pfs
    eor #15
    sta pfshift
    lda cam_hi              ; R0 = cam >> 4
    sta pft1
    lda cam_lo
    lsr pft1
    ror
    lsr pft1
    ror
    lsr pft1
    ror
    lsr pft1
    ror
    sta pfrow               ; row for zone 1

    ldx #1
.zones
    stx pft4
    lda pfrow
    and #15
    tay                     ; slot
    lda pfrow
    cmp slot_row,y
    beq .have
    jsr pf_fillslot
    lda pfrow
    and #15
    tay
.have
    ldx pft4
    lda slotlo,y
    sta zonelo,x
    lda slothi,y
    sta zonehi,x
    lda slot_bg,y
    sta dlendsave,x
    sta dlend,x
    tya
    sta zonebuf,x
    lda oldend,y
    sta zoneold,x
    inc pfrow
    inx
    cpx #14
    bne .zones
    jmp pf_zone14

; Fill slot (pfrow & 15) with map row pfrow
    SUBROUTINE
pf_fillslot
    lda pfrow
    and #15
    tax
    lda pfrow
    sta slot_row,x
    lda slotlo,x
    sta pfq
    lda slothi,x
    sta pfq+1
    ldy pfrow
    lda row_lo,y
    sta pfp
    lda row_hi,y
    sta pfp+1
    ldy #0
    lda (pfp),y
    sta slot_bg,x
    sta oldend,x
    tay
    beq .done
.copy
    lda (pfp),y
    dey
    sta (pfq),y
    bne .copy
.done
    ; end the list (the slot was not on screen)
    ldy slot_bg,x
    lda #0
    iny
    sta (pfq),y
    ldy pfrow
    jmp pf_lamps_row

; Zone 14: the back buffer shows row pfrow (= R0+13)
    SUBROUTINE
pf_zone14
    lda pfz14back
    tax
    clc
    adc #16
    sta zonebuf+14
    lda z14lo,x
    sta pfq
    sta zonelo+14
    lda z14hi,x
    sta pfq+1
    sta zonehi+14
    ; the same row at the same fine scroll as when this buffer was built?
    lda pfrow
    cmp z14_row,x
    bne .z14b
    lda pfs
    cmp z14_f,x
    bne .z14b
    lda z14_bg,x
    jmp .z14n
.z14b
    lda pfrow
    sta z14_row,x
    lda pfs
    sta z14_f,x
    ldy pfrow
    cpy #TABLE_ROWS
    bcc .z14row
    lda #0
    beq .z14n
.z14row
    lda row_lo,y
    sta pfp
    lda row_hi,y
    sta pfp+1
    ldy #0
    lda (pfp),y
    beq .z14n
    sta pft1
.z14c
    ; an object: lo, pw, hi + 15-f, x
    iny
    lda (pfp),y
    dey
    sta (pfq),y
    iny
    iny
    lda (pfp),y
    dey
    sta (pfq),y
    iny
    iny
    lda (pfp),y
    clc
    adc pfshift
    dey
    sta (pfq),y
    iny
    iny
    lda (pfp),y
    dey
    sta (pfq),y
    iny
    cpy pft1
    bcc .z14c
    ldy pfrow               ; rebuilt: its lamps
    jsr pf_lamps_row
    lda pft1
.z14n
    ldx pfz14back
    sta z14_bg,x
    sta dlendsave+14
    sta dlend+14
    sta zoneold+14          ; sprites in the back buffer are all new
    sta oldend+16,x
    lda pfrow
    sta z14_cur
    rts

z14lo .byte <Z14BASE, <(Z14BASE+BUFSIZE)
z14hi .byte >Z14BASE, >(Z14BASE+BUFSIZE)

; ---------------------------------------------------------------------------
; pf_lamps_row: apply lamp states to row Y's objects in the buffer at pfq
    SUBROUTINE
pf_lamps_row
    lda rowlamp_lo,y
    sta pfp
    lda rowlamp_hi,y
    sta pfp+1
    ldy #0
.lr
    lda (pfp),y             ; object offset
    cmp #$FF
    beq .lrdone
    sta pft2
    iny
    lda (pfp),y             ; lamp id
    tax
    iny
    lda lamp_state,x
    beq .off
    cmp #1
    beq .on
    and #1                  ; 2 slow, 3 fast
    tax
    lda frame
    and flashmask,x
    bne .on
.off
    lda (pfp),y             ; pw off ($FF: hide by x)
    iny
    cmp #$FF
    beq .hide
    sty pft3
    ldy pft2
    iny
    sta (pfq),y
    ldy pft3
    iny
    bne .lr
.hide
    sty pft3
    ldy pft2
    iny
    iny
    iny
    lda #160
    sta (pfq),y
    ldy pft3
    iny
    bne .lr
.on
    lda (pfp),y
    iny
    cmp #$FF
    beq .show
    lda (pfp),y             ; pw on
    sty pft3
    ldy pft2
    iny
    sta (pfq),y
    ldy pft3
    iny
    bne .lr
.show
    lda (pfp),y             ; the x it belongs at
    sty pft3
    ldy pft2
    iny
    iny
    iny
    sta (pfq),y
    ldy pft3
    iny
    bne .lr
.lrdone
    rts

flashmask .byte 16, 4

; pf_lamps: every row on screen (zones 1-13: their slots; zone 14)
    SUBROUTINE
pf_lamps
    ldx #1
.pl
    stx pft5
    ldy zonebuf,x
    lda slotlo,y
    sta pfq
    lda slothi,y
    sta pfq+1
    lda slot_row,y
    tay
    jsr pf_lamps_row
    ldx pft5
    inx
    cpx #14
    bne .pl
    lda z14_cur
    cmp #TABLE_ROWS
    bcs .pl1
    tay
    lda zonelo+14
    sta pfq
    lda zonehi+14
    sta pfq+1
    jmp pf_lamps_row
.pl1
    rts

; ---------------------------------------------------------------------------
; pf_drawimg: frame A (IMG_x + n, gen/sprites.asm) anchored at pixel x
; dimg_ax, world line dimg_yl/dimg_yh, palette Y. Draws every strip.
dimg_n      = $57
dimg_yl     = $5A
dimg_yh     = $5B
dimg_ax     = $5D
dimg_idx    = $5E

    SUBROUTINE
pf_drawimg
    tax
    tya
    asl
    asl
    asl
    asl
    asl
    ora frm_pw,x
    sta sp_pw
    lda dimg_ax
    clc
    adc frm_xo,x
    sta sp_x
    lda frm_n,x
    sta dimg_n
    lda frm_s0,x
    sta dimg_idx
    ; screen y of strip 0 = anchor + y offset (signed) - camera
    lda frm_yo,x
    bpl .yp
    dec dimg_yh
.yp
    clc
    adc dimg_yl
    sta dimg_yl
    bcc .y1
    inc dimg_yh
.y1
    sec
    lda dimg_yl
    sbc cam_lo
    sta dimg_yl
    lda dimg_yh
    sbc cam_hi
    sta dimg_yh
    lda #16
    sta sp_h
.strip
    lda dimg_yl
    clc
    adc #32
    tax
    lda dimg_yh
    adc #0
    bne .next               ; off the screen
    stx sp_y
    ldy dimg_idx
    lda strip_lo,y
    sta sp_lo
    lda strip_hi,y
    sta sp_hi
    jsr pf_plot
.next
    inc dimg_idx
    lda dimg_yl
    clc
    adc #16
    sta dimg_yl
    bcc .n1
    inc dimg_yh
.n1
    dec dimg_n
    bne .strip
    rts

; ---------------------------------------------------------------------------
; pf_plot: one 16-line strip at (sp_x, sp_y = screen y + 32)
    SUBROUTINE
pf_plot
    lda pfnodraw
    bne .out
    clc
    lda sp_y
    adc pfs
    bcs .out
    sbc #15
    bcc .out
    sta pft3
    and #15
    sta pft4
    lda pft3
    lsr
    lsr
    lsr
    lsr
    tax                     ; zone of the strip's top
    beq .lower
    cpx #15
    bcs .out
    lda sp_hi
    ora pft4
    jsr pf_object
.lower
    lda pft4
    clc
    adc sp_h
    cmp #16
    bcc .out
    inx
    cpx #15
    bcs .out
    lda sp_hi
    ora pft4
    sec
    sbc #16
    jmp pf_object
.out
    rts

; pf_object: object at sp_lo / A (hi) / sp_pw / sp_x into zone X.
; Keeps the list valid after every store (MARIA may be reading it).
    SUBROUTINE
pf_object
    cpx #14
    bne .ptr
    clc
    adc pfshift
.ptr
    sta pft1
    ldy dlend,x
    tya
    cmp #PFCAP
    bcs .full
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
    bcc .over
    ; past last frame's end: terminator first, palette|width last
    ldy #5
    lda #0
    sta (pfp),y
    ldy #1
    sta (pfp),y
    ldy #3
    lda sp_x
    sta (pfp),y
    dey
    lda pft1
    sta (pfp),y
    ldy #0
    lda sp_lo
    sta (pfp),y
    iny
    lda sp_pw
    sta (pfp),y
    rts
.over
    ; over one of last frame's objects
    ldy #0
    lda (pfp),y
    cmp sp_lo
    bne .new
    iny
    lda (pfp),y
    eor sp_pw
    and #$1F
    bne .new
    lda sp_pw
    sta (pfp),y
    iny
    lda pft1
    sta (pfp),y
    iny
    lda sp_x
    sta (pfp),y
    rts
.new
    ldy #3
    lda #160                ; hide it while it changes
    sta (pfp),y
    dey
    lda pft1
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
.full
    rts

; ---------------------------------------------------------------------------
; In vblank (NMI): end each zone's list, write the zones into the DLL
    SUBROUTINE
pf_terminate
    ldx #14
.t
    lda zonelo,x
    sta pfp
    lda zonehi,x
    sta pfp+1
    ldy zonebuf,x
    lda dlend,x
    sta oldend,y
    tay
    iny
    lda #0
    sta (pfp),y
    dex
    bne .t
    rts

    SUBROUTINE
pf_commit
ZN SET 1
    REPEAT 14
    lda zonehi+ZN
    sta DLLZ1+3*[ZN-1]+1
    lda zonelo+ZN
    sta DLLZ1+3*[ZN-1]+2
ZN SET ZN+1
    REPEND
    lda #$4F
    sec
    sbc pfs
    sta DLLZ1               ; zone 1: 16-f lines
    lda pfs
    ora #$40
    sta DLLZ1+3*13          ; zone 14: f+1 lines
    lda pfz14back
    eor #1
    sta pfz14back
    rts

slotlo
SLI SET 0
    REPEAT 16
    .byte <(SLOTBASE+SLI*BUFSIZE)
SLI SET SLI+1
    REPEND
slothi
SLI SET 0
    REPEAT 16
    .byte >(SLOTBASE+SLI*BUFSIZE)
SLI SET SLI+1
    REPEND

MAXCAM = TABLE_ROWS*16-209

; ---------------------------------------------------------------------------
; hud_puts: copy the 20-character string at (pfp) into the HUD
    SUBROUTINE
hud_puts
    ldy #19
.hp
    lda (pfp),y
    tax
    lda ascii2font-32,x
    sta hudtext,y
    dey
    bpl .hp
    rts
