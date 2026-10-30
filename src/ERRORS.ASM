error_msx2:
    ld hl,msg_msx2
    jp error_console
error_vram128:
    ld hl,msg_vram128
    jp error_console
error_ram:
    ld hl,msg_ram
    jp error_console
error_stack:
    ld hl,msg_stack
    jp error_console
error_mode:
    ld hl,msg_mode
    jp error_console
error_console:
    ld a,(hl)
    or a
    jp z,error_exit
    push hl
    ld e,a
    ld c,6
    call BDOS
    pop hl
    inc hl
    jp error_console
error_exit:
    ld sp,(initial_sp)
    jp 0
msg_ram: dm "MSXCHAT: TPA must extend to C100h (RAM buffers end at C000h)."
    db 13,10,0
msg_stack: dm "MSXCHAT: DOS stack must be in page 3, SP >= C100h."
    db 13,10,0
msg_mode: dm "MSXCHAT: start from video mode 0..3."
    db 13,10,0

msg_msx2: dm "MSXCHAT: MSX2 or newer required."
    db 13,10,0
msg_vram128: dm "MSXCHAT: SCREEN 7 requires 128K VRAM."
    db 13,10,0
