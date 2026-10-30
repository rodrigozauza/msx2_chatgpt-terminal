; Keyboard codes: ASCII MSX BIOS CHSNS/CHGET and MSX control codes.
keyboard_poll:
    ld ix,&009C
    call bios_call
    jp z,keyboard_empty
    ld ix,&009F
    call bios_call
    ret
keyboard_empty:
    xor a
    ret
cursor_tick:
    ld hl,(JIFFY)
    ld de,(blink_tick)
    or a
    sbc hl,de
    ld de,30
    or a
    sbc hl,de
    ret c
    ld hl,(JIFFY)
    ld (blink_tick),hl
    ld a,(cursor_phase)
    xor 1
    ld (cursor_phase),a
    jp mark_cursor_row
blink_tick: dw 0
cursor_phase: db 1
cursor_col: db 0
cursor_screen_row: db INPUT_ROW
