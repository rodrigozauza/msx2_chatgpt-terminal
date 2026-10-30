; EDITOR.ASM -- bounded insert/delete editor, 2047 data bytes plus NUL.
; Newlines are LF internally. Display wraps at exactly 80 cells.
editor_insert:
    ld (insert_value),a
    ld hl,(editor_length)
    ld de,EDITOR_MAX
    or a
    sbc hl,de
    jp nc,editor_full
    ld hl,(editor_length)
    ld de,(editor_cursor)
    or a
    sbc hl,de
    inc hl
    ld b,h
    ld c,l
    ld hl,(editor_length)
    ld de,EDITOR
    add hl,de
    ld d,h
    ld e,l
    inc de
    lddr
    ld hl,(editor_cursor)
    ld de,EDITOR
    add hl,de
    ld a,(insert_value)
    ld (hl),a
    ld hl,(editor_length)
    inc hl
    ld (editor_length),hl
    ld hl,(editor_cursor)
    inc hl
    ld (editor_cursor),hl
    xor a
    ld (buffer_full),a
    jp editor_update
editor_full:
    ld a,1
    ld (buffer_full),a
    jp editor_update
editor_backspace:
    ld hl,(editor_cursor)
    ld a,h
    or l
    ret z
    dec hl
    ld (editor_cursor),hl
    jp editor_delete
editor_delete:
    ld hl,(editor_length)
    ld de,(editor_cursor)
    or a
    sbc hl,de
    ld a,h
    or l
    ret z
    ld b,h
    ld c,l
    push bc
    ld hl,(editor_cursor)
    ld de,EDITOR
    add hl,de
    ld d,h
    ld e,l
    inc hl
    pop bc
    ldir
    ld hl,(editor_length)
    dec hl
    ld (editor_length),hl
    xor a
    ld (buffer_full),a
    jp editor_update
editor_clear:
    xor a
    ld (EDITOR),a
    ld (buffer_full),a
    ld hl,0
    ld (editor_length),hl
    ld (editor_cursor),hl
    ld (view_top),hl
    jp editor_update
editor_left:
    ld hl,(editor_cursor)
    ld a,h
    or l
    ret z
    dec hl
    ld (editor_cursor),hl
    jp editor_update
editor_right:
    ld hl,(editor_length)
    ld de,(editor_cursor)
    or a
    sbc hl,de
    ret z
    inc de
    ld (editor_cursor),de
    jp editor_update
editor_home:
    ld hl,(editor_cursor)
    ld de,EDITOR
    add hl,de
editor_home_loop:
    ld de,EDITOR
    or a
    sbc hl,de
    add hl,de
    jp z,editor_home_done
    dec hl
    ld a,(hl)
    cp 10
    jp nz,editor_home_loop
    inc hl
editor_home_done:
    ld de,EDITOR
    or a
    sbc hl,de
    ld (editor_cursor),hl
    jp editor_update
editor_end:
    ld hl,(editor_cursor)
    ld de,EDITOR
    add hl,de
editor_end_loop:
    ld a,(hl)
    or a
    jp z,editor_end_done
    cp 10
    jp z,editor_end_done
    inc hl
    jp editor_end_loop
editor_end_done:
    ld de,EDITOR
    or a
    sbc hl,de
    ld (editor_cursor),hl
    jp editor_update
editor_up:
    call get_cursor_layout
    ld hl,(cursor_row)
    ld a,h
    or l
    ret z
    dec hl
    ld (target_row),hl
    jp editor_vertical
editor_down:
    call get_cursor_layout
    ld hl,(cursor_row)
    inc hl
    ld (target_row),hl
editor_vertical:
    ld a,(cursor_col)
    ld (target_col),a
    call find_visual_position
    jp editor_update

layout_reset:
    push hl
    ld hl,0
    ld (layout_row),hl
    xor a
    ld (layout_col),a
    ld (layout_wrapped),a
    pop hl
    ret
; Advances one byte, preserving BC/DE/HL. A,flags destroyed.
advance_layout:
    cp 10
    jp z,layout_explicit_newline
    xor a
    ld (layout_wrapped),a
    ld a,(layout_col)
    inc a
    cp COLUMNS
    jp z,layout_wrap
    ld (layout_col),a
    ret
layout_explicit_newline:
    ld a,(layout_wrapped)
    or a
    jp z,layout_newline
    xor a
    ld (layout_wrapped),a
    ret
layout_wrap:
    ld a,1
    ld (layout_wrapped),a
layout_newline:
    xor a
    ld (layout_col),a
    push hl
    ld hl,(layout_row)
    inc hl
    ld (layout_row),hl
    pop hl
    ret
get_cursor_layout:
    call layout_reset
    ld hl,EDITOR
    ld bc,(editor_cursor)
cursor_layout_loop:
    ld a,b
    or c
    jp z,cursor_layout_done
    ld a,(hl)
    call advance_layout
    inc hl
    dec bc
    jp cursor_layout_loop
cursor_layout_done:
    ld hl,(layout_row)
    ld (cursor_row),hl
    ld a,(layout_col)
    ld (cursor_col),a
    ret

; Search all valid cursor positions and clamp to the target visual row/column.
find_visual_position:
    ld hl,(editor_cursor)
    ld (best_position),hl
    call layout_reset
    ld bc,0
    ld hl,EDITOR
find_visual_loop:
    push hl
    ld hl,(layout_row)
    ld de,(target_row)
    or a
    sbc hl,de
    pop hl
    jp c,find_visual_next
    jp nz,find_visual_done
    ld a,(target_col)
    ld e,a
    ld a,(layout_col)
    cp e
    jp c,find_visual_accept
    jp nz,find_visual_done
find_visual_accept:
    ld (best_position),bc
find_visual_next:
    ld de,(editor_length)
    ld a,b
    cp d
    jp nz,find_visual_advance
    ld a,c
    cp e
    jp z,find_visual_done
find_visual_advance:
    ld a,(hl)
    call advance_layout
    inc hl
    inc bc
    jp find_visual_loop
find_visual_done:
    ld hl,(best_position)
    ld (editor_cursor),hl
    ret

editor_update:
    call mark_cursor_row
    ld hl,INPUT_BASE
    ld de,INPUT_OLD
    ld bc,INPUT_ROWS*GRID_STRIDE
    ldir
    call get_cursor_layout
    ld hl,(cursor_row)
    ld de,(view_top)
    or a
    sbc hl,de
    jp nc,view_check_bottom
    ld hl,(cursor_row)
    ld (view_top),hl
    jp view_ready
view_check_bottom:
    ld de,INPUT_ROWS
    or a
    sbc hl,de
    jp c,view_ready
    ld hl,(cursor_row)
    ld de,INPUT_ROWS-1
    or a
    sbc hl,de
    ld (view_top),hl
view_ready:
    ld hl,(cursor_row)
    ld de,(view_top)
    or a
    sbc hl,de
    ld a,l
    add a,INPUT_ROW
    ld (cursor_screen_row),a
    ld a,1
    ld (cursor_phase),a
    ld hl,(JIFFY)
    ld (blink_tick),hl
    ld hl,INPUT_BASE
    ld bc,INPUT_ROWS*GRID_STRIDE
    ld a,32
    call fill_memory
    call layout_reset
    ld hl,EDITOR
    ld bc,(editor_length)
editor_draw_loop:
    ld a,b
    or c
    jp z,editor_draw_done
    ld a,(hl)
    ld (draw_value),a
    cp 10
    jp z,editor_draw_advance
    push hl
    push bc
    call editor_place_visible
    pop bc
    pop hl
editor_draw_advance:
    ld a,(draw_value)
    call advance_layout
    inc hl
    dec bc
    jp editor_draw_loop
editor_draw_done:
    call mark_cursor_row
    ld hl,INPUT_BASE
    ld de,INPUT_OLD
    ld c,INPUT_ROW
editor_compare_row:
    xor a
    ld (input_row_changed),a
    ld b,GRID_STRIDE
editor_compare_cell:
    ld a,(de)
    cp (hl)
    jp z,editor_compare_next
    ld a,1
    ld (input_row_changed),a
editor_compare_next:
    inc hl
    inc de
    djnz editor_compare_cell
    ld a,(input_row_changed)
    or a
    ld a,c
    call nz,mark_pattern_row
    inc c
    ld a,c
    cp INPUT_ROW+INPUT_ROWS
    jp nz,editor_compare_row
    jp draw_status
editor_place_visible:
    ld hl,(layout_row)
    ld de,(view_top)
    or a
    sbc hl,de
    ret c
    ld a,h
    or a
    ret nz
    ld a,l
    cp INPUT_ROWS
    ret nc
    call grid_row_offset
    ld de,INPUT_BASE
    add hl,de
    ld a,(layout_col)
    ld e,a
    ld d,0
    add hl,de
    ld a,(draw_value)
    ld (hl),a
    ret

draw_status:
    ld a,STATUS_ROW
    ld hl,status_template
    call put_line
    ld hl,GRID+STATUS_ROW*GRID_STRIDE+2
    ld de,(editor_length)
    call hex_at
    ld hl,GRID+STATUS_ROW*GRID_STRIDE+9
    ld de,(editor_cursor)
    call hex_at
    ld hl,GRID+STATUS_ROW*GRID_STRIDE+16
    ld de,(cursor_row)
    call hex_at
    ld hl,GRID+STATUS_ROW*GRID_STRIDE+23
    ld a,(cursor_col)
    call hex_byte_at
    ld a,(buffer_full)
    or a
    ld a,&71
    jp z,status_color
    ld a,&81
status_color:
    ld (ROWCOLORS+STATUS_ROW),a
    ret
hex_at:
    push de
    ld a,d
    call hex_byte_at
    pop de
    ld a,e
    jp hex_byte_at
hex_byte_at:
    push af
    rrca
    rrca
    rrca
    rrca
    call nibble_at
    pop af
nibble_at:
    and 15
    add a,48
    cp 58
    jp c,nibble_store
    add a,7
nibble_store:
    ld (hl),a
    inc hl
    ret

editor_length: dw 0
editor_cursor: dw 0
cursor_row: dw 0
view_top: dw 0
layout_row: dw 0
layout_col: db 0
layout_wrapped: db 0
target_row: dw 0
target_col: db 0
best_position: dw 0
insert_value: db 0
draw_value: db 0
buffer_full: db 0
input_row_changed: db 0
status_template: dm "T=0000 P=0000 L=0000 C=00"
    db 0
