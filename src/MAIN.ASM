; MSXCHAT.COM -- MSX2 SCREEN 7 adaptation of Phase 6 gateway terminal.
; SPDX-License-Identifier: MIT
    org &0100
    jp main
    include "CONFIG.ASM"
main:
    ld (initial_sp),sp
    ld hl,(BDOS+1)
    ld de,RAM_END+256
    or a
    sbc hl,de
    jp c,error_ram
    ld hl,0
    add hl,sp
    ld a,h
    cp &C1
    jp c,error_stack
    ; Read BIOS generation via RDSLT; page 0 is DOS RAM here.
    ld a,(EXPTBL)
    ld hl,&002D
    call &000C
    ei
    or a
    jp z,error_msx2
    ; MODE bits 2:1: 00=16KB, 01=64KB, 10=128KB.
    ; Ignore other MODE flags; also retain acceptance of encoding 11.
    ; MSX2 Technical Handbook chapter 2, table 2.22 (appendix 4 has a typo).
    ld a,(&FAFC)
    and 6
    cp 4
    jp c,error_vram128
    ld a,(SCRMOD)
    cp 4
    jp nc,error_mode
    ; R#1 bit 7 is reserved on V9938/V9958, not a VRAM-size flag.
    ; MSX generation and MODE above determine SCREEN 7 eligibility.
    ; All mutable data live in owned TPA or documented BIOS video state.
    ld hl,GRID
    ld bc,TEXT_ROWS*GRID_STRIDE
    ld a,32
    call fill_memory
    ld hl,EDITOR
    ld bc,2048
    xor a
    call fill_memory
    ld hl,ROWCOLORS
    ld bc,TEXT_ROWS
    ld a,&F1
    call fill_memory
    ld a,&F4
    ld (ROWCOLORS),a
    ld a,&B1
    ld (ROWCOLORS+FOOTER_ROW),a
    call net_configure
    call storage_boot
    call ui_initial
    call storage_show_boot
    call net_show_config
    call editor_update
    call mark_all
    call screen_enter
    ld hl,(JIFFY)
    ld (blink_tick),hl
main_loop:
    call keyboard_poll
    or a
    jp z,main_idle
    call handle_key
    call render_dirty
    jp main_loop
main_idle:
    call cursor_tick
    call storage_auto_poll
    call render_dirty
    jp main_loop
exit_normal:
    call screen_leave
    call net_exit_cleanup
    ld sp,(initial_sp)
    jp 0

handle_key:
    ld b,a
    ld a,(history_active)
    or a
    ld a,b
    jp nz,history_key
    cp 24
    jp z,command_cancel
    ld b,a
    xor a
    ld (cancel_armed),a
    ld a,b
    cp 27
    jp z,exit_normal
    cp 25
    jp z,history_open
    cp 23
    jp z,command_network
    cp 19
    jp z,command_save
    cp 17
    jp z,command_submit
    cp 15
    jp z,command_response
    cp 4
    jp z,command_load
    cp 2
    jp z,command_review
    cp 20
    jp z,command_auto
    cp 7
    jp z,help_toggle
    cp 18
    jp z,calibration_toggle
    cp 16
    jp z,preview_local
    cp 12
    jp z,editor_clear
    cp 8
    jp z,editor_backspace
    cp 127
    jp z,editor_delete
    cp 28
    jp z,editor_right
    cp 29
    jp z,editor_left
    cp 30
    jp z,editor_up
    cp 31
    jp z,editor_down
    cp 11
    jp z,editor_home
    cp 1
    jp z,editor_home
    cp 5
    jp z,editor_end
    cp 13
    jp z,editor_enter
    cp 32
    ret c
    jp editor_insert
editor_enter:
    ld a,10
    jp editor_insert

initial_sp: dw 0
    include "SCREEN7.ASM"
    include "TERMINAL.ASM"
    include "EDITOR.ASM"
    include "KEYBOARD.ASM"
    include "ERRORS.ASM"
    include "DOSIO.ASM"
    include "JSON.ASM"
    include "UNICODE.ASM"
    include "HISTORY.ASM"
    include "BROWSER.ASM"
    include "CANCEL.ASM"
    include "NETCONFIG.ASM"
    include "UNAPI.ASM"
    include "NETWORK.ASM"
    include "HTTP.ASM"
    include "FONT8X8.ASM"
program_end:
    assert program_end < &4000
