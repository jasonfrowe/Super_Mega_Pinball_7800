; ===========================================================================
; Super Mega Pinball 7800 - Physics, CORDIC Collision & Multi-Ball Engine
; Powered by the AstroCart FPGA MathUnit & CORDIC Co-Processor ($0420-$043F)
; ===========================================================================

; AstroCart MathUnit & CORDIC Register Addresses
M_X     = $0420
M_Y     = $0422
M_T     = $0424
M_XR    = $0420
M_YR    = $0422
M_ANG   = $0424
M_LEN   = $0426

M_A     = $0430
M_B     = $0432
M_N     = $0434
M_D     = $0438
M_SIGN  = $043A
M_P     = $0430
M_Q     = $0434
M_R     = $0438
M_RND   = $043E

; Physics Constants (8.8 fixed-point: $0100 = 1.0 pixel/frame)
GRAVITY_ACC     = $0007     ; Authentic pinball table slope gravity per 60Hz frame
MAX_BALL_VHI    = $04       ; Clamp velocity magnitude to +/- 4.5 px/frame ($0480)
MAX_BALL_VLO    = $80
MAX_BALLS       = 3         ; Up to 3 simultaneous steel pinballs in Multi-Ball!

; Game State RAM ($2300 - $237F)
pb_state        = $2300     ; 0 = Attract/Title, 1 = Playing, 2 = Game Over
pb_balls_left   = $2301     ; Balls remaining (3..1)
pb_mult         = $2302     ; Playfield bonus multiplier (1, 2, 3, 5)
pb_locks        = $2303     ; Multi-ball locks charged (0, 1, 2 -> 3 triggers Multi-Ball!)
pb_rollovers    = $2304     ; Bitmask (bits 0..2) of Top Rollover Lanes (I-G-N)
pb_drops        = $2305     ; Bitmask (bits 0..2) of Left Drop Targets (M-E-G)
pb_plunger      = $2306     ; Plunger pull-back tension (0..48)
pb_flipl        = $2307     ; Left Flipper state (0=Down, 1=Mid, 2=Up)
pb_flipr        = $2308     ; Right Flipper state (0=Down, 1=Mid, 2=Up)
pb_flipl_vel    = $2309     ; Left Flipper upward swing impulse frames
pb_flipr_vel    = $230A     ; Right Flipper upward swing impulse frames
pb_spinner      = $230B     ; Spinner whirl timer
pb_banner_id    = $230C     ; Active DMD/playfield banner text ID (TXT_*)
pb_banner_tmr   = $230D     ; Active banner timer (0 = none)
pb_frame        = $230E     ; Global 60Hz frame counter
pb_active_cnt   = $230F     ; Count of currently active balls on playfield (1..3)

; 3 Pinballs: X is 8.8 (ball_xf, ball_xi); Y is 16.8 (ball_yf, ball_yl, ball_yh in 0..319)
ball_act        = $2310     ; [3] 1 = active, 0 = inactive
ball_xf         = $2313     ; [3] X fractional byte
ball_xi         = $2316     ; [3] X integer pixel (16..142)
ball_yf         = $2319     ; [3] Y fractional byte
ball_yl         = $231C     ; [3] Y integer low byte
ball_yh         = $231F     ; [3] Y integer high byte (0..1)
ball_vxl        = $2322     ; [3] VX low byte (signed 8.8)
ball_vxh        = $2325     ; [3] VX high byte
ball_vyl        = $2328     ; [3] VY low byte (signed 8.8)
ball_vyh        = $232B     ; [3] VY high byte
ball_cd         = $232E     ; [3] Per-ball bumper/target cooldown (prevents double-trigger)

bmp_flash       = $2331     ; [3] Pop bumper flash timers (0..2)
pb_score        = $2334     ; [7] 7-digit ASCII score in 0..9 ($2334 = millions .. $233A = ones)
pb_saver        = $233B     ; Ball saver timer after launch / multi-ball start
pb_tmp0         = $233C
pb_tmp1         = $233D
pb_tmp2         = $233E
pb_tmp3         = $233F
pb_joy_l        = $2340     ; Input: Left flipper held (0/1)
pb_joy_r        = $2341     ; Input: Right flipper held (0/1)
pb_joy_d        = $2342     ; Input: Down (plunger pull) held (0/1)

; ---------------------------------------------------------------------------
; pinball_init: Initialize entire machine on boot
; ---------------------------------------------------------------------------
pinball_init
    lda #1
    sta M_SIGN              ; Enable signed arithmetic on AstroCart MathUnit
    jsr sound_init
    lda #0
    sta pb_state
    sta pb_frame
    sta pb_banner_tmr
    jsr clear_score
    jsr update_hud_digits
    rts

; ---------------------------------------------------------------------------
; match_init: Start a new 3-ball game
; ---------------------------------------------------------------------------
match_init
    lda #1
    sta M_SIGN
    sta pb_state
    sta pb_mult
    lda #3
    sta pb_balls_left
    lda #0
    sta pb_locks
    sta pb_rollovers
    sta pb_drops
    sta pb_plunger
    sta pb_spinner
    jsr clear_score
    jsr spawn_plunger_ball
    jsr update_hud_digits
    rts

clear_score
    ldx #6
    lda #0
.cs_loop
    sta pb_score,x
    dex
    bpl .cs_loop
    rts

; ---------------------------------------------------------------------------
; spawn_plunger_ball: Place Ball 0 on the Plunger at (138, 284)
; ---------------------------------------------------------------------------
spawn_plunger_ball
    lda #0
    sta ball_act+1
    sta ball_act+2
    sta pb_plunger
    sta bmp_flash
    sta bmp_flash+1
    sta bmp_flash+2

    lda #1
    sta ball_act
    lda #138
    sta ball_xi
    lda #<284
    sta ball_yl
    lda #>284
    sta ball_yh
    lda #0
    sta ball_xf
    sta ball_yf
    sta ball_vxl
    sta ball_vxh
    sta ball_vyl
    sta ball_vyh
    sta ball_cd

    lda #TXT_PRESS
    sta pb_banner_id
    lda #90
    sta pb_banner_tmr
    lda #180                ; 3-second ball saver once launched
    sta pb_saver
    rts

; ---------------------------------------------------------------------------
; add_score_k: Add A * 100 * pb_mult points to the 7-digit score
;   pb_score[0..6] = [M, 100K, 10K, 1K, 100, 10, 1]
; ---------------------------------------------------------------------------
add_score_100
    sta M_A
    lda #0
    sta M_A+1
    lda pb_mult
    sta M_B
    lda #0
    sta M_B+1
    lda M_P                 ; Total hundreds to add (up to 250)
    clc
    adc pb_score+4          ; Hundreds digit
    sta M_N
    lda M_P+1
    adc #0
    sta M_N+1
    lda #0
    sta M_N+2
    sta M_N+3
    lda #10
    sta M_D
    lda #0
    sta M_D+1
    lda M_R
    sta pb_score+4          ; Remainder = new hundreds digit

    ; Propagate carry M_Q up through 1K, 10K, 100K, 1M digits
    ldx #3
.score_prop
    lda M_Q
    beq .score_done
    clc
    adc pb_score,x
    sta M_N
    lda #0
    sta M_N+1
    lda M_R
    sta pb_score,x
    dex
    bpl .score_prop
.score_done
    rts

; ---------------------------------------------------------------------------
; update_hud_digits: Format live 20-char Zone 0 HUD string:
;   "0000000  B:3  1X L:0"
; ---------------------------------------------------------------------------
update_hud_digits
    ldx #6
.uh_score
    lda pb_score,x
    asl                     ; font index = 2 * digit
    sta hudtext,x
    dex
    bpl .uh_score

    lda pb_balls_left
    asl
    sta hudtext+11

    lda pb_mult
    asl
    sta hudtext+14

    lda pb_locks
    asl
    sta hudtext+19
    rts

; ---------------------------------------------------------------------------
; pinball_step: Main 60Hz Gameplay Update (Flippers, Plunger, Balls, Camera)
; ---------------------------------------------------------------------------
pinball_step
    inc pb_frame
    lda #1
    sta M_SIGN
    lda M_RND               ; Step hardware PRNG every frame

    jsr sound_update

    ; Decay timers
    lda pb_banner_tmr
    beq .no_bnr
    dec pb_banner_tmr
.no_bnr
    lda pb_saver
    beq .no_sav
    dec pb_saver
.no_sav
    ldx #2
.dec_bmp
    lda bmp_flash,x
    beq .next_bmp
    dec bmp_flash,x
.next_bmp
    dex
    bpl .dec_bmp

    ; Whirling spinner tick
    lda pb_spinner
    beq .no_spn
    dec pb_spinner
    and #3
    bne .no_spn
    lda #2                  ; +200 pts per spin tick
    jsr add_score_100
    lda #SFX_SPINNER
    jsr sound_play_ch0
.no_spn

    ; 1. Update Left Flipper (pb_joy_l)
    lda #0
    sta pb_flipl_vel
    lda pb_joy_l
    beq .flipl_rel
    lda pb_flipl
    cmp #2
    bcs .flipl_done
    bne .flipl_up1
    lda #SFX_FLIPPER
    jsr sound_play_ch0
.flipl_up1
    inc pb_flipl
    lda #2
    sta pb_flipl_vel        ; Active upward swing impulse!
    jmp .flipl_done
.flipl_rel
    lda pb_flipl
    beq .flipl_done
    dec pb_flipl
.flipl_done

    ; 2. Update Right Flipper (pb_joy_r)
    lda #0
    sta pb_flipr_vel
    lda pb_joy_r
    beq .flipr_rel
    lda pb_flipr
    cmp #2
    bcs .flipr_done
    bne .flipr_up1
    lda #SFX_FLIPPER
    jsr sound_play_ch0
.flipr_up1
    inc pb_flipr
    lda #2
    sta pb_flipr_vel        ; Active upward swing impulse!
    jmp .flipr_done
.flipr_rel
    lda pb_flipr
    beq .flipr_done
    dec pb_flipr
.flipr_done

    ; 3. Update Spring Plunger (pb_joy_d = Down held)
    lda pb_joy_d
    beq .plunger_released
    lda pb_plunger
    cmp #48
    bcs .plunger_hold_ball
    inc pb_plunger
.plunger_hold_ball
    ; If Ball 0 is in shooter lane at bottom, move it down with plunger spring
    lda ball_xi
    cmp #132
    bcc .plg_done_jmp
    lda ball_yh
    beq .plg_done_jmp
    lda pb_plunger
    lsr
    lsr
    lsr
    clc
    adc #<284
    sta ball_yl
    lda #0
    sta ball_vyl
    sta ball_vyh
.plg_done_jmp
    jmp .plunger_done

.plunger_released
    lda pb_plunger
    beq .plunger_done
    cmp #4
    bcc .plunger_zero
    ; Launch ball in shooter lane! VY = -($0220 + pb_plunger * 12)
    lda ball_xi
    cmp #132
    bcc .plunger_zero
    lda ball_yh
    beq .plunger_zero
    lda pb_plunger
    sta M_A
    lda #0
    sta M_A+1
    lda #12
    sta M_B
    lda #0
    sta M_B+1
    clc
    lda M_P
    adc #$20
    sta pb_tmp0
    lda M_P+1
    adc #$02
    sta pb_tmp1
    ; Add small random jitter from M_RND so launches are never identical
    lda M_RND
    and #$1F
    clc
    adc pb_tmp0
    sta pb_tmp0
    bcc .plg_neg
    inc pb_tmp1
.plg_neg
    sec
    lda #0
    sbc pb_tmp0
    sta ball_vyl
    lda #0
    sbc pb_tmp1
    sta ball_vyh
    lda #0
    sta ball_vxl
    sta ball_vxh
    lda #SFX_LAUNCH
    jsr sound_play_ch0
    lda #180
    sta pb_saver
.plunger_zero
    lda #0
    sta pb_plunger
.plunger_done

    ; 4. Update all 3 Pinballs
    lda #0
    sta pb_active_cnt
    ldx #0
.ball_loop
    stx pb_tmp3
    lda ball_act,x
    beq .next_ball
    inc pb_active_cnt
    jsr update_single_ball
    ldx pb_tmp3
.next_ball
    inx
    cpx #MAX_BALLS
    bcc .ball_loop

    ; Check if all balls drained
    lda pb_active_cnt
    bne .update_cam
    ; If Ball Saver active, relaunch immediately without losing a ball!
    lda pb_saver
    beq .lose_ball
    jsr spawn_plunger_ball
    jmp .update_cam

.lose_ball
    lda #SFX_DRAIN
    jsr sound_play_ch1
    dec pb_balls_left
    beq .trigger_game_over
    lda #1
    sta pb_mult             ; Reset bonus multiplier on new ball
    jsr spawn_plunger_ball
    jmp .update_cam

.trigger_game_over
    lda #2
    sta pb_state
    lda #TXT_GAMEOVER
    sta pb_banner_id
    lda #200
    sta pb_banner_tmr

.update_cam
    ; 5. Smooth Camera Vertical Tracking (cam_y in 0..111 follows lowest active ball)
    ;    Find highest Y (lowest on table) among active balls
    lda #0
    sta pb_tmp0             ; low byte of max ball Y
    sta pb_tmp1             ; high byte of max ball Y
    ldx #0
.cam_find
    lda ball_act,x
    beq .cam_next
    lda ball_yh,x
    cmp pb_tmp1
    bcc .cam_next
    bne .cam_take
    lda ball_yl,x
    cmp pb_tmp0
    bcc .cam_next
.cam_take
    lda ball_yl,x
    sta pb_tmp0
    lda ball_yh,x
    sta pb_tmp1
.cam_next
    inx
    cpx #MAX_BALLS
    bcc .cam_find

    ; Compute target cam_y = clamp(ball_y - 104, 0, 111)
    sec
    lda pb_tmp0
    sbc #104
    sta pb_tmp0
    lda pb_tmp1
    sbc #0
    bpl .cam_not_neg
    lda #0
    sta pb_tmp0
    beq .cam_set_t
.cam_not_neg
    bne .cam_max_t
    lda pb_tmp0
    cmp #112
    bcc .cam_set_t
.cam_max_t
    lda #111
    sta pb_tmp0
.cam_set_t
    sta cam_target

    ; Smoothly step cam_y toward cam_target (up to 4 lines/frame)
    lda cam_target
    sec
    sbc cam_y
    beq .cam_done
    bcc .cam_step_up
    cmp #5
    bcc .cam_snap
    lda cam_y
    clc
    adc #4
    sta cam_y
    jmp .cam_done
.cam_step_up
    cmp #$FC                ; >= -4?
    bcs .cam_snap
    lda cam_y
    sec
    sbc #4
    sta cam_y
    jmp .cam_done
.cam_snap
    lda cam_target
    sta cam_y
.cam_done
    jsr update_hud_digits
    rts

; ===========================================================================
; update_single_ball: Physics, Gravity, Walls, Flippers & Table Features (X=0..2)
; ===========================================================================
update_single_ball
    lda ball_cd,x
    beq .no_bcd
    dec ball_cd,x
.no_bcd

    ; 1. Apply table slope gravity (unless ball is resting on plunger in shooter lane)
    lda ball_xi,x
    cmp #132
    bcc .apply_grav
    lda ball_yh,x
    beq .apply_grav
    lda ball_yl,x
    cmp #<282
    bcc .apply_grav
    ; Resting on plunger at Y >= 282 in shooter lane
    lda ball_vyh,x
    bmi .apply_grav
    lda pb_plunger
    lsr
    lsr
    lsr
    clc
    adc #<284
    sta ball_yl,x
    lda #>284
    sta ball_yh,x
    lda #0
    sta ball_vyl,x
    sta ball_vyh,x
    rts

.apply_grav
    clc
    lda ball_vyl,x
    adc #<GRAVITY_ACC
    sta ball_vyl,x
    lda ball_vyh,x
    adc #>GRAVITY_ACC
    sta ball_vyh,x

    ; 2. Clamp velocity magnitude to [-$0480, +$0480]
    lda ball_vxh,x
    bmi .cvx_neg
    cmp #MAX_BALL_VHI
    bcc .cvy_chk
    bne .cvx_pos_cap
    lda ball_vxl,x
    cmp #MAX_BALL_VLO
    bcc .cvy_chk
.cvx_pos_cap
    lda #MAX_BALL_VLO
    sta ball_vxl,x
    lda #MAX_BALL_VHI
    sta ball_vxh,x
    jmp .cvy_chk
.cvx_neg
    cmp #$FB
    bcc .cvx_neg_cap
    bne .cvy_chk
    lda ball_vxl,x
    cmp #$80
    bcs .cvy_chk
.cvx_neg_cap
    lda #$80
    sta ball_vxl,x
    lda #$FB
    sta ball_vxh,x

.cvy_chk
    lda ball_vyh,x
    bmi .cvy_neg
    cmp #MAX_BALL_VHI
    bcc .integrate_pos
    bne .cvy_pos_cap
    lda ball_vyl,x
    cmp #MAX_BALL_VLO
    bcc .integrate_pos
.cvy_pos_cap
    lda #MAX_BALL_VLO
    sta ball_vyl,x
    lda #MAX_BALL_VHI
    sta ball_vyh,x
    jmp .integrate_pos
.cvy_neg
    cmp #$FB
    bcc .cvy_neg_cap
    bne .integrate_pos
    lda ball_vyl,x
    cmp #$80
    bcs .integrate_pos
.cvy_neg_cap
    lda #$80
    sta ball_vyl,x
    lda #$FB
    sta ball_vyh,x

.integrate_pos
    ; 3. Integrate X position (16-bit 8.8)
    clc
    lda ball_xf,x
    adc ball_vxl,x
    sta ball_xf,x
    lda ball_xi,x
    adc ball_vxh,x
    sta ball_xi,x

    ; 4. Integrate Y position (24-bit 16.8: yf, yl, yh)
    ldy #0
    lda ball_vyh,x
    bpl .vy_pos_ext
    ldy #$FF
.vy_pos_ext
    clc
    lda ball_yf,x
    adc ball_vyl,x
    sta ball_yf,x
    lda ball_yl,x
    adc ball_vyh,x
    sta ball_yl,x
    tya
    adc ball_yh,x
    sta ball_yh,x

    ; 5. Top Orbital Arch & Shooter Lane Curve (Y < 32, ball_yh == 0)
    lda ball_yh,x
    bne .not_top_arch
    lda ball_yl,x
    cmp #16
    bcs .check_arch_curve
    lda #16
    sta ball_yl,x
    ; Bounce downward off top arch roof and curve left if in right half
    lda #$80
    sta ball_vyl,x
    lda #$00
    sta ball_vyh,x
    lda ball_xi,x
    cmp #100
    bcc .not_top_arch
    ; Launched up shooter lane into top arch: kick left across top rollover lanes!
    lda M_RND
    and #$3F
    clc
    adc #$C0
    sta ball_vxl,x
    lda #$FD                ; VX ~ -$0200..-0240 left!
    sta ball_vxh,x
    jmp .not_top_arch

.check_arch_curve
    cmp #36
    bcs .not_top_arch
    lda ball_xi,x
    cmp #132
    bcc .not_top_arch
    ; In upper shooter curve (Y = 16..35, X >= 132): deflect smoothly left into playfield!
    lda #$E0
    sta ball_vxl,x
    lda #$FD                ; VX = -$0220
    sta ball_vxh,x

.not_top_arch
    ; 6. Left & Right Outer Walls + Plunger Divider Wall
    lda ball_xi,x
    cmp #17
    bcs .chk_right_walls
    lda #17
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .done_x_walls

.chk_right_walls
    ; Is ball in shooter lane (X >= 132)?
    cmp #132
    bcc .in_main_playfield
    cmp #140
    bcc .chk_shooter_div
    lda #140
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .done_x_walls
.chk_shooter_div
    ; In shooter lane: if Y >= 44, keep X >= 135 against divider wall
    lda ball_yh,x
    bne .clamp_shooter_l
    lda ball_yl,x
    cmp #44
    bcc .done_x_walls
.clamp_shooter_l
    lda ball_xi,x
    cmp #135
    bcs .done_x_walls
    lda #135
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .done_x_walls

.in_main_playfield
    ; Main playfield right wall is at X = 123 (one-way gate prevents re-entering shooter lane)
    cmp #123
    bcc .done_x_walls
    lda #123
    sta ball_xi,x
    jsr negate_damp_vx
.done_x_walls

    ; 7. Check Upper vs Lower Table Features by ball_yh (0 = Y < 256, 1 = Y >= 256)
    lda ball_yh,x
    beq .upper_table_checks
    jmp .lower_table_checks

; ---------------------------------------------------------------------------
; Upper & Mid Playfield Collisions (Y = 0..255, ball_yh == 0)
; ---------------------------------------------------------------------------
.upper_table_checks
    ; Skip playfield obstacle checks while ball is ascending in shooter lane (X >= 132)
    lda ball_xi,x
    cmp #132
    bcc .in_upper_playfield
    rts
.in_upper_playfield
    ; A. Top Rollover Lanes (I - G - N) at Y = 36..44
    lda ball_yl,x
    cmp #36
    bcc .chk_bumpers
    cmp #44
    bcs .chk_bumpers
    lda ball_cd,x
    bne .chk_bumpers
    lda ball_xi,x
    cmp #56
    bcc .roll_0
    cmp #84
    bcc .roll_1
    lda #4
    bne .roll_hit
.roll_0
    lda #1
    bne .roll_hit
.roll_1
    lda #2
.roll_hit
    ora pb_rollovers
    cmp pb_rollovers
    beq .chk_bumpers
    sta pb_rollovers
    lda #12
    sta ball_cd,x
    lda #5                  ; +500 pts per new rollover lane
    jsr add_score_100
    ldx pb_tmp3
    lda #SFX_TARGET
    jsr sound_play_ch1
    ldx pb_tmp3
    ; All 3 rollovers lit (I-G-N == 7)? Advance Bonus Multiplier (1X -> 2X -> 3X -> 5X)!
    lda pb_rollovers
    cmp #7
    bne .chk_bumpers
    lda #0
    sta pb_rollovers
    lda #50                 ; +5,000 Skill/Rollover Bonus!
    jsr add_score_100
    ldx pb_tmp3
    lda #TXT_SKILL
    sta pb_banner_id
    lda #65
    sta pb_banner_tmr
    lda pb_mult
    cmp #5
    bcs .chk_bumpers
    inc pb_mult
    lda pb_mult
    cmp #4
    bne .chk_bumpers
    inc pb_mult             ; 3X -> 5X

.chk_bumpers
    ; B. 3 Neon Pop Bumpers at (48, 72), (88, 72), (68, 102) using CORDIC!
    lda ball_yl,x
    cmp #56
    bcc .jmp_mid_feat
    cmp #120
    bcc .do_bmp_scan
.jmp_mid_feat
    jmp .chk_mid_features
.do_bmp_scan

    ldy #2
.bmp_loop
    sty pb_tmp2
    ; Compute (ball_x - bmp_x) * 256 -> M_X and (ball_y - bmp_y) * 256 -> M_Y
    lda #0
    sta M_X
    sta M_Y
    lda ball_xi,x
    sec
    sbc bmp_x_tbl,y
    sta M_X+1
    lda ball_yl,x
    sec
    sbc bmp_y_tbl,y
    sta M_Y+1

    lda M_LEN+1
    cmp #10                 ; Hit radius = 10 pixels
    bcs .bmp_next

    ; CORDIC Radial Rebound: rotate kick speed ($0260) by outward normal M_ANG!
    lda M_ANG
    sta pb_tmp0
    lda M_ANG+1
    sta pb_tmp1
    lda #$60
    sta M_X
    lda #$02
    sta M_X+1
    lda #0
    sta M_Y
    sta M_Y+1
    lda pb_tmp0
    sta M_T
    lda pb_tmp1
    sta M_T+1

    lda M_XR
    sta ball_vxl,x
    lda M_XR+1
    sta ball_vxh,x
    lda M_YR
    sta ball_vyl,x
    lda M_YR+1
    sta ball_vyh,x

    ; Push ball outside bumper radius along normal
    clc
    lda ball_xi,x
    adc M_XR+1
    adc M_XR+1
    sta ball_xi,x
    clc
    lda ball_yl,x
    adc M_YR+1
    adc M_YR+1
    sta ball_yl,x

    ldy pb_tmp2
    lda #10
    sta bmp_flash,y
    lda #8
    sta ball_cd,x
    lda #10                 ; +1,000 pts * multiplier!
    jsr add_score_100
    lda #SFX_BUMPER
    jsr sound_play_ch1
    ldx pb_tmp3
    rts

.bmp_next
    ldy pb_tmp2
    dey
    bmi .chk_mid_features
    jmp .bmp_loop

.chk_mid_features
    ; C. Left "HYPER RAMP" Chute (X = 16..34, Y = 140..172 moving upward)
    lda ball_yl,x
    cmp #140
    bcc .chk_core_lock
    cmp #172
    bcc .in_mid_y
    jmp .chk_drop_targets
.in_mid_y
    lda ball_xi,x
    cmp #34
    bcs .chk_warp_spinner
    ; Inside Left Hyper Ramp entrance! If moving upward (vyh < 0), launch up ramp to top loop!
    lda ball_vyh,x
    bpl .chk_core_lock
    lda #24
    sta ball_xi,x
    lda #24
    sta ball_yl,x
    lda #$20
    sta ball_vxl,x
    lda #$02                ; Exit top loop moving right (+2.1 px/frame)
    sta ball_vxh,x
    lda #$40
    sta ball_vyl,x
    lda #$00
    sta ball_vyh,x
    lda #100                ; +10,000 Ramp Bonus!
    jsr add_score_100
    lda #TXT_RAMP
    sta pb_banner_id
    lda #75
    sta pb_banner_tmr
    lda #SFX_RAMP
    jsr sound_play_ch1
    ldx pb_tmp3
    rts

.chk_warp_spinner
    ; D. Right "WARP CHUTE" & Whirling Spinner (X = 104..123, Y = 140..168)
    cmp #104
    bcc .chk_core_lock
    lda ball_cd,x
    bne .chk_core_lock
    lda #14
    sta ball_cd,x
    lda #32
    sta pb_spinner          ; Spin the Warp Spinner for 32 frames!
    lda #SFX_SPINNER
    jsr sound_play_ch0
    ldx pb_tmp3

.chk_core_lock
    ; E. Center "IGNITION CORE" Multi-Ball Lock Saucer at (72, 140) via CORDIC!
    lda ball_yl,x
    cmp #126
    bcc .upper_done
    cmp #156
    bcs .chk_drop_targets
    lda ball_cd,x
    bne .upper_done

    lda #0
    sta M_X
    sta M_Y
    lda ball_xi,x
    sec
    sbc #72
    sta M_X+1
    lda ball_yl,x
    sec
    sbc #140
    sta M_Y+1
    lda M_LEN+1
    cmp #10
    bcs .upper_done

    ; Hit the Center Ignition Core! Bounce radially via CORDIC and advance Multi-Ball Lock!
    lda M_ANG+1
    sta pb_tmp1
    lda #$40
    sta M_X
    lda #$02
    sta M_X+1
    lda #0
    sta M_Y
    sta M_Y+1
    sta M_T
    lda pb_tmp1
    sta M_T+1
    lda M_XR
    sta ball_vxl,x
    lda M_XR+1
    sta ball_vxh,x
    lda M_YR
    sta ball_vyl,x
    lda M_YR+1
    sta ball_vyh,x
    lda #18
    sta ball_cd,x
    jsr advance_multiball_lock
    ldx pb_tmp3
.upper_done
    rts

.chk_drop_targets
    ; F. 3 Emerald Drop Targets (M - E - G) on Left Bank (X < 28, Y = 176..223)
    lda ball_yl,x
    cmp #176
    bcc .upper_done
    cmp #224
    bcs .chk_slingshots_upper
    lda ball_xi,x
    cmp #28
    bcs .upper_done
    lda ball_cd,x
    bne .upper_done

    ; Determine which of the 3 targets (0, 1, 2) was hit
    lda ball_yl,x
    cmp #192
    bcc .drop_0
    cmp #208
    bcc .drop_1
    lda #4
    bne .drop_check
.drop_0
    lda #1
    bne .drop_check
.drop_1
    lda #2
.drop_check
    ora pb_drops
    cmp pb_drops
    beq .upper_done         ; Already knocked down
    sta pb_drops
    ; Bounce ball right off the drop target
    lda #$C0
    sta ball_vxl,x
    lda #$01
    sta ball_vxh,x
    lda #12
    sta ball_cd,x
    lda #10                 ; +1,000 pts
    jsr add_score_100
    lda #SFX_TARGET
    jsr sound_play_ch1
    ; All 3 Drop Targets knocked down? Reset bank & advance Multi-Ball Lock!
    lda pb_drops
    cmp #7
    bne .drop_done
    lda #0
    sta pb_drops
    jsr advance_multiball_lock
.drop_done
    ldx pb_tmp3
    rts

.chk_slingshots_upper
    ; G. Left & Right Neon Magenta Slingshot Kickers (Y = 232..255)
    lda ball_yl,x
    cmp #232
    bcc .upper_done
    lda ball_xi,x
    cmp #46
    bcc .hit_sling_l
    cmp #94
    bcs .hit_sling_r
    rts
.hit_sling_l
    lda #46
    sta ball_xi,x
    lda #$20
    sta ball_vxl,x
    lda #$02                ; Kick right & up!
    sta ball_vxh,x
    jmp .sling_common
.hit_sling_r
    lda #94
    sta ball_xi,x
    lda #$E0
    sta ball_vxl,x
    lda #$FD                ; Kick left & up!
    sta ball_vxh,x
.sling_common
    lda #$00
    sta ball_vyl,x
    lda #$FE
    sta ball_vyh,x
    lda #5                  ; +500 pts
    jsr add_score_100
    lda #SFX_SLING
    jsr sound_play_ch0
    ldx pb_tmp3
    rts

; ---------------------------------------------------------------------------
; Lower Playfield: Inlane Funnels, CORDIC Flippers & Drain (Y = 256..319, ball_yh == 1)
; ---------------------------------------------------------------------------
.lower_table_checks
    ; If in shooter lane (X >= 132), skip funnels and flippers
    lda ball_xi,x
    cmp #132
    bcc .lower_main
    rts

.lower_main
    ; 1. Inlane Funnel Rails (Y = 256..282, ball_yl = 0..26):
    ;    Left funnel slopes from X=17 at Y=256 to X=44 at Y=282
    ;    Right funnel slopes from X=123 at Y=256 to X=96 at Y=282
    lda ball_yl,x
    cmp #27
    bcs .chk_flippers
    clc
    adc #18                 ; Left funnel X wall = 18 + (Y - 256)
    cmp ball_xi,x
    bcc .chk_right_funnel
    sta ball_xi,x
    lda #$C0
    sta ball_vxl,x
    lda #$00                ; Slide smoothly down-right onto Left Flipper!
    sta ball_vxh,x
    jmp .chk_flippers

.chk_right_funnel
    lda #122
    sec
    sbc ball_yl,x           ; Right funnel X wall = 122 - (Y - 256)
    cmp ball_xi,x
    bcs .chk_flippers
    sta ball_xi,x
    lda #$40
    sta ball_vxl,x
    lda #$FF                ; Slide smoothly down-left onto Right Flipper!
    sta ball_vxh,x

.chk_flippers
    ; 2. Left & Right Flippers (Y = 278..298 -> ball_yl = 22..42)
    lda ball_yl,x
    cmp #20
    bcc .lower_ret_1
    cmp #44
    bcc .in_flipper_y
    jmp .chk_apron_or_drain
.in_flipper_y

    ; Check Left Flipper (X = 40..67)
    lda ball_xi,x
    cmp #40
    bcc .lower_ret_1
    cmp #68
    bcs .chk_right_flipper
    jmp .do_left_flipper
.lower_ret_1
    rts
.do_left_flipper

    ; Distance d from Left Flipper pivot (0..27)
    sec
    sbc #40
    sta pb_tmp0             ; pb_tmp0 = d (0..27)

    ; Compute flipper surface Y_low (in 256 + Y_low):
    ;   If Up (pb_flipl == 2):  Y_low = 28 - (d >> 2)
    ;   If Rest (pb_flipl < 2): Y_low = 28 + (d >> 2)
    lsr
    lsr
    sta pb_tmp1
    lda pb_flipl
    cmp #2
    bcc .flipl_surf_down
    lda #28
    sec
    sbc pb_tmp1
    jmp .flipl_test_y
.flipl_surf_down
    lda #28
    clc
    adc pb_tmp1
.flipl_test_y
    sta pb_tmp1             ; pb_tmp1 = surface Y_low
    lda ball_yl,x
    clc
    adc #4
    cmp pb_tmp1
    bcc .lower_ret_1

    ; Ball contacted Left Flipper! Place ball on surface
    lda pb_tmp1
    sec
    sbc #4
    sta ball_yl,x

    ; Is Left Flipper actively swinging upward (pb_flipl_vel > 0) or held up as a live catch?
    lda pb_flipl_vel
    bne .flipl_power_shot
    ; Passive bounce / cradle on Left Flipper:
    lda ball_vyh,x
    bmi .lower_ret_1
    ; Bounce upward with damping; if flipper is angled down, roll gently toward tip
    lda #$40
    sta ball_vyl,x
    lda #$FF
    sta ball_vyh,x
    lda pb_flipl
    cmp #2
    beq .flipl_cradle
    lda #$60
    sta ball_vxl,x
    lda #$00
    sta ball_vxh,x
    rts
.flipl_cradle
    lda #$E0
    sta ball_vxl,x
    lda #$FF
    sta ball_vxh,x
    rts

.flipl_power_shot
    ; CORDIC Power Shot from Left Flipper!
    ;   Angle = $B4 + d * 2 ($B4 up-left to $E8 cross-court up-right)
    lda pb_tmp0
    asl
    clc
    adc #$B4
    sta pb_tmp1
    jmp .flipper_cordic_launch

.chk_right_flipper
    ; Check Right Flipper (X = 73..100)
    cmp #73
    bcc .lower_ret_2        ; Between flippers (X = 68..72 = 5px drain gap)
    cmp #101
    bcs .lower_ret_2
    jmp .do_right_flipper
.lower_ret_2
    rts
.do_right_flipper

    ; Distance d from Right Flipper pivot at X=100 (0..27)
    lda #100
    sec
    sbc ball_xi,x
    sta pb_tmp0             ; pb_tmp0 = d (0..27)

    lsr
    lsr
    sta pb_tmp1
    lda pb_flipr
    cmp #2
    bcc .flipr_surf_down
    lda #28
    sec
    sbc pb_tmp1
    jmp .flipr_test_y
.flipr_surf_down
    lda #28
    clc
    adc pb_tmp1
.flipr_test_y
    sta pb_tmp1
    lda ball_yl,x
    clc
    adc #4
    cmp pb_tmp1
    bcc .lower_ret_2

    ; Ball contacted Right Flipper! Place ball on surface
    lda pb_tmp1
    sec
    sbc #4
    sta ball_yl,x

    lda pb_flipr_vel
    bne .flipr_power_shot
    lda ball_vyh,x
    bmi .lower_ret_2
    lda #$40
    sta ball_vyl,x
    lda #$FF
    sta ball_vyh,x
    lda pb_flipr
    cmp #2
    beq .flipr_cradle
    lda #$A0
    sta ball_vxl,x
    lda #$FF
    sta ball_vxh,x
    rts
.flipr_cradle
    lda #$20
    sta ball_vxl,x
    lda #$00
    sta ball_vxh,x
    rts

.flipr_power_shot
    ; CORDIC Power Shot from Right Flipper!
    ;   Angle = $CC - d * 2 ($CC up-right to $98 cross-court up-left into Hyper Ramp!)
    lda pb_tmp0
    asl
    sta pb_tmp1
    lda #$CC
    sec
    sbc pb_tmp1
    sta pb_tmp1

.flipper_cordic_launch
    ; Rotate launch velocity ($03A0 = 3.625 px/frame) by shot angle pb_tmp1 via CORDIC!
    lda #$A0
    sta M_X
    lda #$03
    sta M_X+1
    lda #0
    sta M_Y
    sta M_Y+1
    sta M_T
    lda pb_tmp1
    sta M_T+1
    lda M_XR
    sta ball_vxl,x
    lda M_XR+1
    sta ball_vxh,x
    lda M_YR
    sta ball_vyl,x
    lda M_YR+1
    sta ball_vyh,x
    lda #1                  ; +100 pts per flipper shot
    jsr add_score_100
    ldx pb_tmp3
.lower_done
    rts

.chk_apron_or_drain
    ; 3. Drain Apron Guides (Y = 300..314 -> ball_yl = 44..58):
    ;    Outside the center drain gap (X < 56 or X > 84), apron bounces ball back to flippers;
    ;    inside center drain gap, ball drains at Y >= 314 (ball_yl >= 58)!
    lda ball_xi,x
    cmp #56
    bcc .apron_save_l
    cmp #85
    bcc .check_drain_bottom
    lda #84
    sta ball_xi,x
    lda #$40
    sta ball_vyl,x
    lda #$FE
    sta ball_vyh,x
    rts
.apron_save_l
    lda #56
    sta ball_xi,x
    lda #$40
    sta ball_vyl,x
    lda #$FE
    sta ball_vyh,x
    rts

.check_drain_bottom
    lda ball_yl,x
    cmp #58
    bcc .lower_done
    ; Ball drained through center gap!
    lda #0
    sta ball_act,x
    rts

; ---------------------------------------------------------------------------
; negate_damp_vx: Reverse horizontal velocity with 0.75x restitution
; ---------------------------------------------------------------------------
negate_damp_vx
    sec
    lda #0
    sbc ball_vxl,x
    sta ball_vxl,x
    lda #0
    sbc ball_vxh,x
    sta ball_vxh,x
    ; Multiply by 3/4 (subtract 1/4)
    cmp #$80
    ror
    sta pb_tmp1
    lda ball_vxl,x
    ror
    sta pb_tmp0
    lda pb_tmp1
    cmp #$80
    ror
    sta pb_tmp1
    lda pb_tmp0
    ror
    sta pb_tmp0
    sec
    lda ball_vxl,x
    sbc pb_tmp0
    sta ball_vxl,x
    lda ball_vxh,x
    sbc pb_tmp1
    sta ball_vxh,x
    rts

; ---------------------------------------------------------------------------
; advance_multiball_lock: Charge Ignition Core Lock -> Trigger 3-Ball Multi-Ball!
; ---------------------------------------------------------------------------
advance_multiball_lock
    inc pb_locks
    lda pb_locks
    cmp #1
    bne .chk_lock2
    lda #25                 ; +2,500 pts
    jsr add_score_100
    lda #TXT_LOCK1
    sta pb_banner_id
    lda #75
    sta pb_banner_tmr
    lda #SFX_LOCK
    jmp sound_play_ch1

.chk_lock2
    cmp #2
    bne .trigger_multiball
    lda #50                 ; +5,000 pts
    jsr add_score_100
    lda #TXT_LOCK2
    sta pb_banner_id
    lda #75
    sta pb_banner_tmr
    lda #SFX_LOCK
    jmp sound_play_ch1

.trigger_multiball
    ; 3-BALL MULTI-BALL MANIA!
    lda #0
    sta pb_locks
    lda #250                ; +25,000 Super Jackpot!
    jsr add_score_100
    lda #TXT_MULTIBALL
    sta pb_banner_id
    lda #120
    sta pb_banner_tmr
    lda #240                ; 4-second Multi-Ball ball saver
    sta pb_saver
    lda #SFX_MULTIBALL
    jsr sound_play_ch1

    ; Spawn Ball 1 and Ball 2 if not already active!
    ldy #1
.mb_spawn_loop
    lda ball_act,y
    bne .mb_next
    lda #1
    sta ball_act,y
    lda mb_spawn_x,y
    sta ball_xi,y
    lda mb_spawn_y,y
    sta ball_yl,y
    lda #0
    sta ball_yh,y
    sta ball_xf,y
    sta ball_yf,y
    sta ball_vxl,y
    sta ball_vyl,y
    lda mb_spawn_vxh,y
    sta ball_vxh,y
    lda mb_spawn_vyh,y
    sta ball_vyh,y
    lda #15
    sta ball_cd,y
.mb_next
    iny
    cpy #MAX_BALLS
    bcc .mb_spawn_loop
    rts

mb_spawn_x      .byte 72, 66, 78
mb_spawn_y      .byte 140, 144, 52
mb_spawn_vxh    .byte 0, $FE, $02
mb_spawn_vyh    .byte 0, $FE, $01

bmp_x_tbl       .byte 48, 88, 68
bmp_y_tbl       .byte 72, 72, 102

; ===========================================================================
; pinball_draw: Plot all scrolling playfield sprites & DMD banners
; ===========================================================================
pinball_draw
    ; 1. Draw 3 Neon Pop Bumpers at (48, 72), (88, 72), (68, 102)
    ldx #2
.draw_bmp_loop
    stx pb_tmp3
    lda #IMG_BUMPER
    sta pimg
    lda #0
    ldy bmp_flash,x
    beq .bmp_no_fl
    lda #1
.bmp_no_fl
    sta pframe
    lda #2
    sta ppal
    lda bmp_x_tbl,x
    sec
    sbc #4
    sta px
    lda bmp_y_tbl,x
    sec
    sbc #5
    ldy #0
    jsr draw_world_sprite
    ldx pb_tmp3
    dex
    bpl .draw_bmp_loop

    ; 2. Draw 3 Top Rollover Lane Indicator Gems (Y = 38, X = 46, 70, 94)
    ldx #2
.draw_roll_loop
    stx pb_tmp3
    lda #IMG_GEM
    sta pimg
    lda pb_rollovers
    and bit_mask_tbl,x
    beq .roll_unlit
    lda #1
    sta pframe
    lda #1                  ; Lit Gold
    bne .roll_pal_set
.roll_unlit
    lda #0
    sta pframe
    lda #3                  ; Cyan
.roll_pal_set
    sta ppal
    lda roll_x_tbl,x
    sta px
    lda #38
    ldy #0
    jsr draw_world_sprite
    ldx pb_tmp3
    dex
    bpl .draw_roll_loop

    ; 3. Draw 3 Left Drop Targets (X = 24, Y = 182, 198, 214)
    ldx #2
.draw_drop_loop
    stx pb_tmp3
    lda pb_drops
    and bit_mask_tbl,x
    bne .skip_drop_draw     ; Knocked down!
    lda #IMG_GEM
    sta pimg
    lda #0
    sta pframe
    lda #5                  ; Emerald Green
    sta ppal
    lda #24
    sta px
    lda drop_y_tbl,x
    ldy #0
    jsr draw_world_sprite
.skip_drop_draw
    ldx pb_tmp3
    dex
    bpl .draw_drop_loop

    ; 4. Draw Center Ignition Core Lock Target at (70, 138) & Right Warp Spinner at (110, 150)
    lda #IMG_GEM
    sta pimg
    lda pb_locks
    and #1
    sta pframe
    lda #5
    sta ppal
    lda #70
    sta px
    lda #138
    ldy #0
    jsr draw_world_sprite

    lda #IMG_SPINNER
    sta pimg
    lda pb_spinner
    lsr
    and #1
    sta pframe
    lda #4
    sta ppal
    lda #110
    sta px
    lda #150
    ldy #0
    jsr draw_world_sprite

    ; 5. Draw Left Flipper (X = 44, Y = 282) & Right Flipper (X = 76, Y = 282)
    lda #IMG_FLIPL
    sta pimg
    lda pb_flipl
    sta pframe
    lda #1
    sta ppal
    lda #44
    sta px
    lda #<282
    ldy #>282
    jsr draw_world_sprite

    lda #IMG_FLIPR
    sta pimg
    lda pb_flipr
    sta pframe
    lda #1
    sta ppal
    lda #76
    sta px
    lda #<282
    ldy #>282
    jsr draw_world_sprite

    ; 6. Draw Spring Plunger at (136, 288)
    lda #IMG_PLUNGER
    sta pimg
    lda pb_plunger
    lsr
    lsr
    lsr
    lsr
    cmp #3
    bcc .plg_fr_ok
    lda #2
.plg_fr_ok
    sta pframe
    lda #1
    sta ppal
    lda #136
    sta px
    lda #<288
    ldy #>288
    jsr draw_world_sprite

    ; 7. Draw all active Chrome Steel Pinballs (0..2)
    ldx #0
.draw_ball_loop
    stx pb_tmp3
    lda ball_act,x
    beq .draw_ball_next
    lda #IMG_BALL
    sta pimg
    lda #0
    sta pframe
    lda #7                  ; P7 Chrome Steel
    sta ppal
    lda ball_xi,x
    sec
    sbc #2
    sta px
    lda ball_yl,x
    sec
    sbc #3
    sta pb_tmp0
    lda ball_yh,x
    sbc #0
    tay
    lda pb_tmp0
    jsr draw_world_sprite
.draw_ball_next
    ldx pb_tmp3
    inx
    cpx #MAX_BALLS
    bcc .draw_ball_loop

    ; 8. Draw Playfield Callout Banner / Title Overlay via pf_text
    lda pb_state
    bne .chk_game_banner
    ; Attract / Title Mode Banners
    lda #4
    sta tzone
    lda #3
    sta tpal
    lda #TXT_TITLE1
    jsr pf_text
    lda #6
    sta tzone
    lda #6
    sta tpal
    lda #TXT_TITLE2
    jsr pf_text
    lda pb_frame
    and #16
    bne .done_banners
    lda #9
    sta tzone
    lda #1
    sta tpal
    lda #TXT_PRESS
    jmp pf_text

.chk_game_banner
    lda pb_banner_tmr
    beq .done_banners
    lda #6
    sta tzone
    lda #1
    sta tpal
    lda pb_banner_id
    jmp pf_text
.done_banners
    rts

; ---------------------------------------------------------------------------
; draw_world_sprite: Convert world Y (A = low, Y = high) -> py = world_y - cam_y + 32
;                    and call pf_drawimg if visible on screen!
; ---------------------------------------------------------------------------
draw_world_sprite
    sec
    sbc cam_y
    sta pb_tmp0
    tya
    sbc #0
    bmi .dws_above          ; Slightly above cam_y? Check if within -15..0
    bne .dws_out            ; >= 256 lines below cam_y -> off screen
    lda pb_tmp0
    cmp #209
    bcs .dws_out
    adc #32
    sta py
    jmp pf_drawimg
.dws_above
    cmp #$FF
    bne .dws_out
    lda pb_tmp0
    cmp #241                ; -15..0 -> +32 gives 17..32
    bcc .dws_out
    clc
    adc #32
    sta py
    jmp pf_drawimg
.dws_out
    rts

bit_mask_tbl    .byte 1, 2, 4
roll_x_tbl      .byte 46, 70, 94
drop_y_tbl      .byte 182, 198, 214
