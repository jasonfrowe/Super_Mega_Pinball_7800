; ===========================================================================
; The game: attract mode, rules and scoring, the plunger, the camera, what
; is drawn, the HUD.
;
; Rules (the table is "MEGA"):
;   M-E-G-A top lanes      light all four: bonus multiplier up (to 5X);
;                          the flippers move the lit lanes
;   pop bumpers            1,000
;   slingshots             100
;   3 drop targets         2,500 each; all down: LOCK IS LIT
;   the BLACK HOLE (lock)  lit: lock a ball; the second lock starts
;                          3-ball MULTIBALL. Unlit: 5,000
;   the wire RAMP          10,000 and up 5,000 each time; in multiball it
;                          scores the JACKPOT (50,000, up 25,000 each)
;   left orbit, all the way round: ORBIT 20,000
;   S-T-A-R standups       5,000; all three: 50,000
;   spinner                100 a turn
;   end of ball            bonus (ramps, orbits, targets) x multiplier
;   ball save              the first 10 seconds of each ball
; ===========================================================================

; --- RAM ($2400-) ---
g_state     = $2400 ; 0 attract, 1 playing, 2 between balls, 3 game over
score       = $2401 ; [5] BCD, score+0 = most significant
hiscore     = $2406 ; [5]
lastscore   = $240B ; [5]
pts         = $2410 ; [3] BCD points to add: pts+0 = 100k/10k, +1 = 1k/100, +2 = 10/1
g_ball      = $2413
g_bonusx    = $2414
g_lanes     = $2415
g_stand     = $2416
g_locks     = $2417
g_lock_lit  = $2418
g_mball     = $2419
g_ramps     = $241A
g_jack      = $241B ; jackpot in 10,000s (BCD)
g_save      = $2447 ; [2] ball save frames left
g_msg_t     = $241D
g_msg       = $241E
g_timer     = $241F
g_orbit_t   = $2420
g_spin      = $2421 ; spinner turns left (animation)
g_spin_a    = $2422
g_bumpf     = $2423 ; [3] bumper flash timers
in_now      = $2426 ; bits: 0 left, 1 right, 2 down, 3 up, 4 fire (either)
in_prev     = $2427
in_edge     = $2428
g_bonus     = $2429 ; bonus counter (units of 1,000, BCD)
g_attr_t    = $242A
g_attr_m    = $242B
cam_dir     = $242C
g_hudt      = $242D ; [20] HUD text being built (ASCII)
g_ballsave_msg = $2441
g_tmp       = $2442
g_tmp2      = $2443
g_launch    = $2444 ; frames until the shooter lane auto-launches (multiball)
g_lampanim  = $2445
g_tilt      = $2446
hud_shown   = $2449 ; the HUD shows the score line
hud_last    = $244A ; [5] the score it shows
g_skill     = $2450 ; skill shot lane + 1 (0: none)
g_skill_t   = $2451 ; frames left for it
g_tilted    = $2452
g_shake     = $2453 ; camera shake frames

; --- messages ---
MSG_TITLE   = 0
MSG_PRESS   = 1
MSG_HIGH    = 2
MSG_LOCKLIT = 3
MSG_LOCKED  = 4
MSG_MBALL   = 5
MSG_JACKPOT = 6
MSG_RAMP    = 7
MSG_ORBIT   = 8
MSG_MEGA    = 9
MSG_STAR    = 10
MSG_SAVED   = 11
MSG_BONUS   = 12
MSG_GAMEOVER = 13
MSG_HOLE    = 14
MSG_SHOOT   = 15
MSG_LAST    = 16
MSG_EXTRA   = 17
MSG_SKILL   = 18
MSG_TILT    = 19
MSG_WARN    = 20

; ---------------------------------------------------------------------------
    SUBROUTINE
game_init
    jsr phys_init
    lda #0
    sta g_state
    sta g_attr_t
    sta g_attr_m
    ldx #4
.hs
    lda #0
    sta score,x
    sta lastscore,x
    sta hiscore,x
    dex
    bpl .hs
    lda #$05                ; high score 500,000 to beat
    sta hiscore+2
    jsr lamps_clear
    jsr drops_reset
    lda #MUS_TITLE
    jmp mus_play

; ---------------------------------------------------------------------------
    SUBROUTINE
game_step
    jsr read_input
    ; console reset: back to attract
    lda SWCHB
    and #1
    bne .nr
    lda g_state
    beq .nr
    jsr to_attract
.nr
    lda g_msg_t
    beq .m0
    dec g_msg_t
.m0
    lda g_state
    bne *+5
    jmp attract_step
    cmp #1
    bne .s2
    jmp play_step
.s2
    cmp #2
    bne .s3
    jmp between_step
.s3
    jmp over_step

    SUBROUTINE
read_input
    lda in_now
    sta in_prev
    lda #0
    sta g_tmp
    lda SWCHA
    eor #$FF
    asl                     ; C = right
    rol g_tmp               ; bit 0 right
    asl                     ; left
    rol g_tmp
    asl                     ; down
    rol g_tmp
    asl                     ; up
    rol g_tmp
    ; g_tmp: bit3 right, bit2 left, bit1 down, bit0 up
    lda #0
    ldx g_tmp
    txa
    and #4
    beq .i1
    lda #1
.i1
    sta in_now
    txa
    and #8
    beq .i2
    lda in_now
    ora #2
    sta in_now
.i2
    txa
    and #2
    beq .i3
    lda in_now
    ora #4
    sta in_now
.i3
    txa
    and #1
    beq .i4
    lda in_now
    ora #8
    sta in_now
.i4
    ; buttons (two-button mode): INPT1 left, INPT0 right, bit 7 = pressed
    lda INPT1
    bpl .i5
    lda in_now
    ora #$11
    sta in_now
.i5
    lda INPT0
    bpl .i6
    lda in_now
    ora #$12
    sta in_now
.i6
    lda in_prev
    eor #$FF
    and in_now
    sta in_edge
    rts

; ---------------------------------------------------------------------------
    SUBROUTINE
attract_step
    ; pan the camera slowly up and down the table
    lda tick
    and #1
    bne .pan_done
    lda cam_dir
    bne .down
    lda cam_lo
    ora cam_hi
    beq .flip
    lda cam_lo
    bne .d1
    dec cam_hi
.d1
    dec cam_lo
    jmp .pan_done
.down
    lda cam_lo
    cmp #<MAXCAM
    lda cam_hi
    sbc #>MAXCAM
    bcs .flip
    inc cam_lo
    bne .pan_done
    inc cam_hi
    jmp .pan_done
.flip
    lda cam_dir
    eor #1
    sta cam_dir
.pan_done
    ; lamp show: a chase through all the lamps
    inc g_lampanim
    lda g_lampanim
    and #3
    bne .la
    ldx #NLAMPS-1
.lc
    txa
    clc
    adc g_lampanim
    and #8
    beq .loff
    lda #1
    .byte $2C
.loff
    lda #0
    sta lamp_state,x
    dex
    bpl .lc
    inc lamp_dirty
    jsr drops_lamps
.la
    ; HUD: title, press fire, high score, last score
    dec g_attr_t
    bne .ha
    lda #150
    sta g_attr_t
    inc g_attr_m
.ha
    lda g_attr_m
    and #3
    tax
    lda attr_msgs,x
    jsr hud_msg
    ; start?
    lda in_edge
    and #$10
    beq .ns
    jmp start_game
.ns
    rts

attr_msgs .byte MSG_TITLE, MSG_PRESS, MSG_HIGH, MSG_LAST

    SUBROUTINE
to_attract
    lda #0
    sta g_state
    ldx #MAXB-1
.ta
    sta b_act,x
    dex
    bpl .ta
    lda #150
    sta g_attr_t
    lda #MUS_TITLE
    jmp mus_play

    SUBROUTINE
start_game
    ldx #4
    lda #0
.sc
    sta score,x
    dex
    bpl .sc
    lda #1
    sta g_ball
    sta g_state
    lda #0
    sta g_locks
    sta g_lock_lit
    sta g_mball
    sta g_jack
    lda #$05
    sta g_jack              ; jackpot 50,000
    jsr new_ball_rules
    jsr serve_ball
    lda #MUS_MAIN
    jmp mus_play

    SUBROUTINE
new_ball_rules
    lda #0
    sta hud_shown
    sta g_tilted
    sta g_tilt
    ; skill shot: a random top lane flashes
    lda M_RND
    and #3
    clc
    adc #1
    sta g_skill
    lda #0
    sta g_skill_t
    lda #1
    sta g_bonusx
    lda #0
    sta g_lanes
    sta g_stand
    sta g_ramps
    sta g_bonus
    sta g_mball
    sta g_orbit_t
    sta plg_pull
    jsr lamps_clear
    jsr drops_reset
    lda #<600
    sta g_save
    lda #>600
    sta g_save+1
    lda #LAMP_SHOOT_AGAIN
    ldx #3
    jsr lamp_set
    lda g_lock_lit
    beq .nl
    lda #LAMP_LOCK_ARROW
    ldx #2
    jsr lamp_set
.nl
    lda #MSG_SHOOT
    jmp msg

; a ball in the shooter lane, on the plunger
    SUBROUTINE
serve_ball
    ldx #0
.f
    lda b_act,x
    beq .got
    inx
    cpx #MAXB
    bne .f
    rts
.got
    lda #1
    sta b_act,x
    lda #<(301*16)
    sta b_xl,x
    lda #>(301*16)
    sta b_xh,x
    lda #<(440*16)
    sta b_yl,x
    lda #>(440*16)
    sta b_yh,x
    lda #0
    sta b_xf,x
    sta b_yf,x
    sta b_vxl,x
    sta b_vxh,x
    sta b_vyl,x
    sta b_vyh,x
    sta b_sen0,x
    sta b_sen1,x
    lda #LAYER_PF
    sta b_lay,x
    rts

; ---------------------------------------------------------------------------
    SUBROUTINE
play_step
    ; flippers (dead after a tilt)
    lda g_tilted
    beq .ok
    lda #0
    sta fl_in
    sta fl_in+1
    jmp .nf
.ok
    lda in_now
    and #1
    sta fl_in
    lda in_now
    lsr
    and #1
    sta fl_in+1
    lda in_edge
    and #3
    beq .nf
    pha
    lda #SFX_FLIPPER
    jsr sfx
    pla
    ; lane change: left flipper rotates the lit lanes left, right right
    lsr
    bcc .lr
    lda g_lanes
    lsr
    bcc .l1
    ora #8
.l1
    sta g_lanes
    jmp .nf
.lr
    lda g_lanes
    asl
    cmp #16
    bcc .l2
    and #15
    ora #1
.l2
    sta g_lanes
.nf
    jsr plunger

    jsr phys_step
    jsr game_events
    jsr held_balls
    jsr ball_search

    ; timers
    lda g_save
    ora g_save+1
    beq .t1
    lda g_save
    bne .t0
    dec g_save+1
.t0
    dec g_save
    lda g_save
    ora g_save+1
    bne .t1
    lda #LAMP_SHOOT_AGAIN
    ldx #0
    jsr lamp_set
.t1
    lda g_orbit_t
    beq .t1a
    dec g_orbit_t
.t1a
    lda g_skill_t
    beq .t1b
    dec g_skill_t
    bne .t1b
    lda #0
    sta g_skill
.t1b
    lda g_tilt
    beq .t1c
    dec g_tilt
.t1c
    jsr nudge
.t2
    lda g_spin
    beq .t3
    dec g_spin
    lda g_spin_a
    clc
    adc g_spin
    sta g_spin_a
.t3
    ldx #2
.bf
    lda g_bumpf,x
    beq .bf1
    dec g_bumpf,x
    bne .bf1
    txa
    clc
    adc #LAMP_BUMPER0
    stx g_tmp
    ldx #0
    jsr lamp_set
    ldx g_tmp
.bf1
    dex
    bpl .bf
    jsr lane_lamps
    jsr auto_launch

    ; balls left on the table?
    ldx #MAXB-1
    lda #0
    sta g_tmp
.cnt
    lda b_act,x
    beq .c1
    inc g_tmp
.c1
    dex
    bpl .cnt
    lda g_tmp
    cmp #2
    bcs .cam
    ; multiball over
    lda g_mball
    beq .nm
    lda #0
    sta g_mball
    lda #LAMP_RAMP_ARROW
    ldx #0
    jsr lamp_set
    lda #MUS_MAIN           ; back to the game's tune
    jsr mus_play
.nm
    lda g_tmp
    bne .cam
    jmp ball_lost
.cam
    jmp camera

; Plunger: hold down to pull it back, let go to shoot
    SUBROUTINE
plunger
    lda in_now
    and #4
    beq .rel
    lda plg_pull
    cmp #24
    bcs .r
    inc plg_pull
    lda tick
    and #3
    bne .r
    lda #SFX_PULL
    jmp sfx
.rel
    lda plg_pull
    beq .r
    ; a ball resting on it?
    ldx #MAXB-1
.f
    lda b_act,x
    cmp #1
    bne .n
    lda b_xh,x
    cmp #>(291*16)
    bcc .n
    lda b_yh,x
    cmp #>(430*16)
    bcc .n
    ; vy = -(pull * 104 + 600)
    lda plg_pull
    sta M_A
    lda #0
    sta M_A+1
    lda #104
    sta M_B
    lda #0
    sta M_B+1
    clc
    lda M_P
    adc #<600
    sta g_tmp
    lda M_P+1
    adc #>600
    sta g_tmp2
    sec
    lda #0
    sbc g_tmp
    sta b_vyl,x
    lda #0
    sbc g_tmp2
    sta b_vyh,x
    lda #SFX_LAUNCH
    jsr sfx
    lda #240
    sta g_skill_t
.n
    dex
    bpl .f
    lda #0
    sta plg_pull
.r
    rts

; multiball: a ball served to the shooter lane launches itself
    SUBROUTINE
auto_launch
    lda g_launch
    beq .r
    dec g_launch
    bne .r
    lda #20
    sta plg_pull
    lda #0
    sta in_now              ; (plunger sees a release)
    jmp plunger
.r
    rts

; balls held in the BLACK HOLE: kick them out when their time is up
    SUBROUTINE
held_balls
    ldx #MAXB-1
.h
    lda b_act,x
    cmp #2
    bne .n
    dec b_hold,x
    bne .n
    lda #1
    sta b_act,x
    lda #<(LOCK_X*16-80)
    sta b_xl,x
    lda #>(LOCK_X*16-80)
    sta b_xh,x
    lda #<(LOCK_Y*16+180)
    sta b_yl,x
    lda #>(LOCK_Y*16+180)
    sta b_yh,x
    ; toward the left inlane, about 5 units a frame, spread by the RNG
    lda M_RND
    and #$7F
    clc
    adc #<(-780)
    sta b_vxl,x
    lda #>(-780)
    adc #0
    sta b_vxh,x
    lda M_RND
    and #$7F
    clc
    adc #<1000
    sta b_vyl,x
    lda #>1000
    adc #0
    sta b_vyh,x
    lda #0
    sta b_sen0,x
    sta b_sen1,x
    lda #LAYER_PF
    sta b_lay,x
    stx g_tmp
    lda #SFX_KICK
    jsr sfx
    ldx g_tmp
.n
    dex
    bpl .h
    rts

; ---------------------------------------------------------------------------
; Nudge: joystick up bumps the table: the balls jump a little, the camera
; shakes. Too often and it TILTs: the flippers die until the ball drains.
    SUBROUTINE
nudge
    lda in_edge
    and #8
    bne *+5
    jmp .r
    lda g_tilted
    bne .r
    lda #8
    sta g_shake
    lda #SFX_SLING
    jsr sfx
    ldx #MAXB-1
.b
    lda b_act,x
    cmp #1
    bne .n
    sec
    lda b_vyl,x
    sbc #200
    sta b_vyl,x
    lda b_vyh,x
    sbc #0
    sta b_vyh,x
    lda M_RND
    bpl .p
    lda b_vxl,x
    sec
    sbc #140
    sta b_vxl,x
    lda b_vxh,x
    sbc #0
    sta b_vxh,x
    jmp .n
.p
    lda b_vxl,x
    clc
    adc #140
    sta b_vxl,x
    lda b_vxh,x
    adc #0
    sta b_vxh,x
.n
    dex
    bpl .b
    ; tilt meter
    lda g_tilt
    clc
    adc #70
    bcs .tilt
    sta g_tilt
    cmp #120
    bcc .r
    lda #MSG_WARN
    jmp msg
.tilt
    lda #1
    sta g_tilted
    lda #0
    sta g_save
    sta g_save+1
    jsr lamps_clear
    lda #SFX_DRAIN
    jsr sfx
    lda #MSG_TILT
    jmp msg
.r
    rts

; ---------------------------------------------------------------------------
; Ball search: a ball resting somewhere other than a flipper (or the
; plunger) for two seconds gets a small random bump, as a real machine's
; ball search would free it.
b_still = $232D             ; [3] frames each ball has hardly moved
    SUBROUTINE
ball_search
    ldx #MAXB-1
.b
    lda b_act,x
    cmp #1
    bne .reset
    lda b_yh,x
    cmp #>(400*16)
    bcs .reset              ; down by the flippers or the plunger: fine
    ; |vx| and |vy| under 1/8 unit a frame?
    lda b_vxh,x
    beq .xp
    cmp #$FF
    bne .reset
    lda b_vxl,x
    cmp #$E0
    bcc .reset
    bcs .y
.xp
    lda b_vxl,x
    cmp #$20
    bcs .reset
.y
    lda b_vyh,x
    beq .yp
    cmp #$FF
    bne .reset
    lda b_vyl,x
    cmp #$E0
    bcc .reset
    bcs .still
.yp
    lda b_vyl,x
    cmp #$20
    bcs .reset
.still
    inc b_still,x
    lda b_still,x
    cmp #120
    bcc .n
    ; bump: up, and left or right at random
    lda #<-400
    sta b_vyl,x
    lda #>-400
    sta b_vyh,x
    lda M_RND
    bmi .left
    lda #<300
    sta b_vxl,x
    lda #>300
    sta b_vxh,x
    jmp .reset
.left
    lda #<-300
    sta b_vxl,x
    lda #>-300
    sta b_vxh,x
.reset
    lda #0
    sta b_still,x
.n
    dex
    bpl .b
    rts

; ---------------------------------------------------------------------------
    SUBROUTINE
ball_lost
    ; ball save?
    lda g_save
    ora g_save+1
    beq .lost
    lda #0
    sta g_save
    sta g_save+1
    jsr serve_ball
    lda #40
    sta g_launch
    lda #MSG_SAVED
    jmp msg
.lost
    lda #SFX_DRAIN
    jsr sfx
    lda g_tilted
    bne .nob
    ; bonus: g_bonus thousands x multiplier
    ldx g_bonusx
.bx
    lda #0
    sta pts
    lda g_bonus
    sta pts+1
    lda #0
    sta pts+2
    ; g_bonus is BCD thousands: pts+1 holds 1k/100 -> shift a digit
    lda g_bonus
    asl
    asl
    asl
    asl
    sta pts+1
    lda g_bonus
    lsr
    lsr
    lsr
    lsr
    sta pts
    jsr add_score
    dex
    bne .bx
    lda #MSG_BONUS
    jsr msg
.nob
    lda #2
    sta g_state
    lda #150
    sta g_timer
    rts

    SUBROUTINE
between_step
    jsr camera
    dec g_timer
    bne .r
    lda g_ball
    cmp #3
    bcs game_over
    inc g_ball
    lda #1
    sta g_state
    jsr new_ball_rules
    jmp serve_ball
.r
    rts

    SUBROUTINE
game_over
    lda #3
    sta g_state
    lda #240
    sta g_timer
    ldx #4
.c
    lda score,x
    sta lastscore,x
    dex
    bpl .c
    ; new high score?
    ldx #0
.h
    lda score,x
    cmp hiscore,x
    bcc .nh
    bne .new
    inx
    cpx #5
    bne .h
    beq .nh
.new
    ldx #4
.hc
    lda score,x
    sta hiscore,x
    dex
    bpl .hc
.nh
    lda #MUS_OVER
    jsr mus_play
    lda #MSG_GAMEOVER
    jmp msg

    SUBROUTINE
over_step
    dec g_timer
    bne .r
    jmp to_attract
.r
    lda g_timer
    cmp #200
    bcs .r2
    lda in_edge
    and #$10
    beq .r2
    jmp start_game
.r2
    rts

; ---------------------------------------------------------------------------
; Events from the physics
    SUBROUTINE
game_events
    ldx evq_r
    cpx evq_w
    bne .e
    rts
.e
    lda evqb,x
    sta g_tmp2              ; the ball
    lda evq,x
    pha
    inx
    txa
    and #7
    sta evq_r
    pla
    cmp #EV_DRAIN
    beq game_events         ; counted in play_step
    tax
    lda ev_lo-1,x
    sta pfp
    lda ev_hi-1,x
    sta pfp+1
    jsr .go
    jmp game_events
.go
    jmp (pfp)

; jump table indexed by event id - 1 (EV_* from gen/colliders.asm)
    SUBROUTINE
ev_lo
    .byte <ev_sling, <ev_bumper, <ev_drop0, <ev_drop1, <ev_drop2, <ev_stand0, <ev_stand1, <ev_stand2
    .byte <ev_lane0, <ev_lane1, <ev_lane2, <ev_lane3, <ev_ramp_in, <ev_ramp_back, <ev_ramp_top, <ev_ramp_out
    .byte <ev_spinner, <ev_orbit_l, <ev_orbit_r, <ev_lock, <ev_inlane_l, <ev_inlane_r, <ev_none
    SUBROUTINE
ev_hi
    .byte >ev_sling, >ev_bumper, >ev_drop0, >ev_drop1, >ev_drop2, >ev_stand0, >ev_stand1, >ev_stand2
    .byte >ev_lane0, >ev_lane1, >ev_lane2, >ev_lane3, >ev_ramp_in, >ev_ramp_back, >ev_ramp_top, >ev_ramp_out
    .byte >ev_spinner, >ev_orbit_l, >ev_orbit_r, >ev_lock, >ev_inlane_l, >ev_inlane_r, >ev_none

    if EV_SLING != 1 || EV_BUMPER != 2 || EV_DROP0 != 3 || EV_STAND0 != 6 || EV_LANE0 != 9 || EV_RAMP_IN != 13 || EV_SPINNER != 17 || EV_LOCK != 20 || EV_INLANE_R != 22 || EV_SKILL != 23
        echo "event numbering changed: fix ev_lo/ev_hi"
        err
    endif

    SUBROUTINE
ev_none
    rts

    SUBROUTINE
ev_sling
    lda #SFX_SLING
    jsr sfx
    lda #$10
    jmp add_pts2            ; 10 x 10 = 100... (pts+2 = tens/units)

    SUBROUTINE
ev_bumper
    lda #SFX_BUMPER
    jsr sfx
    ; which bumper: the nearest by the ball's position
    ldx g_tmp2
    lda b_yh,x
    cmp #>(156*16)
    bcc .up
    ldx #2
    bne .fl
.up
    lda b_xh,x
    cmp #>(160*16)
    ldx #0
    bcc .fl
    inx
.fl
    lda #8
    sta g_bumpf,x
    txa
    clc
    adc #LAMP_BUMPER0
    ldx #1
    jsr lamp_set
    lda #$10
    jmp add_pts1            ; 1,000

    SUBROUTINE
ev_drop0
    ldx #0
    beq ev_drop
    SUBROUTINE
ev_drop1
    ldx #1
    bne ev_drop
    SUBROUTINE
ev_drop2
    ldx #2
    SUBROUTINE
ev_drop
    lda dropbit,x
    ora drops_down
    sta drops_down
    txa
    clc
    adc #LAMP_DROPLIT0
    ldx #1
    jsr lamp_set
    jsr drops_lamps
    lda #SFX_DROP
    jsr sfx
    lda #$25
    jsr add_pts1            ; 2,500
    lda drops_down
    cmp #7
    bne .r
    lda g_lock_lit
    bne .r
    lda #1
    sta g_lock_lit
    lda #LAMP_LOCK_ARROW
    ldx #2
    jsr lamp_set
    lda #SFX_LIT
    jsr sfx
    lda #MSG_LOCKLIT
    jmp msg
.r
    rts

    SUBROUTINE
ev_stand0
    ldx #0
    beq ev_stand
    SUBROUTINE
ev_stand1
    ldx #1
    bne ev_stand
    SUBROUTINE
ev_stand2
    ldx #2
    SUBROUTINE
ev_stand
    lda dropbit,x
    ora g_stand
    sta g_stand
    txa
    clc
    adc #LAMP_STAND0
    ldx #1
    jsr lamp_set
    lda #SFX_TARGET
    jsr sfx
    lda #$50
    jsr add_pts1            ; 5,000
    lda g_stand
    cmp #7
    bne .r
    lda #0
    sta g_stand
    ldx #2
.c
    txa
    clc
    adc #LAMP_STAND0
    stx g_tmp
    ldx #0
    jsr lamp_set
    ldx g_tmp
    dex
    bpl .c
    lda #$05
    jsr add_pts0            ; 50,000
    jsr bonus_up
    lda #SFX_AWARD
    jsr sfx
    lda #MSG_STAR
    jmp msg
.r
    rts

    SUBROUTINE
ev_lane0
    ldx #0
    beq ev_lane
    SUBROUTINE
ev_lane1
    ldx #1
    bne ev_lane
    SUBROUTINE
ev_lane2
    ldx #2
    bne ev_lane
    SUBROUTINE
ev_lane3
    ldx #3
    SUBROUTINE
ev_lane
    lda g_skill
    beq .ns
    stx g_tmp
    tay
    dey                     ; the skill lane
    lda #0
    sta g_skill
    cpy g_tmp
    bne .ns
    lda #$05
    jsr add_pts0            ; 50,000
    lda #SFX_JACKPOT
    jsr sfx
    lda #MSG_SKILL
    jsr msg
    ldx g_tmp
.ns
    lda dropbit,x
    ora g_lanes
    cmp g_lanes
    beq .old
    sta g_lanes
    lda #SFX_LANE
    jsr sfx
    lda #$10
    jsr add_pts1            ; 1,000
    lda g_lanes
    cmp #15
    bne .r
    lda #0
    sta g_lanes
    lda g_bonusx
    cmp #5
    bcs .max
    inc g_bonusx
.max
    ldx g_bonusx
    lda #LAMP_BONUS0-2
    clc
    adc g_bonusx
    ldx #1
    jsr lamp_set
    lda #$02
    sta pts
    lda #$50
    sta pts+1
    lda #0
    sta pts+2
    jsr add_score           ; 25,000
    lda #SFX_AWARD
    jsr sfx
    lda #MSG_MEGA
    jmp msg
.old
    lda #$01
    jmp add_pts1            ; 100
.r
    rts

    SUBROUTINE
ev_ramp_in
    lda #SFX_RAMPIN
    jmp sfx
    SUBROUTINE
ev_ramp_back
    SUBROUTINE
ev_ramp_out
    rts

    SUBROUTINE
ev_ramp_top
    jsr bonus_up
    lda g_mball
    beq .plain
    ; JACKPOT
    lda g_jack
    sta pts
    lda #0
    sta pts+1
    sta pts+2
    ; g_jack is in 10,000s (BCD): pts+0 = 100k/10k
    jsr add_score
    sed
    clc
    lda g_jack
    adc #$02
    sta g_jack
    cld
    lda #SFX_JACKPOT
    jsr sfx
    lda #MSG_JACKPOT
    jmp msg
.plain
    lda g_ramps
    cmp #9
    bcs .m
    inc g_ramps
.m
    ; 10,000 + 5,000 per ramp before
    lda #$01
    sta pts
    lda #0
    sta pts+1
    sta pts+2
    jsr add_score
    ldx g_ramps
.rl
    dex
    beq .rd
    lda #$50
    jsr add_pts1
    jmp .rl
.rd
    lda #SFX_RAMP
    jsr sfx
    lda #MSG_RAMP
    jmp msg

    SUBROUTINE
ev_spinner
    ldx g_tmp2
    lda b_vyh,x
    bpl .p
    eor #$FF
.p
    asl
    asl
    asl
    adc #8
    sta g_spin
    lda #$01
    jsr add_pts1            ; 100
    lda #SFX_SPIN
    jmp sfx

    SUBROUTINE
ev_orbit_l
    lda #90
    sta g_orbit_t
    rts

    SUBROUTINE
ev_orbit_r
    lda g_orbit_t
    beq .r
    lda #0
    sta g_orbit_t
    jsr bonus_up
    lda #$02
    jsr add_pts0            ; 20,000
    lda #SFX_RAMP
    jsr sfx
    lda #MSG_ORBIT
    jmp msg
.r
    rts

    SUBROUTINE
ev_inlane_l
    lda #LAMP_INLANE_L
    bne ev_inlane
    SUBROUTINE
ev_inlane_r
    lda #LAMP_INLANE_R
    SUBROUTINE
ev_inlane
    ldx #1
    jsr lamp_set
    lda #$01
    jmp add_pts1

; the BLACK HOLE
    SUBROUTINE
ev_lock
    ldx g_tmp2
    lda b_act,x
    cmp #1
    bne .r
    lda #2
    sta b_act,x
    lda #70
    sta b_hold,x
    lda #SFX_HOLE
    jsr sfx
    lda g_lock_lit
    beq .unlit
    lda g_mball
    bne .unlit
    lda #0
    sta g_lock_lit
    jsr drops_reset
    lda #LAMP_LOCK_ARROW
    ldx #0
    jsr lamp_set
    inc g_locks
    lda g_locks
    cmp #2
    bcs mball_start
    lda #$05
    jsr add_pts0            ; 50,000
    lda #MSG_LOCKED
    jmp msg
.unlit
    lda #$50
    jsr add_pts1            ; 5,000
    lda #MSG_HOLE
    jmp msg
.r
    rts

    SUBROUTINE
mball_start
    lda #0
    sta g_locks
    lda #1
    sta g_mball
    lda #$05
    sta g_jack
    lda #LAMP_RAMP_ARROW
    ldx #3
    jsr lamp_set
    ; another ball out of the hole, one up the shooter lane
    ldx #MAXB-1
.f
    lda b_act,x
    beq .got
    dex
    bpl .f
    bmi .s
.got
    lda #2
    sta b_act,x
    lda #130
    sta b_hold,x
.s
    jsr serve_ball
    lda #60
    sta g_launch
    lda #<900
    sta g_save
    lda #>900
    sta g_save+1
    lda #$10
    jsr add_pts0            ; 100,000
    lda #SFX_JACKPOT
    jsr sfx
    lda #MSG_MBALL
    jsr msg
    lda #MUS_MBALL
    jmp mus_play

    SUBROUTINE
bonus_up
    sed
    clc
    lda g_bonus
    adc #$02
    bcc .b
    lda #$99
.b
    sta g_bonus
    cld
    rts

; ---------------------------------------------------------------------------
; Scoring (BCD)
    SUBROUTINE
add_pts0                    ; A = 100,000s/10,000s digits
    sta pts
    lda #0
    sta pts+1
    sta pts+2
    jmp add_score
    SUBROUTINE
add_pts1                    ; A = 1,000s/100s digits
    sta pts+1
    lda #0
    sta pts
    sta pts+2
    jmp add_score
    SUBROUTINE
add_pts2                    ; A = 10s/1s
    sta pts+2
    lda #0
    sta pts
    sta pts+1
    SUBROUTINE
add_score
    sed
    clc
    lda score+4
    adc pts+2
    sta score+4
    lda score+3
    adc pts+1
    sta score+3
    lda score+2
    adc pts
    sta score+2
    lda score+1
    adc #0
    sta score+1
    lda score
    adc #0
    sta score
    cld
    rts

; ---------------------------------------------------------------------------
; Lamps
    SUBROUTINE
lamp_set                    ; lamp A to state X
    tay
    txa
    sta lamp_state,y
    sta lamp_dirty
    inc lamp_dirty
    rts

    SUBROUTINE
lamps_clear
    ldx #63
    lda #0
.c
    sta lamp_state,x
    dex
    bpl .c
    rts

    SUBROUTINE
drops_reset
    lda #0
    sta drops_down
    ldx #2
.d
    txa
    clc
    adc #LAMP_DROPLIT0
    tay
    lda #0
    sta lamp_state,y
    dex
    bpl .d
    SUBROUTINE
drops_lamps                 ; drop targets standing = their lamps on
    ldx #2
.l
    lda dropbit,x
    and drops_down
    beq .up
    lda #0
    .byte $2C
.up
    lda #1
    pha
    txa
    clc
    adc #LAMP_DROP0
    tay
    pla
    sta lamp_state,y
    dex
    bpl .l
    rts

; the lane lamps follow g_lanes
    SUBROUTINE
lane_lamps
    ldx #3
.l
    lda dropbit,x
    and g_lanes
    beq .o
    lda #1
.o
    sta lamp_state+LAMP_LANE0,x
    dex
    bpl .l
    ldx g_skill
    beq .r
    lda #3
    sta lamp_state+LAMP_LANE0-1,x
.r
    rts

; ---------------------------------------------------------------------------
; Camera: follow the lowest ball on the table
    SUBROUTINE
camera
    lda g_shake
    beq .ns
    dec g_shake
    and #2
    beq .ns
    lda cam_lo
    eor #3
    sta cam_lo
.ns
    lda #0
    sta g_tmp
    sta g_tmp2
    ldx #MAXB-1
.f
    lda b_act,x
    beq .n
    lda b_yh,x
    cmp g_tmp2
    bcc .n
    bne .t
    lda b_yl,x
    cmp g_tmp
    bcc .n
.t
    lda b_yl,x
    sta g_tmp
    lda b_yh,x
    sta g_tmp2
.n
    dex
    bpl .f
    lda g_tmp
    ora g_tmp2
    bne .have
    lda #<(440*16)
    sta g_tmp
    lda #>(440*16)
    sta g_tmp2
.have
    ; y in units = /16; target = y - 128
    ldx #4
.d
    lsr g_tmp2
    ror g_tmp
    dex
    bne .d
    sec
    lda g_tmp
    sbc #128
    sta g_tmp
    lda g_tmp2
    sbc #0
    sta g_tmp2
    ; step = (target - cam) / 4, at most 12
    sec
    lda g_tmp
    sbc cam_lo
    sta g_tmp
    lda g_tmp2
    sbc cam_hi
    sta g_tmp2
    cmp #$80
    ror g_tmp2
    ror g_tmp
    lda g_tmp2
    cmp #$80
    ror g_tmp2
    ror g_tmp
    ; clamp to -12..12, at least 1 if moving
    lda g_tmp2
    bmi .neg
    bne .pmax
    lda g_tmp
    cmp #13
    bcc .padd
.pmax
    lda #12
.padd
    clc
    adc cam_lo
    sta cam_lo
    bcc .r
    inc cam_hi
.r
    rts
.neg
    cmp #$FF
    bne .nmax
    lda g_tmp
    cmp #$F4
    bcs .nadd
.nmax
    lda #$F4
.nadd
    clc
    adc cam_lo
    sta cam_lo
    bcs .r
    dec cam_hi
    rts

; ---------------------------------------------------------------------------
; Drawing
    SUBROUTINE
game_draw
    lda lamp_dirty
    bne .dl
    lda tick
    and #3
    bne .nl
.dl
    jsr pf_lamps
.nl
    lda #0
    sta lamp_dirty
    ; spinner (left orbit)
    lda #6
    sta dimg_ax
    lda #200
    sta dimg_yl
    lda #0
    sta dimg_yh
    lda g_spin_a
    lsr
    lsr
    lsr
    lsr
    lsr
    and #3
    clc
    adc #IMG_SPINNER
    ldy #0
    jsr pf_drawimg
    ; plunger
    lda #150
    sta dimg_ax
    lda plg_pull
    clc
    adc #<456
    sta dimg_yl
    lda #>456
    adc #0
    sta dimg_yh
    lda #IMG_PLUNGER
    ldy #0
    jsr pf_drawimg
    ; flippers
    ldx #0
    jsr flip_frame
    pha
    lda #FLIPL_X/32
    sta dimg_ax
    lda #<(FLIP_Y/16)
    sta dimg_yl
    lda #>(FLIP_Y/16)
    sta dimg_yh
    pla
    clc
    adc #IMG_FLIPL
    ldy #4
    jsr pf_drawimg
    ldx #1
    jsr flip_frame
    pha
    lda #FLIPR_X/32
    sta dimg_ax
    lda #<(FLIP_Y/16)
    sta dimg_yl
    lda #>(FLIP_Y/16)
    sta dimg_yh
    pla
    clc
    adc #IMG_FLIPR
    ldy #4
    jsr pf_drawimg
    ; balls
    ldx #MAXB-1
.b
    stx g_tmp
    lda b_act,x
    beq .nb
    cmp #2
    bne .roll
    ; held in the hole
    lda #LOCK_X/2
    sta dimg_ax
    lda #<LOCK_Y
    sta dimg_yl
    lda #>LOCK_Y
    sta dimg_yh
    jmp .draw
.roll
    ; x pixel = x16 >> 5, y = y16 >> 4
    lda b_xh,x
    sta g_tmp2
    lda b_xl,x
    ldy #5
.sx
    lsr g_tmp2
    ror
    dey
    bne .sx
    sta dimg_ax
    lda b_yh,x
    sta dimg_yh
    lda b_yl,x
    ldy #4
.sy
    lsr dimg_yh
    ror
    dey
    bne .sy
    sta dimg_yl
.draw
    lda #IMG_BALL
    ldy #0
    jsr pf_drawimg
.nb
    ldx g_tmp
    dex
    bpl .b
    jmp hud

; flipper X's frame: (angle - up) * 44 >> 16, 0..FLIP_FRAMES-1
    SUBROUTINE
flip_frame
    sec
    lda fl_angl,x
    sbc #<FLIP_UPANG
    sta M_A
    lda fl_angh,x
    sbc #>FLIP_UPANG
    sta M_A+1
    lda #44
    sta M_B
    lda #0
    sta M_B+1
    lda M_P+2
    cmp #FLIP_FRAMES
    bcc .ok
    lda #FLIP_FRAMES-1
.ok
    rts

; ---------------------------------------------------------------------------
; HUD: a message while its timer runs, else the score and the ball
    SUBROUTINE
msg
    sta g_msg
    lda #150
    sta g_msg_t
    rts

    SUBROUTINE
hud
    lda g_state
    bne *+5                  ; attract sets its own
    jmp .r
    lda g_msg_t
    beq .score
    ; blink the message's first half second
    cmp #120
    bcc .show
    and #8
    beq .score
.show
    lda #0
    sta hud_shown
    lda g_msg
    jmp hud_msg
.score
    ; only when the score (or what the HUD shows) changed
    lda hud_shown
    beq .redo
    ldx #4
.cmp
    lda score,x
    cmp hud_last,x
    bne .redo
    dex
    bpl .cmp
    rts
.redo
    ldx #4
.cp
    lda score,x
    sta hud_last,x
    dex
    bpl .cp
    lda #1
    sta hud_shown
    ; " 12,345,670  BALL 1 "
    ldx #19
    lda #0
.cl
    sta hudtext,x
    dex
    bpl .cl
    ; 10 digits -> positions with commas: d0 d1 , d2 d3 d4 , d5 d6 d7 , d8 d9
    ldx #0                  ; digit index
    ldy #0                  ; hud column
    lda #0
    sta g_tmp               ; leading zero blanking
.dg
    txa
    lsr
    sta g_tmp2
    stx pft5
    tax
    lda score,x
    ldx pft5
    pha
    txa
    and #1
    bne .lo
    pla
    lsr
    lsr
    lsr
    lsr
    jmp .put
.lo
    pla
    and #15
.put
    bne .nz
    cpx #9
    beq .nz
    lda g_tmp
    beq .blank
    lda #0
.nz
    pha
    lda #1
    sta g_tmp
    pla
    clc
    adc #1
    asl
    sta hudtext,y
.blank
    iny
    ; commas after digits 0, 3, 6 (d0,d1d2d3,d4d5d6,d7d8d9)
    cpx #0
    beq .comma
    cpx #3
    beq .comma
    cpx #6
    bne .nc
.comma
    lda g_tmp
    beq .nc1
    lda #44                 ; ','
    stx pft5
    tax
    lda ascii2font-32,x
    ldx pft5
    sta hudtext,y
.nc1
    iny
.nc
    inx
    cpx #10
    bne .dg
    ; BALL n
    ldx #3
.bl
    lda ball_txt,x
    sta hudtext+14,x
    dex
    bpl .bl
    lda g_ball
    clc
    adc #1
    asl
    sta hudtext+19
.r
    rts

ball_txt .byte 24, 22, 44, 44      ; B A L L (font index = 2 x position in FONT_ORDER)

; show message A in the HUD (high score / last score fill in digits)
    SUBROUTINE
hud_msg
    tax
    lda msg_lo,x
    sta pfp
    lda msg_hi,x
    sta pfp+1
    cpx #MSG_HIGH
    beq .hs
    cpx #MSG_LAST
    beq .ls
    jmp hud_puts
.hs
    jsr hud_puts
    ldx #0
    beq .digits
.ls
    jsr hud_puts
    ldx #5
.digits
    ; 10 digits of score set X (0 hiscore, 5 lastscore... via table) at col 10
    ldy #10
    lda #5
    sta g_tmp
.d
    lda hiscore,x
    lsr
    lsr
    lsr
    lsr
    clc
    adc #1
    asl
    sta hudtext,y
    iny
    lda hiscore,x
    and #15
    clc
    adc #1
    asl
    sta hudtext,y
    iny
    inx
    dec g_tmp
    bne .d
    rts

    SUBROUTINE
msg_lo
    .byte <m_title, <m_press, <m_high, <m_locklit, <m_locked, <m_mball, <m_jackpot, <m_ramp
    .byte <m_orbit, <m_mega, <m_star, <m_saved, <m_bonus, <m_over, <m_hole, <m_shoot, <m_last, <m_extra
    .byte <m_skill, <m_tilt, <m_warn
    SUBROUTINE
msg_hi
    .byte >m_title, >m_press, >m_high, >m_locklit, >m_locked, >m_mball, >m_jackpot, >m_ramp
    .byte >m_orbit, >m_mega, >m_star, >m_saved, >m_bonus, >m_over, >m_hole, >m_shoot, >m_last, >m_extra
    .byte >m_skill, >m_tilt, >m_warn

m_title     .byte "SUPER MEGA PINBALL  "
m_press     .byte "  PRESS FIRE TO PLAY"
m_high      .byte "HI SCORE            "
m_locklit   .byte "  * LOCK IS LIT *   "
m_locked    .byte "   BALL  LOCKED!    "
m_mball     .byte "  ** MULTIBALL **   "
m_jackpot   .byte "  *** JACKPOT ***   "
m_ramp      .byte "    RAMP  BONUS     "
m_orbit     .byte "   ORBIT  20,000    "
m_mega      .byte " MEGA! BONUS X UP   "
m_star      .byte "  STAR BONUS 50,000 "
m_saved     .byte "    BALL  SAVED     "
m_bonus     .byte "  END OF BALL BONUS "
m_over      .byte "     GAME  OVER     "
m_hole      .byte " BLACK HOLE  5,000  "
m_shoot     .byte " PULL DOWN TO SHOOT "
m_last      .byte "LAST SCORE          "
m_extra     .byte "                    "
m_skill     .byte " SKILL SHOT  50,000 "
m_tilt      .byte "      T I L T       "
m_warn      .byte "    -- DANGER --    "
