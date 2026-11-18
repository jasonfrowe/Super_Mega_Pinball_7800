; ===========================================================================
; Physics: balls, walls, posts, bumpers and flippers, on the math unit.
;
; Units: positions in 1/16 unit (a unit is half a 160A pixel across, one
; line down), carried with 8 more bits of fraction: X = xh:xl.xf. Velocity
; in 1/256 unit per frame. Gravity pulls down the table.
;
; Every collider is tested the same way: the ball's offset from the
; collider's start point goes into the CORDIC turned by minus the
; collider's angle, which gives at once the distance along it (XR), the
; distance off it (YR), and the straight distance and direction to the
; start point (LEN, ANG). A hit gives a normal angle and a depth; the
; response turns the velocity into the normal's frame (one more CORDIC
; write), bounces the normal part (multiplied by the collider's
; elasticity on the multiplier), and turns it back.
;
; Flippers are the same, in the frame of the turning flipper: the surface
; under the ball moves at (angular speed) x (distance from the pivot), so a
; shot off the tip is faster than one near the pivot, a ball can be
; cradled, caught, and passed. The right flipper is the left one mirrored.
;
; A frame is split in 1, 2 or 4 substeps per ball by its speed, so no ball
; moves more than about 3 units between tests.
; ===========================================================================

MAXB        = 3
GRAV        = 30            ; 1/256 unit / frame^2
VMAX        = 3000          ; 11.7 units / frame
DEPTH       = 96            ; a one-sided wall catches balls up to 6 units behind it
EV_MIN      = 100           ; impact speed that counts as a hit
KICK_BUMP   = 1150
KICK_SLING  = 1000
FLIP_UPSPD  = 2730          ; 15 degrees a frame
FLIP_DNSPD  = 1600
FLIP_E      = 70
F_KICK      = 4

; --- zero page ---
bxf     = $60
bxl     = $61
bxh     = $62
byf     = $63
byl     = $64
byh     = $65
vxl     = $66
vxh     = $67
vyl     = $68
vyh     = $69
blay    = $6A
incx    = $6B   ; 3
incy    = $6E   ; 3
shiftk  = $71
nsub    = $72
subidx  = $73
cptr    = $74   ; 2
cidx    = $76
ci      = $77
phil    = $78
phih    = $79
dl      = $7A
dh      = $7B
tA      = $7C   ; 2
tB      = $7E   ; 2
alongl  = $80
alongh  = $81
perpl   = $82
perph   = $83
cole    = $84
colf    = $85
colev   = $86
impl    = $87
imph    = $88
vtl     = $89
vth     = $8A
mirror  = $8B
bidx    = $8C
ul      = $8D
uh      = $8E
substep = $8F
vchg    = $5F   ; velocity changed: recompute the step
cellidx = $56   ; the grid cell the ball was last tested in

; --- RAM ---
b_act   = $2300 ; 0 none, 1 rolling, 2 held (lock), 3 waiting
b_xf    = $2303
b_xl    = $2306
b_xh    = $2309
b_yf    = $230C
b_yl    = $230F
b_yh    = $2312
b_vxl   = $2315
b_vxh   = $2318
b_vyl   = $231B
b_vyh   = $231E
b_lay   = $2321
b_sen0  = $2324
b_sen1  = $2327
b_hold  = $232A
fl_angl = $2330 ; [2] left, right
fl_angh = $2332
fl_Wl   = $2334
fl_Wh   = $2336
fl_in   = $2338 ; [2] button held
fl_move = $233A ; nonzero if either flipper moved this frame
fl_subl = $2340 ; [10] angle at substep 0..4, side*5+s
fl_subh = $234A
drops_down = $2356
evq     = $2358 ; [8] events
evqb    = $2360 ; [8] the ball of each
evq_w   = $2368
evq_r   = $2369
plg_pull = $236A ; plunger pulled back, units (0..24)
ptmp    = $236B
ptmp2   = $236C
sen_byte = $236D
sen_bit = $236E
bx2     = $236F
by2     = $2370
kicked  = $2371
eff_l   = $2372
eff_h   = $2373

EV_DRAIN = $80

; ---------------------------------------------------------------------------
    SUBROUTINE
phys_init
    ldx #MAXB-1
    lda #0
.pi
    sta b_act,x
    dex
    bpl .pi
    lda #<FLIP_REST
    sta fl_angl
    sta fl_angl+1
    lda #>FLIP_REST
    sta fl_angh
    sta fl_angh+1
    lda #0
    sta drops_down
    sta evq_w
    sta evq_r
    sta plg_pull
    rts

; phys_step: one frame
    SUBROUTINE
phys_step
    jsr phys_flippers
    ldx #0
.balls
    stx bidx
    lda b_act,x
    cmp #1
    bne .nb
    jsr ball_load
    jsr ball_frame
    ldx bidx
    jsr ball_store
.nb
    ldx bidx
    inx
    cpx #MAXB
    bne .balls
    jmp ball_pairs

    SUBROUTINE
ball_load
    lda b_xf,x
    sta bxf
    lda b_xl,x
    sta bxl
    lda b_xh,x
    sta bxh
    lda b_yf,x
    sta byf
    lda b_yl,x
    sta byl
    lda b_yh,x
    sta byh
    lda b_vxl,x
    sta vxl
    lda b_vxh,x
    sta vxh
    lda b_vyl,x
    sta vyl
    lda b_vyh,x
    sta vyh
    lda b_lay,x
    sta blay
    rts

    SUBROUTINE
ball_store
    lda bxf
    sta b_xf,x
    lda bxl
    sta b_xl,x
    lda bxh
    sta b_xh,x
    lda byf
    sta b_yf,x
    lda byl
    sta b_yl,x
    lda byh
    sta b_yh,x
    lda vxl
    sta b_vxl,x
    lda vxh
    sta b_vxh,x
    lda vyl
    sta b_vyl,x
    lda vyh
    sta b_vyh,x
    lda blay
    sta b_lay,x
    rts

; ---------------------------------------------------------------------------
; One ball, one frame
    SUBROUTINE
ball_frame
    ; gravity
    clc
    lda vyl
    adc #GRAV
    sta vyl
    bcc .g
    inc vyh
.g
    jsr clamp_speed

    ; substeps: by the larger speed's high byte; 4 near a moving flipper
    lda vxh
    bpl .ax
    eor #$FF
.ax
    sta ptmp
    lda vyh
    bpl .ay
    eor #$FF
.ay
    cmp ptmp
    bcs .am
    lda ptmp
.am
    ldx #4                  ; shift: inc = V << 4 (one substep)
    ldy #1
    cmp #3
    bcc .ns
    ldx #3
    ldy #2
    cmp #6
    bcc .ns
    ldx #2
    ldy #4
.ns
    ; a moving flipper near: 4 substeps
    lda fl_move
    beq .ns2
    lda byh
    cmp #>(FLIP_Y-640)
    bcc .ns2
    ldx #2
    ldy #4
.ns2
    stx shiftk
    sty nsub
    lda #4
    cpy #1
    beq .ss
    lsr
    cpy #2
    beq .ss
    lsr
.ss
    sta substep             ; flipper angle index step: 4 / nsub
    lda #0
    sta subidx

    jsr calc_inc
.sub
    lda subidx
    clc
    adc substep
    sta subidx
    lda vchg
    beq .same
    jsr calc_inc
.same
    ; move
    clc
    lda bxf
    adc incx
    sta bxf
    lda bxl
    adc incx+1
    sta bxl
    lda bxh
    adc incx+2
    sta bxh
    clc
    lda byf
    adc incy
    sta byf
    lda byl
    adc incy+1
    sta byl
    lda byh
    adc incy+2
    sta byh

    jsr plunger_floor
    jsr coll_grid
    jsr flip_coll
    dec nsub
    bne .sub

    ; drained?
    lda byl
    cmp #<(476*16)
    lda byh
    sbc #>(476*16)
    bcc .nd
    bmi .nd
    ldx bidx
    lda #0
    sta b_act,x
    lda #EV_DRAIN
    jmp push_event
.nd
    ; lost outside the table? put it back in the middle
    lda bxh
    cmp #>(320*16)
    bcs .rescue
    lda byh
    bmi .rescue
    jmp sensors
.rescue
    lda #<(150*16)
    sta bxl
    lda #>(150*16)
    sta bxh
    lda #<(200*16)
    sta byl
    lda #>(200*16)
    sta byh
    lda #0
    sta vxl
    sta vxh
    sta vyl
    sta vyh
    lda #LAYER_PF
    sta blay
    rts

; inc = V << shiftk, 24 bits
    SUBROUTINE
calc_inc
    lda #0
    sta vchg
    lda vxl
    sta incx
    lda vxh
    sta incx+1
    and #$80
    beq .x1
    lda #$FF
.x1
    sta incx+2
    lda vyl
    sta incy
    lda vyh
    sta incy+1
    and #$80
    beq .y1
    lda #$FF
.y1
    sta incy+2
    ldx shiftk
.sh
    asl incx
    rol incx+1
    rol incx+2
    asl incy
    rol incy+1
    rol incy+2
    dex
    bne .sh
    rts

; speed limit: |V| <= VMAX, keeping the direction
    SUBROUTINE
clamp_speed
    lda vxh
    bpl .p1
    eor #$FF
.p1
    cmp #>VMAX
    bcs .cl
    lda vyh
    bpl .p2
    eor #$FF
.p2
    cmp #>VMAX
    bcs .cl
    rts
.cl
    lda vxl
    sta M_X
    lda vxh
    sta M_X+1
    lda vyl
    sta M_Y
    lda vyh
    sta M_Y+1
    lda M_LEN
    cmp #<VMAX
    lda M_LEN+1
    sbc #>VMAX
    bcc .ok
    lda M_T                 ; direction
    sta ptmp
    lda M_T+1
    sta ptmp2
    lda #<VMAX
    sta M_X
    lda #>VMAX
    sta M_X+1
    lda #0
    sta M_Y
    sta M_Y+1
    lda ptmp
    sta M_T
    lda ptmp2
    sta M_T+1
    lda M_X
    sta vxl
    lda M_X+1
    sta vxh
    lda M_Y
    sta vyl
    lda M_Y+1
    sta vyh
.ok
    rts

; The plunger is the shooter lane's floor
PLG_REST = 450              ; ball center at rest, units
    SUBROUTINE
plunger_floor
    lda bxl
    cmp #<(291*16)
    lda bxh
    sbc #>(291*16)
    bcc .no
    lda plg_pull
    clc
    adc #<PLG_REST
    sta tA
    lda #>PLG_REST
    adc #0
    sta tA+1
    ; tA *= 16
    ldx #4
.m
    asl tA
    rol tA+1
    dex
    bne .m
    lda byl
    cmp tA
    lda byh
    sbc tA+1
    bcc .no
    lda tA
    sta byl
    lda tA+1
    sta byh
    lda #0
    sta byf
    lda vyh
    bmi .no
    lda #0
    sta vyl
    sta vyh
    sta vxl
    sta vxh
    lda #1
    sta vchg
.no
    rts

; ---------------------------------------------------------------------------
; Colliders near the ball (the grid cell it is in)
    SUBROUTINE
coll_grid
    ; the ball in 2-unit steps, for the colliders' boxes
    lda bxh
    sta ptmp
    lda bxl
    lsr ptmp
    ror
    lsr ptmp
    ror
    lsr ptmp
    ror
    lsr ptmp
    ror
    lsr ptmp
    ror
    sta bx2
    lda byh
    sta ptmp
    lda byl
    lsr ptmp
    ror
    lsr ptmp
    ror
    lsr ptmp
    ror
    lsr ptmp
    ror
    lsr ptmp
    ror
    sta by2
    lda #$FF
    sta cellidx
    lda byh
    lsr
    cmp #GRIDH
    bcs .r
    tax
    lda mul10,x
    sta ptmp
    lda bxh
    lsr
    cmp #GRIDW
    bcs .r
    clc
    adc ptmp
    sta cellidx
    tax
    lda grid_lo,x
    sta cptr
    lda grid_hi,x
    sta cptr+1
    ldy #0
.l
    lda (cptr),y
    cmp #$FF
    beq .r
    sty cidx
    sta ci
    tax
    jsr coll_one
    ldy cidx
    iny
    bne .l
.r
    rts

    SUBROUTINE
mul10
    .byte 0,10,20,30,40,50,60,70,80,90,100,110,120,130,140,150

dropbit .byte 1,2,4,8

    SUBROUTINE
coll_one
    lda by2
    cmp col_by0,x
    bcc .no
    cmp col_by1,x
    bcs .no
    lda bx2
    cmp col_bx0,x
    bcc .no
    cmp col_bx1,x
    bcs .no
    lda col_lay,x
    and blay
    beq .no
    lda col_drop,x
    beq .up
    tay
    lda dropbit-1,y
    and drops_down
    bne .no
.up
    sec
    lda bxl
    sbc col_axl,x
    sta M_X
    lda bxh
    sbc col_axh,x
    sta M_X+1
    sec
    lda byl
    sbc col_ayl,x
    sta M_Y
    lda byh
    sbc col_ayh,x
    sta M_Y+1
    lda col_kind,x
    sta colf
    lda col_e,x
    sta cole
    lda col_ev,x
    sta colev
    lda #0
    sta ul
    sta uh
    sta mirror
    lda colf
    and #3
    beq .seg
    cmp #1
    bne .circ
    jmp .caps
.no
    rts

.circ
    lda col_r,x
    clc
    adc #<BALL_R
    sta tA
    lda #0
    adc #>BALL_R
    sta tA+1
    lda M_LEN
    cmp tA
    lda M_LEN+1
    sbc tA+1
    bcs .no
    sec
    lda tA
    sbc M_LEN
    sta dl
    lda tA+1
    sbc M_LEN+1
    sta dh
    lda M_T
    sta phil
    lda M_T+1
    sta phih
    jmp resp_ev

.seg
    sec
    lda #0
    sbc col_tl,x
    sta M_T
    lda #0
    sbc col_th,x
    sta M_T+1
    lda M_X
    sta alongl
    lda M_X+1
    sta alongh
    lda M_Y
    sta perpl
    lda M_Y+1
    sta perph
    ; -3 units <= along <= L + 3 units
    lda alongl
    clc
    adc #48
    sta tA
    lda alongh
    adc #0
    bmi .no
    sta tA+1
    lda col_ll,x
    clc
    adc #96
    sta tB
    lda col_lh,x
    adc #0
    sta tB+1
    lda tB
    cmp tA
    lda tB+1
    sbc tA+1
    bcs *+5
    jmp .no
    ; depth d = perp + r: 0 < d, perp < DEPTH
    lda perpl
    clc
    adc #<BALL_R
    sta dl
    lda perph
    adc #>BALL_R
    sta dh
    bmi .no2
    ora dl
    beq .no2
    lda perpl
    cmp #<DEPTH
    lda perph
    sbc #>DEPTH
    bpl .no2
    ; behind the line and heading for the front: passing a gate
    lda perph
    bmi .front
    lda vxl
    sta M_X
    lda vxh
    sta M_X+1
    lda vyl
    sta M_Y
    lda vyh
    sta M_Y+1
    lda M_Y+1
    bmi .no2
.front
    lda col_tl,x
    sta phil
    lda col_th,x
    sec
    sbc #$40
    sta phih
    jmp resp_ev
.no2
    rts

.caps
    sec
    lda #0
    sbc col_tl,x
    sta M_T
    lda #0
    sbc col_th,x
    sta M_T+1
    lda col_r,x
    clc
    adc #<BALL_R
    sta tA
    lda #0
    adc #>BALL_R
    sta tA+1
    lda M_X
    sta alongl
    lda M_X+1
    sta alongh
    bmi .capA
    lda M_Y
    sta perpl
    lda M_Y+1
    sta perph
    lda col_ll,x
    cmp alongl
    lda col_lh,x
    sbc alongh
    bcc .capB
    ; |perp| < R + r
    lda perph
    bpl .pp
    sec
    lda #0
    sbc perpl
    sta tB
    lda #0
    sbc perph
    sta tB+1
    jmp .pc
.pp
    lda perpl
    sta tB
    lda perph
    sta tB+1
.pc
    lda tB
    cmp tA
    lda tB+1
    sbc tA+1
    bcs .no2
    sec
    lda tA
    sbc tB
    sta dl
    lda tA+1
    sbc tB+1
    sta dh
    lda col_tl,x
    sta phil
    lda perph
    bmi .pm
    lda col_th,x
    clc
    adc #$40
    sta phih
    jmp resp_ev
.pm
    lda col_th,x
    sec
    sbc #$40
    sta phih
    jmp resp_ev
.capA
    lda M_LEN
    cmp tA
    lda M_LEN+1
    sbc tA+1
    bcc *+5
    jmp .no2
    sec
    lda tA
    sbc M_LEN
    sta dl
    lda tA+1
    sbc M_LEN+1
    sta dh
    lda M_T
    sta phil
    lda M_T+1
    sta phih
    jmp resp_ev
.capB
    sec
    lda alongl
    sbc col_ll,x
    sta M_X
    lda alongh
    sbc col_lh,x
    sta M_X+1
    lda perpl
    sta M_Y
    lda perph
    sta M_Y+1
    lda M_LEN
    cmp tA
    lda M_LEN+1
    sbc tA+1
    bcs .no3
    sec
    lda tA
    sbc M_LEN
    sta dl
    lda tA+1
    sbc M_LEN+1
    sta dh
    clc
    lda M_T
    adc col_tl,x
    sta phil
    lda M_T+1
    adc col_th,x
    sta phih
    jmp resp_ev
.no3
    rts

; resp, then an event if the hit was hard enough (or kicked)
    SUBROUTINE
resp_ev
    jsr resp
    lda colev
    beq .r
    lda kicked
    bne .ev
    lda imph
    bne .ev
    lda impl
    cmp #EV_MIN
    bcc .r
.ev
    lda colev
    jmp push_event
.r
    rts

    SUBROUTINE
push_event
    ldx evq_w
    sta evq,x
    lda bidx
    sta evqb,x
    inx
    txa
    and #7
    sta evq_w
    rts

; ---------------------------------------------------------------------------
; resp: the ball touches a surface with normal angle phi (pointing at the
; ball), d deep. Push it out; bounce its velocity relative to the surface
; (normal speed u) with elasticity cole; kick if colf says so.
; mirror: the x axis is flipped (right flipper).
    SUBROUTINE
resp
    lda #1
    sta vchg
    lda #0
    sta kicked
    sta impl
    sta imph
    lda dl
    sta M_X
    lda dh
    sta M_X+1
    lda #0
    sta M_Y
    sta M_Y+1
    lda phil
    sta M_T
    lda phih
    sta M_T+1
    lda mirror
    bne .pm
    clc
    lda bxl
    adc M_X
    sta bxl
    lda bxh
    adc M_X+1
    sta bxh
    jmp .py
.pm
    sec
    lda bxl
    sbc M_X
    sta bxl
    lda bxh
    sbc M_X+1
    sta bxh
.py
    clc
    lda byl
    adc M_Y
    sta byl
    lda byh
    adc M_Y+1
    sta byh

    ; velocity into the normal's frame: XR = vr (away +), YR = vt
    lda mirror
    beq .vx
    sec
    lda #0
    sbc vxl
    sta M_X
    lda #0
    sbc vxh
    sta M_X+1
    jmp .vy
.vx
    lda vxl
    sta M_X
    lda vxh
    sta M_X+1
.vy
    lda vyl
    sta M_Y
    lda vyh
    sta M_Y+1
    sec
    lda #0
    sbc phil
    sta M_T
    lda #0
    sbc phih
    sta M_T+1
    lda M_Y
    sta vtl
    lda M_Y+1
    sta vth
    ; rel = vr - u; approaching if < 0
    sec
    lda M_X
    sbc ul
    sta tB
    lda M_X+1
    sbc uh
    sta tB+1
    bmi *+5
    jmp .sep
    ; impact = -rel
    sec
    lda #0
    sbc tB
    sta impl
    lda #0
    sbc tB+1
    sta imph
    ; new vr = u + impact * e
    lda impl
    sta M_A
    lda imph
    sta M_A+1
    lda cole
    sta M_B
    lda #0
    sta M_B+1
    lda M_P+1
    sta tB
    lda M_P+2
    sta tB+1
    ; a slow touch doesn't bounce (rolling along a wall)
    lda imph
    bne .big
    lda impl
    cmp #48
    bcs .big
    lda #0
    sta tB
    sta tB+1
.big
    clc
    lda tB
    adc ul
    sta tB
    lda tB+1
    adc uh
    sta tB+1
    ; kickers
    lda colf
    and #F_KICK
    beq .back
    lda colf
    and #3
    cmp #2
    beq .bump
    lda imph
    bne .sk
    lda impl
    cmp #200
    bcc .back
.sk
    lda #<KICK_SLING
    sta tB
    lda #>KICK_SLING
    sta tB+1
    sta kicked
    jmp .back
.bump
    lda #<KICK_BUMP
    sta tB
    lda #>KICK_BUMP
    sta tB+1
    sta kicked
.back
    lda tB
    sta M_X
    lda tB+1
    sta M_X+1
    lda vtl
    sta M_Y
    lda vth
    sta M_Y+1
    lda phil
    sta M_T
    lda phih
    sta M_T+1
    lda M_Y
    sta vyl
    lda M_Y+1
    sta vyh
    lda mirror
    bne .bm
    lda M_X
    sta vxl
    lda M_X+1
    sta vxh
    rts
.bm
    sec
    lda #0
    sbc M_X
    sta vxl
    lda #0
    sbc M_X+1
    sta vxh
.sep
    rts

; ---------------------------------------------------------------------------
; Flippers: move them (once a frame), keep the angle at each quarter frame
    SUBROUTINE
phys_flippers
    lda #0
    sta fl_move
    ldx #1
.f
    lda fl_in,x
    bne .up
    lda fl_angl,x
    cmp #<FLIP_REST
    bne .down
    lda fl_angh,x
    cmp #>FLIP_REST
    bne .down
    lda fl_Wl,x
    ora fl_Wh,x
    bne .down               ; (once more, to set the substeps and W = 0)
    jmp .nextf
.up
    ; up: ang -= UPSPD, not past FLIP_UPANG
    sec
    lda fl_angl,x
    sbc #<FLIP_UPSPD
    sta tA
    lda fl_angh,x
    sbc #>FLIP_UPSPD
    sta tA+1
    lda tA
    cmp #<FLIP_UPANG
    lda tA+1
    sbc #>FLIP_UPANG
    bvc .v1
    eor #$80
.v1
    bpl .set
    lda #<FLIP_UPANG
    sta tA
    lda #>FLIP_UPANG
    sta tA+1
    jmp .set
.down
    clc
    lda fl_angl,x
    adc #<FLIP_DNSPD
    sta tA
    lda fl_angh,x
    adc #>FLIP_DNSPD
    sta tA+1
    lda #<FLIP_REST
    cmp tA
    lda #>FLIP_REST
    sbc tA+1
    bvc .v2
    eor #$80
.v2
    bpl .set
    lda #<FLIP_REST
    sta tA
    lda #>FLIP_REST
    sta tA+1
.set
    ; eff = new - old
    sec
    lda tA
    sbc fl_angl,x
    sta eff_l
    lda tA+1
    sbc fl_angh,x
    sta eff_h
    ora eff_l
    beq .still
    inc fl_move
.still
    ; quarter steps: sub[s] = old + eff*s/4
    txa
    asl
    asl
    stx ptmp
    clc
    adc ptmp                ; side*5
    tay
    lda fl_angl,x
    sta fl_subl,y
    sta tB
    lda fl_angh,x
    sta fl_subh,y
    sta tB+1
    ; eff/4 (arithmetic)
    lda eff_l
    sta ptmp
    lda eff_h
    sta ptmp2
    cmp #$80
    ror ptmp2
    ror ptmp
    lda ptmp2
    cmp #$80
    ror ptmp2
    ror ptmp
    lda #3
    sta cidx
.q
    iny
    clc
    lda tB
    adc ptmp
    sta tB
    sta fl_subl,y
    lda tB+1
    adc ptmp2
    sta tB+1
    sta fl_subh,y
    dec cidx
    bne .q
    iny
    lda tA
    sta fl_subl,y
    sta fl_angl,x
    lda tA+1
    sta fl_subh,y
    sta fl_angh,x
    ; W = eff * 101 / 256: surface speed = W * along / 256
    lda eff_l
    sta M_A
    lda eff_h
    sta M_A+1
    lda #101
    sta M_B
    lda #0
    sta M_B+1
    lda M_P+1
    sta fl_Wl,x
    lda M_P+2
    sta fl_Wh,x
.nextf
    dex
    bmi .fd
    jmp .f
.fd
    rts

; In a substep: the ball against both flippers
FLX_REACH = 60*16
    SUBROUTINE
flip_coll
    ; near the flippers' line at all?
    sec
    lda byl
    sbc #<FLIP_Y
    sta tB
    lda byh
    sbc #>FLIP_Y
    sta tB+1
    ; -40 .. +36 units
    clc
    lda tB
    adc #<(40*16)
    lda tB+1
    adc #>(40*16)
    bpl *+5
    jmp .r
    cmp #>(76*16)
    bcc *+5
    jmp .r
    lda #0
    sta mirror
    jsr .one
    lda #1
    sta mirror
.one
    ldx mirror
    ; dx in the flipper's frame (mirrored for the right one)
    lda mirror
    bne .rx
    sec
    lda bxl
    sbc #<FLIPL_X
    sta tA
    lda bxh
    sbc #>FLIPL_X
    sta tA+1
    jmp .dx
.rx
    sec
    lda #<FLIPR_X
    sbc bxl
    sta tA
    lda #>FLIPR_X
    sbc bxh
    sta tA+1
.dx
    ; -16 .. +60 units
    clc
    lda tA
    adc #<(16*16)
    lda tA+1
    adc #>(16*16)
    bpl *+5
    jmp .r
    cmp #>(76*16)
    bcc *+5
    jmp .r
    lda tA
    sta M_X
    lda tA+1
    sta M_X+1
    lda tB
    sta M_Y
    lda tB+1
    sta M_Y+1
    ; T = -angle at this substep
    txa
    asl
    asl
    stx ptmp
    clc
    adc ptmp
    adc subidx
    tay
    sec
    lda #0
    sbc fl_subl,y
    sta M_T
    lda #0
    sbc fl_subh,y
    sta M_T+1
    lda fl_subl,y
    sta phil
    lda fl_subh,y
    sta phih
    lda M_X
    sta alongl
    lda M_X+1
    sta alongh
    lda M_Y
    sta perpl
    lda M_Y+1
    sta perph
    lda #FLIP_E
    sta cole
    lda #0
    sta colf
    sta colev
    sta ul
    sta uh
    lda #<(FLIP_RAD+BALL_R)
    sta dl
    lda alongh
    bpl .alongp
    ; behind the pivot: the pivot's round end
    lda M_LEN+1
    bne .r
    lda M_LEN
    cmp #<(FLIP_RAD+BALL_R)
    bcs .r
    sec
    lda #<(FLIP_RAD+BALL_R)
    sbc M_LEN
    sta dl
    lda #0
    sta dh
    lda M_T
    sta phil
    lda M_T+1
    sta phih
    jmp resp
.r
    rts
.alongp
    ; past the tip?
    lda alongl
    cmp #<(FLIP_LEN+FLIP_RAD)
    lda alongh
    sbc #>(FLIP_LEN+FLIP_RAD)
    bcs .r
    ; |perp| < R + r
    lda perph
    bpl .pp
    sec
    lda #0
    sbc perpl
    sta tA
    lda #0
    sbc perph
    bne .r
    jmp .pc
.pp
    lda perph
    bne .r
    lda perpl
    sta tA
.pc
    lda tA
    cmp #<(FLIP_RAD+BALL_R)
    bcs .r
    sec
    lda #<(FLIP_RAD+BALL_R)
    sbc tA
    sta dl
    lda #0
    sta dh
    ; surface speed at this point: W * along / 256, toward +perp
    ; lever = (along + length) / 2: even a shot off the base has some snap
    ldx mirror
    lda fl_Wl,x
    sta M_A
    lda fl_Wh,x
    sta M_A+1
    clc
    lda alongl
    adc #<FLIP_LEN
    sta tB
    lda alongh
    adc #>FLIP_LEN
    lsr
    sta M_B+1
    lda tB
    ror
    sta M_B
    lda M_P+1
    sta ul
    lda M_P+2
    sta uh
    lda perph
    bmi .above
    ; ball below the flipper: normal = angle + 90, u as is
    clc
    lda phih
    adc #$40
    sta phih
    jmp resp
.above
    ; ball on top: normal = angle - 90; the surface moves toward -perp
    sec
    lda phih
    sbc #$40
    sta phih
    sec
    lda #0
    sbc ul
    sta ul
    lda #0
    sbc uh
    sta uh
    jmp resp

; ---------------------------------------------------------------------------
; Sensors: once a frame for the current ball
    SUBROUTINE
sensors
    ; (bx2, by2 and cellidx are coll_grid's, from the last substep)
    ldx bidx
    lda b_sen0,x
    sta tA
    lda b_sen1,x
    sta tA+1
    lda #0
    sta tB
    sta tB+1
    ldx cellidx
    cpx #$FF
    bne .cell
    jmp .end
.cell
    lda sgrid_lo,x
    sta cptr
    lda sgrid_hi,x
    sta cptr+1
    lda #0
    sta cidx
.s
    ldy cidx
    lda (cptr),y
    cmp #$FF
    bne .s0
    jmp .end
.s0
    inc cidx
    tay
    lda bx2
    cmp sen_x0,y
    bcc .out
    lda sen_x1,y
    cmp bx2
    bcc .out
    lda by2
    cmp sen_y0,y
    bcc .out
    lda sen_y1,y
    cmp by2
    bcc .out
    ; inside: set the bit in tB
    jsr senbit
    ora tB,x
    sta tB,x
    ; was it already?
    lda sen_bit
    and tA,x
    bne .out
    ; just entered: on our layer, the right way?
    lda sen_lay,y
    and blay
    beq .out
    lda sen_cond,y
    beq .fire
    cmp #1
    bne .cdown
    lda vyh
    bpl .out
    bmi .fire
.cdown
    lda vyh
    bmi .out
.fire
    lda sen_set,y
    beq .ns
    sta blay
.ns
    sty ptmp2
    lda sen_ev,y
    jsr push_event
    ldy ptmp2
.out
    jmp .s
.end
    ldx bidx
    lda tB
    sta b_sen0,x
    lda tB+1
    sta b_sen1,x
    ; on the ramp but nowhere near it: back on the playfield
    lda blay
    cmp #LAYER_RAMP
    bne .sr
    lda by2
    cmp #136
    bcc .sr
    lda bx2
    cmp #34                 ; (x > 68: right of the ramp's lanes)
    bcc .sr
    lda #LAYER_PF
    sta blay
.sr
    rts

; sensor Y -> X = byte (0/1), A = sen_bit = its bit
    SUBROUTINE
senbit
    tya
    and #7
    tax
    lda bits8,x
    sta sen_bit
    ldx #0
    cpy #8
    bcc .b
    inx
.b
    lda sen_bit
    rts

bits8 .byte 1,2,4,8,16,32,64,128

LAYER_PF   = 1
LAYER_RAMP = 2

