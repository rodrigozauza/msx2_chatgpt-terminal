; EDITOR.ASM -- bounded insert/delete editor, 2047 data bytes plus NUL.
; Newlines are LF internally. Display wraps at exactly 80 cells.
editor_insert:
    ld (insert_value),a
    xor a
    ld (shift_left),a
    ld hl,(editor_length)
    ld de,(editor_cursor)
    or a
    sbc hl,de
    ld a,0
    jr nz,editor_append_tested
    inc a
editor_append_tested:
    ld (append_mode),a
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
    ; Reflow only from the insertion point to the bottom of the viewport.
    ; The already-known cursor layout avoids scanning the preceding 2KB.
    call mark_cursor_row
    ld hl,(cursor_row)
    ld (layout_row),hl
    ld a,(cursor_col)
    ld (layout_col),a
    ld a,(cursor_wrapped)
    ld (layout_wrapped),a
    ld hl,(editor_cursor)
    dec hl
    ld de,EDITOR
    add hl,de
    ld (fast_source),hl
    ld a,(insert_value)
    cp 10
    jr nz,editor_fast_regular
    ld a,(cursor_wrapped)
    or a
    jr z,editor_fast_newline
    xor a
    ld (cursor_wrapped),a
    jr editor_fast_reflow
editor_fast_regular:
    ld a,(cursor_col)
    inc a
    cp COLUMNS
    jr c,editor_fast_column
    ld a,1
    ld (cursor_wrapped),a
    jr editor_fast_wrap
editor_fast_newline:
    xor a
    ld (cursor_wrapped),a
editor_fast_wrap:
    xor a
    ld (cursor_col),a
    ld hl,(cursor_row)
    inc hl
    ld (cursor_row),hl
    ld a,(cursor_screen_row)
    cp INPUT_ROW+INPUT_ROWS-1
    jr c,editor_fast_next_row
    ld hl,(view_top)
    inc hl
    ld (view_top),hl
    call vdp_scroll_editor
    jr editor_fast_reflow
editor_fast_next_row:
    inc a
    ld (cursor_screen_row),a
    jr editor_fast_reflow
editor_fast_column:
    ld (cursor_col),a
    xor a
    ld (cursor_wrapped),a
editor_fast_reflow:
    ld a,(append_mode)
    or a
    jp nz,editor_append_draw
    ld hl,(layout_row)
    ld de,(view_top)
    or a
    sbc hl,de
    ld a,l
    add a,INPUT_ROW
    ld (fast_start_row),a
    call grid_row_address
    ld a,(layout_col)
    ld (fast_start_col),a
    ld e,a
    ld d,0
    add hl,de
    push hl
    ld de,INPUT_BASE+INPUT_ROWS*GRID_STRIDE
    ex de,hl
    or a
    sbc hl,de
    ld b,h
    ld c,l
    pop hl
    ld a,32
    call fill_memory
    ld hl,(fast_source)
editor_fast_draw:
    ld a,(hl)
    or a
    jr z,editor_fast_done
    ld (draw_value),a
    push hl
    cp 10
    call nz,editor_place_visible
    ld a,(draw_value)
    call advance_layout
    ld hl,(layout_row)
    ld de,(view_top)
    or a
    sbc hl,de
    ld a,l
    cp INPUT_ROWS
    pop hl
    jr nc,editor_fast_done
    inc hl
    jr editor_fast_draw
editor_fast_done:
    ld a,(insert_value)
    cp 10
    call nz,vdp_shift_editor
    ld a,INPUT_ROW
    call mark_pattern_row
    inc a
    call mark_pattern_row
    inc a
    call mark_pattern_row
    ld a,1
    ld (cursor_phase),a
    ld hl,(JIFFY)
    ld (blink_tick),hl
    call mark_cursor_row
    jp draw_status
editor_full:
    ld a,1
    ld (buffer_full),a
    jp draw_status
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
    jp editor_delete_redraw
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
    jp editor_move_update
editor_right:
    ld hl,(editor_length)
    ld de,(editor_cursor)
    or a
    sbc hl,de
    ret z
    inc de
    ld (editor_cursor),de
    jp editor_move_update
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
    ld hl,(cursor_row)
    ld a,h
    or l
    ret z
    dec hl
    ld (target_row),hl
    jp editor_vertical
editor_down:
    ld hl,(cursor_row)
    inc hl
    ld (target_row),hl
editor_vertical:
    ld a,(cursor_col)
    ld (target_col),a
    call find_visual_position
    jp editor_move_update

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
    ld hl,0
    ld (cursor_row),hl
    ld hl,EDITOR
    ld bc,(editor_cursor)
layout_scan_segment:
    ld a,b
    or c
    jr z,layout_scan_empty
    ld (scan_remaining),bc
    ld a,10
    cpir
    ld (scan_pointer),hl
    ld a,0
    jr nz,layout_scan_no_lf
    inc a
layout_scan_no_lf:
    ld (scan_lf),a
    ld hl,(scan_remaining)
    or a
    sbc hl,bc
    or a
    jr z,layout_scan_divide
    dec hl
layout_scan_divide:
    ld a,h
    or l
    ld (scan_nonempty),a
    ld de,COLUMNS
layout_scan_quotient:
    or a
    sbc hl,de
    jr c,layout_scan_remainder
    push hl
    ld hl,(cursor_row)
    inc hl
    ld (cursor_row),hl
    pop hl
    jr layout_scan_quotient
layout_scan_remainder:
    add hl,de
    ld a,(scan_lf)
    or a
    jr z,layout_scan_last
    ld a,l
    or a
    jr nz,layout_scan_row_end
    ld a,(scan_nonempty)
    or a
    jr nz,layout_scan_continue
layout_scan_row_end:
    ld hl,(cursor_row)
    inc hl
    ld (cursor_row),hl
layout_scan_continue:
    ld hl,(scan_pointer)
    jp layout_scan_segment
layout_scan_empty:
    ld l,0
    xor a
    ld (scan_nonempty),a
layout_scan_last:
    ld a,l
    ld (cursor_col),a
    ld (layout_col),a
    or a
    ld a,0
    jr nz,layout_scan_store
    ld a,(scan_nonempty)
    or a
    ld a,0
    jr z,layout_scan_store
    inc a
layout_scan_store:
    ld (cursor_wrapped),a
    ld (layout_wrapped),a
    ld hl,(cursor_row)
    ld (layout_row),hl
    ret

; Search all valid cursor positions and clamp to the target visual row/column.
find_visual_position:
    ld hl,(view_top)
    push hl
    ld hl,(target_row)
    ld (view_top),hl
    call find_view_start
    pop de
    ld (view_top),de
    ld de,(skip_rows)
    ld a,d
    or e
    ret nz
    ld a,(target_col)
    ld b,a
    or a
    jr z,find_visual_accept
find_visual_column:
    ld a,(hl)
    or a
    jr z,find_visual_accept
    cp 10
    jr z,find_visual_accept
    inc hl
    djnz find_visual_column
find_visual_accept:
    ld de,EDITOR
    or a
    sbc hl,de
    ld (editor_cursor),hl
    ret
editor_move_update:
    call mark_cursor_row
    call get_cursor_layout
    ld hl,(cursor_row)
    ld de,(view_top)
    or a
    sbc hl,de
    jp c,editor_update
    ld a,h
    or a
    jp nz,editor_update
    ld a,l
    cp INPUT_ROWS
    jp nc,editor_update
    add a,INPUT_ROW
    ld (cursor_screen_row),a
    jp editor_cursor_ready
editor_delete_redraw:
    xor a
    ld (append_mode),a
    call mark_cursor_row
    call get_cursor_layout
    ld hl,(cursor_row)
    ld de,(view_top)
    or a
    sbc hl,de
    jp c,editor_update
    ld a,h
    or a
    jp nz,editor_update
    ld a,l
    cp INPUT_ROWS
    jp nc,editor_update
    add a,INPUT_ROW
    ld (cursor_screen_row),a
    ld hl,(editor_cursor)
    ld de,EDITOR
    add hl,de
    ld (fast_source),hl
    ld a,1
    ld (shift_left),a
    ld a,255
    ld (insert_value),a
    jp editor_fast_reflow
editor_cursor_ready:
    ld a,1
    ld (cursor_phase),a
    ld hl,(JIFFY)
    ld (blink_tick),hl
    call mark_cursor_row
    jp draw_status

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
    call find_view_start
editor_draw_loop:
    push hl
    ld hl,(layout_row)
    ld de,(view_top)
    or a
    sbc hl,de
    ld a,l
    cp INPUT_ROWS
    pop hl
    jp nc,editor_draw_done
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
    call mark_pattern_row
    call put_line_unmarked
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

append_mode: db 0

fast_source: dw 0

cursor_wrapped: db 0

fast_start_row: db INPUT_ROW
fast_start_col: db 0

; Find the viewport by scanning at most 80 bytes per visual row with CPIR.
find_view_start:
    ld hl,(view_top)
    ld (skip_rows),hl
    ld (layout_row),hl
    xor a
    ld (layout_col),a
    ld (layout_wrapped),a
    ld hl,(editor_length)
    ld (skip_remaining),hl
    ld hl,EDITOR
find_view_row:
    ld de,(skip_rows)
    ld a,d
    or e
    jr z,find_view_done
    ld bc,(skip_remaining)
    ld a,b
    or c
    jr z,find_view_done
    ld a,b
    or a
    jr nz,find_view_80
    ld a,c
    cp COLUMNS
    jr c,find_view_count
find_view_80:
    ld bc,COLUMNS
find_view_count:
    ld (scan_remaining),bc
    ld a,10
    cpir
    push af
    push hl
    ld hl,(scan_remaining)
    or a
    sbc hl,bc
    ld d,h
    ld e,l
    ld hl,(skip_remaining)
    or a
    sbc hl,de
    ld (skip_remaining),hl
    pop hl
    pop af
    jr z,find_view_consumed
    ld a,(hl)
    cp 10
    jr nz,find_view_consumed
    inc hl
    ld de,(skip_remaining)
    dec de
    ld (skip_remaining),de
find_view_consumed:
    ld de,(skip_rows)
    dec de
    ld (skip_rows),de
    jr find_view_row
find_view_done:
    ld bc,(skip_remaining)
    ret
scan_remaining: dw 0
scan_pointer: dw 0
scan_lf: db 0
scan_nonempty: db 0
skip_rows: dw 0
skip_remaining: dw 0

shift_left: db 0

editor_append_draw:
    ld hl,(layout_row)
    ld de,(view_top)
    or a
    sbc hl,de
    ld a,l
    add a,INPUT_ROW
    call mark_pattern_row
    ld a,(insert_value)
    cp 10
    jp z,editor_cursor_ready
    ld (draw_value),a
    call editor_place_visible
    jp editor_cursor_ready
