; ===========================================================================
; Super Mega Pinball 7800 - Dual-Channel Polyphonic TIA Sound Engine
; ===========================================================================

SFX_NONE        = 0
SFX_FLIPPER     = 1
SFX_BUMPER      = 2
SFX_SLING       = 3
SFX_TARGET      = 4
SFX_SPINNER     = 5
SFX_LAUNCH      = 6
SFX_RAMP        = 7
SFX_LOCK        = 8
SFX_MULTIBALL   = 9
SFX_DRAIN       = 10

sfx_id0         = $22B4
sfx_tmr0        = $22B5
sfx_id1         = $22B6
sfx_tmr1        = $22B7

sound_init
    lda #0
    sta sfx_id0
    sta sfx_tmr0
    sta sfx_id1
    sta sfx_tmr1
    sta AUDV0
    sta AUDV1
    sta AUDC0
    sta AUDC1
    sta AUDF0
    sta AUDF1
    rts

; Trigger sound effect A on Channel 0 (Flippers, Slingshots, Launch, Spinner)
sound_play_ch0
    sta sfx_id0
    tay
    lda sfx_dur_tbl,y
    sta sfx_tmr0
    rts

; Trigger sound effect A on Channel 1 (Bumpers, Targets, Ramp, Lock, Multi-Ball, Drain)
sound_play_ch1
    ; Don't let a minor chime interrupt a Multi-Ball or Ramp fanfare
    ldy sfx_id1
    cpy #SFX_MULTIBALL
    bne .ch1_ok
    ldy sfx_tmr1
    bne .ch1_skip
.ch1_ok
    sta sfx_id1
    tay
    lda sfx_dur_tbl,y
    sta sfx_tmr1
.ch1_skip
    rts

sfx_dur_tbl
    .byte 0, 5, 10, 7, 10, 3, 16, 24, 28, 48, 30

sound_update
    ; --- Channel 0 ---
    lda sfx_tmr0
    bne .upd_ch0
    sta AUDV0
    jmp .check_ch1

.upd_ch0
    dec sfx_tmr0
    lda sfx_id0
    cmp #SFX_FLIPPER
    beq .ch0_flipper
    cmp #SFX_SLING
    beq .ch0_sling
    cmp #SFX_SPINNER
    beq .ch0_spinner
    ; SFX_LAUNCH: ascending whoosh
    lda #$08
    sta AUDC0
    lda sfx_tmr0
    clc
    adc #8
    sta AUDF0
    lda #10
    sta AUDV0
    jmp .check_ch1

.ch0_flipper
    lda #$0C
    sta AUDC0
    lda #18
    sec
    sbc sfx_tmr0
    sta AUDF0
    lda #12
    sta AUDV0
    jmp .check_ch1

.ch0_sling
    lda #$06
    sta AUDC0
    lda #14
    clc
    adc sfx_tmr0
    sta AUDF0
    lda #12
    sta AUDV0
    jmp .check_ch1

.ch0_spinner
    lda #$04
    sta AUDC0
    lda #6
    sta AUDF0
    lda #9
    sta AUDV0

.check_ch1
    ; --- Channel 1 ---
    lda sfx_tmr1
    bne .upd_ch1
    sta AUDV1
    rts

.upd_ch1
    dec sfx_tmr1
    lda sfx_id1
    cmp #SFX_BUMPER
    beq .ch1_bumper
    cmp #SFX_TARGET
    beq .ch1_target
    cmp #SFX_RAMP
    beq .ch1_ramp
    cmp #SFX_LOCK
    beq .ch1_lock
    cmp #SFX_MULTIBALL
    beq .ch1_multiball

    ; SFX_DRAIN: descending sad warble
    lda #$0C
    sta AUDC1
    lda #31
    sec
    sbc sfx_tmr1
    sta AUDF1
    lda #10
    sta AUDV1
    rts

.ch1_bumper
    lda #$04
    sta AUDC1
    lda sfx_tmr1
    and #2
    beq .bmp_hi
    lda #11
    bne .bmp_set
.bmp_hi
    lda #7
.bmp_set
    sta AUDF1
    lda #12
    sta AUDV1
    rts

.ch1_target
    lda #$0C
    sta AUDC1
    lda sfx_tmr1
    lsr
    clc
    adc #5
    sta AUDF1
    lda #11
    sta AUDV1
    rts

.ch1_ramp
    lda #$04
    sta AUDC1
    lda sfx_tmr1
    lsr
    clc
    adc #4
    sta AUDF1
    lda #12
    sta AUDV1
    rts

.ch1_lock
    lda #$0C
    sta AUDC1
    lda sfx_tmr1
    lsr
    lsr
    tax
    lda lock_notes,x
    sta AUDF1
    lda #13
    sta AUDV1
    rts

.ch1_multiball
    lda #$04
    sta AUDC1
    lda sfx_tmr1
    lsr
    and #7
    tax
    lda mball_notes,x
    sta AUDF1
    lda #14
    sta AUDV1
    rts

lock_notes
    .byte 6, 8, 10, 12, 15, 18, 20, 24

mball_notes
    .byte 5, 7, 9, 12, 6, 8, 11, 14
