; ===========================================================================
; Physics, continued (in the $B000 segment)
; ===========================================================================

; ---------------------------------------------------------------------------
; Balls against each other (multiball), once a frame
    SUBROUTINE
ball_pairs
    ldx #0
    ldy #1
    jsr .pair
    ldx #0
    ldy #2
    jsr .pair
    ldx #1
    ldy #2
.pair
    lda b_act,x
    cmp #1
    beq *+5
    jmp .r
    lda b_act,y
    cmp #1
    beq *+5
    jmp .r
    lda b_lay,x
    and b_lay,y
    bne *+5
    jmp .r
    sec
    lda b_xl,x
    sbc b_xl,y
    sta M_X
    lda b_xh,x
    sbc b_xh,y
    sta M_X+1
    sec
    lda b_yl,x
    sbc b_yl,y
    sta M_Y
    lda b_yh,x
    sbc b_yh,y
    sta M_Y+1
    lda M_LEN+1
    beq *+5
    jmp .r
    lda M_LEN
    cmp #2*BALL_R
    bcc *+5
    jmp .r
    stx bidx
    sty cidx
    lda M_T
    sta phil
    lda M_T+1
    sta phih
    ; each moves half the overlap apart
    sec
    lda #2*BALL_R
    sbc M_LEN
    lsr
    adc #1
    sta dl
    lda #0
    sta dh
    sta ul
    sta uh
    sta colf
    sta colev
    sta mirror
    lda #230
    sta cole
    ; swap the normal parts of their velocities: do it as each ball
    ; bouncing off the other's normal speed
    ; velocity of Y along phi -> u for X
    lda b_vxl,y
    sta M_X
    lda b_vxh,y
    sta M_X+1
    lda b_vyl,y
    sta M_Y
    lda b_vyh,y
    sta M_Y+1
    sec
    lda #0
    sbc phil
    sta M_T
    lda #0
    sbc phih
    sta M_T+1
    lda M_X
    sta ul
    lda M_X+1
    sta uh
    ldx bidx
    jsr ball_load
    jsr resp
    ldx bidx
    jsr ball_store
    ; and Y off X, the other way round
    ldy cidx
    lda b_vxl,x
    sta M_X
    lda b_vxh,x
    sta M_X+1
    lda b_vyl,x
    sta M_Y
    lda b_vyh,x
    sta M_Y+1
    clc
    lda phih
    adc #$80
    sta phih
    sec
    lda #0
    sbc phil
    sta M_T
    lda #0
    sbc phih
    sta M_T+1
    lda M_X
    sta ul
    lda M_X+1
    sta uh
    ldx cidx
    jsr ball_load
    jsr resp
    ldx cidx
    jsr ball_store
.r
    rts
