; ===========================================================================
; Super Mega Pinball 7800 - Physics, CORDIC Collision & Multi-Ball Engine
; Inspired by NES Pinball & Pinball Dreams (Two-Tier Flippers & Side Channels)
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
GRAVITY_ACC     = $0008     ; Crisp pinball table slope gravity per 60Hz frame
MAX_BALL_VHI    = $04       ; Clamp velocity magnitude to +/- 4.5 px/frame ($0480)
MAX_BALL_VLO    = $80
MAX_BALLS       = 3         ; Up to 3 simultaneous steel pinballs in Multi-Ball!
NUM_BUMPERS     = 4         ; 1 Upper Bumper (68,68) + 3 Lower Bumpers (48,206), (92,206), (70,226)

; Game State RAM ($2300 - $237F)
pb_state        = $2300     ; 0 = Attract/Title, 1 = Playing, 2 = Game Over
pb_balls_left   = $2301     ; Balls remaining (3..1)
pb_mult         = $2302     ; Playfield bonus multiplier (1, 2, 3, 5)
pb_locks        = $2303     ; Multi-ball locks charged (0, 1 -> 2 triggers Multi-Ball!)
pb_rollovers    = $2304     ; Bitmask (bits 0..2) of Top Rollover Lanes (I-G-N)
pb_drops        = $2305     ; Bitmask (bits 0..3) of 4 Center Card Targets ($0F = all 4 hit -> lights Lock!)
pb_plunger      = $2306     ; Plunger pull-back tension (0..48)
pb_flipl        = $2307     ; Left Flippers state (0=Down, 1=Mid, 2=Up)
pb_flipr        = $2308     ; Right Flippers state (0=Down, 1=Mid, 2=Up)
pb_flipl_vel    = $2309     ; Left Flippers upward swing impulse frames
pb_flipr_vel    = $230A     ; Right Flippers upward swing impulse frames
pb_spinner      = $230B     ; Spinner whirl timer
pb_banner_id    = $230C     ; Active playfield banner text ID (TXT_*)
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
ball_cd         = $232E     ; [3] Per-ball bumper/target cooldown

bmp_flash       = $2331     ; [4] Pop bumper flash timers (0..3) ($2331-$2334)
pb_score        = $2335     ; [7] 7-digit score in 0..9 ($2335 = millions .. $233B = ones)
pb_lock_lit     = $233C     ; 1 = Upper-Right Lock Chute is LIT (after clearing all 4 Center Cards!)
pb_tmp0         = $233D
pb_tmp1         = $233E
pb_tmp2         = $233F
pb_joy_l        = $2340     ; Input: Left flipper held (0/1)
pb_joy_r        = $2341     ; Input: Right flipper held (0/1)
pb_joy_d        = $2342     ; Input: Down (plunger pull) held (0/1)
pb_tmp3         = $2343

; ---------------------------------------------------------------------------
; pinball_init: Initialize entire machine on boot
; ---------------------------------------------------------------------------
pinball_init
    lda #1
    sta M_SIGN
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
    sta pb_lock_lit
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
    sta bmp_flash+3

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
    rts

; ---------------------------------------------------------------------------
; add_score_100: Add A * 100 * pb_mult points to the 7-digit score
; ---------------------------------------------------------------------------
add_score_100
    sta M_A
    lda #0
    sta M_A+1
    lda pb_mult
    sta M_B
    lda #0
    sta M_B+1
    lda M_P
    clc
    adc pb_score+4
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
    sta pb_score+4

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
    asl
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
    lda M_RND

    jsr sound_update

    ; Decay timers
    lda pb_banner_tmr
    beq .no_bnr
    dec pb_banner_tmr
.no_bnr
    ldx #3
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
    lda #2
    jsr add_score_100
    lda #SFX_SPINNER
    jsr sound_play_ch0
.no_spn

    ; 1. Update Left Flippers (Upper & Lower)
    lda lb_flipl_decay
    beq .chk_flipl_in
    dec pb_flipl_vel
.chk_flipl_in
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
    lda #4                  ; 4-frame active upward swing window!
    sta pb_flipl_vel
    jmp .flipl_done
.flipl_rel
    lda #0
    sta pb_flipl_vel
    lda pb_flipl
    beq .flipl_done
    dec pb_flipl
.flipl_done

    ; 2. Update Right Flippers (Upper & Lower)
    lda pb_flipr_vel
    beq .chk_flipr_in
    dec pb_flipr_vel
.chk_flipr_in
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
    lda #4                  ; 4-frame active upward swing window!
    sta pb_flipr_vel
    jmp .flipr_done
.flipr_rel
    lda #0
    sta pb_flipr_vel
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
    ; Launch ball in shooter lane! VY = -($0240 + pb_plunger * 12)
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
    adc #$40
    sta pb_tmp0
    lda M_P+1
    adc #$02
    sta pb_tmp1
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

    ; Check if all balls drained!
    lda pb_active_cnt
    bne .update_cam

    ; All active balls drained -> lose a ball!
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
    lda #0
    sta pb_tmp0
    sta pb_tmp1
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
    cmp #$FC
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

lb_flipl_decay = pb_flipl_vel

; ===========================================================================
; update_single_ball: Physics, Side Channels, Upper/Lower Flippers & Drain
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

    ; 5. Top Orbital Arch & Shooter Lane Exit Curve (Y < 34, ball_yh == 0)
    lda ball_yh,x
    bne .not_top_arch
    lda ball_yl,x
    cmp #16
    bcs .check_arch_curve
    lda #16
    sta ball_yl,x
    lda #$80
    sta ball_vyl,x
    lda #$00
    sta ball_vyh,x
    lda ball_xi,x
    cmp #100
    bcc .chk_left_orbit_top
    ; Launched up shooter lane into top arch: curve left across rollover lanes!
    lda M_RND
    and #$7F
    clc
    adc #$A0
    sta ball_vxl,x
    lda #$FD                ; VX ~ -$01E0..-$0260 left
    sta ball_vxh,x
    jmp .not_top_arch
.chk_left_orbit_top
    cmp #32
    bcs .not_top_arch
    ; Shot up the Left Side Orbit Channel into the top arch! Curve right (+10,000 Orbit Bonus!)
    lda #$20
    sta ball_vxl,x
    lda #$02
    sta ball_vxh,x
    lda #100
    jsr add_score_100
    lda #TXT_RAMP
    sta pb_banner_id
    lda #70
    sta pb_banner_tmr
    lda #SFX_RAMP
    jsr sound_play_ch1
    ldx pb_tmp3
    jmp .not_top_arch

.check_arch_curve
    cmp #34
    bcs .not_top_arch
    lda ball_xi,x
    cmp #132
    bcc .not_top_arch
    lda #$E0
    sta ball_vxl,x
    lda #$FD
    sta ball_vxh,x

.not_top_arch
    ; 6. Outer Left & Right Walls + Plunger Divider Wall
    lda ball_xi,x
    cmp #17
    bcs .chk_right_walls
    lda #17
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .done_x_walls

.chk_right_walls
    cmp #132
    bcc .in_main_playfield
    cmp #140
    bcc .chk_shooter_div
    lda #140
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .done_x_walls
.chk_shooter_div
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
    cmp #123
    bcc .done_x_walls
    lda #123
    sta ball_xi,x
    jsr negate_damp_vx
.done_x_walls

    ; 7. Dispatch Upper/Mid Playfield (Y < 256) vs Lower Playfield (Y >= 256)
    lda ball_yh,x
    beq .upper_table_checks
    jmp .lower_table_checks

; ---------------------------------------------------------------------------
; Upper & Mid Playfield: Channels, Islands, Upper Flippers, Cards & Bumpers
; ---------------------------------------------------------------------------
.upper_table_checks
    ; Skip playfield checks while ball is ascending in shooter lane (X >= 132)
    lda ball_xi,x
    cmp #132
    bcc .in_upper_playfield
    rts
.in_upper_playfield

    ; A. Top Rollover Lanes (I - G - N) at Y = 34..46, X = 34..106
    lda ball_yl,x
    cmp #34
    bcc .chk_side_channels
    cmp #46
    bcs .chk_side_channels
    lda ball_xi,x
    cmp #34
    bcc .chk_side_channels
    lda ball_cd,x
    bne .chk_side_channels
    lda ball_xi,x
    cmp #56
    bcc .roll_0
    cmp #80
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
    beq .chk_side_channels
    sta pb_rollovers
    lda #12
    sta ball_cd,x
    lda #5
    jsr add_score_100
    ldx pb_tmp3
    lda #SFX_TARGET
    jsr sound_play_ch1
    ldx pb_tmp3
    lda pb_rollovers
    cmp #7
    bne .chk_side_channels
    lda #0
    sta pb_rollovers
    lda #50
    jsr add_score_100
    ldx pb_tmp3
    lda #TXT_SKILL
    sta pb_banner_id
    lda #65
    sta pb_banner_tmr
    lda pb_mult
    cmp #5
    bcs .chk_side_channels
    inc pb_mult
    lda pb_mult
    cmp #4
    bne .chk_side_channels
    inc pb_mult

.jmp_chk_upper_flippers
    jmp .chk_upper_flippers
.jmp_chk_center_cards
    jmp .chk_center_cards

.chk_side_channels
    ; B. Walled Side Channels & Upper-Tier Islands (Y = 48..158):
    ;    1. Left Side Bypass / Orbit Channel (col 2, X = 17..23) separated from
    ;       main arena by Left Channel Wall / Island (cols 3..4, X = 24..39)!
    lda ball_yl,x
    cmp #48
    bcc .jmp_chk_upper_flippers
    cmp #158
    bcs .jmp_chk_center_cards

    lda ball_xi,x
    cmp #24
    bcs .chk_left_island_inner
    ; Ball is INSIDE the Left Side Bypass Channel (X = 17..23)!
    ; Keep it guided inside the channel (X <= 22) as it shoots up or drops down!
    cmp #22
    bcc .jmp_chk_upper_flippers
    lda #22
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .chk_upper_flippers

.chk_left_island_inner
    ; At Y = 96..140, the Left Island occupies X = 24..39, funneling main-arena balls to X >= 40!
    lda ball_yl,x
    cmp #96
    bcc .chk_upper_right_chute
    cmp #140
    bcs .jmp_chk_upper_flippers
    lda ball_xi,x
    cmp #40
    bcs .chk_right_island_inner
    lda #40
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .chk_upper_flippers

.chk_right_island_inner
    ; At Y = 96..140, the Right Island occupies X = 104..118, funneling balls to X <= 103 (or right channel >= 119)
    cmp #104
    bcc .chk_upper_flippers
    cmp #118
    bcs .chk_upper_flippers
    lda #103
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .chk_upper_flippers

.chk_upper_right_chute
    ; Left orbit channel inner wall (col 3, X = 24..31) at Y = 48..95
    lda ball_xi,x
    cmp #32
    bcs .chk_lock_chute_x
    lda #32
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .chk_upper_flippers
.chk_lock_chute_x
    ; 2. Upper-Right Green Multi-Ball Lock Chute (Y = 48..95, X = 102..120, walled on left at X = 96..101)
    lda ball_xi,x
    cmp #96
    bcc .chk_upper_flippers
    cmp #102
    bcs .in_lock_chute
    ; Bounce off left wall of Lock Chute (X = 95)
    lda #95
    sta ball_xi,x
    jsr negate_damp_vx
    jmp .chk_upper_flippers

.in_lock_chute
    ; Inside the Upper-Right Green Lock Chute!
    lda ball_cd,x
    bne .chk_upper_flippers
    lda #24
    sta ball_cd,x
    ; Eject ball downward out of the chute
    lda #$20
    sta ball_vyl,x
    lda #$01
    sta ball_vyh,x
    lda #$C0
    sta ball_vxl,x
    lda #$FF
    sta ball_vxh,x
    ; Is Lock Lit (all 4 Center Cards knocked down)?
    lda pb_lock_lit
    beq .chute_bonus_only
    jsr advance_multiball_lock
    ldx pb_tmp3
    rts
.chute_bonus_only
    lda #15                 ; +1,500 Chute Bonus when Lock not yet lit
    jsr add_score_100
    lda #SFX_TARGET
    jsr sound_play_ch1
    ldx pb_tmp3

.jmp_chk_center_cards2
    jmp .chk_center_cards

.chk_upper_flippers
    ; C. Upper Pair of Flippers at Y = 126..142 (Left: X = 40..55, Right: X = 88..103)
    lda ball_yl,x
    cmp #126
    bcc .jmp_chk_center_cards2
    cmp #142
    bcs .jmp_chk_center_cards2

    ; Upper flippers only catch balls falling onto them (shots from below pass up through)
    lda ball_vyh,x
    bmi .jmp_chk_center_cards2
    lda ball_xi,x
    cmp #40
    bcc .jmp_chk_center_cards2
    cmp #56
    bcc .hit_upper_flipl
    cmp #88
    bcc .jmp_chk_center_cards2
    cmp #104
    bcs .jmp_chk_center_cards2

    ; Upper Right Flipper (X = 88..103)
    lda #103
    sec
    sbc ball_xi,x
    sta pb_tmp0             ; d = 0..15
    lda #128
    sta ball_yl,x
    lda pb_flipr_vel
    bne .up_flipr_shot
    lda ball_vyh,x
    bmi .jmp_chk_center_cards2
    ; Unpressed upper right flipper: slide down-left into mid arena!
    lda #$60
    sta ball_vyl,x
    lda #$00
    sta ball_vyh,x
    lda #$60
    sta ball_vxl,x
    lda #$FF
    sta ball_vxh,x
    rts
.up_flipr_shot
    lda pb_tmp0
    asl
    sta pb_tmp1
    lda #$CE
    sec
    sbc pb_tmp1
    sta pb_tmp1
    jmp .flipper_cordic_launch

.hit_upper_flipl
    ; Upper Left Flipper (X = 40..55)
    sec
    sbc #40
    sta pb_tmp0             ; d = 0..15
    lda #128
    sta ball_yl,x
    lda pb_flipl_vel
    bne .up_flipl_shot
    lda ball_vyh,x
    bmi .jmp_chk_center_cards2
    ; Unpressed upper left flipper: slide down-right into mid arena!
    lda #$60
    sta ball_vyl,x
    lda #$00
    sta ball_vyh,x
    lda #$A0
    sta ball_vxl,x
    lda #$00
    sta ball_vxh,x
    rts
.up_flipl_shot
    lda pb_tmp0
    asl
    clc
    adc #$B2
    sta pb_tmp1
    jmp .flipper_cordic_launch

.jmp_chk_all_bumpers
    jmp .chk_all_bumpers

.chk_center_cards
    ; D. 4 Emerald Center Card Targets (I - G - N - T) at Y = 160..174, X = 38..102
    lda ball_yl,x
    cmp #160
    bcc .jmp_chk_all_bumpers
    cmp #174
    bcs .chk_side_specials
    lda ball_cd,x
    bne .jmp_chk_all_bumpers
    lda ball_xi,x
    cmp #38
    bcc .jmp_chk_all_bumpers
    cmp #102
    bcs .jmp_chk_all_bumpers

    ; Map X (38..101) to card index 0..3 (every 16 pixels)
    sec
    sbc #38
    lsr
    lsr
    lsr
    lsr
    tay                     ; Y = 0..3
    lda bit_mask_tbl,y
    ora pb_drops
    cmp pb_drops
    beq .jmp_chk_all_bumpers    ; That card is already knocked down!
    sta pb_drops
    ; Bounce ball vertically off the card target
    sec
    lda #0
    sbc ball_vyl,x
    sta ball_vyl,x
    lda #0
    sbc ball_vyh,x
    sta ball_vyh,x
    lda #10
    sta ball_cd,x
    lda #10                 ; +1,000 pts per card
    jsr add_score_100
    lda #SFX_TARGET
    jsr sound_play_ch1
    ldx pb_tmp3

    ; Did the player knock down all 4 Center Cards (pb_drops == $0F)?
    lda pb_drops
    cmp #$0F
    bne .jmp_chk_all_bumpers
    lda #1
    sta pb_lock_lit         ; Light the Upper-Right Multi-Ball Lock Chute!
    lda #TXT_JACKPOT        ; "LOCK LIT! SHOOT TOP"
    sta pb_banner_id
    lda #90
    sta pb_banner_tmr
    lda #SFX_LOCK
    jsr sound_play_ch1
    ldx pb_tmp3

.chk_side_specials
    ; E. Left Side Target Bank (X < 26, Y = 180..224) & Right Side Pink Spinner Gate (X > 114, Y = 180..224)
    lda ball_yl,x
    cmp #180
    bcc .chk_all_bumpers
    cmp #224
    bcs .chk_all_bumpers
    lda ball_xi,x
    cmp #26
    bcc .hit_left_bank
    cmp #114
    bcc .chk_all_bumpers
    ; Right Side Spinner Gate!
    lda ball_cd,x
    bne .chk_all_bumpers
    lda #14
    sta ball_cd,x
    lda #28
    sta pb_spinner
    lda #SFX_SPINNER
    jsr sound_play_ch0
    ldx pb_tmp3
    jmp .chk_all_bumpers

.hit_left_bank
    lda #26
    sta ball_xi,x
    lda #$A0
    sta ball_vxl,x
    lda #$01
    sta ball_vxh,x
    lda #5
    jsr add_score_100
    lda #SFX_TARGET
    jsr sound_play_ch1
    ldx pb_tmp3

.chk_all_bumpers
    ; F. 4 Neon Pop Bumpers via CORDIC:
    ;    Bumper 0: Upper Center (68, 68)
    ;    Bumpers 1..3: Lower Triangle (48, 204), (92, 204), (70, 224)
    ldy #NUM_BUMPERS-1
.bmp_loop
    sty pb_tmp2
    lda ball_yl,x
    sec
    sbc bmp_y_tbl,y
    sta M_Y+1
    ; Quick vertical range filter (+/- 14 scanlines) before CORDIC read
    bpl .dy_pos
    cmp #$F2
    bcc .jmp_bmp_next
    bcs .do_bmp_cordic
.dy_pos
    cmp #14
    bcs .jmp_bmp_next

.do_bmp_cordic
    lda #0
    sta M_X
    sta M_Y
    lda ball_xi,x
    sec
    sbc bmp_x_tbl,y
    sta M_X+1

    lda M_LEN+1
    cmp #10
    bcc .bmp_hit
.jmp_bmp_next
    jmp .bmp_next
.bmp_hit

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
    lda #10
    jsr add_score_100
    lda #SFX_BUMPER
    jsr sound_play_ch1
    ldx pb_tmp3
    rts

.bmp_next
    ldy pb_tmp2
    dey
    bmi .chk_lower_channels_top
    jmp .bmp_loop

.chk_lower_channels_top
    ; G. Upper Entry of Lower Inlane/Outlane Channels & Slingshots (Y = 232..255):
    ;    - Left Outlane (X = 17..24) walled on right by Divider Post (col 3, X = 25..31)
    ;    - Left Inlane (X = 32..39) + Left Slingshot Kicker (X = 40..48)
    ;    - Right Slingshot Kicker (X = 96..104) + Right Inlane (X = 105..112)
    ;    - Right Outlane (X = 119..123) walled on left by Divider Post (col 14, X = 113..118)
    lda ball_yl,x
    cmp #232
    bcc .upper_ret
    lda ball_xi,x
    cmp #25
    bcc .in_left_outlane_u
    cmp #32
    bcc .hit_left_div_u
    cmp #48
    bcc .hit_sling_l
    cmp #96
    bcc .upper_ret
    cmp #105
    bcc .hit_sling_r
    cmp #113
    bcc .upper_ret
    cmp #119
    bcc .hit_right_div_u
    ; In Right Outlane (X = 119..123): trap ball in right outlane channel!
    lda #121
    sta ball_xi,x
    lda #0
    sta ball_vxl,x
    sta ball_vxh,x
.upper_ret
    rts

.in_left_outlane_u
    ; In Left Outlane (X = 17..24): trap ball in left outlane channel!
    lda #20
    sta ball_xi,x
    lda #0
    sta ball_vxl,x
    sta ball_vxh,x
    rts

.hit_left_div_u
    lda #32
    sta ball_xi,x
    jsr negate_damp_vx
    rts

.hit_right_div_u
    lda #112
    sta ball_xi,x
    jsr negate_damp_vx
    rts

.hit_sling_l
    ; Only kick if in the slingshot triangle (X = 40..48); X = 32..39 is the Left Inlane!
    cmp #40
    bcc .upper_ret
    lda #49
    sta ball_xi,x
    lda #$00
    sta ball_vxl,x
    lda #$02
    sta ball_vxh,x
    jmp .sling_common

.hit_sling_r
    lda #95
    sta ball_xi,x
    lda #$00
    sta ball_vxl,x
    lda #$FE
    sta ball_vxh,x
.sling_common
    lda #$00
    sta ball_vyl,x
    lda #$FE
    sta ball_vyh,x
    lda #5
    jsr add_score_100
    lda #SFX_SLING
    jsr sound_play_ch0
    ldx pb_tmp3
    rts

; ---------------------------------------------------------------------------
; Lower Playfield: Outlanes, Inlane Funnels, Lower Flippers & V-Drain (Y >= 256)
; ---------------------------------------------------------------------------
.lower_table_checks
    lda ball_xi,x
    cmp #132
    bcc .lower_main
    rts

.lower_main
    ; 1. Outlanes vs Inlane Funnels (Y = 256..282 -> ball_yl = 0..26):
    ;    - If ball is in Left Outlane (X < 26) or Right Outlane (X >= 118),
    ;      it bypasses the inlane rails and slides down the outer V-funnel into the drain!
    lda ball_yl,x
    cmp #27
    bcs .chk_flippers

    lda ball_xi,x
    cmp #26
    bcc .outlane_left_slide
    cmp #118
    bcs .outlane_right_slide

    ; Inside the Inlanes (X = 26..117):
    ; Left Inlane Rail slopes from X=32 at Y=256 to X=48 at Y=282
    lda ball_yl,x
    lsr
    clc
    adc #33
    cmp ball_xi,x
    bcc .chk_right_inlane
    sta ball_xi,x
    lda #$A0
    sta ball_vxl,x
    lda #$00                ; Feed ball smoothly onto Lower Left Flipper!
    sta ball_vxh,x
    jmp .chk_flippers

.chk_right_inlane
    ; Right Inlane Rail slopes from X=111 at Y=256 to X=95 at Y=282
    lda ball_yl,x
    lsr
    sta pb_tmp0
    lda #110
    sec
    sbc pb_tmp0
    cmp ball_xi,x
    bcs .chk_flippers
    sta ball_xi,x
    lda #$60
    sta ball_vxl,x
    lda #$FF                ; Feed ball smoothly onto Lower Right Flipper!
    sta ball_vxh,x
    jmp .chk_flippers

.outlane_left_slide
    ; Keep ball trapped in Left Outlane (X <= 23) heading to the bottom V-drain!
    lda #21
    sta ball_xi,x
    rts

.outlane_right_slide
    ; Keep ball trapped in Right Outlane (X >= 120) heading to the bottom V-drain!
    lda #121
    sta ball_xi,x
    rts

.chk_flippers
    ; 2. Lower Left Flipper (X = 48..63) & Lower Right Flipper (X = 80..95) at Y = 280..294 (ball_yl = 24..38)
    ;    Note the 16-pixel Center Drain Gap at X = 64..79 (and Outlanes at X < 48 or X > 95)!
    lda ball_yl,x
    cmp #22
    bcc .lower_ret_1
    cmp #40
    bcc .in_flipper_y
    jmp .chk_bottom_v_drain
.in_flipper_y

    lda ball_xi,x
    cmp #47
    bcc .lower_ret_1        ; Left Outlane bypasses outside of Left Flipper!
    cmp #64
    bcc .do_left_flipper
    cmp #80
    bcc .lower_ret_1        ; Center Drain Gap (X = 64..79)!
    cmp #97
    bcc .do_right_flipper
.lower_ret_1
    rts

.do_left_flipper
    ; Distance d from Lower Left Flipper pivot at X=48 (0..16)
    sec
    sbc #47
    sta pb_tmp0             ; d = 0..16

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
    sta pb_tmp1
    lda ball_yl,x
    clc
    adc #4
    cmp pb_tmp1
    bcc .lower_ret_1

    lda pb_tmp1
    sec
    sbc #4
    sta ball_yl,x

    lda pb_flipl_vel
    bne .flipl_power_shot
    lda ball_vyh,x
    bmi .lower_ret_1
    ; If flipper is HELD UP (pb_flipl == 2), cradle the ball;
    ; if flipper is RESTING DOWN (pb_flipl == 0), let gravity roll the ball down into the center drain!
    lda pb_flipl
    cmp #2
    beq .flipl_cradle
    lda #$90
    sta ball_vxl,x
    lda #$00                ; Roll down-right toward X=64 center drain gap!
    sta ball_vxh,x
    lda #$60
    sta ball_vyl,x
    lda #$00                ; Downward VY so resting flipper never bounces ball up forever!
    sta ball_vyh,x
    rts
.flipl_cradle
    lda #$00
    sta ball_vxl,x
    sta ball_vxh,x
    sta ball_vyl,x
    sta ball_vyh,x
    rts

.flipl_power_shot
    ; CORDIC Power Shot from Lower Left Flipper (d = 0..16 -> angle $B4..$E4)
    lda pb_tmp0
    asl
    clc
    adc #$B4
    sta pb_tmp1
    jmp .flipper_cordic_launch

.do_right_flipper
    ; Distance d from Lower Right Flipper pivot at X=96 (0..16)
    lda #96
    sec
    sbc ball_xi,x
    sta pb_tmp0             ; d = 0..16

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

    lda pb_tmp1
    sec
    sbc #4
    sta ball_yl,x

    lda pb_flipr_vel
    bne .flipr_power_shot
    lda ball_vyh,x
    bmi .lower_ret_2
    lda pb_flipr
    cmp #2
    beq .flipr_cradle
    lda #$70
    sta ball_vxl,x
    lda #$FF                ; Roll down-left toward X=79 center drain gap!
    sta ball_vxh,x
    lda #$60
    sta ball_vyl,x
    lda #$00                ; Downward VY into center drain!
    sta ball_vyh,x
.lower_ret_2
    rts
.flipr_cradle
    lda #$00
    sta ball_vxl,x
    sta ball_vxh,x
    sta ball_vyl,x
    sta ball_vyh,x
    rts

.flipr_power_shot
    ; CORDIC Power Shot from Lower Right Flipper (d = 0..16 -> angle $CC..$9C)
    lda pb_tmp0
    asl
    sta pb_tmp1
    lda #$CC
    sec
    sbc pb_tmp1
    sta pb_tmp1

.flipper_cordic_launch
    ; Rotate launch velocity ($03C0 = 3.75 px/frame) by shot angle pb_tmp1 via CORDIC!
    lda #$C0
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
    lda #1
    jsr add_score_100
    ldx pb_tmp3
    rts

.chk_bottom_v_drain
    ; 3. Bottom V-Funnel Drain Ramp (Y = 296..316 -> ball_yl = 40..60):
    ;    Any ball that falls below Y=296 (either through the center gap X=64..79
    ;    or down the Left/Right Outlanes) slides down the V-apron into the drain hole!
    lda ball_yl,x
    cmp #56
    bcs .ball_drained_now
    lda ball_xi,x
    cmp #68
    bcc .slide_v_right
    cmp #76
    bcc .keep_falling
    lda #$00
    sta ball_vxl,x
    lda #$FF
    sta ball_vxh,x
    rts
.slide_v_right
    lda #$00
    sta ball_vxl,x
    lda #$01
    sta ball_vxh,x
.keep_falling
    rts

.ball_drained_now
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
; advance_multiball_lock: Called when player shoots the LIT Upper-Right Lock Chute!
;   Requires clearing all 4 Center Cards before EACH lock; 2nd lock starts Multi-Ball!
; ---------------------------------------------------------------------------
advance_multiball_lock
    lda #0
    sta pb_lock_lit         ; Consume Lock Lit state
    sta pb_drops            ; Reset all 4 Center Cards so player must clear them again!
    inc pb_locks
    lda pb_locks
    cmp #1
    bne .trigger_multiball
    lda #50                 ; +5,000 pts for Lock 1!
    jsr add_score_100
    lda #TXT_LOCK1
    sta pb_banner_id
    lda #85
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
    lda #SFX_MULTIBALL
    jsr sound_play_ch1

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

mb_spawn_x      .byte 72, 56, 88
mb_spawn_y      .byte 140, 84, 84
mb_spawn_vxh    .byte 0, $FE, $02
mb_spawn_vyh    .byte 0, $01, $01

; 4 Pop Bumpers: 0 = Upper (68, 68); 1..3 = Lower Triangle (48, 204), (92, 204), (70, 224)
bmp_x_tbl       .byte 68, 48, 92, 70
bmp_y_tbl       .byte 68, 204, 204, 224

; ===========================================================================
; pinball_draw: Plot all scrolling playfield sprites & DMD banners
; ===========================================================================
pinball_draw
    ; 1. Draw 4 Neon Pop Bumpers
    ldx #NUM_BUMPERS-1
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

    ; 2. Draw 3 Top Rollover Lane Gems (Y = 38, X = 42, 66, 90)
    ldx #2
.draw_roll_loop
    stx pb_tmp3
    lda #IMG_GEM
    sta pimg
    lda #1                  ; Small gem frame
    sta pframe
    lda pb_rollovers
    and bit_mask_tbl,x
    beq .roll_unlit
    lda #1                  ; Lit Gold
    bne .roll_pal_set
.roll_unlit
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

    ; 3. Draw 4 Center Emerald Card Targets (Y = 164, X = 40, 56, 72, 88)
    ldx #3
.draw_card_loop
    stx pb_tmp3
    lda #IMG_GEM
    sta pimg
    lda pb_drops
    and bit_mask_tbl,x
    beq .card_up
    lda #1                  ; Hit/Lit indicator
    sta pframe
    lda #1
    bne .card_draw
.card_up
    lda #0                  ; Full green card target
    sta pframe
    lda #5
.card_draw
    sta ppal
    lda card_x_tbl,x
    sta px
    lda #164
    ldy #0
    jsr draw_world_sprite
    ldx pb_tmp3
    dex
    bpl .draw_card_loop

    ; 4. Draw Upper-Right Lock Chute Indicator at (108, 60) & Right Spinner at (118, 198)
    lda #IMG_GEM
    sta pimg
    lda #1
    sta pframe
    lda #5
    ldy pb_lock_lit
    beq .lock_ind_pal
    lda pb_frame
    lsr
    lsr
    and #1
    clc
    adc #1                  ; Flash Gold/Red when Lock is LIT!
.lock_ind_pal
    sta ppal
    lda #108
    sta px
    lda #60
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
    lda #118
    sta px
    lda #198
    ldy #0
    jsr draw_world_sprite

    ; 5. Draw Upper Flippers (Left at X=40, Y=128; Right at X=88, Y=128)
    lda #IMG_FLIPL
    sta pimg
    lda pb_flipl
    sta pframe
    lda #3                  ; Electric Cyan Upper Flippers (like NES Pinball!)
    sta ppal
    lda #40
    sta px
    lda #128
    ldy #0
    jsr draw_world_sprite

    lda #IMG_FLIPR
    sta pimg
    lda pb_flipr
    sta pframe
    lda #3
    sta ppal
    lda #88
    sta px
    lda #128
    ldy #0
    jsr draw_world_sprite

    ; 6. Draw Lower Flippers (Left at X=48, Y=282; Right at X=80, Y=282 — flush with cols 5 & 12!)
    lda #IMG_FLIPL
    sta pimg
    lda pb_flipl
    sta pframe
    lda #1                  ; Gold Lower Flippers
    sta ppal
    lda #48
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
    lda #80
    sta px
    lda #<282
    ldy #>282
    jsr draw_world_sprite

    ; 7. Draw Spring Plunger at (136, 288)
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

    ; 8. Draw all active Chrome Steel Pinballs (0..2)
    ldx #0
.draw_ball_loop
    stx pb_tmp3
    lda ball_act,x
    beq .draw_ball_next
    lda #IMG_BALL
    sta pimg
    lda #0
    sta pframe
    lda #7
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

    ; 9. Draw Playfield Callout Banner / Title Overlay via pf_text
    lda pb_state
    bne .chk_game_banner
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
; ---------------------------------------------------------------------------
draw_world_sprite
    sec
    sbc cam_y
    sta pb_tmp0
    tya
    sbc #0
    bmi .dws_above
    bne .dws_out
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
    cmp #241
    bcc .dws_out
    clc
    adc #32
    sta py
    jmp pf_drawimg
.dws_out
    rts

bit_mask_tbl    .byte 1, 2, 4, 8
roll_x_tbl      .byte 42, 66, 90
card_x_tbl      .byte 40, 56, 72, 88
